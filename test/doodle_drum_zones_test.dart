// 두들 3단계 드럼 세로 구역 표시 (2026-09-29 (12)).
//   flutter test test/doodle_drum_zones_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/doodle_play_view.dart';

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData.dark(),
    home: DoodlePlayView(project: Project.blank(), transport: Transport(), host: null),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.text('이 순서로 시작'));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  testWidgets('킥: 아래 = 고스트 구역이 보이고, 아래를 쳐도 무사히 받는다', (tester) async {
    await _open(tester);
    expect(find.text('고스트'), findsOneWidget);
    final g = await tester.startGesture(const Offset(200, 800));
    await tester.pump();
    await g.up();
    await tester.pump();
  });

  testWidgets('하이햇: 아래 8비트 / 위 16비트 구역이 보인다', (tester) async {
    await _open(tester);
    await tester.tap(find.text('HI-HAT').first);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('8비트'), findsOneWidget);
    expect(find.textContaining('16비트'), findsWidgets);
    final g = await tester.startGesture(const Offset(200, 700));
    await tester.pump();
    await g.moveBy(const Offset(0, -400)); // 롤 중 위로 밀기
    await tester.pump();
    await g.up();
  });

  testWidgets('빈 프로젝트(장르 없음)에서도 두들이 열린다', (tester) async {
    await _open(tester);
    expect(find.text('KICK'), findsWidgets);
  });
}
