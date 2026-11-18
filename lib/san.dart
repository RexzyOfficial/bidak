import 'chess_types.dart';
import 'movegen.dart';

class San {
  static String normalize(String san) =>
      san.replaceAll('+', '').replaceAll('#', '');

  static String _file(int f) => String.fromCharCode(97 + f);

  static String generate(
    List<String> board,
    int from,
    int to, {
    String? promotion,
    String castlingRights = '-',
    int? enPassantSquare,
  }) {
    final p = board[from];
    final isWhite = p == p.toUpperCase();
    final type = p.toLowerCase();
    final f = from % 8;
    final r = from ~/ 8;
    final tF = to % 8;
    final tR = to ~/ 8;
    final isCapture = board[to] != '.' || (type == 'p' && f != tF);

    var san = '';
    if (type == 'k' && (to - from).abs() == 2) {
      san = to > from ? 'O-O' : 'O-O-O';
    } else {
      if (type != 'p') {
        san += p.toUpperCase();
        var ambiguous = false;
        var sameFile = false;
        var sameRank = false;
        for (var i = 0; i < 64; i++) {
          if (i == from || board[i] != p) continue;
          final t = MoveGen.legalTargets(board, i,
              castlingRights: castlingRights,
              enPassantSquare: enPassantSquare);
          if (!t.contains(to)) continue;
          ambiguous = true;
          if (i % 8 == f) sameFile = true;
          if (i ~/ 8 == r) sameRank = true;
        }
        if (ambiguous) {
          if (!sameFile) {
            san += _file(f);
          } else if (!sameRank) {
            san += '${8 - r}';
          } else {
            san += '${_file(f)}${8 - r}';
          }
        }
      } else if (isCapture) {
        san += _file(f);
      }
      if (isCapture) san += 'x';
      san += '${_file(tF)}${8 - tR}';
      if (promotion != null) san += '=${promotion.toUpperCase()}';
    }

    final nextBoard = MoveGen.apply(board, from, to, promotion: promotion);
    final nextWhite = !isWhite;
    if (MoveGen.isInCheck(nextBoard, nextWhite)) {
      int? newEp;
      if (type == 'p' && (to - from).abs() == 16) newEp = (from + to) ~/ 2;
      san += _hasLegal(nextBoard, nextWhite, newEp) ? '+' : '#';
    }
    return san;
  }

  static bool _hasLegal(List<String> board, bool white, int? ep) {
    for (var i = 0; i < 64; i++) {
      final q = board[i];
      if (q == '.' || (q == q.toUpperCase()) != white) continue;
      if (MoveGen.legalTargets(board, i,
              castlingRights: '-', enPassantSquare: ep)
          .isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  /// Semua langkah legal: kunci = SAN tanpa +/#.
  static Map<String, Move> legalMap(
    List<String> board,
    bool white, {
    String castlingRights = '-',
    int? enPassantSquare,
  }) {
    final out = <String, Move>{};
    for (var from = 0; from < 64; from++) {
      final p = board[from];
      if (p == '.' || (p == p.toUpperCase()) != white) continue;
      final targets = MoveGen.legalTargets(board, from,
          castlingRights: castlingRights, enPassantSquare: enPassantSquare);
      for (final to in targets) {
        if (MoveGen.requiresPromotion(board, from, to)) {
          for (final pr in const ['q', 'r', 'b', 'n']) {
            final s = generate(board, from, to,
                promotion: pr,
                castlingRights: castlingRights,
                enPassantSquare: enPassantSquare);
            out[normalize(s)] = Move(from, to, pr);
          }
        } else {
          final s = generate(board, from, to,
              castlingRights: castlingRights,
              enPassantSquare: enPassantSquare);
          out[normalize(s)] = Move(from, to);
        }
      }
    }
    return out;
  }
}
