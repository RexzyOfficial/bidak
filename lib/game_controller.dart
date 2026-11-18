import 'dart:math';
import 'package:flutter/foundation.dart';
import 'chess_types.dart';
import 'humanizer.dart';
import 'movegen.dart';
import 'opening_book.dart';
import 'stockfish_ffi.dart';

class GameController extends ChangeNotifier {
  final StockfishFfi engine;
  final Humanizer humanizer = Humanizer();
  final OpeningBook book = OpeningBook();

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
  bool fromBook = false;

  int engineDepth = 8;
  double blunderChance = 0.05;
  int maxThinkDelayMs = 2500;

  List<String> moveHistory = [];
  final List<_Snapshot> _undo = [];

  GameController(this.engine) {
    reset();
  }

  void updateSettings(int depth, double blunder, int delay) {
    engineDepth = depth;
    blunderChance = blunder;
    maxThinkDelayMs = delay;
    notifyListeners();
  }

  double get whiteEvalPercentage {
    if (lastLines.isEmpty) return 0.5;
    final top = lastLines.first;
    if (top.isMate) {
      final mate = top.mateIn;
      final whiteMate = whiteToMove ? mate > 0 : mate < 0;
      return whiteMate ? 1.0 : 0.0;
    }
    final cp = whiteToMove ? top.scoreCp : -top.scoreCp;
    final clamped = cp.clamp(-1000, 1000);
    return 1.0 / (1.0 + pow(10, -clamped / 400.0));
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
    fromBook = false;
    moveHistory = [];
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
    moveHistory = [...s.moveHistory];
    selected = null;
    selectedTargets = {};
    chosenMove = null;
    lastLines = [];
    status = '';
    gameOver = false;
    fromBook = false;
    notifyListeners();
  }

  Future<void> initEngine() async {
    await engine.init(nnuePath: '');
    await book.load();
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

  String _generateSan(int from, int to, {String? promotion}) {
    final p = board[from];
    final isWhite = p == p.toUpperCase();
    final type = p.toLowerCase();
    final f = from % 8;
    final r = from ~/ 8;
    final tF = to % 8;
    final tR = to ~/ 8;
    final toSq = '${String.fromCharCode(97 + tF)}${8 - tR}';
    final isCapture = board[to] != '.' || (type == 'p' && f != tF && board[to] == '.');

    String san = '';
    if (type == 'k' && (to - from).abs() == 2) {
      san = to > from ? 'O-O' : 'O-O-O';
    } else {
      if (type != 'p') {
        san += p.toUpperCase();
        final others = <int>[];
        for (var i = 0; i < 64; i++) {
          if (i != from && board[i] == p) {
            final targets = MoveGen.legalTargets(board, i,
                castlingRights: castlingRights,
                enPassantSquare: enPassantSquare);
            if (targets.contains(to)) others.add(i);
          }
        }
        if (others.isNotEmpty) {
          final sameFile = others.any((i) => i % 8 == f);
          if (sameFile) {
            san += '${String.fromCharCode(97 + f)}${8 - r}';
          } else {
            san += String.fromCharCode(97 + f);
          }
        }
      } else if (isCapture) {
        san += String.fromCharCode(97 + f);
      }

      if (isCapture) san += 'x';
      san += toSq;
      if (promotion != null) san += '=${promotion.toUpperCase()}';
    }

    final nextBoard = MoveGen.apply(board, from, to, promotion: promotion);
    final nextWhite = !isWhite;
    final inCheck = MoveGen.isInCheck(nextBoard, nextWhite);
    if (inCheck) {
      bool hasMove = false;
      for (var i = 0; i < 64; i++) {
        if (nextBoard[i] != '.' &&
            (nextBoard[i] == nextBoard[i].toUpperCase()) == nextWhite) {
          if (MoveGen.legalTargets(nextBoard, i,
                  castlingRights: '-', enPassantSquare: null)
              .isNotEmpty) {
            hasMove = true;
            break;
          }
        }
      }
      san += hasMove ? '+' : '#';
    }
    return san;
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

    final san = _generateSan(from, to, promotion: promotion);

    board = MoveGen.apply(board, from, to, promotion: promotion);
    castlingRights = newRights.isEmpty ? '-' : newRights;
    enPassantSquare = newEp;
    moveHistory.add(san);

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
    fromBook = false;
    notifyListeners();

    try {
      // 1. Cek Opening Book (maksimal 15 langkah / 7.5 putaran)
      if (moveHistory.length < 15) {
        final bookMove = book.getMove(moveHistory, board);
        if (bookMove != null) {
          chosenMove = bookMove;
          fromBook = true;
          thinking = false;
          notifyListeners();
          // Jeda pikir singkat untuk buku
          await Future.delayed(Duration(milliseconds: 500 + Random().nextInt(800)));
          return;
        }
      }

      // 2. Jika tidak ada di buku, panggil Stockfish
      final lines = await engine.analyse(toFen(), depth: engineDepth);
      if (lines.isNotEmpty) {
        lastLines = lines;
        chosenMove = humanizer.pick(
          lines,
          weAreWhite: whiteToMove,
          blunderChance: blunderChance,
        );
        final pieceCount = board.where((p) => p != '.').length;
        final delay = humanizer.thinkDelay(
          pieceCount: pieceCount,
          inCheck: MoveGen.isInCheck(board, whiteToMove),
          maxDelayMs: maxThinkDelayMs,
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
      [...moveHistory],
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
  final List<String> moveHistory;
  _Snapshot(
    this.board,
    this.whiteToMove,
    this.castlingRights,
    this.enPassantSquare,
    this.lastMove,
    this.moveHistory,
  );
}
