// 메트로놈 첫박 강세 — 다운비트가 약박보다 얼마나 더 들리는지 잰다(피크·100ms RMS, dB).
//   flutter test test/metro_accent_test.dart
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/live_ops.dart';
import 'package:music_doodle_engine/sampler.dart';
import 'package:music_doodle_engine/synth.dart';

double _db(double v) => v <= 1e-9 ? -120 : 20 * math.log(v) / math.ln10;

/// [metroBatch] 의 한 박(같은 delay 의 줄 전부)을 겹쳐 렌더해 (피크, 100ms RMS) 를 dB 로.
(double, double) _click(List<List<dynamic>> rows) {
  final notes = <SynthNote>[];
  for (final r in rows) {
    notes.add(SynthNote()..noteOn(r[0] as String, r[1] as double, r[2] as double, r[3] as int));
  }
  final w = (0.1 * kSampleRate).round();
  final buf = List<double>.filled(w, 0);
  var acc = 0.0, pk = 0.0, best = 0.0;
  for (var i = 0; i < 2 * kSampleRate ~/ 4; i++) {
    var m = 0.0;
    for (final n in notes) {
      if (n.active) {
        n.next();
        m += (n.outL + n.outR) * 0.5;
      }
    }
    m *= kMetroGain;
    pk = math.max(pk, m.abs());
    final k = i % w;
    acc += m * m - buf[k] * buf[k];
    buf[k] = m;
    if (i >= w) best = math.max(best, math.sqrt(math.max(0, acc) / w));
  }
  return (pk, best);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await ensureSamplesLoaded();
  });

  test('다운비트가 약박보다 확실히 세다', () {
    final b = metroBatch([MetTick(0, 0.0), MetTick(1, 0.5)]);
    final down = b.where((r) => r[6] == 0.0).toList();
    final weak = b.where((r) => r[6] == 0.5).toList();
    final d = _click(down), w = _click(weak);
    // ignore: avoid_print
    print('다운비트 pk ${_db(d.$1).toStringAsFixed(1)} rms ${_db(d.$2).toStringAsFixed(1)} | '
        '약박 pk ${_db(w.$1).toStringAsFixed(1)} rms ${_db(w.$2).toStringAsFixed(1)} | '
        '차이 pk ${(_db(d.$1) - _db(w.$1)).toStringAsFixed(1)} rms ${(_db(d.$2) - _db(w.$2)).toStringAsFixed(1)} dB');
    expect(_db(d.$1) - _db(w.$1), greaterThan(6.5), reason: '피크 +6.5dB 이상 (예전 5.8)');
    expect(_db(d.$2) - _db(w.$2), greaterThan(5.5), reason: 'RMS +5.5dB 이상 (예전 5.5 에 음색·길이 차가 더해짐)');
    expect(down.length, 2, reason: '다운비트는 마림바 + 벨 두 겹');
    expect(down[1][0], 'bell');
    expect(_db(d.$1), lessThan(3.0), reason: '다운비트 피크가 리미터를 세게 치지 않는다');
    expect(_db(w.$1), greaterThan(-14), reason: '약박도 반주에 안 묻힌다(예전 값 유지)');
  });
}
