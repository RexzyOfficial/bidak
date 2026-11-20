import 'package:flutter/material.dart';
import 'chess_board.dart';
import 'game_controller.dart';
import 'stockfish_ffi.dart';

void main() {
  runApp(const BidakApp());
}

class BidakApp extends StatefulWidget {
  const BidakApp({super.key});
  @override
  State<BidakApp> createState() => _BidakAppState();
}

class _BidakAppState extends State<BidakApp> {
  final StockfishFfi _engine = StockfishFfi();
  late final GameController _c = GameController(_engine);

  @override
  void initState() {
    super.initState();
    _c.loadSettings();
    _c.initEngine().catchError((e) {
      debugPrint('engine init gagal: $e');
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _engine.dispose();
    super.dispose();
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Pengaturan Humanisasi',
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    Text(
                        'Peluang Blunder: ${(_c.blunderChance * 100).toStringAsFixed(0)}%'),
                    Slider(
                      value: _c.blunderChance,
                      min: 0,
                      max: GameController.maxBlunder,
                      divisions: 25,
                      onChanged: (v) {
                        setModalState(() {});
                        _c.setBlunderChance(v);
                      },
                      onChangeEnd: (_) => _c.saveSettings(),
                    ),
                    const Text(
                      'Kadang sengaja memilih langkah ke-2 atau ke-3 yang lebih lemah. Makin tinggi, makin sering dan makin parah. 0% = selalu langkah terbaik.',
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB58863),
          brightness: Brightness.dark,
        ),
      ),
      home: Scaffold(
        appBar: AppBar(
          title: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              if (_c.status.isNotEmpty) {
                return Row(
                  children: [
                    const Text('Bidak'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _c.status,
                        style: const TextStyle(
                            fontSize: 13, color: Color(0xFFFFAB40)),
                      ),
                    ),
                  ],
                );
              }
              return const Text('Bidak');
            },
          ),
          actions: [
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.settings),
                onPressed: () => _showSettings(ctx),
              ),
            ),
            IconButton(icon: const Icon(Icons.flip), onPressed: _c.flip),
            IconButton(icon: const Icon(Icons.undo), onPressed: _c.undo),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _c.reset),
          ],
        ),
        body: SafeArea(
          top: false,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              return LayoutBuilder(builder: (context, cons) {
                final wide = cons.maxWidth >= cons.maxHeight * 1.2;
                return wide ? _wide() : _narrow();
              });
            },
          ),
        ),
      ),
    );
  }

  Widget _narrow() {
    return Column(
      children: [
        _EvalBar(c: _c, vertical: false),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: ChessBoardView(c: _c),
              ),
            ),
          ),
        ),
        _InfoRow(c: _c),
        _MoveHistory(c: _c, vertical: false),
      ],
    );
  }

  Widget _wide() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _EvalBar(c: _c, vertical: true),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Center(
              child: AspectRatio(
                aspectRatio: 1,
                child: ChessBoardView(c: _c),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 170,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InfoRow(c: _c),
                const SizedBox(height: 8),
                Expanded(child: _MoveHistory(c: _c, vertical: true)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EvalBar extends StatelessWidget {
  final GameController c;
  final bool vertical;
  const _EvalBar({required this.c, required this.vertical});

  @override
  Widget build(BuildContext context) {
    final pct = c.whiteEvalPercentage;
    final flipped = c.flipped;
    final Alignment align = vertical
        ? (flipped ? Alignment.topCenter : Alignment.bottomCenter)
        : (flipped ? Alignment.centerRight : Alignment.centerLeft);

    return Container(
      width: vertical ? 14 : null,
      height: vertical ? null : 10,
      margin: vertical
          ? const EdgeInsets.fromLTRB(8, 8, 0, 8)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: Colors.white24, width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Stack(
          children: [
            Positioned.fill(child: Container(color: Colors.black)),
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: align,
                widthFactor: vertical ? null : pct,
                heightFactor: vertical ? pct : null,
                child: Container(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final GameController c;
  const _InfoRow({required this.c});

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(fontSize: 12, color: Colors.white70);
    Widget status;
    if (!c.engineReady) {
      status = const Text('engine memuat...', style: small);
    } else if (c.thinking) {
      status = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 8),
          Text('berpikir...', style: small),
        ],
      );
    } else if (c.fromBook && c.chosenMove != null) {
      status = const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.menu_book, size: 14, color: Color(0xFFF5B301)),
          SizedBox(width: 6),
          Text('opening book', style: small),
        ],
      );
    } else if (c.isMistake) {
      status = Text(
        'blunder #${c.chosenRank} (-${(c.chosenLoss / 100).toStringAsFixed(1)})',
        style: const TextStyle(fontSize: 12, color: Color(0xFFFFAB40)),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    } else if (c.moveHistory.isEmpty && !c.gameOver) {
      status = const Text(
        'jalan satu langkah untuk melihat saran',
        style: small,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      );
    } else {
      status = const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Text(
            c.evalText,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Align(alignment: Alignment.centerLeft, child: status),
          ),
        ],
      ),
    );
  }
}

class _MoveHistory extends StatelessWidget {
  final GameController c;
  final bool vertical;
  const _MoveHistory({required this.c, required this.vertical});

  InlineSpan _san(int idx, TextStyle style) {
    final san = c.moveHistory[idx];
    final lab = idx < c.labels.length ? c.labels[idx] : null;
    return TextSpan(
      children: <InlineSpan>[
        TextSpan(text: san, style: style),
        if (lab != null)
          TextSpan(
            text: ' ●',
            style: style.copyWith(color: Color(lab.colorValue), fontSize: 11),
          ),
      ],
    );
  }

  List<Widget> _items(TextStyle style) {
    final items = <Widget>[];
    for (var i = 0; i < c.moveHistory.length; i += 2) {
      final moveNum = (i ~/ 2) + 1;
      final hasBlack = i + 1 < c.moveHistory.length;
      items.add(
        Text.rich(
          TextSpan(
            children: <InlineSpan>[
              TextSpan(text: '$moveNum. ', style: style),
              _san(i, style),
              if (hasBlack) TextSpan(text: ' ', style: style),
              if (hasBlack) _san(i + 1, style),
            ],
          ),
        ),
      );
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontFamily: 'monospace', fontSize: 13);
    final items = _items(style);
    final deco = BoxDecoration(
      color: Colors.black26,
      borderRadius: BorderRadius.circular(8),
    );

    if (vertical) {
      return Container(
        decoration: deco,
        child: ListView.builder(
          reverse: true,
          padding: const EdgeInsets.all(8),
          itemCount: items.length,
          itemBuilder: (context, i) => items[items.length - 1 - i],
        ),
      );
    }

    return Container(
      height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: deco,
      child: items.isEmpty
          ? null
          : ListView.builder(
              scrollDirection: Axis.horizontal,
              reverse: true,
              itemCount: items.length,
              itemBuilder: (context, i) => Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: items[items.length - 1 - i],
                ),
              ),
            ),
    );
  }
}
