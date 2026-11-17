// sf_bridge.cpp — jembatan C++ antara Stockfish (program stdin/stdout)
// dan Dart FFI (fungsi sf_init/sf_cmd/sf_read/sf_quit).
//
// Strategi:
//  - Ganti std::cin/std::cout Stockfish dengan dua pipe POSIX.
//  - Jalankan main() Stockfish di thread terpisah.
//  - sf_cmd menulis perintah ke pipe input.
//  - Thread pembaca menyerap pipe output ke buffer string yang dilindungi mutex.
//  - sf_read mengambil satu baris dari buffer.
//
// Kontrak C (dilihat dari Dart):
//   int  sf_init(const char* nnue_path);
//   int  sf_cmd(const char* cmd);
//   int  sf_read(char* buf, int maxlen);
//   SF_EXPORT SF_EXPORT void sf_quit();

#include <cstdio>
#include <cstring>
#include <string>
#include <mutex>
#include <thread>
#include <atomic>
#include <unistd.h>
#include <fcntl.h>
#include <pthread.h>

// Stockfish mengekspos main() di main.cpp. Kita deklarasikan dan panggil.
// Nama simbol disesuaikan lewat CMake (-Dstockfish_main=...).
extern int stockfish_main(int argc, char** argv);


#define SF_EXPORT __attribute__((visibility("default")))

namespace {

int g_in_pipe[2] = {-1, -1};   // Dart -> Stockfish
int g_out_pipe[2] = {-1, -1};  // Stockfish -> pembaca

std::thread g_thread;
std::atomic<bool> g_running{false};
std::atomic<bool> g_stop_reader{false};

std::mutex g_buf_mu;
std::string g_buf;              // akumulasi output mentah
std::mutex g_out_mu;            // serialisasi tulis ke out_pipe

void reader_loop() {
  char tmp[4096];
  while (!g_stop_reader.load()) {
    ssize_t n = read(g_out_pipe[0], tmp, sizeof(tmp));
    if (n <= 0) {
      if (n < 0 && (errno == EINTR || errno == EAGAIN)) continue;
      break;
    }
    std::lock_guard<std::mutex> lk(g_buf_mu);
    g_buf.append(tmp, (size_t)n);
    // Batasi buffer agar tidak tumbuh tanpa batas bila Dart tidak membaca.
    const size_t kMax = 1 << 20;
    if (g_buf.size() > kMax) {
      g_buf.erase(0, g_buf.size() - kMax);
    }
  }
}

void engine_thread() {
  // Arahkan stdio Stockfish ke pipe kita.
  // dup2 pada fd 0 dan 1 agar std::cin/std::cout (yang memakai fd 0/1) ikut.
  dup2(g_in_pipe[0], STDIN_FILENO);
  dup2(g_out_pipe[1], STDOUT_FILENO);
  // stderr dibiarkan; Stockfish menulis info ke stdout.
  char arg0[] = "stockfish";
  char* argv[] = {arg0, nullptr};
  stockfish_main(1, argv);
  g_running.store(false);
}

} // namespace

extern "C" {

SF_EXPORT SF_EXPORT int sf_init(const char* nnue_path) {
  if (g_running.load()) return 0; // sudah jalan

  if (pipe(g_in_pipe) != 0) return -1;
  if (pipe(g_out_pipe) != 0) return -2;

  // out_pipe[0] dibaca non-blocking agar reader_loop bisa berhenti.
  int flags = fcntl(g_out_pipe[0], F_GETFL, 0);
  fcntl(g_out_pipe[0], F_SETFL, flags | O_NONBLOCK);

  g_running.store(true);
  g_stop_reader.store(false);
  g_thread = std::thread(engine_thread);

  // Tunggu engine siap menerima perintah.
  usleep(150 * 1000);

  // Bila ada NNUE, kirim EvalFile sebagai perintah UCI pertama.
  if (nnue_path != nullptr && nnue_path[0] != '\0') {
    std::string cmd = std::string("setoption name EvalFile value ") + nnue_path + "\n";
    std::lock_guard<std::mutex> lk(g_out_mu);
    ssize_t w = write(g_in_pipe[1], cmd.data(), cmd.size());
    (void)w;
  }

  return 0;
}

SF_EXPORT SF_EXPORT int sf_cmd(const char* cmd) {
  if (!g_running.load() || cmd == nullptr) return -1;
  std::string s(cmd);
  s.push_back('\n');
  std::lock_guard<std::mutex> lk(g_out_mu);
  ssize_t w = write(g_in_pipe[1], s.data(), s.size());
  return (w == (ssize_t)s.size()) ? 0 : -2;
}

SF_EXPORT SF_EXPORT int sf_read(char* buf, int maxlen) {
  if (buf == nullptr || maxlen <= 0) return -1;
  std::lock_guard<std::mutex> lk(g_buf_mu);
  if (g_buf.empty()) return -1;
  size_t nl = g_buf.find('\n');
  size_t take;
  if (nl == std::string::npos) {
    take = g_buf.size();
  } else {
    take = nl + 1;
  }
  if (take > (size_t)maxlen) take = (size_t)maxlen;
  std::memcpy(buf, g_buf.data(), take);
  g_buf.erase(0, take);
  return (int)take;
}

SF_EXPORT void sf_quit() {
  if (!g_running.load()) return;
  // Kirim quit agar Stockfish keluar dari loop UCI.
  {
    std::lock_guard<std::mutex> lk(g_out_mu);
    const char q[] = "quit\n";
    ssize_t w = write(g_in_pipe[1], q, sizeof(q) - 1);
    (void)w;
  }
  if (g_thread.joinable()) g_thread.join();
  g_running.store(false);
  g_stop_reader.store(true);

  if (g_in_pipe[0] >= 0) { close(g_in_pipe[0]); g_in_pipe[0] = -1; }
  if (g_in_pipe[1] >= 0) { close(g_in_pipe[1]); g_in_pipe[1] = -1; }
  if (g_out_pipe[0] >= 0) { close(g_out_pipe[0]); g_out_pipe[0] = -1; }
  if (g_out_pipe[1] >= 0) { close(g_out_pipe[1]); g_out_pipe[1] = -1; }

  std::lock_guard<std::mutex> lk(g_buf_mu);
  g_buf.clear();
}

} // extern "C"
