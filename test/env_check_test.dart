// 5단계 48/N — 악기 엔벨로프 확인.
//   flutter test test/env_check_test.dart
//
// 엔벨로프는 **귀로는 '뭔가 달라졌네'까지만 확인된다.** 기타 어택을 1.8ms 로
// 적어 놓고 실제로는 4ms 로 서고 있어도 소리는 그럴듯하다. 그래서 숫자로 본다:
//  · 어택   — 악기마다 소리가 서는 시간이 실제로 다른가
//  · 세기   — 세게 치면 더 빨리 서고 더 밝은가
//  · 울림   — 높은 음이 낮은 음보다 빨리 죽는가
//  · 길이   — 어택을 늘렸는데 **음 전체 길이가 밀리지는 않았는가**
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/instruments.dart';
import 'package:music_doodle_engine/synth.dart';

/// 음 하나를 [sec] 초만큼 뽑는다. (좌우 평균)
List<double> _render(
  String voice, {
  double freq = 1046.5,
  double dur = 0.6,
  int vel = 2,
  bool hq = false,
  double sec = 3.0,
}) {
  final n = SynthNote();
  n.noteOn(voice, freq, dur, vel, highQuality: hq);
  final total = (sec * kSampleRate).round();
  final out = List<double>.filled(total, 0);
  for (var i = 0; i < total; i++) {
    if (!n.active) break;
    n.next();
    out[i] = (n.outL + n.outR) * 0.5;
  }
  return out;
}

/// 어택 시간(ms) — **누적 최댓값**이 꼭대기의 90% 에 닿는 시각.
/// 누적 최댓값을 쓰는 이유: 파형이 0을 지나는 순간에 속지 않는다(반주기만 늦어질 뿐).
double _attackMs(List<double> x) {
  var peak = 0.0;
  for (final v in x) {
    final a = v.abs();
    if (a > peak) peak = a;
  }
  if (peak <= 0) return -1;
  var run = 0.0;
  for (var i = 0; i < x.length; i++) {
    final a = x[i].abs();
    if (a > run) run = a;
    if (run >= peak * 0.9) return i / kSampleRate * 1000;
  }
  return -1;
}

/// 소리가 남아 있는 마지막 시각(초) — 꼭대기의 [th] 아래로 내려가 다시 안 올라오는 곳.
double _tailSec(List<double> x, {double th = 0.02}) {
  var peak = 0.0;
  for (final v in x) {
    final a = v.abs();
    if (a > peak) peak = a;
  }
  final lim = peak * th;
  for (var i = x.length - 1; i >= 0; i--) {
    if (x[i].abs() > lim) return i / kSampleRate;
  }
  return 0;
}

/// 꼭대기의 [frac] 아래로 내려가 다시 안 올라오는 시각(초).
/// 총 길이를 잴 때 꼬리(_tailSec)를 쓰면 **세기에 따라 값이 달라진다** —
/// 릴리즈가 고정된 무음값까지 지수로 떨어지기 때문이다(작은 음일수록 늦게 걸린다).
/// 절반 지점은 그 영향을 거의 안 받는다.
double _fallSec(List<double> x, double frac) {
  var peak = 0.0;
  for (final v in x) {
    final a = v.abs();
    if (a > peak) peak = a;
  }
  final lim = peak * frac;
  for (var i = x.length - 1; i >= 0; i--) {
    if (x[i].abs() > lim) return i / kSampleRate;
  }
  return 0;
}

/// [hz] 위쪽 에너지가 전체에서 차지하는 비율 — 밝기를 재는 값.
double _highRatio(List<double> x, double hz, {int n = 0}) {
  final hp = Biquad()..highpass(hz, 0.707);
  final end = n == 0 ? x.length : math.min(n, x.length);
  var hi = 0.0, all = 0.0;
  for (var i = 0; i < end; i++) {
    final h = hp.process(x[i]);
    hi += h * h;
    all += x[i] * x[i];
  }
  return all <= 0 ? 0 : hi / all;
}

void main() {
  test('악기 엔벨로프', () {
    Human.setLevel(0); // 흔들기를 끄고 잰다 — 안 그러면 잴 때마다 값이 달라진다
    var fail = 0;
    void check(String name, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $name — $detail');
      if (!ok) fail++;
    }

    // ── 1) 어택이 악기마다 다른가 ──
    // 실제: 피크로 긁는 기타는 2ms 도 안 걸리고, 활을 긋는 스트링은 100ms 가까이 걸린다.
    final aGuitar = _attackMs(_render('guitar'));
    final aPiano = _attackMs(_render('piano'));
    final aSax = _attackMs(_render('sax'));
    final aStr = _attackMs(_render('strings'));
    check(
      '1) 어택 순서 — 기타 < 피아노 < 색소폰 < 스트링',
      aGuitar < aPiano && aPiano < aSax && aSax < aStr,
      '${aGuitar.toStringAsFixed(1)} < ${aPiano.toStringAsFixed(1)} < '
          '${aSax.toStringAsFixed(1)} < ${aStr.toStringAsFixed(1)} ms',
    );

    check(
      '2) 뜯는 악기는 3ms 안에 선다',
      aGuitar < 3.0,
      '기타 ${aGuitar.toStringAsFixed(2)}ms',
    );
    check('3) 활은 60ms 넘게 걸린다', aStr > 60.0, '스트링 ${aStr.toStringAsFixed(1)}ms');

    // ── 2) 세기에 따라 어택이 달라지는가 ──
    // 해머·피크가 세게 밀수록 현이 빨리 튄다. 여태는 세기와 무관했다.
    final soft = _attackMs(_render('piano', vel: 1));
    final hard = _attackMs(_render('piano', vel: 3));
    check(
      '4) 세게 치면 빨리 선다',
      hard < soft * 0.75,
      '여리게 ${soft.toStringAsFixed(2)}ms · 세게 ${hard.toStringAsFixed(2)}ms',
    );

    // ── 3) 세기에 따라 밝기가 달라지는가 ──
    // 피아노의 세기 차이는 '음량'이 아니라 '음색'으로 먼저 들린다.
    final bSoft = _highRatio(
      _render('piano', freq: 261.63, vel: 1, hq: true),
      900,
      n: (0.25 * kSampleRate).round(),
    );
    final bHard = _highRatio(
      _render('piano', freq: 261.63, vel: 3, hq: true),
      900,
      n: (0.25 * kSampleRate).round(),
    );
    check(
      '5) 세게 치면 밝다',
      bHard > bSoft * 1.25,
      '여리게 ${(bSoft * 100).toStringAsFixed(1)}% · 세게 ${(bHard * 100).toStringAsFixed(1)}%',
    );

    // ── 4) 음정에 따라 울림이 달라지는가 ──
    // 실제 피아노는 최저음이 20초 넘게 울리고 최고음은 1초도 안 간다.
    final low = _tailSec(_render('piano', freq: 65.4, sec: 6));
    final high = _tailSec(_render('piano', freq: 1046.5, sec: 6));
    check(
      '6) 낮은 음이 더 오래 운다',
      low > high * 1.8,
      '저음 ${low.toStringAsFixed(2)}초 · 고음 ${high.toStringAsFixed(2)}초',
    );

    final gLow = _tailSec(_render('guitar', freq: 82.4, sec: 6));
    final gHigh = _tailSec(_render('guitar', freq: 659.3, sec: 6));
    check(
      '7) 기타도 같다',
      gLow > gHigh * 1.6,
      '6번줄 ${gLow.toStringAsFixed(2)}초 · 1번줄 ${gHigh.toStringAsFixed(2)}초',
    );

    // ── 5) 어택을 늘렸는데 음 길이가 밀리지 않았는가 ──
    // **이걸 안 잡으면 스트링 어택을 90ms 로 바꾼 순간 곡 전체가 밀린다.**
    // 세기를 바꾸면 어택이 수십 ms 씩 움직인다 — 그런데도 총 길이가 그대로여야
    // 보정이 실제로 걸린 것이다. (릴리즈가 지수라 절대값은 표보다 짧게 재진다.)
    for (final v in ['strings', 'sax', 'pad', 'organ']) {
      final t1 = _fallSec(_render(v, freq: 261.63, vel: 1, sec: 4), 0.5);
      final t3 = _fallSec(_render(v, freq: 261.63, vel: 3, sec: 4), 0.5);
      final ak = ATK[v] ?? ATK_DEF;
      final swing = ak[0] * (math.pow(2, ak[1]) - math.pow(2, -ak[1]));
      // 보정이 없으면 차이가 어택 움직임(swing)만큼 그대로 난다.
      check(
        '8) $v 총 길이 그대로',
        (t1 - t3).abs() < math.max(0.020, swing * 0.5),
        '여리게 ${t1.toStringAsFixed(3)} · 세게 ${t3.toStringAsFixed(3)}초 '
            '(어택은 ${(swing * 1000).toStringAsFixed(0)}ms 움직였다)',
      );
    }

    // ── 6) 오르간 키 클릭 ──
    // 해먼드는 건반을 누르는 순간 접점이 '틱' 한다. 이게 없으면 사인 패드다.
    final clickOn = _highRatio(
      _render('organ', freq: 261.63, hq: true),
      1500,
      n: (0.005 * kSampleRate).round(),
    );
    final clickOff = _highRatio(
      _render('organ', freq: 261.63, hq: false),
      1500,
      n: (0.005 * kSampleRate).round(),
    );
    check(
      '9) 오르간 키 클릭',
      clickOn > clickOff * 1.6,
      '있음 ${(clickOn * 100).toStringAsFixed(1)}% · 없음 ${(clickOff * 100).toStringAsFixed(1)}%',
    );

    // ── 7) 표에 빠진 악기가 없는가 ──
    final missing = [
      for (final v in ALL_VOICES)
        if (!ATK.containsKey(v)) v,
    ];
    check(
      '10) 어택 표 — 빠진 악기 없음',
      missing.isEmpty,
      missing.isEmpty ? '${ALL_VOICES.length}종' : missing.join(', '),
    );

    // ignore: avoid_print
    print(fail == 0 ? '악기 엔벨로프 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
