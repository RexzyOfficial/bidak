import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'chess_types.dart';

typedef _SfInitC = Int32 Function(Pointer<Utf8>);
typedef _SfInitD = int Function(Pointer<Utf8>);
typedef _SfCmdC = Int32 Function(Pointer<Utf8>);
typedef _SfCmdD = int Function(Pointer<Utf8>);
typedef _SfReadC = Int32 Function(Pointer<Utf8>, Int32);
typedef _SfReadD = int Function(Pointer<Utf8>, int);
typedef _SfQuitC = Void Function();
typedef _SfQuitD = void Function();

class StockfishFfi {
  static const int multiPv = 3;
  static const int _bufSize = 8192;

  DynamicLibrary? _lib;
  late final _SfInitD _init;
  late final _SfCmdD _cmd;
  late final _SfReadD _read;
  late final _SfQuitD _quit;

  bool _inited = false;
  bool get isInited => _inited;

  Timer? _pumpTimer;
  Pointer<Utf8>? _buf;

  final StreamController<String> _raw = StreamController<String>.broadcast();
  Stream<String> get rawLines => _raw.stream;

  final Map<int, EngineLine> _acc = {};
  Completer<List<EngineLine>>? _result;
  Completer<void>? _idle; // selesai saat 'bestmove' datang
  int _reqSeq = 0;
  Future<void> _lock = Future.value();

  Future<void> init({String nnuePath = ''}) async {
    if (_inited) return;
    _lib = DynamicLibrary.open('libstockfish.so');
    _init = _lib!.lookupFunction<_SfInitC, _SfInitD>('sf_init');
    _cmd = _lib!.lookupFunction<_SfCmdC, _SfCmdD>('sf_cmd');
    _read = _lib!.lookupFunction<_SfReadC, _SfReadD>('sf_read');
    _quit = _lib!.lookupFunction<_SfQuitC, _SfQuitD>('sf_quit');

    final p = nnuePath.toNativeUtf8();
    try {
      final rc = _init(p);
      if (rc != 0) throw StateError('sf_init gagal rc=$rc');
    } finally {
      malloc.free(p);
    }

    _buf = malloc<Uint8>(_bufSize).cast<Utf8>();

    _send('uci');
    _send('setoption name Threads value 1');
    _send('setoption name Hash value 16');
    _send('setoption name MultiPV value $multiPv');
    _send('isready');

    _inited = true;
    _pump();
  }

  void _send(String cmd) {
    final p = cmd.toNativeUtf8();
    try {
      final rc = _cmd(p);
      if (rc != 0) _raw.add('[send rc=$rc] $cmd');
    } finally {
      malloc.free(p);
    }
  }

  void _pump() {
    _pumpTimer?.cancel();
    _pumpTimer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      final buf = _buf;
      if (buf == null) return;
      for (var k = 0; k < 64; k++) {
        final n = _read(buf, _bufSize);
        if (n == 0 || n == -1) break;
        if (n < 0) {
          _raw.add('[read rc=$n]');
          break;
        }
        try {
          final chunk = buf.toDartString(length: n);
          for (final l in const LineSplitter().convert(chunk)) {
            if (l.trim().isEmpty) continue;
            _raw.add(l);
            _handleLine(l);
          }
        } catch (_) {}
      }
    });
  }

  void _handleLine(String line) {
    if (line.startsWith('info')) {
      if (!line.contains(' pv ') ||
          line.contains('lowerbound') ||
          line.contains('upperbound')) {
        return;
      }
      final mpv = _intAfter(line, 'multipv') ?? 1;
      final depth = _intAfter(line, 'depth') ?? 0;
      final cp = _intAfter(line, 'score cp');
      final mate = _intAfter(line, 'score mate');
      final pv = line.split(' pv ').last.trim().split(' ').first;
      final move = Move.fromUci(pv);
      if (move != null) {
        _acc[mpv] = EngineLine(
          multipv: mpv,
          depth: depth,
          scoreCp: cp ?? 0,
          isMate: mate != null,
          mateIn: mate ?? 0,
          move: move,
        );
      }
    } else if (line.startsWith('bestmove')) {
      final list = _acc.values.toList()
        ..sort((a, b) => a.multipv.compareTo(b.multipv));
      _acc.clear();
      final idle = _idle;
      if (idle != null && !idle.isCompleted) idle.complete();
      final res = _result;
      if (res != null && !res.isCompleted) res.complete(list);
    }
  }

  int? _intAfter(String s, String key) {
    final i = s.indexOf(' $key ');
    if (i < 0) return null;
    final rest = s.substring(i + key.length + 2).trimLeft();
    final m = RegExp(r'^-?\d+').firstMatch(rest);
    return m == null ? null : int.parse(m.group(0)!);
  }

  void _abortRunning() {
    final idle = _idle;
    if (idle != null && !idle.isCompleted) _send('stop');
  }

  /// Hentikan analisis yang sedang jalan (aman dipanggil kapan saja).
  void stop() => _abortRunning();

  /// Analisis posisi hasil dari startpos + daftar langkah UCI.
  /// Panggilan baru otomatis membatalkan yang lama.
  Future<List<EngineLine>> analyse(List<String> uciMoves,
      {required int depth}) {
    final id = ++_reqSeq;
    final prev = _lock;
    final done = Completer<void>();
    _lock = done.future;
    _abortRunning();

    return () async {
      try {
        await prev;
        if (id != _reqSeq) return <EngineLine>[]; // sudah digantikan
        return await _run(uciMoves, depth);
      } finally {
        done.complete();
      }
    }();
  }

  Future<List<EngineLine>> _run(List<String> uciMoves, int depth) {
    _acc.clear();
    final result = Completer<List<EngineLine>>();
    final idle = Completer<void>();
    _result = result;
    _idle = idle;

    _send('ucinewgame');
    _send(uciMoves.isEmpty
        ? 'position startpos'
        : 'position startpos moves ${uciMoves.join(' ')}');
    _send('go depth $depth');

    return result.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () async {
        _send('stop');
        await idle.future
            .timeout(const Duration(seconds: 3), onTimeout: () {});
        return <EngineLine>[];
      },
    );
  }

  void dispose() {
    _pumpTimer?.cancel();
    if (_inited) {
      try {
        _quit();
      } catch (_) {}
    }
    final b = _buf;
    if (b != null) {
      malloc.free(b);
      _buf = null;
    }
    _raw.close();
  }
}
