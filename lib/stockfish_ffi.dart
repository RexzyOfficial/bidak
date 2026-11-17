import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
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
  DynamicLibrary? _lib;
  late final _SfInitD _init;
  late final _SfCmdD _cmd;
  late final _SfReadD _read;
  late final _SfQuitD _quit;

  bool _inited = false;
  bool get isInited => _inited;

  Timer? _pumpTimer;
  final StreamController<List<EngineLine>> _out =
      StreamController<List<EngineLine>>.broadcast();
  final StreamController<String> _raw = StreamController<String>.broadcast();

  Stream<List<EngineLine>> get lines => _out.stream;
  Stream<String> get rawLines => _raw.stream;

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

    _send('uci');
    _send('setoption name Threads value 1');
    _send('setoption name Hash value 16');
    _send('setoption name MultiPV value 3');
    _send('isready');

    _inited = true;
    _pump();
  }

  void _send(String cmd) {
    final p = cmd.toNativeUtf8();
    try {
      final rc = _cmd(p);
      if (rc != 0) {
        _raw.add('[send rc=$rc] $cmd');
      }
    } finally {
      malloc.free(p);
    }
  }

  void _pump() {
    _pumpTimer?.cancel();
    _pumpTimer = Timer.periodic(const Duration(milliseconds: 4), (_) {
      final buf = malloc<Uint8>(8192);
      try {
        final n = _read(buf.cast<Utf8>(), 8192);
        if (n > 0) {
          final chunk = buf.cast<Utf8>().toDartString(length: n);
          for (final l in const LineSplitter().convert(chunk)) {
            if (l.trim().isEmpty) continue;
            _raw.add(l);
            _handleLine(l);
          }
        } else if (n < 0 && n != -1) {
          _raw.add('[read rc=$n]');
        }
      } finally {
        malloc.free(buf);
      }
    });
  }

  final Map<int, EngineLine> _acc = {};

  void _handleLine(String line) {
    if (line.startsWith('info') && line.contains(' pv ')) {
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
      if (list.isNotEmpty) _out.add(list);
    }
  }

  int? _intAfter(String s, String key) {
    final i = s.indexOf(' $key ');
    if (i < 0) return null;
    final rest = s.substring(i + key.length + 2).trimLeft();
    final m = RegExp(r'^-?\d+').firstMatch(rest);
    return m == null ? null : int.parse(m.group(0)!);
  }

  Future<List<EngineLine>> analyse(String fen, {int depth = 6}) async {
    final completer = Completer<List<EngineLine>>();
    late StreamSubscription sub;
    sub = _out.stream.listen((lines) {
      if (!completer.isCompleted) completer.complete(lines);
      sub.cancel();
    });
    _send('position fen $fen');
    _send('go depth $depth');
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        sub.cancel();
        _send('stop');
        return <EngineLine>[];
      },
    );
  }

  void dispose() {
    _pumpTimer?.cancel();
    try {
      _quit();
    } catch (_) {}
    _out.close();
    _raw.close();
  }
}
