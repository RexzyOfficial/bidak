import 'dart:math';
import 'package:flutter/material.dart';
import 'game_controller.dart';

class ChessBoardView extends StatelessWidget {
  final GameController c;
  const ChessBoardView({super.key, required this.c});

  static const _glyphs = {
    'P': '♙', 'N': '♘', 'B': '♗', 'R': '♖', 'Q': '♕', 'K': '♔',
    'p': '♟', 'n': '♞', 'b': '♝', 'r': '♜', 'q': '♛', 'k': '♚',
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final side = min(constraints.maxWidth, constraints.maxHeight);
      final sq = side / 8;
      return SizedBox(
        width: side,
        height: side,
        child: GestureDetector(
          onTapDown: (d) {
            final local = d.localPosition;
            var f = (local.dx / sq).floor().clamp(0, 7);
            var r = (local.dy / sq).floor().clamp(0, 7);
            if (c.flipped) { f = 7 - f; r = 7 - r; }
            c.select(r * 8 + f);
          },
          child: CustomPaint(painter: _BoardPainter(c, _glyphs, sq)),
        ),
      );
    });
  }
}

class _BoardPainter extends CustomPainter {
  final GameController c;
  final Map<String, String> glyphs;
  final double sq;
  _BoardPainter(this.c, this.glyphs, this.sq) : super(repaint: c);

  @override
  void paint(Canvas canvas, Size size) {
    final light = Paint()..color = const Color(0xFFEFE3C8);
    final dark = Paint()..color = const Color(0xFFB58863);
    final sel = Paint()..color = const Color(0x66FFEB3B);
    final last = Paint()..color = const Color(0x4400BCD4);

    for (var r = 0; r < 8; r++) {
      for (var f = 0; f < 8; f++) {
        final idx = r * 8 + f;
        final df = c.flipped ? 7 - f : f;
        final dr = c.flipped ? 7 - r : r;
        final rect = Rect.fromLTWH(df * sq, dr * sq, sq, sq);
        canvas.drawRect(rect, (r + f) % 2 == 0 ? light : dark);
        if (c.lastMove != null &&
            (c.lastMove!.from == idx || c.lastMove!.to == idx)) {
          canvas.drawRect(rect, last);
        }
        if (c.selected == idx) {
          canvas.drawRect(rect, sel);
        }
        final p = c.board[idx];
        if (p == '.') continue;
        final tp = TextPainter(
          text: TextSpan(
            text: glyphs[p] ?? p,
            style: TextStyle(
              fontSize: sq * 0.78,
              color: p == p.toUpperCase() ? Colors.white : Colors.black,
              height: 1.0,
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        )..layout(maxWidth: sq);
        final off = Offset(
          df * sq + (sq - tp.width) / 2,
          dr * sq + (sq - tp.height) / 2,
        );
        tp.paint(canvas, off);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) => true;
}
