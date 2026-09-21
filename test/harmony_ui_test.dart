// 「멜로디에 맞추기」 버튼 (계획 6-4) — **코드 판에서만** 나오고, 실제로 채우는가.
//   flutter test test/harmony_ui_test.dart
//
// 세로·가로 둘 다 본다. 편집기 위쪽 줄은 이미 여섯 가지를 이고 있어서
// 한 번 잘린 적이 있다(폰에서 「신스 베이스 내 …」로 잘렸다) — 일곱 번째를
// 얹는 것이라 넘침을 꼭 봐야 한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/harmony.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/editor_view.dart';

void main() {
  testWidgets('멜로디에 맞추기', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final p = Project.initial()..setGenre('lofi');
    final tr = Transport();
    final chord = p.tracks.firstWhere((t) => t.type == 'chord');
    final mel = p.tracks.firstWhere((t) => t.type == 'melody');

    Future<void> open(Track t, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            key: ValueKey('${t.id}${size.width}'),
            body: EditorView(project: p, transport: tr, track: t, host: null),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }

    // ── 1) 멜로디 판에는 안 보인다 ──
    await open(mel, const Size(400, 800));
    check(
      '1) 멜로디 판에는 없다',
      find.text('멜로디에 맞추기').evaluate().isEmpty,
      '「기능이 있다는 이유만으로 다 노출하지 않는다」',
    );
    check('1-b) 세로 안 넘침', tester.takeException() == null, '');

    // ── 2) 코드 판에는 보인다 ──
    await open(chord, const Size(400, 800));
    check('2) 코드 판에는 있다', find.text('멜로디에 맞추기').evaluate().isNotEmpty, '');
    check('2-b) 세로 안 넘침', tester.takeException() == null, '');

    // ── 3) 누르면 채운다 ──
    final name = p.scene.clips[chord.id]!;
    final before = [
      for (final r in p.findNote('chord', name)!.notes) r[0],
    ].join(',');
    await tester.tap(find.text('멜로디에 맞추기'));
    await tester.pump();
    final after = p.findNote('chord', name)!.notes;
    check(
      '3) 누르면 코드가 바뀐다',
      [for (final r in after) r[0]].join(',') != before,
      '$before → ${[for (final r in after) r[0]].join(',')}',
    );

    // 채운 결과가 **실제로 멜로디와 맞는가**
    final melDef = p.findNote('melody', p.scene.clips[mel.id]!)!;
    final fit = harmonyFit(melDef.notes, after, bars: melDef.bars);
    check('3-b) 채운 코드가 멜로디와 맞는다', fit > 0.7, '${(fit * 100).round()}%');

    // ── 4) 되돌릴 수 있다 ── 판 전체를 갈아엎는 일이다
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    check(
      '4) 되돌리기로 원래대로',
      [for (final r in p.findNote('chord', name)!.notes) r[0]].join(',') ==
          before,
      '',
    );

    // ── 5) 가로에서도 ──
    await open(chord, const Size(800, 400));
    check('5) 가로 안 넘침', tester.takeException() == null, '');
    // 가로에서는 **그림표만** 남는다. 코드 판 + 글자 1.3배 + 가로에서 이 한 줄이
    // 22px 넘쳤다(넘침 시험이 잡았다) — 거기서는 되돌리기·지우개·비우기도 다
    // 그림표라, 이것도 그림표로 두고 길게 눌러 이름을 본다.
    // **없어지면 안 된다**: 가로로 눕힌 사람에게는 그 기능이 아예 없는 것이 된다.
    check(
      '5-b) 가로에서도 닿는다',
      find.byIcon(Icons.auto_awesome).evaluate().isNotEmpty,
      '그림표로 남아 있다',
    );

    tester.view.resetPhysicalSize();
    // ignore: avoid_print
    print(fail == 0 ? '멜로디에 맞추기 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
