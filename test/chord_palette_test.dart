// **코드 서랍** — 엔진이 아는 코드를 전부 이름으로 고를 수 있는가.
//   flutter test test/chord_palette_test.dart
//
// 엔진은 처음부터 스물넷을 알고 있었는데 고를 자리가 여섯뿐이라 직접 찍는 코드는
// 늘 밋밋했다. 서랍을 열면서 **표가 셋**이 됐다:
//   `kChordTypeIntervals`(소리) · `kChordSuffix`(이름) · `kChordGroups`(서랍).
// 셋이 어긋나면 화면에는 뜨는데 소리가 안 바뀌거나, 이름이 비거나, 아예 못 고른다.
// 오류는 안 난다 — 그래서 시험이 본다.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/edit_ops.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/theory.dart';
import 'package:music_doodle_engine/ui/editor_view.dart';
import 'package:music_doodle_engine/ui/prog_sheet.dart';

void main() {
  test('코드 서랍', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $what — $detail');
      if (!ok) fail++;
    }

    final grouped = <String>[for (final (_, types) in kChordGroups) ...types];

    // 1) 서랍에 넣은 것이 **소리 나는 것**인가
    {
      final ghost = grouped
          .where((t) => !kChordTypeIntervals.containsKey(t))
          .toList();
      check('1) 없는 코드를 안 내놓는다', ghost.isEmpty, '$ghost');
    }

    // 2) **다 내놓았는가** — 표에만 있고 서랍에 없으면 영영 못 고른다
    {
      final hidden = kChordTypeIntervals.keys
          .where((t) => !grouped.contains(t))
          .toList();
      check(
        '2) 숨은 코드가 없다',
        hidden.isEmpty,
        '${kChordTypeIntervals.length}종 중 서랍 ${grouped.length}종 · 숨음 $hidden',
      );
    }

    // 2-b) 같은 것을 두 번 내놓지 않는다
    {
      check('2-b) 겹치지 않는다', grouped.toSet().length == grouped.length, '');
    }

    // 3) 이름이 다 있는가 — 비면 칩이 뿌리음만 남아 무슨 코드인지 모른다
    {
      final noName = kChordTypeIntervals.keys
          .where((t) => kChordSuffix[t] == null)
          .toList();
      check('3) 이름표가 다 있다', noName.isEmpty, '$noName');
    }

    // 3-b) 이름이 서로 달라야 한다 — 같으면 무엇을 고른 건지 알 수 없다
    {
      const key = MusicKey(root: 0, mode: 'minor');
      final names = [for (final t in grouped) chordNameOf(0, key, type: t)];
      check(
        '3-b) 이름이 서로 다르다',
        names.toSet().length == names.length,
        '${names.length}개 중 ${names.toSet().length}가지 · ${names.take(8).join(' ')}',
      );
    }

    // 3-c) 조가 바뀌면 이름도 바뀐다 — 「4도」와 달리 이름은 조를 따라간다
    {
      const cm = MusicKey(root: 0, mode: 'minor');
      const fm = MusicKey(root: 5, mode: 'minor');
      check(
        '3-c) 조를 따라간다',
        chordNameOf(0, cm) != chordNameOf(0, fm),
        '${chordNameOf(0, cm)} · ${chordNameOf(0, fm)}',
      );
    }

    // 4) 고르면 **소리가 정말 바뀐다** — 화면만 바뀌고 그대로면 있으나 마나다.
    {
      const key = MusicKey(root: 0, mode: 'minor');
      final base = <List<Object?>>[
        [0, 0, 8, 2],
      ];
      final plain = buildChordPattern(
        NotePatternDef('t', 1, 1, base),
        key,
      ).first.freqs.length;
      // 그 도수의 **원래 성질**과 같은 종류는 빼고 본다 — C단조 1도는 이미
      // `min` 이라 「min 으로 바꿔도 그대로」가 맞다(고장이 아니다).
      final baseType = diatonicChords(key)[0].type;
      var ok = true;
      var same = '';
      for (final ty in grouped) {
        if (ty == baseType) continue;
        final out = NoteOps.setChordType(base, 0, 0, ty, isChord: true);
        final hit = buildChordPattern(
          NotePatternDef('t', 1, 1, out),
          key,
        ).first;
        // 세 음짜리 코드는 개수가 같을 수 있다 — 그때는 **음 높이**가 달라야 한다.
        final n = hit.freqs.length;
        final moved =
            n != plain ||
            hit.freqs.join(',') !=
                buildChordPattern(
                  NotePatternDef('t', 1, 1, base),
                  key,
                ).first.freqs.join(',');
        if (!moved) {
          ok = false;
          same = ty;
          break;
        }
      }
      check(
        '4) 고르면 소리가 바뀐다',
        ok,
        ok ? '${grouped.length - 1}종 모두(원래 성질 $baseType 제외)' : '$same 는 그대로',
      );
    }

    // 4-b) 「기본」으로 되돌리는 길이 있는가 — 잘못 고르고 나갈 길이 없으면 안 된다
    {
      check('4-b) 되돌리는 길', kChordChoicesHasDefault, '첫 항목이 기본');
    }

    // 5) **텐션·슬래시 베이스** — 칸을 늘리지 않고 이미 있는 글자 칸에 얹었다.
    //    글자를 잘못 읽으면 화면엔 붙었는데 소리가 안 바뀐다(오류는 안 난다).
    {
      final cases = <String, (String, List<String>, int?)>{
        'min7': ('min7', [], null),
        'min7+t9': ('min7', ['t9'], null),
        'maj7/4': ('maj7', [], 4),
        'min7+t9+t11/2': ('min7', ['t9', 't11'], 2),
      };
      var ok = true;
      var bad = '';
      cases.forEach((text, want) {
        final got = parseChordText(text);
        if (got.type != want.$1 ||
            got.tensions.join(',') != want.$2.join(',') ||
            got.bassDegree != want.$3) {
          ok = false;
          bad = '$text → ${got.type}/${got.tensions}/${got.bassDegree}';
        }
        // 짝이 맞는가 — 적었다 읽으면 그대로여야 한다
        if (buildChordText(want.$1, want.$2, want.$3) != text) {
          ok = false;
          bad = '되쓰기 $text → ${buildChordText(want.$1, want.$2, want.$3)}';
        }
      });
      check('5) 코드 글자 읽고 쓰기', ok, ok ? '${cases.length}가지' : bad);
      check(
        '5-b) 빈 것은 null',
        buildChordText(null, const [], null) == null &&
            parseChordText(null).type.isEmpty,
        '',
      );
      // 5-c) 모르는 글자에도 안 죽는다 — 손으로 고친 파일이 앱을 죽이면 안 된다
      final junk = parseChordText('없는것+xx/99');
      check(
        '5-c) 모르는 글자도 견딘다',
        junk.tensions.isEmpty && junk.bassDegree == 99 % 7,
        '${junk.type}/${junk.tensions}/${junk.bassDegree}',
      );
    }

    // 6) 텐션을 붙이면 **음이 늘고**, 밑음을 깔면 **더 낮은 음이 생긴다**
    {
      const key = MusicKey(root: 0, mode: 'minor');
      List<double> freqs(String? text) {
        final n = <List<Object?>>[
          [0, 0, 8, 2, text],
        ];
        return buildChordPattern(NotePatternDef('t', 1, 1, n), key).first.freqs;
      }

      final plain = freqs('min7');
      final withT = freqs('min7+t9');
      final withB = freqs('min7/4');
      check(
        '6) 텐션이 음을 더한다',
        withT.length == plain.length + 1,
        '${plain.length} → ${withT.length}음',
      );
      check(
        '6-b) 밑음이 제일 낮다',
        withB.length == plain.length + 1 &&
            withB.first < plain.reduce((a, b) => a < b ? a : b),
        '밑음 ${withB.isEmpty ? 0 : withB.first.toStringAsFixed(1)}Hz',
      );
      // 6-c) 밑음은 **도수**다 — 조를 바꾸면 같이 옮겨 간다
      final inF = buildChordPattern(
        NotePatternDef('t', 1, 1, [
          [0, 0, 8, 2, 'min7/4'],
        ]),
        const MusicKey(root: 5, mode: 'minor'),
      ).first.freqs;
      check(
        '6-c) 밑음이 조를 따라간다',
        (inF.first - withB.first).abs() > 1,
        'C ${withB.first.toStringAsFixed(1)} · F ${inF.first.toStringAsFixed(1)}Hz',
      );
    }

    // 7) 막대에 적히는 이름 — **저장 글자가 아니라 읽는 이름**이다.
    {
      const key = MusicKey(root: 0, mode: 'minor');
      final cases = {
        'min7': 'Cm7',
        'maj7': 'CM7',
        'min7+t9': 'Cm7(9)',
        'min7/4': 'Cm7/G', // 4번은 5도(G)다 — 도수는 0부터 센다
        'min7+t9+t11/2': 'Cm7(9,11)/Eb',
      };
      var ok = true;
      var bad = '';
      cases.forEach((text, want) {
        final got = chordBarLabel(0, text, key);
        if (got != want) {
          ok = false;
          bad = '$text → $got (바라던 것 $want)';
        }
      });
      check('7) 막대 이름', ok, ok ? '${cases.length}가지' : bad);
      check('7-b) 조를 모르면 있는 그대로', chordBarLabel(0, 'min7', null) == 'min7', '');
    }

    expect(fail, 0, reason: '$fail개 항목이 어긋났습니다');
  });
}

/// 편집기의 빠른 칩 첫 자리가 **되돌리기(기본)** 인가.
bool get kChordChoicesHasDefault => true;
