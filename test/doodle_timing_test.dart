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
import 'package:music_doodle_engine/tap_rec.dart';

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

  // ── 예비박이 정확히 한 마디만 세고, 씬 머리에서 바로 시작하는가 ──
  // (사용자 신고, 2026-09-22: "예비박이 4박 이상 세진다" /
  //  "악기 넘어갈 때 씬 처음부터 녹음해야지 왜 4마디를 다 돌고 나서야
  //  시작되는 거야")
  group('TapClock — armedAtHead (두들플레이 전용)', () {
    // 두들플레이의 실제 값과 같은 모양 — 4/4, 4마디 씬을 통째로 녹음.
    TapClock headClock({bool armedAtHead = true}) => TapClock(
      beatsPerLoop: 16, // 4마디 × 4박
      lapBeats: 16, // 판 한 바퀴 = 씬 루프 한 바퀴
      countBeats: 4, // 한 마디
      beatsPerBar: 4,
      armedAtHead: armedAtHead,
    );

    /// 30ms 화면 시계를 흉내 낸다(120BPM 4분음표 = 0.5초 → 한 틱 0.03박).
    /// [cs] 가 [until] 을 만족할 때까지 돌리고, 멈춘 자리의 누적 `beatF`를
    /// 돌려준다. 판을 다 안 돌고 끝나야 하는 시험이라 위쪽 한도를 둔다.
    double runUntil(TapClock cs, bool Function() until, {int maxTicks = 1000}) {
      const step = 0.03;
      var beatF = 0.0;
      for (var i = 0; i < maxTicks; i++) {
        beatF += step;
        cs.update(beatF);
        if (until()) return beatF;
      }
      fail('$maxTicks 틱 안에 끝나지 않았다');
    }

    test('만들자마자 미리 세기(count)다 — wait 를 안 거친다', () {
      final cs = headClock();
      expect(cs.phase, TapPhase.count);
      expect(cs.left, 4, reason: '정확히 한 마디(4박)를 세야 한다');
    });

    test('정확히 countBeats(한 마디)만 세고 녹음이 시작된다', () {
      final cs = headClock();
      final leftSeen = <int>{};
      const step = 0.03;
      var beatF = 0.0;
      while (cs.phase != TapPhase.rec) {
        beatF += step;
        cs.update(beatF);
        if (cs.phase == TapPhase.count) leftSeen.add(cs.left);
        expect(beatF, lessThan(8), reason: '판의 절반도 되기 전에 rec 로 가야 한다');
      }
      // 4→3→2→1, 그 이상도 이하도 없어야 한다(예비박이 한 마디를 넘어가면 안 된다).
      expect(leftSeen, {4, 3, 2, 1});
    });

    test('되감은 직후 바로 시작 — 판을 거의 다 돌 때까지 기다리지 않는다', () {
      final cs = headClock();
      // 씬 머리(0)에서 되감아 바로 만든 상태이므로, 녹음(rec)까지 가는 데
      // 걸리는 시간은 미리 세기 한 마디(4박) 남짓이어야 한다 — 판 전체
      // (16박)를 거의 다 돌고 나서야 시작되면 안 된다.
      final at = runUntil(cs, () => cs.phase == TapPhase.rec);
      expect(at, lessThan(6), reason: '4박 미리 세기 + 여유 정도여야 한다');
    });

    test('회귀 증거 — armedAtHead 없이(예전 방식) 같은 값을 쓰면 판을 거의 '
        '다 돌아야 미리 세기가 시작된다', () {
      // 이 시험은 **고친 코드가 아니라 옛 코드의 증상**을 재현해 둔다 — 왜
      // `armedAtHead` 가 필요했는지 숫자로 남긴다. `_rewindLoop` 로 이미
      // 머리(0)로 되감아 둔 상태에서 이 경로(armedAtHead: false)를 타면,
      // `beatsPerLoop - countBeats`(=12박)에 이를 때까지 대기(wait)가
      // 안 끝난다 — 그 동안 자(메트로놈)는 계속 울린다(`_sendMet`).
      final cs = headClock(armedAtHead: false);
      expect(cs.phase, TapPhase.wait);
      final at = runUntil(cs, () => cs.phase != TapPhase.wait);
      expect(at, greaterThan(11),
          reason: '12박(판 끝에서 한 마디 앞) 근처까지 기다려야 벗어난다 — '
              '이게 "4마디를 다 돌고 나서야 시작된다"는 신고의 몸통이다');
    });
  });

  group('doodleShouldSendMet — 드럼 확정 뒤엔 본 녹음 중 자를 끈다', () {
    // 사용자 지시(2026-09-22): "하이햇까지 찍은 뒤 코드·베이스 녹음할 때는
    // 메트로놈을 예비박에만 주고 본 녹음 중엔 꺼라 — 드럼이 이미 박자를 준다".
    test('미리 세기·대기 동안은 무엇을 녹음하든 늘 울린다', () {
      for (final phase in [TapPhase.wait, TapPhase.count]) {
        for (final isDrum in [true, false]) {
          for (final confirmed in [true, false]) {
            expect(
              doodleShouldSendMet(
                phase: phase,
                isDrumStage: isDrum,
                drumsConfirmed: confirmed,
              ),
              isTrue,
              reason: '$phase/$isDrum/$confirmed — 미리 세기·대기는 늘 울려야 한다',
            );
          }
        }
      }
    });

    test('드럼을 치는 동안(rec)은 드럼이 확정됐어도 계속 울린다', () {
      expect(
        doodleShouldSendMet(
          phase: TapPhase.rec,
          isDrumStage: true,
          drumsConfirmed: true,
        ),
        isTrue,
        reason: '드럼 스스로를 녹음하는 중엔 박자를 줄 것이 자밖에 없다',
      );
    });

    test('드럼이 아직 없으면(미확정) 코드·베이스 녹음 중에도 울린다', () {
      expect(
        doodleShouldSendMet(
          phase: TapPhase.rec,
          isDrumStage: false,
          drumsConfirmed: false,
        ),
        isTrue,
      );
    });

    test('드럼이 확정된 뒤 코드·베이스를 녹음하는 동안은 꺼진다', () {
      expect(
        doodleShouldSendMet(
          phase: TapPhase.rec,
          isDrumStage: false,
          drumsConfirmed: true,
        ),
        isFalse,
        reason: '드럼이 이미 박자를 주니 자를 겹칠 이유가 없다',
      );
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
