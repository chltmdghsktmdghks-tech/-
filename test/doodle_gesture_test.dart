// Doodle Play 손짓이 **친 대로 적히는가.**
//
// 이 화면에서 제일 나기 쉬운 잘못은 "소리는 맞는데 판에는 딴 것이 적히는" 것이다.
// 귀로는 「좀 이상한데」로만 느껴지고 무엇이 틀렸는지는 안 보이므로 숫자로 잰다.
// (2026-09-21, 실제로 세 군데가 그런 상태였다 — 아래 세 묶음이 그 자리들이다)

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/prog_ops.dart';
import 'package:music_doodle_engine/tap_rec.dart';
import 'package:music_doodle_engine/theory.dart'
    show
        MusicKey,
        chordMidiOf,
        diatonicChords,
        invertChord,
        midiFreq,
        voicingDegreeLabels;

/// 2마디 32칸에 I → vi 가 걸린 진행.
List<ProgSlot> _prog() => readProg(const [
  [0, 0, 16, 2],
  [5, 16, 16, 2],
], 32);

void main() {
  group('베이스가 코드를 따라 걷는다', () {
    test('진행이 있으면 칸마다 음이 달라진다', () {
      final got = {
        for (var s = 0; s < 32; s++)
          tapDegree(
            prog: _prog(),
            progSteps: 32,
            step: s,
            type: 'bass',
            chord: false,
            chromatic: false,
            mode: 'minor',
          ),
      };
      expect(got.length, greaterThan(1),
          reason: '한 가지 음만 나오면 베이스 단계가 통째로 한 음짜리다');
    });

    test('진행이 비면 전부 한 음 — 그래서 코드를 먼저 쳐야 한다', () {
      // `DoodlePlayView` 가 코드 단계를 베이스보다 **앞에** 두는 이유.
      // 이 성질이 바뀌면 그 순서를 다시 생각해야 한다.
      final got = {
        for (var s = 0; s < 32; s++)
          tapDegree(
            prog: const [],
            progSteps: 0,
            step: s,
            type: 'bass',
            chord: false,
            chromatic: false,
            mode: 'minor',
          ),
      };
      expect(got, {0});
    });
  });

  group('베이스 옥타브', () {
    test('도수는 0~6이라 아래로 내릴 자리가 없다', () {
      // `_writeDegree` 가 베이스의 옥타브를 0/+1 로만 두는 근거.
      // 예전엔 −1 을 허용해서 서로 다른 음이 전부 0 하나로 뭉개졌다.
      for (var s = 0; s < 32; s++) {
        final d = tapDegree(
          prog: _prog(),
          progSteps: 32,
          step: s,
          type: 'bass',
          chord: false,
          chromatic: false,
          mode: 'minor',
        );
        expect(d, inInclusiveRange(0, 6));
        expect((d - 7).clamp(0, kMaxDegree), 0, reason: '내리면 전부 0으로 뭉갠다');
        expect((d + 7).clamp(0, kMaxDegree), d + 7, reason: '올리는 쪽은 멀쩡하다');
      }
    });
  });

  group('코드 줄의 첫 칸은 도수가 아니라 코드 번호', () {
    const key = MusicKey(root: 9, mode: 'minor'); // A minor

    List<double> chordAt(int deg, {String? type}) => buildChordPattern(
      NotePatternDef('p', 1, 1, [
        <Object?>[deg, 0, 8, 2, type],
      ]),
      key,
    ).expand((e) => e.freqs).toList();

    test('거기 3·5·7도를 더하면 다른 코드가 된다 — 그래서 안 더한다', () {
      final asPlayed = chordAt(0).map((f) => f.round()).toSet();
      final ifWeAdded = chordAt(6).map((f) => f.round()).toSet();
      expect(asPlayed, isNot(equals(ifWeAdded)),
          reason: '둘이 다르다는 것이 좌우를 코드 줄에 더하면 안 되는 이유다');
    });

    test('두께는 코드 종류 칸으로 적는다 — 뿌리는 그대로', () {
      final triad = chordAt(0);
      final seventh = chordAt(0, type: 'min7');
      expect(seventh.length, greaterThan(triad.length), reason: '음이 하나 는다');
      expect((seventh.first - triad.first).abs() < 0.01, isTrue,
          reason: '뿌리음은 안 바뀌어야 같은 자리의 같은 코드다');
    });
  });

  group('코드 자리바꿈(전위) — 위아래 쓸기가 옥타브가 아니라 보이싱', () {
    // 사용자 지적(2026-09-24): "옥타브를 왜 쓰니 보이싱을 바꾸라고
    // (135)(351)(531) 이렇게" — 위로 쓸 때마다 기본형→1전위→2전위로 돈다.
    const key = MusicKey(root: 0, mode: 'major'); // C장조 — 암산하기 쉽다
    final triad = diatonicChords(key)[0]; // I = C major

    test('invertChord 는 밑음을 한 옥타브씩 올려 자리를 돈다', () {
      final mid = chordMidiOf(triad); // [60, 64, 67] = C4 E4 G4
      expect(mid, [60, 64, 67]);
      expect(invertChord(mid, 0), [60, 64, 67], reason: '기본형(135)');
      expect(invertChord(mid, 1), [64, 67, 72], reason: '1전위(351) — 뿌리가 위로');
      expect(invertChord(mid, 2), [67, 72, 76], reason: '2전위(531) — 3음까지 위로');
      // 3(=음 개수)바퀴 돌면 나머지가 0이라 기본형 그대로다(늘 %길이).
      expect(invertChord(mid, 3), [60, 64, 67]);
    });

    test('배지 숫자가 (135)(351)(531) 순서 그대로다', () {
      expect(voicingDegreeLabels(3, 0), [1, 3, 5]);
      expect(voicingDegreeLabels(3, 1), [3, 5, 1]);
      expect(voicingDegreeLabels(3, 2), [5, 1, 3]);
    });

    test('연주(친 소리) 계산과 재생(buildChordPattern) 계산이 같은 음을 낸다', () {
      // `_chordDown`(연주)이 하는 일을 그대로 흉내 낸다: chordMidiOf → invertChord.
      // `buildChordPattern`(재생)은 n[6]에 적힌 전위를 보고 똑같이 계산해야 한다
      // — 그래야 「사용하기」 뒤에도 방금 들은 소리가 그대로 재생된다.
      for (var v = 0; v < 3; v++) {
        final playedMidi = invertChord(chordMidiOf(triad), v);
        final playedFreqs = [for (final m in playedMidi) midiFreq(m)];

        final recorded = buildChordPattern(
          NotePatternDef('p', 1, 1, [
            <Object?>[0, 0, 8, 2, null, null, v],
          ]),
          key,
        );

        expect(recorded.single.freqs.length, playedFreqs.length,
            reason: '전위 $v: 음 개수부터 같아야 한다');
        for (var i = 0; i < playedFreqs.length; i++) {
          expect(recorded.single.freqs[i], closeTo(playedFreqs[i], 0.01),
              reason: '전위 $v: ${i + 1}번째 음이 친 소리와 달라졌다');
        }
      }
    });

    test('전위를 안 적은 옛 음(n[6] 없음)은 그대로 voiceLead 자동 전위를 쓴다', () {
      // 호환 확인 — 라이브러리 패턴·편집기로 새로 찍은 음처럼 6칸짜리도 안
      // 되는 짧은 행이 예전과 똑같이 동작해야 기존 곡·기존 시험이 안 깨진다.
      final withoutVoicing = buildChordPattern(
        NotePatternDef('p', 1, 1, const [
          <Object?>[0, 0, 8, 2],
        ]),
        key,
      );
      expect(withoutVoicing.single.freqs.length, 3);
    });
  });

  group('미끄러뜨리기 · 스타카토가 판에 남는다', () {
    test('다섯째 칸의 1이 앞 음에서 미끄러지게 만든다', () {
      // `_decorate` 가 글라이드 칸에 적는 값이 재생에서 실제로 읽히는가.
      final plain = buildRowsPattern(
        NotePatternDef('p', 1, 1, const [
          [0, 0, 2, 2],
          [4, 4, 2, 2],
        ]),
        'bass',
        const MusicKey(root: 9, mode: 'minor'),
      );
      final glided = buildRowsPattern(
        NotePatternDef('p', 1, 1, const [
          [0, 0, 2, 2],
          [4, 4, 2, 2, 1],
        ]),
        'bass',
        const MusicKey(root: 9, mode: 'minor'),
      );
      expect(plain[1].glideFromFreq, 0.0, reason: '안 적으면 미끄러지지 않는다');
      expect(glided[1].glideFromFreq, greaterThan(0.0),
          reason: '적으면 앞 음에서 미끄러진다');
      expect(glided[1].glideFromFreq, closeTo(plain[0].freq, 0.01),
          reason: '출발점은 바로 앞 음이어야 한다');
    });

    test('길이 1칸이 실제로 8분보다 짧다', () {
      // 「톡 치면 짧게」가 없으면 `lenOf` 의 바닥값 때문에 전부 8분(2칸)이 된다.
      final r = TapRecorder(steps: 32, loopBars: 2, loopSec: 4);
      expect(r.lenOf(0.0, 0.0001), 2, reason: '아무리 톡 쳐도 바닥값은 2칸');
      final short = buildRowsPattern(
        NotePatternDef('p', 1, 1, const [
          [0, 0, 1, 2],
        ]),
        'bass',
        const MusicKey(root: 9, mode: 'minor'),
      );
      expect(short.single.len, 1, reason: '1칸으로 적으면 1칸으로 난다');
    });
  });

  group('하이햇만 16분 격자', () {
    test('8분 격자는 붙은 두 방을 한 칸으로 뭉갠다', () {
      // 하이햇 단계만 `TapSnap.sixteenth` 로 올리는 근거.
      final eighth = TapRecorder(steps: 32, loopBars: 2, loopSec: 4);
      final sixteenth = TapRecorder(
        steps: 32,
        loopBars: 2,
        loopSec: 4,
        snap: TapSnap.sixteenth,
      );
      // 한 칸(1/32 바퀴) 차이로 두 번 친다.
      const a = 3 / 32, b = 4 / 32;
      expect(eighth.stepOf(a), eighth.stepOf(b),
          reason: '8분에서는 두 방이 같은 칸 — 뒤엣것이 앞엣것을 덮어쓴다');
      expect(sixteenth.stepOf(a), isNot(sixteenth.stepOf(b)),
          reason: '16분에서는 따로 남는다');
    });
  });
}
