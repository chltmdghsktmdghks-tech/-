// 5단계 47/N — **박자 표가 성한가.**
//   flutter test test/meter_check_test.dart
//
// 박자는 한 번 틀리면 곡 전체가 조용히 어긋난다 — 소리는 나는데 마디가 안 맞는다.
// 오류도 안 난다. 그래서 표 자체를 먼저 잰다.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/meter.dart';
import 'package:music_doodle_engine/patterns.dart' show kStepsPerBar;

void main() {
  test('박자 표', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    // 1) **칸 수가 손으로 센 것과 같다.** 옛 앱 `meterSteps()` 와 같은 값이어야 한다 —
    //    다르면 옛 곡을 열 때 마디가 밀린다.
    const want = {'4/4': 16, '3/4': 12, '6/8': 12, '5/4': 20, '7/8': 14};
    final got = {for (final m in kMeters) m.key: m.stepsPerBar};
    check('1) 마디당 칸 수', '$got' == '$want', '$got');

    // 2) **4/4 는 여태와 똑같다.** 여기가 어긋나면 이미 만든 곡이 전부 흔들린다.
    check(
      '2) 4/4 는 16칸 그대로',
      meterStepsOf('4/4') == kStepsPerBar && kMeterFour.key == '4/4',
      '${meterStepsOf('4/4')}칸',
    );

    // 2-b) `kMeterFour` 가 목록 첫 항목과 **같은 값**인가 — 따로 적어 둔 표라
    //      한쪽만 고치는 날이 온다.
    final f = kMeters.first;
    check(
      '2-b) 기본 4/4 가 목록 첫 항목과 같다',
      kMeterFour.key == f.key &&
          kMeterFour.beats == f.beats &&
          kMeterFour.unit == f.unit &&
          kMeterFour.clickSteps == f.clickSteps &&
          '${kMeterFour.strongAt}' == '${f.strongAt}' &&
          kMeterFour.feel == f.feel,
      '${kMeterFour.label} · ${kMeterFour.stepsPerBar}칸',
    );

    // 3) **모르는 키는 4/4 로 본다.** null 을 돌려주면 부르는 쪽마다 `?? 4/4` 를
    //    적게 되고, 언젠가 한 곳을 빠뜨린다.
    check(
      '3) 모르는 박자는 4/4',
      meterOf(null).isFour &&
          meterOf('9/16').isFour &&
          meterOf('').isFour &&
          meterStepsOf('없는것') == 16,
      'null · 9/16 · 빈 문자열 다 4/4',
    );

    // 4) **키가 겹치지 않는다.** 겹치면 `meterOf` 가 먼저 것만 돌려줘서 뒤엣것은
    //    영영 안 골라진다(오류 없이).
    final keys = {for (final m in kMeters) m.key};
    check('4) 키가 유일하다', keys.length == kMeters.length, '${keys.length}개');

    // 5) **이름표가 키와 같다.** 화면에는 label 을 적고 저장은 key 로 하는데
    //    둘이 다르면 「3/4 로 골랐는데 저장은 딴것」이 된다.
    final bad = [
      for (final m in kMeters)
        if (m.label != m.key) '${m.key}≠${m.label}',
    ];
    check('5) 이름표 = 키', bad.isEmpty, bad.isEmpty ? '5개 다 같음' : '$bad');

    // 6) **메트로놈이 마디에 딱 떨어진다.** 안 떨어지면 마디를 넘을 때마다
    //    「하나」가 조금씩 밀린다 — 홀수 박자에서 제일 티 나는 고장이다.
    final off = [
      for (final m in kMeters)
        if (m.stepsPerBar % m.clickSteps != 0)
          '${m.key}: ${m.stepsPerBar}칸을 ${m.clickSteps}칸마다',
    ];
    check('6) 메트로놈이 마디에 떨어진다', off.isEmpty, off.isEmpty ? '5개 다 떨어짐' : '$off');

    // 7) **세게 치는 자리가 마디 안에 있다.** 밖이면 그 마디에는 「하나」가 없다.
    final out = [
      for (final m in kMeters)
        for (final s in m.strongAt)
          if (s < 0 || s >= m.stepsPerBar) '${m.key}@$s',
    ];
    check('7) 강세가 마디 안', out.isEmpty, out.isEmpty ? '전부 안' : '$out');

    // 7-b) **강세는 메트로놈이 치는 칸에만 있다.** 안 치는 칸에 강세를 적어 두면
    //      그 강세는 영영 안 들린다(적어 놓기만 한 것이 된다).
    final unheard = [
      for (final m in kMeters)
        for (final s in m.strongAt)
          if (s % m.clickSteps != 0) '${m.key}@$s',
    ];
    check(
      '7-b) 강세가 치는 칸 위에 있다',
      unheard.isEmpty,
      unheard.isEmpty ? '전부 들린다' : '$unheard',
    );

    // 8) **마디 첫 칸은 늘 세다.** 어디가 마디 머리인지는 어떤 박자에서도 들려야 한다.
    final noHead = [
      for (final m in kMeters)
        if (!m.strongAt.contains(0)) m.key,
    ];
    check('8) 마디 첫 칸은 세게', noHead.isEmpty, noHead.isEmpty ? '5개 다' : '$noHead');

    // 9) **6/8 은 셋씩 두 갈래.** 「둘」로만 치면 초보가 그 사이를 못 채우고,
    //    강세가 없으면 그냥 6/4 처럼 들린다.
    final m68 = meterOf('6/8');
    check(
      '9) 6/8 은 여섯 번 치고 1·4 가 세다',
      m68.clicksPerBar == 6 && '${m68.strongAt}' == '[0, 6]',
      '${m68.clicksPerBar}번 · 강세 ${m68.strongAt}',
    );

    // 10) **7/8 은 2+2+3.** 일곱을 고르게 세면 마디 머리가 안 들린다.
    final m78 = meterOf('7/8');
    check(
      '10) 7/8 은 2+2+3',
      '${m78.strongAt}' == '[0, 4, 8]' && m78.clicksPerBar == 7,
      '${m78.clicksPerBar}번 · 강세 ${m78.strongAt}',
    );

    // 11) **마디를 넘어도 「하나」가 제자리.** 판은 여러 마디이고 칸 번호는 계속
    //     늘어난다 — 접어서 보지 않으면 둘째 마디부터 강세가 사라진다.
    {
      final m = meterOf('3/4');
      final strong = [
        for (var s = 0; s < m.stepsPerBar * 4; s++)
          if (meterStrongAt(m, s)) s,
      ];
      check(
        '11) 마디마다 「하나」가 있다 (3/4 × 4마디)',
        '$strong' == '[0, 12, 24, 36]',
        '$strong',
      );
    }

    // 12) **박 번호가 1 부터 마지막 박까지 돈다.** 「2마디 3박」을 적는 자리가 쓴다.
    for (final m in kMeters) {
      final beats = {
        for (var s = 0; s < m.stepsPerBar * 2; s++) meterBeatAt(m, s),
      };
      final want = {for (var i = 1; i <= m.clicksPerBar; i++) i};
      check(
        '12) 박 번호 1~${m.clicksPerBar} (${m.key})',
        '${beats.toList()..sort()}' == '${want.toList()..sort()}',
        '${beats.toList()..sort()}',
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '박자 표 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
