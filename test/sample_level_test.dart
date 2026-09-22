// 표본 악기가 **서로 비슷한 크기이고, 천장을 안 넘는가.**
//   flutter test test/sample_level_test.dart
//
// `kSampleTrim`(sampler.dart)을 건드리면 여기가 잡는다.
//
// 이 시험이 있는 이유: 2026-09-22 에 레벨을 맞추면서 처음엔 **RMS** 로 맞췄는데,
// 뜯는 악기는 어택만 뾰족하고 뒤가 조용해서 RMS 가 낮다. 그걸 색소폰 같은
// 지속음에 RMS 로 맞추니 핑거베이스 피크가 **+11.0dB** 로 천장을 뚫었다.
// 귀로는 "어딘가 지직거린다"로만 들리고 무엇이 문제인지는 안 보인다. 그래서 잰다.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/sampler.dart';
import 'package:music_doodle_engine/synth.dart';

/// 그 악기를 **제 음역대에서** 친다 — 베이스를 C4 로 재면 원래 안 나는 소리를
/// 억지로 늘려 재는 셈이라 값이 엉뚱해진다.
const Map<String, double> _testFreq = {
  'upright': 65.41,
  'fingerbass': 65.41,
  'cello': 130.81,
  'piano': 261.63,
  'epiano': 261.63,
  'guitar': 196.00,
  'sax': 261.63,
  'trumpet': 261.63,
  'violin': 440.00,
};

double _db(double v) => v <= 1e-9 ? -120 : 20 * math.log(v) / math.ln10;

double _peak(String voice, double freq, int vel) {
  final n = SynthNote();
  n.noteOn(voice, freq, 2.0, vel);
  var pk = 0.0;
  for (var i = 0; i < (3.0 * kSampleRate).round(); i++) {
    if (!n.active) break;
    n.next();
    final a = n.outL.abs();
    if (a > pk) pk = a;
    final b = n.outR.abs();
    if (b > pk) pk = b;
  }
  return pk;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await ensureSamplesLoaded();
  });

  tearDownAll(() {
    kSampleBanks.clear();
  });

  test('한 음도 천장을 안 넘는다', () {
    expect(kSampleBanks, isNotEmpty);
    final over = <String>[];
    for (final v in (kSampleBanks.keys.toList()..sort())) {
      final pk = _peak(v, _testFreq[v] ?? 261.63, 3);
      // ignore: avoid_print
      print('  ${v.padRight(12)}${_db(pk).toStringAsFixed(1).padLeft(7)}dB');
      if (pk > 1.0) over.add('$v ${_db(pk).toStringAsFixed(1)}dB');
    }
    expect(over, isEmpty, reason: '천장을 넘는 악기: ${over.join(", ")}');
  });

  test('악기끼리 피크가 맞는다 — 한 밴드로 들려야 한다', () {
    final pk = <String, double>{};
    for (final v in kSampleBanks.keys) {
      pk[v] = _peak(v, _testFreq[v] ?? 261.63, 3);
    }
    final lo = _db(pk.values.reduce(math.min));
    final hi = _db(pk.values.reduce(math.max));
    // ignore: avoid_print
    print('피크 범위 ${lo.toStringAsFixed(1)} ~ ${hi.toStringAsFixed(1)}dB '
        '(폭 ${(hi - lo).toStringAsFixed(1)}dB)');
    // 맞추기 전에는 **33.3dB** 벌어져 있었다(업라이트 −41.0 vs 색소폰 −7.7).
    expect(hi - lo, lessThan(3.0),
        reason: '피크 기준으로 맞췄으므로 3dB 안에 들어와야 한다');
  });

  test('세기를 올리면 커진다 — 표본 악기 전부', () {
    // 완만한 표(`kSampleVG`)를 쓰는 악기도 **방향은** 같아야 한다.
    for (final v in (kSampleBanks.keys.toList()..sort())) {
      final f = _testFreq[v] ?? 261.63;
      final p1 = _peak(v, f, 1), p3 = _peak(v, f, 3);
      expect(p3, greaterThan(p1),
          reason: '$v — 세게(${_db(p3).toStringAsFixed(1)}dB)가 '
              '여리게(${_db(p1).toStringAsFixed(1)}dB)보다 커야 한다');
    }
  });
}
