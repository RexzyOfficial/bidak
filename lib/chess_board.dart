import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'game_controller.dart';
import 'move_labels.dart';
import 'movegen.dart';

class ChessBoardView extends StatelessWidget {
  final GameController c;
  const ChessBoardView({super.key, required this.c});

  Widget _badgeGlyph(LabelKind k, double size) {
    Widget txt(String s) => Text(
          s,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: size * 0.52,
            height: 1.0,
          ),
        );
    Widget ico(IconData i) => Icon(i, color: Colors.white, size: size * 0.62);
    return switch (k) {
      LabelKind.brilliant => txt('!!'),
      LabelKind.great => txt('!'),
      LabelKind.best => ico(Icons.star),
      LabelKind.excellent => ico(Icons.thumb_up),
      LabelKind.good => ico(Icons.check),
      LabelKind.book => ico(Icons.menu_book),
      LabelKind.inaccuracy => txt('?!'),
      LabelKind.mistake => txt('?'),
      LabelKind.blunder => txt('??'),
      LabelKind.miss => ico(Icons.close),
      LabelKind.forced => ico(Icons.arrow_forward),
    };
  }

  Widget _labelBadge(double sq) {
    final idx = c.moveHistory.length - 1;
    final move = c.lastMove;
    if (idx < 0 || idx >= c.labels.length || move == null) {
      return const SizedBox.shrink();
    }
    final lab = c.labels[idx];
    if (lab == null) return const SizedBox.shrink();

    var f = move.to % 8;
    var r = move.to ~/ 8;
    if (c.flipped) {
      f = 7 - f;
      r = 7 - r;
    }
    final size = sq * 0.44;
    final left =
        ((f + 1) * sq - size * 0.7).clamp(0.0, 8 * sq - size).toDouble();
    final top = (r * sq - size * 0.3).clamp(0.0, 8 * sq - size).toDouble();

    return Positioned(
      left: left,
      top: top,
      width: size,
      height: size,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: Color(lab.colorValue),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: sq * 0.02),
            boxShadow: const [
              BoxShadow(color: Color(0x66000000), blurRadius: 3),
            ],
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: EdgeInsets.all(size * 0.14),
                child: _badgeGlyph(lab.kind, size),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _pieceCode(String p) {
    final isWhite = p == p.toUpperCase();
    return '${isWhite ? 'w' : 'b'}${p.toUpperCase()}';
  }

  Future<void> _onTap(BuildContext context, int idx) async {
    final selected = c.selected;
    if (selected != null &&
        c.selectedTargets.contains(idx) &&
        MoveGen.requiresPromotion(c.board, selected, idx)) {
      final piece = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Promosi pion'),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final p in ['q', 'r', 'b', 'n'])
                    IconButton(
                      iconSize: 44,
                      onPressed: () => Navigator.pop(ctx, p),
                      icon: SvgPicture.asset(
                        'assets/pieces/${c.whiteToMove ? 'w' : 'b'}${p.toUpperCase()}.svg',
                        width: 44,
                        height: 44,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
      if (piece != null) c.applyPromotion(selected, idx, piece);
      return;
    }
    c.select(idx);
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
            if (c.flipped) {
              f = 7 - f;
              r = 7 - r;
            }
            _onTap(context, r * 8 + f);
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: _BoardPainter(c, sq)),
              ),
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
              // Panah di atas bidak
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _ArrowPainter(c, sq)),
                ),
              ),
              _labelBadge(sq),
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
    if (c.flipped) {
      f = 7 - f;
      r = 7 - r;
    }
    return Offset(f * sq + sq / 2, r * sq + sq / 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final light = Paint()..color = const Color(0xFFEFE3C8);
    final dark = Paint()..color = const Color(0xFFB58863);
    final sel = Paint()..color = const Color(0x66FFEB3B);
    final last = Paint()..color = const Color(0x4400BCD4);
    final check = Paint()..color = const Color(0xAAFF1744);

    final kingSquare = MoveGen.findKing(c.board, c.whiteToMove);
    final inCheck = MoveGen.isInCheck(c.board, c.whiteToMove);

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
        if (inCheck && idx == kingSquare) {
          canvas.drawCircle(rect.center, sq * 0.42, check);
        }
      }
    }

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
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) => true;
}

class _ArrowPainter extends CustomPainter {
  final GameController c;
  final double sq;
  _ArrowPainter(this.c, this.sq) : super(repaint: c);

  static const _gold = Color(0xF2F5B301);
  static const _black = Color(0xF2111111);
  static const _grey = Color(0xE69E9E9E);
  static const _whiteEdge = Color(0xCCFFFFFF);
  static const _darkEdge = Color(0x66000000);

  Offset _center(int idx) {
    var f = idx % 8;
    var r = idx ~/ 8;
    if (c.flipped) {
      f = 7 - f;
      r = 7 - r;
    }
    return Offset(f * sq + sq / 2, r * sq + sq / 2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final chosen = c.chosenMove;
    final chosenUci = chosen?.toUci();
    final others = c.lastLines
        .where((l) => l.move.toUci() != chosenUci)
        .toList()
      ..sort((a, b) => a.multipv.compareTo(b.multipv));

    // Urutan gambar: abu-abu (paling bawah), hitam, lalu gold di atas.
    if (others.length > 1) {
      _arrow(canvas, others[1].move.from, others[1].move.to, _grey, _darkEdge, 0.7);
    }
    if (others.isNotEmpty) {
      _arrow(canvas, others[0].move.from, others[0].move.to, _black, _whiteEdge, 0.85);
    }
    if (chosen != null) {
      _arrow(canvas, chosen.from, chosen.to, _gold, null, 1.0);
    }
  }

  void _arrow(Canvas canvas, int fromIdx, int toIdx, Color fill, Color? edge,
      double scale) {
    final from = _center(fromIdx);
    final to = _center(toIdx);
    final dir = to - from;
    final len = dir.distance;
    if (len < 1) return;
    final u = dir / len;
    final perp = Offset(-u.dy, u.dx);

    final start = from + u * (sq * 0.28);
    final tip = to - u * (sq * 0.18);
    final shaftHalf = sq * 0.065 * scale;
    final headLen = sq * 0.34 * scale;
    final headHalf = sq * 0.27 * scale;
    final neck = tip - u * headLen;

    final pts = <Offset>[
      start + perp * shaftHalf,
      neck + perp * shaftHalf,
      neck + perp * headHalf,
      tip,
      neck - perp * headHalf,
      neck - perp * shaftHalf,
      start - perp * shaftHalf,
    ];
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..color = fill
        ..style = PaintingStyle.fill,
    );
    if (edge != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = edge
          ..style = PaintingStyle.stroke
          ..strokeWidth = sq * 0.035
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ArrowPainter old) => true;
}
