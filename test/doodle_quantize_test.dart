// 두들플레이 「자에 맞춰 치면 그 칸에」 — 고정 입력(가짜 시계·고정 지터)으로만 잰다.
// 실시간 타이머를 쓰지 않아 병렬 부하에서 흔들리지 않는다.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/tap_rec.dart';

const _bpm = 120.0;
const _stepSec = 60.0 / _bpm / 4; // 16분 한 칸 = 125ms
const _bars = 2;
const _loopSec = _bars * 16 * _stepSec;

TapRecorder _rec({
  required double latency,
  TapSnap snap = TapSnap.eighth,
  double oddTol = 0,
}) => TapRecorder(
  steps: _bars * 16,
  loopBars: _bars,
  loopSec: _loopSec,
  snap: snap,
  latencySec: latency,
  oddTol: oddTol,
);

/// 목표 칸 [target] 을 자에 맞춰 쳤을 때 앱이 받는 루프 위치(0~1).
/// [trueDelay] = 터치+출력 지연, [jitter] = 사람 흔들림(초).
double _tapPos(int target, double trueDelay, double jitter) {
  final t = target * _stepSec + trueDelay + jitter;
  return ((t / _loopSec) % 1.0 + 1.0) % 1.0;
}

// 고정 지터(±40ms 안, 순환) — 난수 없음.
const _jit = [0.0, 0.02, -0.025, 0.035, -0.04, 0.01, -0.015, 0.03];

double _hitRate(TapRecorder r, List<int> targets, double trueDelay) {
  var ok = 0;
  for (var i = 0; i < targets.length; i++) {
    final got = r.stepOf(_tapPos(targets[i], trueDelay, _jit[i % _jit.length]));
    if (got == targets[i]) ok++;
  }
  return ok / targets.length;
}

void main() {
  test('지연 상수 — 합이 예전 0.03 보다 크고 조정 가능한 상수다', () {
    expect(doodleLatencySec(), closeTo(0.07, 1e-9));
    expect(doodleLatencySec(user: 0.01), closeTo(0.08, 1e-9));
  });

  test('16분 격자: 예전 지연(30ms)은 실제 70ms 기기에서 밀리고 새 값은 맞는다', () {
    final targets = [for (var i = 0; i < 32; i++) i];
    const trueD = 0.07;
    final oldRate = _hitRate(
      _rec(latency: 0.03, snap: TapSnap.sixteenth),
      targets,
      trueD,
    );
    final newRate = _hitRate(
      _rec(latency: doodleLatencySec(), snap: TapSnap.sixteenth),
      targets,
      trueD,
    );
    // ignore: avoid_print
    print(
      '[QUANT] 16분 적중률 예전 ${(oldRate * 100).round()}% → 새 ${(newRate * 100).round()}%',
    );
    expect(newRate, 1.0);
    expect(newRate, greaterThan(oldRate));
  });

  test('킥·스네어 혼합 격자: 8분 칸과 의도한 16분 뒷박이 모두 그 칸에 들어간다', () {
    final r = _rec(latency: doodleLatencySec(), oddTol: kOddSixteenthTol);
    final eighths = [for (var i = 0; i < 32; i += 2) i];
    final odds = [for (var i = 1; i < 32; i += 2) i];
    final e = _hitRate(r, eighths, 0.07);
    final o = _hitRate(r, odds, 0.07);
    // ignore: avoid_print
    print(
      '[QUANT] 혼합격자 8분 ${(e * 100).round()}% / 홀수16분 ${(o * 100).round()}%',
    );
    expect(e, 1.0);
    expect(o, 1.0);
  });

  test('혼합 격자는 지터로 8분이 16분으로 흩어지지 않는다(순수 16분 대비)', () {
    // 8분 자리를 ±0.5칸(62ms) 거의 끝까지 벗어나 쳐도 8분 칸에 붙는다.
    final mixed = _rec(latency: 0, oddTol: kOddSixteenthTol);
    final pure16 = _rec(latency: 0, snap: TapSnap.sixteenth);
    // 4번 칸(8분) 에서 +0.55칸 늦게 친 손.
    final pos = (4 + 0.55) * _stepSec / _loopSec;
    expect(mixed.stepOf(pos), 4, reason: '혼합: 8분 반경 ±0.6칸');
    expect(pure16.stepOf(pos), 5, reason: '순수 16분이면 옆 칸으로 샌다');
    // 홀수 5번 칸에서 +0.35칸 → 5번(반경 0.4 안).
    expect(mixed.stepOf((5 + 0.35) * _stepSec / _loopSec), 5);
    // 홀수 5번 칸에서 +0.45칸 → 반경 밖, 가까운 8분(6).
    expect(mixed.stepOf((5 + 0.45) * _stepSec / _loopSec), 6);
  });

  test('oddTol 이 0 이면 예전 8분 동작과 완전히 같다', () {
    final a = _rec(latency: 0.03);
    final b = _rec(latency: 0.03, oddTol: 0);
    for (var i = 0; i < 200; i++) {
      final p = i / 200.0;
      expect(a.stepOf(p), b.stepOf(p));
      expect(a.stepOf(p) % 2, 0);
    }
  });

  test('막대(headStep)와 담기는 칸이 같은 표를 쓴다 — 지연 0 이면 막대 칸 = 담긴 칸', () {
    final r = _rec(latency: 0, snap: TapSnap.sixteenth);
    for (var s = 0; s < 32; s++) {
      final center = (s + 0.0) * _stepSec / _loopSec;
      expect(r.stepOf(center), s);
    }
  });

  test('3/4 박자(spb 12)도 혼합 격자가 판 끝에서 되접힌다', () {
    final r = TapRecorder(
      steps: 24,
      loopBars: 2,
      loopSec: 24 * _stepSec,
      latencySec: 0,
      oddTol: kOddSixteenthTol,
      spb: 12,
    );
    expect(r.stepOf(23.9 * _stepSec / (24 * _stepSec)), 0);
    expect(r.stepOf(23.0 * _stepSec / (24 * _stepSec)), 23);
  });
}
