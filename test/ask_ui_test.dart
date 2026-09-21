// **질문 화면** — 열 걸음을 끝까지 갈 수 있는가.
//   flutter test test/ask_ui_test.dart
//
// 이 화면의 값어치는 「끝까지 간다」 하나다. 중간에 막히거나 되돌아갈 길이
// 없으면 아무도 안 끝낸다. 그래서 보는 것: 한 번에 하나만 묻는가 · 고르면
// 바로 넘어가는가 · 「이전」이 있는가 · 열 번째에서 답이 다 모여 나오는가.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/ask_song.dart';
import 'package:music_doodle_engine/ui/ask_sheet.dart';

void main() {
  testWidgets('질문 화면', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $what — $detail');
      if (!ok) fail++;
    }

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Map<String, String>? got;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: TextButton(
                onPressed: () => showAskSheet(ctx, onDone: (a) => got = a),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // 1) 첫 질문만 보인다 — 열 개를 한 화면에 늘어놓으면 설문지가 된다.
    final first = kAskQuestions.first;
    check('1) 첫 질문이 보인다', find.text(first.q).evaluate().isNotEmpty, '');
    check(
      '1-b) 다음 질문은 안 보인다',
      find.text(kAskQuestions[1].q).evaluate().isEmpty,
      '',
    );
    check(
      '1-c) 몇 번째인지 적는다',
      find.textContaining('1 / 10').evaluate().isNotEmpty,
      '',
    );

    // 2) 첫 질문에는 「이전」이 없다 — 갈 데가 없는 손잡이는 헷갈리기만 한다.
    check('2) 첫 질문엔 이전 없음', find.text('이전').evaluate().isEmpty, '');

    // 3) 고르면 **바로** 다음으로 (「다음」 버튼이 없다)
    await tester.tap(find.text(first.answers.first.$2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    check(
      '3) 고르면 다음 질문',
      find.text(kAskQuestions[1].q).evaluate().isNotEmpty,
      '',
    );
    check('3-b) 이제 이전이 있다', find.text('이전').evaluate().isNotEmpty, '');

    // 3-c) 「이전」이 정말 되돌아간다
    await tester.tap(find.text('이전'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    check('3-c) 이전으로 돌아온다', find.text(first.q).evaluate().isNotEmpty, '');

    // 4) 끝까지 가면 **답이 다 모여** 나온다
    for (var i = 0; i < kAskQuestions.length; i++) {
      final q = kAskQuestions[i];
      // 답을 돌아가며 골라 본다 — 늘 첫 답만 고르면 한 길만 시험하게 된다.
      final pick = q.answers[i % q.answers.length].$2;
      await tester.tap(find.text(pick));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }
    check(
      '4) 열 걸음 끝에 답이 다 나온다',
      got != null && got!.length == kAskQuestions.length,
      '${got?.length ?? -1}개',
    );
    check(
      '4-b) 화면이 닫힌다',
      find.text(kAskQuestions.last.q).evaluate().isEmpty,
      '',
    );
    check('4-c) 넘침 없음', tester.takeException() == null, '');

    // 5) 그 답으로 **정말 곡이 나온다**
    if (got != null) {
      final r = askRecipe(got!);
      check(
        '5) 답 → 곡',
        r.genre.isNotEmpty && r.bpm >= 60 && r.targetSec > 60,
        '${r.genre} · ${r.bpm.round()}BPM · ${r.targetSec.round()}초',
      );
      check(
        '5-b) 한 줄로 적어 준다',
        askSummary(got!, r).isNotEmpty,
        askSummary(got!, r),
      );
    }

    expect(fail, 0, reason: '$fail개 항목이 어긋났습니다');
  });
}
