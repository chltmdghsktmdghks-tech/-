// 5단계 33/N — 처음 켠 사람 안내.
//   flutter test test/guide_ui_test.dart
//
// **2026-09 사용자 결정으로 첫 실행 순서가 다시 바뀌었다.**
// Phase 2 에서는 첫 실행에 장르 고르기 시트가 저절로 떴다("장르 선택 →
// 기본 음악이 즉시 재생"). 그런데 그 뒤 결정: 장르 송폼은 프로젝트 시작의
// 필수 첫 단계가 아니라 **나중에 고르는 프리셋**이다(`Project.blank`,
// `home_view.dart` 의 `_maybeGuide`). 그래서 지금은 첫 실행에도 **아무것도
// 저절로 안 뜬다** — 사용자는 곧장 네 버튼(만들기·곡·라이브·쇼) 앞에 선다.
//
// 안내(설명)는 없어진 게 아니다 — 여전히 「사용법」 버튼으로 언제든 열리고,
// 내용도 그대로다. 이 시험이 지키는 것:
//  · 첫 실행에 **아무것도** 저절로 안 뜬다(장르 시트도, 설명도)
//  · 「사용법」 으로 설명이 열리고, 내용(네 단계·느낌·자동 저장·무음 대처)이 다 있다
//  · `guideSeen` 은 첫 실행 한 번으로 켜지고, 재시작해도 남는다
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/store.dart';
import 'package:music_doodle_engine/ui/home_view.dart';

void main() {
  testWidgets('처음 켠 사람 안내', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 진짜 파일을 쓴다 → `runAsync` 안에서(위젯 시험의 가짜 시계로는 안 끝난다)
    late Directory dir;
    final p = Project.blank(); // 실제 앱이 첫 실행에 쓰는 것과 같은 시작점
    late Store store;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('mdguide');
      store = Store(
        project: p,
        transport: Transport(),
        live: LiveChannel(),
        master: MasterChannel(),
        overrideDir: dir,
      );
      await store.start();
    });

    Widget app() => MaterialApp(
      theme: ThemeData.dark(),
      home: HomeView(
        project: p,
        transport: Transport(),
        live: LiveChannel(),
        master: MasterChannel(),
        host: null,
        store: store,
        ready: true,
        onOpenLab: () {},
        onSongOpened: () {},
      ),
    );

    // 재생 위치 표시가 계속 도는 화면이라 `pumpAndSettle` 은 못 쓴다
    Future<void> settle() async {
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    await tester.pumpWidget(app());
    await settle();

    // 1) 첫 실행에 **아무것도** 저절로 안 뜬다 — 장르 시트도, 설명도.
    check(
      '1) 첫 실행에 아무것도 안 뜬다',
      find.text('무슨 음악을 만들까요').evaluate().isEmpty &&
          find.text('음악 낙서장 쓰는 법').evaluate().isEmpty,
      '장르 시트도 설명도 안 뜸',
    );
    // guideSeen 은 화면에 뭘 띄우는 것과 상관없이 "첫 실행을 지났다"는
    // 표시로 이미 켜져 있어야 한다(재시작해도 다시 안 뜨게).
    check('1-b) 첫 실행 표시는 이미 남았다', store.guideSeen, '${store.guideSeen}');

    // 「사용법」 으로 설명을 연다.
    await tester.ensureVisible(find.text('사용법'));
    await tester.pump();
    await tester.tap(find.text('사용법'));
    await settle();
    check(
      '2) 사용법으로 안내가 열린다',
      find.text('음악 낙서장 쓰는 법').evaluate().isNotEmpty,
      '내용이 있다',
    );

    // 3) 네 단계가 다 있고, 각 단계에 '무엇을 누르면 되는지'가 적혀 있다
    final steps = [
      '프로젝트 고르기',
      '씬 — 한 판 만들기',
      '타임라인 — 곡으로 잇기 · 라이브',
      '쇼 — 보여 주기',
    ].where((t) => find.text(t).evaluate().isNotEmpty).length;
    final howTo =
        find.textContaining('「패턴」을 눌러').evaluate().isNotEmpty &&
        find.textContaining('내보내기').evaluate().isNotEmpty;
    check('3) 네 단계 + 누를 것', steps == 4 && howTo, '단계 $steps/4 · 누를 것 $howTo');

    // 4) 소리가 안 날 때의 대처가 적혀 있다 — 실제로 제일 많이 막히는 지점이다.
    // **빈 캔버스가 기본이 된 지금, 이 문구는 예전보다 더 자주 맞는 상황이다**
    // (씨앗이 심어진 패턴이 아니라 정말 아무것도 없어서 조용한 경우가 흔해졌다).
    check(
      '4-a) 느낌·자동 저장을 말해 준다',
      find.textContaining('느낌').evaluate().isNotEmpty &&
          find.textContaining('저절로 저장').evaluate().isNotEmpty,
      '둘 다 적혀 있음',
    );
    check(
      '4-b) 무음 대처',
      find.textContaining('소리가 안 나면').evaluate().isNotEmpty,
      '패턴이 전부 없음인지 보라고 적혀 있음',
    );

    // 5) 「시작하기」를 누르면 닫힌다.
    await tester.tap(find.text('시작하기'));
    await settle();
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await settle();
    }
    check(
      '5) 시작하기로 닫힌다',
      find.text('음악 낙서장 쓰는 법').evaluate().isEmpty,
      '닫힘',
    );

    // 5-b) **「시작하기」는 늘 바닥에 붙어 있는다.**
    {
      await tester.pumpWidget(app());
      await settle();
      showFirstGuide(tester.element(find.byType(Scaffold).first));
      await settle();
      final btn = find.text('시작하기');
      final ok = btn.evaluate().isNotEmpty;
      final within =
          ok &&
          tester.getRect(btn).bottom <= tester.view.physicalSize.height + 1;
      check(
        '5-c) 시작하기가 화면 안에',
        ok && within,
        ok ? '바닥 ${tester.getRect(btn).bottom.round()}px' : '없음',
      );
      if (ok) {
        await tester.tap(btn);
        await settle();
      }
    }

    // 6) 다시 켜도 **아무것도** 저절로 안 뜬다 — 화면을 통째로 새로 만들어 본다
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await settle();
    await tester.pumpWidget(app());
    await settle();
    check(
      '6) 다시 켜도 안 뜬다',
      find.text('음악 낙서장 쓰는 법').evaluate().isEmpty &&
          find.text('무슨 음악을 만들까요').evaluate().isEmpty,
      '설명도 장르 시트도 저절로는 안 뜸',
    );

    // 7) 「사용법」으로 언제든 다시 열 수 있다
    await tester.ensureVisible(find.text('사용법'));
    await tester.pump();
    await tester.tap(find.text('사용법'));
    await settle();
    check(
      '7) 사용법으로 다시 열기',
      find.text('음악 낙서장 쓰는 법').evaluate().isNotEmpty,
      '다시 열림',
    );

    // 8) 저장된 파일에도 남는다 — 앱을 완전히 껐다 켜도 안 뜬다
    late bool seenAfterRestart;
    await tester.runAsync(() async {
      final s2 = Store(
        project: Project.blank(),
        transport: Transport(),
        live: LiveChannel(),
        master: MasterChannel(),
        overrideDir: dir,
      );
      await s2.start();
      seenAfterRestart = s2.guideSeen;
    });
    check('8) 껐다 켜도 그대로', seenAfterRestart, 'index.json 에 남음');

    // 9) 가로로 눕혀도 안 넘친다 — 안내는 **열어 둔 채로** 본다
    tester.view.physicalSize = const Size(800, 400);
    await tester.pump();
    await settle();
    final err = tester.takeException();
    check(
      '9) 가로에서도 안 넘침',
      err == null && find.text('시작하기').evaluate().isNotEmpty,
      '넘침 예외 ${err ?? '없음'} · 시작하기 보임',
    );

    await tester.runAsync(() async => dir.delete(recursive: true));

    // ignore: avoid_print
    print(fail == 0 ? '처음 안내 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
