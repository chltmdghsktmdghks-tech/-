// 합성 하이햇이 스네어보다 시끄럽지 않은가 (2026-09-29 청음 "하이햇이 너무 크다").
// 맞추기 전: 808 +4.3dB · 909 +2.4dB (스네어 −3.6 · +0.5).
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/drums.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/synth.dart' show Human;

double _pk(String inst, String kit, int vel) {
  Human.setLevel(0);
  final d = DrumVoice()..trigger(inst, DRUM_KITS[kit]!, vel);
  var pk = 0.0;
  for (var i = 0; i < kSampleRate * 2 && d.active; i++) {
    d.next();
    pk = math.max(pk, math.max(d.outL.abs(), d.outR.abs()));
  }
  return pk;
}

void main() {
  test('전자음 킷 하이햇은 스네어보다 작고 천장 아래', () {
    for (final k in ['k808', 'k909']) {
      for (final v in [1, 2, 3]) {
        final h = _pk('hat', k, v), s = _pk('snare', k, 3);
        expect(h, lessThan(0.5), reason: '$k hat v$v');
        expect(h, lessThan(s * 0.7), reason: '$k hat v$v 가 스네어보다 작아야');
      }
    }
  });
}
