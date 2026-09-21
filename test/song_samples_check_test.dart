// 샘플곡 확인 — 씬 클립이 아니라 **타임라인 레인**으로 짜였는지, 간주(인트로·
// 브레이크·아웃트로)에만 멜로디가 있고 벌스·코러스 등에는 없는지, 그 간주
// 멜로디가 코드톤(0·2·4도)만이 아니라 지나가는음도 쓰는지 — `song_samples.dart`.
//   flutter test test/song_samples_check_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/song_samples.dart';

void main() {
  test('샘플곡 6개', () async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final defs = buildSampleSongs();
    check('0) 6개(대표 장르 5 + 연주곡 1)', defs.length == 6, '${defs.length}개');

    for (final def in defs) {
      final p = Project.initial();
      def.customize(p);
      final isInstrumental = def.name.contains('연주곡');

      // 1) 씬 클립은 전부 비어 있다 — 소리는 전부 레인에서 와야 한다.
      final sceneHasContent = p.scenes.any(
        (s) => s.clips.values.any((v) => v != null),
      );
      check('${def.name} — 씬은 전부 빈 자리(레인으로만 짬)', !sceneHasContent, '');

      // 1-b) 8·16마디짜리 구간이 4마디로 잘리지 않는다 — 씬이 비어 있으면
      // `loopBarsOf` 가 4로 떨어지므로 `reps` 를 그만큼 늘려야 한다(전에
      // `reps: 1` 로 고정해 뒀다가 벌스·코러스가 전부 4마디로 잘려 나온
      // 것을 실기기에서 보고 잡았다 — 곡 길이가 2:15 대신 1:26).
      final totalBars = p.song.sections.fold<int>(
        0,
        (sum, s) => sum + p.loopBarsOf(s.scene) * s.reps,
      );
      check(
        '${def.name} — 구간이 잘리지 않고 온전한 마디 수로 있다',
        totalBars >= 40, // 제일 짧은 로파이도 44마디, 잘렸으면 4×7=28에 그친다
        '$totalBars마디',
      );

      // 2) 구간이 한 판보다 길면 레인이 여러 번 놓여 채운다 — 최소한 어느
      //    트랙 하나는(드럼 등) 레인 클립이 2개 이상인 구간이 있어야 한다
      //    (8마디 구간 + 4마디 판 조합이 실제로 있다는 뜻).
      final anyRepeated = p.song.lanes
          .fold<Map<String, int>>({}, (m, c) {
            final k = '${c.section}:${c.trackId}';
            m[k] = (m[k] ?? 0) + 1;
            return m;
          })
          .values
          .any((n) => n >= 2);
      check('${def.name} — 긴 구간은 레인이 이어 붙어 채운다', anyRepeated, '');

      for (final t in p.tracks) {
        if (t.type != 'melody') continue;
        // 팝은 멜로디 타입 트랙이 둘(목소리·아르페지오) — 목소리만 간주 규칙을 탄다.
        final isVocalLike = t.voice == 'vocal' || def.genre != 'pop';
        for (var i = 0; i < p.song.sections.length; i++) {
          final name = p.scenes[p.song.sections[i].scene].name;
          final has = p.song.lanesIn(i, t.id).isNotEmpty;
          final vocalSection = name == '벌스' || name == '코러스' || name == '브리지';
          if (isInstrumental) {
            check(
              '${def.name} · $i번 $name(${t.name}) — 연주곡은 멜로디 없음',
              !has,
              '$has',
            );
          } else if (isVocalLike && vocalSection) {
            check(
              '${def.name} · $i번 $name(${t.name}) — 노래 파트엔 멜로디 없음',
              !has,
              '$has',
            );
          } else if (isVocalLike &&
              (name == '인트로' || name == '브레이크' || name == '아웃트로')) {
            check(
              '${def.name} · $i번 $name(${t.name}) — 간주엔 멜로디가 있다',
              has,
              '$has',
            );
          }
        }
      }

      if (!isInstrumental) {
        // 간주 판(userNote) 에 코드톤(0·2·4)만이 아니라 지나가는음(1·3·5·6)도 있다.
        final passing = p.userNote.values.expand((n) => n.notes).any(
          (n) => [1, 3, 5, 6].contains((n[0] as num).toInt() % 7),
        );
        check('${def.name} — 지나가는음이 섞여 있다', passing, '');
      }
    }

    // ignore: avoid_print
    print(fail == 0 ? '샘플곡 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
