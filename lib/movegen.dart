class MoveGen {
  static int findKing(List<String> board, bool white) {
    final target = white ? 'K' : 'k';
    for (var i = 0; i < 64; i++) {
      if (board[i] == target) return i;
    }
    return -1;
  }

  static List<int> pseudoTargets(
    List<String> board,
    int from, {
    String castlingRights = '-',
    int? enPassantSquare,
  }) {
    final p = board[from];
    if (p == '.') return const [];
    final isWhite = p == p.toUpperCase();
    final type = p.toLowerCase();
    final f = from % 8;
    final r = from ~/ 8;
    final out = <int>[];

    bool onBoard(int rr, int ff) => rr >= 0 && rr < 8 && ff >= 0 && ff < 8;
    bool isEnemy(int idx) {
      final q = board[idx];
      if (q == '.') return false;
      return (q == q.toUpperCase()) != isWhite;
    }
    bool isEmpty(int idx) => board[idx] == '.';

    void slide(List<List<int>> dirs) {
      for (final d in dirs) {
        var rr = r + d[0];
        var ff = f + d[1];
        while (onBoard(rr, ff)) {
          final idx = rr * 8 + ff;
          if (isEmpty(idx)) {
            out.add(idx);
          } else {
            if (isEnemy(idx)) out.add(idx);
            break;
          }
          rr += d[0];
          ff += d[1];
        }
      }
    }

    switch (type) {
      case 'p':
        final dir = isWhite ? -1 : 1;
        final startRow = isWhite ? 6 : 1;
        if (onBoard(r + dir, f) && isEmpty((r + dir) * 8 + f)) {
          out.add((r + dir) * 8 + f);
          if (r == startRow && isEmpty((r + 2 * dir) * 8 + f)) {
            out.add((r + 2 * dir) * 8 + f);
          }
        }
        for (final df in [-1, 1]) {
          final rr = r + dir;
          final ff = f + df;
          if (!onBoard(rr, ff)) continue;
          final idx = rr * 8 + ff;
          if (isEnemy(idx)) out.add(idx);
          if (enPassantSquare != null && idx == enPassantSquare) {
            out.add(idx);
          }
        }
        break;
      case 'n':
        for (final d in const [
          [-2, -1], [-2, 1], [-1, -2], [-1, 2],
          [1, -2], [1, 2], [2, -1], [2, 1],
        ]) {
          final rr = r + d[0];
          final ff = f + d[1];
          if (!onBoard(rr, ff)) continue;
          final idx = rr * 8 + ff;
          if (isEmpty(idx) || isEnemy(idx)) out.add(idx);
        }
        break;
      case 'b':
        slide(const [
          [-1, -1], [-1, 1], [1, -1], [1, 1],
        ]);
        break;
      case 'r':
        slide(const [
          [-1, 0], [1, 0], [0, -1], [0, 1],
        ]);
        break;
      case 'q':
        slide(const [
          [-1, -1], [-1, 1], [1, -1], [1, 1],
          [-1, 0], [1, 0], [0, -1], [0, 1],
        ]);
        break;
      case 'k':
        for (var dr = -1; dr <= 1; dr++) {
          for (var df = -1; df <= 1; df++) {
            if (dr == 0 && df == 0) continue;
            final rr = r + dr;
            final ff = f + df;
            if (!onBoard(rr, ff)) continue;
            final idx = rr * 8 + ff;
            if (isEmpty(idx) || isEnemy(idx)) out.add(idx);
          }
        }
        if (isWhite) {
          if (castlingRights.contains('K') &&
              from == 60 &&
              board[61] == '.' &&
              board[62] == '.' &&
              board[63] == 'R') {
            out.add(62);
          }
          if (castlingRights.contains('Q') &&
              from == 60 &&
              board[59] == '.' &&
              board[58] == '.' &&
              board[57] == '.' &&
              board[56] == 'R') {
            out.add(58);
          }
        } else {
          if (castlingRights.contains('k') &&
              from == 4 &&
              board[5] == '.' &&
              board[6] == '.' &&
              board[7] == 'r') {
            out.add(6);
          }
          if (castlingRights.contains('q') &&
              from == 4 &&
              board[3] == '.' &&
              board[2] == '.' &&
              board[1] == '.' &&
              board[0] == 'r') {
            out.add(2);
          }
        }
        break;
    }
    return out;
  }

  static bool isAttacked(List<String> board, int idx, bool byWhite) {
    final r = idx ~/ 8;
    final f = idx % 8;

    final pawnDir = byWhite ? 1 : -1;
    for (final df in [-1, 1]) {
      final rr = r + pawnDir;
      final ff = f + df;
      if (rr >= 0 && rr < 8 && ff >= 0 && ff < 8) {
        final p = board[rr * 8 + ff];
        if (p == (byWhite ? 'P' : 'p')) return true;
      }
    }
    for (final d in const [
      [-2, -1], [-2, 1], [-1, -2], [-1, 2],
      [1, -2], [1, 2], [2, -1], [2, 1],
    ]) {
      final rr = r + d[0];
      final ff = f + d[1];
      if (rr >= 0 && rr < 8 && ff >= 0 && ff < 8) {
        final p = board[rr * 8 + ff];
        if (p == (byWhite ? 'N' : 'n')) return true;
      }
    }
    for (var dr = -1; dr <= 1; dr++) {
      for (var df = -1; df <= 1; df++) {
        if (dr == 0 && df == 0) continue;
        final rr = r + dr;
        final ff = f + df;
        if (rr >= 0 && rr < 8 && ff >= 0 && ff < 8) {
          final p = board[rr * 8 + ff];
          if (p == (byWhite ? 'K' : 'k')) return true;
        }
      }
    }
    for (final d in const [
      [-1, -1], [-1, 1], [1, -1], [1, 1],
    ]) {
      var rr = r + d[0];
      var ff = f + d[1];
      while (rr >= 0 && rr < 8 && ff >= 0 && ff < 8) {
        final p = board[rr * 8 + ff];
        if (p != '.') {
          if (p == (byWhite ? 'B' : 'b') || p == (byWhite ? 'Q' : 'q')) {
            return true;
          }
          break;
        }
        rr += d[0];
        ff += d[1];
      }
    }
    for (final d in const [
      [-1, 0], [1, 0], [0, -1], [0, 1],
    ]) {
      var rr = r + d[0];
      var ff = f + d[1];
      while (rr >= 0 && rr < 8 && ff >= 0 && ff < 8) {
        final p = board[rr * 8 + ff];
        if (p != '.') {
          if (p == (byWhite ? 'R' : 'r') || p == (byWhite ? 'Q' : 'q')) {
            return true;
          }
          break;
        }
        rr += d[0];
        ff += d[1];
      }
    }
    return false;
  }

  static bool isInCheck(List<String> board, bool white) {
    final king = findKing(board, white);
    if (king == -1) return false;
    return isAttacked(board, king, !white);
  }

  static List<String> apply(List<String> board, int from, int to, {String? promotion}) {
    final nb = [...board];
    final p = nb[from];
    final isWhite = p == p.toUpperCase();
    final type = p.toLowerCase();
    final f = from % 8;
    final tF = to % 8;
    final tR = to ~/ 8;

    if (type == 'p' && f != tF && board[to] == '.') {
      final capIdx = isWhite ? to + 8 : to - 8;
      if (capIdx >= 0 && capIdx < 64) nb[capIdx] = '.';
    }

    nb[to] = p;
    nb[from] = '.';

    if (type == 'k' && (to - from).abs() == 2) {
      if (to > from) {
        nb[to - 1] = nb[to + 1];
        nb[to + 1] = '.';
      } else {
        nb[to + 1] = nb[to - 2];
        nb[to - 2] = '.';
      }
    }

    if (type == 'p' && (tR == 0 || tR == 7)) {
      final promoChar = (promotion ?? 'q').toUpperCase();
      nb[to] = isWhite ? promoChar : promoChar.toLowerCase();
    }

    return nb;
  }

  static List<int> legalTargets(
    List<String> board,
    int from, {
    String castlingRights = '-',
    int? enPassantSquare,
  }) {
    final p = board[from];
    if (p == '.') return const [];
    final isWhite = p == p.toUpperCase();
    final pseudo = pseudoTargets(
      board,
      from,
      castlingRights: castlingRights,
      enPassantSquare: enPassantSquare,
    );
    final legal = <int>[];
    for (final to in pseudo) {
      if (p.toLowerCase() == 'k' && (to - from).abs() == 2) {
        final step = to > from ? 1 : -1;
        var blocked = false;
        for (var i = 1; i <= 2; i++) {
          final tb = apply(board, from, from + step * i);
          if (isInCheck(tb, isWhite)) {
            blocked = true;
            break;
          }
        }
        if (blocked) continue;
      }
      final test = apply(board, from, to);
      if (!isInCheck(test, isWhite)) legal.add(to);
    }
    return legal;
  }

  // Perbaikan: Cek apakah bidak yang bergerak benar-benar PION,
  // dan cek warnanya agar target baris promosi sesuai.
  static bool requiresPromotion(List<String> board, int from, int to) {
    final p = board[from];
    if (p == '.') return false;
    if (p.toLowerCase() != 'p') return false;
    
    final isWhite = p == p.toUpperCase();
    final tR = to ~/ 8;
    return (isWhite && tR == 0) || (!isWhite && tR == 7);
  }
}
