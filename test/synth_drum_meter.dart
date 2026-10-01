// 합성 드럼(808·909·로파이 합성 경로)의 스펙트럼·어택을 재는 수동 도구.
//   flutter test test/synth_drum_meter.dart
//
// 「띳띳 vs 칫칫」(하이햇 고역 부족)과 「트랜지언트가 구리다」를 숫자로 본다:
//  · 8k↑ / 12k↑ — 앞 2048점(43ms) 에너지 중 이 위쪽 비율. 어쿠스틱 하이햇 표본은 8k↑ 72%.
//  · 무게중심 Hz
//  · 어택: 앞 3ms 에너지가 앞 40ms 에너지에서 차지하는 비율(%) · 피크(dBFS) · 크레스트
//  · 킥 클릭: 앞 8ms 의 2k↑ 에너지 / 앞 8ms 전체(%) — 비터 「딱」의 또렷함
//  · 100ms RMS(dBFS) — 레벨 밸런스 확인용
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

Float64List render(String inst, DrumKit kit, int vel, {bool direct = true, int sec = 1}) {
  Human.setLevel(0);
  final d = DrumVoice();
  if (direct) {
    switch (inst) {
      case 'kick': d.kick(kit, vel); break;
      case 'snare': d.snare(kit, vel); break;
      case 'hat': d.hat(kit, vel); break;
      case 'hatopen': d.hat(kit, 3, longOpen: true); break;
      case 'clap': d.clap(kit, vel); break;
    }
  } else {
    d.trigger(inst == 'hatopen' ? 'hat' : inst, kit, vel, longOpen: inst == 'hatopen');
  }
  final n = kSampleRate * sec;
  final o = Float64List(n);
  for (var i = 0; i < n; i++) {
    if (d.active) d.next();
    o[i] = (d.outL + d.outR) * 0.5;
  }
  return o;
}

String measure(Float64List x) {
  const len = 2048;
  final re = Float64List(len), im = Float64List(len);
  for (var i = 0; i < len; i++) {
    re[i] = x[i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / (len - 1)));
  }
  _fft(re, im);
  var tot = 0.0, w = 0.0, h8 = 0.0, h12 = 0.0;
  for (var k = 1; k < len ~/ 2; k++) {
    final f = k * kSampleRate / len;
    final e = re[k] * re[k] + im[k] * im[k];
    tot += e;
    w += e * f;
    if (f >= 8000) h8 += e;
    if (f >= 12000) h12 += e;
  }
  double en(int a, int b) {
    var s = 0.0;
    for (var i = a; i < b && i < x.length; i++) {
      s += x[i] * x[i];
    }
    return s;
  }

  final e3 = en(0, 144), e40 = en(0, 1920);
  var pk = 0.0;
  for (final v in x) {
    if (v.abs() > pk) pk = v.abs();
  }
  final rms100 = math.sqrt(en(0, 4800) / 4800);
  // 킥 클릭: 앞 8ms 의 2k↑
  final hp = Biquad()..highpass(2000, 0);
  var ec = 0.0, e8 = 0.0, hpk = 0.0;
  for (var i = 0; i < 384; i++) {
    final y = hp.process(x[i]);
    ec += y * y;
    e8 += x[i] * x[i];
    if (i < 288 && y.abs() > hpk) hpk = y.abs(); // 앞 6ms 2k↑ 피크
  }
  String db(double v) => v <= 0 ? '-inf' : (20 * math.log(v) / math.ln10).toStringAsFixed(1);
  String pc(double v) => (v * 100).toStringAsFixed(0).padLeft(3);
  return 'cen ${(w / tot).round().toString().padLeft(5)}Hz  8k↑${pc(h8 / tot)}%  12k↑${pc(h12 / tot)}%  '
      'atk3ms ${pc(e3 / (e40 + 1e-12))}%  click2k↑ ${pc(ec / (e8 + 1e-12))}%  clkPk ${db(hpk / (pk + 1e-9))}  pk ${db(pk).padLeft(5)}  rms100 ${db(rms100).padLeft(5)}  crest ${db(pk / (rms100 + 1e-9))}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final p in ['hatClosed', 'hatOpen', 'kick', 'snare']) {
      await ensureDrumPieceLoaded(p, set: 'unruly');
      await ensureDrumPieceLoaded(p);
    }
  });
  test('합성 드럼 스펙트럼', () {
    final o = StringBuffer();
    for (final inst in ['hat', 'hatopen', 'kick', 'snare', 'clap']) {
      for (final kn in ['lofi', 'k808', 'k909']) {
        for (final v in (inst == 'hatopen' ? [3] : [2])) {
          o.writeln('${inst.padRight(8)} ${kn.padRight(5)} v$v  ${measure(render(inst, DRUM_KITS[kn]!, v))}');
        }
      }
    }
    o.writeln('--- 기준: 표본 킷(trigger 경유) ---');
    for (final inst in ['hat', 'hatopen', 'kick', 'snare']) {
      for (final kn in ['acoustic', 'lofi']) {
        o.writeln('${inst.padRight(8)} ${kn.padRight(8)} v2  ${measure(render(inst, DRUM_KITS[kn]!, 2, direct: false))}');
      }
    }
    // ignore: avoid_print
    print(o);
  });
}
