// **멜로디가 그 아래 코드와 맞는가.** (작곡 품질)
//   flutter test test/melody_clash_test.dart
//
// 여태 화성 검사는 코드↔코드, 코드↔베이스만 봤다(`harmony_clash_test`).
// 정작 제일 크게 들리는 줄 — **멜로디** — 은 아무도 안 봤다.
// 그래서 이런 것들이 그대로 있었다:
//   · 조의 5음(G)을 iv 코드(F–Ab–C–Eb) 위에서 길게 끌기 → Ab 와 반음
//   · 조의 b3음(Eb)을 VII 도미넌트(Bb–D–F–Ab) 위에서 길게 끌기 → D 와 반음
// 멜로디를 **조** 기준으로만 쓰고 그 순간의 **코드**를 안 봤을 때 나오는 실수다.
// 소리로는 「탁하다·뭔가 틀렸다」로만 들린다.
//
// ── 음이름이 아니라 **실제 간격**을 본다 ──
// 처음엔 12음 자리(피치 클래스)로만 봤다. 그러면 G4↔Ab3 도 '반음'으로 잡힌다 —
// 그건 **장7도**라 하나도 안 부딪친다. 실제로 갈리는 것은 같은 자리에서 부딪칠 때다:
//   **단2도(1반음)** — 같은 자리에서 두 음이 스치며 우는 그것.
// 단9도(13반음)는 안 잡는다. 한 옥타브 벌어져 울리면 거칠지 않고 **색**이다
// (재즈·R&B 가 일부러 쓴다).
//
// ── 왜 주파수로 보는가 ──
// 처음 판은 **패턴 데이터의 도수**를 봤다. 그러면 변형(`varyMelodic`/`varyChord`)이
// 지나간 뒤는 못 본다 — `_legato` 는 음을 늘여서 **다음 코드까지 끌고 갈 수 있고**,
// `_openChord` 는 코드의 맨 윗음을 빼서 **멀쩡하던 음을 어긋나게 만들 수 있다.**
// 그래서 실제로 예약되는 것과 같은 것을 본다: `buildRowsPattern`/`buildChordPattern`
// 을 거친 **주파수**를, **변형 네 바퀴 전부**에 대해.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/theory.dart';
import 'package:music_doodle_engine/variation.dart';

/// 끝음이 코드톤이 아니어도 되는 패턴 — **일부러 그런 것**만 적는다.
///
/// 록 리프는 파워코드가 움직여도 펜타토닉 자리를 지킨다(그게 록 리프다).
/// 엠비언트 하프는 코드 위에 흩뿌리는 배음이라 해결하지 않는 게 맞다.
const _endFree = {'Rock Riff V', 'Rock Riff C', 'Amb Harp A'};

int _midi(double freq) => (69 + 12 * (math.log(freq / 440) / math.ln2)).round();

void main() {
  test('멜로디 화성 충돌', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final held = <String>[]; // 길게 끄는 반음 충돌
    final unresolved = <String>[]; // 프레이즈 끝음이 붕 뜬 것
    var notes = 0, lines = 0;

    for (final g in kGenres) {
      final proj = Project.initial()..setGenre(g.key);
      final key = MusicKey(root: 0, mode: g.mode);
      for (final sc in proj.scenes) {
        // 코드 트랙 전부 — 위층 줄도 멜로디와 같은 자리에 올 수 있다.
        final chordDefs = <NotePatternDef>[];
        for (final t in proj.tracks.where((t) => t.type == 'chord')) {
          final clip = sc.clips[t.id];
          if (clip == null) continue;
          final d = proj.findNote('chord', clip);
          if (d == null || d.notes.isEmpty) continue;
          chordDefs.add(d);
        }
        if (chordDefs.isEmpty) continue;

        for (final t in proj.tracks.where((t) => t.type == 'melody')) {
          final clip = sc.clips[t.id];
          if (clip == null) continue;
          final md = proj.findNote('melody', clip);
          if (md == null || md.notes.isEmpty) continue;
          lines++;

          // **변형 네 바퀴 전부** — 원본(0)과 변형 1·2·3
          for (var v = 0; v < 4; v++) {
            final mel = varyMelodic(
              buildRowsPattern(md, 'melody', key),
              'melody',
              v,
            );
            final chs = [
              for (final d in chordDefs)
                varyChord(buildChordPattern(d, key), v),
            ];

            /// 그 순간 울리고 있는 **화성 전체**의 음들 — MIDI 번호 그대로(자리 포함).
            /// 어느 한 줄이라도 그 음을 코드톤으로 갖고 있으면 화성 안에 있는 것이다 —
            /// 패드가 min9 를 치는데 스트링이 min7 이면 9음은 패드의 코드톤이지 실수가 아니다.
            Set<int> soundingAt(int step) {
              final out = <int>{};
              for (final ch in chs) {
                ChordHit? best;
                for (final c in ch) {
                  if (c.step <= step) {
                    best = c;
                  } else {
                    break;
                  }
                }
                best ??= ch.isEmpty ? null : ch.first;
                if (best != null) {
                  out.addAll(best.freqs.map(_midi));
                }
              }
              return out;
            }

            for (final n in mel) {
              if (v == 0) notes++;
              // **3칸(점8분) 넘게 끄는 음만** 본다. 16분·8분으로 지나가는 반음은
              // 어느 장르에서나 정상이다 — 그것까지 막으면 멜로디가 밋밋해진다.
              if (n.len < 3) continue;
              final m = _midi(n.freq);
              final tones = soundingAt(n.step);
              if (tones.isEmpty) continue;
              // 코드톤이면 아무 문제 없다(그 음이 곧 화성이다)
              if (tones.any((c) => (c - m).abs() % 12 == 0)) continue;
              for (final c in tones) {
                if ((c - m).abs() == 1) {
                  held.add(
                    '${g.key}/${sc.name} $clip '
                    '${v == 0 ? '원본' : '변형$v'} ${n.step ~/ 16 + 1}마디',
                  );
                  break;
                }
              }
            }

            // 끝음 해결은 **원본**만 본다 — 변형은 일부러 끝을 들어 올린다
            // (`_liftLast`, 한 옥타브라 음이름은 그대로다).
            if (v != 0 || _endFree.contains(clip)) continue;
            final bars = md.bars;
            for (var bar = 3; bar < bars; bar += 4) {
              MelodicHit? last;
              for (final m in mel) {
                if (m.step ~/ kStepsPerBar <= bar) last = m;
              }
              if (last == null) continue;
              final lm = _midi(last.freq);
              if (!soundingAt(last.step).any((c) => (c - lm).abs() % 12 == 0)) {
                unresolved.add('${g.key}/${sc.name} $clip ${bar + 1}마디');
              }
            }
          }
        }
      }
    }

    check(
      '1) 길게 끄는 음이 코드와 단2도로 안 부딪친다 (변형 4바퀴 전부)',
      held.isEmpty,
      held.isEmpty ? '$lines개 줄 · 음 $notes개 × 4바퀴' : held.take(5).join(' · '),
    );
    check(
      '2) 프레이즈 끝음이 코드톤으로 내려앉는다',
      unresolved.isEmpty,
      unresolved.isEmpty
          ? '$lines개 줄 (일부러 안 푸는 것 ${_endFree.length}개 제외)'
          : unresolved.take(5).join(' · '),
    );

    // ignore: avoid_print
    print(fail == 0 ? '멜로디 화성 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
