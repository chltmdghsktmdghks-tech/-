// **한 음의 배음 구조를 눈으로 보는 도구** (수동 실행).
//   flutter test test/timbre_meter.dart
//
// 「소리가 난다」와 「그 악기 소리가 난다」는 다르다. 크기(voice_meter)로는
// 그 차이가 안 보인다 — 기본 삼각파도 크기는 멀쩡하게 나온다.
// 여기서는 **배음 하나하나의 세기**와 **포먼트(고정 공명)가 실제로 서 있는지**를 잰다.
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/engine.dart';
import 'package:music_doodle_engine/instruments.dart'
    show VOICE_LABEL, INSTRUMENTS;
import 'package:music_doodle_engine/synth.dart' show Human;

double _midi(int n) => 440 * math.pow(2, (n - 69) / 12).toDouble();

List<double> _note(String voice, int midi, {double sec = 1.0}) {
  final e = Engine()..trackMix.configure(['a']);
  e.schedule(0.01, voice, _midi(midi), 0.6, 3, part: kPartBass);
  final total = (sec * kSampleRate).round();
  final out = List<double>.filled(total, 0);
  var done = 0;
  while (done < total) {
    final n = math.min(1024, total - done);
    final pcm = e.render(n);
    for (var i = 0; i < n; i++) {
      out[done + i] = (pcm[i * 2] + pcm[i * 2 + 1]) / 2 / 32768.0;
    }
    done += n;
  }
  return out;
}

/// 한 주파수의 세기 — 고에젤. 창은 해닝, 길이는 0.4초로 고정.
double _bin(List<double> x, int from, double freq) {
  final n = math.min((0.4 * kSampleRate).round(), x.length - from);
  final w = 2 * math.pi * freq / kSampleRate;
  final c = 2 * math.cos(w);
  var s1 = 0.0, s2 = 0.0;
  for (var i = 0; i < n; i++) {
    final win = 0.5 - 0.5 * math.cos(2 * math.pi * i / n);
    final s = x[from + i] * win + c * s1 - s2;
    s2 = s1;
    s1 = s;
  }
  return math.sqrt(s1 * s1 + s2 * s2 - c * s1 * s2) / n;
}

void main() {
  test('음색 구조', () {
    Human.setLevel(0);
    // ignore: avoid_print
    void pr(String s) => print(s);

    const midi = 60; // C4
    final f0 = _midi(midi);
    final voices = <String>['vocal', 'sax', 'strings', 'organ', 'pad'];

    pr('C4(${f0.round()}Hz) 한 음 · 0.1초 뒤부터 0.4초 창\n');
    pr('악기        표?   배음 1~10 (제일 큰 것 대비 dB)');
    for (final v in voices) {
      final x = _note(v, midi);
      final from = (0.1 * kSampleRate).round();
      final h = [for (var k = 1; k <= 10; k++) _bin(x, from, f0 * k)];
      final mx = h.reduce(math.max);
      final db = [
        for (final a in h) mx <= 0 ? -99.0 : 20 * math.log(a / mx) / math.ln10,
      ];
      final tag = INSTRUMENTS.containsKey(v) ? ' O ' : ' X ';
      pr(
        '${(VOICE_LABEL[v] ?? v).padRight(10)} $tag  '
        '${db.map((d) => d.round().toString().padLeft(4)).join(' ')}',
      );
    }

    pr('\n── 포먼트 대역 (넓은 잡음처럼 재서 고정 공명이 서 있는지 본다) ──');
    pr('악기        400  700  1200  2000  3000 Hz  (전체 대비 dB)');
    for (final v in voices) {
      final x = _note(v, midi);
      final from = (0.1 * kSampleRate).round();
      // 반음 간격으로 촘촘히 재서 그 대역의 실제 에너지를 본다
      double band(double lo, double hi) {
        var e = 0.0;
        var n = 0;
        for (var f = lo; f < hi; f *= 1.03) {
          final a = _bin(x, from, f);
          e += a * a;
          n++;
        }
        return math.sqrt(e / n);
      }

      final bs = [
        band(340, 470),
        band(600, 820),
        band(1050, 1400),
        band(1750, 2300),
        band(2600, 3400),
      ];
      final mx = bs.reduce(math.max);
      pr(
        '${(VOICE_LABEL[v] ?? v).padRight(10)} '
        '${bs.map((a) => (mx <= 0 ? -99.0 : 20 * math.log(a / mx) / math.ln10).round().toString().padLeft(5)).join('')}',
      );
    }
    pr('\n음색 구조 출력 끝');
  });
}
