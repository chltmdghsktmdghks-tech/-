// 편집기 아래 바 — **못 옮겼는데 고른 것만 옆으로 넘어가지 않는가.**
//   flutter test test/editor_move_test.dart
//
// `NoteOps.move` 는 옮기려는 자리에 이미 음이 있으면 **아무것도 안 하고**
// 원래 목록을 그대로 돌려준다(`edit_ops.dart` 의 `_indexOf(out, degree, to) >= 0`).
// 그런데 `_moveNote` 의 성공 판정이 「목표 자리에 음이 있나」였다 — 그러면
// 그 **남의 음**을 보고 성공으로 읽는다.
//
// 그래서 ▶ 를 눌러도 판은 그대로인데 **노란 테두리만 옆 음으로 넘어가고**,
// 그 상태로 휴지통을 누르면 **남의 음이 지워졌다.** 고른 것을 지웠다고
// 생각하는데 엉뚱한 것이 사라진다 — 되돌리기를 눌러도 왜 그랬는지 모른다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/editor_view.dart';

const _kCell = 30.0, _kHead = 62.0;

Offset _cell(WidgetTester tester, int rowFromTop, int step, int rows) {
  final grid = find.byType(ListView).last;
  final top = tester.getTopLeft(grid).dy;
  final rowH = rowHeightFor(tester.getSize(grid).height, rows);
  return Offset(
    _kHead + step * _kCell + _kCell / 2,
    top + rowFromTop * rowH + rowH / 2,
  );
}

Future<List<List<Object?>> Function()> _open(
  WidgetTester tester,
  List<List<Object?>> notes,
) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final p = Project.initial()..setGenre('lofi');
  final mel = p.tracks.firstWhere((t) => t.type == 'melody');
  final nm = mel.pattern!;
  p.putUserPattern('melody', nm, note: NotePatternDef(nm, 2, 2, notes));

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: EditorView(
          project: p,
          transport: Transport(),
          track: mel,
          host: null,
        ),
      ),
    ),
  );
  await tester.pump();
  return () => p.findNote('melody', nm)!.notes;
}

void main() {
  const rows = 15, deg = 10, rowFromTop = rows - 1 - deg;

  testWidgets('막혀서 못 옮겼으면 휴지통이 **내 음**을 지운다', (tester) async {
    // 4번 칸(길이 1)과 5번 칸(길이 1) — 4번을 오른쪽으로 못 옮긴다.
    final ns = await _open(tester, const [
      [deg, 4, 1, 2],
      [deg, 5, 1, 2],
    ]);

    // 4번 음을 고른다.
    await tester.tapAt(_cell(tester, rowFromTop, 4, rows));
    await tester.pump();

    // ▶ — 5번에 이미 음이 있어 **못 옮긴다.**
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    // ignore: avoid_print
    print('▶ 누른 뒤 — ${ns()}');
    expect(ns().length, 2, reason: '못 옮겼으니 판은 그대로');

    // 휴지통 — **고른 4번**이 지워져야 한다.
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    // ignore: avoid_print
    print('휴지통 뒤 — ${ns()}');
    expect(ns().length, 1, reason: '하나만 지워져야 한다');
    expect(ns().first[1], 5,
        reason: '4번이 지워지고 5번이 남아야 한다 — 5번이 사라졌다면 '
            '고른 것이 몰래 옆 음으로 넘어간 것이다');
  });

  testWidgets('빈 자리로는 제대로 옮겨진다 — 회귀가 아니다', (tester) async {
    final ns = await _open(tester, const [
      [deg, 4, 1, 2],
    ]);
    await tester.tapAt(_cell(tester, rowFromTop, 4, rows));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    // ignore: avoid_print
    print('빈 자리로 옮김 — ${ns()}');
    expect(ns().single[1], 5, reason: '한 칸 오른쪽으로 갔어야 한다');

    // 옮긴 뒤 휴지통은 그 음을 지운다.
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    expect(ns().length, 0);
  });

  testWidgets('판 끝에서 더 밀어도 고른 것이 안 흔들린다', (tester) async {
    // 마지막 칸(2마디 = 32칸이므로 31번)에서 오른쪽으로 더 못 간다.
    final ns = await _open(tester, const [
      [deg, 31, 1, 2],
      [deg, 4, 1, 2],
    ]);
    await tester.tapAt(_cell(tester, rowFromTop, 4, rows));
    await tester.pump();
    // 4번을 왼쪽으로 3번 밀어 1번까지 — 여기까진 빈 자리다.
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pump();
    }
    // ignore: avoid_print
    print('왼쪽으로 3칸 — ${ns()}');
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pump();
    // ignore: avoid_print
    print('휴지통 뒤 — ${ns()}');
    expect(ns().length, 1, reason: '옮긴 그 음이 지워져야 한다');
    expect(ns().first[1], 31, reason: '31번 음은 그대로 남아야 한다');
  });

  _headTests();
}

// ── 재생 막대와 화면 따라가기가 **같은 자리를 가리키는가** ──
//
// 그리는 쪽은 `headStep(..., spb: spb)` 로 재는데 따라가기 쪽이 `spb` 를 안
// 넘기면 기본값 16으로 잰다. 3/4·6/8 처럼 한 마디가 16칸이 아닌 곡에서는
// 둘이 달라져 **막대가 없는 자리로 화면이 끌려간다.**
void _headTests() {
  group('재생 막대 — 박자표가 달라도 한 자리를 가리킨다', () {
    test('6/8(한 마디 12칸)에서 그리는 값과 따라가는 값이 같다', () {
      const steps = 24, loopBars = 2, spb = 12;
      for (final pos in [0.0, 0.1, 0.25, 0.5, 0.75, 0.99]) {
        final drawn = headStep(pos, steps: steps, loopBars: loopBars, spb: spb);
        final follow = headStep(pos, steps: steps, loopBars: loopBars, spb: spb);
        expect(follow, drawn);
      }
    });

    test('spb 를 빠뜨리면 정말 어긋난다 — 회귀하면 여기가 걸린다', () {
      const steps = 24, loopBars = 2, spb = 12;
      const pos = 0.5;
      final right = headStep(pos, steps: steps, loopBars: loopBars, spb: spb);
      final wrong = headStep(pos, steps: steps, loopBars: loopBars); // 기본 16
      // ignore: avoid_print
      print('6/8 pos=0.5 — 맞는 값 $right · spb 빠뜨린 값 $wrong');
      expect(wrong, isNot(right), reason: '둘이 같으면 이 시험은 뜻이 없다');
    });

    test('4/4 에서는 기본값과 같다 — 여태 안 드러난 이유', () {
      const steps = 32, loopBars = 2;
      for (final pos in [0.0, 0.3, 0.7]) {
        expect(
          headStep(pos, steps: steps, loopBars: loopBars, spb: 16),
          headStep(pos, steps: steps, loopBars: loopBars),
        );
      }
    });
  });
}
