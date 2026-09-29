// 닫힌 하이햇 톤 — 「칫칫」(어둡고 둔함) 대 「띳띳」(선명). 고역 셸프 전후를 잰다.
//   flutter test test/hat_bright_test.dart
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/drum_sampler.dart';
import 'package:music_doodle_engine/drums.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/synth.dart' show Human;

void _fft(Float64List re, Float64List im) {
  final n = re.length;
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final tr = re[i]; re[i] = re[j]; re[j] = tr;
      final ti = im[i]; im[i] = im[j]; im[j] = ti;
    }
  }
  for (var len = 2; len <= n; len <<= 1) {
    final ang = -2 * math.pi / len;
    for (var i = 0; i < n; i += len) {
      for (var k = 0; k < len ~/ 2; k++) {
        final wr = math.cos(ang * k), wi = math.sin(ang * k);
        final ur = re[i + k], ui = im[i + k];
        final vr = re[i + k + len ~/ 2] * wr - im[i + k + len ~/ 2] * wi;
        final vi = re[i + k + len ~/ 2] * wi + im[i + k + len ~/ 2] * wr;
        re[i + k] = ur + vr; im[i + k] = ui + vi;
        re[i + k + len ~/ 2] = ur - vr; im[i + k + len ~/ 2] = ui - vi;
      }
    }
  }
}


/// 앞 1024 점의 (스펙트럼 무게중심 Hz, 4kHz 위 에너지 비, 8kHz 위 에너지 비).
List<double> _spec(Float64List x) {
  const len = 1024; // 앞 21ms — 「띳」은 어택에서 정해진다
  final re = Float64List(len), im = Float64List(len);
  for (var i = 0; i < len && i < x.length; i++) {
    re[i] = x[i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / (len - 1)));
  }
  _fft(re, im);
  var tot = 0.0, w = 0.0, h4 = 0.0, h8 = 0.0;
  for (var k = 1; k < len ~/ 2; k++) {
    final f = k * kSampleRate / len;
    final e = re[k] * re[k] + im[k] * im[k];
    tot += e;
    w += e * f;
    if (f >= 4000) h4 += e;
    if (f >= 8000) h8 += e;
  }
  return [w / tot, h4 / tot, h8 / tot];
}

Float64List _hit(String inst, int vel) {
  Human.setLevel(0);
  final d = DrumVoice()..trigger(inst, DRUM_KITS['acoustic']!, vel);
  final n = (0.4 * kSampleRate).round();
  final o = Float64List(n);
  for (var i = 0; i < n; i++) {
    if (d.active) d.next();
    o[i] = (d.outL + d.outR) * 0.5;
  }
  return o;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await ensureDrumPieceLoaded('hatClosed', set: 'avirt');
    await ensureDrumPieceLoaded('hatOpen', set: 'avirt');
  });

  test('닫힌 하이햇 — 셸프 후 무게중심이 오르고 고역이 산다', () {
    final o = StringBuffer();
    for (final v in [1, 2]) {
      // 원본(셸프 전): 두 벌 평균
      final b = kDrumSampleBanks[drumBankKey('hatClosed', 'avirt')]!;
      var c0 = 0.0, a0 = 0.0, b0 = 0.0;
      for (final c in b.byVel[v]!) {
        final x = Float64List(c.pcm.length);
        for (var i = 0; i < x.length; i++) {
          x[i] = c.pcm[i] / 32768.0;
        }
        final s = _spec(x); // 44.1k 표본이라 48k 축과 조금 다르지만 전후 비교용 근사
        c0 += s[0] / 2; a0 += s[1] / 2; b0 += s[2] / 2;
      }
      var c1 = 0.0, a1 = 0.0, b1 = 0.0;
      const N = 24;
      for (var k = 0; k < N; k++) {
        final s = _spec(_hit('hat', v));
        c1 += s[0] / N; a1 += s[1] / N; b1 += s[2] / N;
      }
      o.writeln('v$v 무게중심 ${c0.round()} -> ${c1.round()} Hz | >4k ${(a0 * 100).toStringAsFixed(0)}% -> '
          '${(a1 * 100).toStringAsFixed(0)}% | >8k ${(b0 * 100).toStringAsFixed(0)}% -> ${(b1 * 100).toStringAsFixed(0)}%');
      expect(c1, greaterThan(c0 + 1200), reason: 'v$v 밝아졌다');
      expect(a1, greaterThan(0.7), reason: 'v$v 4kHz 위가 주');
    }
    // ignore: avoid_print
    print(o);
  });
}
