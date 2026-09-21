// **코드 트랙이 둘 이상인 장르에서 둘이 같은 자리에 있는가** 를 재는 도구 (수동 실행).
//   flutter test test/stack_meter.dart
//
// 트랩(패드+브라스) · 프로그하우스(패드+스탭) · 엠비언트(패드+스트링) · 재즈(피아노+비브)
// 는 코드 트랙이 둘이다. 둘이 **같은 진행을 같은 옥타브에서** 치면 한쪽이 다른 쪽에
// 완전히 묻힌다 — 재즈 비브라폰이 전체 대비 −24.7dB 였던 이유를 여기서 찾는다.
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/theory.dart';

double _midi(double f) => 69 + 12 * (math.log(f / 440) / math.ln2);

void main() {
  test('코드 트랙 겹침', () {
    // ignore: avoid_print
    void pr(String s) => print(s);
    pr('장르        씬          트랙쌍                    음역A      음역B    겹침  같은음%');
    for (final g in kGenres) {
      final proj = Project.initial()..setGenre(g.key);
      final key = MusicKey(root: 0, mode: g.mode);
      for (final sc in proj.scenes) {
        final rows = <(String, List<ChordHit>)>[];
        for (final t in proj.tracks.where((t) => t.type == 'chord')) {
          final clip = sc.clips[t.id];
          if (clip == null) continue;
          final d = proj.findNote('chord', clip);
          if (d == null || d.notes.isEmpty) continue;
          rows.add((clip, buildChordPattern(d, key)));
        }
        if (rows.length < 2) continue;
        for (var i = 0; i < rows.length; i++) {
          for (var j = i + 1; j < rows.length; j++) {
            final a = rows[i], b = rows[j];
            List<double> mid(List<ChordHit> h) => [
              for (final c in h)
                for (final f in c.freqs) _midi(f),
            ];
            final ma = mid(a.$2), mb = mid(b.$2);
            if (ma.isEmpty || mb.isEmpty) continue;
            final aLo = ma.reduce(math.min), aHi = ma.reduce(math.max);
            final bLo = mb.reduce(math.min), bHi = mb.reduce(math.max);
            final ov = math.min(aHi, bHi) - math.max(aLo, bLo);
            // 정확히 같은 음(반음 이내)이 몇 %인가 — 같은 순간에 울리는 것만
            var same = 0, tot = 0;
            for (final ca in a.$2) {
              for (final cb in b.$2) {
                if (cb.step >= ca.step + ca.len ||
                    ca.step >= cb.step + cb.len) {
                  continue;
                }
                for (final fa in ca.freqs) {
                  tot++;
                  for (final fb in cb.freqs) {
                    if ((_midi(fa) - _midi(fb)).abs() < 0.5) {
                      same++;
                      break;
                    }
                  }
                }
              }
            }
            final ra = '${aLo.round()}~${aHi.round()}'.padRight(9);
            final rb = '${bLo.round()}~${bHi.round()}'.padRight(9);
            final pct = tot == 0 ? '-' : '${(same * 100 / tot).round()}%';
            pr(
              '${g.key.padRight(11)} ${sc.name.padRight(11)} '
              '${'${a.$1} ↔ ${b.$1}'.padRight(25)} '
              '$ra  $rb  ${ov.round()}반음  $pct',
            );
          }
        }
      }
    }
  });
}
