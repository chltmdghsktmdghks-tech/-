// **드럼 줄이 어떻게 생겼는가** 를 재는 도구 (수동 실행).
//   flutter test test/groove_meter.dart
//
// 드럼 시험은 여태 **소리**만 봤다(음색·세기 반응·좌우). 정작 **리듬**은 아무도 안 봤다.
// 여기서 보는 것:
//   · 마디마다 달라지는가 — 1마디를 네 번 붙인 것은 사람이 친 것처럼 안 들린다
//   · 하이햇이 완전히 규칙적인가 — 그게 '머신건'이다
//   · 세기가 몇 가지인가 — 전부 최대면 다이내믹이 없다
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';

void main() {
  test('그루브 계량', () {
    // ignore: avoid_print
    void pr(String s) => print(s);
    pr('장르        패턴             마디 킥 스네어 햇  백비트 마디변화 햇격자  세기종류');
    final seen = <String>{};
    for (final g in kGenres) {
      final proj = Project.initial()..setGenre(g.key);
      for (final sc in proj.scenes) {
        for (final t in proj.tracks.where((t) => t.type == 'drum')) {
          final clip = sc.clips[t.id];
          if (clip == null || !seen.add(clip)) continue;
          final d = findDrumPattern(clip);
          if (d == null) continue;
          final hits = buildDrumPattern(d);
          final bars = d.bars;
          final k = hits.where((h) => h.lane == 'kick').toList();
          final s = hits.where((h) => h.lane == 'snare').toList();
          final h8 = hits.where((h) => h.lane == 'hat').toList();
          // 백비트 — **스네어든 박수든** 2·4박(스텝 4·12)에 있는가.
          //
          // 스네어만 세면 하우스·프로그·디스코·가스펠이 전부 낮게 나온다 —
          // 그 스타일들은 뒷박을 **박수**로 친다. 「백비트 25%」를 보고
          // 「하우스에 뒷박이 없다」고 읽을 뻔했다(그건 계기판이 틀린 것이다).
          final backHits = [...s, ...hits.where((h) => h.lane == 'clap')];
          var back = 0, snareTot = 0;
          for (final n in backHits) {
            snareTot++;
            final w = n.step % 16;
            if (w == 4 || w == 12) back++;
          }
          // 마디끼리 다른가 — src 안에서 마디별 타격 자리 집합 비교
          final perBar = <int, Set<String>>{};
          for (final n in hits) {
            perBar
                .putIfAbsent(n.step ~/ 16, () => {})
                .add('${n.lane}${n.step % 16}');
          }
          final shapes = perBar.values
              .map((x) => (x.toList()..sort()).join(','))
              .toSet();
          // 하이햇 격자 — 간격이 몇 가지인가(한 가지면 완전히 규칙적)
          final hs = h8.map((x) => x.step).toList()..sort();
          final gaps = <int>{};
          for (var i = 1; i < hs.length; i++) {
            gaps.add(hs[i] - hs[i - 1]);
          }
          final vels = hits.map((x) => x.vel).toSet().length;
          pr(
            '${g.key.padRight(11)} ${clip.padRight(16)} '
            '${bars.toString().padLeft(3)} '
            '${(k.length / bars).toStringAsFixed(1).padLeft(3)} '
            '${(s.length / bars).toStringAsFixed(1).padLeft(4)} '
            '${(h8.length / bars).toStringAsFixed(1).padLeft(4)} '
            '${snareTot == 0 ? '   -' : '${(back * 100 / snareTot).round()}%'.padLeft(5)} '
            '${'${shapes.length}/${perBar.length}'.padLeft(6)} '
            '${hs.isEmpty ? '  -' : '${gaps.length}종'.padLeft(4)} '
            '${'$vels종'.padLeft(5)}',
          );
        }
      }
    }
  });
}
