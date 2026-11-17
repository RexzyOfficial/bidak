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
          title: const Text('Bidak'),
          actions: [
            IconButton(
              icon: const Icon(Icons.flip),
              tooltip: 'flip',
              onPressed: _c.flip,
            ),
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'undo',
              onPressed: _c.undo,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'reset',
              onPressed: _c.reset,
            ),
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

  String _fmt(int cp) {
    final s = cp >= 0 ? '+$cp' : '$cp';
    return '$s cp';
  }

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
      return const Center(
        child: Text('jalan satu langkah untuk melihat saran'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: c.lastLines.length,
      itemBuilder: (context, i) {
        final l = c.lastLines[i];
        final move = l.move.toUci();
        final score = l.isMate ? 'mate ${l.mateIn}' : _fmt(l.scoreCp);
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 14,
            child: Text('${l.multipv}', style: const TextStyle(fontSize: 12)),
          ),
          title: Text(move, style: const TextStyle(fontFamily: 'monospace')),
          subtitle: Text('depth ${l.depth} · $score'),
        );
      },
    );
  }
}
