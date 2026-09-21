// 스윙이 **실제로 무엇을 미는지** 재는 도구 (수동 실행).
//   flutter test test/swing_meter.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/feel.dart';
import 'package:music_doodle_engine/genre_mix.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';

void main() {
  test('스윙 계량', () {
    // ignore: avoid_print
    void p(String s) => print(s);
    p('장르         16분(ms)  밀린 타격/전체            밀린 음/전체   최대밀림');
    for (final g in kGenreDuck.keys) {
      final tr = Transport();
      final off = Project.initial()
        ..setGenre(g)
        ..setFeel(const Feel(groove: 0, vary: 0, fill: 0));
      final on = Project.initial()
        ..setGenre(g)
        ..setFeel(const Feel(groove: 1.0, vary: 0, fill: 0));
      final a = SceneSequencer.build(off, tr, reps: 1);
      final b = SceneSequencer.build(on, tr, reps: 1);
      final stepMs = 60.0 / tr.bpm / 4 * 1000;

      // 자리(레인·음높이)로 짝을 지어 시간차를 본다
      Map<String, List<double>> byKey(List<List<dynamic>> src, bool drum) {
        final m = <String, List<double>>{};
        for (final e in src) {
          final k = drum ? e[1] as String : (e[1] as num).toStringAsFixed(1);
          (m[k] ??= []).add((e[drum ? 4 : 6] as num).toDouble());
        }
        for (final v in m.values) {
          v.sort();
        }
        return m;
      }

      (int, int, double) diff(
        List<List<dynamic>> x,
        List<List<dynamic>> y,
        bool drum,
      ) {
        final ma = byKey(x, drum), mb = byKey(y, drum);
        var moved = 0, total = 0;
        var maxMs = 0.0;
        for (final k in ma.keys) {
          final la = ma[k]!, lb = mb[k] ?? const <double>[];
          for (var i = 0; i < la.length; i++) {
            total++;
            if (i >= lb.length) continue;
            final d = (lb[i] - la[i]).abs() * 1000;
            if (d > 1) {
              moved++;
              if (d > maxMs) maxMs = d;
            }
          }
        }
        return (moved, total, maxMs);
      }

      final (dm, dt, dmax) = diff(a.drums, b.drums, true);
      final (nm, nt, nmax) = diff(a.notes, b.notes, false);
      final mx = dmax > nmax ? dmax : nmax;
      p(
        '${g.padRight(11)} ${stepMs.toStringAsFixed(0).padLeft(4)}ms   '
        '${'$dm/$dt'.padRight(10)} (${dt == 0 ? 0 : (dm * 100 / dt).round()}%)   '
        '${'$nm/$nt'.padRight(9)} (${nt == 0 ? 0 : (nm * 100 / nt).round()}%)   '
        '${mx.toStringAsFixed(0)}ms',
      );
    }

    // 레인별로 — 하이햇만 밀리고 킥·스네어는 제자리인지
    p('── 레인별 (로파이) ──');
    final tr = Transport();
    final off = Project.initial()
      ..setGenre('lofi')
      ..setFeel(const Feel(groove: 0, vary: 0, fill: 0));
    final on = Project.initial()
      ..setGenre('lofi')
      ..setFeel(const Feel(groove: 1.0, vary: 0, fill: 0));
    final a = SceneSequencer.build(off, tr, reps: 1);
    final b = SceneSequencer.build(on, tr, reps: 1);
    final lanes = <String, List<int>>{};
    for (final lane in {for (final d in a.drums) d[1] as String}) {
      final la = [
        for (final d in a.drums)
          if (d[1] == lane) (d[4] as num).toDouble(),
      ]..sort();
      final lb = [
        for (final d in b.drums)
          if (d[1] == lane) (d[4] as num).toDouble(),
      ]..sort();
      var moved = 0;
      for (var i = 0; i < la.length && i < lb.length; i++) {
        if ((lb[i] - la[i]).abs() > 0.001) moved++;
      }
      lanes[lane] = [moved, la.length];
    }
    for (final e in lanes.entries) {
      p('  ${e.key.padRight(8)} ${e.value[0]}/${e.value[1]}');
    }
  });
}
