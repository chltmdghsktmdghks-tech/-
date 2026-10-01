// 악기 품질 측정 도구 (수동 실행) — 밝기(센트로이드)·고역 비율·스테레오 폭·움직임.
//   flutter test test/inst_quality_meter.dart
//
// 「싸구려로 들린다」를 숫자로 잡으려고 만든다. 정답표가 아니라 **악기끼리 비교하는 자**다.
//   cen   : 0.2~1.0s 구간 스펙트럼 무게중심(Hz)
//   hf%   : 4~12kHz 에너지 비율 — 너무 낮으면 둔탁, 너무 높으면 쇳소리
//   sub%  : 150Hz 아래 비율(베이스의 바닥)
//   wid%  : 좌우 다름 정도 (1-corr)/2 — 0 이면 모노(납작), 유니즌·코러스가 있으면 올라간다
//   mov   : 0.3~1.2s 50ms RMS 의 흔들림(dB 표준편차, 추세 제거) — 0 이면 정지 화면 같은 소리
//   pk/rms: 피크 · 가장 큰 100ms RMS (dBFS)
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/instruments.dart';
import 'package:music_doodle_engine/sampler.dart';
import 'package:music_doodle_engine/synth.dart';

double _db(double v) => v <= 1e-9 ? -120 : 20 * math.log(v) / math.ln10;

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

class Row {
  final String name;
  final double cen, hf, sub, wid, mov, pk, rms, acen, ahf;
  Row(this.name, this.cen, this.hf, this.sub, this.wid, this.mov, this.pk, this.rms, this.acen, this.ahf);
  String get s =>
      '${name.padRight(12)} acen ${acen.toStringAsFixed(0).padLeft(5)} ahf ${ahf.toStringAsFixed(2).padLeft(5)} | cen ${cen.toStringAsFixed(0).padLeft(5)}  hf ${hf.toStringAsFixed(2).padLeft(5)}  '
      'sub ${sub.toStringAsFixed(1).padLeft(5)}  wid ${wid.toStringAsFixed(1).padLeft(5)}  '
      'mov ${mov.toStringAsFixed(2).padLeft(5)}  pk ${_db(pk).toStringAsFixed(1).padLeft(6)}  rms ${_db(rms).toStringAsFixed(1).padLeft(6)}';
}

Row measure(String v, double f, {double dur = 1.2, int vel = 3}) {
  Human.setLevel(0);
  final n = SynthNote()..noteOn(v, f, dur, vel);
  final total = (2.0 * kSampleRate).round();
  final l = Float64List(total), r = Float64List(total);
  var len = 0;
  for (; len < total; len++) {
    if (!n.active) break;
    n.next();
    l[len] = n.outL;
    r[len] = n.outR;
  }
  final m = Float64List(total);
  var pk = 0.0, sLR = 0.0, sLL = 0.0, sRR = 0.0;
  for (var i = 0; i < total; i++) {
    m[i] = (l[i] + r[i]) * 0.5;
    pk = math.max(pk, math.max(l[i].abs(), r[i].abs()));
    sLR += l[i] * r[i];
    sLL += l[i] * l[i];
    sRR += r[i] * r[i];
  }
  final corr = sLL * sRR <= 0 ? 1.0 : sLR / math.sqrt(sLL * sRR);
  // spectrum 0.2..1.0s (8192 pts x 4 avg)
  const nf = 8192;
  final acc = Float64List(nf ~/ 2);
  for (var st = (0.2 * kSampleRate).round(); st + nf <= (1.0 * kSampleRate).round() + nf && st + nf <= total; st += nf ~/ 2) {
    final re = Float64List(nf), im = Float64List(nf);
    for (var i = 0; i < nf; i++) {
      re[i] = m[st + i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / (nf - 1)));
    }
    _fft(re, im);
    for (var k = 1; k < nf ~/ 2; k++) {
      acc[k] += re[k] * re[k] + im[k] * im[k];
    }
  }
  var tot = 0.0, cs = 0.0, hf = 0.0, sub = 0.0;
  for (var k = 1; k < nf ~/ 2; k++) {
    final fr = k * kSampleRate / nf;
    tot += acc[k];
    cs += acc[k] * fr;
    if (fr >= 4000 && fr < 12000) hf += acc[k];
    if (fr < 150) sub += acc[k];
  }
  final cen = tot > 0 ? cs / tot : 0.0;
  // movement
  final w = (0.05 * kSampleRate).round();
  final ys = <double>[];
  for (var st = (0.3 * kSampleRate).round(); st + w <= (1.2 * kSampleRate).round() && st + w <= total; st += w) {
    var a = 0.0;
    for (var i = 0; i < w; i++) {
      a += m[st + i] * m[st + i];
    }
    ys.add(_db(math.sqrt(a / w)));
  }
  var mov = 0.0;
  if (ys.length > 3) {
    final nn = ys.length;
    final xm = (nn - 1) / 2, ym = ys.reduce((a, b) => a + b) / nn;
    var sxy = 0.0, sxx = 0.0;
    for (var i = 0; i < nn; i++) {
      sxy += (i - xm) * (ys[i] - ym);
      sxx += (i - xm) * (i - xm);
    }
    final b = sxy / sxx;
    var ss = 0.0;
    for (var i = 0; i < nn; i++) {
      final e = ys[i] - (ym + b * (i - xm));
      ss += e * e;
    }
    mov = math.sqrt(ss / nn);
  }
  // rms100
  final w2 = (0.1 * kSampleRate).round();
  var best = 0.0, a2 = 0.0;
  for (var i = 0; i < total; i++) {
    a2 += m[i] * m[i];
    if (i >= w2) a2 -= m[i - w2] * m[i - w2];
    if (i >= w2 - 1) best = math.max(best, math.sqrt(math.max(0, a2) / w2));
  }
  // attack spectrum: first 4096 samples after onset
  final ar = Float64List(4096), ai = Float64List(4096);
  for (var i = 0; i < 4096; i++) {
    ar[i] = m[i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / 4095));
  }
  _fft(ar, ai);
  var at = 0.0, ac = 0.0, ah = 0.0;
  for (var k = 1; k < 2048; k++) {
    final fr = k * kSampleRate / 4096;
    final e = ar[k] * ar[k] + ai[k] * ai[k];
    at += e;
    ac += e * fr;
    if (fr >= 4000 && fr < 12000) ah += e;
  }
  return Row(v, cen, tot > 0 ? hf / tot * 100 : 0, tot > 0 ? sub / tot * 100 : 0, (1 - corr) / 2 * 100, mov, pk, best,
      at > 0 ? ac / at : 0, at > 0 ? ah / at * 100 : 0);
}

const kBassSet = {'bass', 'moogbass', 'fingerbass', 'jbass', 'upright', 'wobble'};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await ensureSamplesLoaded();
  });
  test('instrument quality table', () {
    final o = StringBuffer();
    o.writeln('== 베이스류 (C2 65.41Hz, vel3)');
    for (final v in INSTRUMENTS.keys.where(kBassSet.contains)) {
      o.writeln(measure(v, 65.41).s);
    }
    o.writeln('== 그 밖 (C4 261.63Hz, vel3)');
    for (final v in INSTRUMENTS.keys.where((k) => !kBassSet.contains(k))) {
      o.writeln(measure(v, 261.63).s);
    }
    // ignore: avoid_print
    print(o);
  });
}
