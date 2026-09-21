// Phase 2 — **간단히 보기**가 실제로 감추는가. (개선 계획 4-3)
//   flutter test test/simple_mode_test.dart
//
// 계획의 요구는 "기능을 제거하는 것이 아니라 **정보 노출량을 줄인다**" 이다.
// 그래서 두 가지를 같이 본다:
//   · 간단히 보기에서 **안 보이는가** (믹서·엔진 시험·조 고르기·음 편집기)
//   · 전부 보기로 돌리면 **다시 보이는가** (감춘 것이지 없앤 것이 아니다)
//
// 그리고 **세로·가로 둘 다** 본다. 가로는 높이가 귀해서 위쪽 바가 한 줄로 접히는데,
// 거기서 칩 하나를 빼면 배치가 달라진다 — 세로만 보고 넘기면 놓친다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/store.dart';
import 'package:music_doodle_engine/ui/home_view.dart';
import 'package:music_doodle_engine/ui/scene_view.dart';

void main() {
  testWidgets('간단히 보기', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $what — $detail');
      if (!ok) fail++;
    }

    final p = Project.initial();
    final tr = Transport();

    Future<void> pumpHome(bool simple, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      final st =
          Store(
              project: p,
              transport: tr,
              live: LiveChannel(),
              master: MasterChannel(),
            )
            ..simpleMode = simple
            ..guideSeen = true;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: HomeView(
            project: p,
            transport: tr,
            live: LiveChannel(),
            master: MasterChannel(),
            host: null,
            store: st,
            ready: true,
            onOpenLab: () {},
            onSongOpened: () {},
          ),
        ),
      );
      await tester.pump();
    }

    Future<void> pumpScene(bool simple, Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SceneView(
              project: p,
              transport: tr,
              host: null,
              simple: simple,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    // 새로 깐 폰처럼 — **저장 파일이 아예 없을 때** 기본이 무엇인가.
    // 폰에 새로 깔아 보고서야 알았다: 파일이 없으면 `start()` 의 분기를 안 타서
    // 필드 기본값이 그대로 남는다. 처음 쓰는 사람은 간단히 보기여야 한다.
    check(
      '0) 새로 깐 상태의 기본값',
      Store(
        project: Project.initial(),
        transport: Transport(),
        live: LiveChannel(),
        master: MasterChannel(),
      ).simpleMode,
      '간단히 보기로 시작',
    );

    const portrait = Size(400, 800), landscape = Size(800, 400);
    for (final (label, size) in [('세로', portrait), ('가로', landscape)]) {
      // ── 첫 화면 ──
      // **믹서는 이제 첫 화면에 없다**(2026-09 — 첫 화면이 프로젝트 고르기로
      // 바뀌면서, 믹서는 연 프로젝트 안(`ProjectWorkspace`)에서만 연다).
      // 그래서 여기서는 간단히·전부 보기 둘 다 믹서가 없는 게 정상이고,
      // 이 시험이 지키던 것(엔진 시험 화면·간단히 토글의 노출량)만 본다.
      await pumpHome(true, size);
      final simpleLab = find.text('엔진 시험 화면').evaluate().length;
      final backBtn = find.text('더 보기').evaluate().length;
      check(
        '$label · 첫 화면 — 간단히면 시험화면이 없다',
        simpleLab == 0,
        '시험 $simpleLab',
      );
      // **되돌아올 길이 반드시 보여야 한다** — 가로에서 화면 밖으로 밀린 적이 있다
      check('$label · 첫 화면 — 되돌아올 버튼이 보인다', backBtn == 1, '「더 보기」 $backBtn개');

      await pumpHome(false, size);
      // 머리줄 것은 **스크롤 없이** 보여야 한다
      check(
        '$label · 첫 화면 — 전부 보기면 머리줄에 다시 나온다',
        find.text('간단히').evaluate().length == 1,
        '간단히 보임',
      );
      // 아래쪽 것은 **닿을 수 있으면** 된다. 가로는 높이가 400px 이라 접히는데,
      // `ListView` 는 화면 밖을 아예 안 만들어서 그냥 찾으면 없다고 나온다.
      // "안 보인다"와 "없다"는 다르다 — 밀어서 확인한다.
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
      check(
        '$label · 첫 화면 — 엔진 시험 화면에 닿는다',
        find.text('엔진 시험 화면').evaluate().length == 1,
        '밀어 내리면 나온다',
      );

      // ── 만들기(씬) 화면 ──
      // 조·스타일 칩은 2026-09 부터 이 화면에 아예 없다(작업 화면 위쪽
      // 톱니바퀴의 「프로젝트 설정」으로 옮겼다) — 간단히/전부 보기와
      // 상관없이 늘 없다. 여기서는 음 편집기(연필)만 간단히 보기가 감추는지 본다.
      await pumpScene(true, size);
      final pencil = find.byIcon(Icons.edit_note).evaluate().length;
      check(
        '$label · 만들기 — 간단히면 음편집기가 없다',
        pencil == 0,
        '연필 $pencil개',
      );
      // 핵심 조작(음색·패턴)은 **그대로 있어야** 한다 — 이건 감출 것이 아니다
      final voice = find.text('음색').evaluate().length;
      final pat = find.text('패턴').evaluate().length;
      check(
        '$label · 만들기 — 음색·패턴은 그대로',
        voice > 0 && pat > 0,
        '음색 $voice · 패턴 $pat개',
      );
      // 느낌은 2026-09 부터 스타일·조와 함께 「프로젝트 설정」으로 옮겨서
      // 이제 이 화면(간단히든 전부든)에는 아예 없다 — 따로 확인할 게 없다.

      await pumpScene(false, size);
      check(
        '$label · 만들기 — 전부 보기면 연필이 다시 나온다',
        find.byIcon(Icons.edit_note).evaluate().isNotEmpty,
        '연필 ${find.byIcon(Icons.edit_note).evaluate().length}개',
      );

      // 넘침 없음 — 감추면 남은 것들이 밀린다
      check('$label · 넘침 없음', tester.takeException() == null, '');
    }

    tester.view.resetPhysicalSize();
    // ignore: avoid_print
    print(fail == 0 ? '간단히 보기 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
