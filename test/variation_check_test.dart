// Phase 4 — **변형이 실제로 무엇을 바꾸는가.** (개선 계획 6-1)
//   flutter test test/variation_check_test.dart
//
// 변형은 그럴듯하게 틀리기 쉬운 기능이다. 손잡이는 움직이는데 소리는 그대로여도
// "뭔가 달라진 것 같다"고 넘어간다 — 필·느낌에서 겪은 것과 같은 함정이다.
// 그래서 목록을 세어 본다.
//
// 지키는 것 일곱:
//  1. 끄면 **한 글자도 안 바뀐다** — 예전 곡이 그대로 들려야 한다
//  2. 번호가 오르면 **반드시 뭔가 달라진다**(못 하는 수는 건너뛴다)
//  3. **골격은 안 준다** — 킥·스네어·박수는 개수가 안 줄어든다
//  4. **화성은 안 잃는다** — 코드 타격 수와 근음은 그대로
//  5. 레가토는 **겹치지 않는다**
//  6. 같은 입력 → 같은 결과(난수를 안 쓴다)
//  7. 씬 루프가 **바퀴마다 다르다**, 곡의 두 번째 벌스가 첫 번째와 다르다
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/feel.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/theory.dart';
import 'package:music_doodle_engine/variation.dart';

const _twigLanes = {'hat', 'shaker', 'cowbell', 'ride'};

String _dsig(List<DrumHit> h) =>
    [for (final x in h) '${x.lane}${x.step}:${x.vel}'].join(',');
String _msig(List<MelodicHit> h) => [
  for (final x in h) '${x.step}/${x.len}/${x.vel}/${x.freq.toStringAsFixed(2)}',
].join(',');
String _csig(List<ChordHit> h) => [
  for (final x in h)
    '${x.step}/${x.len}/${x.vel}/${x.freqs.map((f) => f.toStringAsFixed(1)).join('+')}',
].join(',');

void main() {
  test('변형', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $what — $detail');
      if (!ok) fail++;
    }

    const key = MusicKey(root: 0, mode: 'major');

    // ── 1) 끄면 그대로 ──
    {
      var same = true;
      for (final d in kDrumPatterns) {
        final h = buildDrumPattern(d);
        if (_dsig(varyDrums(h, 0)) != _dsig(h)) same = false;
      }
      for (final n in kMelodyPatterns) {
        final h = buildRowsPattern(n, 'melody', key);
        if (_msig(varyMelodic(h, 'melody', 0)) != _msig(h)) same = false;
      }
      for (final c in kChordPatterns) {
        final h = buildChordPattern(c, key);
        if (_csig(varyChord(h, 0)) != _csig(h)) same = false;
      }
      check(
        '1) 0번은 원본 그대로',
        same,
        '드럼 ${kDrumPatterns.length} · 멜로디 ${kMelodyPatterns.length} · 코드 ${kChordPatterns.length}개 패턴',
      );
      check(
        '1-b) 말과 동작이 짝을 이룬다',
        const VarySpec(amount: 0).cycle == 1 &&
            const VarySpec(amount: 0.3).cycle == 2 &&
            const VarySpec(amount: 1).cycle == 4 &&
            Feel.varyWord(0) == '없음' &&
            Feel.varyWord(0.3) == '가끔' &&
            Feel.varyWord(1) == '자주',
        '없음=1 · 가끔=2 · 자주=4바퀴',
      );
    }

    // ── 2) 번호가 오르면 반드시 달라진다 ──
    {
      final dead = <String>[];
      for (final d in kDrumPatterns) {
        final h = buildDrumPattern(d);
        for (var v = 1; v <= 3; v++) {
          if (_dsig(varyDrums(h, v)) == _dsig(h)) dead.add('${d.name}#$v');
        }
      }
      check(
        '2) 드럼 — 번호마다 달라진다',
        dead.isEmpty,
        dead.isEmpty
            ? '${kDrumPatterns.length}개 × 3번 전부'
            : '안 바뀜: ${dead.take(4).join(', ')}',
      );

      final deadN = <String>[];
      for (final n in [...kMelodyPatterns, ...kBassPatterns]) {
        final type = kBassPatterns.contains(n) ? 'bass' : 'melody';
        final h = buildRowsPattern(n, type, key);
        if (h.isEmpty) continue;
        for (var v = 1; v <= 3; v++) {
          if (_msig(varyMelodic(h, type, v)) == _msig(h))
            deadN.add('${n.name}#$v');
        }
      }
      check(
        '2-b) 베이스·멜로디 — 번호마다 달라진다',
        deadN.isEmpty,
        deadN.isEmpty
            ? '${kMelodyPatterns.length + kBassPatterns.length}개 × 3번 전부'
            : '안 바뀜: ${deadN.take(4).join(', ')}',
      );

      final deadC = <String>[];
      for (final c in kChordPatterns) {
        final h = buildChordPattern(c, key);
        if (h.isEmpty) continue;
        for (var v = 1; v <= 3; v++) {
          if (_csig(varyChord(h, v)) == _csig(h)) deadC.add('${c.name}#$v');
        }
      }
      check(
        '2-c) 코드 — 번호마다 달라진다',
        deadC.isEmpty,
        deadC.isEmpty
            ? '${kChordPatterns.length}개 × 3번 전부'
            : '안 바뀜: ${deadC.take(4).join(', ')}',
      );
    }

    // ── 3) 골격은 안 준다 ──
    {
      final broke = <String>[];
      for (final d in kDrumPatterns) {
        final h = buildDrumPattern(d);
        int bones(List<DrumHit> x) => x
            .where(
              (e) => e.lane == 'kick' || e.lane == 'snare' || e.lane == 'clap',
            )
            .length;
        for (var v = 1; v <= 3; v++) {
          if (bones(varyDrums(h, v)) < bones(h)) broke.add('${d.name}#$v');
        }
      }
      check(
        '3) 킥·스네어·박수는 안 줄어든다',
        broke.isEmpty,
        broke.isEmpty ? '72개 패턴 전부' : broke.take(4).join(', '),
      );

      // 강박(4스텝 배수)의 음은 안 뺀다 — 골격이다
      final lost = <String>[];
      for (final n in kMelodyPatterns) {
        final h = buildRowsPattern(n, 'melody', key);
        final strong = h.where((e) => e.step % 2 == 0).length;
        for (var v = 1; v <= 3; v++) {
          final after = varyMelodic(
            h,
            'melody',
            v,
          ).where((e) => e.step % 2 == 0).length;
          if (after < strong) lost.add('${n.name}#$v');
        }
      }
      check(
        '3-b) 멜로디 강박은 안 준다',
        lost.isEmpty,
        lost.isEmpty
            ? '${kMelodyPatterns.length}개 패턴'
            : lost.take(4).join(', '),
      );
    }

    // ── 4) 화성은 안 잃는다 ──
    {
      final bad = <String>[];
      for (final c in kChordPatterns) {
        final h = buildChordPattern(c, key);
        for (var v = 1; v <= 3; v++) {
          final a = varyChord(h, v);
          if (a.length != h.length) {
            bad.add('${c.name}#$v 개수');
            continue;
          }
          for (var i = 0; i < h.length; i++) {
            if (h[i].step != a[i].step) bad.add('${c.name}#$v 자리');
            // 근음(제일 낮은 음)은 남아야 한다
            final lo = h[i].freqs.reduce((x, y) => x < y ? x : y);
            if (!a[i].freqs.any((f) => (f - lo).abs() < 1e-9)) {
              bad.add('${c.name}#$v 근음');
            }
          }
        }
      }
      check(
        '4) 코드 — 타격 수·자리·근음 그대로',
        bad.isEmpty,
        bad.isEmpty
            ? '${kChordPatterns.length}개 패턴 × 3번'
            : bad.take(4).join(', '),
      );
    }

    // ── 5) 레가토는 겹치지 않는다 ──
    {
      final over = <String>[];
      for (final n in [...kMelodyPatterns, ...kBassPatterns]) {
        final type = kBassPatterns.contains(n) ? 'bass' : 'melody';
        for (var v = 1; v <= 3; v++) {
          final a = List<MelodicHit>.of(
            varyMelodic(buildRowsPattern(n, type, key), type, v),
          )..sort((x, y) => x.step.compareTo(y.step));
          for (var i = 0; i + 1 < a.length; i++) {
            if (a[i].step == a[i + 1].step) continue; // 같은 자리(화음)는 겹쳐도 된다
            if (a[i].step + a[i].len > a[i + 1].step) over.add('${n.name}#$v');
          }
        }
      }
      check(
        '5) 늘여도 다음 음을 안 넘는다',
        over.isEmpty,
        over.isEmpty ? '전 패턴 통과' : over.take(4).join(', '),
      );

      // 옥타브 올리기 상한 — 통째로 올리는 수(`_octaveUp`)와 끝음만 올리는 수 둘 다
      var tooHigh = 0;
      for (final n in kMelodyPatterns) {
        for (var v = 1; v <= 3; v++) {
          for (final h in varyMelodic(
            buildRowsPattern(n, 'melody', key),
            'melody',
            v,
          )) {
            if (h.freq > 1600) tooHigh++;
          }
        }
      }
      check('5-b) 너무 높이 안 올린다', tooHigh == 0, '1600Hz 초과 $tooHigh개');
    }

    // ── 6) 결정적 ──
    {
      var same = true;
      for (final d in kDrumPatterns) {
        for (var v = 1; v <= 3; v++) {
          if (_dsig(varyDrums(buildDrumPattern(d), v)) !=
              _dsig(varyDrums(buildDrumPattern(d), v))) {
            same = false;
          }
        }
      }
      check('6) 같은 입력 → 같은 결과', same, '난수를 안 쓴다');
    }

    // ── 7) 씬·곡에서 실제로 들린다 ──
    {
      final tr = Transport();
      final on = Project.initial()..setFeel(const Feel(vary: 1.0, fill: 0));
      final off = Project.initial()..setFeel(const Feel(vary: 0, fill: 0));
      const cycle = 4;

      // 씬 — 늘린 루프를 바퀴별로 잘라 견준다
      List<String> turn(SceneBuild b, int i) {
        final lo = b.loopSec * i, hi = b.loopSec * (i + 1);
        final out = <String>[];
        for (final d in b.drums) {
          final t = (d[4] as num).toDouble();
          if (t >= lo && t < hi) {
            out.add('${d[1]}@${(t - lo).toStringAsFixed(4)}');
          }
        }
        for (final n in b.notes) {
          final t = (n[6] as num).toDouble();
          if (t >= lo && t < hi) {
            out.add(
              '${(n[1] as num).toStringAsFixed(1)}'
              '~${(n[2] as num).toStringAsFixed(3)}@${(t - lo).toStringAsFixed(4)}',
            );
          }
        }
        return out..sort();
      }

      final bOn = SceneSequencer.build(on, tr, reps: cycle);
      final bOff = SceneSequencer.build(off, tr, reps: cycle);
      final sameTurns = <int>[];
      for (var i = 1; i < cycle; i++) {
        if (turn(bOn, i).join('|') == turn(bOn, 0).join('|')) sameTurns.add(i);
      }
      check(
        '7) 씬 — 바퀴마다 다르다',
        sameTurns.isEmpty,
        sameTurns.isEmpty
            ? '${cycle - 1}바퀴 전부 다름'
            : '${sameTurns.join(',')}번 바퀴가 첫 바퀴와 같다',
      );

      var offSame = true;
      for (var i = 1; i < cycle; i++) {
        if (turn(bOff, i).join('|') != turn(bOff, 0).join('|')) offSame = false;
      }
      check('7-b) 끄면 바퀴가 전부 같다', offSame, '예전 소리 그대로');

      // 곡 — 같은 씬을 다시 쓰는 구간이 앞 구간과 다르다
      final song = SceneSequencer.buildSong(on, tr);
      final spans = SceneSequencer.songSpans(on, tr);
      final byScene = <int, List<int>>{};
      for (var i = 0; i < on.song.sections.length; i++) {
        byScene.putIfAbsent(on.song.sections[i].scene, () => []).add(i);
      }
      var repeated = 0, differed = 0;
      for (final e in byScene.entries) {
        if (e.value.length < 2) continue;
        List<String> at(int idx) {
          final (s, d) = spans[idx];
          final out = <String>[];
          for (final x in song.drums) {
            final t = (x[4] as num).toDouble();
            if (t >= s && t < s + d) {
              out.add('${x[1]}@${(t - s).toStringAsFixed(4)}');
            }
          }
          for (final x in song.notes) {
            final t = (x[6] as num).toDouble();
            if (t >= s && t < s + d) {
              out.add(
                '${(x[1] as num).toStringAsFixed(1)}@${(t - s).toStringAsFixed(4)}',
              );
            }
          }
          return out..sort();
        }

        final first = at(e.value[0]).join('|');
        for (var i = 1; i < e.value.length; i++) {
          repeated++;
          if (at(e.value[i]).join('|') != first) differed++;
        }
      }
      check(
        '7-c) 곡 — 다시 나오는 구간이 처음과 다르다',
        repeated > 0 && differed == repeated,
        '되풀이 구간 $repeated개 중 $differed개가 다름',
      );
    }

    // ── 7-d) **한 바퀴의 성격이 바뀌는가** ──
    //
    // 처음엔 조심스럽게 만들었다 — 약박 하나 걸러 하나, 고스트 하나, 킥 하나.
    // 사용자가 「모르겠다」고 했다. 4마디 안에서 타격 몇 개 바뀌는 건 안 걸린다.
    // 이제 잔가지 밀도를 통째로 바꾼다: 성기게 ↔ 촘촘하게.
    {
      final thin = <String>[], fat = <String>[];
      for (final d in kDrumPatterns) {
        final h = buildDrumPattern(d);
        final base = h.where((x) => _twigLanes.contains(x.lane)).length;
        if (base == 0) continue;
        final a = varyDrums(
          h,
          1,
        ).where((x) => _twigLanes.contains(x.lane)).length;
        final b = varyDrums(
          h,
          2,
        ).where((x) => _twigLanes.contains(x.lane)).length;
        // 어느 쪽이든 **눈에 띄게** 달라져야 한다(20% 넘게)
        if ((base - a).abs() * 5 < base && (base - b).abs() * 5 < base) {
          thin.add(d.name);
        }
        if (a > base && b < base) fat.add(d.name);
      }
      check(
        '7-d) 잔가지 밀도가 바퀴마다 크게 바뀐다',
        thin.isEmpty,
        thin.isEmpty
            ? '잔가지 있는 패턴 전부 20% 넘게'
            : '거의 안 바뀜: ${thin.take(4).join(', ')}',
      );
    }

    // ── 8) 저장 왕복 ──
    {
      const f = Feel(vary: 0.25);
      check(
        '8) 저장·되살리기',
        Feel.fromJson(f.toJson()).vary == 0.25,
        '${Feel.fromJson(f.toJson()).vary}',
      );
      check(
        '8-b) 없으면 켬(0.6)',
        Feel.fromJson({'e': 0.5}).vary == 0.6,
        '옛 파일도 변형이 붙는다',
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '변형 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
