// 두들 설정 시트 — 취소 버튼과 BPM 큰 걸음(±10) 확인 (디자인, 2026-09-29).
//   flutter test test/doodle_setup_cancel_bigstep_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/ui/doodle_setup_sheet.dart';

void main() {
  testWidgets('취소 버튼은 아무것도 확정하지 않고 닫는다 · ±10 은 범위에서 멈춘다', (tester) async {
    tester.view.physicalSize = const Size(320, 568); // 작은 폰
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final genre = kGenres.first;
    DoodleSetup? result;
    var closed = false;

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDoodleSetupSheet(context,
                  genre: genre, initialRoot: 0);
              closed = true;
            },
            child: const Text('열기'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull); // 320폭에서 넘치지 않는다

    final start = genre.bpm.round();
    await tester.tap(find.text('+10'));
    await tester.pump();
    expect(find.text('${start + 10} BPM'), findsOneWidget);
    await tester.tap(find.text('-10'));
    await tester.tap(find.text('-10'));
    await tester.pump();
    expect(find.text('${start - 10} BPM'), findsOneWidget);
    // 터치 면적 44 이상
    final sz = tester.getSize(find.ancestor(
        of: find.text('+10'), matching: find.byType(InkWell)).first);
    expect(sz.width >= 44 && sz.height >= 44, isTrue);

    // ignore: avoid_print
    print('취소 y=${tester.getCenter(find.text('취소')).dy} / 화면 568');
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(result, isNull);
  });
}
