import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/editor_view.dart';

const _kCell = 30.0, _kHead = 62.0;

void main() {
  for (final size in [const Size(400, 800), const Size(400, 900), const Size(360, 780), const Size(800, 400)]) {
    testWidgets('선택 전후 줄 높이 $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final p = Project.initial();
      final mel = p.tracks.firstWhere((t) => t.type == 'melody');
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: EditorView(project: p, transport: Transport(), track: mel, host: null)),
      ));
      await tester.pump();
      final grid = find.byType(ListView).last;
      final h0 = tester.getSize(grid).height;
      final rh0 = rowHeightFor(h0, 15);
      final top0 = tester.getTopLeft(grid).dy;
      await tester.tapAt(Offset(_kHead + 0 * _kCell + _kCell / 2, top0 + 3 * rh0 + rh0 / 2));
      await tester.pump();
      final h1 = tester.getSize(grid).height;
      final rh1 = rowHeightFor(h1, 15);
      final top1 = tester.getTopLeft(grid).dy;
      final y0 = top0 + 10 * rh0 + rh0 / 2;
      final y1 = top1 + 10 * rh1 + rh1 / 2;
      // ignore: avoid_print
      print('SIZE=$size gridH $h0 -> $h1 | rowH $rh0 -> $rh1 | 10th row center $y0 -> $y1 (shift ${(y1-y0).toStringAsFixed(1)}px)');
    });
  }
}
