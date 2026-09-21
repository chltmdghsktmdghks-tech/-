// 5단계 20/N — 씬(만들기) 화면 UI 확인.
//   flutter test test/scene_ui_test.dart
//
// 만들기 화면의 주인공은 **트랙**이다. 위쪽 설정이 화면을 먹으면 정작 만들 것이 안 보인다.
// 조·스타일 칩은 이제 이 화면에 없다(작업 화면 위쪽 톱니바퀴의 「프로젝트
// 설정」으로 옮겼다 — `project_settings_ui_test.dart` 가 그쪽을 본다).
// 여기서 보는 것: 그 칩들이 정말 없는가(자리를 안 먹는가) · 트랙이 첫
// 화면에 몇 개나 보이는가.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/pattern_names.dart';
import 'package:music_doodle_engine/ui/scene_view.dart';

void main() {
  testWidgets('씬 화면 위쪽', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = Project.initial();
    final tr = Transport();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SceneView(project: p, transport: tr, host: null),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    // 1) 조·스타일 칩이 이 화면에 없다 — 프로젝트 설정으로 옮겼다
    check(
      '1) 조 칩이 없다',
      find.textContaining('조  ').evaluate().isEmpty,
      '작업 화면 톱니바퀴의 프로젝트 설정에만 있음',
    );
    // '▾' 는 확인하지 않는다 — 느낌 칩이 그대로 그 표시를 쓴다(느낌은 안 옮겼다).
    check(
      '1-b) 스타일 칩이 없다',
      find.textContaining('스타일 고르기').evaluate().isEmpty,
      '',
    );

    // 2) 트랙이 첫 화면에 다 보인다 — 위쪽 설정에 밀리면 안 된다
    final names = [for (final t in p.tracks) t.name];
    final shown = names.where((n) => find.text(n).evaluate().isNotEmpty).length;
    check(
      '2) 트랙이 보인다',
      shown == names.length,
      '$shown/${names.length} · ${names.join(',')}',
    );

    // 6) 멈춰 있어도 마디 표시가 읽힌다 — 빈 칸 넷만 있으면 뭔지 알 수 없다
    check(
      '6) 멈춤 상태 마디 표시',
      find.textContaining('한 판').evaluate().isNotEmpty &&
          find.text('1').evaluate().isNotEmpty &&
          find.text('4').evaluate().isNotEmpty,
      '한 판 N마디 + 칸마다 번호',
    );

    // 7~9) 패턴 고르기 — 72개를 한 벽에 늘어놓지 않는다
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SceneView(project: p, transport: tr, host: null),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    // 짧은 이름(「코러스」)은 **씬 칩과 글자가 같다** — 이름으로 찾으면 둘이 잡힌다.
    // 첫 트랙(드럼)의 「패턴」 칸을 라벨로 집는다.
    await tester.tap(find.text('패턴').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 패턴 이름은 이제 한국어로 보인다(5단계 36/N) — 「Lofi Chorus」 → 「로파이 코러스」
    final lofi = find.textContaining('로파이').evaluate().length;
    final house = find.textContaining('하우스').evaluate().length;
    check(
      '7) 이 스타일 것만 먼저',
      find.text('로파이').evaluate().isNotEmpty && lofi > 0 && house == 0,
      '로파이 $lofi개 · 하우스 $house개(안 보여야 함)',
    );

    await tester.tap(find.text('전부 보기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    check(
      '8) 전부 보기',
      find.text('기본').evaluate().isNotEmpty &&
          find.text('다른 스타일').evaluate().isNotEmpty &&
          find.textContaining('하우스').evaluate().isNotEmpty,
      '기본·다른 스타일 묶음이 펼쳐짐',
    );

    final drumTrack = p.tracks.firstWhere((t) => t.type == 'drum');
    final houseChorus = find.text(patternLabel('House Chorus'));
    await tester.ensureVisible(houseChorus.first);
    await tester.pump();
    await tester.tap(houseChorus.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    check(
      '9) 고르면 실린다',
      drumTrack.pattern == 'House Chorus',
      '${drumTrack.pattern}',
    );

    // 10) 가로로 눕혀도 안 넘침
    tester.view.physicalSize = const Size(800, 400);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SceneView(project: p, transport: tr, host: null),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final err = tester.takeException();
    check('10) 가로·세로 안 넘침', err == null, '넘침 예외 ${err ?? '없음'}');

    // 11) **한 가지를 두 이름으로 부르지 않는다.**
    //     고르는 화면(`create_sheet`)이 「빠르기」라고 말해 놓고 이 화면만 「템포」였다.
    //     같은 손잡이에 두 이름이 붙으면 초보는 다른 것인 줄 안다.
    check(
      '12) 빠르기라고 부른다',
      find.text('빠르기').evaluate().isNotEmpty &&
          find.text('템포').evaluate().isEmpty,
      '빠르기 ${find.text('빠르기').evaluate().length}개 · '
          '템포 ${find.text('템포').evaluate().length}개',
    );

    // ── **연주해서 곡 만들기** ──
    //
    // 씬을 눌러 넘긴 순서가 그대로 구간표가 된다. 여태 곡을 만드는 길은
    // 「＋구간 붙이기」로 하나씩 놓기뿐이었다 — 그건 적는 일이지 만드는 일이 아니다.
    {
      final before = p.song.sections.length;
      // 앞 검사들이 씬을 옮겨 놨을 수 있다 — **시작점을 못 박고** 시작한다.
      // (녹음을 켜는 순간 「지금 씬」이 첫 구간으로 적힌다)
      await tester.tap(find.text(p.scenes[0].name).first);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tap(find.text('연주 녹음'));
      await tester.pump(const Duration(milliseconds: 16));
      final armed = find.textContaining('곡으로 (').evaluate().isNotEmpty;

      // 씬을 둘 넘긴다 (지금 씬이 하나 이미 적혀 있으니 모두 셋이 된다)
      await tester.tap(find.text(p.scenes[2].name).first);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tap(find.text(p.scenes[1].name).first);
      await tester.pump(const Duration(milliseconds: 16));

      await tester.tap(find.textContaining('곡으로 ('));
      await tester.pump(const Duration(milliseconds: 16));
      final made = p.song.sections;
      check(
        '연주 녹음 → 곡 구성',
        armed &&
            made.length == 3 &&
            made[0].scene == 0 &&
            made[1].scene == 2 &&
            made[2].scene == 1 &&
            made.every((x) => x.reps >= 1),
        '켜짐 $armed · ${before}구간 → '
            '${made.map((x) => '${x.scene}번×${x.reps}판').join(' → ')}',
      );

      // 되돌릴 길이 있어야 한다 — 곡 구성은 한 번에 제일 많이 잃는 자리다
      check('되돌리기가 뜬다', find.text('되돌리기').evaluate().isNotEmpty, '스낵바에 되돌리기');
    }

    // ignore: avoid_print
    print(fail == 0 ? '씬 화면 위쪽 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });

  // 5단계 28/N — **패턴이 하나도 없는 씬**. 폰에서 잡은 고장이다:
  // 패턴이 '없음' 이면 「음 찍기」 버튼이 눌리지 않았다(`onPressed: null`).
  // 그런데 색이 거의 같아 보여서, 눌러도 아무 일이 안 나는 **고장으로 보인다.**
  testWidgets('씬이 통째로 비었을 때', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = Project.initial();
    for (final t in p.tracks) {
      p.setClip(t, null); // 전부 '없음 (안 침)'
    }
    final tr = Transport();

    Future<void> show() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SceneView(project: p, transport: tr, host: null),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }

    await show();

    // 1) 무음이라는 걸 그 자리에서 알려 준다
    check(
      '1) 무음 안내',
      find.textContaining('아무 소리도 안 납니다').evaluate().isNotEmpty,
      '씬 전체가 없음일 때만',
    );

    // 2) 패턴이 없어도 「음 찍기」가 눌린다 → 편집기가 열린다
    final lead = p.tracks.firstWhere((t) => t.type == 'melody');
    final i = p.tracks.indexOf(lead);
    await tester.tap(find.byIcon(Icons.edit_note).at(i));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    check(
      '2) 빈 판도 편집기가 열린다',
      find.text('${lead.name} 편집').evaluate().isNotEmpty,
      '편집 화면',
    );

    // 3) 들어가는 순간 **빈 내 패턴**이 생긴다 (음은 0개)
    final made = lead.pattern;
    final notes = made == null ? null : p.findNote('melody', made)?.notes;
    check(
      '3) 빈 판이 생긴다',
      made != null && p.isMine(made) && notes != null && notes.isEmpty,
      '패턴 $made · 음 ${notes?.length}개',
    );

    // 4) 하나라도 실리면 안내는 사라진다
    Navigator.of(tester.element(find.text('${lead.name} 편집'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    check(
      '4) 실리면 안내가 사라진다',
      find.textContaining('아무 소리도 안 납니다').evaluate().isEmpty,
      '한 트랙이라도 있으면',
    );

    // 5~7) **「쉬기」는 확인하고 뺀다** (5단계 44/N).
    //      예전엔 ⊖ 를 누르면 확인도 없이 바로 빠졌고, 무엇이 빠졌는지도 안 알려 줬다.
    final drum = p.tracks.firstWhere((t) => t.type == 'drum');
    p.setClip(drum, 'Lofi Chorus');
    await show();

    await tester.tap(find.byIcon(Icons.do_not_disturb_on_outlined).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    check(
      '5) 쉬기 전에 묻는다',
      find.textContaining('쉬게 할까요').evaluate().isNotEmpty &&
          drum.pattern == 'Lofi Chorus',
      '확인 창 · 아직 ${drum.pattern}',
    );

    // 무엇이 빠지는지 **이름을 댄다** — 기억에 의존하면 안 된다
    check(
      '6) 무엇이 빠지는지 알려 준다',
      find.textContaining(patternShort('Lofi Chorus')).evaluate().isNotEmpty,
      '「${patternShort('Lofi Chorus')}」 이 빠진다고 적혀 있음',
    );

    await tester.tap(find.text('취소'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    check('7) 취소하면 그대로', drum.pattern == 'Lofi Chorus', '${drum.pattern}');

    // 8~9) **씬 삭제는 되돌릴 수 있어야 한다.**
    //      씬 하나에 트랙 전부의 패턴이 들어 있고, 그 씬을 쓰던 **곡 구간까지**
    //      같이 지워진다. 여태 확인도 되돌리기도 없었다.
    p.song.sections.clear();
    for (final n in [0, 1, 1]) {
      p.song.add(n);
    }
    final scenes0 = p.scenes.length;
    final secs0 = p.song.sections.length;
    final victim = p.scenes[1].name;
    await show();

    // 10) **메뉴에 눈으로 닿는다** — 길게 누르기만으로는 있는 줄도 모른다.
    //     지금 씬에만 ⋮ 가 붙는다(하나만 나와야 안 어지럽다).
    check(
      '10) 지금 씬에 ⋮ 가 하나 있다',
      find.byIcon(Icons.more_vert).evaluate().length == 1,
      '${find.byIcon(Icons.more_vert).evaluate().length}개',
    );
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    check(
      '10-b) 눌러서 메뉴가 열린다',
      find.text('복제').evaluate().isNotEmpty,
      '이름 바꾸기·복제·삭제',
    );
    await tester.tapAt(const Offset(200, 60)); // 시트 밖을 눌러 닫는다
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.longPress(find.text(victim).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('삭제'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    check(
      '8) 씬을 지우면 되돌리기가 뜬다',
      p.scenes.length == scenes0 - 1 && find.text('되돌리기').evaluate().isNotEmpty,
      '씬 ${p.scenes.length}개 · 구간 ${p.song.sections.length}개',
    );
    // 곡에서 몇 군데가 같이 빠졌는지 **숫자로 말해 준다** — 안 그러면 눈치도 못 챈다
    check(
      '8-b) 곡에서 빠진 것도 알려 준다',
      find.textContaining('군데도 같이 빠졌어요').evaluate().isNotEmpty,
      '스낵바 문구',
    );

    await tester.tap(find.text('되돌리기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    check(
      '9) 누르면 씬도 곡 구간도 돌아온다',
      p.scenes.length == scenes0 && p.song.sections.length == secs0,
      '씬 ${p.scenes.length}/$scenes0 · 구간 ${p.song.sections.length}/$secs0',
    );

    // ignore: avoid_print
    print(fail == 0 ? '빈 씬 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
