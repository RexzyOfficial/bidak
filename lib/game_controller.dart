import 'dart:ffi' show Abi;
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chess_types.dart';
import 'humanizer.dart';
import 'move_labels.dart';
import 'movegen.dart';
import 'opening_book.dart';
import 'san.dart';
import 'stockfish_ffi.dart';

class GameController extends ChangeNotifier {
  final StockfishFfi engine;
  final Humanizer humanizer = Humanizer();
  final OpeningBook book = OpeningBook();

  // armv7 (SF11, HP lama) lebih ringan; arm64 (SF16 + NNUE) lebih dalam.
  static final int engineDepth = Abi.current() == Abi.androidArm ? 10 : 12;

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
  int halfmoveClock = 0; // setengah-langkah sejak tangkapan / gerak pion
  List<String> posKeys = []; // kunci tiap posisi, untuk hitung repetisi

  double blunderChance = 0.05;
  static const double maxBlunder = 0.25;
  static const String _kBlunder = 'blunder_chance';

  // Posisi langkah terpilih dibanding terbaik (untuk penanda blunder).
  int chosenRank = 1;
  int chosenLoss = 0; // dalam cp

  // Eval dari sudut pandang Putih.
  double evalFraction = 0.5;
  String evalText = '0.0';

  List<String> moveHistory = [];
  List<String> uciHistory = [];
  List<MoveLabel?> labels = [];
  _Pending? _pending;
  final List<_Snapshot> _undo = [];

  int _gen = 0;
  bool _disposed = false;

  GameController(this.engine) {
    reset();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  void setBlunderChance(double v) {
    blunderChance = v;
    notifyListeners();
  }

  double get whiteEvalPercentage => evalFraction;

  Future<void> loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getDouble(_kBlunder);
      if (v != null) {
        blunderChance = v.clamp(0.0, maxBlunder).toDouble();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_kBlunder, blunderChance);
    } catch (_) {}
  }

  bool get isMistake =>
      chosenMove != null && !fromBook && chosenRank > 1 && chosenLoss >= 30;

  void _noteMistake(List<EngineLine> lines, Move picked) {
    chosenRank = 1;
    chosenLoss = 0;
    final top = lines.first;
    for (final l in lines) {
      if (l.move.toUci() == picked.toUci()) {
        chosenRank = l.multipv;
        if (!top.isMate && !l.isMate) chosenLoss = top.scoreCp - l.scoreCp;
        break;
      }
    }
  }

  void _updateEval(List<EngineLine> lines) {
    final top = lines.first;
    if (top.isMate) {
      final whiteMates = whiteToMove ? top.mateIn > 0 : top.mateIn < 0;
      evalFraction = whiteMates ? 1.0 : 0.0;
      evalText = '${whiteMates ? '' : '-'}M${top.mateIn.abs()}';
      return;
    }
    final cp = whiteToMove ? top.scoreCp : -top.scoreCp;
    final clamped = cp.clamp(-1000, 1000);
    evalFraction = 1.0 / (1.0 + pow(10, -clamped / 400.0));
    evalText = cp.abs() < 5
        ? '0.0'
        : '${cp > 0 ? '+' : ''}${(cp / 100).toStringAsFixed(1)}';
  }

  void _cancelAnalysis() {
    _gen++;
    engine.stop();
    thinking = false;
  }

  void reset() {
    _cancelAnalysis();
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
    lastLines = [];
    status = '';
    gameOver = false;
    fromBook = false;
    evalFraction = 0.5;
    evalText = '0.0';
    moveHistory = [];
    uciHistory = [];
    halfmoveClock = 0;
    posKeys = [_posKey()];
    labels = [];
    _pending = null;
    _undo.clear();
    notifyListeners();
  }

  void flip() {
    flipped = !flipped;
    notifyListeners();
  }

  void undo() {
    if (_undo.isEmpty) return;
    _cancelAnalysis();
    final s = _undo.removeLast();
    board = [...s.board];
    whiteToMove = s.whiteToMove;
    castlingRights = s.castlingRights;
    enPassantSquare = s.enPassantSquare;
    lastMove = s.lastMove;
    moveHistory = [...s.moveHistory];
    uciHistory = [...s.uciHistory];
    halfmoveClock = s.halfmoveClock;
    posKeys = [...s.posKeys];
    _pending = null;
    if (labels.length > moveHistory.length) {
      labels.removeRange(moveHistory.length, labels.length);
    }
    selected = null;
    selectedTargets = {};
    chosenMove = null;
    lastLines = [];
    evalFraction = 0.5;
    evalText = '0.0';
    status = '';
    gameOver = false;
    fromBook = false;
    if (MoveGen.isInCheck(board, whiteToMove)) {
      status = whiteToMove ? 'Skak untuk Putih.' : 'Skak untuk Hitam.';
    }
    final claim = _claimableDraw();
    if (claim != null) {
      status = status.isEmpty ? claim : '$status  $claim';
    }
    notifyListeners();
    if (moveHistory.isNotEmpty) _advise();
  }

  Future<void> initEngine() async {
    await engine.init(nnuePath: '');
    await book.load();
    engineReady = true;
    notifyListeners();
  }

  bool _isWhitePiece(String p) => p != '.' && p == p.toUpperCase();

  void select(int idx) {
    if (gameOver) return;
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
    _capturePending(from, to, promotion);
    _cancelAnalysis();
    _pushUndo();

    final movedPiece = board[from];
    final isWhite = _isWhitePiece(movedPiece);
    final type = movedPiece.toLowerCase();
    final newRights = _updateCastlingRights(from, to, type, isWhite);

    int? newEp;
    if (type == 'p' && (to - from).abs() == 16) {
      newEp = (from + to) ~/ 2;
    }

    final san = San.generate(
      board,
      from,
      to,
      promotion: promotion,
      castlingRights: castlingRights,
      enPassantSquare: enPassantSquare,
    );

    final isCapture =
        board[to] != '.' || (type == 'p' && (from % 8) != (to % 8));
    halfmoveClock = (type == 'p' || isCapture) ? 0 : halfmoveClock + 1;
    board = MoveGen.apply(board, from, to, promotion: promotion);
    castlingRights = newRights.isEmpty ? '-' : newRights;
    enPassantSquare = newEp;
    moveHistory.add(san);
    labels.add(null);
    _tryInstantLabel();
    uciHistory.add(Move(from, to, promotion).toUci());

    lastMove = Move(from, to, promotion);
    whiteToMove = !whiteToMove;
    posKeys.add(_posKey());
    selected = null;
    selectedTargets = {};
    chosenMove = null;
    lastLines = [];
    fromBook = false;

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
    if (!gameOver) {
      final autoDraw = _autoDraw();
      if (autoDraw != null) {
        gameOver = true;
        status = autoDraw;
        evalFraction = 0.5;
        evalText = '0.0';
      } else {
        final claim = _claimableDraw();
        if (claim != null) {
          status = status.isEmpty ? claim : '$status  $claim';
        }
      }
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

  // Kunci posisi untuk hitungan repetisi: susunan bidak, giliran, hak rokade.
  String _posKey() => toFen().split(' ').take(3).join(' ');

  int _repetitions() {
    if (posKeys.isEmpty) return 0;
    final key = posKeys.last;
    var n = 0;
    for (final k in posKeys) {
      if (k == key) n++;
    }
    return n;
  }

  bool _insufficientMaterial() {
    var knights = 0;
    final bishops = <int>[];
    for (var i = 0; i < 64; i++) {
      final p = board[i];
      if (p == '.') continue;
      final t = p.toLowerCase();
      if (t == 'n') {
        knights++;
      } else if (t == 'b') {
        bishops.add(i);
      } else if (t != 'k') {
        return false; // masih ada pion / benteng / menteri
      }
    }
    final minors = knights + bishops.length;
    if (minors <= 1) return true; // K v K, atau K + 1 bidak ringan v K
    if (knights == 0) {
      // hanya gajah: seri kalau semuanya di warna kotak yang sama
      int colorOf(int sq) => ((sq ~/ 8) + (sq % 8)) % 2;
      final c = colorOf(bishops.first);
      return bishops.every((b) => colorOf(b) == c);
    }
    return false;
  }

  // Seri otomatis: game berhenti.
  String? _autoDraw() {
    if (_insufficientMaterial()) return 'Seri: material tidak cukup.';
    if (_repetitions() >= 5) return 'Seri: posisi berulang 5 kali.';
    if (halfmoveClock >= 150) return 'Seri: aturan 75 langkah.';
    return null;
  }

  // Seri yang boleh diklaim: game tetap lanjut.
  String? _claimableDraw() {
    if (_repetitions() >= 3) {
      return 'Seri bisa diklaim: posisi berulang 3 kali.';
    }
    if (halfmoveClock >= 100) return 'Seri bisa diklaim: aturan 50 langkah.';
    return null;
  }

  // ---- Label kualitas langkah ----
  void _capturePending(int from, int to, String? promotion) {
    _pending = null;
    final move = Move(from, to, promotion);
    final isBook = book.containsMove(toFen(), move);

    var legalCount = 0;
    for (var i = 0; i < 64; i++) {
      final p = board[i];
      if (p == '.' || _isWhitePiece(p) != whiteToMove) continue;
      legalCount += MoveGen.legalTargets(
        board,
        i,
        castlingRights: castlingRights,
        enPassantSquare: enPassantSquare,
      ).length;
    }
    final forced = legalCount == 1;
    if (lastLines.isEmpty && !isBook && !forced) return;

    final before = [...lastLines]
      ..sort((a, b) => a.multipv.compareTo(b.multipv));
    final played = move.toUci();

    var epBefore = 0.5;
    double? epAfter;
    if (before.isNotEmpty) {
      epBefore = MoveQuality.ep(before.first);
      for (final l in before) {
        if (l.move.toUci() == played) {
          epAfter = MoveQuality.ep(l);
          break;
        }
      }
    }

    var sacrifice = false;
    final moved = board[from];
    if (!isBook &&
        !forced &&
        moved.toLowerCase() != 'k' &&
        MoveQuality.pieceValue(moved) >= 3) {
      sacrifice = MoveQuality.sacrificeValue(board, move) >= 2;
      if (sacrifice) {
        // Bukan Brilliant kalau ada langkah non-pengorbanan yang hampir
        // sama bagus di 3 besar mesin.
        for (final l in before) {
          if (l.move.toUci() == played) continue;
          if (MoveQuality.ep(l) < epBefore - 0.01) continue;
          if (MoveQuality.sacrificeValue(board, l.move) < 2) {
            sacrifice = false;
            break;
          }
        }
      }
    }

    LabelKind? prevKind;
    final prevIdx = moveHistory.length - 1;
    if (prevIdx >= 0 && prevIdx < labels.length) {
      prevKind = labels[prevIdx]?.kind;
    }

    final lm = lastMove;
    final recapture = lm != null && lm.to == to && board[to] != '.';

    _pending = _Pending(
      index: moveHistory.length,
      recapture: recapture,
      before: before,
      playedUci: played,
      isBook: isBook,
      forced: forced,
      sacrifice: sacrifice,
      prevKind: prevKind,
      epBefore: epBefore,
      epAfter: epAfter,
    );
  }

  void _tryInstantLabel() {
    final p = _pending;
    if (p == null || p.index >= labels.length) return;
    if (p.forced) {
      labels[p.index] = const MoveLabel(LabelKind.forced, 0.0);
      _pending = null;
      return;
    }
    if (p.isBook) {
      labels[p.index] = const MoveLabel(LabelKind.book, 0.0);
      _pending = null;
      return;
    }
    final after = p.epAfter;
    if (after != null) {
      _applyLabel(p, after);
      _pending = null;
    }
  }

  void _resolvePendingLabel(List<EngineLine> afterLines) {
    final p = _pending;
    if (p == null || afterLines.isEmpty || p.before.isEmpty) return;
    // Analisis posisi sesudah langkah ada di sudut pandang lawan.
    final epOpp = MoveQuality.ep(afterLines.first);
    _applyLabel(p, 1.0 - epOpp);
    _pending = null;
  }

  void _applyLabel(_Pending p, double epAfter) {
    if (p.index >= labels.length || p.before.isEmpty) return;
    final top = p.before.first;
    final playedIsTop = top.move.toUci() == p.playedUci;
    final epSecond =
        p.before.length > 1 ? MoveQuality.ep(p.before[1]) : null;
    final topIsMate = top.isMate && top.mateIn > 0;
    var stillMates = epAfter >= 0.95;
    for (final l in p.before) {
      if (l.move.toUci() == p.playedUci) {
        stillMates = l.isMate && l.mateIn > 0;
        break;
      }
    }
    labels[p.index] = MoveQuality.classify(
      forced: p.forced,
      isBook: p.isBook,
      playedIsTop: playedIsTop,
      epBefore: p.epBefore,
      epAfter: epAfter,
      epSecond: epSecond,
      realSacrifice: p.sacrifice,
      isRecapture: p.recapture,
      topIsMate: topIsMate,
      playedStillMates: stillMates,
      prevOppKind: p.prevKind,
    );
  }

  Future<void> _advise() async {
    if (!engineReady) return;
    final gen = ++_gen;
    thinking = true;
    lastLines = [];
    chosenMove = null;
    fromBook = false;
    chosenRank = 1;
    chosenLoss = 0;
    notifyListeners();

    try {
      final fen = toFen();
      final seed = Humanizer.seedFrom(fen);

      // 1. Opening book: langkah gold langsung tampil.
      Move? bookMove;
      if (moveHistory.length < 40) {
        bookMove = book.getMove(
          fen,
          board,
          whiteToMove: whiteToMove,
          castlingRights: castlingRights,
          enPassantSquare: enPassantSquare,
          rng: Random(seed),
        );
        if (bookMove != null) {
          chosenMove = bookMove;
          fromBook = true;
          notifyListeners();
        }
      }

      // 2. Stockfish tetap jalan: eval bar + panah alternatif (hitam/abu).
      final lines = await engine.analyse(uciHistory, depth: engineDepth);
      if (gen != _gen) return;
      if (lines.isNotEmpty) {
        lastLines = lines;
        _updateEval(lines);
        _resolvePendingLabel(lines);
        if (bookMove == null) {
          final picked = humanizer.pick(
            lines,
            blunderChance: blunderChance,
            seed: seed,
          );
          chosenMove = picked;
          _noteMistake(lines, picked);
        }
      }
    } catch (_) {
      if (gen == _gen) lastLines = [];
    } finally {
      if (gen == _gen) {
        thinking = false;
        notifyListeners();
      }
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
      [...uciHistory],
      halfmoveClock,
      [...posKeys],
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
          if (empty > 0) {
            sb.write(empty);
            empty = 0;
          }
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

class _Pending {
  final int index;
  final List<EngineLine> before;
  final String playedUci;
  final bool isBook;
  final bool forced;
  final bool sacrifice;
  final bool recapture;
  final LabelKind? prevKind;
  final double epBefore;
  final double? epAfter;
  _Pending({
    required this.index,
    required this.before,
    required this.playedUci,
    required this.isBook,
    required this.forced,
    required this.sacrifice,
    required this.recapture,
    required this.prevKind,
    required this.epBefore,
    required this.epAfter,
  });
}

class _Snapshot {
  final List<String> board;
  final bool whiteToMove;
  final String castlingRights;
  final int? enPassantSquare;
  final Move? lastMove;
  final List<String> moveHistory;
  final List<String> uciHistory;
  final int halfmoveClock;
  final List<String> posKeys;
  _Snapshot(
    this.board,
    this.whiteToMove,
    this.castlingRights,
    this.enPassantSquare,
    this.lastMove,
    this.moveHistory,
    this.uciHistory,
    this.halfmoveClock,
    this.posKeys,
  );
}
