// 두들플레이 제스처 이펙트·안내 (감사 2026-09-29 (7)) —
// 소리·판정이 아니라 **손끝에 돌아오는 표시**가 있는지만 잰다.
//   flutter test test/doodle_gesture_fx_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/doodle_play_view.dart';

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: DoodlePlayView(
        project: Project.initial(),
        transport: Transport(),
        host: null,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.text('이 순서로 시작'));
  await tester.pump(const Duration(milliseconds: 100));
}

/// 친 자리 물결 — 2026-09-30 부터 위젯이 아니라 **한 장의 그림**(`CustomPaint`, 키 `doodle-fx`)이라
/// 화면 상태의 살아 있는 물결 수로 잰다. 치기 전에는 0 이어야 한다.
int _live(WidgetTester t) =>
    (t.state(find.byType(DoodlePlayView)) as dynamic).debugLiveRipples as int;

void main() {
  testWidgets('드럼: 친 자리에 물결이 뜨고, 단계 이름 밑에 악기 역할 한 줄이 있다', (tester) async {
    await _open(tester);
    expect(find.textContaining('심장박동'), findsOneWidget);
    expect(find.byKey(const ValueKey('doodle-fx')), findsOneWidget);
    expect(_live(tester), 0);
    final g = await tester.startGesture(const Offset(80, 400));
    await tester.pump();
    expect(_live(tester), greaterThan(0));
    await g.up();
  });

  testWidgets('베이스: 패드가 없어도 친 자리에 물결이 뜨고, 세기 3구역이 보인다', (tester) async {
    await _open(tester);
    await tester.tap(find.text('BASS').first);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('여리게'), findsOneWidget);
    expect(find.text('세게'), findsOneWidget);
    final g = await tester.startGesture(const Offset(300, 400));
    await tester.pump();
    expect(_live(tester), greaterThan(0), reason: '예전엔 베이스에 물결이 아예 없었다');
    await g.up();
  });

  testWidgets('코드: 코드 이름표가 늘 있고, 잡으면 패드에 코드 이름이 적힌다 (전위 쓸기 없음)', (tester) async {
    await _open(tester);
    await tester.tap(find.text('CHORD').first);
    await tester.pump(const Duration(milliseconds: 100));
    final name = RegExp(r'^지금 [A-G]\S* +· +다음 → ');
    expect(
      find.byWidgetPredicate((w) => w is Text && name.hasMatch(w.data ?? '')),
      findsWidgets,
      reason: '이름표가 사라지면 한 바퀴 돌아온 걸 고장으로 본다',
    );
    expect(find.textContaining('전위'), findsNothing);
    // 은은한 힌트 — 왼쪽 긴장 / 오른쪽 해결
    expect(find.textContaining('긴장'), findsWidgets);
    expect(find.textContaining('해결'), findsWidgets);

    final g = await tester.startGesture(const Offset(200, 400));
    await tester.pump();
    expect(find.text('HOLD'), findsNothing, reason: '잡으면 코드 이름이 적혀야 한다');
    expect(find.text('3화음'), findsNothing, reason: '손가락 수 두께는 없앴다');
    await g.moveBy(const Offset(0, -80));
    await tester.pump();
    expect(find.textContaining('1전위'), findsNothing);
    await g.up();
  });
}
