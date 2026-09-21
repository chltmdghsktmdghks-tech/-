// 5단계 36/N — 패턴 이름 한국어로 읽어 주기.
//   flutter test test/pattern_names_test.dart
//
// 화면 전체가 한국어인데 패턴 이름만 「Lofi Walk C」 처럼 영어였다.
// 표를 하나 만들어 **보여 줄 때만** 옮긴다(이름 자체는 키라서 못 바꾼다).
//
// 여기서 보는 것은 딱 하나: **영어가 남아 있는 이름이 몇 개인가.**
// 표에 낱말을 빠뜨리면 화면에 「로파이 Walk 코러스용」 같은 반쪽짜리가 나온다.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/pattern_names.dart';
import 'package:music_doodle_engine/patterns.dart';

/// 라틴 글자가 남아 있으면 못 옮긴 낱말이 있는 것이다.
/// 다만 **코드 이름은 그대로 두는 게 맞다** — `Cm-Ab-Eb-Bb` 는 영어가 아니라
/// 악보 기호다. 옮기면 오히려 못 읽는다. 그래서 코드 꼴 낱말은 빼고 본다.
final _latin = RegExp(r'[A-Za-z]');
final _chord = RegExp(r'^[A-G][#b]?(m|maj|min|dim|aug)?$');

/// 코드 기호를 걷어낸 뒤 남는 라틴 글자만 본다.
bool _hasEnglish(String label) {
  for (final w in label.split(RegExp(r'[\s·-]+'))) {
    if (w.isEmpty || _chord.hasMatch(w)) continue;
    if (_latin.hasMatch(w)) return true;
  }
  return false;
}

void main() {
  test('패턴 이름', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final all = <String>{
      for (final d in kDrumPatterns) d.name,
      for (final n in kBassPatterns) n.name,
      for (final n in kChordPatterns) n.name,
      for (final n in kMelodyPatterns) n.name,
    };
    check('0) 패턴을 다 모았다', all.length > 100, '${all.length}개');

    // 1) 영어가 남은 이름 — 하나도 없어야 한다
    final left = [
      for (final n in all)
        if (_hasEnglish(patternLabel(n))) '$n → ${patternLabel(n)}',
    ];
    check(
      '1) 영어가 안 남는다',
      left.isEmpty,
      left.isEmpty
          ? '${all.length}개 전부'
          : '${left.length}개: ${left.take(8).join(' / ')}',
    );

    // 2) 옮긴 이름이 서로 안 겹친다 — 목록에 같은 이름이 둘이면 못 고른다
    final byLabel = <String, List<String>>{};
    for (final n in all) {
      (byLabel[patternLabel(n)] ??= []).add(n);
    }
    final dup = [
      for (final e in byLabel.entries)
        if (e.value.length > 1) '${e.key}(${e.value.join(',')})',
    ];
    check(
      '2) 이름이 안 겹친다',
      dup.isEmpty,
      dup.isEmpty ? '${byLabel.length}개 전부 다름' : dup.take(5).join(' / '),
    );

    // 3) 몇 개 눈으로 — 사람이 읽어서 말이 되는지
    const want = {
      'Lofi Walk C': '로파이 워킹 · 코러스용',
      'House Off V': '하우스 오프비트 · 벌스용',
      'Jazz Sax H': '재즈 색소폰 · 헤드용',
      'Amb Pad A': '엠비언트 패드 A',
      'Lofi Chorus': '로파이 코러스',
    };
    final wrong = [
      for (final e in want.entries)
        if (patternLabel(e.key) != e.value) '${e.key} → ${patternLabel(e.key)}',
    ];
    check(
      '3) 읽어서 말이 된다',
      wrong.isEmpty,
      wrong.isEmpty ? want.keys.join(' · ') : wrong.join(' / '),
    );

    // 3-b) 좁은 칸용 짧은 이름 — 스타일 낱말과 '용' 을 뗀다
    const wantShort = {
      'Lofi Walk C': '워킹 코러스',
      'Lofi Chorus': '코러스',
      'House Off V': '오프비트 벌스',
      'Jazz Sax H': '색소폰 헤드',
    };
    final wrongShort = [
      for (final e in wantShort.entries)
        if (patternShort(e.key) != e.value) '${e.key} → ${patternShort(e.key)}',
    ];
    check(
      '3-b) 짧은 이름',
      wrongShort.isEmpty,
      wrongShort.isEmpty
          ? wantShort.values.join(' · ')
          : wrongShort.join(' / '),
    );

    // 3-c) 짧은 이름도 **영어가 안 남아야** 하고, 너무 길면 칸에서 잘린다
    // 코드 진행 이름(`Cm-Ab-Eb-Bb`)은 길어도 어쩔 수 없다 — 줄이면 못 읽는다.
    bool isChordName(String s) => s.split('-').every((w) => _chord.hasMatch(w));
    final longOnes = [
      for (final n in all)
        if (!isChordName(n) && patternShort(n).replaceAll(' ', '').length > 8)
          '$n → ${patternShort(n)}',
    ];
    check(
      '3-c) 짧은 이름 길이',
      longOnes.isEmpty,
      longOnes.isEmpty
          ? '코드 진행 빼고 전부 8자 이하'
          : '${longOnes.length}개: ${longOnes.take(5).join(' / ')}',
    );

    // 4) 모르는 이름은 **그대로** 나온다(억지로 옮기다 틀린 말을 만들면 안 된다)
    check('4) 모르는 건 그대로', patternLabel('Zzz Qqq') == 'Zzz Qqq', '건드리지 않음');

    // ignore: avoid_print
    print(fail == 0 ? '패턴 이름 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
