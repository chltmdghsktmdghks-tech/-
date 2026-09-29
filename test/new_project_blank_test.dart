// 새 프로젝트 = 빈 상태 + 시작 방식 선택 시트, 되돌리기 스낵바는 시간이 되면 내려간다
// (2026-09-29 (9)).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/store.dart';
import 'package:music_doodle_engine/ui/new_project_choice_sheet.dart';

void main() {
  test('newSong(blank) — 장르 없이 씬 1개·전부 쉼, 기본 newSong 은 그대로 로파이', () async {
    final dir = await Directory.systemTemp.createTemp('mdblank');
    final p = Project.initial();
    final st = Store(
      project: p,
      transport: Transport(),
      live: LiveChannel(),
      master: MasterChannel(),
      overrideDir: dir,
    );
    await st.start();
    await st.newSong(name: '빈 곡', blank: true);
    expect(p.name, '빈 곡');
    expect(p.genre, '');
    expect(p.scenes.length, 1);
    expect(p.scenes.first.clips.values.every((v) => v == null), isTrue);
    expect(p.song.sections.length, 1);
    expect(p.tracks.length, 4);

    await st.newSong(name: '기본');
    expect(p.genre, 'lofi');
    expect(p.scenes.length, greaterThan(1));
  });

  testWidgets('시작 방식 시트 — 세 갈래, 닫으면 null', (tester) async {
    NewProjectMode? got = NewProjectMode.ask;
    var done = false;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () async {
            got = await showNewProjectChoiceSheet(ctx);
            done = true;
          },
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('질문에 답해서 만들기'), findsOneWidget);
    expect(find.text('두드려서 플레이'), findsOneWidget);
    expect(find.text('처음부터 직접 만들기'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10)); // 바깥 탭 = 닫기
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(got, isNull);
  });

  testWidgets('action 있는 스낵바도 persist:false 면 duration 뒤에 내려간다', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => ScaffoldMessenger.of(ctx).showSnackBar(
              SnackBar(
                content: const Text('지웠습니다'),
                duration: const Duration(seconds: 2),
                persist: false,
                action: SnackBarAction(label: '되돌리기', onPressed: () {}),
              ),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('지웠습니다'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('지웠습니다'), findsNothing);
  });
}
