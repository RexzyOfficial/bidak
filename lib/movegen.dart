class MoveGen {
  /// Langkah pseudo-legal (belum cek skak) dari kotak [from].
  /// board: index 0=a8 ... 63=h1.
  static List<int> targets(List<String> board, int from) {
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
          if (onBoard(rr, ff) && isEnemy(rr * 8 + ff)) {
            out.add(rr * 8 + ff);
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
        break;
    }
    return out;
  }
}
