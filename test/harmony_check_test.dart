// Phase 4 — **이론을 몰라도 어울리는 화성을 얻는가.** (개선 계획 6-4)
//   flutter test test/harmony_check_test.dart
//
// 지키는 것:
//  1. 코드톤 판정이 조와 무관하다(도수 공간)
//  2. 멜로디에 실제로 맞는 코드를 고른다 — **사람이 쓴 것보다 못하지 않다**
//  3. dim 은 웬만하면 안 고른다
//  4. 처음과 끝은 으뜸화음 쪽
//  5. 멜로디가 쉬는 자리는 앞 코드를 이어 간다
//  6. 같은 입력 → 같은 결과
//  7. 나온 줄을 그대로 코드 패턴으로 쓸 수 있다
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genre_mix.dart';
import 'package:music_doodle_engine/harmony.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/theory.dart';

/// 씬에서 **같이 울리는** 멜로디·코드 짝. 이름으로 묶으면 벌스 멜로디에
/// 코러스 코드가 붙는다 — 기준이 틀리면 그 뒤 숫자는 전부 뜻이 없다.
List<(List<List<Object?>>, List<List<Object?>>, int)> _pairs() {
  final out = <(List<List<Object?>>, List<List<Object?>>, int)>[];
  for (final g in kGenreDuck.keys) {
    final p = Project.initial()..setGenre(g);
    for (final sc in p.scenes) {
      for (final mt in p.tracks.where((t) => t.type == 'melody')) {
        final mc = sc.clips[mt.id];
        if (mc == null) continue;
        for (final ct in p.tracks.where((t) => t.type == 'chord')) {
          final cc = sc.clips[ct.id];
          if (cc == null) continue;
          final m = p.findNote('melody', mc), c = p.findNote('chord', cc);
          if (m == null || c == null || m.notes.isEmpty || c.notes.isEmpty) {
            continue;
          }
          out.add((m.notes, c.notes, m.bars));
          break;
        }
      }
    }
  }
  return out;
}

void main() {
  test('어울리는 코드', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    const cMinor = MusicKey(root: 0, mode: 'minor');
    const fMajor = MusicKey(root: 5, mode: 'major');

    // ── 1) 조가 달라도 답이 같다 ──
    {
      // 도수로 저장하므로 조를 옮겨도 **같은 번호**가 나와야 한다
      final mel = <List<Object?>>[
        for (var b = 0; b < 4; b++) ...[
          [0, b * 16, 4, 3],
          [2, b * 16 + 4, 4, 2],
          [4, b * 16 + 8, 8, 3],
        ],
      ];
      final a = suggestChords(mel, bars: 4, key: cMinor);
      final b = suggestChords(
        mel,
        bars: 4,
        key: cMinor.root == 0 ? const MusicKey(root: 7, mode: 'minor') : cMinor,
      );
      check(
        '1) 조를 옮겨도 같은 번호',
        [for (final x in a) x.index].join() ==
            [for (final x in b) x.index].join(),
        [for (final x in a) x.index].join(','),
      );
      // 으뜸화음 코드톤(0·2·4)만 있는 멜로디 → i 를 골라야 한다
      check(
        '1-b) 뻔한 멜로디는 뻔한 코드',
        a.every((e) => e.index == 0),
        [for (final x in a) x.index].join(','),
      );
    }

    // ── 2) 사람이 쓴 것보다 못하지 않다 ──
    {
      final pairs = _pairs();
      var human = 0.0, auto = 0.0, agree = 0.0;
      for (final (mel, ch, bars) in pairs) {
        human += harmonyFit(mel, ch, bars: bars);
        final picks = suggestChords(mel, bars: bars, key: cMinor);
        auto += harmonyFit(mel, chordRowsOf(picks), bars: bars);
        var same = 0, n = 0;
        for (final pk in picks) {
          var h = -1, at = -1;
          for (final row in ch) {
            final st = (row[1] as num).toInt();
            if (st <= pk.step && st > at) {
              at = st;
              h = ((row[0] as num).toInt() % 7 + 7) % 7;
            }
          }
          if (h < 0) continue;
          n++;
          if (h == pk.index) same++;
        }
        agree += n == 0 ? 0 : same / n;
      }
      final hp = human / pairs.length, ap = auto / pairs.length;
      check(
        '2) 사람이 쓴 코드보다 못하지 않다',
        ap >= hp,
        '사람 ${(hp * 100).round()}% → 자동 ${(ap * 100).round()}% (${pairs.length}쌍)',
      );
      // 사람과 **얼마나 같은 것을 고르는가** — 아무렇게나 고르면 1/7(14%)이다
      check(
        '2-b) 사람과 같은 코드를 고르는 비율',
        agree / pairs.length > 0.45,
        '${(agree / pairs.length * 100).round()}% (아무렇게나면 14%)',
      );
    }

    // ── 3) dim 은 피한다 ──
    {
      // 단조에서 dim 은 ii(번호 1). 그 코드톤만 있는 멜로디를 줘도
      // 웬만하면 딴 걸 고른다 — 이론상 맞아도 초보 귀에는 틀린 소리다.
      final dimTones = <List<Object?>>[
        for (var b = 0; b < 4; b++) ...[
          [1, b * 16, 8, 3],
          [3, b * 16 + 8, 8, 3],
        ],
      ];
      final picks = suggestChords(dimTones, bars: 4, key: cMinor);
      final dimIdx = [
        for (var i = 0; i < 7; i++)
          if (diatonicChords(cMinor)[i].type == 'dim') i,
      ];
      final used = picks.where((e) => dimIdx.contains(e.index)).length;
      check(
        '3) dim 은 웬만하면 안 고른다',
        used == 0,
        'dim 번호 ${dimIdx.join(',')} · ${picks.length}자리 중 $used번',
      );
    }

    // ── 4) 처음과 끝 ──
    {
      // 어느 코드든 비슷하게 맞는 멜로디(스케일을 훑는다) → 끝은 으뜸화음으로 돌아온다
      final scale = <List<Object?>>[
        for (var i = 0; i < 32; i++) [i % 7, i * 2, 2, 2],
      ];
      final picks = suggestChords(scale, bars: 4, key: fMajor);
      check(
        '4) 끝은 으뜸화음으로 돌아온다',
        picks.last.index == 0,
        [for (final x in picks) x.index].join(','),
      );
    }

    // ── 5) 쉬는 자리는 앞 코드를 이어 간다 ──
    {
      final sparse = <List<Object?>>[
        [0, 0, 8, 3], // 1마디에만 있다
      ];
      final picks = suggestChords(sparse, bars: 4, key: cMinor);
      check(
        '5) 쉬는 자리는 이어 간다',
        picks.length == 4 && picks.every((e) => e.index == picks.first.index),
        [
          for (final x in picks) '${x.index}(${(x.confidence * 100).round()}%)',
        ].join(' '),
      );
      check(
        '5-b) 멜로디가 없으면 확신도 0',
        picks.skip(1).every((e) => e.confidence == 0),
        '뒤 세 자리 전부 0',
      );
    }

    // ── 6) 결정적 ──
    {
      final pairs = _pairs();
      var same = true;
      for (final (mel, _, bars) in pairs.take(20)) {
        final a = suggestChords(mel, bars: bars, key: cMinor);
        final b = suggestChords(mel, bars: bars, key: cMinor);
        if ([for (final x in a) x.index].join() !=
            [for (final x in b) x.index].join()) {
          same = false;
        }
      }
      check('6) 같은 입력 → 같은 결과', same, '난수를 안 쓴다');
    }

    // ── 7) 나온 줄을 그대로 쓸 수 있다 ──
    {
      final pairs = _pairs();
      final (mel, _, bars) = pairs.first;
      final rows = chordRowsOf(suggestChords(mel, bars: bars, key: cMinor));
      final def = NotePatternDef('시험', bars, bars, rows);
      final hits = buildChordPattern(def, cMinor);
      final bad = rows.where((r) {
        final s = (r[1] as num).toInt();
        return s < 0 || s >= bars * kStepsPerBar;
      }).length;
      check(
        '7) 코드 패턴으로 바로 쓸 수 있다',
        hits.length == rows.length &&
            bad == 0 &&
            hits.every((h) => h.freqs.isNotEmpty),
        '${rows.length}자리 → 타격 ${hits.length}개 · 범위 밖 $bad개',
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '어울리는 코드 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
