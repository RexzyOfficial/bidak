import 'dart:math';
import 'chess_types.dart';

class Humanizer {
  final Random _rng = Random();

  Move pick(List<EngineLine> lines,
      {required bool weAreWhite, int evalThresholdCp = 300}) {
    if (lines.isEmpty) throw StateError('no lines');
    final sorted = [...lines]..sort((a, b) => a.multipv.compareTo(b.multipv));
    final top = sorted.first;
    final topEval = _signedEval(top, weAreWhite);

    if (topEval > evalThresholdCp &&
        sorted.length >= 2 &&
        _rng.nextDouble() < 0.05) {
      final alt = sorted.skip(1).where((l) {
        final e = _signedEval(l, weAreWhite);
        return (topEval - e).abs() < 80;
      }).toList();
      if (alt.isNotEmpty) {
        return alt[_rng.nextInt(alt.length)].move;
      }
    }

    const weights = [0.60, 0.30, 0.10];
    final n = min(sorted.length, weights.length);
    final w = weights.sublist(0, n);
    final total = w.reduce((a, b) => a + b);
    var roll = _rng.nextDouble() * total;
    for (var i = 0; i < n; i++) {
      roll -= w[i];
      if (roll <= 0) return sorted[i].move;
    }
    return top.move;
  }

  int _signedEval(EngineLine l, bool weAreWhite) {
    if (l.isMate) {
      final m = l.mateIn;
      final signed = m > 0 ? 100000 - m * 100 : -100000 - m * 100;
      return weAreWhite ? signed : -signed;
    }
    return weAreWhite ? l.scoreCp : -l.scoreCp;
  }

  Duration thinkDelay({required int pieceCount, required bool inCheck}) {
    var base = 800 + _rng.nextInt(1700);
    if (inCheck) base += 400 + _rng.nextInt(800);
    if (pieceCount > 24) base += 200 + _rng.nextInt(600);
    return Duration(milliseconds: base);
  }
}
