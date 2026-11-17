// sf_bridge.cpp — jembatan C++ antara Stockfish dan Dart FFI.

#include <cstdio>
#include <cstring>
#include <cerrno>
#include <string>
#include <mutex>
#include <thread>
#include <atomic>
#include <unistd.h>
#include <fcntl.h>

extern int stockfish_main(int argc, char** argv);

#define SF_EXPORT __attribute__((visibility("default")))

namespace {

int g_in_pipe[2] = {-1, -1};   // Dart -> Stockfish
int g_out_pipe[2] = {-1, -1};  // Stockfish -> pembaca

std::thread g_engine_thread;
std::thread g_reader_thread;
std::atomic<bool> g_running{false};
std::atomic<bool> g_stop_reader{false};

std::mutex g_buf_mu;
std::string g_buf;

std::mutex g_in_mu;            // serialisasi tulis ke pipe input

void reader_loop() {
  char tmp[4096];
  while (!g_stop_reader.load()) {
    ssize_t n = read(g_out_pipe[0], tmp, sizeof(tmp));
    if (n > 0) {
      std::lock_guard<std::mutex> lk(g_buf_mu);
      g_buf.append(tmp, (size_t)n);
      continue;
    }
    if (n == 0) break; // EOF
    if (errno == EINTR) continue;
    if (errno == EAGAIN || errno == EWOULDBLOCK) {
      usleep(2000);
      continue;
    }
    break;
  }
}

void engine_thread() {
  char arg0[] = "stockfish";
  char* argv[] = {arg0, nullptr};
  stockfish_main(1, argv);
}

} // namespace

extern "C" {

SF_EXPORT int sf_init(const char* nnue_path) {
  if (g_running.load()) return 0;

  if (pipe(g_in_pipe) != 0) return -1;
  if (pipe(g_out_pipe) != 0) return -2;

  // Redirect stdin/stdout SEKARANG, sebelum thread dan sebelum Stockfish
  // mengonstruksi std::cin/std::cout.
  if (dup2(g_in_pipe[0], STDIN_FILENO) < 0) return -3;
  if (dup2(g_out_pipe[1], STDOUT_FILENO) < 0) return -4;

  // out_pipe[0] non-blocking agar reader_loop bisa berhenti.
  int flags = fcntl(g_out_pipe[0], F_GETFL, 0);
  fcntl(g_out_pipe[0], F_SETFL, flags | O_NONBLOCK);

  g_running.store(true);
  g_stop_reader.store(false);
  g_reader_thread = std::thread(reader_loop);
  g_engine_thread = std::thread(engine_thread);

  usleep(200 * 1000);

  if (nnue_path != nullptr && nnue_path[0] != '\0') {
    std::string cmd =
        std::string("setoption name EvalFile value ") + nnue_path + "\n";
    std::lock_guard<std::mutex> lk(g_in_mu);
    ssize_t w = write(g_in_pipe[1], cmd.data(), cmd.size());
    (void)w;
  }

  return 0;
}

SF_EXPORT int sf_cmd(const char* cmd) {
  if (!g_running.load() || cmd == nullptr) return -1;
  std::string s(cmd);
  s.push_back('\n');
  std::lock_guard<std::mutex> lk(g_in_mu);
  ssize_t w = write(g_in_pipe[1], s.data(), s.size());
  return (w == (ssize_t)s.size()) ? 0 : -2;
}

SF_EXPORT int sf_read(char* buf, int maxlen) {
  if (buf == nullptr || maxlen <= 0) return -1;
  std::lock_guard<std::mutex> lk(g_buf_mu);
  if (g_buf.empty()) return -1;
  size_t nl = g_buf.find('\n');
  size_t take = (nl == std::string::npos) ? g_buf.size() : nl + 1;
  if (take > (size_t)maxlen) take = (size_t)maxlen;
  std::memcpy(buf, g_buf.data(), take);
  g_buf.erase(0, take);
  return (int)take;
}

SF_EXPORT void sf_quit() {
  if (!g_running.load()) return;
  {
    std::lock_guard<std::mutex> lk(g_in_mu);
    const char q[] = "quit\n";
    ssize_t w = write(g_in_pipe[1], q, sizeof(q) - 1);
    (void)w;
  }
  if (g_engine_thread.joinable()) g_engine_thread.join();
  g_stop_reader.store(true);
  if (g_reader_thread.joinable()) g_reader_thread.join();
  g_running.store(false);

  if (g_in_pipe[0] >= 0) { close(g_in_pipe[0]); g_in_pipe[0] = -1; }
  if (g_in_pipe[1] >= 0) { close(g_in_pipe[1]); g_in_pipe[1] = -1; }
  if (g_out_pipe[0] >= 0) { close(g_out_pipe[0]); g_out_pipe[0] = -1; }
  if (g_out_pipe[1] >= 0) { close(g_out_pipe[1]); g_out_pipe[1] = -1; }

  std::lock_guard<std::mutex> lk(g_buf_mu);
  g_buf.clear();
}

} // extern "C"
