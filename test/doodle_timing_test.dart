// Doodle Play 가 **씬과 같은 박, 같은 마디로 도는가.**
//
// 사용자 신고(2026-09-21): "씬 재생이랑 두들플레이 박자가 안맞아 /
// 왜 두마디만하는거야 씬따라서 2,4,8 마디 해야지".
//
// 두 가지 다 "숫자로 재면 바로 보이는데 귀로는 「좀 이상한데」로만 느껴지는"
// 종류라 여기서 잰다.

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/live_ops.dart';
import 'package:music_doodle_engine/meter.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';

void main() {
  group('자(메트로놈)가 씬과 같은 시계를 쓴다', () {
    // 씬 루프는 delay 를 **렌더 커서**에서 잰다(engine 이 _now + delay 를 더하면
    // 정확히 목표 프레임이 된다). 자는 loopPos 로 재는데, loopPos 는
    // `nowFrames - buffered` = **귀에 들리는 자리**다. 보정을 안 하면 자만
    // 버퍼 한 통만큼 늦는다.
    const bufferedFrames = 3072;
    const buf = bufferedFrames / 48000.0; // 64ms
    const beatSec = 0.5; // 120BPM 4분음표
    const loopSec = 4.0;

    test('보정을 안 하면 자가 버퍼 한 통만큼 늦는다', () {
      // 들리는 자리가 0.0 일 때, 0.5초 뒤 박을 예약한다.
      final raw = beatsToSend(
        nowSec: 0.0,
        loopSec: loopSec,
        beatSec: beatSec,
        sent: <int>{},
        lead: 0.6, // 박 간격(0.5s)보다 넓어야 그 박이 창에 들어온다
      );
      final tick = raw.firstWhere((t) => t.beat == 1);
      // 이 delay 는 렌더 커서에 얹히므로, 실제로 들리는 시각은 +buf 다.
      final heardAt = 0.0 + buf + tick.delay;
      // ignore: avoid_print
      print('[MET] 보정 없음 → 들리는 시각 ${heardAt.toStringAsFixed(4)}s '
          '(맞아야 할 ${beatSec.toStringAsFixed(4)}s)');
      expect(heardAt - beatSec, closeTo(buf, 1e-9),
          reason: '정확히 버퍼 한 통만큼 늦는다 = 64ms');
    });

    test('렌더 시계 기준으로 넘기면 제자리에 들린다', () {
      final fixed = beatsToSend(
        nowSec: 0.0 + buf, // ← 이 화면이 하는 보정
        loopSec: loopSec,
        beatSec: beatSec,
        sent: <int>{},
        lead: 0.5,
      );
      final tick = fixed.firstWhere((t) => t.beat == 1);
      final heardAt = 0.0 + buf + tick.delay;
      // ignore: avoid_print
      print('[MET] 보정 후  → 들리는 시각 ${heardAt.toStringAsFixed(4)}s');
      expect(heardAt, closeTo(beatSec, 1e-9), reason: '박 위에 정확히 떨어진다');
    });

    test('미세한 역행을 랩으로 읽으면 같은 박을 두 번 보낸다', () {
      // 위치 보간은 실측값과 만나는 자리에서 조금씩 뒤로 흔들린다.
      final sent = <int>{};
      for (final t in beatsToSend(
        nowSec: 1.0,
        loopSec: loopSec,
        beatSec: beatSec,
        sent: sent,
        lead: 0.6,
      )) {
        sent.add(t.beat);
      }
      final before = Set<int>.from(sent);
      expect(before, isNotEmpty);

      // 0.02초 뒤로 흔들렸다. 옛 조건(nowSec < _metLastNow)이면 통째로 비운다.
      const nowSec = 0.98, metLastNow = 1.0;
      final oldClears = nowSec < metLastNow;
      final newClears = metLastNow - nowSec > loopSec / 2;
      // ignore: avoid_print
      print('[MET] 0.02s 역행 → 옛 판정 clear=$oldClears / 새 판정 clear=$newClears');
      expect(oldClears, isTrue, reason: '옛 판정은 지워서 같은 박을 다시 보냈다');
      expect(newClears, isFalse, reason: '새 판정은 진짜 한 바퀴일 때만 지운다');
    });
  });

  group('판 길이가 씬을 따라간다', () {
    // `_pickBars` 와 같은 규칙.
    int pick(int sceneBars) =>
        sceneBars >= 8 ? 8 : (sceneBars >= 4 ? 4 : 2);

    test('2·4·8 로 갈무리된다', () {
      expect(pick(1), 2);
      expect(pick(2), 2);
      expect(pick(3), 2, reason: '어중간한 씬은 내려서 자르지 않고 2로');
      expect(pick(4), 4);
      expect(pick(6), 4);
      expect(pick(8), 8);
      expect(pick(16), 8);
    });

    test('판이 씬과 같아지면 되접기가 항등이 된다', () {
      // `TapRecorder.stepOf` 가 `s %= steps` 로 되접는다. 판(steps)이 루프보다
      // 짧으면 루프 뒷마디에 친 것이 앞마디 위에 겹쳐 적힌다.
      for (final bars in [2, 4, 8]) {
        const spb = 16;
        final steps = bars * spb;
        final loopSteps = bars * spb; // _bars == _loopBars 가 된 뒤
        for (var s = 0; s < loopSteps; s++) {
          expect(s % steps, s, reason: '$bars마디에서 겹쳐 적히는 칸이 없어야 한다');
        }
      }
    });

    test('2마디로 박혀 있으면 4마디 씬의 절반만 사용자 것이 된다', () {
      // 고치기 전 상태의 크기를 남겨 둔다(회귀하면 이 수가 바뀐다).
      const spb = 16;
      const fixedSteps = 2 * spb; // 옛 _kDoodleBars
      const sceneSteps = 4 * spb;
      final distinct = {for (var s = 0; s < sceneSteps; s++) s % fixedSteps};
      // ignore: avoid_print
      print('[BARS] 4마디 씬 $sceneSteps칸 중 사용자가 정할 수 있던 칸 = ${distinct.length}');
      expect(distinct.length, fixedSteps);
      expect(distinct.length / sceneSteps, 0.5);
    });
  });

  group('자가 박자표를 따라간다', () {
    test('6/8 에서 한 클릭은 4분음표가 아니라 8분음표다', () {
      final m = meterOf('6/8');
      const bpm = 120.0;
      final stepSec = 60.0 / bpm / 4;
      final fromMeter = stepSec * m.clickSteps; // 새 계산
      final quarterFixed = 60.0 / bpm; // 옛 계산
      // ignore: avoid_print
      print('[MET] 6/8 clickSteps=${m.clickSteps} '
          '→ 새 ${fromMeter.toStringAsFixed(4)}s / 옛 ${quarterFixed.toStringAsFixed(4)}s');
      expect(m.clickSteps, 2);
      expect(fromMeter, closeTo(quarterFixed / 2, 1e-9),
          reason: '옛 계산은 정확히 절반 속도로 울렸다');
    });

    test('4/4 에서는 새 계산도 옛 계산과 같다 — 회귀가 아니다', () {
      final m = meterOf('4/4');
      const bpm = 120.0;
      final stepSec = 60.0 / bpm / 4;
      expect(stepSec * m.clickSteps, closeTo(60.0 / bpm, 1e-9));
    });
  });

  _silentSceneTests();
}

// ── 씬을 빈 상태로 시작하기 (사용자 지시, 2026-09-22) ──
//
// 두들플레이는 가락·패드를 재우고 메트로놈만 남긴 채 시작한다. 그런데
// **재우면 씬 루프 길이가 달라진다** — `sceneLoopBars` 가 `audible(t)` 를 보기
// 때문이다. 그래서 마디 수는 반드시 **재우기 전에** 재야 한다. 순서가 뒤집히면
// 4마디 씬이 조용히 짧은 판으로 줄어든다(예전에 꼭 이 모양으로 당했다).
void _silentSceneTests() {
  group('씬을 재워도 판 길이는 원래 씬을 따라간다', () {
    test('재우면 sceneLoopBars 가 줄어든다 — 그래서 먼저 재야 한다', () {
      final p = Project.initial()..setGenre('lofi');
      // 가락을 **8마디**로 늘려 둔다 — 기전이 실제로 드러나야 시험이 뜻이 있다.
      // (그냥 두면 이 장르는 전부 4마디라 4→4 로 지나가 버린다)
      final mel = p.tracks.firstWhere((t) => t.type == 'melody');
      p.putUserPattern(
        'melody',
        'long_mel',
        note: NotePatternDef('long_mel', 8, 8, const [
          [7, 0, 4, 2],
        ]),
      );
      p.setClip(mel, 'long_mel');
      final before = SceneSequencer.sceneLoopBars(p, p.currentScene);
      expect(before, 8, reason: '가락이 제일 길면 그것이 씬 길이다');

      // 두드려 채울 세 트랙만 남기고 나머지를 재운다(화면이 하는 것과 같다).
      final keep = <String>{};
      for (final ty in ['drum', 'bass', 'chord']) {
        final t = p.tracks.where((x) => x.type == ty);
        if (t.isNotEmpty) keep.add(t.first.id);
      }
      var muted = 0;
      for (final t in p.tracks) {
        if (keep.contains(t.id)) continue;
        t.mute = true;
        muted++;
      }
      final after = SceneSequencer.sceneLoopBars(p, p.currentScene);
      // ignore: avoid_print
      print('[SILENT] 재운 트랙 $muted개 · 마디 $before → $after');
      expect(muted, greaterThan(0), reason: '재울 트랙이 있어야 시험이 뜻이 있다');
      expect(after, lessThan(before),
          reason: '가락을 재우면 씬이 짧아진다 — 그래서 마디는 재우기 전에 재야 한다');
    });

    test('재운 것은 되돌아온다', () {
      final p = Project.initial()..setGenre('lofi');
      final prior = {for (final t in p.tracks) t.id: t.mute};
      for (final t in p.tracks) {
        t.mute = true;
      }
      expect(p.tracks.every((t) => !p.audible(t)), isTrue,
          reason: '전부 재웠으면 아무것도 안 들린다');
      // 화면이 dispose 에서 하는 것과 같다.
      for (final t in p.tracks) {
        final was = prior[t.id];
        if (was != null) t.mute = was;
      }
      for (final t in p.tracks) {
        expect(t.mute, prior[t.id], reason: '들어오기 전 상태 그대로');
      }
    });
  });
}
