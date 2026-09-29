// 재현 테스트 — 두들 진입 시트에서 고른 빠르기가 **씬에는 안 남는다**
// (감사 2026-09-29). 아직 안 고쳐진 버그라 이 시험은 **실패하는 게 정상**이다.
//   flutter test test/doodle_setup_bpm_scene_test.dart
//
// `home_view.dart` `_doodlePlay` 는 `transport.bpm = setup.bpm` 만 쓴다.
// 그런데 `project.setGenre` 는 씬마다 `bpm: 장르 기본값` 을 심고, 씬 칩
// 누르기(`scene_view._launch`)·곡 타임라인(`sequencer` 의 `bpm: s.bpm`)은
// **씬의 bpm 을 우선**한다 — 그래서 시트에서 140 을 골라도 씬 하나만
// 눌러도 장르 기본값으로 돌아간다. 옳은 길은 `Project.setBpm(tr, v)` 다
// (Transport 와 scene.bpm 을 같이 쓴다).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/home_view.dart';

void main() {
  testWidgets('두들 시트에서 고른 BPM 이 씬에도 남는다', (tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = Project.initial();
    final tr = Transport();
    final genre = kGenres.first;
    final want = genre.bpm + 20; // 장르 기본값과 확실히 다른 값

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: HomeView(
          project: p,
          transport: tr,
          live: LiveChannel(),
          master: MasterChannel(),
          host: null,
          store: null,
          ready: true,
          onOpenLab: () {},
          onSongOpened: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('두드려서 만들기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(genre.label));
    await tester.pumpAndSettle();
    for (var i = 0; i < 20; i++) {
      await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.byIcon(Icons.add)).first); // 시트 안 BPM +
      await tester.pump();
    }
    await tester.tap(find.text('이 설정으로 시작'));
    await tester.pump(const Duration(milliseconds: 500));

    expect(tr.bpm, want, reason: '재생 빠르기는 시트 값');
    expect(p.scene.bpm, want,
        reason: 'scene.bpm 이 장르 기본값(${genre.bpm})으로 남아 씬 전환·타임라인에서 되돌아간다');
  });
}
