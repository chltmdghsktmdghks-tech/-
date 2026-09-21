// 프로젝트 설정 「스타일 바꾸기」 확인 — 2026-09 부터 **편성(트랙·씬·패턴)은
// 그대로 두고 박자(빠르기·시간표기)와 마스터링만** 바뀐다.
//   flutter test test/project_style_change_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/project_settings_sheet.dart';

void main() {
  testWidgets('스타일 바꾸기 — 편성은 그대로', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = Project.initial(); // lofi 로 seed — 트랙 4개 + 씬 5개
    final tr = Transport();
    final master = MasterChannel();
    var changed = 0;

    // 바꾸기 전 값들 — 편성이 그대로인지 견줄 기준.
    final trackIdsBefore = p.tracks.map((t) => t.id).toList();
    final scenesJsonBefore = [for (final s in p.scenes) s.toJson().toString()];

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
                  master: master,
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

    // 스타일 한 줄 손잡이 — 지금은 「로파이」
    await tester.tap(find.text('로파이'));
    await tester.pumpAndSettle();

    // 하우스로 고른다(목록이 길어 스크롤해야 보인다).
    await tester.dragUntilVisible(
      find.text('하우스'),
      find.byType(ListView).last,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('하우스'));
    await tester.pumpAndSettle();

    check(
      '1) 빠르기가 하우스 것으로 바뀐다',
      tr.bpm == 124,
      '${tr.bpm} BPM',
    );
    check('2) 장르 이름표가 바뀐다', p.genre == 'house', p.genre);
    check(
      '3) 트랙은 그대로(개수·id 하나도 안 바뀜)',
      p.tracks.map((t) => t.id).toList().toString() == trackIdsBefore.toString(),
      '${p.tracks.map((t) => t.id).toList()}',
    );
    check(
      '4) 씬·클립(편성)도 그대로',
      [for (final s in p.scenes) s.toJson().toString()].toString() ==
          scenesJsonBefore.toString(),
      '',
    );
    check(
      '5) 마스터 인서트가 장르 자동으로 채워진다(클럽감 프리셋)',
      master.chain.isNotEmpty && master.fxAuto,
      '${master.chain.length}개 · auto=${master.fxAuto}',
    );
    check('6) onChanged 가 불린다', changed > 0, '$changed번');
    check('7) 되돌리기 단추가 뜬다', find.text('되돌리기').evaluate().isNotEmpty, '');

    check('8) 예외 없음', tester.takeException() == null, '');

    // ignore: avoid_print
    print(fail == 0 ? '스타일 바꾸기 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
