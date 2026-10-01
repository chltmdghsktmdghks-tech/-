// 2026-10-01 악기 품질(패드 스웰 · 플럭 배음) 회귀 시험 — 결정론적(난수·시계 없음).
// 재는 법: test/inst_quality_meter.dart (수동 표).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/instruments.dart';
import 'package:music_doodle_engine/synth.dart';

double _db(double v) => v <= 1e-9 ? -120 : 20 * math.log(v) / math.ln10;

/// 음 하나를 [sec] 초 렌더(좌우 합)해서 돌려준다.
Float64List _render(String v, double f, double dur, double sec) {
  Human.setLevel(0);
  final n = SynthNote()..noteOn(v, f, dur, 3);
  final total = (sec * kSampleRate).round();
  final m = Float64List(total);
  for (var i = 0; i < total; i++) {
    if (!n.active) break;
    n.next();
    m[i] = (n.outL + n.outR) * 0.5;
  }
  return m;
}

/// [from] 초부터 4096 샘플의 스펙트럼 무게중심(Hz).
double _centroid(Float64List x, double from) {
  const nf = 4096;
  final st = (from * kSampleRate).round();
  final re = Float64List(nf), im = Float64List(nf);
  for (var i = 0; i < nf && st + i < x.length; i++) {
    re[i] = x[st + i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / (nf - 1)));
  }
  // 단순 DFT 를 쓰기엔 느리니 바이트 반전 FFT.
  for (var i = 1, j = 0; i < nf; i++) {
    var bit = nf >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final t = re[i]; re[i] = re[j]; re[j] = t;
    }
  }
  for (var len = 2; len <= nf; len <<= 1) {
    final ang = -2 * math.pi / len;
    for (var i = 0; i < nf; i += len) {
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
  var tot = 0.0, cs = 0.0;
  for (var k = 1; k < nf ~/ 2; k++) {
    final e = re[k] * re[k] + im[k] * im[k];
    tot += e;
    cs += e * k * kSampleRate / nf;
  }
  return tot > 0 ? cs / tot : 0;
}

double _rms100(Float64List x) {
  final w = (0.1 * kSampleRate).round();
  var acc = 0.0, best = 0.0;
  for (var i = 0; i < x.length; i++) {
    acc += x[i] * x[i];
    if (i >= w) acc -= x[i - w] * x[i - w];
    if (i >= w - 1) best = math.max(best, math.sqrt(math.max(0, acc) / w));
  }
  return best;
}

double _peak(Float64List x) => x.fold(0.0, (m, v) => math.max(m, v.abs()));

void main() {
  test('패드·현악: 필터가 서서히 열린다 (뒤 구간이 앞 구간보다 밝다)', () {
    // 현악(strings·jpstrings)은 어택 때 숨소리 노이즈 층이 무게중심을 끌어올려 이 방법으로
    // 못 잰다 — 표 시험(아래)으로만 확인한다.
    for (final v in ['pad', 'analogpad']) {
      final x = _render(v, 261.63, 2.0, 2.2);
      final early = _centroid(x, 0.12), late = _centroid(x, 1.0);
      expect(late, greaterThan(early * 1.15), reason: '$v early $early late $late');
    }
  });

  test('패드: 사인 수준이 아니다 (어택 이후 무게중심이 기본음의 1.5배 이상)', () {
    final x = _render('pad', 261.63, 2.0, 2.2);
    expect(_centroid(x, 0.5), greaterThan(261.63 * 1.5));
  });

  test('플럭: 위 배음이 산다 (어택 무게중심이 기본음의 1.5배 이상)', () {
    final x = _render('pluck', 261.63, 0.5, 1.0);
    expect(_centroid(x, 0.0), greaterThan(261.63 * 1.5));
  });

  test('크기는 예전 선 근처 (2026-10-01 이전 rms ±1.5dB, 피크 천장 아래)', () {
    // 이전 측정(balance_meter, C4 vel3 100ms RMS, dBFS): pad -15.4 analogpad -19.6 strings -19.3
    // jpstrings -20.3 pluck -16.7
    const before = {
      'pad': -15.4,
      'analogpad': -19.6,
      'strings': -19.3,
      'jpstrings': -20.3,
      'pluck': -16.7,
    };
    for (final e in before.entries) {
      final x = _render(e.key, 261.63, 1.5, 3.0);
      expect((_db(_rms100(x)) - e.value).abs(), lessThan(1.5), reason: e.key);
      expect(_peak(x), lessThan(0.89), reason: '${e.key} 천장');
    }
  });

  test('표가 서로 맞는다 (PADSWELL 은 합성 패드만, 시작<끝)', () {
    for (final e in PADSWELL.entries) {
      expect(INSTRUMENTS.containsKey(e.key), isTrue);
      expect(PLUCKY[e.key], isNot(true), reason: '${e.key} 는 열렸다 닫히는 쪽이 아니다');
      expect(e.value[0], lessThan(e.value[1]));
      expect(e.value[2], greaterThan(0.1));
    }
  });
}
