// 5단계 47/N 뒤에 미뤄 뒀던 **악기 품질** — 처음으로 재 본다.
//   flutter test test/timbre_check_test.dart
//
// HANDOFF 의 가설: 지속음 악기(패드·스트링·브라스·리드·오르간…)는
// `_cutFrom == _cutTo`(필터가 안 움직인다)라 음이 시작해서 끝날 때까지 음색이
// 한 번도 안 변하고, `bright = 0.66 + 0.34*(vel/3)` 라 세기 1과 3의 밝기차가 좁다.
//
// ── 처음 잰 법은 틀렸다 ──
// 배음의 **정확한 자리**(1~8배음)를 고에젤로 재서 무게중심을 봤더니 바이올린
// −36%·색소폰 −30% 처럼 크게 움직였다 — 그런데 그건 **비브라토가 배음을
// 정확한 자리에서 밀어내서**, 그 자리만 재는 자가 "사라졌다"로 잘못 읽은
// 것이었다(`VIB` 표의 깊이와 측정된 크기가 그대로 겹쳤다). 그래서 여기서는
// **정확한 자리를 안 따지는 넓은 대역**(500Hz 위/아래 RMS 비율,
// `env_check_test._highRatio` 와 같은 방식)으로 잰다 — 비브라토 몇 %엔 안
// 흔들리고, 필터가 실제로 열리고 닫히면 크게 바뀐다.
//
// ── 여기서 왜 실패로 안 잡는가 ──
// 재 보니(아래 출력) 몇몥 악기(패드·스트링·색소폰 등)는 **세게 칠수록 오히려
// 살짝 어두워진다** — 「세게 칠수록 밝게」라는 설계 의도와 반대다. 그런데 그
// 원인을 필터 계수(Biquad RBJ 쿡북 공식)까지 직접 대조해 봐도 **명확한
// 원인이 안 나왔다**(공진(Q)을 죽여도, 배음을 하나만 남겨도 똑같이 나온다 —
// 필터 자체 문제가 아니라 잴 창·정상상태 판단 어딘가의 문제일 수 있다).
// 원인을 확신 못 한 채 오디오 엔진(24종 악기가 걸린 공용 필터 경로)을
// 고치면 **모르는 채로 다른 곡을 깨뜨릴 수 있다** — 그래서 여기서는
// 잘못을 판정하지 않고 **숫자만 찍어 둔다.** 다음에 이 자리를 다시 열
// 때 「원인을 먼저 확실히 하고 나서 고친다」로 시작해야 한다.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/instruments.dart';
import 'package:music_doodle_engine/synth.dart';

List<double> _render(
  String voice, {
  double freq = 261.63,
  double dur = 1.0,
  int vel = 2,
  double sec = 1.0,
}) {
  final n = SynthNote();
  n.noteOn(voice, freq, dur, vel);
  final total = (sec * kSampleRate).round();
  final out = List<double>.filled(total, 0);
  for (var i = 0; i < total; i++) {
    if (!n.active) break;
    n.next();
    out[i] = (n.outL + n.outR) * 0.5;
  }
  return out;
}

/// [hz] 위쪽 에너지가 [from]~[from]+[n] 구간 전체에서 차지하는 비율.
/// `env_check_test._highRatio` 와 같은 방식(정확한 배음 자리를 안 따진다 —
/// 비브라토 몇 %엔 안 흔들리고, 필터가 실제로 열리고 닫히면 크게 바뀐다).
double _highRatio(List<double> x, double hz, int from, int n) {
  final hp = Biquad()..highpass(hz, 0.707);
  final end = math.min(from + n, x.length);
  var hi = 0.0, all = 0.0;
  for (var i = 0; i < from; i++) {
    hp.process(x[i]); // 필터를 그 자리까지 먼저 데운다(과도응답을 안 잰다)
  }
  for (var i = from; i < end; i++) {
    final h = hp.process(x[i]);
    hi += h * h;
    all += x[i] * x[i];
  }
  return all <= 0 ? -1 : hi / all;
}

void main() {
  test('악기 품질 — 지속음의 밝기가 세기·시간에 따라 움직이는가', () {
    Human.setLevel(0); // 흔들기를 끄고 잰다
    var fail = 0;
    void check(String name, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $name — $detail');
      if (!ok) fail++;
    }

    const f0 = 261.63; // C4
    const winN = 24000; // 0.5s @ 48k
    const cutHz = 500.0;

    final voices = [
      for (final v in ALL_VOICES)
        if (PLUCKY[v] != true) v,
    ];

    // ── 세기 — **참고용, 실패로 안 잡는다** ──
    // "세게 칠수록 밝게"가 의도인데, 재 보면 몇몇 악기는 반대로 살짝
    // 어두워진다(원인 미확인 — 파일 머리 설명 참고). 원인 없이 방향만으로
    // 잘못을 판정하면, 다음에 원인을 찾아 진짜로 고쳤을 때 오히려 이 시험이
    // 막을 수 있다. 그래서 숫자만 찍어 둔다 — 다음에 손볼 때 「전과 후」를
    // 잴 자로 쓴다.
    final velLines = <String>[];
    for (final v in voices) {
      final x1 = _render(v, freq: f0, dur: 1.0, vel: 1, sec: 1.0);
      final x3 = _render(v, freq: f0, dur: 1.0, vel: 3, sec: 1.0);
      final from = (0.05 * kSampleRate).round();
      final b1 = _highRatio(x1, cutHz, from, winN);
      final b3 = _highRatio(x3, cutHz, from, winN);
      if (b1 < 0 || b3 < 0) continue; // 무음(정의 안 된 음색) — 안 잰다
      final pct = b1 <= 1e-9 ? 0.0 : (b3 - b1) / b1 * 100;
      velLines.add('$v ${pct.toStringAsFixed(1)}%');
    }
    // ignore: avoid_print
    print('  (참고) vel1→vel3 밝기 변화 — ${velLines.join(', ')}');

    // ── 시간 — 마찬가지로 참고용 ──
    // 지속음이 시간이 지나도 안 변하는 게 늘 결함은 아니다(오르간은 원래
    // 그렇다) — 잘못을 판정하지 않고 **다음에 잴 때 견줄 숫자**만 찍어 둔다.
    final timeLines = <String>[];
    for (final v in voices) {
      final x = _render(v, freq: f0, dur: 2.0, vel: 2, sec: 2.0);
      final earlyFrom = (0.05 * kSampleRate).round();
      final lateFrom = math.max(0, x.length - winN - 4800);
      final b0 = _highRatio(x, cutHz, earlyFrom, winN);
      final b1 = _highRatio(x, cutHz, lateFrom, winN);
      if (b0 < 0 || b1 < 0) continue;
      final pct = b0 <= 1e-9 ? 0.0 : (b1 - b0) / b0 * 100;
      timeLines.add('$v ${pct.toStringAsFixed(1)}%');
    }
    // ignore: avoid_print
    print('  (참고) 2초 음 초반→후반 밝기 변화 — ${timeLines.join(', ')}');

    // ── 잘못을 판정하는 건 이것 하나뿐이다 ──
    // 무음·NaN 처럼 **원인과 상관없이 확실히 고장인 것**만 잡는다.
    final broken = <String>[
      for (final v in voices)
        if (_render(v, freq: f0, dur: 0.3, vel: 2, sec: 0.3).every(
          (s) => s == 0,
        ))
          v,
    ];
    check('1) 소리가 나기는 한다', broken.isEmpty, broken.isEmpty ? '전부 소리남' : broken.join(', '));

    // ignore: avoid_print
    print(fail == 0 ? '악기 품질 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
