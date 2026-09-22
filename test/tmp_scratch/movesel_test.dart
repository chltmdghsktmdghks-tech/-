import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/editor_view.dart';

const _kCell = 30.0, _kHead = 62.0;

void main() {
  testWidgets('막힌 ▶ 가 고른 표시를 옆 음으로 넘기는가', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
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
    String nm() => p.tracks.firstWhere((t) => t.type == 'melody').pattern!;
    List<List<Object?>> notes() => p.findNote('melody', nm())!.notes;
    List<List<Object?>> row0() => [for (final n in notes()) if (n[0] == 14) n];
    Offset at(int rowFromTop, int step) {
      final top = tester.getTopLeft(grid).dy;
      final rowH = rowHeightFor(tester.getSize(grid).height, 15);
      return Offset(_kHead + step * _kCell + _kCell / 2, top + rowFromTop * rowH + rowH / 2);
    }

    await tester.tapAt(at(0, 3)); // B
    await tester.pump();
    await tester.tapAt(at(0, 2)); // A (그리고 A 가 골라진다)
    await tester.pump();
    // ignore: avoid_print
    print('BEFORE row0=${row0()}');
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    // ignore: avoid_print
    print('AFTER_MOVE row0=${row0()}');
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    // ignore: avoid_print
    print('AFTER_DELETE row0=${row0()}');
  });
}
