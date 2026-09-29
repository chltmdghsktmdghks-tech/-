// 새 드럼 표본 세트(avirt = virtuosity_drums, 44.1kHz) vs 예전 세트(drum = MuldjordKit, 22.05kHz)
// 를 잰다 — 피크·100ms RMS·11kHz 위 에너지·킥 어택(비터 클릭)·하이햇/스네어 비.
//   flutter test test/drum_set_level_test.dart
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/drum_sampler.dart';
import 'package:music_doodle_engine/drums.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/synth.dart' show Human;

const _pieces = ['kick', 'snare', 'hatClosed', 'hatOpen', 'crash', 'ride', 'tom'];
const _sets = ['drum', 'avirt'];

double _db(double v) => v <= 1e-9 ? -120 : 20 * math.log(v) / math.ln10;

/// 한 번 쳐서 엔진 출력(48kHz, 좌우 합)을 [sec] 초 받는다.
Float64List _hit(String inst, String kit, int vel, double sec) {
  Human.setLevel(0);
  final d = DrumVoice()..trigger(inst, DRUM_KITS[kit]!, vel);
  final n = (sec * kSampleRate).round();
  final o = Float64List(n);
  for (var i = 0; i < n; i++) {
    if (d.active) d.next();
    o[i] = (d.outL + d.outR) * 0.5;
  }
  return o;
}

double _peak(Float64List x) => x.fold(0.0, (m, v) => math.max(m, v.abs()));

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

/// [lo,hi] Hz 대역 에너지 / 전체 에너지 (앞 [sec] 초, 단순 DFT 를 8192 점 FFT 로).
double _bandRatio(Float64List x, double lo, double hi, {int from = 0, int len = 8192, bool hann = true}) {
  final re = Float64List(len), im = Float64List(len);
  for (var i = 0; i < len && from + i < x.length; i++) {
    final w = hann ? 0.5 - 0.5 * math.cos(2 * math.pi * i / (len - 1)) : 1.0;
    re[i] = x[from + i] * w;
  }
  _fft(re, im);
  var tot = 0.0, band = 0.0;
  for (var k = 1; k < len ~/ 2; k++) {
    final f = k * kSampleRate / len;
    final e = re[k] * re[k] + im[k] * im[k];
    tot += e;
    if (f >= lo && f < hi) band += e;
  }
  return tot <= 0 ? 0 : band / tot;
}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final s in _sets) {
      for (final p in _pieces) {
        await ensureDrumPieceLoaded(p, set: s);
      }
    }
  });

  test('새 세트가 실제로 44.1kHz 로 읽힌다', () {
    for (final p in _pieces) {
      final b = kDrumSampleBanks[drumBankKey(p, 'avirt')]!;
      for (final v in [1, 2, 3]) {
        expect(b.byVel[v]!.length, 2, reason: '$p v$v 라운드로빈 2벌');
        for (final c in b.byVel[v]!) {
          expect(c.sampleRate, 44100, reason: '$p v$v');
        }
      }
      final old = kDrumSampleBanks[drumBankKey(p, 'drum')]!;
      expect(old.byVel[2]!.first.sampleRate, 22050, reason: '$p 예전 세트');
    }
  });

  test('새 어쿠스틱: 하이햇은 스네어보다 작고, 천장 아래, 고음이 산다', () {
    for (final v in [1, 2, 3]) {
      final sn = _peak(_hit('snare', 'acoustic', v, 1.5));
      final hat = _peak(_hit('hat', 'acoustic', v, 1.5));
      expect(hat, lessThan(sn * 0.7), reason: 'hat v$v < snare v$v');
    }
    // 닫힌 하이햇(v2)이 들릴 만큼은 있다 — 예전엔 rms -44.6dB 로 묻혔다.
    expect(_db(_rms100(_hit('hat', 'acoustic', 2, 1.0))), greaterThan(-40));
    for (final i in ['kick', 'snare', 'hat', 'tom', 'crash', 'ride']) {
      for (final v in [1, 2, 3]) {
        expect(_peak(_hit(i, 'acoustic', v, 2.0)), lessThan(0.89), reason: '$i v$v 천장');
      }
    }
    // 킥 비터 클릭 — 앞 20ms 의 2-6kHz 가 예전 세트(≈2.5%) 수준. 합성 클릭을
    // 빼면 0.3% 로 떨어진다(펠트 비터 킥이라 원본엔 클릭이 없다).
    expect(_bandRatio(_hit('kick', 'acoustic', 3, 1.0), 2000, 6000, len: 1024, hann: false),
        greaterThan(0.015));
    // 11kHz 위: 22.05kHz 표본엔 원래 없던 대역이다(하이햇·라이드에 뚜렷해야).
    expect(_bandRatio(_hit('hat', 'acoustic', 2, 1.0), 11000, 24000), greaterThan(0.02));
    expect(_bandRatio(_hit('ride', 'acoustic', 3, 2.0), 11000, 24000), greaterThan(0.05));
  });

  test('라운드로빈 — 같은 세기에서 서로 다른 녹음이 번갈아 나온다', () {
    for (final p in _pieces) {
      final b = kDrumSampleBanks[drumBankKey(p, 'avirt')]!;
      for (final v in [1, 2, 3]) {
        final a = b.byVel[v]![0].pcm, c = b.byVel[v]![1].pcm;
        var diff = 0;
        for (var i = 0; i < 2000 && i < a.length && i < c.length; i++) {
          if (a[i] != c[i]) diff++;
        }
        // 하이햇 닫힘 ff·라이드 ff 는 같은 층의 rr1/rr2 다(서로 다른 녹음).
        expect(diff, greaterThan(100), reason: '$p v$v rr1 != rr2');
      }
    }
  });

  test('예전 세트는 amuld 킷으로 그대로 남아 있다(되돌리기)', () {
    expect(DRUM_KITS['acoustic']!.sampleSet, 'avirt');
    expect(DRUM_KITS['amuld']!.sampleSet, 'drum');
    expect(DRUM_KITS['rock']!.sampleSet, 'drum');
    expect(DRUM_KITS['lofi']!.sampleSet, 'drum');
  });

  test('측정 표 (출력 = 예전 acoustic 대 새 acoustic)', () {
    final o = StringBuffer('== 드럼 세트 비교 (48kHz 엔진 출력, 좌우합)\n');
    o.writeln('조각      세기  |  예전(amuld) pk  rms  11k↑%  |  새(acoustic) pk  rms  11k↑%');
    final insts = ['kick', 'snare', 'hat', 'tom', 'crash', 'ride'];
    for (final i in insts) {
      for (final v in [1, 2, 3]) {
        final a = _hit(i, 'amuld', v, 2.0), b = _hit(i, 'acoustic', v, 2.0);
        String f(Float64List x) =>
            '${_db(_peak(x)).toStringAsFixed(1).padLeft(6)} ${_db(_rms100(x)).toStringAsFixed(1).padLeft(6)} '
            '${(_bandRatio(x, 11000, 24000) * 100).toStringAsFixed(2).padLeft(6)}';
        o.writeln('${i.padRight(8)}  v$v   |  ${f(a)}  |  ${f(b)}');
      }
    }
    // 킥 비터 클릭 — 앞 20ms 안의 2~6kHz 비율(공격 성분).
    for (final k in ['amuld', 'acoustic']) {
      final x = _hit('kick', k, 3, 1.0);
      o.writeln('킥 v3 비터 대역(2-6k) 앞 20ms 비율 $k: '
          '${(_bandRatio(x, 2000, 6000, len: 1024, hann: false) * 100).toStringAsFixed(1)}%');
    }
    // ignore: avoid_print
    print(o);
  });
}
