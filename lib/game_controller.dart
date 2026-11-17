import 'package:flutter/foundation.dart';
import 'chess_types.dart';
import 'stockfish_ffi.dart';

class GameController extends ChangeNotifier {
  final StockfishFfi engine;

  List<String> board = List.filled(64, '.');
  bool whiteToMove = true;
  bool flipped = false;
  int? selected;
  Move? lastMove;
  bool thinking = false;
  bool engineReady = false;
  List<EngineLine> lastLines = [];
  final List<_Snapshot> _undo = [];

  GameController(this.engine) {
    reset();
  }

  void reset() {
    board = List.filled(64, '.');
    const back = ['r', 'n', 'b', 'q', 'k', 'b', 'n', 'r'];
    for (var f = 0; f < 8; f++) {
      board[f] = back[f];
      board[8 + f] = 'p';
      board[48 + f] = 'P';
      board[56 + f] = back[f].toUpperCase();
    }
    whiteToMove = true;
    flipped = false;
    selected = null;
    lastMove = null;
    thinking = false;
    lastLines = [];
    _undo.clear();
    notifyListeners();
  }

  void flip() {
    flipped = !flipped;
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    final s = _undo.removeLast();
    board = [...s.board];
    whiteToMove = s.whiteToMove;
    lastMove = s.lastMove;
    selected = null;
    lastLines = [];
    notifyListeners();
  }

  Future<void> initEngine() async {
    await engine.init(nnuePath: '');
    engineReady = true;
    notifyListeners();
  }

  bool _isWhitePiece(String p) => p != '.' && p == p.toUpperCase();

  void select(int idx) {
    if (thinking) return;
    final p = board[idx];

    if (selected == null) {
      if (p == '.') return;
      if (_isWhitePiece(p) != whiteToMove) return;
      selected = idx;
      notifyListeners();
      return;
    }

    if (selected == idx) {
      selected = null;
      notifyListeners();
      return;
    }

    final selP = board[selected!];
    final selIsWhite = _isWhitePiece(selP);
    final targetIsWhite = _isWhitePiece(p);

    // Ketuk bidak sendiri: pilih ulang.
    if (p != '.' && targetIsWhite == selIsWhite) {
      selected = idx;
      notifyListeners();
      return;
    }

    _applyManual(selected!, idx);
  }

  void _applyManual(int from, int to) {
    _pushUndo();
    board[to] = board[from];
    board[from] = '.';
    lastMove = Move(from, to);
    whiteToMove = !whiteToMove;
    selected = null;
    notifyListeners();
    _advise();
  }

  Future<void> _advise() async {
    if (!engineReady || thinking) return;
    thinking = true;
    lastLines = [];
    notifyListeners();
    try {
      final lines = await engine.analyse(toFen(), depth: 6);
      lastLines = lines;
    } catch (_) {
      lastLines = [];
    } finally {
      thinking = false;
      notifyListeners();
    }
  }

  void _pushUndo() {
    _undo.add(_Snapshot([...board], whiteToMove, lastMove));
    if (_undo.length > 200) _undo.removeAt(0);
  }

  String toFen() {
    final sb = StringBuffer();
    for (var r = 0; r < 8; r++) {
      var empty = 0;
      for (var f = 0; f < 8; f++) {
        final p = board[r * 8 + f];
        if (p == '.') {
          empty++;
        } else {
          if (empty > 0) { sb.write(empty); empty = 0; }
          sb.write(p);
        }
      }
      if (empty > 0) sb.write(empty);
      if (r < 7) sb.write('/');
    }
    sb.write(whiteToMove ? ' w ' : ' b ');
    sb.write('KQkq - 0 1');
    return sb.toString();
  }
}

class _Snapshot {
  final List<String> board;
  final bool whiteToMove;
  final Move? lastMove;
  _Snapshot(this.board, this.whiteToMove, this.lastMove);
}
