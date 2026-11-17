import 'package:flutter/foundation.dart';
import 'chess_types.dart';
import 'humanizer.dart';
import 'movegen.dart';
import 'stockfish_ffi.dart';

class GameController extends ChangeNotifier {
  final StockfishFfi engine;
  final Humanizer humanizer = Humanizer();

  List<String> board = List.filled(64, '.');
  bool whiteToMove = true;
  bool flipped = false;
  String castlingRights = 'KQkq';
  int? enPassantSquare;
  int? selected;
  Set<int> selectedTargets = {};
  Move? lastMove;
  Move? chosenMove;
  bool thinking = false;
  bool engineReady = false;
  List<EngineLine> lastLines = [];
  String status = '';
  bool gameOver = false;
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
    castlingRights = 'KQkq';
    enPassantSquare = null;
    selected = null;
    selectedTargets = {};
    lastMove = null;
    chosenMove = null;
    thinking = false;
    lastLines = [];
    status = '';
    gameOver = false;
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
    castlingRights = s.castlingRights;
    enPassantSquare = s.enPassantSquare;
    lastMove = s.lastMove;
    selected = null;
    selectedTargets = {};
    chosenMove = null;
    lastLines = [];
    status = '';
    gameOver = false;
    notifyListeners();
  }

  Future<void> initEngine() async {
    await engine.init(nnuePath: '');
    engineReady = true;
    notifyListeners();
  }

  bool _isWhitePiece(String p) => p != '.' && p == p.toUpperCase();

  void select(int idx) {
    if (thinking || gameOver) return;
    final p = board[idx];

    if (selected == null) {
      if (p == '.') return;
      if (_isWhitePiece(p) != whiteToMove) return;
      selected = idx;
      selectedTargets = MoveGen.legalTargets(
        board,
        idx,
        castlingRights: castlingRights,
        enPassantSquare: enPassantSquare,
      ).toSet();
      notifyListeners();
      return;
    }

    if (selected == idx) {
      selected = null;
      selectedTargets = {};
      notifyListeners();
      return;
    }

    final selP = board[selected!];
    final selIsWhite = _isWhitePiece(selP);
    final targetIsWhite = _isWhitePiece(p);

    if (p != '.' && targetIsWhite == selIsWhite) {
      selected = idx;
      selectedTargets = MoveGen.legalTargets(
        board,
        idx,
        castlingRights: castlingRights,
        enPassantSquare: enPassantSquare,
      ).toSet();
      notifyListeners();
      return;
    }

    if (!selectedTargets.contains(idx)) return;

    _applyManual(selected!, idx);
  }

  void applyPromotion(int from, int to, String piece) {
    _applyManual(from, to, promotion: piece);
  }

  void _applyManual(int from, int to, {String? promotion}) {
    _pushUndo();

    final movedPiece = board[from];
    final isWhite = _isWhitePiece(movedPiece);
    final type = movedPiece.toLowerCase();

    final newRights = _updateCastlingRights(from, to, type, isWhite);

    int? newEp;
    if (type == 'p' && (to - from).abs() == 16) {
      newEp = (from + to) ~/ 2;
    }

    board = MoveGen.apply(board, from, to, promotion: promotion);
    castlingRights = newRights.isEmpty ? '-' : newRights;
    enPassantSquare = newEp;

    lastMove = Move(from, to, promotion);
    whiteToMove = !whiteToMove;
    selected = null;
    selectedTargets = {};
    chosenMove = null;
    notifyListeners();

    final inCheck = MoveGen.isInCheck(board, whiteToMove);
    final hasLegal = _hasAnyLegalMove();
    if (!hasLegal) {
      gameOver = true;
      status = inCheck
          ? (whiteToMove ? 'Skakmat. Hitam menang.' : 'Skakmat. Putih menang.')
          : 'Stalemate. Seri.';
    } else if (inCheck) {
      status = whiteToMove ? 'Skak untuk Putih.' : 'Skak untuk Hitam.';
    } else {
      status = '';
    }
    notifyListeners();

    if (!gameOver) _advise();
  }

  String _updateCastlingRights(int from, int to, String type, bool isWhite) {
    var rights = castlingRights;
    if (rights == '-') return rights;
    if (type == 'k') {
      rights = isWhite
          ? rights.replaceAll('K', '').replaceAll('Q', '')
          : rights.replaceAll('k', '').replaceAll('q', '');
    }
    for (final sq in [from, to]) {
      if (sq == 63) rights = rights.replaceAll('K', '');
      if (sq == 56) rights = rights.replaceAll('Q', '');
      if (sq == 7) rights = rights.replaceAll('k', '');
      if (sq == 0) rights = rights.replaceAll('q', '');
    }
    return rights;
  }

  bool _hasAnyLegalMove() {
    for (var i = 0; i < 64; i++) {
      final p = board[i];
      if (p == '.') continue;
      if (_isWhitePiece(p) != whiteToMove) continue;
      final targets = MoveGen.legalTargets(
        board,
        i,
        castlingRights: castlingRights,
        enPassantSquare: enPassantSquare,
      );
      if (targets.isNotEmpty) return true;
    }
    return false;
  }

  Future<void> _advise() async {
    if (!engineReady || thinking) return;
    thinking = true;
    lastLines = [];
    chosenMove = null;
    notifyListeners();
    try {
      final lines = await engine.analyse(toFen(), depth: 8);
      if (lines.isNotEmpty) {
        lastLines = lines;
        chosenMove = humanizer.pick(lines, weAreWhite: whiteToMove);
        final pieceCount = board.where((p) => p != '.').length;
        final delay = humanizer.thinkDelay(
          pieceCount: pieceCount,
          inCheck: MoveGen.isInCheck(board, whiteToMove),
        );
        thinking = false;
        notifyListeners();
        await Future.delayed(delay);
      }
    } catch (_) {
      lastLines = [];
    } finally {
      thinking = false;
      notifyListeners();
    }
  }

  void _pushUndo() {
    _undo.add(_Snapshot(
      [...board],
      whiteToMove,
      castlingRights,
      enPassantSquare,
      lastMove,
    ));
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
    sb.write(castlingRights.isEmpty ? '-' : castlingRights);
    sb.write(' ');
    if (enPassantSquare != null) {
      final f = enPassantSquare! % 8;
      final r = 8 - (enPassantSquare! ~/ 8);
      sb.write('${String.fromCharCode(97 + f)}$r');
    } else {
      sb.write('-');
    }
    sb.write(' 0 1');
    return sb.toString();
  }
}

class _Snapshot {
  final List<String> board;
  final bool whiteToMove;
  final String castlingRights;
  final int? enPassantSquare;
  final Move? lastMove;
  _Snapshot(
    this.board,
    this.whiteToMove,
    this.castlingRights,
    this.enPassantSquare,
    this.lastMove,
  );
}
