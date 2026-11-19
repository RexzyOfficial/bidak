import 'dart:math';
import 'chess_types.dart';

class Humanizer {
  /// Seed stabil dari string (FNV-1a), supaya posisi yang sama
  /// selalu menghasilkan pilihan yang sama.
  static int seedFrom(String s) {
    var h = 0x811C9DC5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  // Skor SELALU dari sudut pandang pihak yang jalan (sama seperti UCI).
  int _score(EngineLine l) {
    if (l.isMate) {
      final m = l.mateIn;
      return m > 0 ? 100000 - m : -100000 - m;
    }
    return l.scoreCp;
  }

  Move pick(
    List<EngineLine> lines, {
    required double blunderChance,
    required int seed,
  }) {
    if (lines.isEmpty) throw StateError('no lines');
    final rng = Random(seed);
    final sorted = [...lines]..sort((a, b) => a.multipv.compareTo(b.multipv));
    final top = sorted.first;
    if (sorted.length < 2) return top.move;

    final topScore = _score(top);
    // Lagi punya jalur mat: selalu ambil yang terbaik.
    if (topScore > 90000) return top.move;

    // Kesalahan manusiawi. Coba rentang selisih berurutan:
    // 40-150 cp, lalu 15-39 cp (lebih ringan), lalu 151-250 cp (lebih parah).
    // Sisi yang sudah tertinggal (< -1.5) tidak boleh blunder lagi.
    if (rng.nextDouble() < blunderChance && topScore >= -150) {
      for (final t in const [
        [40, 150],
        [15, 39],
        [151, 250],
      ]) {
        final cands = sorted.skip(1).where((l) {
          final s = _score(l);
          if (s.abs() > 90000) return false; // jangan pilih jalur mat
          final gap = topScore - s;
          if (gap < t[0] || gap > t[1]) return false;
          // jangan jatuhkan posisi yang masih oke jadi buruk
          if (s < -150 && topScore >= -150) return false;
          return true;
        }).toList();
        if (cands.isNotEmpty) return cands[rng.nextInt(cands.length)].move;
      }
    }

    // Variasi natural: kadang pilih langkah yang nyaris setara (<=25 cp).
    final near = sorted.skip(1).where((l) {
      final s = _score(l);
      return s.abs() <= 90000 && topScore - s <= 25;
    }).toList();
    if (near.isNotEmpty && rng.nextDouble() < 0.35) {
      return near[rng.nextInt(near.length)].move;
    }
    return top.move;
  }
}
