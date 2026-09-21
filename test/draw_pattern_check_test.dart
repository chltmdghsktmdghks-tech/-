// 패턴 고르기 시트 — "직접 그리기" 확인.
//   flutter test test/draw_pattern_check_test.dart
//
// 손으로 직접 곡을 써 보다가 찾은 틈: 새 프로젝트는 기본이 「간단히」 모드라
// 가락·화음 패턴 고르기 시트에 미리 만든 패턴만 있고, 빈 판에 직접 그리러
// 가는 길이 그 안에는 없었다(음 편집기 진입점은 그 모드에서 숨어 있다).
// "음악 낙서장"이라는 이름값을 생각해 시트 안에 「간단히」 모드에서도 보이는
// "직접 그리기" 버튼을 추가했다 — 여기서는 그 버튼이 (1) 간단히 모드에서도
// 보이고 (2) 누르면 음 편집기로 넘어가는지, (3) 타임라인 레인 쪽(패턴을
// 정해서 그 자리에 놓아야 하는 화면)에는 안 나오는지를 본다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/scene_view.dart';

void main() {
  testWidgets('씬 화면 패턴 시트 — 직접 그리기', (tester) async {
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
          // simple: true — 「간단히」 모드에서도 이 버튼이 보여야 한다.
          body: SceneView(project: p, transport: tr, host: null, simple: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    // 「연필 아이콘」 자체는 간단히 모드에서 없다 — 이게 이번에 찾은 틈이다.
    check(
      '0) 간단히 모드엔 연필 아이콘이 없다',
      find.byIcon(Icons.edit_note).evaluate().isEmpty,
      '있으면 이 시험의 전제가 깨진다',
    );

    // 가락 트랙 행의 「패턴」 칸을 찾아 누른다.
    final patternFields = find.text('패턴');
    await tester.tap(patternFields.last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    check(
      '1) 간단히 모드에서도 「직접 그리기」가 보인다',
      find.text('직접 그리기').evaluate().isNotEmpty,
      '',
    );

    await tester.tap(find.text('직접 그리기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    check(
      '2) 누르면 음 편집기로 넘어간다',
      find.textContaining('편집').evaluate().isNotEmpty,
      '',
    );

    final err = tester.takeException();
    check('3) 넘어가는 길에 예외 없음', err == null, '${err ?? '없음'}');

    expect(fail, 0);
  });

  testWidgets('타임라인 레인 시트 — 직접 그리기 없음', (tester) async {
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

    // pickPatternSheet 를 직접 불러 allowDraw 기본값(true)과 false 를 비교한다
    // — 화면 전체를 세팅하는 대신 시트 하나만 열어 본다.
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => pickPatternSheet(
                  context,
                  title: '레인에 놓을 패턴',
                  names: const ['Lofi Chorus'],
                  current: null,
                  color: Colors.teal,
                  genre: p.genre,
                  isMine: (_) => false,
                  allowDraw: false,
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('열기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    check(
      '레인 쪽 시트엔 「직접 그리기」가 없다',
      find.text('직접 그리기').evaluate().isEmpty,
      '',
    );

    expect(fail, 0);
  });
}
