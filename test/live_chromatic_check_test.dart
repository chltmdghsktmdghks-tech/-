// 라이브 반음 건반 확인 — `ChromaticPad` (live_ops.dart).
//   flutter test test/live_chromatic_check_test.dart
//
// 화면(live_view.dart)의 피아노는 **자리만** 그린다 — 무슨 음이 나는지,
// 지금 조에 맞는지는 여기서 정한 계산을 그대로 쓴다. 그래서 숫자로 본다.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/live_ops.dart';
import 'package:music_doodle_engine/theory.dart';

void main() {
  test('반음 건반', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final cMajor = MusicKey(root: 0, mode: 'major');

    // 1) 반음 0(으뜸음)은 semiFreq(0,...) 과 같은 소리 — 옥타브 배율만 얹는다
    final f0 = ChromaticPad.freqOf(0, cMajor, 0);
    final expect0 = semiFreq(0, 'melody', cMajor);
    check(
      '1) 으뜸음 주파수',
      (f0 - expect0).abs() < 0.001,
      '$f0 vs $expect0',
    );

    // 2) 옥타브 버튼을 올리면 정확히 2배
    final f0up = ChromaticPad.freqOf(0, cMajor, 1);
    check('2) 옥타브 +1 = 2배', (f0up - f0 * 2).abs() < 0.001, '$f0up vs ${f0 * 2}');

    // 3) C 장조에서 도(0)·레(2)·미(4)·파(5)·솔(7)·라(9)·시(11) 7개가 음계 안
    final inScale = [
      for (var s = 0; s < 12; s++) ChromaticPad.inScale(s, cMajor),
    ];
    final wantIn = {0, 2, 4, 5, 7, 9, 11};
    final gotIn = {
      for (var s = 0; s < 12; s++)
        if (inScale[s]) s,
    };
    check('3) 장조 음계 7개', gotIn.length == 7 && gotIn.containsAll(wantIn), '$gotIn');

    // 4) 나머지 5개(반음)는 음계 밖 — 검은 건반 자리와 같다
    final wantOut = {1, 3, 6, 8, 10};
    final gotOut = {
      for (var s = 0; s < 12; s++)
        if (!inScale[s]) s,
    };
    check('4) 반음 5개는 밖', gotOut.length == 5 && gotOut.containsAll(wantOut), '$gotOut');

    // 5) 조를 옮겨도(D 장조, root=2) 「으뜸음에서 몇 반음」식은 그대로다
    //    — inScale(0)은 늘 참(으뜸음은 항상 음계 안)
    final dMajor = MusicKey(root: 2, mode: 'major');
    check(
      '5) 조가 바뀌어도 으뜸음은 늘 음계 안',
      ChromaticPad.inScale(0, dMajor) && ChromaticPad.inScale(0, cMajor),
      '',
    );

    // 6) events() 는 단음 한 줄만 낸다(코드·아르페지오 없음)
    final ev = ChromaticPad.events(
      semi: 4,
      key: cMajor,
      oct: 0,
      voice: 'bell',
      dur: 0.9,
    );
    check('6) 반음 건반은 늘 단음', ev.length == 1, '${ev.length}줄');

    // ignore: avoid_print
    print(fail == 0 ? '반음 건반 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
