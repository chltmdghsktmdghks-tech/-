// **질문에 답해서 곡 만들기** — 답이 정말 곡을 바꾸는가.
//   flutter test test/ask_song_test.dart
//
// 이 기능의 값어치는 「답한 대로 나온다」 하나다. 답을 바꿔도 같은 곡이 나오면
// 열 번 물어본 것이 전부 헛일이고, 사람은 두 번 안 쓴다.
//
// 그래서 **답 하나만 바꿔** 결과가 그 방향으로 움직이는지 잰다.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/ask_song.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';

Map<String, String> _base() => {
  'mood': 'calm',
  'scene': 'cafe',
  'speed': 'mid',
  'power': 'mid2',
  'lead': 'warm',
  'low': 'bounce',
  'drum': 'normal',
  'space': 'room2',
  'len': 'm',
  'edge': 'clean',
};

(Project, Transport) _make(Map<String, String> a) {
  final p = Project.initial();
  final tr = Transport();
  applyAsk(p, tr, a, askRecipe(a));
  return (p, tr);
}

void main() {
  test('질문에 답해서 곡 만들기', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $what — $detail');
      if (!ok) fail++;
    }

    // 1) 질문 표가 성한가 — 값이 겹치면 점수가 엉키고, 빈 답은 못 고른다.
    {
      final keys = [for (final q in kAskQuestions) q.key];
      check(
        '1) 질문 열 개',
        kAskQuestions.length == 10,
        '${kAskQuestions.length}개',
      );
      check('1-b) 질문 키가 안 겹친다', keys.toSet().length == keys.length, '');
      var ok = true;
      var bad = '';
      final seen = <String>{};
      for (final q in kAskQuestions) {
        if (q.answers.length < 2) {
          ok = false;
          bad = '${q.key} 답이 ${q.answers.length}개';
        }
        for (final (v, l, _) in q.answers) {
          if (v.isEmpty || l.isEmpty) {
            ok = false;
            bad = '${q.key} 빈 답';
          }
          if (!seen.add(v)) {
            ok = false;
            bad = '값이 겹친다($v)';
          }
        }
      }
      check('1-c) 답이 성하고 값이 안 겹친다', ok, bad);
    }

    // 1-d) **뼈대 곡이 다 있는 스타일인가.** 없는 키를 적어 두면 곡을 못 만든다.
    {
      final have = {for (final g in kGenres) g.key};
      final missing = kAskFit.keys.where((k) => !have.contains(k)).toList();
      check('1-d) 뼈대 곡이 다 있다', missing.isEmpty, '$missing');
    }

    // 2) **답이 다르면 곡이 다르다** — 기분 넷이 서로 다른 뼈대·조를 고르는가.
    {
      final got = <String>{};
      for (final m in ['bright', 'calm', 'blue', 'dark']) {
        final a = _base()..['mood'] = m;
        final r = askRecipe(a);
        got.add('${r.genre}/${r.root}/${r.mode}');
      }
      check('2) 기분이 곡을 가른다', got.length >= 3, '$got');
    }

    // 2-b) 밝은 기분은 **장조**로 — 단조로 나면 「밝고 신남」이라 답한 뜻이 없다.
    {
      final a = _base()..['mood'] = 'bright';
      check('2-b) 밝으면 장조', askRecipe(a).mode == 'major', askRecipe(a).mode);
    }

    // 3) **빠르기가 답을 따라간다**
    {
      double bpmOf(String s) => askRecipe(_base()..['speed'] = s).bpm;
      check(
        '3) 빠르기가 답을 따른다',
        bpmOf('fast') > bpmOf('mid') &&
            bpmOf('mid') > bpmOf('slow') &&
            bpmOf('slow') > bpmOf('still'),
        '${bpmOf('fast').round()} > ${bpmOf('mid').round()} > '
            '${bpmOf('slow').round()} > ${bpmOf('still').round()}',
      );
      check(
        '3-b) 사람이 칠 수 있는 빠르기',
        [
          'fast',
          'mid',
          'slow',
          'still',
        ].every((s) => bpmOf(s) >= 60 && bpmOf(s) <= 180),
        '',
      );
    }

    // 4) **길이가 답을 따라간다** — 초로 잰다(마디로 세면 빠르기에 휘둘린다).
    {
      double secOf(String l) {
        final a = _base()..['len'] = l;
        final (p, tr) = _make(a);
        return SceneSequencer.songSeconds(p, tr);
      }

      final s = secOf('s'), m = secOf('m'), l = secOf('l');
      check(
        '4) 길이가 답을 따른다',
        s < m && m < l,
        '짧게 ${s.round()}초 · 보통 ${m.round()}초 · 길게 ${l.round()}초',
      );
      check('4-b) 다 1분은 넘는다', s > 60, '${s.round()}초');
    }

    // 5) **맨 앞 악기가 답대로**
    {
      for (final (ans, want) in [
        ('voice', 'vocal'),
        ('bell', 'bell'),
        ('warm', 'sax'),
        ('synth', 'saw'),
      ]) {
        final (p, _) = _make(_base()..['lead'] = ans);
        final mel = p.tracks.where((t) => t.type == 'melody');
        check(
          '5) 앞 악기 $ans',
          mel.isNotEmpty && mel.first.voice == want,
          mel.isEmpty ? '가락 트랙 없음' : mel.first.voice,
        );
      }
    }

    // 6) **저음·드럼·공간이 답을 따라간다** — 값이 진짜 움직이는가.
    {
      double bassVol(String v) {
        final (p, _) = _make(_base()..['low'] = v);
        return p.tracks.firstWhere((t) => t.type == 'bass').vol;
      }

      check(
        '6) 저음 크기',
        bassVol('deep') > bassVol('bounce') &&
            bassVol('bounce') > bassVol('soft'),
        '묵직 ${bassVol('deep').toStringAsFixed(2)} · '
            '통통 ${bassVol('bounce').toStringAsFixed(2)} · '
            '부드 ${bassVol('soft').toStringAsFixed(2)}',
      );

      double drumVol(String v) {
        final (p, _) = _make(_base()..['drum'] = v);
        return p.tracks.firstWhere((t) => t.type == 'drum').vol;
      }

      check(
        '6-b) 드럼 크기',
        drumVol('punch') > drumVol('normal') &&
            drumVol('normal') > drumVol('back'),
        '${drumVol('punch').toStringAsFixed(2)} · '
            '${drumVol('normal').toStringAsFixed(2)} · '
            '${drumVol('back').toStringAsFixed(2)}',
      );

      double rev(String v) {
        final (p, _) = _make(_base()..['space'] = v);
        var s = 0.0;
        for (final t in p.tracks) {
          s += t.rev;
        }
        return s;
      }

      check(
        '6-c) 잔향',
        rev('hall') > rev('room2') && rev('room2') > rev('dry'),
        '홀 ${rev('hall').toStringAsFixed(2)} · '
            '방 ${rev('room2').toStringAsFixed(2)} · '
            '앞 ${rev('dry').toStringAsFixed(2)}',
      );
    }

    // 7) **꽉/비움이 악기 수를 바꾼다**
    {
      int n(String v) => _make(_base()..['power'] = v).$1.tracks.length;
      check(
        '7) 악기 수',
        n('huge') > n('mid2') && n('mid2') > n('thin'),
        '꽉 ${n('huge')} · 보통 ${n('mid2')} · 비움 ${n('thin')}',
      );
    }

    // 8) **거칠게는 드럼 키트로** — 씬에도 얹어야 저장했다 열 때 안 돌아간다.
    {
      final (p, _) = _make(_base()..['edge'] = 'rough');
      check(
        '8) 거칠게',
        p.tracks.firstWhere((t) => t.type == 'drum').kit == 'lofi' &&
            p.scenes.every((s) => s.kit == 'lofi'),
        p.tracks.firstWhere((t) => t.type == 'drum').kit,
      );
    }

    // 9) **어떤 답 조합이든 소리가 난다** — 여기서 「음악이 아닌 것」이 나오면 안 된다.
    {
      var worst = '';
      var ok = true;
      for (var i = 0; i < kAskQuestions.length; i++) {
        for (final (v, _, _) in kAskQuestions[i].answers) {
          final a = _base()..[kAskQuestions[i].key] = v;
          try {
            final (p, tr) = _make(a);
            final b = SceneSequencer.buildSong(p, tr);
            if (b.notes.isEmpty && b.drums.isEmpty) {
              ok = false;
              worst = '$v → 조용함';
            }
            for (final n in b.notes) {
              final f = (n[1] as num).toDouble();
              if (!f.isFinite || f < 15 || f > 20000) {
                ok = false;
                worst = '$v → 말이 안 되는 음(${f.toStringAsFixed(1)}Hz)';
              }
            }
          } catch (e) {
            ok = false;
            worst = '$v → 터진다: $e';
          }
        }
      }
      check('9) 어떤 답이든 소리가 난다', ok, ok ? '답 33가지 모두' : worst);
    }

    expect(fail, 0, reason: '$fail개 항목이 어긋났습니다');
  });
}
