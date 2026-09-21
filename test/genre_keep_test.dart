// 5단계 15/N — 스타일을 바꿔도 **내가 고친 판은 지킨다**.
//   flutter test test/genre_keep_test.dart
//
// 스타일 칩은 누르기 쉽다(구경하려고 눌러 본다). 그때마다 손으로 찍은 판이 조용히
// 사라지면, 사용자는 **그 사실을 나중에 알게 된다** — 되돌릴 방법도 없다.
// 앱을 지우는 이유는 대개 이런 것이지 기능이 모자라서가 아니다.
//
// 배열형(4트랙 고정)끼리는 같은 자리에 **다시 실어 준다**.
// 객체형(편성이 통째로 바뀜)은 실을 자리가 없으니 **개수만 알리고 판은 안 지운다**.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/feel.dart';
import 'package:music_doodle_engine/genre_mix.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/ui/song_view.dart' show genreChangeNote;

void main() {
  test('스타일 바꿔도 내 판 지키기', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final p = Project.initial();
    final tr = Transport();
    final drum = p.tracks.firstWhere((t) => t.type == 'drum');
    final sceneAt = p.currentScene;

    // 드럼을 손으로 고친다 — 킥만 네 박에 하나씩(누가 봐도 내가 찍은 판)
    final mineName = p.makeEditable(drum);
    p.putUserPattern(
      'drum',
      mineName,
      drum: DrumPatternDef(mineName, 2, 2, const {
        'k': [0, 8, 16, 24],
      }),
    );
    check(
      '1) 내 판 만들기',
      p.isMine(p.scenes[sceneAt].clips[drum.id]),
      '$mineName · 씬 ${p.scenes[sceneAt].name}',
    );

    // 배열형 → 배열형 (로파이 → 하우스)
    p.setGenre('house');
    final drum2 = p.tracks.firstWhere((t) => t.type == 'drum');
    final clipNow = p.scenes[sceneAt].clips[drum2.id];
    check(
      '2) 스타일 바꿔도 그대로',
      clipNow == mineName && p.keptMine >= 1,
      '클립 $clipNow · 지킨 판 ${p.keptMine}개',
    );

    // 나머지 트랙은 새 스타일 것으로 갈려야 한다 — 안 갈리면 스타일을 바꾼 게 아니다
    final bass = p.tracks.firstWhere((t) => t.type == 'bass');
    final bassClip = p.scenes[sceneAt].clips[bass.id];
    check(
      '3) 나머지는 새 스타일로',
      (bassClip ?? '').startsWith('House'),
      '베이스 $bassClip',
    );

    // 지킨 판이 **실제로 소리를 낸다** (이름만 남고 안 울리면 지킨 게 아니다)
    //
    // 변형은 꺼 둔다 — 되풀이되는 바퀴에 킥을 하나 더하는 수가 있어서(계획 6-1)
    // 「네 박에 하나」 셈이 어긋난다. 여기서 재는 것은 **판이 지켜졌는가**다.
    p.setFeel(const Feel(vary: 0));
    p.launchScene(sceneAt);
    final b = SceneSequencer.build(p, tr, reps: 1);
    final kicks = [
      for (final d in b.drums)
        if (d[1] == 'kick') d,
    ];
    check(
      '4) 지킨 판이 소리 난다',
      kicks.isNotEmpty && kicks.length % 4 == 0,
      '킥 ${kicks.length}타(내 판은 네 박에 하나)',
    );

    // 객체형(트랩) — 편성이 통째로 바뀐다
    p.setGenre('trap');
    check(
      '5) 객체형은 개수만 알림',
      p.keptMine == 0 && p.parkedMine >= 1 && p.userDrum.containsKey(mineName),
      '빠진 판 ${p.parkedMine}개 · 판 자체는 남아 있음 ${p.userDrum.containsKey(mineName)}',
    );

    // 편집기 패턴 목록 **맨 위**에 있어야 다시 고를 수 있다
    final names = SceneSequencer.patternNamesFor(p, 'drum');
    check('6) 목록 맨 위에 남는다', names.first == mineName, '맨 앞 ${names.first}');

    // 다시 배열형으로 돌아와도 판은 살아 있다(자동으로 다시 실리지는 않는다)
    p.setGenre('lofi');
    check(
      '7) 돌아와도 안 지워짐',
      p.userDrum.containsKey(mineName),
      '내 판 ${p.userDrum.length}개 보관 중',
    );

    // 저장·불러오기 왕복에도 남는다
    final back = Project.initial()..loadJson(p.toJson());
    check(
      '8) 저장 왕복',
      back.userDrum.containsKey(mineName),
      '되살린 뒤 ${back.userDrum.length}개',
    );

    // 10) **손으로 맞춰 둔 믹서는 스타일을 바꿔도 그대로다.**
    //
    //     인서트(`fxAuto`)에는 이 규칙이 있었는데 믹서에는 없었다.
    //     정확히는 **믹스를 얹는 코드 자체가 배열형에 없어서** 문제가 안 드러났다 —
    //     그걸 고치는 순간 「스타일 구경했더니 공들여 맞춘 페이더가 날아간다」가
    //     생긴다. 그래서 같이 넣었다(`mixAuto`).
    {
      final q = Project.initial(); // 로파이
      final drum = q.tracks.firstWhere((t) => t.type == 'drum');
      // **값이 실제로 달라지는 슬롯**을 고른다 — 로파이 코드 0.95 → 하우스 0.78.
      // 우연히 같은 슬롯(베이스는 둘 다 1.05)으로 재면 안 바뀌어도 통과한다.
      final chord = q.tracks.firstWhere((t) => t.type == 'chord');
      drum.vol = 0.42; // 손으로 만졌다
      final chordBefore = chord.vol; // 안 만졌다
      q.setGenre('house');
      final houseChord = kGenreMix['house']!.parts['chord']!.vol;
      check(
        '10) 만진 페이더는 그대로 · 안 만진 것은 새 스타일로',
        (drum.vol - 0.42).abs() < 1e-9 &&
            (chord.vol - houseChord).abs() < 1e-9 &&
            (chordBefore - houseChord).abs() > 1e-6 && // 진짜 달라지는 값인가
            !drum.mixAuto &&
            chord.mixAuto,
        '드럼 ${drum.vol}(그대로) · 코드 $chordBefore → ${chord.vol}(하우스 값)',
      );

      // EQ 만 만져도 지켜야 한다 — 페이더만 세는 것은 반쪽이다
      final r = Project.initial();
      final ch = r.tracks.firstWhere((t) => t.type == 'chord');
      ch.eq.hi = 5;
      ch.eqChanged();
      r.setGenre('rock');
      check(
        '10-b) EQ 만 만져도 지킨다',
        ch.eq.hi == 5 && !ch.mixAuto,
        'hi=${ch.eq.hi} · mixAuto=${ch.mixAuto}',
      );

      // 저장·불러오기 왕복에도 깃발이 남아야 한다 (안 그러면 다음에 열 때 덮인다)
      final back = Project.initial()..loadJson(q.toJson());
      final bd = back.tracks.firstWhere((t) => t.type == 'drum');
      back.setGenre('rock');
      check(
        '10-c) 왕복해도 지킨다',
        (bd.vol - 0.42).abs() < 1e-9 && !bd.mixAuto,
        '드럼 ${bd.vol} · mixAuto=${bd.mixAuto}',
      );
    }

    // 9) **말해 주는 문장이 빠뜨리지 않는가.**
    //    지킨 것과 빠진 것은 **동시에** 생길 수 있는데(일부만 자리를 찾는다),
    //    예전 문장은 지킨 쪽만 말하고 빠진 쪽은 입을 다물었다.
    //    하필 사용자가 걱정하는 것은 빠진 쪽이다.
    final both = genreChangeNote(3, 2) ?? '';
    check(
      '9) 지킨 것·빠진 것을 **둘 다** 말한다',
      both.contains('3개') && both.contains('2개') && both.contains('빠졌'),
      '「$both」',
    );
    check(
      '9-b) 지킨 것만 있으면 그것만',
      genreChangeNote(3, 0) == '손으로 고친 판 3개는 그대로 뒀습니다',
      '「${genreChangeNote(3, 0)}」',
    );
    check(
      '9-c) 빠진 것만 있으면 어디 있는지까지',
      (genreChangeNote(0, 2) ?? '').contains('편집기 패턴 목록 맨 위'),
      '「${genreChangeNote(0, 2)}」',
    );
    check('9-d) 아무것도 없으면 말 안 한다', genreChangeNote(0, 0) == null, 'null');

    // ── 11) 스타일 바꾸기를 **되돌릴 수 있다** ──
    //
    // 지키는 것만으로는 모자란다. 객체형(트랩·팝…)으로 넘어가면 편성이 통째로
    // 갈려서 지킬 자리 자체가 없다 — 그때는 「되돌리기」밖에 길이 없다.
    {
      final q = Project.initial()..name = '되돌릴 곡';
      final qt = Transport();
      final d = q.tracks.firstWhere((t) => t.type == 'drum');
      // 손으로 고친 판 하나를 만들어 둔다
      q.putUserPattern(
        'drum',
        '내가 만든 판',
        drum: const DrumPatternDef('내가 만든 판', 1, 1, {
          'K': [0, 8],
        }),
      );
      q.setClip(d, '내가 만든 판');
      final beforeGenre = q.genre;
      final beforeTracks = q.tracks.length;
      final beforeScenes = [for (final sc in q.scenes) sc.name];
      final beforeClip = q.scenes[q.currentScene].clips[d.id];
      final beforeBpm = qt.bpm, beforeMode = qt.mode;

      final undo = GenreUndo.of(q, qt);
      q.setGenre('trap'); // 객체형 — 편성이 통째로 바뀐다
      qt
        ..bpm = 140
        ..mode = 'minor';
      final changed =
          q.genre == 'trap' &&
          q.tracks.length != beforeTracks &&
          [for (final sc in q.scenes) sc.name].join() != beforeScenes.join();
      check(
        '11-a) 스타일이 실제로 통째로 갈린다',
        changed,
        '트랙 $beforeTracks→${q.tracks.length} · 씬 ${beforeScenes.length}→${q.scenes.length}',
      );

      undo.restore(q, qt);
      final backTrack = q.tracks.firstWhere((t) => t.type == 'drum');
      check(
        '11-b) 되돌리면 다 돌아온다',
        q.genre == beforeGenre &&
            q.tracks.length == beforeTracks &&
            [for (final sc in q.scenes) sc.name].join() ==
                beforeScenes.join() &&
            qt.bpm == beforeBpm &&
            qt.mode == beforeMode,
        '스타일 ${q.genre} · 트랙 ${q.tracks.length} · 씬 ${q.scenes.length} · '
            '${qt.bpm.round()}BPM ${qt.mode}',
      );
      // **클립까지** 돌아와야 한다 — 이름만 돌아오고 아무것도 안 치면 되돌린 게 아니다.
      check(
        '11-c) 손으로 고친 판도 그 자리에',
        q.scenes[q.currentScene].clips[backTrack.id] == beforeClip &&
            beforeClip == '내가 만든 판' &&
            q.userDrum.containsKey('내가 만든 판'),
        '클립 ${q.scenes[q.currentScene].clips[backTrack.id]} '
            '(바라는 값 $beforeClip)',
      );
    }

    // ── 12) 같은 타입 트랙이 둘이어도 각자 몫을 받는다 ──
    //
    // `+악기` 는 같은 종류를 몇 번이든 더할 수 있다(막는 코드가 없다). 배열형은
    // "타입이 곧 슬롯"이라고 가정하는데, 트랙이 둘이면 그 가정이 깨진다 —
    // 예전엔 마지막 트랙만 `bySlot` 에 남아서 **두 번째 베이스는 스타일을
    // 바꿔도 믹스가 안 갱신됐고**, 씬에 남겨 둔 사용자 패턴도 하나가 다른
    // 하나를 덮어써 사라졌다.
    {
      final r = Project.initial()..setGenre('lofi'); // 배열형
      r.addTrack('bass'); // 베이스가 이제 둘
      final bassTracks = r.tracks.where((t) => t.type == 'bass').toList();
      check('12-a) 베이스 트랙이 둘', bassTracks.length == 2, '${bassTracks.length}개');
      final b0 = bassTracks[0], b1 = bassTracks[1];

      // 각자 다른 사용자 패턴을 물린다 — 씬 하나에 같은 타입 둘이 서로
      // 다른 걸 치는 상황을 그대로 재현한다.
      final name0 = r.makeEditable(b0);
      r.userNote[name0]!.notes
        ..clear()
        ..addAll([
          [1, 0, 4, 2],
        ]);
      final name1 = r.makeEditable(b1);
      r.userNote[name1]!.notes
        ..clear()
        ..addAll([
          [5, 4, 4, 2],
        ]);
      check(
        '12-b) 이름이 서로 다르다(같은 트랙 이름에서 나서 겹칠 뻔했다)',
        name0 != name1,
        '「$name0」 · 「$name1」',
      );

      r.setGenre('house'); // 다른 배열형으로

      final wantHouseBass = kGenreMix['house']!.parts['bass']!;
      // 배열형 사이의 전환은 트랙을 새로 안 만든다(같은 객체가 산다) —
      // b0·b1 을 그대로 다시 잰다.
      final bothUpdated = [b0, b1].every(
        (t) =>
            (t.vol - wantHouseBass.vol).abs() < 1e-9 &&
            (t.rev - wantHouseBass.rev).abs() < 1e-9,
      );
      check(
        '12-c) 베이스 둘 다 새 스타일 믹스를 받는다',
        bothUpdated,
        '${b0.name} vol=${b0.vol} rev=${b0.rev} · '
            '${b1.name} vol=${b1.vol} rev=${b1.rev} '
            '(바라는 값 vol=${wantHouseBass.vol} rev=${wantHouseBass.rev})',
      );

      // 각자 자기 패턴을 그대로 갖고 있어야 한다 — 하나가 다른 하나를
      // 덮어썼다면 여기서 둘이 같은 이름이 되거나 하나가 라이브러리 판으로
      // 떨어진다.
      final clip0 = r.scene.clips[b0.id];
      final clip1 = r.scene.clips[b1.id];
      check(
        '12-d) 두 베이스가 각자 자기 패턴을 지킨다(서로 안 덮어씀)',
        clip0 == name0 && clip1 == name1,
        '트랙0 「$clip0」(바라는 값 「$name0」) · 트랙1 「$clip1」(바라는 값 「$name1」)',
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '스타일 바꿔도 내 판 지키기 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
