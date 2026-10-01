// 두들플레이 코드 재설계 (2026-10-01) — 결정론적 시험(실시간 타이머 없음).
//   #3 장르마다 코드가 다르다   #4 위/아래 = 대체코드(다음 코드에 영향)   #5 한 박에 코드 둘(반박)
//   flutter test test/doodle_genre_sub_half_test.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/doodle_chords.dart';
import 'package:music_doodle_engine/doodle_genre_chords.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/meter.dart' as mt;
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/tap_rec.dart';
import 'package:music_doodle_engine/theory.dart';
import 'package:music_doodle_engine/ui/doodle_play_view.dart';

String _name(MusicKey k, DoodleChordPick p, int color) =>
    doodleChordName(doodleChordSpec(k, p, color));

DoodleChordPlan _plan(
  List<DoodleChordPick> base, {
  String mode = 'major',
  String genre = 'pop',
  int spb = 16,
  int beatSteps = 4,
  int seed = 1,
}) => DoodleChordPlan(
  base,
  mode: mode,
  genre: genre,
  spb: spb,
  beatSteps: beatSteps,
  rng: math.Random(seed),
);

void main() {
  // ───────────────────────── #3 장르 팔레트 ─────────────────────────
  group('#3 장르마다 코드가 다르다', () {
    test('앱의 모든 장르에 팔레트가 있다(빠뜨리면 조용히 일반 진행이 된다)', () {
      for (final g in kGenres) {
        expect(kDoodleGenreChords.containsKey(g.key), isTrue, reason: g.key);
      }
    });

    test('모든 진행은 4마디·도수 0~6·장/단조 둘 다 있고 표기가 올바르다', () {
      for (final g in kDoodleGenreChords.keys) {
        for (final mode in ['minor', 'major']) {
          final pool = doodleGenrePool(g, mode)!;
          expect(pool.length, greaterThanOrEqualTo(3), reason: '$g/$mode 풀이 얇다');
          for (final p in pool) {
            expect(p.length, 4, reason: '$g/$mode $p');
            expect(p.every((c) => c.degree >= 0 && c.degree <= 6), isTrue);
            expect(p.every((c) => c.type == null || c.type == 'dom7'), isTrue);
          }
        }
      }
    });

    test('장르끼리 풀이 서로 다르다(같은 풀을 돌려 쓰지 않는다)', () {
      for (final mode in ['minor', 'major']) {
        final sig = <String, String>{};
        for (final e in kDoodleGenreChords.entries) {
          final s = (mode == 'minor' ? e.value.minor : e.value.major).toList()..sort();
          final k = s.join('|');
          expect(sig[k], isNull, reason: '${e.key} 와 ${sig[k]} 의 $mode 풀이 같다');
          sig[k] = e.key;
        }
      }
    });

    test('뽑힌 기본 진행은 늘 그 장르 풀 안에서 나온다 (장르 × 조 × 마디 수 × 씨앗)', () {
      for (final g in kDoodleGenreChords.keys) {
        for (final mode in ['minor', 'major']) {
          final pool = doodleGenrePool(g, mode)!;
          final strs = {for (final p in pool) p.join(',')};
          for (var seed = 0; seed < 25; seed++) {
            for (final bars in [1, 2, 3, 4, 5, 6, 7, 8]) {
              final plan = doodleBasePlan(
                mode: mode,
                bars: bars,
                genre: g,
                rng: math.Random(seed),
              );
              expect(plan.length, bars);
              expect(plan.every((c) => c.degree >= 0 && c.degree <= 6), isTrue);
              if (bars == 4) {
                // 4마디는 풀의 한 진행 그대로(재즈 계열의 V→V7 은 이미 풀에 D 로 적혀 있거나 아래 보정)
                final got = plan.join(',');
                final okPlain = strs.contains(got);
                final okFixed = pool.any((p) {
                  final fixed = [
                    for (var i = 0; i < 4; i++)
                      (p[i].degree == 4 && p[i].type == null && p[(i + 1) % 4].degree == 0 &&
                              kDoodleGenreChords[g]!.flavor == DoodleFlavor.jazzy)
                          ? const DoodleChordPick(4, 'dom7')
                          : p[i],
                  ];
                  return fixed.join(',') == got;
                });
                expect(okPlain || okFixed, isTrue, reason: '$g/$mode seed=$seed $plan');
              }
            }
          }
        }
      }
    });

    test('로파이: 7th·9th 색채 + iv-VII-III-VI 턴어라운드/ii-V', () {
      expect(doodleGenreColor('lofi'), 2);
      const k = MusicKey(root: 0, mode: 'minor');
      final pool = doodleGenrePool('lofi', 'minor')!;
      // 웹 원본 벌스: iv-VII-III-VI
      expect(pool.first.map((c) => c.degree), [3, 6, 2, 5]);
      expect(pool.first.map((c) => _name(k, c, 2)), ['Fm7(9)', 'Bb7(9)', 'EbM7(9)', 'AbM7(9)']);
      // 느슨한 ii-V: ii°-V7 가 들어간 진행이 있다
      expect(
        pool.any((p) => p[0].degree == 1 && p[1] == const DoodleChordPick(4, 'dom7')),
        isTrue,
      );
      // 모든 코드가 7th 이상(3화음 없음)
      for (final p in pool) {
        for (final c in p) {
          final t = doodleChordText(k, c, 2);
          expect(t, isNotNull, reason: 'lofi 코드는 3화음이 아니다: $c');
        }
      }
    });

    test('하우스: 단순 반복 — 8마디는 4마디의 되풀이, V7·딤 없음', () {
      for (var seed = 0; seed < 30; seed++) {
        final p = doodleBasePlan(mode: 'minor', bars: 8, genre: 'house', rng: math.Random(seed));
        expect(p.sublist(4), p.sublist(0, 4), reason: 'seed=$seed $p');
        expect(p.every((c) => c.type == null && c.degree != 1), isTrue);
      }
      expect(doodleGenrePool('house', 'minor')!.any((p) => p.map((c) => c.degree).join() == '0526'), isTrue);
      expect(doodleGenreColor('house'), 0);
    });

    test('힙합: 마이너 루프 — 한 진행에 서로 다른 코드가 3개 이하, i 로 시작', () {
      for (final p in doodleGenrePool('hiphop', 'minor')!) {
        expect(p.toSet().length, lessThanOrEqualTo(3), reason: '$p');
        expect(p.first.degree, 0);
      }
    });

    test('트랩: 미니멀 — 한 코드에 머문다(이웃 같은 코드를 지우지 않는다), 코드 둘 이하 색', () {
      var stays = false;
      for (var seed = 0; seed < 30; seed++) {
        final p = doodleBasePlan(mode: 'minor', bars: 4, genre: 'trap', rng: math.Random(seed));
        for (var i = 1; i < p.length; i++) {
          if (p[i] == p[i - 1]) stays = true;
        }
        expect(p.first.degree, 0);
        expect(p.every((c) => c.type == null), isTrue);
      }
      expect(stays, isTrue, reason: '트랩 진행은 으뜸에 머무는 마디가 있다');
    });

    test('시티팝: 모든 진행에 세컨더리 도미넌트(또는 V7)가 있고 그 뒤로 풀린다', () {
      for (final mode in ['minor', 'major']) {
        for (final p in doodleGenrePool('citypop', mode)!) {
          expect(p.any((c) => c.type == 'dom7'), isTrue, reason: '$mode $p');
          for (var i = 0; i < 3; i++) {
            if (p[i].type != 'dom7') continue;
            if (p[i].degree == 4) {
              // V7 은 I(정격) · vi(기만) · iii(왕도 진행 IV-V7-iii-vi) 로 간다
              expect([0, 5, 2].contains(p[i + 1].degree), isTrue, reason: '$mode $p');
            } else {
              expect(p[i + 1].degree, (p[i].degree + 3) % 7,
                  reason: '$mode $p: 세컨더리 ${p[i]} 는 5도 아래로 풀려야');
            }
          }
        }
      }
      // 세컨더리 도미넌트가 4도 아닌 뿌리(0D=V/iv, 2D=V/vi)에도 쓰인다
      final roots = {
        for (final mode in ['minor', 'major'])
          for (final p in doodleGenrePool('citypop', mode)!)
            for (final c in p)
              if (c.type == 'dom7' && c.degree != 4 && c.degree != 6) c.degree,
      };
      expect(roots, isNotEmpty);
    });

    test('재즈: 모든 진행이 ii-V(-I) 또는 5도권(뿌리가 5도씩 내려가는 사슬)', () {
      for (final mode in ['minor', 'major']) {
        for (final p in doodleGenrePool('jazz', mode)!) {
          var fifths = 0;
          for (var i = 0; i < 3; i++) {
            if (p[i + 1].degree == (p[i].degree + 3) % 7) fifths++;
          }
          expect(fifths, greaterThanOrEqualTo(2), reason: '$mode $p');
          expect(p.any((c) => c == const DoodleChordPick(4, 'dom7')), isTrue);
        }
      }
    });

    test('발라드: 다이아토닉 서정 — dom7 없음, 3화음', () {
      for (final mode in ['minor', 'major']) {
        for (final p in doodleGenrePool('ballad', mode)!) {
          expect(p.every((c) => c.type == null), isTrue);
        }
      }
      expect(doodleGenreColor('ballad'), 0);
      // 하행 i-VII-VI-v
      expect(doodleGenrePool('ballad', 'minor')!.first.map((c) => c.degree), [0, 6, 5, 4]);
    });

    test('록: 장조는 I-IV-V 계열이 중심, 단조는 i-VII-VI/i-iv-VII, 3화음(기타는 파워코드)', () {
      final maj = doodleGenrePool('rock', 'major')!;
      expect(maj.every((p) => p.every((c) => const [0, 3, 4].contains(c.degree))), isTrue);
      expect(maj.any((p) => p.map((c) => c.degree).join() == '0343'), isTrue);
      expect(doodleGenreColor('rock'), 0);
    });

    test('같은 풀이어도 장르 색(두께)이 다르다: 같은 i-VI 가 로파이 9th / 하우스 3화음', () {
      const k = MusicKey(root: 0, mode: 'minor');
      expect(_name(k, const DoodleChordPick(0), doodleGenreColor('house')), 'Cm');
      expect(_name(k, const DoodleChordPick(0), doodleGenreColor('lofi')), 'Cm7(9)');
      expect(_name(k, const DoodleChordPick(0), doodleGenreColor('jazz')), 'Cm7');
    });

    test('반복 루프 장르의 좌우 걸음은 V7·딤·단조 v 로 끌지 않는다', () {
      for (final g in ['house', 'trap', 'hiphop', 'drill', 'ambient', 'proghouse']) {
        for (var d = 0; d < 7; d++) {
          for (final dir in [-1, 1]) {
            for (var s = 0; s < 20; s++) {
              final n = doodleStepChord(DoodleChordPick(d), dir, mode: 'minor', genre: g, salt: s);
              // 어느 도수에서 출발하든 후보가 하나라도 선법적이면 그것만 나온다
              final from = doodleStepChord(DoodleChordPick(d), dir, mode: 'minor', salt: s);
              if (from.type == 'dom7' && d != 1) {
                expect(n.type, isNull, reason: '$g d=$d dir=$dir: $n');
              }
            }
          }
        }
      }
    });
  });

  // ───────────────────────── #4 대체코드 ─────────────────────────
  group('#4 위/아래 = 대체코드', () {
    test('대체는 늘 다른 코드이고 같은 입력은 같은 답(난수 없음)', () {
      for (final mode in ['major', 'minor']) {
        for (final g in ['', ...kDoodleGenreChords.keys]) {
          for (var d = 0; d < 7; d++) {
            for (final t in [null, 'dom7']) {
              final from = DoodleChordPick(d, t);
              for (var s = 0; s < 6; s++) {
                final a = doodleSubstitute(from, mode: mode, genre: g, salt: s);
                final b = doodleSubstitute(from, mode: mode, genre: g, salt: s);
                expect(a, b);
                expect(a, isNot(from), reason: '$mode/$g $from salt=$s');
                expect(a.degree, inInclusiveRange(0, 6));
              }
            }
          }
        }
      }
    });

    test('C장조 기능 가족: I↔vi/iii · IV↔ii/vi · V↔vii°/iii · vi↔I/IV', () {
      const k = MusicKey(root: 0, mode: 'major');
      Set<String> subs(int d) => {
        for (var s = 0; s < 4; s++)
          _name(k, doodleSubstitute(DoodleChordPick(d), mode: 'major', salt: s), 0),
      };
      expect(subs(0), {'Am', 'Em'});
      expect(subs(1), {'F', 'Am'});
      expect(subs(3), {'Dm', 'Am'});
      expect(subs(4), {'Bdim', 'Em'});
      expect(subs(5), {'C', 'F'});
    });

    test('A단조 아닌 C단조: i↔III/VI · iv↔VI/ii° · v↔VII/III · VII↔III/v', () {
      const k = MusicKey(root: 0, mode: 'minor');
      Set<String> subs(int d) => {
        for (var s = 0; s < 4; s++)
          _name(k, doodleSubstitute(DoodleChordPick(d), mode: 'minor', salt: s), 0),
      };
      expect(subs(0), {'Eb', 'Ab'});
      expect(subs(3), {'Ab', 'Ddim'});
      expect(subs(4), {'Bb', 'Eb'});
      expect(subs(6), {'Eb', 'Gm'});
    });

    test('V7 은 vii°/iii 로, 세컨더리 도미넌트는 같은 뿌리 3화음으로 대체된다', () {
      const k = MusicKey(root: 0, mode: 'major');
      for (var s = 0; s < 4; s++) {
        final v7 = doodleSubstitute(const DoodleChordPick(4, 'dom7'), mode: 'major', salt: s);
        expect([6, 2], contains(v7.degree));
        expect(v7.type, isNull);
        final iii7 = doodleSubstitute(const DoodleChordPick(2, 'dom7'), mode: 'major', salt: s);
        expect(_name(k, iii7, 0), 'Em'); // E7 → Em
      }
    });

    test('반복 루프 장르(하우스)의 대체코드는 딤 화음을 안 쓴다', () {
      for (var s = 0; s < 8; s++) {
        expect(doodleSubstitute(const DoodleChordPick(4), mode: 'major', genre: 'house', salt: s).degree, 2);
        expect(doodleSubstitute(const DoodleChordPick(3), mode: 'minor', genre: 'house', salt: s).degree, 5);
      }
    });

    test('위(대체) 구역은 한가운데 한 줄로 갈린다', () {
      expect(doodleSubOfY(0.0), isTrue);
      expect(doodleSubOfY(0.49), isTrue);
      expect(doodleSubOfY(0.5), isFalse);
      expect(doodleSubOfY(1.0), isFalse);
    });

    test('soundAt: 위 = 대체코드, 아래 = 깔린 코드 — 소리와 적히는 값이 같다', () {
      for (var seed = 0; seed < 20; seed++) {
        final p = _plan(const [
          DoodleChordPick(0),
          DoodleChordPick(4),
          DoodleChordPick(5),
          DoodleChordPick(3),
        ], seed: seed);
        final sub = p.soundAt(0, sub: true);
        expect(sub, isNot(p.plan[0]));
        expect(p.soundAt(0, sub: false), p.plan[0]);
        p.recordTap(0, dir: 0, sub: true);
        expect(p.pickAt(0), sub, reason: '친 소리 = 마디에 적힌 코드');
      }
    });

    test('대체를 쓰면 가운데 착지여도 다음 마디가 달라진다(대체코드에서 이어지는 걸음)', () {
      for (var seed = 0; seed < 60; seed++) {
        const base = [
          DoodleChordPick(0),
          DoodleChordPick(4),
          DoodleChordPick(5),
          DoodleChordPick(3),
        ];
        final plain = _plan(base, seed: seed)..recordTap(0, dir: 0, sub: false);
        expect(plain.pickAt(1), base[1], reason: '대체 안 쓰면 깔린 진행 그대로');

        final p = _plan(base, seed: seed)..recordTap(0, dir: 0, sub: true);
        final s0 = p.pickAt(0);
        final n1 = p.pickAt(1);
        expect(n1, isNot(base[1]), reason: 'seed=$seed: 대체 $s0 뒤에 원래 진행의 V 가 그대로 붙었다');
        expect(
          n1,
          doodleStepChord(s0, 1, mode: 'major', genre: 'pop', salt: p.salt),
          reason: '대체코드에서 이어지는 해결 걸음',
        );
      }
    });

    test('대체 + 좌우: 방향은 대체코드에서 출발한다', () {
      for (final dir in [-1, 1]) {
        for (var seed = 0; seed < 30; seed++) {
          const base = [DoodleChordPick(0), DoodleChordPick(4), DoodleChordPick(5), DoodleChordPick(3)];
          final p = _plan(base, seed: seed)..recordTap(0, dir: dir, sub: true);
          final s0 = p.soundAt(0, sub: true);
          expect(p.pickAt(1), doodleStepChord(s0, dir, mode: 'major', genre: 'pop', salt: p.salt));
        }
      }
    });

    test('미리보기 = 확정 (대체 포함)', () {
      for (var seed = 0; seed < 40; seed++) {
        final p = _plan(const [
          DoodleChordPick(0),
          DoodleChordPick(4),
          DoodleChordPick(5),
          DoodleChordPick(3),
        ], seed: seed, genre: 'jazz');
        p.recordTap(0, dir: seed % 3 - 1, sub: seed.isEven);
        final pv = p.previewNext(0);
        expect(p.pickAt(1), pv);
      }
    });

    test('착지(마지막 일반 탭)가 대체 여부를 정한다: 위→아래로 끝나면 원래 코드', () {
      final p = _plan(const [DoodleChordPick(0), DoodleChordPick(4)]);
      p.recordTap(0, dir: 0, sub: true);
      p.recordTap(0, dir: 0, sub: false);
      expect(p.landSubOf(0), isFalse);
      expect(p.pickAt(0), p.plan[0]);
      expect(p.pickAt(1), p.base[1]);
    });

    test('대체가 연쇄돼도 항상 유효한 도수 (모든 장르 × 조 × 씨앗 × 대체/방향 조합)', () {
      for (final g in kDoodleGenreChords.keys) {
        for (final mode in ['minor', 'major']) {
          for (var seed = 0; seed < 8; seed++) {
            final base = doodleBasePlan(mode: mode, bars: 8, genre: g, rng: math.Random(seed));
            final p = DoodleChordPlan(base, mode: mode, genre: g, spb: 16, beatSteps: 4, rng: math.Random(seed));
            for (var b = 0; b < 8; b++) {
              p.recordTap(b, dir: (b + seed) % 3 - 1, sub: (b * 3 + seed) % 2 == 0);
            }
            for (var b = 0; b < 8; b++) {
              final c = p.pickAt(b);
              expect(c.degree, inInclusiveRange(0, 6), reason: '$g/$mode bar $b');
            }
          }
        }
      }
    });
  });

  // ───────────────────────── #5 한 박에 코드 둘 ─────────────────────────
  group('#5 한 박에 코드 둘 (반박 코드)', () {
    test('한 박 길이는 박자표가 정한다: 4/4·3/4·5/4·7/8 = 4칸, 6/8 = 6칸', () {
      expect(doodleBeatSteps(mt.meterOf('4/4')), 4);
      expect(doodleBeatSteps(mt.meterOf('3/4')), 4);
      expect(doodleBeatSteps(mt.meterOf('5/4')), 4);
      expect(doodleBeatSteps(mt.meterOf('6/8')), 6);
      expect(doodleBeatSteps(mt.meterOf('7/8')), 4);
    });

    test('반박 자리: 박자표마다 어디인가 (그리고 전부 8분 격자=짝수 칸)', () {
      const want = {
        '4/4': [2, 6, 10, 14],
        '3/4': [2, 6, 10],
        '6/8': [4, 10],
        '5/4': [2, 6, 10, 14, 18],
        '7/8': [2, 6, 10],
      };
      for (final m in mt.kMeters) {
        final bs = doodleBeatSteps(m);
        final slots = [
          for (var s = 0; s < m.stepsPerBar; s++)
            if (doodleIsHalfSlot(s, spb: m.stepsPerBar, beatSteps: bs)) s,
        ];
        expect(slots, want[m.key], reason: m.key);
        expect(slots.every((s) => s.isEven), isTrue, reason: '${m.key}: 코드 격자(8분)에 안 놓이는 반박');
        // 다음 마디도 똑같다(마디 안 위치로 본다)
        for (final s in slots) {
          expect(doodleIsHalfSlot(s + m.stepsPerBar * 3, spb: m.stepsPerBar, beatSteps: bs), isTrue);
        }
      }
    });

    test('마지막 반박(다음 마디를 앞당겨 거는 자리)', () {
      bool last(String k, int s) {
        final m = mt.meterOf(k);
        return doodleIsLastHalf(s, spb: m.stepsPerBar, beatSteps: doodleBeatSteps(m));
      }

      expect(last('4/4', 14), isTrue);
      expect(last('4/4', 10), isFalse);
      expect(last('3/4', 10), isTrue);
      expect(last('3/4', 6), isFalse);
      expect(last('6/8', 10), isTrue);
      expect(last('6/8', 4), isFalse);
      expect(last('7/8', 10), isTrue); // 7/8: 12 칸 머리의 반박은 마디 밖이라 10 이 마지막
      expect(last('7/8', 6), isFalse);
    });

    test('doodleHalfChord: 늘 지금 코드와 다르고, 마지막 반박은 다음 마디 코드를 앞당긴다', () {
      for (final mode in ['major', 'minor']) {
        for (final g in ['', 'pop', 'jazz', 'house', 'citypop']) {
          for (var d = 0; d < 7; d++) {
            for (final dir in [-1, 0, 1]) {
              for (final sub in [false, true]) {
                for (var s = 0; s < 5; s++) {
                  final cur = DoodleChordPick(d);
                  final h = doodleHalfChord(cur, null,
                      lastBeat: false, dir: dir, sub: sub, mode: mode, genre: g, salt: s);
                  expect(h, isNot(cur), reason: '$mode/$g d=$d dir=$dir sub=$sub');
                  final nxt = DoodleChordPick((d + 3) % 7);
                  final push = doodleHalfChord(cur, nxt,
                      lastBeat: true, dir: dir, sub: sub, mode: mode, genre: g, salt: s);
                  expect(push, nxt);
                }
              }
            }
          }
        }
      }
    });

    test('가운데 반박 = 대체(I→vi), 좌 = 긴장 걸음, 우 = 해결 걸음', () {
      const cur = DoodleChordPick(0);
      final c = doodleHalfChord(cur, null,
          lastBeat: false, dir: 0, sub: false, mode: 'major', salt: 0);
      expect(c, doodleSubstitute(cur, mode: 'major', salt: 0));
      final t = doodleHalfChord(cur, null, lastBeat: false, dir: -1, sub: false, mode: 'major', salt: 3);
      expect(t, doodleStepChord(cur, -1, mode: 'major', salt: 3));
      final r = doodleHalfChord(cur, null, lastBeat: false, dir: 1, sub: false, mode: 'major', salt: 3);
      expect(r, doodleStepChord(cur, 1, mode: 'major', salt: 3));
    });

    test('머리 없이 반박만 친 것은 코드가 안 바뀐다(오프비트 스트럼 보호)', () {
      final p = _plan(const [DoodleChordPick(0), DoodleChordPick(4)]);
      expect(p.isHalfChord(2, {2}), isFalse, reason: '머리(0)가 없다');
      expect(p.isHalfChord(2, {0, 2}), isTrue);
      expect(p.isHalfChord(4, {0, 4}), isFalse, reason: '4 는 다음 박 머리');
      expect(p.isHalfChord(6, {4, 6}), isTrue, reason: '둘째 박의 반박은 둘째 박 머리가 필요');
      expect(p.isHalfChord(6, {0, 6}), isFalse, reason: '다른 박의 머리로는 안 된다');
    });

    test('중간 반박: 머리 코드와 다른 코드, 마지막 반박: 다음 마디 코드와 같다', () {
      for (var seed = 0; seed < 30; seed++) {
        final p = _plan(const [
          DoodleChordPick(0),
          DoodleChordPick(4),
          DoodleChordPick(5),
          DoodleChordPick(3),
        ], seed: seed);
        final head = p.pickAt(0);
        p.recordTap(0, dir: 0, sub: false);
        p.recordHalfTap(2, dir: 0, sub: false);
        expect(p.halfChordAt(2), isNot(head));
        p.recordHalfTap(14, dir: 0, sub: false); // 마지막 박의 반박
        expect(p.halfChordAt(14), p.previewNext(0), reason: 'seed=$seed 푸시 = 다음 마디 코드');
        expect(p.pickAt(1), p.previewNext(0));
        expect(p.pickAt(0), head, reason: '반박 탭이 마디 코드를 바꾸지 않는다');
      }
    });

    test('친 소리(방향·대체를 직접 줌) = 적힌 값(기록에서 읽음)', () {
      for (var seed = 0; seed < 20; seed++) {
        for (final step in [2, 6, 10, 14]) {
          for (final dir in [-1, 0, 1]) {
            for (final sub in [false, true]) {
              final p = _plan(const [
                DoodleChordPick(0),
                DoodleChordPick(4),
                DoodleChordPick(5),
                DoodleChordPick(3),
              ], seed: seed, genre: 'jazz');
              final live = p.halfChordAt(step, dir: dir, sub: sub);
              p.recordHalfTap(step, dir: dir, sub: sub);
              expect(p.halfChordAt(step), live, reason: 'seed=$seed step=$step dir=$dir sub=$sub');
            }
          }
        }
      }
    });

    test('마지막 마디의 푸시는 판 머리(루프로 돌아가는 코드)를 건다', () {
      final p = _plan(const [DoodleChordPick(0), DoodleChordPick(4)]);
      p.recordTap(1, dir: 0, sub: false);
      p.recordHalfTap(16 + 14, dir: 0, sub: false);
      expect(p.halfChordAt(16 + 14), p.plan[0]);
    });

    test('3/4: 반박은 둘째 박 머리(4)+2=6, 마지막 반박(10)은 다음 마디를 건다', () {
      final p = _plan(const [DoodleChordPick(0), DoodleChordPick(3)], spb: 12, beatSteps: 4);
      expect(p.isHalfChord(6, {4, 6}), isTrue);
      p.recordTap(0, dir: 0, sub: false);
      p.recordHalfTap(10, dir: 0, sub: false);
      expect(p.halfChordAt(10), p.previewNext(0));
    });

    test('6/8: 한 박=6칸, 반박=+4. 칸 2 는 반박이 아니다(기본값 4/4 가 새면 어긋난다)', () {
      final p = _plan(const [DoodleChordPick(0), DoodleChordPick(3)], spb: 12, beatSteps: 6);
      expect(p.isHalfChord(4, {0, 4}), isTrue);
      expect(p.isHalfChord(2, {0, 2}), isFalse);
      expect(p.isHalfChord(10, {6, 10}), isTrue);
      expect(p.isHalfChord(6, {0, 6}), isFalse);
      // 4/4 설정(beatSteps 4)이었다면 2 가 반박이 되어 버린다 — 박자표를 넘겨야 하는 이유
      final wrong = _plan(const [DoodleChordPick(0), DoodleChordPick(3)], spb: 12, beatSteps: 4);
      expect(wrong.isHalfChord(2, {0, 2}), isTrue);
    });

    test('빠르게 두 번: 같은 박 머리 칸으로 반올림되면 반박으로 옮긴다', () {
      int? q({
        int step = 0,
        int? prev = 0,
        int? since = 120,
        Set<int> tapped = const {0},
        String meter = '4/4',
        double stepSec = 0.125,
      }) {
        final m = mt.meterOf(meter);
        return doodleQuickHalfStep(
          step: step,
          prevStep: prev,
          sinceMs: since,
          stepSec: stepSec,
          tapped: tapped,
          spb: m.stepsPerBar,
          beatSteps: doodleBeatSteps(m),
        );
      }

      expect(q(), 2);
      expect(q(step: 4, prev: 4, tapped: {4}), 6);
      expect(q(prev: null), isNull, reason: '직전 탭이 없다');
      expect(q(prev: 4), isNull, reason: '직전 탭이 다른 칸');
      expect(q(since: 400), isNull, reason: '반박 한 칸(250ms) 안이 아니면 다음 바퀴의 같은 자리');
      expect(q(tapped: {0, 2}), isNull, reason: '이미 있는 반박을 덮지 않는다');
      expect(q(step: 2, prev: 2, tapped: {2}), isNull, reason: '이미 반박 자리');
      // 박자표별
      expect(q(step: 12, prev: 12, tapped: {12}, meter: '3/4'), 14, reason: '3/4 의 12 는 둘째 마디 머리 → 반박 14');
      expect(q(step: 0, prev: 0, meter: '6/8'), 4);
      expect(q(step: 6, prev: 6, tapped: {6}, meter: '6/8'), 10);
      expect(q(step: 2, prev: 2, tapped: {2}, meter: '6/8'), isNull, reason: '6/8 의 2 는 머리가 아니다');
      expect(q(step: 12, prev: 12, tapped: {12}, meter: '7/8'), isNull, reason: '7/8 의 꼬리 박(12)은 반박이 마디 밖');
      expect(q(step: 8, prev: 8, tapped: {8}, meter: '7/8'), 10);
    });

    test('칸 → 위치 → 칸: 모든 박자표에서 TapRecorder.stepOf 가 같은 칸으로 되돌린다', () {
      for (final m in mt.kMeters) {
        final spb = m.stepsPerBar;
        for (final loopBars in [1, 2, 4]) {
          for (final lat in [0.0, 0.07, 0.35]) {
            final rec = TapRecorder(
              steps: loopBars * spb,
              loopBars: loopBars,
              loopSec: 6.0,
              latencySec: lat,
              spb: spb,
            );
            for (var s = 0; s < loopBars * spb; s += 2) {
              final pos = doodlePosOfStep(s, loopSteps: loopBars * spb, latencyFrac: lat / 6.0);
              expect(rec.stepOf(pos), s, reason: '${m.key} bars=$loopBars lat=$lat step=$s');
            }
          }
        }
      }
    });
  });

  // ───────────────────────── 화면 연결(시계 없이) ─────────────────────────
  group('화면 연결: 장르 진행·대체·반박이 판에 적힌다', () {
    Future<dynamic> open(WidgetTester tester, String genre, {String mode = 'minor'}) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final tr = Transport()..mode = mode;
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: DoodlePlayView(
          project: Project.blank()..setGenreBare(genre),
          transport: tr,
          host: null,
          initialBars: 4,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      return tester.state(find.byType(DoodlePlayView));
    }

    List<Object?> row(List<List<Object?>> notes, int step) =>
        notes.firstWhere((n) => n[1] == step);

    testWidgets('로파이에서 깐 진행이 장르 풀의 것이고 코드 종류가 7th 이상으로 적힌다', (tester) async {
      final st = await open(tester, 'lofi');
      final base = st.debugPlan.base as List<DoodleChordPick>;
      final pools = doodleGenrePool('lofi', 'minor')!.map((p) => p.join(',')).toSet();
      expect(pools.any((s) => s == base.join(',')) || base.length == 4, isTrue);
      st.debugCommit(DoodleKind.chord, [for (final s in [0, 16, 32, 48]) TapHit(0, s, 8)]);
      final notes = st.debugChordNotes as List<List<Object?>>;
      expect(notes.length, 4);
      expect(notes.every((n) => n[4] != null), isTrue, reason: '로파이 코드는 3화음이 아니다');
    });

    testWidgets('하우스에서는 코드 종류를 안 적는다(3화음)', (tester) async {
      final st = await open(tester, 'house');
      st.debugCommit(DoodleKind.chord, [for (final s in [0, 16, 32, 48]) TapHit(0, s, 8)]);
      final notes = st.debugChordNotes as List<List<Object?>>;
      expect(notes.every((n) => n[4] == null), isTrue);
    });

    testWidgets('4/4: 박 머리(0)+반박(2) → 두 코드, 머리 음은 반박에서 끊긴다', (tester) async {
      final st = await open(tester, 'pop', mode: 'major');
      st.debugCommit(DoodleKind.chord, [TapHit(0, 0, 8), TapHit(0, 2, 2)]);
      final notes = st.debugChordNotes as List<List<Object?>>;
      final head = row(notes, 0), half = row(notes, 2);
      expect([head[0], head[4]], isNot([half[0], half[4]]), reason: '반박은 다른 코드');
      expect(head[2], 2, reason: '머리 음은 반박(2칸)에서 끊긴다');
    });

    testWidgets('반박만 친 것(머리 없음)은 마디 코드 그대로', (tester) async {
      final st = await open(tester, 'pop', mode: 'major');
      st.debugCommit(DoodleKind.chord, [TapHit(0, 2, 2), TapHit(0, 8, 4)]);
      final notes = st.debugChordNotes as List<List<Object?>>;
      expect(row(notes, 2)[0], row(notes, 8)[0]);
    });

    testWidgets('마지막 반박(14)은 다음 마디의 코드로 앞당겨 걸린다 + 리듬 락이 뒤 마디로 복사', (tester) async {
      final st = await open(tester, 'pop', mode: 'major');
      st.debugCommit(DoodleKind.chord, [TapHit(0, 12, 2), TapHit(0, 14, 2)]);
      final notes = st.debugChordNotes as List<List<Object?>>;
      // 0마디에서 친 리듬이 1~3마디에 복사된다 → 각 마디의 14 는 그 다음 마디 코드
      for (var bar = 0; bar < 3; bar++) {
        final push = row(notes, bar * 16 + 14);
        final nextHead = row(notes, (bar + 1) * 16 + 12);
        expect([push[0], push[4]], [nextHead[0], nextHead[4]], reason: 'bar $bar');
      }
    });

    testWidgets('3/4(왈츠): 반박은 6, 마지막 반박 10 — 12 칸 마디', (tester) async {
      final st = await open(tester, 'waltz', mode: 'major');
      expect(st.debugPlan.spb, 12);
      expect(st.debugPlan.beatSteps, 4);
      st.debugCommit(DoodleKind.chord, [TapHit(0, 4, 2), TapHit(0, 6, 2)]);
      final notes = st.debugChordNotes as List<List<Object?>>;
      expect(row(notes, 4)[0] == row(notes, 6)[0] && row(notes, 4)[4] == row(notes, 6)[4], isFalse);
    });

    testWidgets('6/8: 한 박 6칸 — 반박은 4 (칸 2 는 반박이 아니다)', (tester) async {
      final st = await open(tester, 'ballad68');
      expect(st.debugPlan.spb, 12);
      expect(st.debugPlan.beatSteps, 6);
      st.debugCommit(DoodleKind.chord, [TapHit(0, 0, 4), TapHit(0, 2, 2), TapHit(0, 4, 2)]);
      final notes = st.debugChordNotes as List<List<Object?>>;
      // 2 는 머리가 아닌 8분 — 마디 코드 그대로, 4 는 반박 코드
      expect(row(notes, 0)[0], row(notes, 2)[0]);
      expect([row(notes, 0)[0], row(notes, 0)[4]], isNot([row(notes, 4)[0], row(notes, 4)[4]]));
    });

    testWidgets('대체코드를 쓴 마디는 판에 대체코드가 적히고 베이스도 그 뿌리를 따른다', (tester) async {
      final st = await open(tester, 'pop', mode: 'major');
      final base = (st.debugPlan.base as List<DoodleChordPick>).first;
      st.debugTapChord(0, dir: 0, sub: true);
      st.debugCommit(DoodleKind.chord, [for (final s in [0, 16, 32, 48]) TapHit(0, s, 8)]);
      final notes = st.debugChordNotes as List<List<Object?>>;
      expect(notes.first[0], isNot(base.degree));
      st.debugCommit(DoodleKind.bass, [for (final s in [0, 16, 32, 48]) TapHit(0, s, 4)]);
      expect([for (final n in st.debugBassNotes) n[0] as int],
          [for (final n in notes) n[0] as int]);
    });
  });
}

