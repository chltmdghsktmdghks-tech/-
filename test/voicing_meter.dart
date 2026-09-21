// **코드가 마디마다 얼마나 뛰어다니는가** 를 재는 도구 (수동 실행).
//   flutter test test/voicing_meter.dart
//
// `chordFreqsOf` 는 어떤 코드든 **근음 자리(root position)** 로만 쌓는다.
// 그래서 i–iv–VI–VII 를 치면 밑음이 60→65→68→70 으로 계속 기어오르다가
// 다음 바퀴에 60 으로 뚝 떨어진다. 사람이 건반을 그렇게 치지 않는다 —
// 손은 한자리에 두고 **자리바꿈(inversion)** 으로 잇는다.
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/theory.dart';

double _midi(double f) => 69 + 12 * (math.log(f / 440) / math.ln2);

void main() {
  test('코드 자리', () {
    // ignore: avoid_print
    void pr(String s) => print(s);
    pr('장르        씬            코드수  밑음이동  전체이동  밑음범위');
    var allLow = 0.0, allAll = 0.0, n = 0;
    for (final g in kGenres) {
      final proj = Project.initial()..setGenre(g.key);
      final key = MusicKey(root: 0, mode: g.mode);
      for (final sc in proj.scenes) {
        for (final t in proj.tracks.where((t) => t.type == 'chord')) {
          final clip = sc.clips[t.id];
          if (clip == null) continue;
          final d = proj.findNote('chord', clip);
          if (d == null || d.notes.isEmpty) continue;
          final hits = buildChordPattern(d, key);
          // 같은 코드를 여러 번 치는 것(스탭)은 한 번으로 본다
          final seq = <List<double>>[];
          for (final h in hits) {
            final v = [for (final f in h.freqs) _midi(f)]..sort();
            if (seq.isNotEmpty && _same(seq.last, v)) continue;
            seq.add(v);
          }
          if (seq.length < 2) continue;
          var low = 0.0, all = 0.0;
          var lo = 200.0, hi = -200.0;
          for (var i = 1; i < seq.length; i++) {
            low += (seq[i].first - seq[i - 1].first).abs();
            final m = math.min(seq[i].length, seq[i - 1].length);
            var s = 0.0;
            for (var k = 0; k < m; k++) {
              s += (seq[i][k] - seq[i - 1][k]).abs();
            }
            all += s / m;
          }
          for (final v in seq) {
            lo = math.min(lo, v.first);
            hi = math.max(hi, v.first);
          }
          final steps = seq.length - 1;
          pr(
            '${g.key.padRight(11)} ${sc.name.padRight(12)} '
            '${seq.length.toString().padLeft(4)}  '
            '${(low / steps).toStringAsFixed(1).padLeft(7)}  '
            '${(all / steps).toStringAsFixed(1).padLeft(7)}  '
            '${lo.round()}~${hi.round()}',
          );
          allLow += low / steps;
          allAll += all / steps;
          n++;
        }
      }
    }
    pr('');
    pr(
      '평균  밑음이동 ${(allLow / n).toStringAsFixed(1)}반음 · '
      '전체이동 ${(allAll / n).toStringAsFixed(1)}반음  ($n개 줄)',
    );
  });
}

bool _same(List<double> a, List<double> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if ((a[i] - b[i]).abs() > 0.01) return false;
  }
  return true;
}
