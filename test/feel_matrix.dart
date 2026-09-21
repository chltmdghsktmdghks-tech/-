// **느낌 손잡이 다섯 개가 장르마다 실제로 뭔가를 하는가** (수동 실행).
//   flutter test test/feel_matrix.dart
//
// `feel_check_test` 는 손잡이 하나하나가 옳게 도는지를 **한 패턴**으로 본다.
// 그건 「규칙이 맞는가」다. 여기서는 「**15개 장르 전부에서 손이 닿는가**」를 본다 —
// 어떤 장르는 하이햇이 없어서 「빽빽」이 아무것도 못 하고, 어떤 장르는 뒷박이
// 없어서 스윙이 안 걸린다. 그러면 그 장르에서 그 손잡이는 **가짜**다.
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/feel.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/synth.dart';

/// 만든 판을 한 줄 지문으로 — 자리·세기·길이가 다 들어간다.
List<String> _sig(SceneBuild b) => [
  for (final n in b.notes)
    'n${(n[6] as double).toStringAsFixed(4)}|${n[3]}|'
        '${(n[2] as double).toStringAsFixed(3)}',
  for (final d in b.drums)
    'd${(d[4] as double).toStringAsFixed(4)}|${d[1]}|${d[2]}',
];

/// 두 지문이 얼마나 다른가(%).
double _diff(List<String> a, List<String> b) {
  final sa = a.toSet(), sb = b.toSet();
  final same = sa.intersection(sb).length;
  final tot = math.max(sa.length, sb.length);
  return tot == 0 ? 0 : (1 - same / tot) * 100;
}

void main() {
  test('느낌 손잡이 판', () {
    Human.setLevel(0);
    // ignore: avoid_print
    void pr(String s) => print(s);
    pr('장르        신남   빽빽   스윙   필    변화');
    final dead = <String>[];
    for (final g in kGenres) {
      final p = Project.initial()..setGenre(g.key);
      final tr = Transport()
        ..bpm = g.bpm
        ..mode = g.mode
        ..reps = 4;
      List<String> run(Feel f) {
        p.feel = f;
        return _sig(SceneSequencer.build(p, tr, reps: 4));
      }

      final base = run(const Feel());
      final rows = <double>[];
      for (final f in [
        const Feel(energy: 1.0),
        const Feel(density: 1.0),
        const Feel(groove: 1.0),
        const Feel(fill: 0),
        const Feel(vary: 0),
      ]) {
        rows.add(_diff(base, run(f)));
      }
      p.feel = const Feel();
      const names = ['신남', '빽빽', '스윙', '필', '변화'];
      for (var i = 0; i < rows.length; i++) {
        // **「필」은 원래 작게 나온다** — 네 바퀴 중 한 마디만 건드리니까.
        // 음이 많은 장르(팝 1%)일수록 비율이 더 작다. 그래서 문턱을 나눈다.
        final floor = names[i] == '필' ? 0.5 : 1.0;
        if (rows[i] < floor) dead.add('${g.key}/${names[i]}');
      }
      pr(
        '${g.key.padRight(11)}'
        '${rows.map((r) => '${r.toStringAsFixed(0)}%'.padLeft(6)).join(' ')}',
      );
    }
    pr('');
    pr(
      dead.isEmpty
          ? '손이 안 닿는 자리 없음'
          : '**손이 안 닿는 자리** ${dead.length}곳 — ${dead.join(' · ')}',
    );
  });
}
