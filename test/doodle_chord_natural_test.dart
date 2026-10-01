// 코드 진행이 「자연스러운가」 — 난수 없이 모든 (마디, 방향, salt) 조합을 훑어 규칙으로 잰다.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/doodle_chords.dart';

void main() {
  test('떠 있는 도미넌트 7 은 가운데 착지여도 풀린다(어떤 salt 든)', () {
    for (final mode in ['major', 'minor']) {
      for (var salt = 0; salt < 60; salt++) {
        final plan = DoodleChordPlan(
          [for (var i = 0; i < 4; i++) const DoodleChordPick(0)],
          mode: mode,
          spb: 16,
          beatSteps: 4,
          genre: 'jazz',
          rng: _FixedRng(salt),
        );
        // 0마디 착지 = 긴장 → 1마디가 딴 코드(V7·세컨더리 등)
        plan.recordTap(0, dir: -1, sub: false);
        final b1 = plan.pickAt(1);
        // 1마디 착지 = 가운데(0)
        plan.recordTap(1, dir: 0, sub: false);
        final b2 = plan.pickAt(2);
        if (b1.type == 'dom7') {
          expect(b2, doodleResolveDom(b1),
              reason: '$mode salt=$salt: $b1 뒤에 $b2 (풀려야 함)');
        }
      }
    }
  });

  test('미리보기 = 확정 (풀림 규칙 포함)', () {
    for (var salt = 0; salt < 40; salt++) {
      final plan = DoodleChordPlan(
        const [
          DoodleChordPick(0),
          DoodleChordPick(0),
          DoodleChordPick(3),
          DoodleChordPick(0),
        ],
        mode: 'major',
        spb: 16,
        beatSteps: 4,
        genre: 'jazz',
        rng: _FixedRng(salt),
      );
      plan.recordTap(0, dir: -1, sub: false);
      final pv = plan.previewNext(0);
      expect(plan.pickAt(1), pv);
      plan.recordTap(1, dir: 0, sub: false);
      final pv2 = plan.previewNext(1);
      expect(plan.pickAt(2), pv2);
    }
  });

  test('ii 의 해결은 V (ii-V 가 가장 자연스럽다)', () {
    final seen = <DoodleChordPick>{
      for (var s = 0; s < 12; s++)
        doodleStepChord(const DoodleChordPick(1), 1, mode: 'major', salt: s),
    };
    expect(seen, containsAll([const DoodleChordPick(4)]));
    expect(seen.contains(const DoodleChordPick(3)), isFalse);
  });

  test('재즈 계열 기본 진행: 토닉으로 가는 V 는 V7', () {
    for (var i = 0; i < 40; i++) {
      for (final mode in ['major', 'minor']) {
        final p = doodleBasePlan(
            mode: mode, bars: 4, genre: 'jazz', rng: math.Random(i));
        for (var b = 0; b < 4; b++) {
          if (p[b].degree == 4 && p[(b + 1) % 4].degree == 0) {
            expect(p[b].type, 'dom7', reason: '$mode $p');
          }
        }
      }
    }
  });

  test('장르 없으면 세컨더리 도미넌트·5도권 사슬이 안 나온다', () {
    for (var s = 0; s < 30; s++) {
      for (var d = 0; d < 7; d++) {
        final c = doodleStepChord(DoodleChordPick(d), -1, mode: 'major', salt: s);
        expect(c.type == null || c.degree == 4, isTrue, reason: '$d → $c');
      }
    }
  });
}

class _FixedRng implements math.Random {
  final int v;
  _FixedRng(this.v);
  @override
  int nextInt(int max) => v % max;
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
}
