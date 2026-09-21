// 타임라인 구간을 **직접 끌어서** 순서·길이를 바꾸는 손짓 확인.
//   flutter test test/song_timeline_drag_check_test.dart
//
// 목록 모드(`song_ui_test.dart`)는 이미 「손잡이를 끌어서 순서 바꾸기」를
// 본다. 여기는 **타임라인 모드**(마디 비율대로 늘어선 그림)에서 구간
// 카드 자체를 끌면 순서가 바뀌고, 오른쪽 모서리를 끌면 길이(판 수)가
// 바뀌는지를 본다 — 버튼(◀▶ · −/+)을 여러 번 누르지 않아도 되게 한
// 손짓이다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/song_view.dart';

void main() {
  testWidgets('타임라인 구간 끌기', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    tester.view.physicalSize = const Size(500, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = Project.initial();
    final tr = Transport();
    final song = p.song;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SongView(
            project: p,
            transport: tr,
            host: null,
            mode: 'timeline', // 목록이 아니라 타임라인으로 바로 연다
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    check('0) 구간이 셋 이상', song.sections.length >= 3, '${song.sections.length}개');

    // 1) 구간 0 의 **순서 손잡이**(왼쪽 모서리)를 오른쪽으로 크게 끌면
    //    1번과 자리가 바뀐다. 카드 몸통이 아니라 손잡이인 이유: 이 줄은
    //    가로로 길어서 몸통을 끌면 타임라인 자체가 스크롤되는 손짓과
    //    겹친다(실기기에서 처음엔 그렇게 되어 손잡이로 갈랐다).
    final objBefore = [...song.sections];
    final handle0 = find.byKey(const ValueKey('secreorder-0'));
    check('1) 첫 구간 순서 손잡이가 있다', handle0.evaluate().isNotEmpty, '');
    final start = tester.getCenter(handle0);
    final drag = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 30));
    // 카드 하나 너비를 넉넉히 넘게(마디수×30px 의 절반보다 크게) 민다
    await drag.moveBy(const Offset(140, 0));
    await tester.pump(const Duration(milliseconds: 30));
    await drag.up();
    await tester.pump(const Duration(milliseconds: 30));

    final movedTo = song.sections.indexOf(objBefore[0]);
    check(
      '2) 끌면 순서가 실제로 바뀐다',
      movedTo > 0 && song.sections.length == objBefore.length,
      '구간 0 이 $movedTo 번째로 (전체 ${song.sections.length}개, 그대로)',
    );

    // 3) 구간 하나를 골라 오른쪽 모서리(길이 손잡이)를 오른쪽으로 끌면 판 수가 는다
    await tester.tap(find.byKey(const ValueKey('secblk-0')));
    await tester.pump(const Duration(milliseconds: 16));
    final repsBefore = song.sections[0].reps;
    final grip = find.byKey(const ValueKey('secresize-0'));
    final gripStart = tester.getCenter(grip);
    final rdrag = await tester.startGesture(gripStart);
    await tester.pump(const Duration(milliseconds: 30));
    // 씬 한 판 너비(마디수 × 30px)를 넉넉히 넘게 두 번 늘린다
    await rdrag.moveBy(const Offset(200, 0));
    await tester.pump(const Duration(milliseconds: 30));
    await rdrag.up();
    await tester.pump(const Duration(milliseconds: 30));
    final repsAfter = song.sections[0].reps;
    check(
      '3) 모서리를 끌면 판 수가 는다',
      repsAfter > repsBefore,
      '$repsBefore판 → $repsAfter판',
    );

    // 4) 반대로 끌면 줄어든다(1판 밑으로는 안 내려간다)
    final grip2 = find.byKey(const ValueKey('secresize-0'));
    final g2start = tester.getCenter(grip2);
    final rdrag2 = await tester.startGesture(g2start);
    await tester.pump(const Duration(milliseconds: 30));
    await rdrag2.moveBy(const Offset(-400, 0));
    await tester.pump(const Duration(milliseconds: 30));
    await rdrag2.up();
    await tester.pump(const Duration(milliseconds: 30));
    final repsAfter2 = song.sections[0].reps;
    check(
      '4) 반대로 끌면 줄고 1판 밑으로는 안 내려간다',
      repsAfter2 >= 1 && repsAfter2 < repsAfter,
      '$repsAfter판 → $repsAfter2판',
    );

    check('5) 예외 없음', tester.takeException() == null, '');

    // ignore: avoid_print
    print(fail == 0 ? '타임라인 구간 끌기 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
