// 두들플레이 — **녹음이 씬 처음부터 시작하는가.**
//   flutter test test/tap_clock_head_test.dart
//
// 사용자 신고(2026-09-22): "두들플레이 악기 넘어갈때 씬 처음부터 녹음해야지
// 왜 중간부터 들어가는거야".
//
// `TapClock` 의 대기→미리세기 전환이 **아무 마디 머리**에서나 일어났다
// (`beatF.floor() % beatsPerBar == 0`). 미리 세기가 한 마디이므로, 4마디 씬의
// 3마디째에 걸리면 녹음이 4마디째부터 시작해 **3·4·1·2 순**으로 담긴다 —
// 친 것이 씬의 엉뚱한 자리에 얹힌다.
//
// 녹음 창이 판 한 바퀴와 같을 때는(두들플레이가 그렇다) 판 머리에서 시작해야
// 한다. 숫자로 잰다.

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/tap_rec.dart';

/// [enterAt] 박에서 화면을 열었다고 보고, 판을 여러 바퀴 돌리며
/// **REC 이 시작된 판 안 위치**(0~beatsPerLoop)를 돌려준다.
double _recStartsAt({
  required int beatsPerLoop,
  required int lapBeats,
  required int countBeats,
  required double enterAt,
}) {
  final c = TapClock(
    beatsPerLoop: beatsPerLoop,
    lapBeats: lapBeats,
    countBeats: countBeats,
    beatsPerBar: 4,
  );
  var beat = enterAt;
  const stepBeat = 0.05; // 화면 시계처럼 잘게 민다
  for (var i = 0; i < 20000; i++) {
    final was = c.phase;
    c.update(beat % beatsPerLoop);
    if (was != TapPhase.rec && c.phase == TapPhase.rec) {
      return beat % beatsPerLoop;
    }
    if (c.phase == TapPhase.done) return -1;
    beat += stepBeat;
  }
  return -1;
}

void main() {
  group('판 한 바퀴를 녹음할 때는 판 머리에서 시작한다', () {
    // 4마디 = 16박, 녹음 창도 16박, 미리 세기 4박.
    const loop = 16, lap = 16, count = 4;

    test('어디서 열어도 REC 은 0박에서 시작한다', () {
      for (final enter in [0.1, 2.5, 5.0, 7.3, 11.9, 14.2, 15.5]) {
        final at = _recStartsAt(
          beatsPerLoop: loop,
          lapBeats: lap,
          countBeats: count,
          enterAt: enter,
        );
        // ignore: avoid_print
        print('  ${enter.toStringAsFixed(1)}박에 열림 → REC 시작 ${at.toStringAsFixed(2)}박');
        expect(at, greaterThanOrEqualTo(0), reason: 'REC 에 못 들어갔다');
        // 0박 근처(한 틱 안)여야 한다.
        final off = at > loop / 2 ? loop - at : at;
        expect(off, lessThan(0.2),
            reason: '$enter박에 열었더니 REC 이 $at박에서 시작했다 '
                '— 씬 중간부터 녹음된다');
      }
    });

    test('8마디 씬에서도 같다', () {
      for (final enter in [3.0, 9.5, 20.1, 27.8]) {
        final at = _recStartsAt(
          beatsPerLoop: 32,
          lapBeats: 32,
          countBeats: 4,
          enterAt: enter,
        );
        final off = at > 16 ? 32 - at : at;
        expect(off, lessThan(0.2), reason: '$enter박 → $at박');
      }
    });
  });

  group('녹음 창이 판보다 짧으면 예전 규칙 그대로', () {
    // 「두드려 넣기」 화면은 4마디 루프에서 2마디만 녹음할 수 있다.
    test('아무 마디 머리에서나 시작한다 — 회귀가 아니다', () {
      final at = _recStartsAt(
        beatsPerLoop: 16,
        lapBeats: 8,
        countBeats: 4,
        enterAt: 1.0,
      );
      // ignore: avoid_print
      print('짧은 녹음 창 — REC 시작 ${at.toStringAsFixed(2)}박');
      expect(at, greaterThanOrEqualTo(0));
      // 마디 머리(4의 배수)에서 시작해야 한다.
      expect(at % 4, lessThan(0.2), reason: '마디 머리가 아니다');
    });
  });
}
