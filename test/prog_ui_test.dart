// **코드 진행 서랍**이 실제로 열리고, 눌러서 바뀌는가. (세로·가로 둘 다)
//   flutter test test/prog_ui_test.dart
//
// 셈은 `prog_check_test` 가 본다. 여기서 보는 것은 **손이 닿는가**다:
// 씬 메뉴에 길이 있는가 · 자리마다 코드 이름이 뜨는가 · 눌러 고르면 실제로
// 프로젝트가 바뀌는가 · 좁은 화면과 누운 화면에서 안 넘치는가.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/theory.dart';
import 'package:music_doodle_engine/ui/prog_sheet.dart';
import 'package:music_doodle_engine/ui/scene_view.dart';

void main() {
  testWidgets('코드 진행', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    addTearDown(tester.view.reset);

    final p = Project.initial()..setGenre('lofi');
    final tr = Transport();

    Future<void> open(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
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

    // 1) 씬 메뉴에 길이 있다 — 없으면 있으나 마나다.
    await open(const Size(400, 800));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final entry = find.textContaining('코드 진행');
    check('1) 씬 메뉴에 있다', entry.evaluate().isNotEmpty, '');

    // 2) 눌러서 열면 자리마다 코드 이름이 뜬다
    if (entry.evaluate().isNotEmpty) {
      await tester.tap(entry.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }
    final (slots, _) = p.readSceneProg();
    final key = MusicKey(root: tr.root, mode: tr.mode);
    final shown = slots
        .where(
          (s) => find.text(chordNameOf(s.degree, key)).evaluate().isNotEmpty,
        )
        .length;
    check(
      '2) 자리마다 코드 이름',
      slots.isNotEmpty && shown > 0,
      '${slots.length}자리 · $shown개 보임',
    );
    // 「마디」는 재생선에도 있다 — 서랍이 안 열려도 찾아진다(재는 시늉만 하는 검사).
    // 서랍에만 있는 말로 본다.
    check(
      '2-b) 서랍이 열렸다',
      find.textContaining('베이스·멜로디도 같이').evaluate().isNotEmpty,
      '',
    );
    check('2-c) 세로 안 넘침', tester.takeException() == null, '');

    // 3) 자리를 누르면 7개가 나온다
    if (slots.isNotEmpty) {
      await tester.tap(find.text(slots.first.label).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final seven = [
        for (var d = 0; d < 7; d++) '${d + 1}도',
      ].where((t) => find.text(t).evaluate().isNotEmpty).length;
      check('3) 다이아토닉 7개', seven == 7, '$seven개');

      // 4) 골라 누르면 **정말 바뀐다** — 화면만 닫히고 아무 일도 안 일어나면 안 된다.
      final want = (slots.first.degree + 2) % 7;
      final was = slots.first.degree;
      await tester.tap(find.text('${want + 1}도'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final (now, _) = p.readSceneProg();
      final at = now.firstWhere(
        (s) => s.step == slots.first.step,
        orElse: () => slots.first,
      );
      check('4) 눌러서 바뀐다', at.degree == want, '${was + 1}도 → ${at.degree + 1}도');

      // 4-b) 되돌리기는 **서랍 안에** 있어야 한다 — 스낵바로 내면 서랍의 막 아래
      //      깔려서 눌러도 아무 일이 안 일어난다(처음에 그렇게 만들었다가 잡혔다).
      final undoFinder = find.textContaining('되돌리기 —');
      check('4-b) 되돌리기가 뜬다', undoFinder.evaluate().isNotEmpty, '');
      if (undoFinder.evaluate().isNotEmpty) {
        await tester.tap(undoFinder.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        final (back, _) = p.readSceneProg();
        final b = back.firstWhere(
          (s) => s.step == slots.first.step,
          orElse: () => slots.first,
        );
        check('4-c) 눌러서 되돌아온다', b.degree == was, '${b.degree + 1}도');
      }
    }
    // 5) **가로로 누운 폰**에서도 안 넘친다 — 서랍은 화면 높이의 절반까지만 쓴다.
    await open(const Size(800, 360));
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final e2 = find.textContaining('코드 진행');
    if (e2.evaluate().isNotEmpty) {
      await tester.tap(e2.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }
    check(
      '5) 가로 안 넘침',
      tester.takeException() == null &&
          find.textContaining('마디').evaluate().isNotEmpty,
      '',
    );

    expect(fail, 0, reason: '$fail개 항목이 어긋났습니다');
  });
}
