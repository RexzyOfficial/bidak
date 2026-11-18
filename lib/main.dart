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
    _c.initEngine().catchError((e) {
      debugPrint('engine init gagal: $e');
    });
  }

  @override
  void dispose() {
    _engine.dispose();
    super.dispose();
  }

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
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
                  Text('Depth Mesin: ${_c.engineDepth}'),
                  Slider(
                    value: _c.engineDepth.toDouble(),
                    min: 6,
                    max: 14,
                    divisions: 8,
                    onChanged: (v) {
                      setModalState(() => _c.engineDepth = v.round());
                      _c.updateSettings(_c.engineDepth, _c.blunderChance, _c.maxThinkDelayMs);
                    },
                  ),
                  Text('Peluang Blunder: ${(_c.blunderChance * 100).toStringAsFixed(1)}%'),
                  Slider(
                    value: _c.blunderChance,
                    min: 0,
                    max: 0.15,
                    divisions: 15,
                    onChanged: (v) {
                      setModalState(() => _c.blunderChance = v);
                      _c.updateSettings(_c.engineDepth, _c.blunderChance, _c.maxThinkDelayMs);
                    },
                  ),
                  Text('Jeda Maksimal: ${_c.maxThinkDelayMs} ms'),
                  Slider(
                    value: _c.maxThinkDelayMs.toDouble(),
                    min: 1000,
                    max: 5000,
                    divisions: 8,
                    onChanged: (v) {
                      setModalState(() => _c.maxThinkDelayMs = v.round());
                      _c.updateSettings(_c.engineDepth, _c.blunderChance, _c.maxThinkDelayMs);
                    },
                  ),
                ],
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
                        style: const TextStyle(fontSize: 13, color: Color(0xFFFFAB40)),
                      ),
                    ),
                  ],
                );
              }
              return const Text('Bidak');
            },
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _showSettings,
            ),
            IconButton(icon: const Icon(Icons.flip), onPressed: _c.flip),
            IconButton(icon: const Icon(Icons.undo), onPressed: _c.undo),
            IconButton(icon: const Icon(Icons.refresh), onPressed: _c.reset),
          ],
        ),
        body: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            return Column(
              children: [
                Expanded(
                  flex: 6,
                  child: Column(
                    children: [
                      _EvalBar(c: _c),
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
                      _MoveHistory(c: _c),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: _SuggestionPanel(c: _c),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EvalBar extends StatelessWidget {
  final GameController c;
  const _EvalBar({required this.c});

  @override
  Widget build(BuildContext context) {
    final pct = c.whiteEvalPercentage;
    return Container(
      height: 10,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                alignment: Alignment.centerLeft,
                widthFactor: pct,
                child: Container(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MoveHistory extends StatelessWidget {
  final GameController c;
  const _MoveHistory({required this.c});

  @override
  Widget build(BuildContext context) {
    if (c.moveHistory.isEmpty) return const SizedBox(height: 40);

    return Container(
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        reverse: true,
        itemCount: (c.moveHistory.length + 1) ~/ 2,
        itemBuilder: (context, i) {
          final idx = c.moveHistory.length - 1 - (i * 2);
          final bIdx = idx - 1;
          final wIdx = idx;

          String w = '';
          String b = '';
          
          if (wIdx % 2 == 0) {
            w = c.moveHistory[wIdx];
            if (bIdx >= 0) b = c.moveHistory[bIdx];
          } else {
            w = c.moveHistory[wIdx];
            if (bIdx >= 0) b = c.moveHistory[bIdx];
          }

          // Sesuaikan urutan putih/hitam jika panjang ganjil/genap
          final moveNum = (wIdx ~/ 2) + 1;
          final isWhiteMove = wIdx % 2 == 0;
          
          String text = '$moveNum. ';
          if (isWhiteMove) {
             text += w;
             if (bIdx >= 0) text += ' $b';
          } else {
             text += '... $w';
          }

          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                text,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SuggestionPanel extends StatelessWidget {
  final GameController c;
  const _SuggestionPanel({required this.c});

  String _fmt(int cp) => '${cp >= 0 ? '+$cp' : '$cp'} cp';

  @override
  Widget build(BuildContext context) {
    if (!c.engineReady) {
      return const Center(child: Text('engine memuat...'));
    }
    if (c.thinking) {
      return const Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('engine berpikir...'),
          ],
        ),
      );
    }
    if (c.lastLines.isEmpty) {
      return Center(
        child: Text(c.gameOver
            ? c.status
            : 'jalan satu langkah untuk melihat saran'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: c.lastLines.length,
      itemBuilder: (context, i) {
        final l = c.lastLines[i];
        final score = l.isMate ? 'mate ${l.mateIn}' : _fmt(l.scoreCp);
        final isChosen =
            c.chosenMove != null && l.move.toUci() == c.chosenMove!.toUci();
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 14,
            backgroundColor: isChosen ? const Color(0xFFF5B301) : null,
            child: Text(
              '${l.multipv}',
              style: TextStyle(
                fontSize: 12,
                color: isChosen ? Colors.black : null,
                fontWeight: isChosen ? FontWeight.bold : null,
              ),
            ),
          ),
          title: Text(
            l.move.toUci(),
            style: TextStyle(
              fontFamily: 'monospace',
              fontWeight: isChosen ? FontWeight.bold : null,
            ),
          ),
          subtitle: Text('depth ${l.depth} · $score'),
        );
      },
    );
  }
}
