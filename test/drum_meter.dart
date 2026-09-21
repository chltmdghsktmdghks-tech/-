// 킥·스네어가 **실제로 어떤 소리인지** 재는 도구 (수동 실행).
//   flutter test test/drum_meter.dart
//
// 「구리다」는 말은 고칠 데를 안 알려준다. 숫자로 바꿔 놓고 본다:
//  · 얼마나 오래 울리는가(감쇠) — 짧으면 '톡', 길면 '둥'
//  · 힘이 어느 대역에 있는가 — **폰 스피커는 150Hz 아래를 못 낸다.**
//    거기에만 힘이 있으면 폰에서는 아무 소리도 안 난다.
//  · 어택이 얼마나 빠른가 — 느리면 뭉개진다
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/drums.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/synth.dart' show Human;

/// 한 타격을 통째로 렌더한다(모노).
List<double> _hit(String inst, String kit, int vel) {
  Human.setLevel(0);
  final d = DrumVoice()..trigger(inst, DRUM_KITS[kit]!, vel);
  final out = <double>[];
  for (var i = 0; i < kSampleRate; i++) {
    if (!d.active) break;
    d.next();
    out.add((d.outL + d.outR) * 0.5);
  }
  return out;
}

/// -20dB 까지 걸리는 시간(ms) — 귀로 느끼는 '길이'에 제일 가깝다.
double _decayMs(List<double> x) {
  var peak = 0.0;
  for (final v in x) {
    if (v.abs() > peak) peak = v.abs();
  }
  if (peak <= 0) return 0;
  final thr = peak * 0.1;
  // 뒤에서부터 훑어 마지막으로 문턱을 넘은 자리
  for (var i = x.length - 1; i >= 0; i--) {
    if (x[i].abs() > thr) return i / kSampleRate * 1000;
  }
  return 0;
}

/// 어택 = **포락선**이 최고치의 90% 에 처음 닿는 시각.
///
/// 처음엔 「제일 큰 샘플의 자리」로 쟀는데, 잡음이 많은 소리(스네어)에서는
/// 그게 사실상 제비뽑기다 — 엔벨로프가 10ms 동안 평평하면 그 안 어디서든
/// 최대가 나온다. 값을 조금 바꿨을 뿐인데 6.4ms 가 12.0ms 로 튀어서 알았다.
/// 1ms 창으로 매끈하게 만든 뒤 재면 흔들리지 않는다.
double _attackMs(List<double> x) {
  const w = 48; // 1ms
  final env = <double>[];
  var acc = 0.0;
  for (var i = 0; i < x.length; i++) {
    acc += x[i] * x[i];
    if (i >= w) acc -= x[i - w] * x[i - w];
    env.add(math.sqrt(acc / w));
  }
  var peak = 0.0;
  for (final v in env) {
    if (v > peak) peak = v;
  }
  if (peak <= 0) return 0;
  for (var i = 0; i < env.length; i++) {
    if (env[i] >= peak * 0.9) return i / kSampleRate * 1000;
  }
  return 0;
}

/// 대역별 힘(제곱합 비율). 경계는 **폰 스피커 기준**으로 잡았다.
///  0: ~60 (초저역, 폰에서 안 들림)  1: 60~150 (저역, 폰에서 거의 안 들림)
///  2: 150~400 (몸통, 폰에서 들리기 시작)  3: 400~1500 (중역)
///  4: 1.5k~5k (딱·크랙)  5: 5k~ (공기)
List<double> _bands(List<double> x) {
  const edges = [60.0, 150.0, 400.0, 1500.0, 5000.0];
  final out = List<double>.filled(6, 0);
  var cur = List<double>.of(x);
  for (var i = 0; i < edges.length; i++) {
    final lp = Biquad()..lowpass(edges[i], 0);
    final lo = [for (final v in cur) lp.process(v)];
    var e = 0.0;
    for (final v in lo) {
      e += v * v;
    }
    out[i] = e;
    for (var j = 0; j < cur.length; j++) {
      cur[j] -= lo[j];
    }
  }
  var e = 0.0;
  for (final v in cur) {
    e += v * v;
  }
  out[5] = e;
  final tot = out.reduce((a, b) => a + b);
  return tot <= 0 ? out : [for (final v in out) v / tot];
}

void main() {
  test('타악기 계량', () {
    // ignore: avoid_print
    void p(String s) => print(s);
    p(
      '             길이   어택   피크   ｜ ~60  60~150  150~400  400~1.5k  1.5k~5k  5k~',
    );
    // 킥·스네어만 보다가 놓친 자리가 있을까 봐 **열 레인 전부** 본다 (2026-08-30).
    for (final inst in [
      'kick',
      'snare',
      'hat',
      'ride',
      'clap',
      'rim',
      'tom',
      'shaker',
      'cowbell',
      'crash',
    ]) {
      p('── $inst ──');
      for (final kit in DRUM_KITS.keys) {
        final x = _hit(inst, kit, 3);
        var peak = 0.0;
        for (final v in x) {
          if (v.abs() > peak) peak = v.abs();
        }
        final b = _bands(x);
        // 폰에서 들리는 몫 = 150Hz 위 전부
        final phone = b[2] + b[3] + b[4] + b[5];
        p(
          '${kit.padRight(10)} ${_decayMs(x).round().toString().padLeft(4)}ms '
          '${_attackMs(x).toStringAsFixed(1).padLeft(5)}ms '
          '${peak.toStringAsFixed(2).padLeft(5)}  ｜'
          '${b.map((v) => '${(v * 100).round()}%'.padLeft(6)).join()}'
          '   폰 ${(phone * 100).round()}%',
        );
      }
    }
    // 세기별
    p('── 세기 반응 (acoustic) ──');
    for (final inst in ['kick', 'snare']) {
      final v = [
        for (var i = 1; i <= 3; i++)
          () {
            final x = _hit(inst, 'acoustic', i);
            var pk = 0.0;
            for (final s in x) {
              if (s.abs() > pk) pk = s.abs();
            }
            return '$i:${pk.toStringAsFixed(2)}/${_decayMs(x).round()}ms';
          }(),
      ];
      p('$inst  ${v.join('  ')}');
    }
  });
}
