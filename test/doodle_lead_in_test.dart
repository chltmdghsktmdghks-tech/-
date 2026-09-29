// 두들 녹음 마디 밀림 (2026-09-29 (14)) — 재현 + 고침.
//   flutter test test/doodle_lead_in_test.dart
//
// 재현: 두들은 판을 되감고(위치 0) 곧바로 한 마디 미리 센 뒤 녹음한다. 녹음은 위치 1마디째에서
// 시작하는데 위치→칸 계산이 루프 위치 그대로라, 녹음 첫 마디에 친 것이 2마디째 칸에 담겼다.
// 고침: 판 머리를 한 마디 미뤄(LoopState startDelaySec) 미리 세기가 판 끝쪽에 오게 한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/audio_isolate.dart';
import 'package:music_doodle_engine/engine.dart';
import 'package:music_doodle_engine/live_ops.dart';
import 'package:music_doodle_engine/tap_rec.dart';

const int _bars = 4;
const double _beatSec = 0.5; // 120BPM
const double _loopSec = _bars * 4 * _beatSec; // 8s
const int _spb = 16;

/// 30ms 화면 시계로 흉내 낸다. [startPos] = 되감은 직후의 (들리는) 위치.
/// 반환: 판(녹음)의 k 번째 박(0부터)을 **정확히 그 박 위에** 쳤을 때 담기는 칸들.
List<int> _stepsOfTakeBeats({required double startPos, required bool fixedClock}) {
  final cs = TapClock(
    beatsPerLoop: _bars * 4,
    lapBeats: _bars * 4,
    countBeats: 4,
    beatsPerBar: 4,
    armedAtHead: true,
    startBeat: fixedClock ? startPos * _bars * 4 : null,
  );
  TapRecorder newRec() => TapRecorder(
    steps: _bars * _spb,
    loopBars: _bars,
    loopSec: _loopSec,
    latencySec: 0,
    spb: _spb,
  );
  double posAt(double t) => (startPos + t / _loopSec) % 1.0;

  var rec = newRec();
  double? recStart;
  var t = 0.0;
  while (cs.phase != TapPhase.rec) {
    t += 0.03;
    cs.update(posAt(t) * _bars * 4);
    if (cs.phase == TapPhase.rec) {
      recStart = t;
      rec = newRec();
    }
    expect(t, lessThan(6), reason: '미리 세기는 한 마디(2초) 안팎이어야 한다');
  }
  // 녹음이 시작된 **박 시각** = 카운트 끝. 사용자는 이 박부터 한 박씩 친다.
  final out = <int>[];
  for (var k = 0; k < _bars * 4; k++) {
    final tk = recStart! + k * _beatSec;
    out.add(rec.stepOf(posAt(tk)));
  }
  return out;
}

void main() {
  group('재현 — 되감은 자리가 판 머리(0)이면 녹음이 한 마디 밀린다', () {
    test('옛 기하(startPos 0): 녹음 첫 박이 2마디째 칸(16)에 담긴다', () {
      final s = _stepsOfTakeBeats(startPos: 0, fixedClock: false);
      // ignore: avoid_print
      print('[밀림] 옛 기하 첫 4박 칸 = ${s.take(4).toList()} (맞아야 할 0,4,8,12)');
      expect(s.first, isNot(0), reason: '재현: 첫 박이 0 이 아니다');
      expect(s.first, closeTo(_spb, 2), reason: '정확히 한 마디(16칸) 뒤에 담긴다');
      expect(s[_bars * 4 - 1], lessThan(_spb), reason: '마지막 마디는 첫 마디 칸으로 되접힌다');
    });
  });

  group('고침 — 미리 세기가 판의 마지막 마디, 녹음은 판 머리에서', () {
    final start = leadInStartPos(loopSec: _loopSec, leadSec: 4 * _beatSec);
    test('시작 위치는 판 끝에서 한 마디 앞', () {
      expect(start, closeTo(0.75, 1e-9));
    });
    test('버퍼만큼 들리는 자리가 더 뒤(들리는 위치 = 렌더 − 버퍼)', () {
      expect(
        leadInStartPos(loopSec: _loopSec, leadSec: 2, bufferedSec: 0.032),
        closeTo(0.75 - 0.032 / 8, 1e-9),
      );
    });
    test('k 번째 박에 치면 칸 4k — 16박 전부 제자리(밀림 0)', () {
      final s = _stepsOfTakeBeats(startPos: start, fixedClock: true);
      // ignore: avoid_print
      print('[밀림] 고친 기하 첫 4박 칸 = ${s.take(4).toList()}');
      for (var k = 0; k < _bars * 4; k++) {
        // 시계 틱(30ms) 오차 안에서 제자리 — 8분 격자(2칸)로 붙으니 ±2칸 안.
        final diff = (s[k] - 4 * k) % (_bars * _spb);
        expect(diff <= 2 || diff >= _bars * _spb - 2, isTrue,
            reason: '박 $k → 칸 ${s[k]} (기대 ${4 * k})');
      }
      expect(s.first, lessThanOrEqualTo(2));
    });
    test('미루기가 없으면(판이 한 마디 이하) 위치 0 그대로', () {
      expect(leadInStartPos(loopSec: 2, leadSec: 2), 0);
      expect(leadInStartPos(loopSec: 8, leadSec: 0), 0);
    });
  });

  group('LoopState — startDelaySec (기본 0 은 예전과 같다)', () {
    List<dynamic> kick() => <dynamic>[
      <dynamic>['acoustic', 'kick', 3, 180.0, 0.0],
    ];

    test('기본: 판 머리 = 지금', () {
      final e = Engine();
      final l = LoopState()..set(<dynamic>[], kick(), 1.0, true, e);
      expect(l.nextAt, e.nowFrames);
      expect(l.posOf(e.nowFrames), 0);
    });

    test('미루면: 판 머리가 그만큼 뒤, 그동안 위치는 판 끝쪽, 첫 킥은 그때', () {
      final e = Engine();
      final l = LoopState()
        ..set(<dynamic>[], kick(), 1.0, true, e, startDelaySec: 0.5);
      expect(l.nextAt - e.nowFrames, 24000);
      expect(l.posOf(e.nowFrames), closeTo(0.5, 1e-9), reason: '판 끝에서 0.5초 앞');
      // 아이솔레이트와 같은 방식으로 3초 렌더하며 첫 타격 위치를 잰다.
      final total = 3 * kSampleRate;
      var got = 0;
      int? first;
      while (got < total) {
        l.topUp(e, 6144 + kSampleRate ~/ 4);
        final pcm = e.render(1024);
        for (var i = 0; i < pcm.length; i += 2) {
          if (first == null && pcm[i].abs() > 2000) first = got + i ~/ 2;
        }
        got += 1024;
      }
      expect(first, isNotNull);
      expect((first! - 24000).abs(), lessThan(kSampleRate ~/ 100),
          reason: '첫 킥은 0.5초 뒤 ±10ms — 판 머리가 정확히 미뤄졌다');
    });
  });

  group('메트로놈 — 미리 세기 네 박(12~15) 뒤 판 머리 박(0)이 빠지지 않는다', () {
    test('화면과 같은 방식(_metSent/_metNext 승계)으로 돌려 12,13,14,15,0,1 이 한 번씩', () {
      const loopSec = _loopSec;
      final sent = <int>{12}; // _sendMetHead 가 낸 미리 세기 첫 박
      final next = <int>{};
      final order = <int>[12];
      var lastNow = 0.0;
      // 렌더 시계 기준 nowSec: 되감은 직후 = 판 끝 − 한 마디(6.0), 30ms 씩 흐른다(3초 = 6박).
      for (var i = 0; i <= 100; i++) {
        final raw = 6.0 + i * 0.03;
        final nowSec = raw % loopSec;
        if (lastNow - nowSec > loopSec / 2) {
          sent
            ..clear()
            ..addAll(next);
          next.clear();
        }
        if (nowSec > lastNow) lastNow = nowSec;
        final ticks = beatsToSend(
          nowSec: nowSec,
          loopSec: loopSec,
          beatSec: _beatSec,
          sent: sent,
          lead: 0.5,
          wrap: true,
          sentNext: next,
        );
        for (final t in ticks) {
          (t.next ? next : sent).add(t.beat);
          order.add(t.beat);
        }
      }
      expect(order.take(6).toList(), [12, 13, 14, 15, 0, 1],
          reason: '판 머리 박(0)이 미리 세기 직후 정확히 한 번 나와야 한다');
    });
  });
}
