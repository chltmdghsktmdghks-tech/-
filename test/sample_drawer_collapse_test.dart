// 첫 화면 「샘플곡」 서랍 접기 확인(사용자 요청, 2026-09-13: "샘플곡들은
// 안보이게 접어놔").
//   flutter test test/sample_drawer_collapse_test.dart
//
// 서랍을 아예 없앤 게 아니라 **접을 수만** 있게 했다 — 몇 개인지 이름표는
// 늘 보이고, 눌러서 펴고 접는다. 접은 채로 저장소에 남아 다음에 열어도
// 또 접어야 하지 않는다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/store.dart';
import 'package:music_doodle_engine/ui/home_view.dart';

void main() {
  testWidgets('샘플곡 서랍 접기·펴기', (tester) async {
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
      dir = await Directory.systemTemp.createTemp('mdsamples');
      store = Store(
        project: Project.initial(),
        transport: Transport(),
        live: LiveChannel(),
        master: MasterChannel(),
        overrideDir: dir,
        seedSamples: true,
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

    // 1) 기본은 펼침 — 샘플곡 카드가 보인다
    check(
      '1) 기본은 펼침(샘플 이름이 보인다)',
      find.textContaining('샘플').evaluate().isNotEmpty,
      '',
    );
    check('1-b) 카드 격자가 있다', find.byType(GridView).evaluate().length >= 2, '');

    // 2) 헤더를 누르면 접힌다 — 안내 문구·카드가 사라진다(제목·개수는 남는다)
    // `setSamplesCollapsed` 는 진짜 파일에 쓰고 나서 `notifyListeners` 하므로
    // (`_writeIndex` 가 실제 I/O) `runAsync` 로 감싸야 그 완료를 기다린다 —
    // 안 그러면 가짜 시계 위에서 파일 쓰기가 안 끝나 화면이 안 바뀐 채로 본다.
    await tester.runAsync(() async {
      await tester.tap(find.text('샘플곡'));
      // `onTap` 이 부른 `setSamplesCollapsed` 는 진짜 파일에 쓴 **뒤에**
      // `notifyListeners` 한다 — 그 완료를 기다려야 화면이 접힌다.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle();
    check(
      '2) 접으면 안내 문구가 사라진다',
      find.textContaining('바로 열어서').evaluate().isEmpty,
      '',
    );
    check(
      '2-b) 접혀도 제목·개수는 남는다',
      find.text('샘플곡').evaluate().isNotEmpty &&
          find.textContaining('개').evaluate().isNotEmpty,
      '',
    );

    // 3) 저장소에도 남는다 — 새로 HomeView 를 그려도 접힌 채로
    check('3) 저장소에 접힘이 남는다', store.samplesCollapsed, '${store.samplesCollapsed}');

    // 4) 다시 누르면 펴진다
    await tester.runAsync(() async {
      await tester.tap(find.text('샘플곡'));
      // `onTap` 이 부른 `setSamplesCollapsed` 는 진짜 파일에 쓴 **뒤에**
      // `notifyListeners` 한다 — 그 완료를 기다려야 화면이 접힌다.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await settle();
    check(
      '4) 다시 누르면 펴진다',
      find.textContaining('바로 열어서').evaluate().isNotEmpty,
      '',
    );

    final err = tester.takeException();
    check('5) 예외 없음', err == null, '${err ?? '없음'}');

    expect(fail, 0);
  });
}
