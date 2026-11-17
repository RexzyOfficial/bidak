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
                          fontSize: 13,
                          color: Color(0xFFFFAB40),
                        ),
                      ),
                    ),
                  ],
                );
              }
              return const Text('Bidak');
            },
          ),
          actions: [
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
