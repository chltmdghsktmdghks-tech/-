// 프로젝트 설정 시트 확인 — 스타일·조를 씬/타임라인 화면에서 여기로
// 옮긴 뒤 나온 새 화면.
//   flutter test test/project_settings_ui_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/project_settings_sheet.dart';

void main() {
  testWidgets('프로젝트 설정', (tester) async {
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
    var changed = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showProjectSettingsSheet(
                  context,
                  project: p,
                  transport: tr,
                  master: MasterChannel(),
                  onChanged: () => changed++,
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    // 1) 스타일 한 줄 손잡이가 있다(지금 스타일 이름이 보인다)
    check(
      '1) 스타일 손잡이',
      find.textContaining('로파이').evaluate().isNotEmpty,
      '지금 스타일 이름이 보인다',
    );

    // 2) 12키가 처음부터 다 펼쳐져 있다(따로 펼치는 시트 없이 한 화면)
    final keys = kMinorKeyNames.where((k) => find.text(k).evaluate().isNotEmpty).length;
    check('2) 조 12개가 바로 보인다', keys == 12, '$keys/12');

    // 3) 조를 고르면 실제로 바뀐다
    await tester.tap(find.text('F'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('장조 (밝다)'));
    await tester.pump(const Duration(milliseconds: 50));
    check(
      '3) 고른 조가 반영',
      tr.root == 5 && tr.mode == 'major' && changed > 0,
      '루트 ${tr.root}(F=5) · ${tr.mode} · onChanged $changed번',
    );

    // 5) 느낌 한 줄 손잡이도 있다(만진 적 없으면 손잡이 글자도 "느낌") —
    //    누르면 느낌 시트(다섯 손잡이)가 겹쳐 열린다.
    final feelLabels = find.text('느낌');
    check('5) 느낌 손잡이', feelLabels.evaluate().length >= 2, '제목+손잡이 값');
    await tester.tap(feelLabels.last);
    await tester.pumpAndSettle();
    check(
      '6) 느낌 시트가 열린다',
      find.textContaining('신남').evaluate().isNotEmpty,
      '',
    );

    check('4) 예외 없음', tester.takeException() == null, '');

    // ignore: avoid_print
    print(fail == 0 ? '프로젝트 설정 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
