// 메트로놈 택 누락 회귀 (2026-09-29 (11)).
//
// 원인 둘: ① 판 머리 박(0박)이 어느 바퀴에서도 안 잡힘 ② 되감기가 엔진 예약을 비우는데
// 화면의 「보낸 박」 기록은 남아 그 박들이 영영 안 울림. ①을 여기서 잰다(②는 화면 상태).

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/live_ops.dart';

void main() {
  test('wrap 없이는 판 머리 박이 어느 바퀴에서도 안 잡힌다(옛 결함 재현)', () {
    const loop = 4.0, beat = 0.5, buf = 1536 / 48000.0;
    final sent = <int>{};
    var zero = 0;
    var lastNow = 0.0;
    for (var ms = 0; ms < 8000; ms += 30) {
      final now = (ms / 1000.0) % loop + buf;
      if (lastNow - now > loop / 2) sent.clear();
      lastNow = now;
      for (final t in beatsToSend(
          nowSec: now, loopSec: loop, beatSec: beat, sent: sent, lead: 0.5)) {
        if (t.beat == 0) zero++;
        sent.add(t.beat);
      }
    }
    expect(zero, 0);
  });

  test('wrap 이면 매 바퀴 모든 박이 정확히 한 번씩 잡힌다', () {
    const loop = 4.0, beat = 0.5, buf = 1536 / 48000.0;
    const laps = 5, n = 8;
    final sent = <int>{}, next = <int>{};
    final counts = <int, int>{};
    var lastNow = 0.0, lap = 0;
    for (var ms = 60; ms < laps * 4000; ms += 30) {
      final now = (ms / 1000.0) % loop + buf;
      if (lastNow - now > loop / 2) {
        sent
          ..clear()
          ..addAll(next);
        next.clear();
        lap++;
      }
      lastNow = now;
      for (final t in beatsToSend(
          nowSec: now,
          loopSec: loop,
          beatSec: beat,
          sent: sent,
          lead: 0.5,
          wrap: true,
          sentNext: next)) {
        final key = (t.next ? lap + 1 : lap) * 100 + t.beat;
        counts[key] = (counts[key] ?? 0) + 1;
        (t.next ? next : sent).add(t.beat);
      }
    }
    for (var l = 1; l < laps - 1; l++) {
      for (var b = 0; b < n; b++) {
        expect(counts[l * 100 + b], 1, reason: '$l바퀴 $b박');
      }
    }
  });

  test('박이 정수가 아닌 판은 wrap 을 켜도 안 넘긴다', () {
    final t = beatsToSend(
        nowSec: 3.9,
        loopSec: 4.0,
        beatSec: 0.7,
        sent: <int>{},
        lead: 1.0,
        wrap: true,
        sentNext: <int>{});
    expect(t.every((e) => !e.next), isTrue);
  });
}
