// 재현 테스트 — 두들플레이에 **들어갔다 아무것도 안 치고 나오면 씬이 그대로**
// 여야 한다(감사 2026-09-29). 아직 안 고쳐진 버그라 이 시험은 **실패하는 게 정상**이다.
//   flutter test test/doodle_exit_restores_scene_test.dart
//
// `initState`(doodle_play_view.dart ~512-545)는 들어오자마자 지금 씬의 드럼·베이스·
// 코드 클립을 **빈 패턴으로 갈아 끼운다**(`putUserPattern`+`setClip`). 나갈 때
// `dispose` 는 음소거만 되돌리고 클립은 안 되돌린다. 그런데 그만두기 문구는
// "아직 아무것도 안 남겼어요. 지금 나가면 이 씬은 그대로입니다."라고 한다.
// 씬 화면의 「두드려서 채우기」(scene_view.dart)로 만든 곡에 들어갔다 나오면
// 그 씬의 드럼·베이스·코드가 조용히 사라진다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/doodle_play_view.dart';

void main() {
  testWidgets('들어갔다 그냥 나오면 씬의 드럼·베이스·코드 클립이 그대로', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = Project.initial()..setGenre('lofi');
    final tr = Transport();
    Map<String, String?> clips() => {
      for (final t in p.tracks.where(
        (t) => t.type == 'drum' || t.type == 'bass' || t.type == 'chord',
      ))
        t.id: p.scene.clips[t.id],
    };
    final before = clips();
    expect(before.values.where((v) => v != null), isNotEmpty,
        reason: '전제: 장르를 깐 씬에는 드럼·베이스·코드 클립이 있다');

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                openDoodlePlay(context, project: p, transport: tr, host: null),
            child: const Text('열기'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('이 순서로 시작'), findsOneWidget);

    // 순서 정하기 화면은 묻지 않고 나갈 수 있다(canPop: _ordering).
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('열기'), findsOneWidget);

    expect(clips(), before,
        reason: '아무것도 안 쳤는데 씬의 드럼·베이스·코드가 빈 패턴으로 바뀌었다');
  });
}
