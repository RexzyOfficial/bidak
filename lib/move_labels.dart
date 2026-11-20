import 'dart:ffi' show Abi;
import 'dart:math';
import 'chess_types.dart';
import 'movegen.dart';

enum LabelKind {
  forced,
  book,
  brilliant,
  great,
  best,
  excellent,
  good,
  inaccuracy,
  mistake,
  miss,
  blunder,
}

class MoveLabel {
  final LabelKind kind;
  final double loss; // kehilangan expected points, 0..1
  const MoveLabel(this.kind, this.loss);

  String get text => switch (kind) {
        LabelKind.forced => 'Forced',
        LabelKind.book => 'Book',
        LabelKind.brilliant => 'Brilliant',
        LabelKind.great => 'Great',
        LabelKind.best => 'Best',
        LabelKind.excellent => 'Excellent',
        LabelKind.good => 'Good',
        LabelKind.inaccuracy => 'Inaccuracy',
        LabelKind.mistake => 'Mistake',
        LabelKind.miss => 'Miss',
        LabelKind.blunder => 'Blunder',
      };

  int get colorValue => switch (kind) {
        LabelKind.forced => 0xFF9E9E9E,
        LabelKind.book => 0xFFA88865,
        LabelKind.brilliant => 0xFF1BACA6,
        LabelKind.great => 0xFF5C8BB0,
        LabelKind.best => 0xFF7CB342,
        LabelKind.excellent => 0xFF9CCC65,
        LabelKind.good => 0xFFA5B49B,
        LabelKind.inaccuracy => 0xFFF7C631,
        LabelKind.mistake => 0xFFE58F2A,
        LabelKind.miss => 0xFFFF7769,
        LabelKind.blunder => 0xFFCA3431,
      };
}

class MoveQuality {
  // SF16 memakai cp yang dinormalisasi (356 vs 208 di skala lama),
  // SF11 (armv7) memakai skala lama.
  static final double _cpScale =
      Abi.current() == Abi.androidArm ? 1.0 : 356 / 208;
  static const double _k = 0.00368208; // kurva win% Lichess

  /// Expected points (0..1) dari sudut pandang pihak yang jalan di baris ini.
  static double ep(EngineLine l) {
    if (l.isMate) return l.mateIn > 0 ? 1.0 : 0.0;
    final x = (-_k * l.scoreCp * _cpScale).clamp(-50.0, 50.0).toDouble();
    return 1.0 / (1.0 + exp(x));
  }

  static int pieceValue(String p) => switch (p.toLowerCase()) {
        'p' => 1,
        'n' || 'b' => 3,
        'r' => 5,
        'q' => 9,
        'k' => 100,
        _ => 0,
      };

  /// Untung bersih (>= 0) bagi pihak [whiteToCapture] bila ia memulai
  /// menangkap di kotak [sq]; masing-masing pihak boleh berhenti kapan saja.
  static int see(List<String> board, int sq, bool whiteToCapture,
      {int depth = 0}) {
    if (depth > 8) return 0;
    final target = board[sq];
    if (target == '.') return 0;
    var bestFrom = -1;
    var bestVal = 1 << 30;
    for (var i = 0; i < 64; i++) {
      final p = board[i];
      if (p == '.' || (p == p.toUpperCase()) != whiteToCapture) continue;
      final v = pieceValue(p);
      if (v >= bestVal) continue;
      if (MoveGen.legalTargets(board, i).contains(sq)) {
        bestVal = v;
        bestFrom = i;
      }
    }
    if (bestFrom < 0) return 0;
    final gain = pieceValue(target);
    final next = MoveGen.apply(board, bestFrom, sq);
    final reply = see(next, sq, !whiteToCapture, depth: depth + 1);
    return max(0, gain - reply);
  }

  /// Poin material yang hilang bersih bagi pelangkah (setelah lawan membalas
  /// dengan tukar-menukar terbaik di kotak tujuan). >= 2 dianggap pengorbanan.
  static int sacrificeValue(List<String> boardBefore, Move m) {
    final mover = boardBefore[m.from];
    if (mover == '.') return 0;
    final moverWhite = mover == mover.toUpperCase();
    final captured = boardBefore[m.to];
    final capturedVal = captured == '.' ? 0 : pieceValue(captured);
    final after =
        MoveGen.apply(boardBefore, m.from, m.to, promotion: m.promotion);
    final lost = see(after, m.to, !moverWhite);
    return lost - capturedVal;
  }

  static MoveLabel classify({
    required bool forced,
    required bool isBook,
    required bool playedIsTop,
    required double epBefore,
    required double epAfter,
    required double? epSecond,
    required bool realSacrifice,
    required bool topIsMate,
    required bool playedStillMates,
    required LabelKind? prevOppKind,
  }) {
    if (forced) return const MoveLabel(LabelKind.forced, 0.0);
    if (isBook) return const MoveLabel(LabelKind.book, 0.0);
    final loss = max(0.0, epBefore - epAfter);

    // Brilliant: pengorbanan nyata, hampir terbaik, tidak jadi buruk,
    // dan posisi sebelumnya belum menang telak.
    if (realSacrifice && loss < 0.02 && epAfter >= 0.45 && epBefore <= 0.90) {
      return MoveLabel(LabelKind.brilliant, loss);
    }
    if (playedIsTop) {
      if (epSecond != null && epBefore >= 0.30 && epBefore - epSecond >= 0.20) {
        return const MoveLabel(LabelKind.great, 0.0);
      }
      return const MoveLabel(LabelKind.best, 0.0);
    }
    // Mate yang tersedia tapi tidak diambil.
    if (topIsMate && !playedStillMates) {
      return MoveLabel(LabelKind.miss, loss);
    }
    if (loss < 0.02) return MoveLabel(LabelKind.excellent, loss);
    if (loss < 0.05) return MoveLabel(LabelKind.good, loss);

    // Gagal memanfaatkan kesalahan lawan di langkah sebelumnya.
    final missedChance = epBefore >= 0.60 &&
        (prevOppKind == LabelKind.mistake || prevOppKind == LabelKind.blunder);
    if (loss < 0.10) {
      return MoveLabel(
          missedChance ? LabelKind.miss : LabelKind.inaccuracy, loss);
    }
    if (loss < 0.20) {
      return MoveLabel(missedChance ? LabelKind.miss : LabelKind.mistake, loss);
    }
    return MoveLabel(LabelKind.blunder, loss);
  }
}
