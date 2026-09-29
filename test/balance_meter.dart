// 악기 밸런스 측정 도구 (수동 실행) — 피크와 「제일 시끄러운 100ms RMS」를 dB 로.
//   flutter test test/balance_meter.dart
//
// 피크만 맞추면 뜯는 악기(어택만 뾰족)가 지속음보다 작게 들린다. RMS 를 같이 본다.
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/drum_sampler.dart';
import 'package:music_doodle_engine/drums.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/instruments.dart';
import 'package:music_doodle_engine/sampler.dart';
import 'package:music_doodle_engine/synth.dart';

double _db(double v) => v <= 1e-9 ? -120 : 20 * math.log(v) / math.ln10;

class _M {
  final double pk, rms;
  _M(this.pk, this.rms);
  String get s => '${_db(pk).toStringAsFixed(1).padLeft(7)} pk ${_db(rms).toStringAsFixed(1).padLeft(7)} rms';
}

_M _measure(bool Function() next, double Function() l, double Function() r, int max) {
  final w = (0.1 * kSampleRate).round();
  final buf = List<double>.filled(w, 0);
  var acc = 0.0, pk = 0.0, best = 0.0, i = 0;
  for (var n = 0; n < max; n++) {
    if (!next()) break;
    final m = (l() + r()) * 0.5;
    pk = math.max(pk, math.max(l().abs(), r().abs()));
    final k = i % w;
    acc += m * m - buf[k] * buf[k];
    buf[k] = m;
    i++;
    if (i >= w) best = math.max(best, math.sqrt(math.max(0, acc) / w));
  }
  if (best == 0 && i > 0) best = math.sqrt(math.max(0, acc) / i);
  return _M(pk, best);
}

_M _synth(String v, double f, int vel) {
  final n = SynthNote()..noteOn(v, f, 1.0, vel);
  return _measure(() {
    if (!n.active) return false;
    n.next();
    return true;
  }, () => n.outL, () => n.outR, 3 * kSampleRate);
}

_M _drum(String inst, String kit, int vel) {
  Human.setLevel(0);
  final d = DrumVoice()..trigger(inst, DRUM_KITS[kit]!, vel);
  return _measure(() {
    if (!d.active) return false;
    d.next();
    return true;
  }, () => d.outL, () => d.outR, 3 * kSampleRate);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await ensureSamplesLoaded();
    for (final p in ['kick', 'snare', 'hatClosed', 'hatOpen', 'crash', 'ride', 'tom']) {
      await ensureDrumPieceLoaded(p);
      await ensureDrumPieceLoaded(p, set: 'avirt');
    }
  });

  test('bass range sweep (E1..G2, vel3, peak)', () {
    final o = StringBuffer('== 베이스 음역 스윕 (최대 피크)\n');
    for (final v in ['fingerbass', 'jbass']) {
      var worst = 0.0;
      for (var m = 28; m <= 43; m++) {
        final f = 440 * math.pow(2, (m - 69) / 12);
        worst = math.max(worst, _synth(v, f.toDouble(), 3).pk);
      }
      o.writeln('${v.padRight(12)} worst ${_db(worst).toStringAsFixed(1)} dB');
    }
    // ignore: avoid_print
    print(o);
  });

  test('measure', () {
    final out = StringBuffer();
    out.writeln('== 베이스 (65.41Hz, vel 3 / vel 2)');
    for (final v in ['bass', 'moogbass', 'fingerbass', 'jbass', 'upright']) {
      out.writeln('${v.padRight(12)} v3 ${_synth(v, 65.41, 3).s}   v2 ${_synth(v, 65.41, 2).s}');
    }
    out.writeln('== 그 밖 (C4 261.63 / vel 3)');
    for (final v in INSTRUMENTS.keys) {
      if (const {'bass', 'moogbass', 'fingerbass', 'jbass', 'upright'}.contains(v)) continue;
      out.writeln('${v.padRight(12)} ${_synth(v, 261.63, 3).s}');
    }
    out.writeln('== 드럼 (킷별, vel 3/2)');
    for (final k in DRUM_KIT_ORDER) {
      for (final i in ['kick', 'snare', 'hat', 'tom', 'crash', 'ride', 'clap', 'rim']) {
        out.writeln('${k.padRight(9)}${i.padRight(7)} v3 ${_drum(i, k, 3).s}   v2 ${_drum(i, k, 2).s}');
      }
    }
    // ignore: avoid_print
    print(out);
  });
}
