import 'dart:async';
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
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    _subs.add(_engine.rawLines.listen((l) => _add('RAW $l')));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _engine.dispose();
    super.dispose();
  }

  void _add(String s) {
    if (!mounted) return;
    setState(() => _log.writeln(s));
  }

  Future<void> _init() async {
    try {
      await _engine.init(nnuePath: '');
      _add('engine: init ok');
    } catch (e) {
      _add('engine: init FAILED: $e');
    }
  }

  Future<void> _test() async {
    if (!_engine.isInited) {
      _add('engine belum init');
      return;
    }
    _add('analyse depth 6 ...');
    try {
      const startFen =
          'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
      final lines = await _engine.analyse(startFen, depth: 6);
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
                    onPressed: _init,
                    child: const Text('init'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _test,
                    child: const Text('analyse d6'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _log.isEmpty ? '(log kosong)' : _log.toString(),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
