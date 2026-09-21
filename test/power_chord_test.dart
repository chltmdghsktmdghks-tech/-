// **록 기타는 파워코드를 친다.**
//   flutter test test/power_chord_test.dart
//
// 파워코드는 3음이 없다(뿌리 + 5도 + 옥타브). 왜곡을 걸면 3음의 배음이 5도와
// 맥놀이를 일으켜 지저분해진다 — 그래서 록 기타는 3음을 뺀다. 뺀 자리는
// 베이스와 보컬이 채운다.
//
// 보는 것: 3음이 정말 없는가(소리로) · **기타일 때만**인가(록이어도 피아노는
// 3음이 있어야 한다) · 사용자가 고른 코드 종류를 덮지 않는가.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/theory.dart';

/// 그 화음의 **반음 간격**(뿌리 기준) — 3음이 있나 보려면 이게 필요하다.
Set<int> _semis(List<double> freqs) {
  if (freqs.isEmpty) return {};
  final lo = freqs.reduce((a, b) => a < b ? a : b);
  return {
    for (final f in freqs) ((12 * (log2(f / lo))).round() % 12 + 12) % 12,
  };
}

double log2(double x) {
  var n = 0.0;
  var v = x;
  while (v >= 2) {
    v /= 2;
    n += 1;
  }
  while (v < 1) {
    v *= 2;
    n -= 1;
  }
  // 남은 1~2 구간은 이분법으로 — 시험에 쓸 만큼만 정확하면 된다.
  var step = 0.5;
  for (var i = 0; i < 24; i++) {
    v *= v;
    if (v >= 2) {
      v /= 2;
      n += step;
    }
    step /= 2;
  }
  return n;
}

void main() {
  test('록 기타 파워코드', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $what — $detail');
      if (!ok) fail++;
    }

    // 1) 표가 성한가 — 파워코드는 뿌리·5도·옥타브다
    {
      final iv = kChordTypeIntervals['five'];
      check('1) 파워코드는 3음이 없다', iv != null && iv.join(',') == '0,7,12', '$iv');
      check('1-b) 이름표는 5', kChordSuffix['five'] == '5', '');
    }

    // 2) 규칙 — **기타일 때만.** 록이어도 피아노가 화음을 맡으면 3음이 있어야 한다.
    {
      check(
        '2) 기타일 때만',
        genreChordType('rock', 'guitar') == 'five' &&
            genreChordType('rock', 'nylon') == 'five' &&
            genreChordType('rock', 'piano') == null &&
            genreChordType('rock', 'pad') == null &&
            genreChordType('lofi', 'guitar') == null,
        '록·기타 ${genreChordType('rock', 'guitar')} · '
            '록·패드 ${genreChordType('rock', 'pad')} · '
            '로파이·기타 ${genreChordType('lofi', 'guitar')}',
      );
    }

    // 3) **록을 고르면 화음이 기타가 된다** — 「기타가 앞에」라고 적어 놓고
    //    정작 패드가 소리를 내고 있었다.
    final p = Project.initial()..setGenre('rock');
    final chord = p.tracks.firstWhere((t) => t.type == 'chord');
    check('3) 록 화음은 기타', chord.voice == 'guitar', chord.voice);
    check('3-b) 이름도 기타', chord.name == '기타', chord.name);
    // 3-b2) 가락도 기타 — 록은 기타 두 대(리듬 + 리드)다.
    //       가락이 신스 리드로 나면 그 순간 록이 아니라 신스팝이 된다.
    {
      final mel = p.tracks.firstWhere((t) => t.type == 'melody');
      check('3-b2) 록 가락도 기타', mel.voice == 'guitar', mel.voice);
      // 다만 **가락은 파워코드가 아니다** — 낱음을 켜는 줄이다.
      check('3-b3) 가락은 화음이 아니다', mel.type == 'melody', mel.type);
    }

    // 3-c) 다른 스타일로 가면 도로 그 스타일 것 — 록 기타가 로파이에 남으면 안 된다
    {
      final q = Project.initial()
        ..setGenre('rock')
        ..setGenre('lofi');
      final c = q.tracks.firstWhere((t) => t.type == 'chord');
      check('3-c) 스타일을 바꾸면 돌아온다', c.voice == kTypeVoice['chord'], c.voice);
    }

    // 3-d) **사용자가 고른 음색은 안 건드린다**
    {
      final q = Project.initial()..setGenre('lofi');
      final c = q.tracks.firstWhere((t) => t.type == 'chord');
      c.voice = 'organ'; // 사용자가 골랐다
      q.setGenre('rock');
      final c2 = q.tracks.firstWhere((t) => t.type == 'chord');
      check('3-d) 고른 음색은 지킨다', c2.voice == 'organ', c2.voice);
    }

    // 4) **소리에 3음이 없다** — 표가 아니라 나가는 주파수로 본다.
    {
      final tr = Transport()
        ..root = 0
        ..mode = 'minor';
      final b = SceneSequencer.build(p, tr, reps: 1);
      final part = SceneSequencer.busNames(p).indexOf(chord.id);
      // 같은 시각에 난 음들을 한 화음으로 묶는다
      final byTime = <String, List<double>>{};
      for (final n in b.notes) {
        if (n[7] != part) continue;
        byTime
            .putIfAbsent((n[6] as double).toStringAsFixed(4), () => [])
            .add(n[1] as double);
      }
      var chords = 0, withThird = 0;
      byTime.forEach((_, fs) {
        if (fs.length < 2) return;
        chords++;
        final s = _semis(fs);
        // 단3도(3) 나 장3도(4) 가 있으면 파워코드가 아니다
        if (s.contains(3) || s.contains(4)) withThird++;
      });
      check(
        '4) 소리에 3음이 없다',
        chords > 0 && withThird == 0,
        '화음 $chords개 · 3음 있는 것 $withThird개',
      );
      // 4-b) 5도는 **있어야** 한다 — 없으면 파워코드가 아니라 그냥 한 음이다
      var withFifth = 0;
      byTime.forEach((_, fs) {
        if (fs.length >= 2 && _semis(fs).contains(7)) withFifth++;
      });
      check('4-b) 5도는 있다', withFifth == chords, '$withFifth/$chords');
    }

    // 5) **직접 고른 코드 종류가 이긴다** — 고른 것을 스타일이 덮으면 고를 이유가 없다.
    {
      const key = MusicKey(root: 0, mode: 'minor');
      final def = NotePatternDef('t', 1, 1, [
        [0, 0, 8, 2, 'min7'],
        [3, 8, 8, 2],
      ]);
      final hits = buildChordPattern(def, key, plainType: 'five');
      final a = _semis(hits[0].freqs); // 적어 둔 것 — m7 그대로
      final b2 = _semis(hits[1].freqs); // 안 적은 것 — 파워코드
      check(
        '5) 적어 둔 코드가 이긴다',
        a.contains(3) && !b2.contains(3) && !b2.contains(4),
        '적은 것 $a · 안 적은 것 $b2',
      );
    }

    expect(fail, 0, reason: '$fail개 항목이 어긋났습니다');
  });
}
