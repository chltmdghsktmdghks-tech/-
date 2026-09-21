// **느낌 손잡이 다섯 개가 장르마다 실제로 손이 닿는가.** (UX)
//   flutter test test/feel_reach_test.dart
//
// `feel_check_test` 는 손잡이 하나하나가 **옳게 도는지**를 한 패턴으로 본다.
// 여기서는 「**15개 장르 전부에서 뭔가 일어나는가**」를 본다 — 그건 다른 질문이다.
//
// 실제로 죽어 있었다: 「빽빽」은 하이햇만 쪼갰는데 **재즈는 하이햇이 없다**
// (라이드·셰이커로 시간을 센다). 엠비언트도 셰이커뿐이다. 두 장르에서 그 손잡이는
// 끌어도 **아무 일이 안 일어났다** — 오류도 없고, 화면도 멀쩡하고, 소리만 그대로다.
// 새 장르를 넣을 때 제일 놓치기 쉬운 자리라 못을 박아 둔다.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/feel.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/synth.dart';

/// 만든 판을 지문으로 — 자리·세기·길이가 다 들어간다.
List<String> _sig(SceneBuild b) => [
  for (final n in b.notes)
    'n${(n[6] as double).toStringAsFixed(4)}|${n[3]}|'
        '${(n[2] as double).toStringAsFixed(3)}',
  for (final d in b.drums)
    'd${(d[4] as double).toStringAsFixed(4)}|${d[1]}|${d[2]}',
];

double _diff(List<String> a, List<String> b) {
  final sa = a.toSet(), sb = b.toSet();
  final tot = math.max(sa.length, sb.length);
  return tot == 0 ? 0 : (1 - sa.intersection(sb).length / tot) * 100;
}

void main() {
  test('느낌 손잡이가 다 닿는다', () {
    Human.setLevel(0);
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    const names = ['신남', '빽빽', '스윙', '필', '변화'];
    // 「필」은 원래 작게 나온다 — 네 바퀴 중 한 마디만 건드린다.
    const floors = [1.0, 1.0, 1.0, 0.5, 1.0];
    final dead = <String>[];
    final worst = List<double>.filled(5, 999);
    final worstAt = List<String>.filled(5, '');

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
      const knobs = [
        Feel(energy: 1.0),
        Feel(density: 1.0),
        Feel(groove: 1.0),
        Feel(fill: 0),
        Feel(vary: 0),
      ];
      for (var i = 0; i < knobs.length; i++) {
        final d = _diff(base, run(knobs[i]));
        if (d < worst[i]) {
          worst[i] = d;
          worstAt[i] = g.key;
        }
        if (d < floors[i]) {
          dead.add('${g.key}/${names[i]} ${d.toStringAsFixed(1)}%');
        }
      }
      p.feel = const Feel();
    }

    check(
      '1) 손잡이 다섯 × 장르 열다섯 — 안 죽은 자리가 없다',
      dead.isEmpty,
      dead.isEmpty
          ? [
              for (var i = 0; i < 5; i++)
                '${names[i]} 최소 ${worst[i].toStringAsFixed(0)}%(${worstAt[i]})',
            ].join(' · ')
          : dead.join(' · '),
    );

    // ignore: avoid_print
    print(fail == 0 ? '느낌 손잡이 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
