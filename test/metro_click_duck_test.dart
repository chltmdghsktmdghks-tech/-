// 메트로놈: 또렷한 클릭 + 켜지는 프레임에 맞춘 덕킹.
//   flutter test test/metro_click_duck_test.dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/engine.dart';
import 'package:music_doodle_engine/live_ops.dart';
import 'package:music_doodle_engine/synth.dart';

void main() {
  test('metroBatch — 다운비트가 더 높고 세며 kPartMetro 로 나간다', () {
    final b = metroBatch([MetTick(0, 0.0), MetTick(1, 0.5)]);
    expect(b[0][7], kPartMetro);
    expect(b[0][1] as double, greaterThan(b[1][1] as double));
    expect(b[0][3] as int, greaterThan(b[1][3] as int));
    expect(b[1][3] as int, greaterThanOrEqualTo(2)); // 약박이 vel1 로 묻히지 않는다
  });

  test('덕킹 — 클릭이 켜지는 프레임에 시간 정렬되고 자동 복귀한다', () {
    // 반주: 슬롯 0 에 긴 소리 하나
    Engine mk() {
      final e = Engine()..trackMix.configure(['a', 'b', 'c']);
      e.schedule(0, 'sine', 220, 2.0, 3, part: 0);
      return e;
    }

    const delay = 0.5;
    final e = mk();
    e.schedule(delay, 'marimba', 2093, 0.06, 3, part: kPartMetro);
    final at = (delay * 48000).round();
    e.render(at - 1); // 클릭 직전까지
    expect(e.metroDuckLevel, 1.0, reason: '클릭 전엔 안 눌린다');
    e.render(48); // 1ms 뒤
    expect(e.metroDuckLevel, lessThan(1.0), reason: '켜진 직후부터 눌린다');
    e.render(2400); // 50ms 지점
    final minL = e.metroDuckLevel;
    expect(minL, greaterThan(0.74));
    expect(minL, lessThan(0.85)); // 약 -2.5dB ≈ 0.75
    e.render(48000 ~/ 10); // 100ms 더
    expect(e.metroDuckLevel, 1.0, reason: '자동 복귀 — 상태가 안 남는다');
  });

  test('메트로놈이 없으면 덕 값은 정확히 1.0 (기존 소리 불변)', () {
    final e = Engine()..trackMix.configure(['a', 'b', 'c']);
    e.schedule(0, 'sine', 220, 1.0, 3, part: 0);
    e.render(4800);
    expect(e.metroDuckLevel, 1.0);
  });

  test('클릭 레벨 — 약박도 반주 RMS 근처까지 올라온다', () {
    double peak(double f, int vel) {
      final e = Engine()..trackMix.configure(['a', 'b', 'c']);
      e.schedule(0, 'marimba', f, 0.06, vel, part: kPartMetro);
      final o = e.render(4800);
      var p = 0.0;
      for (var i = 0; i < 4800; i++) {
        p = math.max(p, (o[i * 2] / 32768.0).abs());
      }
      return p;
    }

    final down = peak(2093, 3), weak = peak(1568, 2);
    // ignore: avoid_print
    print('다운 pk=${down.toStringAsFixed(3)} 약박 pk=${weak.toStringAsFixed(3)}');
    expect(weak, greaterThan(0.15)); // 예전 0.049
    expect(down, greaterThan(weak * 1.5)); // 다운비트 구분 유지
  });
}
