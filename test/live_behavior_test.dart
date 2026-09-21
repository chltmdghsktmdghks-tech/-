// Phase 5 — **라이브가 장르를 따르는가.** (개선 계획 7 「Live Behavior」)
//   flutter test test/live_behavior_test.dart
//
// 라이브 패드는 여태 어떤 장르든 **피아노 · 한 음 · 보통 길이**였다.
// 트랩을 만들다 라이브를 열면 피아노가 나왔다.
//
// 지키는 것:
//  1. 장르마다 값이 있고, 그 값이 실제로 쓸 수 있는 것인가
//  2. 화면을 열면 그 값이 얹히는가
//  3. **사용자가 고른 음색은 안 덮는가** — 인서트와 같은 규칙
//  4. 음계는 안 건드린다 — 「아무 패드나 눌러도 맞는 음」이 이 화면의 약속이다
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/instruments.dart';
import 'package:music_doodle_engine/live_ops.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/theory.dart';
import 'package:music_doodle_engine/ui/live_view.dart';

void main() {
  testWidgets('라이브 기본값', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    // ── 1) 값이 제정신인가 ──
    {
      final bad = <String>[];
      for (final g in kGenres) {
        if (!INSTRUMENTS.containsKey(g.liveVoice)) {
          bad.add('${g.key} 없는 음색 ${g.liveVoice}');
        }
        if (!['single', 'chord', 'arp'].contains(g.liveMode)) {
          bad.add('${g.key} 모르는 주법 ${g.liveMode}');
        }
        if (g.liveLen < 0 || g.liveLen > 2) bad.add('${g.key} 길이 ${g.liveLen}');
      }
      check(
        '1) 장르마다 쓸 수 있는 값',
        bad.isEmpty,
        bad.isEmpty ? '${kGenres.length}개' : bad.take(4).join(', '),
      );

      // 다 같으면 넣으나 마나다
      final voices = {for (final g in kGenres) g.liveVoice};
      check(
        '1-b) 장르끼리 다르다',
        voices.length >= 5,
        '음색 ${voices.length}종 · ${voices.join(' ')}',
      );
    }

    // ── 2) 화면을 열면 얹힌다 ──
    {
      Future<LiveChannel> open(String genre) async {
        final p = Project.initial()..setGenre(genre);
        final live = LiveChannel();
        await tester.pumpWidget(
          MaterialApp(
            key: ValueKey(genre),
            theme: ThemeData.dark(),
            home: Scaffold(
              body: LiveView(
                project: p,
                transport: Transport(),
                live: live,
                host: null,
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
        return live;
      }

      final trap = await open('trap');
      check('2) 트랩을 열면 벨', trap.voice == 'bell', trap.voice);
      final rock = await open('rock');
      check('2-b) 록을 열면 기타', rock.voice == 'guitar', rock.voice);
      final amb = await open('ambient');
      check('2-c) 엠비언트를 열면 패드', amb.voice == 'pad', amb.voice);
    }

    // ── 3) **내가 고른 음색은 안 덮는다** ──
    {
      final p = Project.initial()..setGenre('trap');
      final live = LiveChannel()..voice = 'sax'; // 사용자가 골랐다
      await tester.pumpWidget(
        MaterialApp(
          key: const ValueKey('mine'),
          theme: ThemeData.dark(),
          home: Scaffold(
            body: LiveView(
              project: p,
              transport: Transport(),
              live: live,
              host: null,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      check('3) 내가 고른 음색은 그대로', live.voice == 'sax', live.voice);
      check('3-b) 고르기 전에는 장르가 정한다', LiveChannel().voiceAuto, '');
    }

    // ── 4) 음계는 안 건드렸다 ──
    //
    // 장르마다 음을 빼면 「아무 패드나 눌러도 맞는 음이 나온다」가 흔들린다.
    // 14개 패드가 전부 음계 안에 있는지 본다(장르와 무관하게).
    {
      const key = MusicKey(root: 3, mode: 'minor');
      final scale = kScale[key.mode]!;
      final out = <String>[];
      for (var d = 0; d < LivePads.count; d++) {
        final midi = LivePads.midiOf(d, key, 0);
        if (!scale.contains((midi - key.root - 60) % 12)) {
          out.add('$d번($midi)');
        }
      }
      check(
        '4) 패드 14개가 다 음계 안',
        out.isEmpty,
        out.isEmpty ? '조를 옮겨도 그대로' : out.join(', '),
      );
    }

    // 5) **살아 있으면 장르 음색이 얹힌다.** (왕복은 store_check_test 5-c)
    //    이게 조용히 죽어 있었다 — 불러오기가 `live.voice = ...` 를 썼는데
    //    그 setter 는 「사용자가 골랐다」는 뜻이라 voiceAuto 를 꺼 버린다.
    {
      final live2 = LiveChannel()..restore(voice: 'piano', auto: true);
      live2.suggestVoice(genreDef('trap').liveVoice);
      final live3 = LiveChannel()..restore(voice: 'piano', auto: false);
      live3.suggestVoice(genreDef('trap').liveVoice);
      check(
        '5) 장르 음색은 「고른 적 없을 때만」 얹힌다',
        live2.voice == genreDef('trap').liveVoice && live3.voice == 'piano',
        '안 골랐으면 ${live2.voice} · 골랐으면 ${live3.voice}',
      );
      // restore 는 **깃발을 안 건드려야** 한다 — 그게 setter 와 다른 점이다
      final live4 = LiveChannel()..restore(voice: 'sax');
      check(
        '5-b) restore 는 「내가 골랐다」로 적지 않는다',
        live4.voiceAuto,
        'voiceAuto=${live4.voiceAuto}',
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '라이브 기본값 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
