// 재현 테스트 — 두들플레이 "그만할까요?" 문구가 **실제로 남긴 단계**와 다르다
// (감사 2026-09-29). 아직 안 고쳐진 버그라 이 시험은 **실패하는 게 정상**이다.
//   flutter test test/doodle_exit_dialog_test.dart
//
// `_confirmExit`(doodle_play_view.dart) 는 `kept = _stage`(지금 보고 있는 단계의
// 번호)를 "사용하기까지 누른 단계 수"로 쓰고 `_stages.take(kept)` 를 나열한다.
// 그런데 진행 표시(✓●○)로 아무 단계나 건너뛸 수 있게 된 뒤로(`_gotoStage`,
// 2026-09-24) `_stage` 는 확정 개수가 아니다 — 아무것도 확정 안 하고 세 번째
// 칸으로 건너뛰기만 해도 "KICK·SNARE 는 이미 씬에 남았어요"라고 거짓을 말한다.
// 맞는 값은 `_keptStages` 다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/doodle_play_view.dart';

void main() {
  testWidgets('아무것도 확정 안 하고 건너뛰기만 했으면 "남았어요"라 말하면 안 된다', (tester) async {
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

    // 진행 표시에서 세 번째(HI-HAT)로 건너뛴다 — 아무 단계도 「사용하기」 안 눌렀다.
    await tester.tap(find.text('HI-HAT').first);
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('그만할까요?'), findsOneWidget);
    expect(find.textContaining('이미 씬에 남았어요'), findsNothing,
        reason: '확정한 단계가 0개인데 KICK·SNARE 가 남았다고 안내한다');
  });
}
