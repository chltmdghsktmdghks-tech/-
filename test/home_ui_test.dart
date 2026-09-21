// 첫 화면 확인 — **프로젝트 고르기로 다시 짰다**(2026-09, 로직 프로
// 「프로젝트 초이저」 참고).
//   flutter test test/home_ui_test.dart
//
// 예전엔 "지금 곡" 카드 + 할 일 네 버튼(만들기·곡·라이브·쇼)이 첫 화면
// 이었고, 버튼마다 **다른 화면**으로 push 됐다. 이제 첫 화면은 "어느
// 프로젝트를 열까"만 묻고, 고르면 `ProjectWorkspace` 하나가 열려 그 안에서
// 씬·타임라인·라이브·쇼를 **탭**으로 오간다(뒤로가기 없이).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/store.dart';
import 'package:music_doodle_engine/ui/home_view.dart';

void main() {
  testWidgets('첫 화면', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = Project.initial()..name = '첫 곡';
    var lab = 0;

    Widget app() => MaterialApp(
      theme: ThemeData.dark(),
      home: HomeView(
        project: p,
        transport: Transport(),
        live: LiveChannel(),
        master: MasterChannel(),
        host: null, // 소리 없이 화면만
        store: null, // 저장소 없이도 화면이 안 죽어야 한다(카드가 없을 뿐)
        ready: true,
        onOpenLab: () => lab++,
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

    // 1) 첫 화면 — 이름표와 "새 프로젝트" 카드가 있다
    check(
      '1) 첫 화면 요소',
      find.text('음악 낙서장').evaluate().isNotEmpty &&
          find.text('새 프로젝트').evaluate().isNotEmpty,
      '이름표·새 프로젝트 카드',
    );

    // 2) 「질문에 답해서 곡 만들기」가 첫 화면에 있다
    check(
      '2) 질문 만들기 입구',
      find.textContaining('질문에 답해서').evaluate().isNotEmpty,
      '',
    );

    // 3) "새 프로젝트"를 누르면 작업 화면(씬·타임라인·라이브·쇼 탭)이 열린다
    // **좁은 화면(이 시험의 400dp)에서는 탭이 아이콘만 보인다** — 실기기에서
    // "타임라인"이 "타…"로 잘려 읽기 힘들었던 걸 잡은 뒤로는(`workspace_view
    // .dart`), 탭 이름을 `Tooltip` 으로만 갖고 있다. 그래서 글자 대신
    // `byTooltip` 으로 찾는다 — 넓은 화면이든 좁은 화면이든 똑같이 통한다.
    await tester.tap(find.text('새 프로젝트'));
    await settle();
    // 3-a) 이름을 지어 볼지 먼저 묻는다(사용자 요청, 2026-09-13) — 시험은
    // 여태처럼 자동 이름으로 넘어가려고 「나중에 짓기」를 누른다.
    check(
      '3-a) 이름 짓기 대화상자가 먼저 뜬다',
      find.text('나중에 짓기').evaluate().isNotEmpty,
      '',
    );
    await tester.tap(find.text('나중에 짓기'));
    await settle();
    final modes = ['씬', '타임라인', '라이브', '쇼'];
    final tabsShown = modes.where((m) => find.byTooltip(m).evaluate().isNotEmpty).length;
    check('3) 네 모드 탭이 다 있다', tabsShown == 4, '$tabsShown/4 · ${modes.join(' · ')}');

    // 4) 기본은 씬 모드 — 스타일 칩(로파이) 같은 씬 화면 요소가 보인다
    check('4) 기본은 씬 모드', find.textContaining('로파이').evaluate().isNotEmpty, '');

    // 5) 탭만 눌러도 화면이 안 나가고 내용만 바뀐다(뒤로가기 없음) — 탭 넷은
    // `Expanded` 로 늘 화면 안에 다 보인다(스크롤 없음, 좁은 폰에서도).
    await settle();
    await tester.tap(find.byTooltip('라이브'));
    await settle();
    check('5) 라이브 탭으로 전환', find.textContaining('반주').evaluate().isNotEmpty, '뒤로가기 없이');

    await tester.tap(find.byTooltip('타임라인'));
    await settle();
    // 타임라인 탭 안에서도 다시 네 모드 탭 줄이 그대로 있다(같은 화면이라는 뜻)
    final stillTabs = modes.where((m) => find.byTooltip(m).evaluate().isNotEmpty).length;
    check('5-b) 타임라인에서도 탭 줄이 있다', stillTabs == 4, '$stillTabs/4');

    // 6) 사용법은 작업 화면 어디서든 열린다(모드를 안 가림)
    check('6) 사용법 아이콘', find.byIcon(Icons.help_outline).evaluate().isNotEmpty, '');

    // 7) 뒤로가기로 프로젝트를 나가면 다시 첫 화면(카드 목록)
    await tester.tap(find.byIcon(Icons.arrow_back));
    await settle();
    check('7) 뒤로가면 첫 화면', find.text('새 프로젝트').evaluate().isNotEmpty, '');

    // 8) 엔진 시험 화면은 **맨 아래 작은 글씨**로만
    await tester.ensureVisible(find.text('엔진 시험 화면'));
    await tester.pump();
    await tester.tap(find.text('엔진 시험 화면'));
    await tester.pump();
    check('8) 시험 화면은 구석에', lab == 1, '눌러야만 열린다');

    // 9) 가로에서도 안 넘친다
    tester.view.physicalSize = const Size(800, 400);
    await tester.pumpWidget(app());
    await settle();
    final err = tester.takeException();
    check('9) 가로에서도 안 넘침', err == null, '넘침 예외 ${err ?? '없음'}');

    // ignore: avoid_print
    print(fail == 0 ? '첫 화면 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });

  // ── 소리 장치를 못 열었을 때 ──
  //
  // 여태는 여기서 터지면 **동그라미만 영영 돌았다.** 화면은 멀쩡히 움직이는데
  // ▶를 눌러도 아무 일이 안 난다 — 사용자에게는 「앱이 고장 났다」로만 보이고
  // 무엇이 문제인지 알 길이 없다. 까닭을 한 줄로 말해 준다.
  testWidgets('소리 장치 실패', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Future<void> show(String? err) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: HomeView(
            project: Project.initial(),
            transport: Transport(),
            live: LiveChannel(),
            master: MasterChannel(),
            host: null,
            store: null,
            ready: false,
            audioError: err,
            onOpenLab: () {},
            onSongOpened: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }

    await show(null); // 아직 여는 중
    check(
      '1) 여는 중엔 동그라미',
      find.byType(CircularProgressIndicator).evaluate().isNotEmpty &&
          find.textContaining('못 열었습니다').evaluate().isEmpty,
      '동그라미만',
    );

    await show('PlatformException(no audio)');
    check(
      '2) 못 열면 까닭을 말한다',
      find.textContaining('못 열었습니다').evaluate().isNotEmpty &&
          find.byType(CircularProgressIndicator).evaluate().isEmpty,
      '동그라미 대신 한 줄',
    );

    // ignore: avoid_print
    print(fail == 0 ? '소리 장치 실패 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });

  // ── 카드 미리보기 세 모드 다 안 터진다 ──
  //
  // 「씬」·「타임라인」·「쇼」 미리보기는 각자 다른 레이아웃(색 블록 줄 ·
  // 색 막대 줄 · 어두운 무대 위 점)을 그린다. 셋 다 실제 저장된 곡으로
  // 그려 보고 렌더 예외가 없는지만 본다(생김새 자체는 눈으로 볼 것).
  testWidgets('카드 미리보기', (tester) async {
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
    final p = Project.initial();
    late Store store;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('mdcardpreview');
      store = Store(
        project: p,
        transport: Transport(),
        live: LiveChannel(),
        master: MasterChannel(),
        overrideDir: dir,
      );
      await store.start();
      await store.saveNow(); // meta 에 sceneActive·timelineScenes 를 채운다
    });
    addTearDown(() => tester.runAsync(() => dir.delete(recursive: true)));

    for (final mode in ['scene', 'timeline', 'show']) {
      await tester.runAsync(() => store.setPreviewMode(mode));
      await tester.pumpWidget(
        MaterialApp(
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
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      check('$mode 모드로 안 터짐', tester.takeException() == null, '');
    }

    // ignore: avoid_print
    print(fail == 0 ? '카드 미리보기 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
