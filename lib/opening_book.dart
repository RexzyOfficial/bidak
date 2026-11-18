import 'dart:math';
import 'package:flutter/services.dart';
import 'chess_types.dart';
import 'san.dart';

class OpeningBook {
  // Kunci: riwayat SAN tanpa +/# (mis. "e4 e5 Nf3"), nilai: langkah berikutnya.
  final Map<String, List<String>> _book = {};
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
      if (moves.isEmpty) continue;
      final key = moves.sublist(0, moves.length - 1).join(' ');
      _book.putIfAbsent(key, () => []).add(moves.last);
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
    final cands = _book[key];
    if (cands == null || cands.isEmpty) return null;

    final legal = San.legalMap(board, whiteToMove,
        castlingRights: castlingRights, enPassantSquare: enPassantSquare);
    final valid = <Move>[];
    for (final s in cands) {
      final m = legal[s];
      if (m != null) valid.add(m);
    }
    if (valid.isEmpty) return null;
    return valid[rng.nextInt(valid.length)];
  }
}
