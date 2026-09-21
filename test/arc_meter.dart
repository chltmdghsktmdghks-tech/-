// **곡이 어디론가 가는가** 를 재는 도구 (수동 실행).
//   flutter test test/arc_meter.dart
//
// 구간마다 몇 줄이 울리고 얼마나 촘촘한지를 본다. 인트로부터 아웃트로까지
// 숫자가 **평평하면** 곡이 아니라 루프다. 사람은 그걸 「지루하다」로 느낀다.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';

void main() {
  test('곡 흐름', () {
    // ignore: avoid_print
    void pr(String s) => print(s);
    for (final g in kGenres) {
      final proj = Project.initial()..setGenre(g.key);
      final tr = Transport()
        ..bpm = g.bpm
        ..mode = g.mode;
      final rows = <String>[];
      var lo = 1e9, hi = -1e9;
      for (var i = 0; i < proj.scenes.length; i++) {
        final sc = proj.scenes[i];
        final b = SceneSequencer.build(proj, tr, reps: 1, from: sc);
        var bars = 0;
        for (final t in proj.tracks) {
          final clip = sc.clips[t.id];
          if (clip == null) continue;
          final n = proj.barsOf(t.type, clip);
          if (n > bars) bars = n;
        }
        if (bars <= 0) bars = 4;
        final live = proj.tracks.where((t) => sc.clips[t.id] != null).length;
        final per = (b.notes.length + b.drums.length) / bars;
        if (per < lo) lo = per;
        if (per > hi) hi = per;
        rows.add('${sc.name}:$live줄/${per.round()}');
      }
      pr(
        '${g.key.padRight(11)} ${rows.join('  ')}   '
        '  최소${lo.round()}→최대${hi.round()} (${(hi / (lo < 1 ? 1 : lo)).toStringAsFixed(1)}배)',
      );
    }
  });
}
