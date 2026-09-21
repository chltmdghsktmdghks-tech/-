// 첫 화면 프로젝트 카드 미리보기 — 레인 툴팁에 실제 패턴 이름 확인
// (사용자 요청, 2026-09-13: "미리보기에 실제 패턴 이름 툴팁").
//   flutter test test/preview_tooltip_check_test.dart
//
// 미리보기는 색만 보여 줘서 "이 카드에 뭐가 들었는지"는 열어 봐야 알았다.
// `Store.scenePatternsOf` 가 트랙별 패턴의 **보여 주는 이름**을 뽑아
// `SongMeta.scenePatterns` 에 저장하고, 카드의 레인마다 그 이름을 Tooltip
// 으로 붙였다 — 여기서는 (1) 값 뽑기, (2) JSON 저장·복원, (3) 카드 위
// 실제 Tooltip 문구를 확인한다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/store.dart';
import 'package:music_doodle_engine/ui/home_view.dart';

void main() {
  test('scenePatternsOf — 트랙별 패턴 이름 뽑기', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final p = Project.initial();
    final drum = p.tracks.firstWhere((t) => t.type == 'drum');
    final melody = p.tracks.firstWhere((t) => t.type == 'melody');
    drum.pattern = 'Lofi Chorus';
    melody.pattern = null; // 안 실린 트랙은 빈 문자열이어야 한다

    final names = Store.scenePatternsOf(p);
    check('0) 넷(kPreviewTrackTypes 차례)', names.length == 4, '$names');
    check('1) 드럼 자리에 이름이 있다', names[0].isNotEmpty, names[0]);
    check('2) 멜로디는 비어 있다(패턴 없음)', names[3].isEmpty, '"${names[3]}"');

    expect(fail, 0);
  });

  test('SongMeta — scenePatterns 가 JSON 을 오간다', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final m = SongMeta(
      id: 's1',
      name: '곡',
      genre: 'lofi',
      updated: DateTime.now(),
      scenePatterns: ['로파이 코러스', '', '', ''],
    );
    final back = SongMeta.fromJson(jsonDecode(jsonEncode(m.toJson())));
    check(
      '되살린 값이 같다',
      back.scenePatterns != null &&
          back.scenePatterns!.first == '로파이 코러스',
      '${back.scenePatterns}',
    );

    expect(fail, 0);
  });

  testWidgets('카드 레인 — 길게 누르면 패턴 이름 툴팁', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late Directory dir;
    late Store store;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('mdpreview');
      store = Store(
        project: Project.initial(),
        transport: Transport(),
        live: LiveChannel(),
        master: MasterChannel(),
        overrideDir: dir,
      );
      await store.start();
    });
    addTearDown(() => dir.delete(recursive: true));

    // 카드 하나를 직접 만들어 넣는다 — `_ProjectCard` 는 파일 비공개라
    // `HomeView` 전체를 통해서만 본다(다른 UI 시험과 같은 방식).
    store.songs
      ..clear()
      ..add(
        SongMeta(
          id: 'preview1',
          name: '내 곡',
          genre: 'lofi',
          updated: DateTime.now(),
          sceneActive: [true, false, false, false],
          scenePatterns: ['로파이 코러스', '', '', ''],
        ),
      );
    store.currentId = 'preview1';

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: HomeView(
          project: store.project,
          transport: store.transport,
          live: store.live,
          master: store.master,
          host: null,
          store: store,
          ready: true,
          onOpenLab: () {},
          onSongOpened: () {},
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }

    final tooltips = find.byType(Tooltip);
    final messages = tooltips
        .evaluate()
        .map((e) => (e.widget as Tooltip).message)
        .toList();
    check(
      '켜진 드럼 레인 툴팁에 패턴 이름이 있다',
      messages.any((m) => m != null && m.contains('로파이 코러스')),
      '$messages',
    );
    check(
      '꺼진 레인은 「쉬는 중」이라 말해 준다',
      messages.any((m) => m != null && m.contains('쉬는 중')),
      '$messages',
    );

    expect(fail, 0);
  });
}
