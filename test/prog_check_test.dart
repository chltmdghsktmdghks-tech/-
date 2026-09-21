// **씬 코드 진행 — 코드를 바꾸면 베이스·멜로디가 따라오는가.**
//   flutter test test/prog_check_test.dart
//
// 이 기능이 있는 이유는 하나다: 코드만 바뀌고 베이스가 그대로면 **그 구간만
// 어긋난 채** 돈다. 그러니 시험도 거기를 본다 — 데이터가 아니라 **실제로 나가는
// 소리**(`SceneSequencer.build` 가 뽑는 주파수)까지 따라가서 확인한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/prog_ops.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/theory.dart';
import 'package:music_doodle_engine/ui/prog_sheet.dart';

/// 그 트랙이 [from]~[until] 스텝 사이에 내는 주파수들 (시간 순).
List<double> _freqs(
  Project p,
  Transport tr,
  String type,
  int fromStep,
  int untilStep,
) {
  final b = SceneSequencer.build(p, tr, reps: 1);
  final buses = SceneSequencer.busNames(p);
  final t = p.tracks.firstWhere((x) => x.type == type);
  final part = buses.indexOf(t.id);
  final stepSec = 60.0 / tr.bpm / 4;
  final out = <(double, double)>[];
  for (final n in b.notes) {
    if (n[7] != part) continue;
    final at = n[6] as double;
    final step = at / stepSec;
    if (step < fromStep - 0.01 || step >= untilStep - 0.01) continue;
    out.add((at, n[1] as double));
  }
  out.sort((a, b) => a.$1.compareTo(b.$1));
  return [for (final e in out) e.$2];
}

void main() {
  test('씬 코드 진행', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $what — $detail');
      if (!ok) fail++;
    }

    // 1) 가까운 쪽으로 움직인다 — 1도에서 7도는 여섯 칸 위가 아니라 한 칸 아래다.
    {
      final ok =
          progDelta(0, 6) == -1 &&
          progDelta(6, 0) == 1 &&
          progDelta(0, 3) == 3 &&
          progDelta(0, 4) == -3 &&
          progDelta(2, 2) == 0;
      check(
        '1) 가까운 쪽 도수 차',
        ok,
        '1→7 ${progDelta(0, 6)} · 1→4 ${progDelta(0, 3)} · 1→5 ${progDelta(0, 4)}',
      );
      var span = true;
      for (var a = 0; a < 7; a++) {
        for (var b = 0; b < 7; b++) {
          final d = progDelta(a, b);
          if (d < -3 || d > 3 || (a + d) % 7 != b) span = false;
        }
      }
      check('1-b) 49가지 모두 −3~+3', span, '');
    }

    // 2) 자리 읽기 — 빈틈 없이 이어지고 마지막이 패턴 끝에 닿아야 한다.
    //    (틈이 생기면 그 사이 베이스는 아무도 안 옮긴다)
    {
      final notes = <List<Object?>>[
        [0, 0, 7, 2],
        [3, 8, 7, 2],
        [3, 8, 7, 2], // 같은 칸에 겹쳐 찍힌 것 — 한 자리로 봐야 한다
        [4, 16, 7, 2],
      ];
      final slots = readProg(notes, 32);
      final gapless =
          slots.length == 3 &&
          slots[0].step == 0 &&
          slots[0].untilStep == 8 &&
          slots[1].untilStep == 16 &&
          slots[2].untilStep == 32;
      check(
        '2) 자리가 빈틈없이 이어진다',
        gapless,
        [for (final s in slots) '${s.label}:${s.degree}'].join(' '),
      );
    }

    // 3) 코드만 바뀌고 나머지는 그대로 — 타입(m7)과 층은 화성을 바꾼다고 버릴 뜻이 아니다.
    {
      final notes = <List<Object?>>[
        [0, 0, 7, 2, 'min7', -1],
        [3, 8, 7, 2],
      ];
      final slots = readProg(notes, 16);
      final out = setProg(notes, slots[0], 5);
      check(
        '3) 타입·층을 지킨다',
        out[0][0] == 5 &&
            out[0][4] == 'min7' &&
            out[0][5] == -1 &&
            out[1][0] == 3,
        '${out[0]}',
      );
      check('3-b) 원본은 안 건드린다', notes[0][0] == 0, '원본 ${notes[0][0]}');
    }

    // 4) 따라 옮기기 — 구간 안만, 그리고 줄 밖으로 안 나간다.
    {
      final notes = <List<Object?>>[
        [0, 0, 2, 2],
        [13, 4, 2, 2], // +3 하면 16 — 줄이 15개(0~14)뿐이다
        [7, 20, 2, 2], // 구간 밖
      ];
      final s = const ProgSlot(0, 0, 16);
      final out = followProg(notes, s, 3);
      check(
        '4) 구간 안만 옮긴다',
        out[0][0] == 3 && out[2][0] == 7,
        '${out[0][0]} · 밖 ${out[2][0]}',
      );
      check(
        '4-b) 줄 밖으로 안 나간다',
        out[1][0] == 9 && (out[1][0] as int) <= kMaxDegree,
        '13+3 → ${out[1][0]}',
      );
    }

    // ── 여기부터는 실제 곡에 걸어 본다 ──
    final p = Project.initial()..setGenre('lofi');
    final tr = Transport()..reps = 1;
    final key = MusicKey(root: tr.root, mode: tr.mode);

    final (slots, steps) = p.readSceneProg();
    check(
      '5) 코드 진행을 읽는다',
      slots.length >= 2 && steps > 0,
      '${slots.length}자리 · $steps칸',
    );

    if (slots.length >= 2) {
      // **베이스 음이 제일 많은 자리**를 고른다 — 한 음짜리 자리에서 재면
      // 「따라왔다」가 우연히도 맞을 수 있다.
      var slot = slots[1];
      var most = -1;
      for (final s in slots) {
        final n = _freqs(p, tr, 'bass', s.step, s.untilStep).length;
        if (n > most) {
          most = n;
          slot = s;
        }
      }
      final to = (slot.degree + 3) % 7;
      final delta = progDelta(slot.degree, to);

      // 바꾸기 **전** 그 구간의 베이스 소리
      final before = _freqs(p, tr, 'bass', slot.step, slot.untilStep);
      // 구간 **밖** — 앞뒤 둘 다 본다. 앞만 재면 첫 자리를 골랐을 때
      // 「0음이 그대로였다」로 통과한다(재는 시늉만 하는 시험이 된다).
      final outside = [
        ..._freqs(p, tr, 'bass', 0, slot.step),
        ..._freqs(p, tr, 'bass', slot.untilStep, steps),
      ];

      final undo = p.changeChord(slot, to);
      check(
        '6) 바꿨다',
        undo != null,
        '${slot.label} ${slot.degree + 1}도 → ${to + 1}도',
      );

      final after = _freqs(p, tr, 'bass', slot.step, slot.untilStep);
      final outside2 = [
        ..._freqs(p, tr, 'bass', 0, slot.step),
        ..._freqs(p, tr, 'bass', slot.untilStep, steps),
      ];

      // 6-b) 구간 **안**의 베이스가 도수 차만큼 옮겨졌는가 — 소리로 확인한다.
      {
        var ok = before.isNotEmpty && before.length == after.length;
        var detail = '음 ${before.length}개';
        if (ok) {
          for (var i = 0; i < before.length; i++) {
            // 옛 주파수 → 옛 도수 → +delta → 새 주파수, 이것과 같아야 한다
            var d = -1;
            for (var g = 0; g <= kMaxDegree; g++) {
              if ((degreeFreq(g, 'bass', key) - before[i]).abs() < 0.01) {
                d = g;
                break;
              }
            }
            var want = d + delta;
            while (want > kMaxDegree) {
              want -= 7;
            }
            while (want < 0) {
              want += 7;
            }
            final wf = degreeFreq(want, 'bass', key);
            if (d < 0 || (after[i] - wf).abs() > 0.01) {
              ok = false;
              detail =
                  '$i번째: ${before[i].toStringAsFixed(1)}Hz(도수 $d) → '
                  '${after[i].toStringAsFixed(1)}Hz, 바라던 것 ${wf.toStringAsFixed(1)}Hz';
              break;
            }
          }
        }
        check('6-b) 베이스가 소리까지 따라왔다', ok, detail);
      }

      // 6-c) 구간 **밖**은 그대로여야 한다 — 다 옮기면 조를 바꾼 것이지 코드를 바꾼 게 아니다.
      {
        final same =
            outside.length == outside2.length &&
            () {
              for (var i = 0; i < outside.length; i++) {
                if ((outside[i] - outside2[i]).abs() > 0.01) return false;
              }
              return true;
            }();
        check(
          '6-c) 구간 밖은 그대로',
          same && outside.isNotEmpty,
          '밖 ${outside.length}음',
        );
      }

      // 6-d) 코드 트랙 자신도 바뀌었나
      {
        final (now, _) = p.readSceneProg();
        final at = now.firstWhere(
          (s) => s.step == slot.step,
          orElse: () => const ProgSlot(-1, -1, -1),
        );
        check('6-d) 코드가 바뀌었다', at.degree == to, '${at.degree + 1}도');
      }

      // 7) 되돌리면 **소리까지** 원래대로
      {
        p.undoChangeChord(undo!);
        final back = _freqs(p, tr, 'bass', slot.step, slot.untilStep);
        final (now, _) = p.readSceneProg();
        final at = now.firstWhere(
          (s) => s.step == slot.step,
          orElse: () => const ProgSlot(-1, -1, -1),
        );
        var same = back.length == before.length && at.degree == slot.degree;
        if (same) {
          for (var i = 0; i < back.length; i++) {
            if ((back[i] - before[i]).abs() > 0.01) same = false;
          }
        }
        check('7) 되돌리면 소리까지 원래대로', same, '${back.length}음 · ${at.degree + 1}도');
      }
    }

    // 8) 짧은 패턴은 **펼친 뒤** 옮긴다 — 안 펼치면 한 마디를 두 코드가 나눠 써서
    //    한쪽을 맞추는 순간 다른 쪽이 어긋난다.
    {
      final q = Project.initial()..setGenre('lofi');
      final bass = q.tracks.firstWhere((t) => t.type == 'bass');
      final name = q.makeEditable(bass);
      // 1마디짜리 베이스를 만들어 끼운다
      q.userNote[name] = NotePatternDef(name, 1, 1, [
        [0, 0, 4, 2],
        [4, 8, 4, 2],
      ]);
      final (sl, _) = q.readSceneProg();
      // 첫 마디를 넘어선 자리라야 「펼치지 않으면 어긋난다」를 잴 수 있다.
      final later = sl.where((s) => s.step >= kStepsPerBar).toList();
      if (later.isNotEmpty) {
        final u = q.changeChord(later.first, (later.first.degree + 2) % 7);
        final def = q.userNote[name]!;
        check(
          '8) 짧은 패턴을 펼쳐서 옮긴다',
          u != null && def.bars > 1 && def.notes.length > 2,
          '${def.bars}마디 · ${def.notes.length}음',
        );
        // 첫 마디는 다른 코드 구간이니 그대로여야 한다
        final first = def.notes.where((n) => (n[1] as int) < kStepsPerBar);
        check(
          '8-b) 앞마디는 그대로',
          first.any((n) => n[0] == 0) && first.any((n) => n[0] == 4),
          '${[for (final n in first) n[0]]}',
        );
      } else {
        check('8) 짧은 패턴', false, '첫 마디 뒤에 코드가 없다 — 시험을 다시 짜야 한다');
      }
    }

    // 9) 미리 들려줄 때 **코드 트랙 음색**으로 낸다 — 패드 곡에서 피아노가 나면
    //    견주려고 눌러 보는 것인데 견줄 수가 없다.
    {
      final q = Project.initial()..setGenre('lofi');
      final chord = q.tracks.firstWhere((t) => t.type == 'chord');
      chord.voice = 'organ';
      check('9) 코드 트랙 음색으로 들려준다', chordVoiceOf(q) == 'organ', chordVoiceOf(q));
      final drumOnly = Project.initial();
      drumOnly.tracks.removeWhere((t) => t.type == 'chord');
      check(
        '9-b) 코드 트랙이 없어도 소리는 난다',
        chordVoiceOf(drumOnly).isNotEmpty,
        chordVoiceOf(drumOnly),
      );
    }

    // 10) **반음 줄 판은 반음으로 옮긴다.** 도수만큼 옮기면 3도 올리려다
    //     3반음만 올라가 화성이 어긋난다 — 소리는 나므로 오류로는 안 잡힌다.
    {
      // 단조에서 1도 → 4도는 도수 3, 반음 5다.
      check(
        '10) 도수↔반음이 다르다',
        progSemiDelta(0, 3, 'minor') == 5 && progDelta(0, 3) == 3,
        '도수 ${progDelta(0, 3)} · 반음 ${progSemiDelta(0, 3, 'minor')}',
      );
      final slot = const ProgSlot(0, 0, 16);
      final notes = <List<Object?>>[
        [0, 0, 2, 2],
      ];
      final asDeg = followProg(notes, slot, 3);
      final asSemi = followProg(
        notes,
        slot,
        3,
        chromatic: true,
        semiDelta: progSemiDelta(0, 3, 'minor'),
      );
      check(
        '10-b) 반음 판은 반음만큼',
        asDeg[0][0] == 3 && asSemi[0][0] == 5,
        '도수 판 ${asDeg[0][0]} · 반음 판 ${asSemi[0][0]}',
      );
      // 10-c) 반음 판은 **25줄**까지 쓴다 — 도수 판의 15로 되접으면 음이 튄다
      final high = followProg(
        [
          [22, 0, 2, 2],
        ],
        slot,
        3,
        chromatic: true,
        semiDelta: 5,
      );
      check('10-c) 반음 판은 25줄로 되접는다', high[0][0] == 15, '${high[0][0]}');
    }

    expect(fail, 0, reason: '$fail개 항목이 어긋났습니다');
  });
}
