import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'game_controller.dart';

class ChessBoardView extends StatelessWidget {
  final GameController c;
  const ChessBoardView({super.key, required this.c});

  String _pieceCode(String p) {
    final isWhite = p == p.toUpperCase();
    final prefix = isWhite ? 'w' : 'b';
    return '$prefix${p.toUpperCase()}';
  }

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
          child: Stack(
            children: [
              // Layer 1: Papan, titik, dan panah.
              Positioned.fill(
                child: CustomPaint(painter: _BoardPainter(c, sq)),
              ),
              // Layer 2: Bidak SVG.
              for (var i = 0; i < 64; i++)
                if (c.board[i] != '.')
                  Positioned(
                    left: (c.flipped ? 7 - (i % 8) : (i % 8)) * sq,
                    top: (c.flipped ? 7 - (i ~/ 8) : (i ~/ 8)) * sq,
                    width: sq,
                    height: sq,
                    child: IgnorePointer(
                      child: Padding(
                        padding: EdgeInsets.all(sq * 0.04),
                        child: SvgPicture.asset(
                          'assets/pieces/${_pieceCode(c.board[i])}.svg',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      );
    });
  }
}

class _BoardPainter extends CustomPainter {
  final GameController c;
  final double sq;
  _BoardPainter(this.c, this.sq) : super(repaint: c);

  Offset _center(int idx) {
    var f = idx % 8;
    var r = idx ~/ 8;
    if (c.flipped) { f = 7 - f; r = 7 - r; }
    return Offset(f * sq + sq / 2, r * sq + sq / 2);
  }

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
      }
    }

    // Titik langkah legal.
    for (final idx in c.selectedTargets) {
      final center = _center(idx);
      final isCapture = c.board[idx] != '.';
      if (isCapture) {
        canvas.drawCircle(
          center,
          sq * 0.42,
          Paint()
            ..color = const Color(0x77000000)
            ..style = PaintingStyle.stroke
            ..strokeWidth = sq * 0.08,
        );
      } else {
        canvas.drawCircle(
          center,
          sq * 0.14,
          Paint()..color = const Color(0x77000000),
        );
      }
    }

    // Panah saran engine.
    if (c.lastLines.isNotEmpty) {
      final colors = [
        const Color(0xFF8D6E63), // mpv3 bronze
        const Color(0xFF90A4AE), // mpv2 silver
        const Color(0xFFF5B301), // mpv1 gold
      ];
      final sorted = [...c.lastLines]
        ..sort((a, b) => b.multipv.compareTo(a.multipv));
      for (final line in sorted) {
        final colorIdx = line.multipv - 1;
        if (colorIdx < 0 || colorIdx >= colors.length) continue;
        _drawArrow(
          canvas,
          _center(line.move.from),
          _center(line.move.to),
          colors[colorIdx],
          sq,
          line.multipv == 1 ? 1.0 : 0.75,
        );
      }
    }
  }

  void _drawArrow(Canvas canvas, Offset from, Offset to, Color color,
      double sq, double scale) {
    final dir = to - from;
    final len = dir.distance;
    if (len < 1) return;
    final unit = dir / len;
    final start = from + unit * (sq * 0.30);
    final end = to - unit * (sq * 0.34);
    final stroke = sq * 0.12 * scale;

    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = color.withOpacity(0.85)
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );

    final headLen = sq * 0.30 * scale;
    final headWidth = sq * 0.22 * scale;
    final perp = Offset(-unit.dy, unit.dx);
    final p1 = end;
    final p2 = end - unit * headLen + perp * headWidth;
    final p3 = end - unit * headLen - perp * headWidth;
    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withOpacity(0.85)
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) => true;
}
