// 느낌 시트가 **세로·가로 둘 다** 안 넘치는가.
//   flutter test test/feel_ui_test.dart
//
// 손잡이가 다섯이 됐다(기운·빽빽함·그루브·매듭·변화). 슬라이더 다섯 줄은
// 가로로 누웠을 때(높이 400) 화면보다 길다 — 넘치면 빨간 줄이 뜨고
// 「처음으로」가 손에 안 닿는다. 그래서 두 방향을 다 세워 놓고 본다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/feel.dart';
import 'package:music_doodle_engine/ui/feel_sheet.dart';

void main() {
  testWidgets('느낌 시트', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $what — $detail');
      if (!ok) fail++;
    }

    var got = Feel.none;
    Future<void> show(Size size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            key: ValueKey('${size.width}x${size.height}'),
            body: FeelSheetBody(value: const Feel(), onChanged: (f) => got = f),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }

    // ── 세로 ──
    await show(const Size(400, 800));
    var err = tester.takeException();
    check('1) 세로 안 넘침', err == null, '넘침 예외 ${err ?? '없음'}');
    for (final t in ['기운', '빽빽함', '그루브', '매듭', '변화']) {
      check('1-$t) 손잡이가 보인다', find.text(t).evaluate().isNotEmpty, '');
    }

    // ── 가로 ──
    await show(const Size(800, 400));
    err = tester.takeException();
    check('2) 가로 안 넘침', err == null, '넘침 예외 ${err ?? '없음'}');
    // 가로에서도 다섯 손잡이가 다 **닿을 수 있어야** 한다(스크롤로라도)
    for (final t in ['기운', '변화']) {
      final f = find.text(t);
      check('2-$t) 가로에서도 있다', f.evaluate().isNotEmpty, '');
    }
    await tester.ensureVisible(find.text('처음으로'));
    await tester.pump();
    check('2-b) 「처음으로」에 닿는다', tester.takeException() == null, '스크롤해서 보인다');

    // ── 손잡이가 실제로 값을 바꾼다 ──
    await show(const Size(400, 800));
    final slider = find.byType(Slider);
    check(
      '3) 슬라이더 다섯 개',
      slider.evaluate().length == 5,
      '${slider.evaluate().length}개',
    );
    await tester.drag(slider.at(4), const Offset(-200, 0));
    await tester.pump();
    check(
      '3-b) 변화를 줄이면 값이 내려간다',
      got.vary < 0.5,
      '${got.vary.toStringAsFixed(2)} · ${Feel.varyWord(got.vary)}',
    );

    tester.view.resetPhysicalSize();
    // ignore: avoid_print
    print(fail == 0 ? '느낌 시트 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
