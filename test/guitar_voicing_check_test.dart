// 기타 코드 보이싱 확인 — 실제 바레 코드 손 모양(오픈 E 모양을 프렛만 옮김)인지,
// 그리고 기타/나일론이 아닌 음색은 여태처럼 촘촘한 코드톤 배치를 쓰는지.
//   flutter test test/guitar_voicing_check_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/theory.dart';

void main() {
  test('기타 바레 코드', () async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    // 1) E장조 — 개방현 자리(프렛 0), 오픈 E 모양 그대로.
    final e = guitarChordMidi(const ChordSpec(root: 4, type: 'maj'));
    check(
      '1) E장조 = 오픈 E 모양(40,47,52,56,59,64)',
      e.toString() == [40, 47, 52, 56, 59, 64].toString(),
      '$e',
    );

    // 2) G장조 — E 에서 3프렛 위(오픈 G 모양이 아니라 **바레**로 짚은 자리).
    final g = guitarChordMidi(const ChordSpec(root: 7, type: 'maj'));
    check(
      '2) G장조 = E 모양을 3칸 올림',
      g.toString() == [43, 50, 55, 59, 62, 67].toString(),
      '$g',
    );

    // 3) Am — 마이너 모양, A(9)는 E 보다 5칸 위.
    final am = guitarChordMidi(const ChordSpec(root: 9, type: 'min'));
    check(
      '3) Am = 마이너 모양(프렛 5)',
      am.toString() == [45, 52, 57, 60, 64, 69].toString(),
      '$am',
    );

    // 4) 파워코드 — 세 음뿐(근음·5도·옥타브), 여느 코드보다 훨씬 성기다.
    final five = guitarChordMidi(const ChordSpec(root: 0, type: 'five'));
    check('4) 파워코드 = 3음(근음·5도·옥타브)', five.length == 3, '$five');

    // 5) 목록에 없는 종류(예: 9화음)는 기존 길로 되돌아간다(자리바꿈 O).
    final maj9 = guitarChordMidi(const ChordSpec(root: 0, type: 'maj9'));
    final maj9Fallback = chordMidiOf(const ChordSpec(root: 0, type: 'maj9'));
    check(
      '5) 없는 종류는 기존 길로',
      maj9.toString() == maj9Fallback.toString(),
      '$maj9',
    );

    // 6) 슬래시 코드(베이스 지정)는 기타여도 자리를 안 바꾼다(기존 길 그대로).
    final slash = guitarChordMidi(
      const ChordSpec(root: 0, type: 'maj', bass: 4),
    );
    final slashFallback = chordMidiOf(
      const ChordSpec(root: 0, type: 'maj', bass: 4),
    );
    check(
      '6) 슬래시 코드는 기존 길로',
      slash.toString() == slashFallback.toString(),
      '$slash',
    );

    // 7) `buildChordPattern` 에 voice: 'guitar' 를 주면 실제로 이 모양이 나온다,
    // voice 를 안 주거나 'piano' 등을 주면 여태처럼 촘촘한 배치(옥타브 띠 안).
    final def = NotePatternDef('시험', 4, 4, [
      [0, 0, 16, 2],
    ]);
    final key = const MusicKey(root: 0, mode: 'major'); // C장조 — i=C장조 코드
    final asGuitar = buildChordPattern(def, key, voice: 'guitar');
    check(
      '7) 기타 음색이면 바레 모양(6음, E 로부터 8칸 = C)',
      asGuitar.first.freqs.length == 6,
      '${asGuitar.first.freqs.length}개',
    );
    final asPiano = buildChordPattern(def, key, voice: 'piano');
    check(
      '8) 기타가 아니면 여태처럼 촘촘한 배치(3음)',
      asPiano.first.freqs.length == 3,
      '${asPiano.first.freqs.length}개',
    );

    // ignore: avoid_print
    print(fail == 0 ? '기타 보이싱 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
