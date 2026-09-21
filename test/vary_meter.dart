// 변형이 실제로 얼마나 바꾸는지 재는 도구 (수동 실행).
//   flutter test test/vary_meter.dart
//
// 씬: 늘린 루프를 **바퀴별로 잘라** 첫 바퀴와 견준다(같으면 루프로 들린다).
// 곡: 변형을 껐을 때와 켰을 때의 전체 차이.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/feel.dart';
import 'package:music_doodle_engine/genre_mix.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/variation.dart';

/// 타격 하나를 **바퀴 안 상대 시각**으로 적은 이름표.
///
/// [withVel] 이 false 면 세기를 뺀다 — 세기만 한 단 낮춘 변형은 **자리가 안 바뀐 것**인데
/// 세기를 이름에 넣으면 100% 가 달라진 것처럼 나온다. 자리와 세기를 따로 센다.
String _key(List<dynamic> e, bool drum, double loopSec, {bool withVel = true}) {
  final t = (e[drum ? 4 : 6] as num).toDouble();
  final rel = t % loopSec;
  final v = withVel ? '/${e[drum ? 2 : 3]}' : '';
  // 음 길이도 **자리**다 — 레가토(이어 붙이기)는 자리를 바꾸는 변형인데
  // 길이를 안 보면 「아무것도 안 바뀜」으로 잘못 읽힌다.
  final len = drum ? '' : '~${(e[2] as num).toStringAsFixed(3)}';
  return drum
      ? '${e[1]}$v@${rel.toStringAsFixed(4)}'
      : '${(e[1] as num).toStringAsFixed(1)}$v$len@${rel.toStringAsFixed(4)}';
}

int _bag(List<String> a, List<String> b) {
  final ma = <String, int>{}, mb = <String, int>{};
  for (final k in a) {
    ma[k] = (ma[k] ?? 0) + 1;
  }
  for (final k in b) {
    mb[k] = (mb[k] ?? 0) + 1;
  }
  var d = 0;
  for (final k in {...ma.keys, ...mb.keys}) {
    d += ((ma[k] ?? 0) - (mb[k] ?? 0)).abs();
  }
  return d;
}

void main() {
  test('변형 계량', () {
    // ignore: avoid_print
    void p(String s) => print(s);
    p('장르         씬 한 바퀴  바퀴마다 다른 것        곡 전체 차이');
    for (final g in kGenreDuck.keys) {
      final tr = Transport();
      final off = Project.initial()
        ..setGenre(g)
        ..setFeel(const Feel(vary: 0, fill: 0));
      final on = Project.initial()
        ..setGenre(g)
        ..setFeel(const Feel(vary: 1.0, fill: 0));
      final cycle = const VarySpec(amount: 1.0).cycle;

      // ── 씬 ──
      final b = SceneSequencer.build(on, tr, reps: cycle);
      final turns = <List<String>>[for (var i = 0; i < cycle; i++) <String>[]];
      final turnsNv = <List<String>>[
        for (var i = 0; i < cycle; i++) <String>[],
      ];
      void put(List<List<dynamic>> src, bool drum) {
        for (final e in src) {
          final t = (e[drum ? 4 : 6] as num).toDouble();
          var i = (t / b.loopSec).floor();
          if (i < 0) i = 0;
          if (i >= cycle) i = cycle - 1;
          turns[i].add(_key(e, drum, b.loopSec));
          turnsNv[i].add(_key(e, drum, b.loopSec, withVel: false));
        }
      }

      put(b.drums, true);
      put(b.notes, false);
      final base = turns[0].length;
      // 자리가 다른 것 — 더해지거나 빠지거나 음이 바뀐 것(세기는 안 본다)
      final diffs = [
        for (var i = 1; i < cycle; i++)
          base == 0 ? 0 : (_bag(turnsNv[0], turnsNv[i]) * 100 / base).round(),
      ];
      // 세기까지 보면 몇 %인지 — 자리는 그대로고 세기만 바뀐 바퀴를 알아보려고
      final withV = [
        for (var i = 1; i < cycle; i++)
          base == 0 ? 0 : (_bag(turns[0], turns[i]) * 100 / base).round(),
      ];

      // ── 곡 ──
      final g0 = SceneSequencer.buildSong(off, tr);
      final g1 = SceneSequencer.buildSong(on, tr);
      final gd =
          _bag(
            [for (final e in g0.drums) _key(e, true, 1e9)],
            [for (final e in g1.drums) _key(e, true, 1e9)],
          ) +
          _bag(
            [for (final e in g0.notes) _key(e, false, 1e9)],
            [for (final e in g1.notes) _key(e, false, 1e9)],
          );
      final gTot = g0.drums.length + g0.notes.length;

      p(
        '${g.padRight(12)} ${base.toString().padLeft(4)}   '
        '자리 ${diffs.map((e) => '$e%').join('·').padRight(14)} '
        '세기포함 ${withV.map((e) => '$e%').join('·').padRight(16)} '
        '곡 ${gTot == 0 ? 0 : (gd * 100 / gTot).round()}%',
      );
    }
  });
}
