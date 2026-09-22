// 표본 악기가 **서로 얼마나 크기가 다른가** — 자로 잰다.
//   flutter test test/sample_level_meter.dart
//
// 시험이 아니라 **자**다(`voice_meter.dart` 와 같은 성격). 숫자를 뽑아서
// `kSampleTrim` 을 정하는 데 쓴다.
//
// 기존 `test/voice_meter.dart` 로는 이걸 못 잰다 — `TestWidgetsFlutterBinding`
// 을 안 띄우고 `ensureSamplesLoaded()` 도 안 불러서, 표본 악기가 **합성 대체음**
// 으로 측정된다. 그래서 따로 둔다.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/sampler.dart';
import 'package:music_doodle_engine/synth.dart';

double _rms(List<double> x) {
  if (x.isEmpty) return 0;
  var s = 0.0;
  for (final v in x) {
    s += v * v;
  }
  return math.sqrt(s / x.length);
}

double _db(double v) => v <= 1e-9 ? -120 : 20 * math.log(v) / math.ln10;

/// 그 악기를 **제 음역대에서** 친다 — 베이스를 C4 로 재면 원래 안 나는 소리를
/// 억지로 늘려 재는 셈이라 값이 엉뚱해진다.
const Map<String, double> _testFreq = {
  'upright': 65.41, // C2
  'fingerbass': 65.41,
  'cello': 130.81, // C3
  'piano': 261.63, // C4
  'epiano': 261.63,
  'guitar': 196.00, // G3
  'sax': 261.63,
  'trumpet': 261.63,
  'violin': 440.00, // A4
};

/// 한 음을 끝까지 렌더해서 **가장 센 0.3초 구간**의 RMS 를 돌려준다.
/// 통짜 RMS 로 재면 꼬리가 긴 악기(피아노)가 부당하게 작게 나온다.
double _peakRms(String voice, double freq, int vel) {
  final n = SynthNote();
  n.noteOn(voice, freq, 2.0, vel);
  final total = (3.0 * kSampleRate).round();
  final buf = <double>[];
  for (var i = 0; i < total; i++) {
    if (!n.active) break;
    n.next();
    buf.add(n.outL);
  }
  if (buf.isEmpty) return 0;
  final win = (0.3 * kSampleRate).round();
  if (buf.length <= win) return _rms(buf);
  var best = 0.0;
  for (var s = 0; s + win <= buf.length; s += (0.05 * kSampleRate).round()) {
    final r = _rms(buf.sublist(s, s + win));
    if (r > best) best = r;
  }
  return best;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await ensureSamplesLoaded();
  });

  tearDownAll(() {
    kSampleBanks.clear();
  });

  test('표본 악기 레벨 자', () {
    expect(kSampleBanks, isNotEmpty);
    final names = kSampleBanks.keys.toList()..sort();
    final ff = <String, double>{};

    // ignore: avoid_print
    print('\n악기        음     vel1      vel2      vel3      ff-pp');
    for (final v in names) {
      final f = _testFreq[v] ?? 261.63;
      final r1 = _peakRms(v, f, 1);
      final r2 = _peakRms(v, f, 2);
      final r3 = _peakRms(v, f, 3);
      ff[v] = r3;
      // ignore: avoid_print
      print(
        '${v.padRight(11)}${f.toStringAsFixed(0).padLeft(4)}  '
        '${_db(r1).toStringAsFixed(1).padLeft(7)}dB'
        '${_db(r2).toStringAsFixed(1).padLeft(8)}dB'
        '${_db(r3).toStringAsFixed(1).padLeft(8)}dB'
        '${(_db(r3) - _db(r1)).toStringAsFixed(1).padLeft(8)}dB',
      );
    }

    // ── 트림 제안 ──
    // 제일 큰 악기를 기준으로, 나머지를 거기 맞추는 배수.
    final loud = ff.values.reduce(math.max);
    final target = loud * 0.75; // 제일 큰 것보다 살짝 아래를 기준선으로
    // ignore: avoid_print
    print('\n제안 kSampleTrim (기준선 ${_db(target).toStringAsFixed(1)}dB):');
    final sorted = ff.keys.toList()
      ..sort((a, b) => ff[a]!.compareTo(ff[b]!));
    for (final v in sorted) {
      final t = (target / ff[v]!).clamp(0.25, 8.0);
      // ignore: avoid_print
      print("  '$v': ${t.toStringAsFixed(2)},"
          '   // ${_db(ff[v]!).toStringAsFixed(1)}dB');
    }
    final spread = _db(loud) - _db(ff[sorted.first]!);
    // ignore: avoid_print
    print('\n제일 큰 악기와 제일 작은 악기 차이: ${spread.toStringAsFixed(1)}dB');
    expect(ff.length, names.length);
  });
}
