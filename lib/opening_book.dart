import 'dart:math';
import 'package:flutter/services.dart';
import 'chess_types.dart';
import 'san.dart';

class OpeningBook {
  // Kunci: riwayat SAN tanpa +/# (mis. "e4 e5 Nf3").
  // Nilai: langkah berikutnya -> jumlah baris opening yang melewatinya.
  final Map<String, Map<String, int>> _book = {};
  bool _loaded = false;

  int get size => _book.length;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    String raw;
    try {
      raw = await rootBundle.loadString('assets/book/openings.tsv');
    } catch (_) {
      return;
    }
    for (final rawLine in raw.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final parts = line.split('\t');
      if (parts.length < 3 || parts[0] == 'eco') continue;

      final moves = <String>[];
      for (final t in parts[2].trim().split(RegExp(r'\s+'))) {
        // buang nomor langkah: "1." atau "1.e4"
        final s = t.replaceFirst(RegExp(r'^\d+\.+'), '');
        if (s.isEmpty) continue;
        moves.add(San.normalize(s));
      }

      // Setiap langkah di baris ini menambah hitungan di posisinya.
      final prefix = <String>[];
      for (final m in moves) {
        final bucket = _book.putIfAbsent(prefix.join(' '), () => {});
        bucket[m] = (bucket[m] ?? 0) + 1;
        prefix.add(m);
      }
    }
  }

  Move? getMove(
    List<String> sanHistory,
    List<String> board, {
    required bool whiteToMove,
    required String castlingRights,
    int? enPassantSquare,
    required Random rng,
  }) {
    final key = sanHistory.map(San.normalize).join(' ');
    final bucket = _book[key];
    if (bucket == null || bucket.isEmpty) return null;

    final legal = San.legalMap(board, whiteToMove,
        castlingRights: castlingRights, enPassantSquare: enPassantSquare);

    final moves = <Move>[];
    final weights = <double>[];
    var total = 0.0;
    bucket.forEach((san, count) {
      final m = legal[san];
      if (m == null) return;
      final w = sqrt(count.toDouble());
      moves.add(m);
      weights.add(w);
      total += w;
    });
    if (moves.isEmpty) return null;

    var roll = rng.nextDouble() * total;
    for (var i = 0; i < moves.length; i++) {
      roll -= weights[i];
      if (roll <= 0) return moves[i];
    }
    return moves.last;
  }
}
