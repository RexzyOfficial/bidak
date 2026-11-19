import 'dart:math';
import 'package:flutter/services.dart';
import 'chess_types.dart';
import 'movegen.dart';

class _BookMove {
  final Move move;
  final int weight;
  _BookMove(this.move, this.weight);
}

class OpeningBook {
  // Kunci: 4 field pertama FEN (susunan bidak, giliran, rokade, en passant).
  final Map<String, List<_BookMove>> _book = {};
  bool _loaded = false;

  // Makin kecil = makin merata, 1.0 = persis sesuai popularitas.
  static const double _weightPower = 0.7;

  int get size => _book.length;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    String raw;
    try {
      raw = await rootBundle.loadString('assets/book/gm2001.tsv');
    } catch (_) {
      return;
    }
    for (final rawLine in raw.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final tab = line.indexOf('\t');
      if (tab < 0) continue;
      final key = line.substring(0, tab);
      final moves = <_BookMove>[];
      for (final tok in line.substring(tab + 1).split(' ')) {
        final c = tok.indexOf(':');
        if (c < 4) continue;
        final m = Move.fromUci(tok.substring(0, c));
        final w = int.tryParse(tok.substring(c + 1)) ?? 0;
        if (m != null && w > 0) moves.add(_BookMove(m, w));
      }
      if (moves.isNotEmpty) _book[key] = moves;
    }
  }

  Move? getMove(
    String fen,
    List<String> board, {
    required bool whiteToMove,
    required String castlingRights,
    int? enPassantSquare,
    required Random rng,
  }) {
    final key = fen.split(' ').take(4).join(' ');
    final cands = _book[key];
    if (cands == null || cands.isEmpty) return null;

    final moves = <Move>[];
    final weights = <double>[];
    var total = 0.0;
    for (final c in cands) {
      final p = board[c.move.from];
      if (p == '.' || (p == p.toUpperCase()) != whiteToMove) continue;
      final legal = MoveGen.legalTargets(
        board,
        c.move.from,
        castlingRights: castlingRights,
        enPassantSquare: enPassantSquare,
      );
      if (!legal.contains(c.move.to)) continue;
      final w = pow(c.weight.toDouble(), _weightPower).toDouble();
      moves.add(c.move);
      weights.add(w);
      total += w;
    }
    if (moves.isEmpty) return null;

    var roll = rng.nextDouble() * total;
    for (var i = 0; i < moves.length; i++) {
      roll -= weights[i];
      if (roll <= 0) return moves[i];
    }
    return moves.last;
  }
}
