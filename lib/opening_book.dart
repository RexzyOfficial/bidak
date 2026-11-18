import 'package:flutter/services.dart';
import 'chess_types.dart';
import 'movegen.dart';

class OpeningBook {
  // Key: history SAN (misal "e4 c5 Nf3"), Value: list SAN selanjutnya
  final Map<String, List<String>> _book = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final raw = await rootBundle.loadString('assets/book/openings.tsv');
    final lines = raw.split('\n');
    
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final parts = line.split('\t');
      if (parts.length < 3) continue;
      
      // parts[2] adalah PGN string (contoh: "e4 c5 Nf3")
      final pgnMoves = parts[2].trim().split(' ');
      if (pgnMoves.length < 2) continue;
      
      final history = pgnMoves.sublist(0, pgnMoves.length - 1).join(' ');
      final nextMove = pgnMoves.last;
      
      _book.putIfAbsent(history, () => []).add(nextMove);
    }
    _loaded = true;
  }

  /// Cari langkah dari buku. Mengembalikan null jika tidak ada.
  Move? getMove(List<String> sanHistory, List<String> board) {
    final historyKey = sanHistory.join(' ');
    final candidates = _book[historyKey];
    if (candidates == null || candidates.isEmpty) return null;

    // Pilih acak dari kandidat yang ada di buku
    candidates.shuffle();
    for (final san in candidates) {
      final move = _sanToMove(san, board, sanHistory.length % 2 == 0);
      if (move != null) return move;
    }
    return null;
  }

  Move? _sanToMove(String san, List<String> board, bool weAreWhite) {
    // Bersihkan anotasi skak dan skakmat
    final clean = san.replaceAll('+', '').replaceAll('#', '');
    
    for (var from = 0; from < 64; from++) {
      final p = board[from];
      if (p == '.') continue;
      if ((p == p.toUpperCase()) != weAreWhite) continue;
      
      final targets = MoveGen.legalTargets(board, from);
      for (final to in targets) {
        final f = to % 8;
        final r = 8 - (to ~/ 8);
        final sq = '${String.fromCharCode(97 + f)}$r';
        
        // Cocokkan tujuan dan tipe bidak
        if (!clean.contains(sq)) continue;
        
        final type = p.toLowerCase();
        if (type != 'p') {
          final pieceChar = type.toUpperCase();
          if (!clean.contains(pieceChar)) continue;
        }
        
        // Jika cocok, ini langkahnya
        String? promo;
        if (clean.contains('=')) {
          promo = clean.split('=').last.toLowerCase();
        }
        return Move(from, to, promo);
      }
    }
    return null;
  }
}
