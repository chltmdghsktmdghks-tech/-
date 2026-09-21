// **연주해서 곡을 만든다** — 씬을 눌러 넘긴 순서가 구간표가 되는가.
//   flutter test test/arrange_rec_test.dart
//
// 이 기능의 전부는 「몇 판이나 머물렀나」를 초에서 판 수로 바꾸는 셈이다.
// 그 셈이 틀리면 곡 길이가 통째로 어긋난다 — 그래서 화면에서 떼어 놓고 여기서 잰다.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/arrange_rec.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';

void main() {
  test('연주해서 곡 만들기', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    // 씬 한 판이 10초라고 치고 잰다(실제 값은 밖에서 준다)
    double ten(int _) => 10.0;

    // ── 1) 넘긴 순서 그대로 ──
    {
      final r = ArrangeRecorder()
        ..mark(0, 0)
        ..mark(1, 10)
        ..mark(2, 30);
      final out = sectionsFrom(r, 40, loopSecOf: ten);
      check(
        '1) 넘긴 순서 · 머문 만큼',
        out.length == 3 &&
            out[0].scene == 0 &&
            out[0].reps == 1 &&
            out[1].scene == 1 &&
            out[1].reps == 2 &&
            out[2].scene == 2 &&
            out[2].reps == 1,
        out.map((s) => '${s.scene}번×${s.reps}판').join(' → '),
      );
    }

    // ── 2) **같은 씬을 다시 눌러도 구간이 안 늘어난다** ──
    //     칩을 두 번 눌렀다고 구간이 둘이 되면 곡이 이상해진다.
    {
      final r = ArrangeRecorder()
        ..mark(0, 0)
        ..mark(0, 3)
        ..mark(0, 6)
        ..mark(1, 10);
      final out = sectionsFrom(r, 20, loopSecOf: ten);
      check(
        '2) 같은 씬을 다시 눌러도 하나',
        r.count == 2 && out.length == 2 && out[0].reps == 1,
        '기록 ${r.count}개 → 구간 ${out.length}개',
      );
    }

    // ── 3) **스치듯 지난 구간이 사라지지 않는다** ──
    //     내림하면 0판이 되어 통째로 없어진다. 눌렀다는 것 자체가 「여기 한 판」이다.
    {
      final r = ArrangeRecorder()
        ..mark(0, 0)
        ..mark(1, 1.2) // 1.2초만 머물렀다 — 한 판의 12%
        ..mark(2, 2.0);
      final out = sectionsFrom(r, 12, loopSecOf: ten);
      check(
        '3) 스친 구간도 한 판은 남는다',
        out.length == 3 && out.every((s) => s.reps >= 1),
        out.map((s) => '${s.reps}판').join(' · '),
      );
    }

    // ── 4) **반올림한다** — 사람이 손으로 넘기면 판 경계에 딱 안 맞는다 ──
    {
      final r = ArrangeRecorder()
        ..mark(0, 0) // 18초 머묾 = 1.8판 → 2판
        ..mark(1, 18); // 11초 머묾 = 1.1판 → 1판
      final out = sectionsFrom(r, 29, loopSecOf: ten);
      check(
        '4) 판 수는 반올림',
        out[0].reps == 2 && out[1].reps == 1,
        '18초 → ${out[0].reps}판 · 11초 → ${out[1].reps}판',
      );
    }

    // ── 5) 안 죽는다 — 빈 기록 · 0초 판 · 아주 긴 구간 ──
    {
      final empty = sectionsFrom(ArrangeRecorder(), 10, loopSecOf: ten);
      final zero = sectionsFrom(
        ArrangeRecorder()..mark(0, 0),
        10,
        loopSecOf: (_) => 0,
      );
      final huge = sectionsFrom(
        ArrangeRecorder()..mark(0, 0),
        100000,
        loopSecOf: ten,
      );
      check(
        '5) 빈 기록·0초 판·아주 긴 구간에도 안 죽는다',
        empty.isEmpty && zero.length == 1 && huge.first.reps == 32,
        '빈 ${empty.length}개 · 0초판 ${zero.first.reps}판 · 아주 김 ${huge.first.reps}판(상한 32)',
      );
    }

    // ── 6) **실제 씬 길이로 만든 곡이 그 길이로 흐른다** ──
    //     여기가 어긋나면 「내가 연주한 대로가 아닌데」가 된다.
    {
      final p = Project.initial();
      final tr = Transport();
      // 씬 한 판 길이를 구간표로 재는 대신, 씬 하나만 담은 구간표의 길이를 쓴다
      double oneScene(int i) {
        final keep = [...p.song.sections];
        p.song.restore([Section(i, reps: 1)]);
        final s = SceneSequencer.songSpans(p, tr);
        final sec = s.isEmpty ? 0.0 : s.first.$2;
        p.song.restore(keep);
        return sec;
      }

      final r = ArrangeRecorder()
        ..mark(0, 0)
        ..mark(2, oneScene(0) * 2); // 0번 씬을 두 판 머물렀다
      final made = sectionsFrom(
        r,
        oneScene(0) * 2 + oneScene(2),
        loopSecOf: oneScene,
      );
      p.song.restore(made);
      final total = SceneSequencer.songSeconds(p, tr);
      final want = oneScene(0) * 2 + oneScene(2);
      check(
        '6) 만든 곡이 연주한 길이로 흐른다',
        made.length == 2 &&
            made[0].reps == 2 &&
            made[1].reps == 1 &&
            (total - want).abs() < 0.6,
        '${made.map((s) => '${s.scene}번×${s.reps}판').join(' → ')} · '
            '${total.toStringAsFixed(1)}초 (연주 ${want.toStringAsFixed(1)}초)',
      );
    }

    // ── 7) **곡 길이를 목표에 맞춘다** ──
    //
    // 마디가 아니라 **초**로 잰다 — 78BPM 로파이와 128BPM 하우스는 같은 마디
    // 수라도 길이가 배로 다르다. 인트로·아웃트로는 안 건드린다(자리를 지켜야 한다).
    {
      // 0=인트로 · 1,2,3=가운데 · 4=아웃트로. 한 판 10초.
      List<Section> mk() => [
        Section(0, reps: 1),
        Section(1, reps: 4),
        Section(2, reps: 4),
        Section(3, reps: 4),
        Section(4, reps: 1),
      ];
      bool end(int i) => i == 0 || i == 4;
      double sec(List<Section> ss) {
        var t = 0.0;
        for (final x in ss) {
          t += 10.0 * x.reps;
        }
        return t;
      }

      final long = fitToLength(mk(), 60, secOf: ten, isEnd: end);
      final short = fitToLength(mk(), 200, secOf: ten, isEnd: end);
      final same = fitToLength(mk(), sec(mk()), secOf: ten, isEnd: end);

      check(
        '7) 목표 길이에 가까워진다',
        (sec(long) - 60).abs() <= 10 &&
            (sec(short) - 200).abs() <= 10 &&
            sec(same) == sec(mk()),
        '140초 → 짧게 ${sec(long).round()}초 · 길게 ${sec(short).round()}초 · '
            '그대로 ${sec(same).round()}초',
      );

      check(
        '7-b) 인트로·아웃트로는 안 건드린다',
        long.first.reps == 1 &&
            long.last.reps == 1 &&
            short.first.reps == 1 &&
            short.last.reps == 1,
        '짧게 ${long.map((s) => s.reps).join(',')} · '
            '길게 ${short.map((s) => s.reps).join(',')}',
      );

      check(
        '7-c) 구간을 없애거나 지어내지 않는다',
        long.length == 5 && short.length == 5 && long.every((s) => s.reps >= 1),
        '${long.length}개 · ${short.length}개',
      );

      // 원본을 안 건드린다 — 되돌릴 수 있어야 한다
      final src = mk();
      fitToLength(src, 60, secOf: ten, isEnd: end);
      check('7-d) 원본을 안 건드린다', src[1].reps == 4, '원본 ${src[1].reps}판');
    }

    // ignore: avoid_print
    print(fail == 0 ? '연주해서 곡 만들기 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
