// 두들플레이 시작 전 설정 시트 확인 — 장르를 고른 뒤 빠르기·조·마디를
// 정하는 화면(`doodle_setup_sheet.dart`, 2026-09-29 신설).
//   flutter test test/doodle_setup_ui_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/project.dart' show keyLabel;
import 'package:music_doodle_engine/ui/doodle_play_view.dart'
    show kDoodleBarChoices;
import 'package:music_doodle_engine/ui/doodle_setup_sheet.dart';

void main() {
  testWidgets('두들플레이 설정 시트', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final genre = kGenres.first; // 로파이 — bpm·mode 가 뚜렷이 정해져 있다
    DoodleSetup? result;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  result = await showDoodleSetupSheet(
                    context,
                    genre: genre,
                    initialRoot: 3, // D# — 장르 기본값과 다른 값으로 시작
                  );
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    // 1) 장르 고르면 그 기본 BPM 이 채워진다.
    check(
      '1) 장르 기본 BPM 이 채워진다',
      find.text('${genre.bpm.round()} BPM').evaluate().isNotEmpty,
      '장르 기본값 ${genre.bpm.round()}BPM',
    );

    // 2) 조도 장르 기본 mode + 진입 시점 root 로 채워진다(장르는 root 를
    //    안 정하므로 호출부가 넘긴 initialRoot=3 를 써야 한다).
    check(
      '2) 조 초기값 = mode(장르)+root(진입 시점)',
      find.text(keyLabel(3, genre.mode)).evaluate().isNotEmpty,
      keyLabel(3, genre.mode),
    );

    // 3) 마디 기본값 4가 이미 골라져 있다(중간값).
    check(
      '3) 마디 기본 4',
      find.text('4마디').evaluate().isNotEmpty,
      'kDoodleBarChoices=$kDoodleBarChoices',
    );

    // 4) BPM +/- 가 동작한다.
    await tester.tap(find.byIcon(Icons.add).first);
    await tester.pump();
    check(
      '4) BPM + 누르면 1 오른다',
      find.text('${genre.bpm.round() + 1} BPM').evaluate().isNotEmpty,
      '+1',
    );
    await tester.tap(find.byIcon(Icons.remove).first);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.remove).first);
    await tester.pump();
    check(
      '4-b) BPM - 누르면 내려간다',
      find.text('${genre.bpm.round() - 1} BPM').evaluate().isNotEmpty,
      '-1(순누적 +1-1-1)',
    );

    // 5) 조 +/- 가 반음씩 움직이고(mod 12), 12개 root 모두 순환한다.
    //    root=3 에서 + 를 9번 누르면 3+9=12 → 0(C) 으로 넘어간다.
    for (var i = 0; i < 9; i++) {
      await tester.tap(find.byIcon(Icons.add).at(1)); // 두 번째 + 는 조 쪽
      await tester.pump();
    }
    check(
      '5) 조 + 가 반음씩 돌고 12에서 0으로 넘어간다(wrap)',
      find.text(keyLabel(0, genre.mode)).evaluate().isNotEmpty,
      keyLabel(0, genre.mode),
    );

    // 6) 장조/단조 토글이 실제로 바뀐다.
    final otherModeLabel = genre.mode == 'major' ? '단조 (어둡다)' : '장조 (밝다)';
    final otherMode = genre.mode == 'major' ? 'minor' : 'major';
    await tester.tap(find.text(otherModeLabel));
    await tester.pump();
    check(
      '6) 장조/단조 토글',
      find.text(keyLabel(0, otherMode)).evaluate().isNotEmpty,
      '$otherMode 로 전환',
    );

    // 7) 마디 2/4/8 중 고르면 선택이 바뀐다.
    await tester.tap(find.text('8마디'));
    await tester.pump();

    // 7-b) 터치 타깃 — 디자인 감사(2026-09-29): BPM/조 -/+ 버튼(`StepButton`,
    // 예전 36×36)과 마디 칩(`_PickChip`, 예전 세로 패딩 10 → 전체 ~36)이
    // 44dp 최소 터치 타깃에 못 미쳤다. 이제 보이는 손끝 영역이 44dp 이상인지
    // 여기서 잰다 — 다음에 누가 다시 줄이면 이 시험이 잡는다.
    final bpmPlusInkWell = tester.getSize(
      find
          .ancestor(of: find.byIcon(Icons.add).first, matching: find.byType(InkWell))
          .first,
    );
    check(
      '7-b) BPM +/- 버튼 터치 타깃 44dp 이상',
      bpmPlusInkWell.width >= 44 && bpmPlusInkWell.height >= 44,
      '${bpmPlusInkWell.width}×${bpmPlusInkWell.height}',
    );
    final barChipSize = tester.getSize(
      find
          .ancestor(of: find.text('8마디'), matching: find.byType(InkWell))
          .first,
    );
    check(
      '7-c) 마디 칩 터치 타깃 44dp 이상(세로)',
      barChipSize.height >= 44,
      '${barChipSize.width}×${barChipSize.height}',
    );

    // 8) 확정하면 시트가 닫히고 고른 값 그대로 돌아온다.
    await tester.tap(find.text('이 설정으로 시작'));
    await tester.pumpAndSettle();
    check(
      '8) 확정 시 고른 값 그대로 돌아온다',
      result != null &&
          result!.bpm == genre.bpm - 1 &&
          result!.root == 0 &&
          result!.mode == otherMode &&
          result!.bars == 8,
      result == null
          ? 'null'
          : 'bpm=${result!.bpm} root=${result!.root} mode=${result!.mode} bars=${result!.bars}',
    );

    check('9) 예외 없음', tester.takeException() == null, '');

    // ignore: avoid_print
    print(fail == 0 ? '두들플레이 설정 시트 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
