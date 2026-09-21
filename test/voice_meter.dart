// **악기 33종이 같은 세기에서 얼마나 크게 나는가** 를 재는 도구 (수동 실행).
//   flutter test test/voice_meter.dart
//
// 계획이 제일 앞에 둔 기준: 「단독으로 좋은 소리보다 **Mix 안에서** 좋은 소리」.
// 같은 음·같은 세기로 쳤을 때 악기끼리 크기가 벌어지면, 곡에 같이 넣는 순간
// 작은 쪽이 사라진다. `instrument_quality_test` 는 대표 7종만 본다 — 여기서 전수한다.
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/engine.dart';
import 'package:music_doodle_engine/instruments.dart'
    show ALL_VOICES, VOICE_LABEL;
import 'package:music_doodle_engine/synth.dart' show Human;

double _midi(int n) => 440 * math.pow(2, (n - 69) / 12).toDouble();

List<double> _note(String voice, int midi, int vel, {double sec = 1.2}) {
  final e = Engine()..trackMix.configure(['a']);
  e.schedule(0.01, voice, _midi(midi), 0.5, vel, part: kPartBass);
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

double _db(List<double> x, int to) {
  var e = 0.0;
  for (var i = 0; i < to && i < x.length; i++) {
    e += x[i] * x[i];
  }
  final r = math.sqrt(e / math.max(1, to));
  return r <= 1e-9 ? -120 : 20 * math.log(r) / math.ln10;
}

/// 저역 악기는 낮은 음으로 잰다 — 높은 음을 시키면 원래 안 나는 소리다.
const _low = {'bass', 'fingerbass', 'moogbass', 'wobble', 'sine', 'upright'};

void main() {
  test('악기 크기', () {
    Human.setLevel(0);
    final rows = <(String, double)>[];
    for (final v in ALL_VOICES) {
      final m = _low.contains(v) ? 40 : 60;
      rows.add((v, _db(_note(v, m, 3), (0.3 * kSampleRate).round())));
    }
    rows.sort((a, b) => a.$2.compareTo(b.$2));
    final mid = rows[rows.length ~/ 2].$2;
    // ignore: avoid_print
    void pr(String s) => print(s);
    pr('악기            크기      가운데 대비');
    for (final r in rows) {
      final rel = r.$2 - mid;
      final mark = rel < -8 ? '  ← 작다' : (rel > 8 ? '  ← 크다' : '');
      pr(
        '${(VOICE_LABEL[r.$1] ?? r.$1).padRight(14)} '
        '${r.$2.toStringAsFixed(1).padLeft(6)}dB  '
        '${rel.toStringAsFixed(1).padLeft(6)}$mark',
      );
    }
    pr('');
    // **저역 악기와 나머지를 섞어서 「폭」을 내면 안 된다.**
    //  저역은 40번 음(낮은 미)으로 재고 나머지는 60번(가온다)으로 잰다 —
    //  같은 세기라도 낮은 음이 에너지가 크다. 섞으면 폭이 18.7dB 로 나오는데
    //  그건 「악기끼리 크기가 벌어졌다」가 아니라 **베이스가 베이스라서** 그렇다.
    //  (한 번 이 숫자를 보고 없는 병을 쫓을 뻔했다.)
    final melo = [
      for (final r in rows)
        if (!_low.contains(r.$1)) r.$2,
    ];
    final bass = [
      for (final r in rows)
        if (_low.contains(r.$1)) r.$2,
    ];
    String span(List<double> v) => v.isEmpty
        ? '없음'
        : '${(v.last - v.first).toStringAsFixed(1)}dB '
              '(${v.first.toStringAsFixed(1)} ~ ${v.last.toStringAsFixed(1)})';
    pr('멜로디·화성 ${melo.length}종 폭 ${span(melo)}');
    pr('저역 ${bass.length}종 폭 ${span(bass)}  ← 낮은 음으로 쟀다. 위와 섞지 말 것');
    pr('가운데 ${mid.toStringAsFixed(1)}dB');
  });
}
