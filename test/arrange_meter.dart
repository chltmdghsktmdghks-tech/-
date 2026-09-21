// 구간 성격이 **실제로 무엇을 바꾸는지** 재는 도구 (수동 실행).
//   flutter test test/arrange_meter.dart
import 'package:music_doodle_engine/arrange.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genre_mix.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';

void main() {
  test('구간 성격 계량', () {
    // ignore: avoid_print
    void p(String s) => print(s);
    for (final g in kGenreDuck.keys) {
      final tr = Transport();
      final proj = Project.initial()..setGenre(g);
      final b = SceneSequencer.buildSong(proj, tr);
      final spans = SceneSequencer.songSpans(proj, tr);
      final rows = <String>[];
      for (var i = 0; i < spans.length; i++) {
        final (st, du) = spans[i];
        final name = proj.scenes[proj.song.sections[i].scene].name;
        var vs = 0, vn = 0, hits = 0;
        for (final d in b.drums) {
          final t = (d[4] as num).toDouble();
          if (t < st || t >= st + du) continue;
          vs += d[2] as int;
          vn++;
          hits++;
        }
        for (final n in b.notes) {
          final t = (n[6] as num).toDouble();
          if (t < st || t >= st + du) continue;
          vs += n[3] as int;
          vn++;
        }
        final avg = vn == 0 ? 0.0 : vs / vn;
        // 빌드업은 **평균**으로는 안 보인다(앞은 내리고 뒤는 올리니 상쇄된다).
        // 앞뒤 반씩 갈라 봐야 「차오르는지」가 보인다.
        var f = 0, fn = 0, l = 0, ln = 0;
        for (final d in b.drums) {
          final t = (d[4] as num).toDouble();
          if (t < st || t >= st + du) continue;
          if (t - st < du / 2) {
            f += d[2] as int;
            fn++;
          } else {
            l += d[2] as int;
            ln++;
          }
        }
        final ramp = (fn == 0 || ln == 0)
            ? ''
            : ' ${(f / fn).toStringAsFixed(1)}→${(l / ln).toStringAsFixed(1)}';
        // 초당 타격 수 — 밀도
        final dens = du <= 0 ? 0.0 : hits / du;
        rows.add(
          '$name[${roleOf(name).name.substring(0, 2)}] '
          '세기${avg.toStringAsFixed(2)}$ramp 밀도${dens.toStringAsFixed(1)}',
        );
      }
      p('${g.padRight(11)} ${rows.join(' | ')}');
    }
  });
}
