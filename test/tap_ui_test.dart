// 5단계 46/N — 「두드려 넣기」 **화면**을 시험이 직접 눌러 본다.
//   flutter test test/tap_ui_test.dart
//
// 계산은 `tap_check_test.dart` 가 본다. 여기서 보는 건 다른 것이다:
//  · 편집기에서 **닿을 수 있는가**(세로·가로 둘 다)
//  · 이미 있는 음을 **말없이 지우지 않는가**
//  · 두드릴 판이 트랙에 맞게 나오는가(가락 1개 · 드럼 4개)
//  · 그만두면 판이 **그대로인가**
//
// 소리 엔진(host)은 없다. 그래서 미리 세기가 저절로 굴러가지 않는다 —
// 「지금 몇 초인가」가 없으면 셀 수가 없기 때문이다. 여기서 재는 것은 그 앞까지다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/editor_view.dart';

Widget _app(Project p, Track t) => MaterialApp(
  theme: ThemeData.dark(),
  home: Scaffold(
    body: EditorView(
      project: p,
      transport: Transport(),
      track: t,
      host: null, // 소리 없이 화면만
    ),
  ),
);

void main() {
  testWidgets('두드려 넣기 화면', (tester) async {
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
    final mel = p.tracks.firstWhere((t) => t.type == 'melody');
    await tester.pumpWidget(_app(p, mel));
    await tester.pump();

    final name = mel.pattern!;
    List<List<Object?>> notes() => p.findNote('melody', name)!.notes;

    check(
      '1) 편집기에 단추가 있다',
      find.text('두드려 넣기').evaluate().isNotEmpty,
      '「두드려 넣기」',
    );

    // 2) **음이 있는 판이면 묻는다.** 되돌리기가 있어도, 방금 만든 것이 사라지는
    //    순간의 놀람은 되돌려지지 않는다.
    check('2) 판에 음이 있다(묻는 조건)', notes().isNotEmpty, '음 ${notes().length}개');
    await tester.tap(find.text('두드려 넣기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final asked = find.text('이 판에 이미 음이 있습니다').evaluate().isNotEmpty;
    check(
      '2-b) 지우기 전에 묻는다',
      asked &&
          find.text('지우고 시작').evaluate().isNotEmpty &&
          find.text('위에 더하기').evaluate().isNotEmpty &&
          find.text('취소').evaluate().isNotEmpty,
      '지우고 시작 · 위에 더하기 · 취소',
    );

    // 2-c) 취소하면 **아무 일도 안 일어난다**
    final before = notes().length;
    await tester.tap(find.text('취소'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    check(
      '2-c) 취소하면 그대로',
      notes().length == before &&
          find.text('이 판에 이미 음이 있습니다').evaluate().isEmpty,
      '음 ${notes().length}개',
    );

    // 3) **빈 판이면 안 묻는다** — 물어봤자 고를 것이 없다.
    p.putUserPattern('melody', name, note: NotePatternDef(name, 2, 2, const []));
    await tester.pump();
    await tester.tap(find.text('두드려 넣기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    check(
      '3) 빈 판은 바로 열린다',
      find.text('이 판에 이미 음이 있습니다').evaluate().isEmpty &&
          find.text('그만두기').evaluate().isNotEmpty,
      '두드릴 판이 열렸다',
    );

    // 4) 고를 것들이 다 있다
    check(
      '4) 자·메트로놈·반주',
      find.text('8분').evaluate().isNotEmpty &&
          find.text('16분').evaluate().isNotEmpty &&
          find.text('메트로놈').evaluate().isNotEmpty &&
          find.text('반주').evaluate().isNotEmpty,
      '8분 · 16분 · 메트로놈 · 반주',
    );

    // 5) 가락 트랙은 **큰 판 하나**. 높낮이를 여기서 고르게 하면 두 가지를 한 번에
    //    하게 되는데, 그게 원래 어려웠던 바로 그 문제다.
    check(
      '5) 가락은 판 하나',
      find.text('두드리기').evaluate().length == 1 &&
          find.text('쿵').evaluate().isEmpty,
      '「두드리기」 1개',
    );

    // 6) 소리 엔진이 없으면 **세지 않고, 안 센다고 말한다.**
    //    「지금 몇 초인가」가 소리에서 오기 때문이다. 여기서 저절로 넘어가면
    //    그건 시계 없이 센 것이라 실기에서 어긋난다.
    await tester.pump(const Duration(seconds: 2));
    check(
      '6) 시계가 없으면 안 세고, 그렇다고 말한다',
      find.textContaining('소리를 아직 못 켰습니다').evaluate().isNotEmpty,
      '대기 그대로 · 이유를 적어 둔다',
    );

    // 7) 그만두면 **판이 그대로**
    await tester.tap(find.text('그만두기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    check(
      '7) 그만두면 그대로',
      notes().isEmpty && find.text('그만두기').evaluate().isEmpty,
      '음 ${notes().length}개 · 시트 닫힘',
    );

    // ── 8) 드럼은 판이 넷 ──
    final drum = p.tracks.firstWhere((t) => t.type == 'drum');
    await tester.pumpWidget(_app(p, drum));
    await tester.pump();
    // 드럼 판을 비워 두면 묻지 않는다
    final dname = drum.pattern!;
    p.putUserPattern('drum', dname, drum: DrumPatternDef(dname, 2, 2, const {}));
    await tester.pump();
    await tester.tap(find.text('두드려 넣기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    check(
      '8) 드럼은 판이 넷',
      find.text('쿵').evaluate().isNotEmpty &&
          find.text('탁').evaluate().isNotEmpty &&
          find.text('치').evaluate().isNotEmpty &&
          find.text('둥').evaluate().isNotEmpty,
      '쿵 · 탁 · 치 · 둥',
    );

    // 9) 세로에서 안 넘친다
    check('9) 세로 안 넘침', tester.takeException() == null, '넘침 예외 없음');

    // 10) **가로에서도** 넘치지 않는다. 여기가 제일 좁다 — 판 넷을 400px 높이에
    //     넣어야 한다(가로에서 두드리는 것이 오히려 자연스럽다).
    tester.view.physicalSize = const Size(800, 400);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    check('10) 가로 안 넘침', tester.takeException() == null, '넘침 예외 없음');
    check(
      '10-b) 가로에서도 판 넷이 다 보인다',
      find.text('쿵').evaluate().isNotEmpty &&
          find.text('둥').evaluate().isNotEmpty,
      '쿵 ~ 둥',
    );

    await tester.tap(find.text('그만두기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 11) 가로 편집기에서도 **닿을 수 있다.** 글자는 자리가 없어 그림표만 남겼다 —
    //     그림표까지 없으면 가로로 눕힌 사람에게는 이 기능이 아예 없는 것이다.
    check(
      '11) 가로에서도 단추가 있다',
      find.byIcon(Icons.touch_app).evaluate().isNotEmpty,
      '그림표로 남아 있다',
    );

    // ignore: avoid_print
    print(fail == 0 ? '두드려 넣기 화면 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
