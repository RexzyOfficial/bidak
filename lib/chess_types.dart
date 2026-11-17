// Representasi papan: 64 kotak, index 0 = a8 ... 63 = h1.
// Piece: 'P','N','B','R','Q','K' putih; huruf kecil = hitam; '.' kosong.

class Move {
  final int from;
  final int to;
  final String? promotion; // 'q','r','b','n' atau null
  Move(this.from, this.to, [this.promotion]);

  String toUci() {
    String sq(int i) {
      final f = i % 8;          // 0=a ... 7=h
      final r = 8 - (i ~/ 8);   // 8..1
      return '${String.fromCharCode(97 + f)}$r';
    }
    return '${sq(from)}${sq(to)}${promotion ?? ''}';
  }

  static Move? fromUci(String uci) {
    if (uci.length < 4) return null;
    int sq(String s) {
      final f = s.codeUnitAt(0) - 97;
      final r = 8 - int.parse(s[1]);
      return r * 8 + f;
    }
    final from = sq(uci.substring(0, 2));
    final to = sq(uci.substring(2, 4));
    final promo = uci.length > 4 ? uci[4] : null;
    return Move(from, to, promo);
  }
}

class EngineLine {
  final int multipv;
  final int depth;
  final int scoreCp; // centipawn
  final bool isMate;
  final int mateIn;
  final Move move;
  EngineLine({
    required this.multipv,
    required this.depth,
    required this.scoreCp,
    required this.isMate,
    required this.mateIn,
    required this.move,
  });
}
