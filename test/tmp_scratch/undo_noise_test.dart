import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/editor_view.dart';

const _kCell = 30.0, _kHead = 62.0;

void main() {
  testWidgets('꾹 잡기만 해도 다시하기가 날아가는가', (tester) async {
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
    int count() => p.findNote('melody', nm())!.notes.length;
    Offset at(int rowFromTop, int step) {
      final top = tester.getTopLeft(grid).dy;
      final rowH = rowHeightFor(tester.getSize(grid).height, 15);
      return Offset(_kHead + step * _kCell + _kCell / 2, top + rowFromTop * rowH + rowH / 2);
    }

    final c0 = count();
    // 빈 칸 두 곳에 찍기 — 0번 줄(제일 높은 음)은 대개 비어 있다
    await tester.tapAt(at(0, 1));
    await tester.pump();
    await tester.tapAt(at(0, 5));
    await tester.pump();
    final c2 = count();
    // 되돌리기 한 번 → 하나 사라진다(다시하기 통에 1개)
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    final cUndo = count();
    // **아무것도 안 하고** 음 하나를 꾹 잡았다 뗀다
    final g = await tester.startGesture(at(0, 1));
    await tester.pump(const Duration(milliseconds: 700));
    await g.up();
    await tester.pump();
    final cHold = count();
    // 다시하기
    await tester.tap(find.byIcon(Icons.redo));
    await tester.pump();
    final cRedo = count();
    // ignore: avoid_print
    print('COUNTS start=$c0 after2adds=$c2 afterUndo=$cUndo afterHold=$cHold afterRedo=$cRedo');
    // ignore: avoid_print
    print(cRedo == c2 ? 'REDO_OK — 다시하기가 살아 있다' : 'REDO_LOST — 꾹 잡기만 했는데 다시하기가 날아갔다');
  });
}
