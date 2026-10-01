// 합성 킷(808·909·로파이)의 하이햇 고역과 킥·스네어 앞머리가 다시 어두워지지 않게 지킨다.
// 재는 표는 test/synth_drum_meter.dart. 결정론(Human 0, 합성 경로 직접 호출).
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/drums.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/synth.dart' show Human;

Float64List _render(void Function(DrumVoice) hit) {
  Human.setLevel(0);
  final d = DrumVoice();
  hit(d);
  final o = Float64List(kSampleRate ~/ 2);
  for (var i = 0; i < o.length; i++) {
    if (d.active) d.next();
    o[i] = (d.outL + d.outR) * 0.5;
  }
  return o;
}

/// 앞 2048점에서 [hz] 위 에너지 비율 — FFT 없이
/// 모든 빈을 직접 DFT 로 잰다(빈을 건너뛰면 잡음이라 값이 흔들린다).
double _above(Float64List x, double hz) {
  const n = 2048;
  var tot = 0.0, hi = 0.0;
  for (var k = 1; k < 1024; k++) {
    final f = k * kSampleRate / n;
    var re = 0.0, im = 0.0;
    for (var i = 0; i < n; i++) {
      final w = 0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1));
      re += x[i] * w * math.cos(2 * math.pi * k * i / n);
      im -= x[i] * w * math.sin(2 * math.pi * k * i / n);
    }
    final e = re * re + im * im;
    tot += e;
    if (f >= hz) hi += e;
  }
  return hi / tot;
}

/// 앞 6ms 의 2kHz 위 피크 ÷ 전체 피크 (dB) — 클릭이 몸통에 비해 얼마나 서 있나.
double _clickDb(Float64List x) {
  final hp = Biquad()..highpass(2000, 0);
  var pk = 0.0, hpk = 0.0;
  for (var i = 0; i < x.length; i++) {
    if (x[i].abs() > pk) pk = x[i].abs();
  }
  for (var i = 0; i < 288; i++) {
    final y = hp.process(x[i]).abs();
    if (y > hpk) hpk = y;
  }
  return 20 * math.log(hpk / pk) / math.ln10;
}

void main() {
  for (final kn in ['k808', 'k909', 'lofi']) {
    final kit = DRUM_KITS[kn]!;
    test('$kn 합성 하이햇 — 8kHz 위가 70% 근처, 12kHz 위도 산다', () {
      final c = _above(_render((d) => d.hat(kit, 2)), 8000);
      final h = _above(_render((d) => d.hat(kit, 2)), 12000);
      expect(c, greaterThan(0.65), reason: '$kn 닫힌 햇 8k↑');
      expect(h, greaterThan(0.25), reason: '$kn 닫힌 햇 12k↑');
      final o = _above(_render((d) => d.hat(kit, 3, longOpen: true)), 8000);
      expect(o, greaterThan(0.65), reason: '$kn 열린 햇 8k↑');
    });
    test('$kn 합성 킥 — 비터 클릭이 몸통 피크 −7dB 안에 선다', () {
      expect(_clickDb(_render((d) => d.kick(kit, 2))), greaterThan(-7.0));
    });
  }
  test('808·909 스네어 — 앞머리 크랙', () {
    for (final kn in ['k808', 'k909']) {
      expect(_clickDb(_render((d) => d.snare(DRUM_KITS[kn]!, 2))), greaterThan(-4.5), reason: kn);
    }
  });
}
