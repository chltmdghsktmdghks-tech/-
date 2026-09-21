// **한 씬에 코드 악기가 둘이면 같은 자리에 두면 안 된다.** (작곡·편곡 품질)
//   flutter test test/stack_check_test.dart
//
// 재즈 비브라폰이 전체 대비 −24.7dB 로 안 들린 것이 Phase 3 부터 「믹스 문제」로
// 남아 있었다. 아니었다 — **비브라폰이 피아노와 완전히 같은 음을 치고 있었다.**
// 두 악기가 같은 진행을 같은 옥타브에서 치면 한쪽은 소리를 키워도 안 들린다.
// 페이더로 못 고치는 종류다. 편곡으로만 고쳐진다.
//
// 재 봤더니 그런 자리가 여섯 곳이었다(재즈 100% · 트랩 100% · 팝 100% ·
// R&B 100% · 엠비언트 94% · 프로그하우스 57%). 위층을 맡는 줄에 층(oct)을 줬다.
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/theory.dart';

/// 일부러 겹쳐 두는 짝 — **겹치는 게 그 소리인 것**만 적는다.
///
/// 팝 코러스의 기타는 8분으로 긁고 스트링은 마디를 끈다. 음은 같아도 하나는
/// 때리고 하나는 깔리는 소리라 서로를 안 지운다 — 팝 코러스가 그렇게 만들어진다.
/// (엠비언트 스트링 둘은 예외였는데, 두 번째 줄에 sus2·add9·sus4 를 줘서
///  81% → 27% 로 내려갔다. 예외를 지웠다 — **고칠 수 있으면 고치는 게 먼저다.**)
const _layered = {'Pop Gtr C↔Pop Str C'};

double _midi(double f) => 69 + 12 * (math.log(f / 440) / math.ln2);

void main() {
  test('코드 트랙 겹침', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final same = <String>[];
    var pairs = 0;
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
        for (var i = 0; i < rows.length; i++) {
          for (var j = i + 1; j < rows.length; j++) {
            final a = rows[i], b = rows[j];
            if (_layered.contains('${a.$1}↔${b.$1}') ||
                _layered.contains('${b.$1}↔${a.$1}')) {
              continue;
            }
            var hit = 0, tot = 0;
            for (final ca in a.$2) {
              for (final cb in b.$2) {
                // 같은 순간에 울리는 것만 견준다
                if (cb.step >= ca.step + ca.len ||
                    ca.step >= cb.step + cb.len) {
                  continue;
                }
                for (final fa in ca.freqs) {
                  tot++;
                  for (final fb in cb.freqs) {
                    if ((_midi(fa) - _midi(fb)).abs() < 0.5) {
                      hit++;
                      break;
                    }
                  }
                }
              }
            }
            if (tot == 0) continue;
            pairs++;
            final pct = hit * 100 / tot;
            if (pct > 60) {
              same.add('${g.key}/${sc.name} ${a.$1}↔${b.$1} ${pct.round()}%');
            }
          }
        }
      }
    }
    check(
      '1) 코드 악기 둘이 같은 음을 치지 않는다',
      same.isEmpty,
      same.isEmpty
          ? '$pairs쌍 전부 (일부러 포개는 ${_layered.length}쌍 제외)'
          : same.take(5).join(' · '),
    );

    // ignore: avoid_print
    print(fail == 0 ? '코드 겹침 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
