// 새 프로젝트 이름 짓기 유도 + 샘플곡 카드 미리보기 채우기
// (사용자 요청, 2026-09-13: "둘 다 진행해").
//   flutter test test/new_project_name_and_sample_preview_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/store.dart';
import 'package:music_doodle_engine/ui/home_view.dart';

void main() {
  testWidgets('새 프로젝트 — 이름 짓기 대화상자', (tester) async {
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
      dir = await Directory.systemTemp.createTemp('mdname');
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

    Widget app() => MaterialApp(
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
    );

    Future<void> settle() async {
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    await tester.pumpWidget(app());
    await settle();

    final before = store.songs.length;

    // 1) 「새 프로젝트」를 누르면 바로 만들어지지 않고 이름부터 묻는다.
    //
    // **탭 전체를 `runAsync` 로 감싼다** — `_newProject` 는 `async` 함수라
    // **처음 불릴 때의 존(zone)**을 그대로 들고 간다(도중에 대화상자를
    // 채우고 다시 눌러도 이어지는 코드는 여전히 그 존이다). 이 함수 안에서
    // `saveNow`/`_createFrom` 이 진짜 파일을 쓰므로, 맨 처음 누르는 이
    // 탭부터 `runAsync` 존 안이어야 그 뒤에 이어지는 진짜 I/O 가 끝까지
    // 돈다 — 나중 탭만 감싸면 이미 가짜 시계 존에 묶인 뒤라 소용없다
    // (실제로 그렇게 짰다가 `saveNow` 에서 영영 안 끝나는 것으로 잡았다).
    await tester.runAsync(() async {
      await tester.tap(find.text('새 프로젝트'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle();
    check(
      '1) 이름 짓기 대화상자가 뜬다',
      find.text('새 프로젝트 이름을 지어 볼까요?').evaluate().isNotEmpty,
      '',
    );
    check('1-b) 아직 곡이 안 늘었다', store.songs.length == before, '${store.songs.length}');

    // 2) 이름을 치고 확인하면 그 이름으로 만들어진다.
    await tester.enterText(find.byType(TextField), '여름밤 로파이');
    await tester.runAsync(() async {
      await tester.tap(find.text('확인'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await settle();
    check(
      '2) 새 곡이 지어 준 이름으로 생겼다',
      store.songs.any((s) => s.name == '여름밤 로파이'),
      '${store.songs.map((s) => s.name).toList()}',
    );

    // 3) 뒤로 나가서 다시, 이번엔 「나중에 짓기」 — 자동 이름으로 만들어진다.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await settle();
    await tester.runAsync(() async {
      await tester.tap(find.text('새 프로젝트'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle();
    await tester.runAsync(() async {
      await tester.tap(find.text('나중에 짓기'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await settle();
    check(
      '3) 나중에 짓기 — 자동 이름으로도 생긴다',
      store.songs.length == before + 2,
      '${store.songs.length} (기대 ${before + 2})',
    );

    final err = tester.takeException();
    check('4) 예외 없음', err == null, '${err ?? '없음'}');

    expect(fail, 0);
  });

  test('scenePatternsOf/sceneActiveOf — 씬이 비면 첫 구간 레인으로', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final p = Project.initial();
    // 씬은 일부러 비워 둔다(타임라인 레인으로 지은 샘플곡과 같은 모양) —
    // `Project.initial()` 의 기본 씬 클립을 전부 지운다.
    for (final s in p.scenes) {
      s.clips.updateAll((_, _) => null);
    }
    for (final t in p.tracks) {
      t.pattern = null;
    }
    p.song.sections
      ..clear()
      ..add(Section(0, reps: 1));

    // 레인을 놓기 **전에** 먼저 확인한다 — 놓은 뒤에 재보면 이미 채워진
    // 값을 보게 되어 "비었다"를 증명하지 못한다.
    check(
      '0) 지금 씬은 정말 비었다',
      Store.sceneActiveOf(p).every((b) => !b),
      '${Store.sceneActiveOf(p)}',
    );

    final drum = p.tracks.firstWhere((t) => t.type == 'drum');
    p.song.putLane(0, 0, drum.id, 'Lofi Chorus');

    // 씬이 비었으니 0번 구간 레인에서 드럼 패턴을 찾아와야 한다.
    final active = Store.sceneActiveOf(p);
    final names = Store.scenePatternsOf(p);
    check('1) 드럼 자리가 켜진다(레인에서 찾음)', active[0], '$active');
    check('2) 드럼 패턴 이름도 온다', names[0].isNotEmpty, '"${names[0]}"');
    check('3) 베이스는 여전히 꺼짐(레인도 없음)', !active[1], '$active');

    expect(fail, 0);
  });
}
