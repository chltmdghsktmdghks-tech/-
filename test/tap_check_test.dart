// 5단계 46/N — 「두드려 넣기」의 **계산**을 잰다.
//   flutter test test/tap_check_test.dart
//
// 화면은 `tap_ui_test.dart` 가 본다. 여기서 보는 건 셋이다:
//  · 손가락이 닿은 순간이 **몇 번째 칸**이 되는가 (되접기·지연·칸 맞추기)
//  · 누르고 있던 동안이 **몇 칸 길이**가 되는가
//  · 처음 높이가 **정말 그 코드에 어울리는 음**인가 — 표가 아니라 **주파수**로 본다
//
// 제일 무서운 것은 첫째다. 재생 막대(`headStep`)와 두드림(`stepOf`)이 **다른 규칙**을
// 쓰면, 막대를 보면서 쳤는데 딴 칸에 찍힌다. 그러면 사람은 자기 박자를 의심한다.
// 그래서 둘을 **맞대 본다** — 「말없이 어긋난 두 표」가 제일 나기 쉬운 자리다.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/prog_ops.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/tap_rec.dart';
import 'package:music_doodle_engine/theory.dart';
import 'package:music_doodle_engine/ui/editor_view.dart' show headStep;

void main() {
  _more();
  _clock();
  test('두드려 넣기 계산', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    // 1) **재생 막대와 같은 칸을 가리킨다.**
    //    판보다 루프가 긴 경우(2마디 판 · 4마디 루프)까지 넣는다 — 되접기를 안 하면
    //    거기서 두 배로 샌다.
    var worst = 0.0;
    var samples = 0;
    for (final (bars, loopBars) in const [(1, 1), (2, 2), (2, 4), (4, 4), (4, 8)]) {
      final steps = bars * kStepsPerBar;
      final rec = TapRecorder(
        steps: steps,
        loopBars: loopBars,
        loopSec: 8.0,
        snap: TapSnap.sixteenth, // 칸 맞추기 없이(1칸 단위) 순수 되접기만 본다
      );
      for (var i = 0; i < 400; i++) {
        final pos = i / 400.0;
        final mine = rec.stepOf(pos);
        final head = headStep(pos, steps: steps, loopBars: loopBars);
        // 막대는 칸 안의 어디쯤(소수)까지 알려 준다 — 반올림해서 맞대면 된다
        final want = head.round() % steps;
        final d = (mine - want).abs();
        if (d > worst) worst = d.toDouble();
        samples++;
      }
    }
    check(
      '1) 두드린 칸 = 재생 막대가 가리키는 칸',
      worst == 0,
      '$samples자리 · 제일 많이 어긋난 곳 ${worst.round()}칸',
    );

    // 2) **칸 맞추기가 정말 붙는다.** 8분이면 결과가 전부 짝수 칸이어야 한다 —
    //    초보가 두드리면 16분으로는 거의 늘 어긋나서 리듬이 삐뚤어진다.
    final r8 = TapRecorder(steps: 64, loopBars: 4, loopSec: 8.0);
    var odd = 0;
    for (var i = 0; i < 500; i++) {
      if (r8.stepOf(i / 500.0) % 2 != 0) odd++;
    }
    check('2) 8분으로 맞추면 홀수 칸이 없다', odd == 0, '홀수 칸 $odd개 / 500');

    final r16 = TapRecorder(
      steps: 64,
      loopBars: 4,
      loopSec: 8.0,
      snap: TapSnap.sixteenth,
    );
    final got16 = {for (var i = 0; i < 500; i++) r16.stepOf(i / 500.0)};
    check('2-b) 16분은 64칸을 다 쓴다', got16.length == 64, '${got16.length}칸');

    // 3) **늦게 잡히는 것을 되돌린다.**
    //    귀에 닿는 소리는 앞질러 만든 양만큼 늦다 → "제때 쳤다"고 느낀 순간의 위치는
    //    실제보다 그만큼 뒤다. 그대로 반올림하면 **한 칸씩 밀린 판**이 나온다.
    const loopSec = 8.0;
    const lat = 3072 / 48000.0; // 64ms — 실제 값
    final rl = TapRecorder(
      steps: 64,
      loopBars: 4,
      loopSec: loopSec,
      snap: TapSnap.sixteenth,
      latencySec: lat,
    );
    // 0칸을 노렸는데 지연만큼 늦게 잡힌 순간
    final late0 = lat / loopSec;
    check('3) 늦게 잡힌 것이 제자리로', rl.stepOf(late0) == 0, '${rl.stepOf(late0)}칸');
    // 되돌리지 않으면 어디에 찍히나 — 밀린다는 것을 같이 보여 준다
    final noFix = TapRecorder(
      steps: 64,
      loopBars: 4,
      loopSec: loopSec,
      snap: TapSnap.sixteenth,
    );
    check(
      '3-b) 안 되돌리면 밀린다(그래서 되돌린다)',
      noFix.stepOf(late0) != 0,
      '되돌리기 없으면 ${noFix.stepOf(late0)}칸',
    );

    // 4) **길이는 잡고 있던 만큼.** 한 판 4마디(64칸)를 8초로 잡으면 한 칸 = 0.125초.
    final rlen = TapRecorder(
      steps: 64,
      loopBars: 4,
      loopSec: 8.0,
      snap: TapSnap.sixteenth,
    );
    check('4) 8칸 잡으면 8칸', rlen.lenOf(0.0, 8 / 64) == 8, '${rlen.lenOf(0.0, 8 / 64)}칸');
    check('4-b) 톡 친 것도 남는다', rlen.lenOf(0.5, 0.5) == 1, '${rlen.lenOf(0.5, 0.5)}칸');
    // 8분으로 맞추면 톡 친 것도 8분(2칸)이 바닥이다 — 들리는 길이가 자를 따라간다
    check('4-c) 8분이면 바닥이 2칸', r8.lenOf(0.5, 0.5) == 2, '${r8.lenOf(0.5, 0.5)}칸');
    // 판을 넘겨 뗐다 — 음수가 되면 안 된다
    check(
      '4-d) 판을 넘겨 떼도 성하다',
      rlen.lenOf(0.95, 0.05) == (0.10 * 64).round(),
      '${rlen.lenOf(0.95, 0.05)}칸',
    );

    // 5) **한 바퀴가 끝났는데 아직 누르고 있는 것** — 거기서 끊어 담는다.
    //    안 담으면 마지막 음이 통째로 사라진다(꾹 누른 마지막 음일수록 중요하다).
    final rc = TapRecorder(steps: 32, loopBars: 2, loopSec: 4.0);
    rc.down(0, 0.0);
    rc.up(0, 4 / 32);
    rc.down(0, 0.5);
    check('5) 안 뗀 것은 아직 없다', rc.count == 1, '${rc.count}개');
    rc.closeAll(0.75);
    check('5-b) 끝날 때 끊어 담는다', rc.count == 2, '${rc.count}개');

    // 6) **같은 자리를 두 번 치면 하나.** 겹쳐 담으면 소리가 두 겹이 된다.
    final rd = TapRecorder(steps: 32, loopBars: 2, loopSec: 4.0);
    rd.down(0, 0.0);
    rd.up(0, 0.01);
    rd.down(0, 0.002); // 같은 칸
    rd.up(0, 0.01);
    check('6) 같은 칸은 하나', rd.count == 1, '${rd.count}개');

    // 6-b) 뗀 적 없는 손가락은 아무 일도 안 한다(화면 밖에서 들어온 손가락)
    final re = TapRecorder(steps: 32, loopBars: 2, loopSec: 4.0);
    re.up(3, 0.5);
    check('6-b) 누른 적 없으면 안 담는다', re.count == 0, '${re.count}개');

    // 7) **드럼 판 넷은 진짜 있는 레인이다.** 이름이 하나만 틀려도 그 판은 무음이다
    //    (셰이커·카우벨이 16% 무음이었던 것이 바로 이 종류다).
    final bad = [
      for (final (lane, _) in kTapDrumPads)
        if (!kDrumLanes.contains(lane)) lane,
    ];
    check('7) 두드릴 드럼 넷이 다 있는 레인', bad.isEmpty, bad.isEmpty ? '4개 다 성함' : '$bad');

    // ── 8~10) 처음 높이 ──
    //
    // 코드 판: 0칸에 1도(0), 16칸에 4도(3), 32칸에 5도(4), 48칸에 1도(0).
    final prog = readProg(const [
      [0, 0, 7, 2],
      [3, 16, 7, 2],
      [4, 32, 7, 2],
      [0, 48, 7, 2],
    ], 64);

    int deg(int step, {String type = 'melody', bool chord = false, bool chro = false}) =>
        tapDegree(
          prog: prog,
          progSteps: 64,
          step: step,
          type: type,
          chord: chord,
          chromatic: chro,
          mode: 'minor',
        );

    check(
      '8) 코드를 따라간다',
      deg(0, chord: true) == 0 &&
          deg(20, chord: true) == 3 &&
          deg(40, chord: true) == 4 &&
          deg(60, chord: true) == 0,
      '0·20·40·60칸 → ${deg(0, chord: true)}·${deg(20, chord: true)}·'
          '${deg(40, chord: true)}·${deg(60, chord: true)}도',
    );

    // 8-b) **코드 판이 이 판보다 짧아도** 되접어 찾는다
    check(
      '8-b) 판보다 짧은 코드도 되접는다',
      deg(64 + 20, chord: true) == 3,
      '84칸 → ${deg(84, chord: true)}도 (코드 판은 64칸)',
    );

    // 8-c) 코드 트랙이 없는 씬 — 1도로 놓는다(조의 중심이라 안 튄다)
    final none = tapDegree(
      prog: const [],
      progSteps: 0,
      step: 7,
      type: 'melody',
      chord: false,
      chromatic: false,
      mode: 'minor',
    );
    check('8-c) 코드가 없으면 1도', none == 7, '$none (가락 줄의 1도)');

    // 9) **좌표계 밖으로 안 나간다.** 줄 수가 셋 다 다르다(화음 7 · 낱음 15 · 반음 25).
    var over = 0;
    for (var s = 0; s < 64; s++) {
      if (deg(s, chord: true) < 0 || deg(s, chord: true) > 6) over++;
      if (deg(s) < 0 || deg(s) > 14) over++;
      if (deg(s, type: 'bass') < 0 || deg(s, type: 'bass') > 14) over++;
      if (deg(s, chro: true) < 0 || deg(s, chro: true) >= kProRows) over++;
    }
    check('9) 줄 밖으로 안 나간다', over == 0, '벗어난 곳 $over개 / 256');

    // 10) **정말 그 코드에 어울리는 음인가 — 주파수로 본다.**
    //     "코드의 뿌리음을 쓴다"고 적어 두는 것과 그 소리가 나는 것은 다른 일이다.
    //     도수를 주파수로 바꿔서, 그 자리 코드의 음 하나와 **옥타브까지 접어** 맞는지 본다.
    for (final root in [0, 3, 7, 10]) {
      for (final mode in ['minor', 'major']) {
        final key = MusicKey(root: root, mode: mode);
        final chords = diatonicChords(key);
        var miss = 0;
        for (var s = 0; s < 64; s += 4) {
          final cd = tapDegree(
            prog: prog,
            progSteps: 64,
            step: s,
            type: 'melody',
            chord: false,
            chromatic: false,
            mode: mode,
          );
          final f = degreeFreq(cd, 'melody', key);
          final want = chordFreqsOf(chords[deg(s, chord: true) % 7]);
          // 옥타브가 다를 수 있다 — 반음 수로 접어서 견준다
          final mySemi = (12 * (_log2(f / 440.0)) + 0.5).floor() % 12;
          final ok = want.any(
            (w) => (12 * _log2(w / 440.0) + 0.5).floor() % 12 == mySemi,
          );
          if (!ok) miss++;
        }
        check(
          '10) 그 자리 코드 안의 음이다 ($root/$mode)',
          miss == 0,
          '어긋난 자리 $miss개 / 16',
        );
      }
    }

    // ignore: avoid_print
    print(fail == 0 ? '두드려 넣기 계산 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}

void _more() {
  test('두드린 것이 판에 담긴다', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final prog = readProg(const [
      [0, 0, 7, 2],
      [4, 16, 7, 2],
    ], 32);

    List<List<Object?>> put(
      List<List<Object?>> was,
      List<TapHit> hits, {
      bool clear = false,
      int steps = 32,
    }) => tapToNotes(
      was,
      hits,
      prog: prog,
      progSteps: 32,
      steps: steps,
      type: 'melody',
      chord: false,
      chromatic: false,
      mode: 'minor',
      clear: clear,
    );

    final was = <List<Object?>>[
      [3, 4, 2, 2],
      [5, 12, 2, 2],
    ];

    // 11) **위에 더하기** — 있던 것이 그대로 있다
    final added = put(was, const [TapHit(0, 0, 4), TapHit(0, 20, 2)]);
    check(
      '11) 더하면 있던 것이 남는다',
      added.length == 4 && added.any((n) => n[0] == 3 && n[1] == 4),
      '${was.length}개 + 2개 → ${added.length}개',
    );
    // 원본은 안 건드린다 — 되돌리기가 여기에 기대고 있다
    check('11-b) 원본은 그대로', was.length == 2, '원본 ${was.length}개');

    // 12) **지우고 시작** — 두드린 것만 남는다
    final fresh = put(was, const [TapHit(0, 0, 4), TapHit(0, 20, 2)], clear: true);
    check('12) 지우고 시작하면 둘뿐', fresh.length == 2, '${fresh.length}개');

    // 13) **칸 순서로 담긴다** — 편집기가 읽는 순서와 같아야 한다
    final sorted = [for (final n in added) n[1] as int];
    final want = [...sorted]..sort();
    check('13) 칸 순서', '$sorted' == '$want', '$sorted');

    // 14) **꼬리가 판을 넘지 않는다.** 넘긴 채로 두면 다음 바퀴 첫 음과 겹쳐 울린다.
    final tail = put(const [], const [TapHit(0, 30, 16)]);
    check('14) 꼬리를 자른다', tail.first[2] == 2, '30칸에서 16칸 → ${tail.first[2]}칸');

    // 15) **판 밖은 안 담는다** (2마디 판에 4마디짜리 두드림이 섞여 들어오는 경우)
    final over = put(const [], const [TapHit(0, 40, 2), TapHit(0, 8, 2)]);
    check('15) 판 밖은 버린다', over.length == 1 && over.first[1] == 8, '${over.length}개');

    // 16) **높이는 그 자리 코드를 따라간다** — 0칸은 1도, 20칸은 5도.
    check(
      '16) 자리마다 코드를 따라간다',
      added.firstWhere((n) => n[1] == 0)[0] == 7 &&
          added.firstWhere((n) => n[1] == 20)[0] == 11,
      '0칸 ${added.firstWhere((n) => n[1] == 0)[0]}도 · '
          '20칸 ${added.firstWhere((n) => n[1] == 20)[0]}도',
    );

    // ── 17) **정말 소리가 나는가** ──
    // 판에 적히는 것과 엔진이 내는 것은 다른 일이다. 두드린 것을 실제 곡에 넣고
    // 시퀀서가 뽑는 **주파수**를 센다. 「적어 놓은 것」만 보면 무음인 층을 못 본다.
    final p = Project.initial();
    final mel = p.tracks.firstWhere((t) => t.type == 'melody');
    final nm = p.makeEditable(mel);
    final def = p.findNote('melody', nm)!;
    final steps = def.bars * kStepsPerBar;
    final (sprog, sprogSteps) = p.readSceneProg();
    final hits = [
      for (var s = 0; s < steps; s += 4) TapHit(0, s, 2),
    ];
    p.putUserPattern(
      'melody',
      nm,
      note: def.copyWith(
        notes: tapToNotes(
          const [],
          hits,
          prog: sprog,
          progSteps: sprogSteps,
          steps: steps,
          type: 'melody',
          chord: false,
          chromatic: false,
          mode: 'minor',
        ),
      ),
    );
    final tr = Transport();
    final built = SceneSequencer.build(p, tr, reps: 1);
    final mine = [
      for (final n in built.notes)
        if (n[0] == mel.voice) n,
    ];
    check(
      '17) 두드린 수만큼 소리가 난다',
      mine.length == hits.length,
      '두드림 ${hits.length}개 → 소리 ${mine.length}개',
    );
    check(
      '17-b) 다 들리는 주파수다',
      mine.every((n) => (n[1] as double) > 20 && (n[1] as double) < 20000),
      mine.isEmpty
          ? '없음'
          : '${(mine.first[1] as double).round()}~${(mine.last[1] as double).round()}Hz',
    );

    // ignore: avoid_print
    print(fail == 0 ? '두드린 것 담기 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}

/// 대목이 바뀐 자리를 **초 단위**로 적어 둔 것.
class _Mark {
  final TapPhase phase;
  final double sec;
  const _Mark(this.phase, this.sec);
  @override
  String toString() => '$phase@${sec.toStringAsFixed(2)}s';
}

/// 화면이 하는 것과 **같은 방식**으로 굴린다 — 30ms 마다 루프 안 위치를 넣는다.
/// [startBeat] 은 창을 연 순간이 루프 안 몇 박째인가(마디 중간에서 열 수도 있다).
List<_Mark> _drive({
  required int loopBars,
  required int bars,
  required double bpm,
  required double startBeat,
  double forSec = 40,
  double stepSec = 0.03,
}) {
  final beatsPerLoop = loopBars * 4;
  final beatSec = 60.0 / bpm;
  final loopSec = beatsPerLoop * beatSec;
  final c = TapClock(beatsPerLoop: beatsPerLoop, lapBeats: bars * 4);
  final out = <_Mark>[];
  var t = startBeat * beatSec;
  for (var i = 0; i * stepSec < forSec; i++) {
    final pos = (t % loopSec) / loopSec;
    if (c.update(pos * beatsPerLoop)) {
      out.add(_Mark(c.phase, t - startBeat * beatSec));
    }
    if (c.phase == TapPhase.done) break;
    t += stepSec;
  }
  return out;
}

void _clock() {
  test('대목이 제때 흘러간다', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    // 1) **마디 중간에 열면 다음 마디 첫 박까지 기다린다.**
    //    박 중간에 「넷」이 시작되면 그 넷이 음악과 안 맞는다.
    {
      const bpm = 120.0, beat = 0.5; // 한 박 0.5초
      final m = _drive(loopBars: 4, bars: 2, bpm: bpm, startBeat: 1.3);
      final count = m.firstWhere((x) => x.phase == TapPhase.count);
      // 1.3박에서 열었으니 다음 마디 첫 박은 4박째 = 2.7박 뒤
      check(
        '1) 마디 첫 박까지 기다린다',
        (count.sec - 2.7 * beat).abs() < 0.05,
        '${count.sec.toStringAsFixed(2)}초 뒤 (2.7박 = ${(2.7 * beat).toStringAsFixed(2)}초)',
      );
    }

    // 2) **넷을 센 뒤 시작한다.**
    {
      const beat = 0.5;
      final m = _drive(loopBars: 4, bars: 2, bpm: 120, startBeat: 0.1);
      final count = m.firstWhere((x) => x.phase == TapPhase.count);
      final rec = m.firstWhere((x) => x.phase == TapPhase.rec);
      check(
        '2) 미리 세기는 네 박',
        ((rec.sec - count.sec) - 4 * beat).abs() < 0.05,
        '${(rec.sec - count.sec).toStringAsFixed(2)}초 (네 박 = ${(4 * beat).toStringAsFixed(2)}초)',
      );
    }

    // 3) **판 한 바퀴만 돈다** — 판이 루프보다 짧아도·같아도·길어도.
    //    되접기를 안 하면 여기서 곱절로 돈다(그러면 앞머리를 두 번 두드리게 된다).
    for (final (loopBars, bars, bpm) in const [
      (4, 2, 120.0),
      (4, 4, 90.0),
      (2, 4, 140.0),
      (1, 1, 75.0),
    ]) {
      final beat = 60.0 / bpm;
      final m = _drive(loopBars: loopBars, bars: bars, bpm: bpm, startBeat: 0.4);
      final rec = m.firstWhere((x) => x.phase == TapPhase.rec);
      final done = m.firstWhere((x) => x.phase == TapPhase.done);
      final lap = done.sec - rec.sec;
      check(
        '3) 한 바퀴만 돈다 (루프 $loopBars마디 · 판 $bars마디 · $bpm BPM)',
        (lap - bars * 4 * beat).abs() < 0.05,
        '${lap.toStringAsFixed(2)}초 (판 한 바퀴 = ${(bars * 4 * beat).toStringAsFixed(2)}초)',
      );
    }

    // 4) **남은 수가 4→3→2→1 로 준다.** 「3,3,2,1」이나 「4,2,1」이면 못 센다.
    {
      final c = TapClock(beatsPerLoop: 16, lapBeats: 8);
      final seen = <int>[];
      var t = 0.05;
      while (c.phase != TapPhase.rec && t < 40) {
        c.update((t % 8.0) / 8.0 * 16);
        if (c.phase == TapPhase.count && (seen.isEmpty || seen.last != c.left)) {
          seen.add(c.left);
        }
        t += 0.03;
      }
      check('4) 넷부터 하나까지', '$seen' == '[4, 3, 2, 1]', '$seen');
    }

    // 5) **진행 막대가 0 에서 1 로 간다.** 늘 0 이면 「도는 중」이 안 보인다.
    {
      final c = TapClock(beatsPerLoop: 16, lapBeats: 8);
      final got = <double>[];
      var t = 0.05;
      while (c.phase != TapPhase.done && t < 60) {
        c.update((t % 8.0) / 8.0 * 16);
        if (c.phase == TapPhase.rec) got.add(c.progress);
        t += 0.03;
      }
      final rising = got.length > 10 &&
          got.first < 0.1 &&
          got.last > 0.9 &&
          () {
            for (var i = 1; i < got.length; i++) {
              if (got[i] < got[i - 1] - 1e-9) return false;
            }
            return true;
          }();
      check(
        '5) 진행 막대가 0→1 로만 간다',
        rising,
        got.isEmpty
            ? '없음'
            : '${got.first.toStringAsFixed(2)} → ${got.last.toStringAsFixed(2)} · ${got.length}번',
      );
    }

    // 6) **판이 넘어가도 성하다.** 루프 위치는 0.9 → 0.1 로 되돈다 — 그대로 빼면
    //    음수가 되어 지난 박이 줄어든다(녹음이 영영 안 끝난다).
    {
      final m = _drive(loopBars: 1, bars: 4, bpm: 120, startBeat: 0.2);
      final rec = m.firstWhere((x) => x.phase == TapPhase.rec);
      final done = m.firstWhere(
        (x) => x.phase == TapPhase.done,
        orElse: () => const _Mark(TapPhase.wait, -1),
      );
      check(
        '6) 루프를 네 번 넘어도 끝난다',
        done.sec > 0 && ((done.sec - rec.sec) - 8.0).abs() < 0.05,
        done.sec < 0
            ? '안 끝났다'
            : '${(done.sec - rec.sec).toStringAsFixed(2)}초 (4마디 = 8.00초)',
      );
    }

    // 7) **화면이 잠깐 멈췄다 와도** 지나친 만큼을 알아본다(30ms 대신 400ms 마다).
    {
      final m = _drive(
        loopBars: 4,
        bars: 2,
        bpm: 120,
        startBeat: 0.4,
        stepSec: 0.4,
      );
      final rec = m.firstWhere((x) => x.phase == TapPhase.rec);
      final done = m.firstWhere((x) => x.phase == TapPhase.done);
      check(
        '7) 띄엄띄엄 와도 한 바퀴',
        ((done.sec - rec.sec) - 4.0).abs() < 0.45,
        '${(done.sec - rec.sec).toStringAsFixed(2)}초 (2마디 = 4.00초 · 한 걸음 0.4초)',
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '대목 흐름 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}

/// 주파수를 **반음 번호**로 — 440Hz 를 0으로 놓는다. 옥타브를 접어 견주려고 쓴다.
double _log2(double x) => math.log(x) / math.ln2;
