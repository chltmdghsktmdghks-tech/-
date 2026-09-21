// 5단계 3/N — 씬 **무한 반복**이 밀리지 않는지 확인.
//
//   flutter test test/loop_check_test.dart
//
// 이게 왜 중요한가: 루프가 한 판마다 몇 ms 씩만 밀려도 30초쯤 지나면 박자가 눈에 띄게
// 어긋난다. "귀로 들으니 괜찮더라"로는 못 잡는다 — 자로 재야 한다.
//
// 베낀 코드가 아니라 **실물(`LoopState`)** 을 돌린다. 아이솔레이트가 부르는 것과 같은
// `topUp()` 을 같은 순서로 부르고, 실제로 렌더한 소리에서 타격 시각을 찾아 잰다.
//
// 확인하는 것:
//  1) 한 판에 킥 하나짜리 프로그램으로 20판을 돌려, 타격 간격이 한 판 그대로인가
//     (특히 **오차가 쌓이지 않는가** — 판마다 1ms 씩만 밀려도 20판이면 20ms 다)
//  2) 급식이 들쭉날쭉해도(렌더 덩어리 크기를 흔들어도) 안 밀리는가
//  3) 돌고 있는 중에 프로그램을 갈아 끼워도 박자가 안 흔들리는가(restart:false)
//  4) 위치(posOf)가 0→1 로 돌고, 판이 바뀔 때 되감기는가
//  5) 정지(clear)하면 더 안 나오는가
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/audio_isolate.dart';
import 'package:music_doodle_engine/engine.dart';
import 'package:music_doodle_engine/synth.dart';

/// 킥 하나만 있는 한 판.
List<dynamic> _kickOnly() => <dynamic>[
  <dynamic>['acoustic', 'kick', 3, 180.0, 0.0],
];

/// 렌더하면서 [LoopState.topUp] 을 아이솔레이트와 같은 방식으로 부른다.
/// [chunk] 를 흔들면 급식이 들쭉날쭉한 상황을 흉내 낼 수 있다.
Int16List _run(
  Engine e,
  LoopState loop,
  double seconds, {
  int Function(int)? chunkOf,
}) {
  final frames = (seconds * kSampleRate).round();
  final buf = Int16List(frames * 2);
  var got = 0;
  var i = 0;
  while (got < frames) {
    loop.topUp(e, 6144 + kSampleRate ~/ 4); // 아이솔레이트와 같은 guard
    var n = chunkOf == null ? 1024 : chunkOf(i++);
    if (n > frames - got) n = frames - got;
    if (n < 1) n = 1;
    final pcm = e.render(n);
    buf.setRange(got * 2, (got + n) * 2, pcm);
    got += n;
  }
  return buf;
}

/// 타격이 시작된 프레임 위치들.
///
/// **자를 두 번 고쳤다.**
///
/// 처음엔 샘플값이 문턱을 넘는 순간을 그대로 셌다가 20판에 408개가 잡혔다. 킥은
/// 저음이라 한 번 치는 동안 파형이 0을 수십 번 지나간다 — 그때마다 '새 타격'으로 센 것이다.
/// → 짧은 창(32프레임)의 최대값으로 **포락선**을 만들고, 한 번 잡으면 0.2초는 쉰다.
///
/// 두 번째는 **킥을 길게 고친 날**이다(75~142ms → 176~405ms). 「지금 조용하다가
/// 소리가 났다」로 타격을 찾고 있었는데, 킥이 길어지니 **타격 사이가 조용하지 않다** —
/// 문턱 아래로 안 내려가서 두 번째 타격부터 통째로 안 잡혔다. 20판에 42개가 잡히고
/// 누적 오차 20초가 나왔다. 루프는 멀쩡했고 **자가 틀렸다**(이 프로젝트에서 네 번째다).
/// → 「조용하다가 소리 남」이 아니라 **「갑자기 커짐」** 으로 바꿨다. 타격은 어택이
///   2ms 라 한 창만에 몇 배로 뛴다. 꼬리는 아무리 커도 그렇게 못 뛴다.
List<int> _onsets(Int16List b, {double thr = 0.05}) {
  const block = 32;
  const refractory = 9600; // 0.2초
  const jump = 2.5; // 앞 창의 몇 배로 뛰면 새 타격인가
  final n = b.length ~/ 2;
  final out = <int>[];
  var last = -1000000;
  var prevEnv = 0.0;
  for (var f = 0; f + block <= n; f += block) {
    var env = 0.0;
    for (var i = 0; i < block; i++) {
      final v = (b[(f + i) * 2] / 32768.0).abs();
      if (v > env) env = v;
    }
    final rose = env > thr && env > prevEnv * jump;
    if (rose && f - last > refractory) {
      // 이 창 안에서 **앞 창보다 확실히 커지는** 첫 샘플이 진짜 시작점
      final gate = prevEnv > thr ? prevEnv * 1.5 : thr;
      var at = f;
      for (var i = 0; i < block; i++) {
        if ((b[(f + i) * 2] / 32768.0).abs() > gate) {
          at = f + i;
          break;
        }
      }
      out.add(at);
      last = at;
    }
    prevEnv = env;
  }
  return out;
}

void main() {
  test('씬 루프', () {
    Human.setLevel(0);
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    const loopSec = 1.0;
    final loopFrames = (loopSec * kSampleRate).round();

    // 1) 밀리지 않는가
    final e1 = Engine();
    final l1 = LoopState()..set(<dynamic>[], _kickOnly(), loopSec, true, e1);
    final pcm1 = _run(e1, l1, 20.5);
    final on1 = _onsets(pcm1);
    final gaps = [for (var i = 1; i < on1.length; i++) on1[i] - on1[i - 1]];
    final worst = gaps.isEmpty
        ? -1
        : gaps.map((g) => (g - loopFrames).abs()).reduce(max);
    // **쌓이는가**가 핵심이다. 한 판씩의 오차는 커 봐야 몇 프레임인데, 그건 드럼이 칠 때마다
    // 레이어 간격을 조금씩 흔들기 때문이다(drums.dart 의 씨앗 없는 난수 — 소리의 개성이지
    // 박자 문제가 아니다). 그래서 파형이 문턱을 넘는 지점이 몇 샘플씩 달라진다.
    // 밀림이 진짜라면 **누적 오차**가 판 수에 비례해 커진다.
    final drift = on1.isEmpty
        ? -1
        : ((on1.last - on1.first) - (on1.length - 1) * loopFrames).abs();
    check(
      '1) 20판 간격',
      on1.length >= 20 && worst <= 8 && drift <= 8,
      '타격 ${on1.length}개 · 판당 오차 최대 $worst프레임 · **누적 오차 $drift프레임**'
          ' (${(drift / kSampleRate * 1000).toStringAsFixed(2)}ms)',
    );

    // 2) 급식이 들쭉날쭉해도
    final e2 = Engine();
    final l2 = LoopState()..set(<dynamic>[], _kickOnly(), loopSec, true, e2);
    // 64 ~ 4096 프레임 사이로 크게 흔든다
    final pcm2 = _run(
      e2,
      l2,
      10.5,
      chunkOf: (i) => [64, 4096, 512, 2048, 128][i % 5],
    );
    final on2 = _onsets(pcm2);
    final gaps2 = [for (var i = 1; i < on2.length; i++) on2[i] - on2[i - 1]];
    final worst2 = gaps2.isEmpty
        ? -1
        : gaps2.map((g) => (g - loopFrames).abs()).reduce(max);
    final drift2 = on2.isEmpty
        ? -1
        : ((on2.last - on2.first) - (on2.length - 1) * loopFrames).abs();
    check(
      '2) 급식 흔들려도',
      on2.length >= 10 && worst2 <= 8 && drift2 <= 8,
      '타격 ${on2.length}개 · 판당 최대 $worst2프레임 · 누적 $drift2프레임',
    );

    // 3) 돌고 있는 중에 프로그램 교체(restart:false) — 박자는 그대로여야 한다
    final e3 = Engine();
    final l3 = LoopState()..set(<dynamic>[], _kickOnly(), loopSec, true, e3);
    final head = _run(e3, l3, 5.5);
    // 내용만 바꾼다(킥 + 스네어). 시작 시각은 안 건드린다.
    l3.set(
      <dynamic>[],
      <dynamic>[
        <dynamic>['acoustic', 'kick', 3, 180.0, 0.0],
        <dynamic>['acoustic', 'snare', 3, 180.0, 0.5],
      ],
      loopSec,
      false,
      e3,
    );
    final tail = _run(e3, l3, 5.5);
    final onHead = _onsets(head);
    final onTail = _onsets(tail);
    // 이어 붙였을 때 킥 자리(1초 간격)가 유지되는가 — 뒤쪽은 0.5초마다 소리가 나므로
    // 짝수 번째(킥)만 본다.
    final kickGaps = [
      for (var i = 2; i < onTail.length; i += 2) onTail[i] - onTail[i - 2],
    ];
    final worst3 = kickGaps.isEmpty
        ? -1
        : kickGaps.map((g) => (g - loopFrames).abs()).reduce(max);
    check(
      '3) 재생 중 교체',
      onHead.length >= 5 && onTail.length > onHead.length && worst3 <= 8,
      '교체 전 ${onHead.length}개 → 교체 후 ${onTail.length}개(스네어 추가) · 킥 간격 오차 $worst3',
    );

    // 4) 위치가 돌고 있는가
    final e4 = Engine();
    final l4 = LoopState()..set(<dynamic>[], _kickOnly(), loopSec, true, e4);
    _run(e4, l4, 2.5);
    final pos = [
      for (final head in [0, loopFrames ~/ 4, loopFrames ~/ 2, loopFrames - 1])
        l4.posOf(l4.startAt + head),
    ];
    final posOk =
        (pos[0] - 0).abs() < 1e-9 &&
        (pos[1] - 0.25).abs() < 0.01 &&
        (pos[2] - 0.5).abs() < 0.01 &&
        pos[3] > 0.99;
    // 아직 이전 판을 듣고 있을 때(앞질러 예약된 상태) 되감기는가
    final back = l4.posOf(l4.startAt - loopFrames ~/ 2);
    check(
      '4) 위치',
      posOk && (back - 0.5).abs() < 0.01,
      '${pos.map((p) => p.toStringAsFixed(2)).join(' ')} · 이전 판 ${back.toStringAsFixed(2)}',
    );

    // 5) 정지
    final e5 = Engine();
    final l5 = LoopState()..set(<dynamic>[], _kickOnly(), loopSec, true, e5);
    _run(e5, l5, 1.2);
    l5.clear();
    e5.allOff();
    e5.clearSchedule();
    final buf5 = _run(e5, l5, 3.0);
    // **꼬리는 울려도 된다** — 정지는 「지금 나던 소리를 자르는 것」이 아니라
    // 「다음 것을 안 내는 것」이다. `_onsets` 는 앞 창이 없는 첫 창을 무조건
    // 타격으로 읽으므로(prevEnv 가 0에서 시작한다), 앞 0.3초는 앞 판의 꼬리로 본다.
    // (킥을 짧게 조인 뒤 여기가 걸렸다 — 소리가 아니라 **재는 법**이 문제였다.)
    final after = _onsets(buf5).where((f) => f > 14400).toList();
    // 그 대신 **꼬리가 실제로 죽는지**를 같이 본다 — 예전 검사에는 없던 것이다.
    var endMax = 0.0;
    for (var f = (buf5.length ~/ 2) - 24000; f < buf5.length ~/ 2; f++) {
      if (f < 0) continue;
      final v = (buf5[f * 2] / 32768.0).abs();
      if (v > endMax) endMax = v;
    }
    check(
      '5) 정지',
      after.isEmpty && endMax < 0.001,
      '정지 뒤 새 타격 ${after.length}개 · 마지막 0.5초 최대 '
          '${endMax.toStringAsFixed(5)}',
    );

    // ignore: avoid_print
    print(fail == 0 ? '씬 루프 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
