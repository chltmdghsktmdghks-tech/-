// 5단계 12/N — 음 길이·세기·글라이드 확인.
//   flutter test test/editor_check_test.dart
//
// **눈이 속기 쉬운 자리다.** 편집기에서 막대를 늘려도 소리가 그대로일 수 있고
// (길이가 재생 이벤트까지 안 내려가는 경우), 세기를 바꿔도 저장을 건너뛰면
// 앱을 껐다 켜는 순간 없던 일이 된다. 그래서 화면을 믿지 않고
// **고친 값 → 실제 재생 이벤트(초·세기·글라이드) → 저장·불러오기** 까지 따라간다.
//
// 재생 이벤트 한 줄의 형식(sequencer.dart `SceneBuild.notes`):
//   [voice, freq, durSec, vel, soft, glide, delaySec, part]
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/edit_ops.dart';
import 'package:music_doodle_engine/theory.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/ui/editor_view.dart'
    show followTarget, headStep, kChordChoices;

void main() {
  test('음 길이·세기·글라이드', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final p = Project.initial();
    final tr = Transport();
    final mel = p.tracks.firstWhere((t) => t.type == 'melody');
    final name = p.makeEditable(mel); // 라이브러리 → 내 패턴 복사본
    final steps = p.barsOf('melody', name) * kStepsPerBar;

    void write(List<List<Object?>> list) => p.putUserPattern(
      'melody',
      name,
      note: NotePatternDef(
        name,
        p.barsOf('melody', name),
        p.barsOf('melody', name),
        list,
      ),
    );

    List<List<Object?>> read() => p.findNote('melody', name)!.notes;

    /// 이 트랙이 실제로 내는 소리들만 골라, 스텝 순으로.
    ///
    /// **구간 성격과 변형은 꺼 둔다.** 여기서 재는 것은 「편집기에서 만진 값이
    /// 재생 이벤트까지 그대로 가는가」다. 씬 이름이 코러스면 구간 성격이 세기를
    /// 한 단 올리므로(계획 6-3), 안 끄면 이 시험이 편곡을 재게 된다.
    List<List<dynamic>> played() {
      final b = SceneSequencer.build(p, tr, reps: 1, arrange: false);
      final part = b.busNames.indexOf(mel.id);
      return [
        for (final n in b.notes)
          if (n[7] == part) n,
      ]..sort((a, b) => (a[6] as double).compareTo(b[6] as double));
    }

    final stepSec = 60.0 / tr.bpm / 4;

    // 판을 비우고 내가 찍은 음 두 개만 남긴다 — 라이브러리 음이 섞이면 뭘 봤는지 모른다
    write(const []);
    write(NoteOps.add(read(), 0, 0, isChord: false, steps: steps)); // 낮은 음
    write(NoteOps.add(read(), 4, 4, isChord: false, steps: steps)); // 높은 음

    // 1) 길이 — 재생 이벤트의 '초'가 같이 길어져야 한다
    final durBefore = played()[1][2] as double;
    write(NoteOps.setLen(read(), 4, 4, 6, steps: steps));
    final durAfter = played()[1][2] as double;
    check(
      '1) 길이',
      (durBefore - 2 * stepSec).abs() < 1e-9 &&
          (durAfter - 6 * stepSec).abs() < 1e-9,
      '2칸 ${durBefore.toStringAsFixed(3)}초 → 6칸 ${durAfter.toStringAsFixed(3)}초',
    );

    // 2) 세기
    final velBefore = played()[1][3] as int;
    write(NoteOps.setVel(read(), 4, 4, 3));
    final velAfter = played()[1][3] as int;
    check(
      '2) 세기',
      velBefore == 2 && velAfter == 3,
      '보통 $velBefore → 세게 $velAfter',
    );

    // 3) 글라이드 — **앞 음의 높이**에서 미끄러져 들어와야 한다(0 이면 안 걸린 것)
    final glideOff = played()[1][5] as double;
    write(NoteOps.toggleGlide(read(), 4, 4, isChord: false));
    final ev = played();
    final glideOn = ev[1][5] as double;
    final prevFreq = ev[0][1] as double;
    check(
      '3) 글라이드',
      glideOff == 0 && (glideOn - prevFreq).abs() < 1e-6,
      '없음 $glideOff → ${glideOn.toStringAsFixed(1)}Hz(앞 음 ${prevFreq.toStringAsFixed(1)}Hz)',
    );

    // 4) 옮기기 — 갈 자리에 음이 있으면 **그대로 둔다**(덮어쓰면 음이 사라진다)
    final blocked = NoteOps.move(
      read(),
      0,
      0,
      4,
      steps: steps,
    ); // 4번 칸은 도수가 달라 빈 자리
    final samePlace = NoteOps.move(
      NoteOps.add(read(), 4, 5, isChord: false, steps: steps),
      4,
      4,
      1,
      steps: steps,
    );
    check(
      '4) 옮기기',
      blocked.any((n) => n[0] == 0 && n[1] == 4) &&
          samePlace.any((n) => n[0] == 4 && n[1] == 4),
      '빈 자리는 옮겨지고, 막힌 자리(4도 5칸)로는 안 감',
    );

    // 5) 코드 타입은 살아남아야 한다 — 코드 트랙의 5번째 칸은 글라이드가 아니라 **코드 이름**이다.
    //    여기가 깨지면 재즈 코드가 전부 평범한 3화음으로 바뀐다(소리로는 알아채기 어렵다).
    final jazz = findChordPattern('Jazz Keys H')!;
    var ch = [for (final n in jazz.notes) List<Object?>.from(n)];
    ch = NoteOps.setVel(ch, 1, 0, 3);
    ch = NoteOps.setLen(ch, 1, 0, 5, steps: 64);
    ch = NoteOps.toggleGlide(ch, 1, 0, isChord: true); // 코드는 아무 일도 없어야 한다
    check(
      '5) 코드 타입 보존',
      ch[0][4] == 'm7b5' && ch[0][3] == 3 && ch[0][2] == 5,
      '타입 ${ch[0][4]} · 세기 ${ch[0][3]} · 길이 ${ch[0][2]}칸',
    );

    // 6) 드럼 세기 — 저장·불러오기를 건너서도 남아야 한다
    final drum = p.tracks.firstWhere((t) => t.type == 'drum');
    final dName = p.makeEditable(drum);
    final d = DrumOps.read(p.findDrum(dName))
      ..add('snare', 3)
      ..setVel('snare', 3, 1) // 여리게 — 고스트 노트
      ..setVel('kick', 0, 1);
    p.putUserPattern(
      'drum',
      dName,
      drum: d.toDef(dName, p.barsOf('drum', dName)),
    );
    final reloaded = Project.initial()..loadJson(p.toJson());
    final back = buildDrumPattern(reloaded.findDrum(dName)!);
    final ghost = back.firstWhere((h) => h.lane == 'snare' && h.step == 3);
    final kick0 = back.where((h) => h.lane == 'kick' && h.step == 0).toList();
    check(
      '6) 드럼 세기 저장',
      ghost.vel == 1 && (kick0.isEmpty || kick0.first.vel == 1),
      '스네어 3칸 세기 ${ghost.vel}(여리게) · 킥 첫 칸 ${kick0.isEmpty ? '없음' : kick0.first.vel}',
    );

    // 7) 라이브러리 패턴은 **그대로** — 세기를 안 만진 패턴은 웹과 같은 소리여야 한다
    final lib = findDrumPattern('Lofi Chorus')!;
    final hits = buildDrumPattern(lib);
    final hats = [
      for (final h in hits)
        if (h.lane == 'hat') h,
    ]..sort((a, b) => a.step.compareTo(b.step));
    final okHat = hats.every((h) => h.vel == defaultDrumVel('hat', h.step));
    check(
      '7) 라이브러리 기본 세기',
      lib.vels == null && okHat && hats.isNotEmpty,
      '하이햇 ${hats.length}타 — 박머리 2 / 사이 1 규칙 그대로',
    );

    // 8) 마디를 줄이면 꼬리도 잘린다 — 안 자르면 다음 판 첫 박에 소리가 겹친다
    final long = NoteOps.setLen(
      NoteOps.add(const [], 0, 28, isChord: false, steps: 64),
      0,
      28,
      8,
      steps: 64,
    );
    final cut = NoteOps.trimTo(long, 32);
    check('8) 마디 줄이기', cut.first[2] == 4, '28칸에서 8칸 → ${cut.first[2]}칸(32칸까지)');

    // 9) 코드 줄의 **층**을 새 음도 따라간다 (theory.dart `voiceLead` 의 oct)
    //
    // 위층을 맡는 줄(재즈 비브라폰·팝 스트링)에 음을 하나 찍었는데 그것만 한 옥타브
    // 아래로 떨어지면, 그 음만 패드와 겹쳐 탁해진다. 눈으로는 안 보이는 종류다.
    {
      final high = <List<Object?>>[
        [0, 0, 8, 2, 'min7', 1],
        [5, 16, 8, 2, 'maj7', 1],
      ];
      final added = NoteOps.add(high, 3, 32, isChord: true, steps: 64);
      final made = added.last;
      check(
        '9) 코드 줄의 층을 새 음도 따라간다',
        NoteOps.chordOct(high) == 1 &&
            made.length > 5 &&
            made[5] == 1 &&
            NoteOps.chordOct(const [
                  [0, 0, 8, 2],
                ]) ==
                0,
        '위층 줄에 찍은 음 → 층 ${made.length > 5 ? made[5] : 0} · 보통 줄은 0',
      );
    }

    // ── 재생 막대 따라가기 ──
    //
    // 4마디 판은 64칸 × 30px = **1920px** 인데 화면에 보이는 건 280px 남짓이다.
    // 그래서 재생을 눌러도 재생 막대가 **시간의 85% 를 화면 밖에** 있었다.
    // 여기서는 「어디로 밀지 정하는 규칙」만 본다(스크롤 자체는 화면 쪽 일이다).
    {
      const vp = 280.0, maxS = 1920.0 - 280.0;
      // 1) 보이는 폭 한가운데면 안 민다 — 매 프레임 밀어 대면 못 쓴다
      check(
        '따라가기 1) 보이면 가만둔다',
        followTarget(x: 140, offset: 0, viewport: vp, maxScroll: maxS) ==
                null &&
            followTarget(x: 500, offset: 400, viewport: vp, maxScroll: maxS) ==
                null,
        '가운데·가장자리 안쪽 둘 다 null',
      );

      // 2) 오른쪽으로 벗어나면 **왼쪽 15% 자리로** 끌어온다.
      //    0 에 갖다 놓으면 다음 순간 또 나간다(그래서 15%).
      final r = followTarget(x: 600, offset: 0, viewport: vp, maxScroll: maxS);
      check(
        '따라가기 2) 오른쪽으로 나가면 끌어온다',
        r != null && (r - (600 - vp * 0.15)).abs() < 0.01,
        '$r',
      );

      // 3) 판이 한 바퀴 돌아 처음으로 가면 뒤로도 따라간다
      final b = followTarget(x: 0, offset: 1000, viewport: vp, maxScroll: maxS);
      check('따라가기 3) 처음으로 돌아가면 뒤로도', b != null && b == 0.0, '$b');

      // ── 코드 종류 고르기 ──
      //
      // `theory.dart` 는 스물넷을 알고 라이브러리 패턴도 쓰는데, **편집기에서
      // 고를 길이 없어서** 직접 찍는 코드는 무엇을 찍어도 기본 3화음뿐이었다.
      {
        final src = <List<Object?>>[
          [0, 0, 8, 2],
          [3, 16, 8, 2, null, 1], // 층(6번째 칸)이 있는 자리
        ];
        final m7 = NoteOps.setChordType(src, 0, 0, 'min7', isChord: true);
        final back = NoteOps.setChordType(m7, 0, 0, null, isChord: true);
        final withOct = NoteOps.setChordType(src, 3, 16, 'maj7', isChord: true);
        // 음정 줄에서는 5번째 칸이 **글라이드**다 — 건드리면 안 된다
        final notChord = NoteOps.setChordType(
          src,
          0,
          0,
          'min7',
          isChord: false,
        );
        check(
          '코드 1) 종류를 넣고 뺀다',
          NoteOps.chordTypeOf(m7[0]) == 'min7' &&
              NoteOps.chordTypeOf(back[0]) == null &&
              NoteOps.chordTypeOf(notChord[0]) == null,
          '넣기 ${NoteOps.chordTypeOf(m7[0])} → 빼기 ${NoteOps.chordTypeOf(back[0])} · '
              '음정 줄 ${NoteOps.chordTypeOf(notChord[0])}',
        );
        check(
          '코드 2) 층(6번째 칸)을 안 밀어낸다',
          NoteOps.chordTypeOf(withOct[1]) == 'maj7' &&
              withOct[1].length > 5 &&
              withOct[1][5] == 1,
          '종류 ${NoteOps.chordTypeOf(withOct[1])} · 층 ${withOct[1].length > 5 ? withOct[1][5] : '없어짐'}',
        );
        // 넣은 종류가 **실제로 그 코드로 울리는가** — 여기가 끊기면 화면만 바뀐다
        {
          final def = NotePatternDef('시험', 1, 1, [
            [0, 0, 8, 2, 'min7'],
          ]);
          const key = MusicKey(root: 0, mode: 'minor');
          final hits = buildChordPattern(def, key);
          final plain = buildChordPattern(
            NotePatternDef('시험', 1, 1, [
              [0, 0, 8, 2],
            ]),
            key,
          );
          check(
            '코드 3) 고른 종류가 소리까지 간다',
            hits.isNotEmpty &&
                plain.isNotEmpty &&
                hits.first.freqs.length == plain.first.freqs.length + 1,
            'm7 ${hits.first.freqs.length}음 · 기본 ${plain.first.freqs.length}음',
          );
        }
        // 목록에 적은 이름이 **실제로 있는 종류**여야 한다 — 오타면 조용히 3화음이 된다
        final unknown = [
          for (final (k, _) in kChordChoices)
            if (k != null && !kChordTypeIntervals.containsKey(k)) k,
        ];
        check(
          '코드 4) 목록에 모르는 이름이 없다',
          unknown.isEmpty,
          unknown.isEmpty ? '${kChordChoices.length}가지 전부' : unknown.join(', '),
        );
      }

      // ── 전체 음 길이 늘이고 줄이기 ──
      //
      // 음을 하나씩 골라 「칸 +」를 누르면 20음짜리는 20번이다. 베이스·패드를
      // 스타카토 ↔ 레가토로 통째로 바꾸는 손잡이라 한 번에 되어야 한다.
      {
        // 같은 줄(도수 0)에 4칸 간격으로 셋 — 늘리면 서로 부딪힌다
        final src = <List<Object?>>[
          [0, 0, 1, 2],
          [0, 4, 1, 2],
          [0, 8, 1, 2],
          [3, 30, 1, 2], // 다른 줄 · 판 끝 가까이
        ];
        final up = NoteOps.stretchAll(src, 1, steps: 32);
        final up2 = NoteOps.stretchAll(up, 1, steps: 32);
        final down = NoteOps.stretchAll(up, -1, steps: 32);
        final floor = NoteOps.stretchAll(down, -1, steps: 32);
        check(
          '길이 1) 전체가 한 칸씩 늘고 준다',
          up.every((n) => n[2] == 2) &&
              down.every((n) => n[2] == 1) &&
              floor.every((n) => n[2] == 1),
          '1→${up[0][2]}→${down[0][2]} · 바닥 ${floor[0][2]}칸',
        );
        check(
          '길이 2) 같은 줄 다음 음에 안 부딪힌다',
          up2[0][2] == 3 && up2[1][2] == 3 && up2[2][2] == 3,
          '0번 ${up2[0][2]}칸 · 4번 ${up2[1][2]}칸 (사이가 4칸이라 최대 4)',
        );
        // 32칸 판의 30번 자리 음은 2칸을 넘을 수 없다
        var last = <List<Object?>>[
          [3, 30, 1, 2],
        ];
        for (var i = 0; i < 6; i++) {
          last = NoteOps.stretchAll(last, 1, steps: 32);
        }
        check(
          '길이 3) 판 끝을 안 넘는다',
          last[0][2] == 2,
          '30번 칸 음이 ${last[0][2]}칸 (판은 32칸)',
        );
        check(
          '길이 4) 원본을 안 건드린다',
          src[0][2] == 1,
          '원본 ${src[0][2]}칸 (복사본만 바뀌어야 한다)',
        );
      }

      // ── 3-b) **막대가 가리키는 칸이 실제로 울리는 칸인가** ──
      //
      // 엔진이 주는 `pos`(0~1)의 기준자는 **씬 루프 한 바퀴**다 — 그 씬에서 들리는
      // 트랙 중 제일 긴 패턴에 맞춘다. 그런데 격자는 **지금 고치는 패턴**이다.
      // 2마디 드럼을 고치는데 씬에 4마디 패드가 있으면 루프는 4마디 —
      // 그대로 `pos * steps` 를 쓰면 막대가 소리의 **절반 속도**로 기어간다.
      // (격자를 한 바퀴 도는 동안 소리는 두 바퀴 돈다. 최대 한 마디까지 벌어진다)
      {
        // 2마디(32칸) 격자 · 루프는 4마디
        double h(double pos) => headStep(pos, steps: 32, loopBars: 4);
        final quarter = h(0.25); // 루프의 1/4 = 1마디 지점 → 격자 16칸
        final half = h(0.5); // 루프의 절반 = 2마디 → 격자를 한 바퀴 → 0
        final threeQ = h(0.75); // 3마디 → 16
        // 루프와 격자가 같은 길이면 예전 식과 같아야 한다
        final same = headStep(0.25, steps: 32, loopBars: 2);
        // 루프 마디 수를 모르면(정지 중) 옛 식으로 물러난다
        final fallback = headStep(0.25, steps: 32, loopBars: 0);
        check(
          '따라가기 3-b) 막대를 격자 칸으로 되접는다',
          (quarter - 16).abs() < 1e-9 &&
              half.abs() < 1e-9 &&
              (threeQ - 16).abs() < 1e-9 &&
              (same - 8).abs() < 1e-9 &&
              (fallback - 8).abs() < 1e-9,
          '2마디 격자·4마디 루프에서 1/4→${quarter.round()}칸 · '
              '1/2→${half.round()}칸 · 3/4→${threeQ.round()}칸 '
              '(같은 길이면 ${same.round()}칸)',
        );
      }

      // 4) 끝은 넘지 않는다 — 격자 오른쪽 밖의 흰 공간을 보여 주면 안 된다
      final e = followTarget(x: 1900, offset: 0, viewport: vp, maxScroll: maxS);
      check('따라가기 4) 끝을 넘지 않는다', e == maxS, '$e / $maxS');

      // 5) 밀 데가 없으면(다 보이는 짧은 판) 아무 일도 안 한다
      check(
        '따라가기 5) 다 보이면 손대지 않는다',
        followTarget(x: 100, offset: 0, viewport: 500, maxScroll: 0) == null,
        '스크롤 자체가 없는 판',
      );
    }

    // ── 편집기를 열면 반복 마디가 사라지지 않는다 ──
    //
    // 라이브러리 패턴 중엔 `bars > src` 인 것이 많다(1마디를 두 번 돌려 2마디를
    // 채우는 식). `makeEditable`(project.dart)이 라이브러리 패턴을 사용자 패턴으로
    // **복사**할 때, 되풀이되는 뒷마디를 실제로 펼치지 않고 `src=bars` 라고만
    // 표시해 버리면 뒷마디가 통째로 조용해진다 — 편집기를 열기만 해도, 저장은
    // 하지 않아도 일어난다(2026-09-03 워크플로 사냥에서 잡았다).
    {
      final p2 = Project.initial();
      final drumT = p2.tracks.firstWhere((t) => t.type == 'drum');
      final bassT = p2.tracks.firstWhere((t) => t.type == 'bass');

      // 'Boom Bap' — 킥 세 방(0·7·10)이 1마디(src=1)라 2마디(bars=2)를 채우려면
      // 두 번 돈다. 펼치지 않으면 두 번째 마디(16~31칸)가 빈다.
      p2.setClip(drumT, 'Boom Bap');
      final dName = p2.makeEditable(drumT);
      final dDef = p2.userDrum[dName]!;
      check(
        '편집 1) 드럼 — bars·src 가 실제로 펼쳐진 마디 수와 같다',
        dDef.bars == 2 && dDef.src == 2,
        '${dDef.bars}·${dDef.src} (바라는 값 2·2)',
      );
      final kickSteps = List<int>.from(dDef.hits['k'] ?? const []);
      check(
        '편집 2) 드럼 — 두 번째 마디의 킥이 살아 있다',
        kickSteps.contains(16) &&
            kickSteps.contains(23) &&
            kickSteps.contains(26),
        '킥 자리 $kickSteps (16·23·26 이 있어야 두 번째 마디가 산다)',
      );
      // 실제 재생에서도 두 마디분(6방) 다 나오는지 — 화면 값만 맞고 소리는
      // 그대로일 수 있다는 이 파일의 첫 줄 원칙을 여기도 지킨다.
      final dHits = buildDrumPattern(dDef);
      final dKicks = dHits.where((h) => h.lane == 'kick').length;
      check('편집 3) 드럼 — 재생 이벤트도 6방(2마디×3)', dKicks == 6, '$dKicks방');

      // 'Root 8ths' — 베이스 8분음표 라인, 1마디(src=1)를 2마디(bars=2)로 편다.
      p2.setClip(bassT, 'Root 8ths');
      final bName = p2.makeEditable(bassT);
      final bDef = p2.userNote[bName]!;
      check(
        '편집 4) 베이스 — bars·src 가 실제로 펼쳐진 마디 수와 같다',
        bDef.bars == 2 && bDef.src == 2,
        '${bDef.bars}·${bDef.src} (바라는 값 2·2)',
      );
      final steps = [for (final n in bDef.notes) n[1] as int]..sort();
      final hasSecondBar = steps.any((s) => s >= 16);
      check('편집 5) 베이스 — 두 번째 마디에도 음이 있다', hasSecondBar, '스텝 $steps');
      // 두 마디분 음 개수가 원본 라이브러리 패턴(펼치기 전)의 배와 같아야 한다
      final origBass = findBassPattern('Root 8ths')!;
      check(
        '편집 6) 베이스 — 음 개수가 원본의 두 배(두 바퀴)',
        bDef.notes.length == origBass.notes.length * 2,
        '${bDef.notes.length}개 (원본 ${origBass.notes.length}개 × 2)',
      );

      // ── 베이스에서 만든 패턴이 코드·멜로디 고르기에 새어 들지 않는다 ──
      //
      // `userNote` 는 베이스·코드·멜로디가 한 표를 같이 쓴다(이름만으로 구분).
      // 타입을 안 걸러 내면 방금 만든 베이스 패턴(`bName`)이 코드·멜로디
      // 트랙의 패턴 고르기에도 그대로 떴다 — 골라도 오류는 안 나고
      // (`findNote` 가 트랙 타입과 안 맞는 것도 그냥 돌려줬다) 소리만 틀렸다.
      final chordNames = SceneSequencer.patternNamesFor(p2, 'chord');
      final melodyNames = SceneSequencer.patternNamesFor(p2, 'melody');
      final bassNames = SceneSequencer.patternNamesFor(p2, 'bass');
      check(
        '편집 7) 베이스 패턴이 코드 고르기엔 안 뜬다',
        !chordNames.contains(bName),
        chordNames.contains(bName) ? '떴음 — 새어 들었다' : '안 뜸',
      );
      check(
        '편집 8) 베이스 패턴이 멜로디 고르기엔 안 뜬다',
        !melodyNames.contains(bName),
        melodyNames.contains(bName) ? '떴음 — 새어 들었다' : '안 뜸',
      );
      check(
        '편집 9) 베이스 패턴은 베이스 고르기엔 뜬다',
        bassNames.contains(bName),
        bassNames.contains(bName) ? '뜸' : '안 뜸',
      );

      // 억지로 코드 트랙에 베이스 패턴 이름을 물려도(예전 곡이 이미 그렇게
      // 저장돼 있을 수 있다) **틀린 음을 내느니 조용한 편**이 맞다 —
      // findNote 가 타입이 안 맞으면 못 찾은 것으로 친다.
      check(
        '편집 10) 타입이 안 맞으면 findNote 가 안 돌려준다',
        p2.findNote('chord', bName) == null,
        p2.findNote('chord', bName) == null ? 'null(맞음)' : '틀린 타입인데 돌려줌',
      );

      // 반대로 옛 곡(타입을 몰랐던 시절 저장분)은 **여전히 통과**해야 한다 —
      // 이 표가 생기기 전에는 다 이렇게 동작했다.
      p2.userNoteType.remove(bName);
      check(
        '편집 11) 타입을 모르면(옛 곡) 그대로 통과',
        p2.findNote('chord', bName) != null &&
            SceneSequencer.patternNamesFor(p2, 'chord').contains(bName),
        '모르는 이름은 예전처럼 다 통과해야 한다',
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '음 길이·세기·글라이드 확인 통과' : '실패 $fail건');
    // **종류 칩이 덧음·밑음을 안 지운다.** 서랍에서 붙인 텐션이 칩 한 번에 날아가면
    // 「공들인 것이 사라졌다」가 된다 — 짝이 하나 없는 그 모양이다.
    {
      final n = <List<Object?>>[
        [0, 0, 8, 2, 'min7+t9/4'],
      ];
      final kept = buildChordText(
        'maj7',
        NoteOps.chordTensionsOf(n[0]),
        NoteOps.chordBassOf(n[0]),
      );
      check('코드 5) 종류만 바꿔도 덧음이 남는다', kept == 'maj7+t9/4', '$kept');
    }

    expect(fail, 0);
  });
}
