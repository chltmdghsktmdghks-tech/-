// 라이브 패드가 **무슨 소리를 낼지** 정하는 계산 (5단계 13/N).
//
// 화면(`ui/live_view.dart`)에서 떼어낸 이유는 편집기와 같다 — 여기가 이 화면의 약속이
// 걸린 자리라서다: **아무 패드나 눌러도 지금 조에 맞는 음이 나온다.**
// 그 약속은 귀로는 확인하기 어렵다(맞게 들리는지 아닌지 애매한 음이 있다). 숫자로 본다:
// 시험이 14개 패드의 주파수를 전부 꺼내 **음계 안에 있는지** 검사한다.
//
// 소리는 전부 라이브 버스(`kPartLive`)로 나간다 — 믹서의 라이브 페이더가 이 소리만 잡고,
// 곡 트랙은 안 건드린다.

import 'synth.dart' show kPartLive;
import 'theory.dart';

enum LiveMode { single, chord, arp }

class LivePads {
  /// 패드 하나 = 음계의 한 도수. 0~6 이 아래줄, 7~13 이 윗줄(한 옥타브 위).
  static const int count = 14;

  /// 옥타브 배율 — 2의 거듭제곱(한 옥타브 = 2배).
  static double octMul(int oct) {
    var v = 1.0;
    for (var i = 0; i < oct.abs(); i++) {
      v *= 2;
    }
    return oct < 0 ? 1 / v : v;
  }

  /// 도수 → 주파수. **곡을 만들 때 쓰는 `degreeFreq` 를 그대로 쓴다** —
  /// 다른 식으로 계산하면 반주와 라이브가 미묘하게 어긋난다.
  static double freqOf(int degree, MusicKey key, int oct) =>
      degreeFreq(degree.clamp(0, 14), 'melody', key) * octMul(oct);

  /// 그 도수의 **다이아토닉 3화음** — 조가 정해 주는 코드라 틀릴 수가 없다.
  static List<double> chordFreqs(int degree, MusicKey key, int oct) {
    final chords = diatonicChords(key);
    final spec = chords[degree % chords.length];
    // `diatonicChords` 는 근음을 `% 12` 로 접어서 늘 C4 언저리에 쌓는다 —
    // 곡의 코드 트랙은 그 자리가 맞다. 그런데 이 패드의 다른 셋은 **안 접힌**
    // 자리를 쓴다: 라벨([midiOf])·단음([freqOf])·녹음한 것의 재생(`degreeFreq`).
    // 그래서 C 가 아닌 조에서는 화음·아르페지오만 한 옥타브 밑으로 울렸고,
    // 그걸 녹음해 두면 재생될 때는 **들었던 것보다 한 옥타브 위**로 나왔다.
    // 접힌 만큼 되돌려서 넷을 같은 자리에 세운다(C 조는 fold 가 늘 0 이라 그대로).
    final fold = (key.root + scaleOf(key.mode)[degree % 7]) ~/ 12;
    final mul = octMul(oct + (degree >= 7 ? 1 : 0) + fold);
    return [for (final f in chordFreqsOf(spec)) f * mul];
  }

  /// 패드를 눌렀을 때 엔진에 보낼 것들.
  /// 한 줄 형식은 `AudioClient.batch` 와 같다: [voice, freq, dur, vel, soft, glide, delay, part]
  static List<List<dynamic>> events(
    int degree, {
    required LiveMode mode,
    required MusicKey key,
    required int oct,
    required String voice,
    required double dur,
    int vel = 3,
  }) {
    switch (mode) {
      case LiveMode.single:
        return [
          [
            voice,
            freqOf(degree, key, oct),
            dur,
            vel,
            false,
            0.0,
            0.0,
            kPartLive,
          ],
        ];
      case LiveMode.chord:
        // 반주처럼 살짝 죽여서(soft) — 안 그러면 3음이 겹쳐 라이브가 반주를 덮는다
        return [
          for (final f in chordFreqs(degree, key, oct))
            [voice, f, dur * 1.6, vel, true, 0.0, 0.0, kPartLive],
        ];
      case LiveMode.arp:
        final fs = chordFreqs(degree, key, oct);
        final up = [...fs, if (fs.isNotEmpty) fs.first * 2];
        return [
          for (var i = 0; i < up.length; i++)
            [voice, up[i], dur, vel, false, 0.0, i * 0.11, kPartLive],
        ];
    }
  }

  /// 도수 → 계이름(C·D#…). 무슨 음을 누르는지 보이면 **배우게 된다**.
  static int midiOf(int degree, MusicKey key, int oct) {
    final sc = scaleOf(key.mode);
    return 60 + sc[degree % 7] + 12 * (degree ~/ 7) + key.root + 12 * oct;
  }
}

/// **반음 건반**(프로 모드) — 다이아토닉 패드와 달리 12음 전부를 낸다.
///
/// [semi] 는 `semiFreq` 와 같은 뜻: 으뜸음에서 몇 반음 위인가(0 = 으뜸음).
/// 화음·아르페지오는 여기 없다 — `diatonicChords` 가 도수를 전제로 하는데
/// 반음은 임의의 음이라 「이 반음의 3화음」이 조에 안 맞을 수 있다. 반음
/// 건반은 **단음**만 낸다(코드는 다이아토닉 패드나 편집기에서).
class ChromaticPad {
  /// 반음 → 주파수. `semiFreq` 를 그대로 쓴다(재생·녹음 계산과 같은 식).
  static double freqOf(int semi, MusicKey key, int oct) =>
      semiFreq(semi, 'melody', key) * LivePads.octMul(oct);

  /// 패드를 눌렀을 때 엔진에 보낼 것 — 형식은 `LivePads.events` 와 같다.
  static List<List<dynamic>> events({
    required int semi,
    required MusicKey key,
    required int oct,
    required String voice,
    required double dur,
    int vel = 3,
  }) => [
    [voice, freqOf(semi, key, oct), dur, vel, false, 0.0, 0.0, kPartLive],
  ];

  /// 이 반음이 **지금 조의 음계 안**인가(초보 모드가 흐리게·묵음으로 쓸 값).
  static bool inScale(int semi, MusicKey key) =>
      scaleOf(key.mode).contains(semi % 12);

  /// 반음 → 계이름(C·D#…) — 다이아토닉 패드의 `LivePads.midiOf` 와 같은 뜻.
  static int midiOf(int semi, MusicKey key, int oct) =>
      60 + key.root + semi + 12 * oct;
}

/// 친 걸 **트랙으로 남긴다** (5단계 14/N).
///
/// 패드가 음계의 도수라서 녹음이 간단해진다 — 무슨 음인지 이미 알고 있으니
/// 음높이를 알아낼 필요가 없고, 결과가 **편집기와 똑같은 형식**([도수,스텝,길이,세기])
/// 으로 바로 나온다. 녹음한 걸 편집기에서 이어서 고칠 수 있다는 뜻이다.
///
/// ── 박자는 자동으로 맞춘다 ──
/// 패턴은 16분음표 칸 단위라 **맞추지 않을 수가 없다**(칸 사이에 음을 둘 곳이 없다).
/// 초보에게는 이게 오히려 기능이다 — 조금 어긋나게 쳐도 판에 딱 붙는다.
///
/// ── 늦게 잡히는 문제 ──
/// 귀에 들리는 소리는 엔진이 만든 것보다 **한 박자 늦게** 나온다(앞질러 만든 양 +
/// 장치 버퍼). 그래서 "제때 쳤다"고 느낀 순간의 위치는 실제보다 그만큼 뒤다.
/// 그대로 반올림하면 한 칸씩 밀린 판이 나온다 → [latencySec] 만큼 되돌린 뒤 맞춘다.
class LiveRecorder {
  /// 한 판의 칸 수(마디 × 16).
  final int steps;
  final double loopSec;
  final double latencySec;

  /// (도수, 칸) → 한 줄. 같은 자리를 다시 치면 덮어쓴다(겹쳐 녹음).
  final Map<String, List<Object?>> _hits = {};

  LiveRecorder({
    required this.steps,
    required this.loopSec,
    this.latencySec = 0,
  });

  int get count => _hits.length;

  /// [pos] 는 지금 판 안의 위치(0~1). [lenSteps] 는 남길 음 길이(칸).
  void hit(int degree, double pos, {int lenSteps = 2, int vel = 3}) {
    if (steps <= 0) return;
    final back = loopSec > 0 ? latencySec / loopSec : 0.0;
    final p = ((pos - back) % 1.0 + 1.0) % 1.0;
    final step = (p * steps).round() % steps;
    _hits['$degree:$step'] = [
      degree,
      step,
      lenSteps.clamp(1, steps),
      vel.clamp(1, 3),
    ];
  }

  /// 칸 순서로 정리해서 돌려준다(편집기가 읽는 순서와 같게).
  List<List<Object?>> notes() {
    final out = [for (final n in _hits.values) List<Object?>.from(n)];
    out.sort((a, b) => (a[1] as int).compareTo(b[1] as int));
    return out;
  }

  void clear() => _hits.clear();
}

// ── 메트로놈 ──
//
// 드럼이 없는 씬(패드·코드만)에서 녹음하면 **기댈 박이 아예 없다.** 반주는 흐르는데
// 어디가 1박인지 안 들리니 박에 맞춰 칠 수가 없다.
//
// ── 화면 타이머로 「지금」 울리면 안 된다 ──
// 프레임은 16ms 마다 오고 그마저 밀린다. 박을 ±16ms 로 흔드는 메트로놈은 자가 아니라
// 소음이다. 그래서 **앞질러 예약한다** — 엔진은 delay 를 받아 샘플 단위로 놓는다
// (`scheduleDrum`). 화면은 「무엇을 언제 놓을지」만 정하고 시각은 엔진이 지킨다.
//
// 아래 [beatsToSend] 가 그 「무엇을 언제」다. 여기가 이 기능에서 틀릴 수 있는
// 전부라(두 번 놓기·건너뛰기·판 넘어가기) 화면에서 떼어 놓고 시험이 직접 잰다.

/// 앞질러 예약할 박 하나 — 판 안의 몇 번째 박인가, 지금부터 몇 초 뒤인가.
class MetTick {
  /// 판 안에서 몇 번째 박인가(0부터). 마디 첫 박은 `beat % 4 == 0`.
  final int beat;

  /// 지금부터 몇 초 뒤에 놓을 것인가.
  final double delay;
  const MetTick(this.beat, this.delay);
}

/// **지금 예약해야 할 박들.**
///
/// [nowSec] 은 판 안의 지금 위치, [loopSec] 은 한 판 길이, [beatSec] 은 한 박.
/// [sent] 는 이번 바퀴에 이미 예약한 박 번호 — **여기에 담긴 것은 다시 안 낸다**
/// (같은 박을 두 번 놓으면 두 번 들린다. 앞질러 예약하는 방식의 유일한 함정이다).
///
/// [lead] 만큼 앞을 내다본다. 부르는 쪽이 그보다 자주 부르면 빈틈이 안 생긴다.
/// [gap] 은 너무 코앞의 박은 건너뛰는 여유다 — 이미 지나간 것을 예약하면
/// 엔진이 곧바로 울려서 박이 앞으로 튄다.
List<MetTick> beatsToSend({
  required double nowSec,
  required double loopSec,
  required double beatSec,
  required Set<int> sent,
  double lead = 0.4,
  double gap = 0.03,
}) {
  if (loopSec <= 0 || beatSec <= 0) return const [];
  final out = <MetTick>[];
  final from = nowSec + gap;
  var k = (from / beatSec).ceil();
  if (k < 0) k = 0;
  while (k * beatSec < nowSec + lead) {
    final t = k * beatSec;
    // 판을 넘는 것은 **다음 바퀴에** 잡는다 — 넘어가면 `sent` 를 비우기 때문이다
    if (t >= loopSec) break;
    if (!sent.contains(k)) out.add(MetTick(k, t - nowSec));
    k++;
  }
  return out;
}

/// 예약할 박들을 **엔진에 보낼 줄**로 바꾼다 (`AudioClient.batch` 형식).
///
/// ── 왜 드럼이 아니라 라이브 버스인가 ──
/// 여태 메트로놈은 드럼 킷의 'rim' 이었다. 그러면 **드럼 버스에 실린다** — 믹서에서
/// 드럼을 줄이면 자까지 같이 작아지고, 「반주 끄기」로 트랙을 다 내리면 **자가 통째로
/// 사라진다.** 박을 세는 소리는 곡의 일부가 아니라 **곡을 재는 소리**다. 곡 볼륨에
/// 딸려 가면 안 된다. 그래서 라이브 버스로 낸다(`kPartLive`).
///
/// 마디 첫 박은 한 옥타브 위로 세게 — 어디가 1박인지 안 들리면 자가 아니다.
List<List<dynamic>> metroBatch(
  List<MetTick> ticks, {
  int beatsPerBar = 4,
  String voice = 'marimba',
}) => [
  for (final t in ticks)
    [
      voice,
      t.beat % beatsPerBar == 0 ? 1568.0 : 1046.5,
      0.06, // 짧게 — 길면 박이 아니라 음이 된다
      t.beat % beatsPerBar == 0 ? 3 : 1,
      false,
      0.0,
      t.delay,
      kPartLive,
    ],
];
