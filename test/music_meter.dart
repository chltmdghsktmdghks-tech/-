// 지금 나오는 **곡 자체**가 어떤지 재는 도구 (수동 실행).
//   flutter test test/music_meter.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/song.dart';

const _rn = ['i', 'ii', 'III', 'iv', 'v', 'VI', 'VII'];

void main() {
  test('곡 계량', () {
    // ignore: avoid_print
    void p(String s) => print(s);

    p('══ 코드 진행 ══');
    for (final g in kGenres) {
      final proj = Project.initial()..setGenre(g.key);
      final rows = <String>[];
      for (var i = 0; i < proj.scenes.length; i++) {
        final sc = proj.scenes[i];
        for (final t in proj.tracks.where((t) => t.type == 'chord')) {
          final clip = sc.clips[t.id];
          if (clip == null) continue;
          final def = proj.findNote('chord', clip);
          if (def == null || def.notes.isEmpty) continue;
          // 마디마다 첫 코드만
          final byBar = <int, int>{};
          for (final n in def.notes) {
            final bar = (n[1] as int) ~/ 16;
            byBar.putIfAbsent(bar, () => (n[0] as int) % 7);
          }
          final seq = [
            for (var b = 0; b < def.bars; b++)
              if (byBar[b] != null) _rn[byBar[b]!],
          ];
          rows.add('${sc.name}: ${seq.join('–')}');
          break;
        }
      }
      p('${g.key.padRight(11)} ${rows.join('  |  ')}');
    }

    p('');
    p('══ 멜로디 생김새 ══');
    p('이름              음수 음역 도약 되풀이 쉼 길이종류 코드톤');
    for (final m in kMelodyPatterns) {
      if (m.notes.length < 3) continue;
      final degs = [for (final n in m.notes) n[0] as int];
      final steps = [for (final n in m.notes) n[1] as int];
      final lens = {for (final n in m.notes) n[2] as int};
      final lo = degs.reduce((a, b) => a < b ? a : b);
      final hi = degs.reduce((a, b) => a > b ? a : b);
      // 도약 = 3도 넘게 뛰는 비율
      var leap = 0;
      for (var i = 1; i < degs.length; i++) {
        if ((degs[i] - degs[i - 1]).abs() > 2) leap++;
      }
      // 되풀이 = 같은 (도수 차, 칸 차) 모티프가 다시 나오는가
      final motifs = <String, int>{};
      for (var i = 1; i < degs.length; i++) {
        final k = '${degs[i] - degs[i - 1]}:${steps[i] - steps[i - 1]}';
        motifs[k] = (motifs[k] ?? 0) + 1;
      }
      final repeat = motifs.values.where((v) => v > 1).fold(0, (a, b) => a + b);
      // 쉼 = 판에서 음이 안 울리는 칸의 비율
      final total = m.bars * 16;
      var filled = 0;
      for (final n in m.notes) {
        filled += n[2] as int;
      }
      final rest = ((1 - filled / total) * 100).clamp(0, 100).round();
      p(
        '${m.name.padRight(17)} ${m.notes.length.toString().padLeft(3)} '
        '${'$lo~$hi'.padLeft(5)} '
        '${(leap * 100 / (degs.length - 1)).round().toString().padLeft(3)}% '
        '${(repeat * 100 / (degs.length - 1)).round().toString().padLeft(5)}% '
        '${rest.toString().padLeft(3)}% '
        '${lens.length.toString().padLeft(4)}종',
      );
    }
  });
}
