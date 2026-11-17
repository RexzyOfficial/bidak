import 'package:flutter/material.dart';
import 'stockfish_ffi.dart';
import 'chess_types.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: EngineTestPage(),
  ));
}

class EngineTestPage extends StatefulWidget {
  const EngineTestPage({super.key});
  @override
  State<EngineTestPage> createState() => _EngineTestPageState();
}

class _EngineTestPageState extends State<EngineTestPage> {
  final StockfishFfi _engine = StockfishFfi();
  final StringBuffer _log = StringBuffer();
  bool _inited = false;
  bool _busy = false;

  void _add(String s) {
    setState(() => _log.writeln(s));
  }

  Future<void> _init() async {
    setState(() => _busy = true);
    try {
      await _engine.init(nnuePath: '');
      _inited = true;
      _add('engine: init ok');
    } catch (e) {
      _add('engine: init FAILED: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _test() async {
    if (!_inited) {
      _add('engine belum init');
      return;
    }
    setState(() => _busy = true);
    try {
      const startFen =
          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      _add('analyse depth 12 ...');
      final lines = await _engine.analyse(startFen, depth: 12);
      if (lines.isEmpty) {
        _add('hasil kosong (timeout atau parse gagal)');
      } else {
        for (final EngineLine l in lines) {
          _add('mpv${l.multipv} depth${l.depth} '
              'cp=${l.scoreCp} mate=${l.isMate ? l.mateIn : '-'} '
              'move=${l.move.toUci()}');
        }
      }
    } catch (e) {
      _add('analyse FAILED: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bidak — engine test')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy ? null : _init,
                    child: const Text('init engine'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy ? null : _test,
                    child: const Text('analyse start'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _log.isEmpty ? '(log kosong)' : _log.toString(),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
