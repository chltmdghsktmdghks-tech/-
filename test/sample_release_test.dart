// 표본 악기가 **손을 뗀 순간 멎는가.**
//   flutter test test/sample_release_test.dart
//
// 2026-09-22 에 잡은 버그의 회귀 시험이다.
//
// `SynthNote.release()` 는 `_env` 와 `_life` 만 건드렸는데, 표본 경로
// (`_nextSample`)는 **둘 다 안 읽는다.** 게다가 `_life` 를 깎는 줄은 합성
// 경로에 있어서 `next()` 가 표본일 때 먼저 return 하며 아예 안 탄다.
// 결과: 손을 떼도 표본이 끝까지(길면 몇 초) 그대로 울었다. 빨리 연타하면
// 안 꺼진 음이 겹겹이 쌓여 뭉갰다.
//
// 기존 `sampler_check_test.dart` 는 **`dur` 를 짧게 준 경우**만 재서 이걸
// 못 잡았다 — `release()` 를 한 번도 안 부른다. 여기서 그 경로를 직접 친다.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/sampler.dart';
import 'package:music_doodle_engine/synth.dart';

double _rms(List<double> x) {
  if (x.isEmpty) return 0;
  var s = 0.0;
  for (final v in x) {
    s += v * v;
  }
  return math.sqrt(s / x.length);
}

/// 잡았다가 [holdSec] 뒤에 **놓는다**. 돌려주는 것은 (놓기 직전 50ms, 꼬리 끝 50ms).
(double, double, bool) _holdThenRelease(
  String voice,
  double freq, {
  double holdSec = 0.5,
  double tailSec = 1.2,
}) {
  final n = SynthNote();
  // `Engine.noteHold` 가 넘기는 값과 같게 — 이게 이 버그의 핵심이다.
  // 화면이 "잡고 있는 소리"를 낼 때 dur 자리에 12초가 들어간다.
  n.noteOn(voice, freq, 12.0, 3);
  final hold = (holdSec * kSampleRate).round();
  final win = (0.05 * kSampleRate).round();

  final before = <double>[];
  for (var i = 0; i < hold; i++) {
    if (!n.active) break;
    n.next();
    if (i >= hold - win) before.add(n.outL);
  }
  final aliveAtRelease = n.active;
  n.release();

  final tail = (tailSec * kSampleRate).round();
  final after = <double>[];
  for (var i = 0; i < tail; i++) {
    if (!n.active) {
      after.add(0);
      continue;
    }
    n.next();
    after.add(n.outL);
  }
  final last = after.sublist(math.max(0, after.length - win));
  return (_rms(before), _rms(last), aliveAtRelease);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await ensureSamplesLoaded();
  });

  tearDownAll(() {
    kSampleBanks.clear();
  });

  test('손을 떼면 표본이 멎는다 — 표본 악기 전부', () {
    expect(kSampleBanks, isNotEmpty, reason: '표본을 못 읽으면 이 시험은 뜻이 없다');

    var fail = 0;
    final names = kSampleBanks.keys.toList()..sort();
    for (final voice in names) {
      final (before, after, alive) = _holdThenRelease(voice, 261.63);
      if (!alive) {
        // 표본이 0.5초 안에 자연히 끝났다 — 놓을 것이 없으니 건너뛴다.
        // ignore: avoid_print
        print('  $voice — 0.5초 전에 표본이 끝남(해당 없음)');
        continue;
      }
      // 놓기 전에는 소리가 나고 있어야 시험이 성립한다.
      final sounded = before > 1e-4;
      // 놓은 뒤 1.2초면 완전히 멎어야 한다. 제일 긴 릴리즈(하프 0.50s)의
      // 두 배가 넘는 시간이다.
      final quiet = after < before * 0.01;
      if (!sounded || !quiet) fail++;
      // ignore: avoid_print
      print(
        '  ${sounded && quiet ? "OK " : "FAIL"} $voice — '
        '놓기 직전 ${before.toStringAsFixed(5)} → 1.2초 뒤 ${after.toStringAsFixed(5)}'
        ' (${(after / (before == 0 ? 1 : before) * 100).toStringAsFixed(2)}%)',
      );
    }
    expect(fail, 0, reason: '$fail개 악기가 손을 떼도 안 멎는다');
  });

  test('놓기 전에는 안 줄어든다 — 잡고 있는 동안은 그대로 울어야 한다', () {
    // 반대쪽 함정: 릴리스를 너무 일찍 걸면 잡고 있는데도 소리가 사그라든다.
    final n = SynthNote();
    n.noteOn('piano', 261.63, 12.0, 3);
    final win = (0.05 * kSampleRate).round();
    final early = <double>[], later = <double>[];
    final total = (1.0 * kSampleRate).round();
    for (var i = 0; i < total; i++) {
      if (!n.active) break;
      n.next();
      if (i < win) early.add(n.outL);
      if (i >= total - win) later.add(n.outL);
    }
    // ignore: avoid_print
    print('piano 잡고 있는 1초: 처음 ${_rms(early).toStringAsFixed(5)} '
        '→ 끝 ${_rms(later).toStringAsFixed(5)}');
    expect(later, isNotEmpty, reason: '1초를 못 버티면 잡고 있는 소리가 아니다');
    expect(_rms(later), greaterThan(0), reason: '놓지도 않았는데 멎으면 안 된다');
  });

  test('두 번 놓아도 페이드가 되감기지 않는다', () {
    final n = SynthNote();
    n.noteOn('piano', 261.63, 12.0, 3);
    final step = (0.3 * kSampleRate).round();
    for (var i = 0; i < step && n.active; i++) {
      n.next();
    }
    n.release();
    final win = (0.05 * kSampleRate).round();
    for (var i = 0; i < win && n.active; i++) {
      n.next();
    }
    final mid = <double>[];
    for (var i = 0; i < win; i++) {
      if (!n.active) {
        mid.add(0);
        continue;
      }
      n.next();
      mid.add(n.outL);
    }
    n.release(); // 두 번째 — 여기서 되감기면 소리가 다시 커진다
    final after = <double>[];
    for (var i = 0; i < win; i++) {
      if (!n.active) {
        after.add(0);
        continue;
      }
      n.next();
      after.add(n.outL);
    }
    // ignore: avoid_print
    print('release 두 번: ${_rms(mid).toStringAsFixed(5)} → ${_rms(after).toStringAsFixed(5)}');
    expect(_rms(after), lessThanOrEqualTo(_rms(mid) * 1.05),
        reason: '두 번째 release 가 페이드를 처음으로 되감으면 안 된다');
  });
}
