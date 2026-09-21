// 드럼 — 웹의 vKick/vSnare/vHat/vTom/vCrash/vRide/vRim/vClap/vShaker/vCowbell 를 그대로 옮긴 것.
// 값과 신호 흐름(어떤 필터를 몇 단으로, 엔벨로프 전/후 어디에 거는지)은 전부
// ~/AI Company/music_doodle/assets/app.html 의 검증된 코드를 그대로 따랐다.
//
// pitched() 와 다른 점: 드럼 타격 하나는 몇 개의 **짧은 레이어**(오실레이터 1~2개,
// 필터를 거친 노이즈, 금속 클러스터)가 동시에 울리고 곧 끝난다. 배음을 쌓아 하나의
// 음을 만드는 SynthNote 와는 결이 달라서 별도로 만든다.
//
// 레이어 3종:
//   Tone    — 오실레이터 1개. 피치가 시간에 따라 떨어질 수 있다(킥·탐·림의 '때리는' 느낌).
//             필터는 **엔벨로프 뒤에** 걸 수 있다(탐의 쉘 공명 — 웹: o→g→pk→dest).
//   Noise   — 잡음이 필터 체인(최대 3단)을 거친 뒤 엔벨로프를 곱한다(웹: noise→filters→gain).
//             스네어만 밴드패스 중심주파수가 시간에 따라 움직인다(열렸다 닫히는 느낌).
//   Cluster — 오실레이터 여러 개(금속 클러스터 6개 또는 카우벨 2개)를 합쳐 **엔벨로프 앞**
//             필터 1단을 거친다(웹: osc들→highpass/bandpass→gain).
// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dsp.dart';
import 'drum_sampler.dart';
import 'instruments.dart' show VG;
import 'synth.dart' show Human;

// ───────────────────────── 키트 데이터 ─────────────────────────
// 웹 DRUM_KITS 를 그대로 옮긴 값. 왜 이 값인지는 이 파일이 아니라
// ~/AI Company/music_doodle/HANDOFF.md 와 app.html 의 주석에 있다 — 바꾸지 않는다.

class KickK {
  final double f, end, rel, punch, click, clickHz, drive, sub;
  const KickK(
    this.f,
    this.end,
    this.rel,
    this.punch,
    this.click,
    this.clickHz,
    this.drive,
    this.sub,
  );
}

class SnareK {
  final double tone0, tone1, noise, rel, bright, wire, open, shell;
  const SnareK(
    this.tone0,
    this.tone1,
    this.noise,
    this.rel,
    this.bright,
    this.wire,
    this.open,
    this.shell,
  );
}

class HatK {
  final double hi, rel, tune, metal, noise;
  const HatK(this.hi, this.rel, this.tune, this.metal, this.noise);
}

class TomK {
  final double mul, rel, shell, drive;
  const TomK(this.mul, this.rel, this.shell, this.drive);
}

class CrashK {
  final double rel, hi, tune, metal, noise;
  const CrashK(this.rel, this.hi, this.tune, this.metal, this.noise);
}

class RideK {
  final double rel, hi, tune, bell;
  const RideK(this.rel, this.hi, this.tune, this.bell);
}

class RimK {
  final double f, rel, wood, noise;
  const RimK(this.f, this.rel, this.wood, this.noise);
}

class ClapK {
  final int n;
  final double spread, bp, q, rel, tail;
  const ClapK(this.n, this.spread, this.bp, this.q, this.rel, this.tail);
}

class ShakeK {
  final double hi, bp, rel;
  const ShakeK(this.hi, this.bp, this.rel);
}

class CowK {
  final double f0, f1, rel, bp;
  const CowK(this.f0, this.f1, this.rel, this.bp);
}

class DrumKit {
  final String label;
  final KickK kick;
  final SnareK snare;
  final HatK hat;
  final TomK tom;
  final CrashK crash;
  final RideK ride;
  final RimK rim;
  final ClapK clap;
  final ShakeK shake;
  final CowK cow;

  /// 이 킷은 표본(실제 녹음)이 있으면 그걸 우선한다 — 어쿠스틱/록처럼 "실제
  /// 드럼 소리"를 노리는 킷만 켠다. 808·909·로파이는 **의도적으로 전자음**
  /// 이라, 표본을 켜면 오히려 그 킷의 정체성이 사라진다(`drum_sampler.dart`).
  final bool sampled;
  const DrumKit({
    required this.label,
    required this.kick,
    required this.snare,
    required this.hat,
    required this.tom,
    required this.crash,
    required this.ride,
    required this.rim,
    required this.clap,
    required this.shake,
    required this.cow,
    this.sampled = false,
  });
}

const Map<String, DrumKit> DRUM_KITS = {
  'acoustic': DrumKit(
    sampled: true,
    label: '어쿠스틱',
    kick: KickK(180, 48, 0.40, 0.028, 0.62, 2800, 0.26, 0.18),
    snare: SnareK(188, 332, 1300, 0.52, 3600, 1.00, 2.2, 5),
    hat: HatK(7000, 0.058, 1.00, 0.30, 1.00),
    tom: TomK(1.00, 0.36, 5, 0.12),
    crash: CrashK(1.60, 3400, 1.00, 0.55, 1.00),
    ride: RideK(1.00, 3200, 1.00, 0.40),
    rim: RimK(1750, 0.038, 0.55, 0.22),
    clap: ClapK(3, 0.011, 1350, 1.1, 0.17, 0.30),
    shake: ShakeK(6000, 8800, 0.040),
    cow: CowK(540, 800, 0.15, 2640),
  ),
  'k808': DrumKit(
    label: '808',
    kick: KickK(120, 26, 0.62, 0.048, 0.40, 1800, 0.10, 0.50),
    snare: SnareK(210, 0, 2000, 0.38, 4200, 0.70, 1.4, 2),
    hat: HatK(8600, 0.038, 1.00, 0.85, 0.45),
    tom: TomK(0.80, 0.45, 2, 0.08),
    crash: CrashK(1.10, 4600, 1.06, 0.75, 0.60),
    ride: RideK(0.75, 4200, 1.06, 0.28),
    rim: RimK(2100, 0.026, 0.30, 0.30),
    clap: ClapK(3, 0.009, 1500, 1.4, 0.13, 0.22),
    shake: ShakeK(7000, 10000, 0.032),
    // 808 카우벨은 상징이라 길게
    cow: CowK(540, 800, 0.30, 2640),
  ),
  'k909': DrumKit(
    label: '909',
    kick: KickK(200, 46, 0.50, 0.018, 0.88, 3200, 0.32, 0.18),
    snare: SnareK(200, 360, 1600, 0.55, 3900, 1.25, 2.8, 3),
    hat: HatK(9000, 0.050, 1.03, 0.62, 0.80),
    tom: TomK(1.05, 0.32, 3, 0.14),
    crash: CrashK(1.35, 4000, 1.03, 0.68, 0.90),
    ride: RideK(0.85, 3800, 1.03, 0.34),
    rim: RimK(1900, 0.030, 0.40, 0.28),
    // 909 클랩 = 4연타 + 긴 꼬리
    clap: ClapK(4, 0.0085, 1200, 0.9, 0.20, 0.42),
    shake: ShakeK(6600, 9400, 0.036),
    cow: CowK(560, 830, 0.18, 2700),
  ),
  'lofi': DrumKit(
    // 실제 녹음 표본을 쓴다(사용자 지적, 2026-09-13: "드럼퀄리티 실화냐") —
    // 로파이 힙합은 원래도 신시사이저 808/909 킥이 아니라 **진짜 드럼 브레이크**를
    // 늘어뜨려 쓰는 장르다. 여태는 `sampled` 가 안 켜져 있어서 킥·스네어·하이햇이
    // 전부 합성(파라미터 모델)으로 났다 — `acoustic`/`rock` 만 켜져 있었다.
    // 아래 킥·스네어 등 합성 값은 **표본이 없는 조각(림·클랩·셰이크·카우벨)의
    // 대비용으로 그대로 둔다** — `sampled` 켜져 있어도 표본이 없는 조각은
    // 자동으로 이 값들로 떨어진다(`drums.dart` 의 `trigger()` 참고).
    sampled: true,
    label: '로파이',
    kick: KickK(150, 42, 0.50, 0.036, 0.44, 1600, 0.38, 0.18),
    snare: SnareK(176, 300, 900, 0.55, 2400, 0.75, 1.6, 6),
    hat: HatK(5200, 0.046, 0.97, 0.25, 1.00),
    tom: TomK(0.95, 0.34, 6, 0.22),
    crash: CrashK(1.20, 2600, 0.96, 0.35, 1.00),
    ride: RideK(0.80, 2600, 0.96, 0.22),
    rim: RimK(1550, 0.042, 0.65, 0.18),
    clap: ClapK(3, 0.013, 1050, 0.9, 0.18, 0.34),
    shake: ShakeK(4800, 7200, 0.044),
    cow: CowK(510, 760, 0.16, 2300),
  ),
  'rock': DrumKit(
    sampled: true,
    label: '록',
    kick: KickK(190, 52, 0.54, 0.022, 0.76, 3000, 0.30, 0.16),
    snare: SnareK(196, 352, 1700, 0.62, 3700, 1.15, 3.0, 6),
    hat: HatK(7600, 0.075, 1.00, 0.34, 1.00),
    tom: TomK(1.12, 0.42, 6, 0.16),
    crash: CrashK(2.00, 3200, 1.00, 0.60, 1.10),
    ride: RideK(1.20, 3000, 1.00, 0.45),
    rim: RimK(1700, 0.040, 0.60, 0.25),
    clap: ClapK(3, 0.012, 1400, 1.0, 0.19, 0.32),
    shake: ShakeK(6200, 9000, 0.042),
    cow: CowK(560, 820, 0.16, 2700),
  ),
};

const List<String> DRUM_KIT_ORDER = [
  'acoustic',
  'k808',
  'k909',
  'lofi',
  'rock',
];

const Map<String, String> DRUM_LABEL = {
  'kick': '킥',
  'snare': '스네어',
  'hat': '하이햇',
  'tom': '탐',
  'crash': '크래시',
  'ride': '라이드',
  'rim': '림샷',
  'clap': '박수',
  'shake': '쉐이커',
  'cow': '카우벨',
};

/// **소리 쪽 이름과 데이터 쪽 이름이 달랐다.** (2026-08-30)
///
/// `patterns.dart` 의 `kDrumLanes` 는 'shaker'·'cowbell' 을 쓰고, 여기 `trigger` 의
/// 스위치는 'shake'·'cow' 만 알았다. 그래서 시퀀서가 예약한 셰이커·카우벨이
/// **전부 무음**이었다 — 15곡 전체 타격 14775개 중 **2361개(16%)**.
/// 오류도 안 나고, 다른 타악기는 멀쩡히 나니 「그냥 안 들리는 층」으로 남아 있었다.
/// (`drum_check_test` 는 `DRUM_ORDER`, 즉 **소리 쪽 이름**으로만 확인해서 못 봤다.)
///
/// 한쪽으로 통일하지 않는 이유: 데이터 쪽 이름은 **사용자가 편집기에서 만든 패턴에
/// 저장돼 있다.** 바꾸면 그 패턴들이 이름을 잃는다. 그래서 둘 다 받는다.
const Map<String, String> kDrumAlias = {'shaker': 'shake', 'cowbell': 'cow'};

/// 데이터 쪽 이름을 소리 쪽 이름으로. 모르는 이름은 그대로 둔다.
String drumName(String lane) => kDrumAlias[lane] ?? lane;

const List<String> DRUM_ORDER = [
  'kick',
  'snare',
  'hat',
  'tom',
  'crash',
  'ride',
  'rim',
  'clap',
  'shake',
  'cow',
];

// 씨앗을 박아 둔다 — 안 그러면 **같은 곡을 내보낼 때마다 파일이 달라진다**
// (박수는 원래 타격마다 흩어지는 소리라 난수를 쓴다).
final math.Random _rnd = math.Random(20260820);
double _rnd2() => _rnd.nextDouble() * 2 - 1;

/// 이 타격 한 번만의 미세한 흔들림 (5단계 49/N).
///
/// 실제 드러머는 같은 자리를 두 번 똑같이 못 친다. 매번 똑같은 파형이 나오면
/// **'머신건'** 으로 들린다 — 16비트 하이햇에서 제일 티가 난다.
/// 세기는 `Human.level` 을 따른다(0 = 흔들림 없음, 2 = 두 배).
class _Hit {
  double pitch = 1, amp = 1, tone = 1, rel = 1;
}

// ───────────────────────── 레이어 ─────────────────────────

class _Tone {
  Float32List? tab;
  double phase = 0;
  bool ramp = false;
  final Env freqEnv = Env();
  double inc = 0; // 고정 주파수(ramp==false)일 때 위상 증가량
  final Env amp = Env();
  final Biquad post = Biquad(); // 엔벨로프 '뒤'에 거는 필터 (탐의 쉘 공명 전용)
  bool hasPost = false;
  bool on = false;
}

class _NoiseLayer {
  final Noise rng = Noise();
  final List<Biquad> filt = [Biquad(), Biquad(), Biquad()];
  int nFilt = 0;
  int bpIdx = -1; // 이동하는 밴드패스가 있으면 그 필터의 인덱스 (스네어 전용)
  final Env bpFreq = Env();
  double bpQ = 1.0;
  final Env amp = Env();
  int delay = 0; // 시작까지 남은 샘플 (클랩의 다중 타격)
  bool on = false;
}

class _ClusterLayer {
  static const int kMax = 6;
  int n = 0;
  final Float64List phase = Float64List(kMax);
  final Float64List inc = Float64List(kMax);
  final List<Float32List?> tab = List.filled(kMax, null);
  final Biquad pre = Biquad(); // 엔벨로프 '앞'에 거는 필터 (금속: 하이패스 / 카우벨: 밴드패스)
  bool hasPre = false;
  final Env amp = Env();
  bool on = false;
}

const int _kModStride = 16; // 스네어 이동 밴드패스 계수 갱신 간격 (synth.dart 와 같은 값)

/// 드럼 타격 하나. 풀에서 꺼내 쓰고 끝나면 반납한다 (SynthNote 와 같은 방식).
class DrumVoice {
  bool active = false;
  double outL = 0, outR = 0;

  int _life = 0;
  int _age = 0;

  static const int _kTone = 2;
  static const int _kNoise = 5; // 909 클랩(4연타) + 꼬리 = 5
  int _nt = 0, _nn = 0;
  final List<_Tone> _tones = List.generate(_kTone, (_) => _Tone());
  final List<_NoiseLayer> _noises = List.generate(
    _kNoise,
    (_) => _NoiseLayer(),
  );
  final _ClusterLayer _cluster = _ClusterLayer();

  /// 지금 울리는 타악기 이름 — 초킹(하이햇 끊기)에 쓴다.
  String inst = '';

  final _Hit _hit = _Hit();
  bool _varyOn = false;

  // ── 표본 모드 (`drum_sampler.dart`) ── `SynthNote._nextSample` 과 같은
  // 생각이지만 dur 기반 release 가 없다 — 타격은 원래 한 번 나고 끝난다.
  bool _sampleMode = false;
  Int16List? _smPcm;
  double _smPos = 0, _smRatio = 1, _smGain = 0;

  /// 라운드로빈을 고르는 난수 — 곡을 다시 내보내도 같은 결과가 나오게
  /// 씨앗을 박아 둔다(`_rnd` 와 같은 이유).
  static final math.Random _rrRng = math.Random(20260910);

  /// **좌우 자리** — 실제 드럼 세트는 한 점에서 나지 않는다 (Phase 3 · 계획 5-4).
  /// 전부 가운데서 나면 심벌과 스네어가 같은 자리에서 겹쳐 뭉친다.
  ///
  /// 앞에서 본 기준이다(쇼 화면 밴드 그림과 같은 좌우) — 오른손잡이 드러머의
  /// 하이햇은 **우리 오른쪽**, 라이드는 우리 왼쪽. 킥·스네어는 가운데(골격이라
  /// 한쪽으로 치우치면 곡이 기운다).
  double _panL = 1, _panR = 1;

  static const Map<String, double> _panOf = {
    'kick': 0.0,
    'snare': 0.05,
    'rim': 0.05,
    'clap': 0.0,
    'hat': 0.34,
    'crash': 0.30,
    'cow': 0.16,
    'ride': -0.34,
    'tom': -0.18,
    'shake': -0.22,
  };

  void _setPan(double pan) {
    // 등파워 — 가운데(0)에서 좌우 합이 커지지 않게. 모노였던 때와 같은 크기다.
    final a = (pan.clamp(-1.0, 1.0) + 1) * math.pi / 4;
    _panL = math.cos(a) * math.sqrt2;
    _panR = math.sin(a) * math.sqrt2;
  }

  int _chokeN = 0, _chokeLeft = 0;

  /// 이 타격만의 흔들림을 뽑는다. 각 타악기가 자기 폭을 정해서 부른다.
  void _vary({
    double pitch = 0.025,
    double amp = 0.06,
    double tone = 0.08,
    double rel = 0.08,
  }) {
    final k = Human.level == 0 ? 0.0 : (Human.level == 1 ? 1.0 : 2.0);
    _varyOn = k > 0;
    _hit.pitch = 1 + _rnd2() * pitch * k;
    _hit.amp = 1 + _rnd2() * amp * k;
    _hit.tone = 1 + _rnd2() * tone * k;
    _hit.rel = 1 + _rnd2() * rel * k;
  }

  /// **소리를 멎게 한다** — 하이햇을 닫는 것.
  /// 뚝 끊으면 '틱' 하고 튀므로 짧게 훑어 내린다.
  void choke([double sec = 0.012]) {
    if (!active) return;
    final n = math.max(1, (sec * kSampleRate).round());
    if (_chokeLeft > 0 && _chokeLeft <= n) return; // 이미 더 빨리 멎는 중
    _chokeN = n;
    _chokeLeft = n;
  }

  void reset() {
    active = false;
    _sampleMode = false;
    _life = 0;
    _age = 0;
    _chokeN = 0;
    _chokeLeft = 0;
    _varyOn = false;
    _panL = 1;
    _panR = 1;
    _hit.pitch = 1;
    _hit.amp = 1;
    _hit.tone = 1;
    _hit.rel = 1;
    _nt = 0;
    _nn = 0;
    for (final t in _tones) {
      t.on = false;
      t.hasPost = false;
    }
    for (final n in _noises) {
      n.on = false;
      n.nFilt = 0;
      n.bpIdx = -1;
      n.delay = 0;
    }
    _cluster.on = false;
    _cluster.n = 0;
    _cluster.hasPre = false;
  }

  // ── 레이어 빌더 ──

  void _addTone({
    required WaveSet wave,
    required double startFreq,
    List<List<double>>? rampSegs, // [[초, 도착주파수], ...] — exp 램프. null 이면 고정 주파수.
    required double a,
    required double h,
    required double r,
    required double peak,
    double? sus,
    void Function(Biquad)? postSetup,
  }) {
    if (_nt >= _kTone) return;
    final t = _tones[_nt++];
    t.on = true;
    t.phase = 0;
    t.tab = wave.tableFor(startFreq);
    if (rampSegs != null && rampSegs.isNotEmpty) {
      t.ramp = true;
      t.freqEnv.clear();
      for (final seg in rampSegs) {
        t.freqEnv.add(seg[0], seg[1], exp: true);
      }
      // 마지막 값에서 계속 머문다 — 안 그러면 램프가 끝나는 순간 next() 가 0 을 돌려준다
      // (Env 는 원래 '음량' 이 0 으로 꺼지는 걸 표현하려고 만들어졌기 때문).
      t.freqEnv.add(3.0, rampSegs.last[1]);
      t.freqEnv.start(from: startFreq);
    } else {
      t.ramp = false;
      t.inc = startFreq / kSampleRate;
    }
    t.hasPost = postSetup != null;
    if (postSetup != null) {
      t.post.reset();
      postSetup(t.post);
    }
    buildAdsr(t.amp, a, h, r, peak, sus);
    final n = t.amp.totalSamples + (0.05 * kSampleRate).round();
    if (n > _life) _life = n;
  }

  void _addNoise(
    List<void Function(Biquad)> filters, {
    required double a,
    required double h,
    required double r,
    required double peak,
    double? sus,
    double delaySec = 0,
  }) {
    if (_nn >= _kNoise) return;
    final nl = _noises[_nn++];
    // **타격마다 다른 잡음.** 이게 없으면 아무리 음량·밝기를 흔들어도
    // 파형 자체가 같아서 하이햇 16비트가 '머신건'으로 들린다.
    if (_varyOn) nl.rng.seed(_rnd.nextInt(0x7FFFFFFF));
    nl.nFilt = filters.length.clamp(0, 3);
    for (var i = 0; i < nl.nFilt; i++) {
      nl.filt[i].reset();
      filters[i](nl.filt[i]);
    }
    nl.bpIdx = -1;
    buildAdsr(nl.amp, a, h, r, peak, sus);
    nl.delay = (delaySec * kSampleRate).round();
    nl.on = true;
    final n = nl.delay + nl.amp.totalSamples + (0.05 * kSampleRate).round();
    if (n > _life) _life = n;
  }

  /// 스네어 전용 — 밴드패스 중심주파수가 시간에 따라 열렸다 닫힌다.
  void _addSnareNoise(
    SnareK k,
    double v, {
    double wireMul = 1,
    double brightMul = 1,
    double relMul = 1,
  }) {
    if (_nn >= _kNoise) return;
    final nl = _noises[_nn++];
    if (_varyOn) nl.rng.seed(_rnd.nextInt(0x7FFFFFFF));
    var idx = 0;
    nl.filt[idx].reset();
    nl.filt[idx].highpass(k.noise, 0);
    idx++;
    final bpIdx = idx;
    nl.filt[bpIdx].reset();
    nl.filt[bpIdx].bandpass(k.bright * k.open * brightMul, 0.55);
    idx++;
    nl.bpIdx = bpIdx;
    nl.bpQ = 0.55;
    nl.bpFreq.clear();
    // 밝기는 **빨리** 내려온다. 스네어의 '크랙'은 첫 10ms 안에 다 나온다.
    //
    // 여기를 꼬리 길이(`k.rel`)에 묶어 두면 **꼬리를 늘릴 때 크랙까지 늦어진다** —
    // 실제로 꼬리를 늘렸더니 어택이 7.7ms → 10.3ms 로 밀렸다. 위쪽에서 시작한
    // 밴드패스가 아직 안 내려와서 첫 순간에 통과하는 게 거의 없기 때문이다.
    // 스윕은 짧게 못 박고, 꼬리는 진폭 엔벨로프가 따로 맡는다.
    nl.bpFreq.add(
      math.min(0.13, k.rel * 0.6) * relMul,
      k.bright * 0.72 * brightMul,
      exp: true,
    );
    nl.bpFreq.add(3.0, k.bright * 0.72 * brightMul);
    nl.bpFreq.start(from: k.bright * k.open * brightMul);
    if (k.shell > 0) {
      nl.filt[idx].reset();
      nl.filt[idx].peaking(k.tone0 * 1.6, 1.1, k.shell);
      idx++;
    }
    nl.nFilt = idx;
    nl.bpIdx = bpIdx;
    nl.delay = 0;
    nl.on = true;
    buildAdsr(
      nl.amp,
      0.0008,
      0.010,
      k.rel * relMul,
      0.5 * k.wire * v * wireMul,
      null,
    );
    final n = nl.amp.totalSamples + (0.05 * kSampleRate).round();
    if (n > _life) _life = n;
  }

  void _addCluster({
    required List<double> freqs,
    required List<WaveSet> waves,
    void Function(Biquad)? preSetup,
    required double a,
    required double h,
    required double r,
    required double peak,
    double? sus,
  }) {
    final c = _cluster;
    c.n = freqs.length.clamp(0, _ClusterLayer.kMax);
    for (var i = 0; i < c.n; i++) {
      c.phase[i] = 0;
      c.inc[i] = freqs[i] / kSampleRate;
      c.tab[i] = waves[i].tableFor(freqs[i]);
    }
    c.hasPre = preSetup != null;
    if (preSetup != null) {
      c.pre.reset();
      preSetup(c.pre);
    }
    buildAdsr(c.amp, a, h, r, peak, sus);
    c.on = true;
    final n = c.amp.totalSamples + (0.05 * kSampleRate).round();
    if (n > _life) _life = n;
  }

  // ── 타격 ──

  void kick(DrumKit kit, int vel) {
    reset();
    final k = kit.kick;
    final v = VG[vel] ?? 1.0;
    _vary(pitch: 0.018, amp: 0.05, tone: 0.06, rel: 0.06);
    final vr = vel / 3.0;
    // 세게 밟을수록 비터가 헤드를 더 세게 밀어 **음정이 더 높이 튀었다 떨어진다.**
    // (세기 2 에서 예전 값과 같다 — 이미 맞춰 둔 소리를 흔들지 않으려고)
    final pu = _hit.pitch * (0.90 + 0.15 * vr);
    _addTone(
      wave: k.drive > 0 ? satWave(k.drive) : wSine,
      startFreq: k.f * pu,
      rampSegs: [
        [k.punch, k.end * 2.1 * _hit.pitch],
        [k.punch * 3, k.end * 1.25 * _hit.pitch],
        // 세 번째 마디는 **음정이 바닥에 앉는 시간**이다. 0.26초는 너무 길어서
        // 킥이 「둥—」 하고 끌렸다(사용자: 「킥이 전반적으로 너무 뚱뚱거려」).
        // 빨리 앉을수록 단단하게 들린다.
        [math.max(0.001, 0.19 - k.punch * 4), k.end * _hit.pitch],
      ],
      a: 0.0012,
      h: 0.03,
      r: k.rel * _hit.rel,
      peak: 1.0 * v * _hit.amp,
    );
    if (k.sub > 0) {
      _addTone(
        wave: wSine,
        startFreq: k.end * 1.05 * _hit.pitch,
        a: 0.002,
        h: k.rel * 0.5,
        r: k.rel * 0.9 * _hit.rel,
        peak: k.sub * v * _hit.amp,
      );
    }
    if (k.click > 0) {
      // 비터가 닿는 '딱' — 세게 밟을수록 **음량보다 먼저 이게 늘어난다.**
      // 여태는 세기와 비율이 같아서 살살 밟아도 딱 소리가 똑같이 났다.
      _addNoise(
        [(b) => b.highpass(k.clickHz * (0.82 + 0.27 * vr) * _hit.tone, 0)],
        a: 0.0004,
        h: 0.002,
        r: 0.016,
        peak: k.click * (0.24 + 0.39 * vr) * v * _hit.amp,
      );
    }
    active = true;
  }

  void snare(DrumKit kit, int vel) {
    reset();
    final k = kit.snare;
    final v = VG[vel] ?? 1.0;
    _vary(pitch: 0.022, amp: 0.07, tone: 0.09, rel: 0.09);
    final vr = vel / 3.0;
    // **고스트 노트는 거의 줄(스네어 와이어) 소리만 난다.** 살짝 스치면 헤드가
    // 제대로 안 울려서 몸통 음정은 묻히고 줄 버즈만 남는다. 여태는 세기가
    // 둘을 똑같이 줄여서, 여린 타격이 그냥 '작은 스네어'로만 들렸다.
    final wireMul = 1.15 - 0.15 * vr; // 여리게 1.10 → 세게 1.00
    final toneMul = 0.80 + 0.20 * vr; // 여리게 0.87 → 세게 1.00
    // 줄 비중은 여릴 때 높지만 **밝기 자체는 세게 칠 때가 위**다.
    // 세게 치면 헤드가 크게 휘면서 높은 모드가 같이 깨어난다(그게 '크랙').
    _addSnareNoise(
      k,
      v,
      wireMul: wireMul * _hit.amp,
      brightMul: (0.70 + 0.45 * vr) * _hit.tone,
      relMul: _hit.rel,
    );
    // 몸통을 바로 감쇠시키면 타점은 살아나지만 **두께가 얇아진다**(150~400Hz 가
    // 34% → 29% 로 빠졌다). 그만큼 몸통 크기를 올려서 되찾는다.
    for (final t in [
      [k.tone0, 0.46],
      [k.tone1, 0.24],
    ]) {
      final f = t[0] * _hit.pitch, amp = t[1];
      if (f <= 0) continue;
      _addTone(
        wave: wTriangle,
        startFreq: f * 1.06,
        rampSegs: [
          [0.10, f * 0.82],
        ],
        a: 0.0008,
        // **유지 구간을 두면 타점이 흐려진다.** 몸통 음 둘(188·332Hz)은 144Hz 차로
        // 맞물려서 6.9ms 마다 한 번씩 겹치는데, 첫 겹침은 어택 램프에 깎이고
        // **두 번째 겹침이 최고점**이 된다 — 그래서 타점이 6.6ms 로 밀렸다.
        // 처음부터 감쇠시키면 첫 순간이 제일 크다(층을 갈라 재 보고 알았다:
        // 잡음 층은 2.0ms 로 멀쩡했고 몸통 층만 6.5ms 였다).
        h: 0.0015,
        r: 0.26 * _hit.rel,
        peak: amp * v * toneMul * _hit.amp,
      );
    }
    active = true;
  }

  void hat(DrumKit kit, int vel, {bool highQuality = true}) {
    reset();
    final k = kit.hat;
    final v = VG[vel] ?? 1.0;
    // 하이햇은 16비트로 제일 많이 반복된다 — **여기가 머신건이 제일 잘 들리는 자리**라
    // 흔들림 폭을 다른 타악기보다 크게 잡았다.
    _vary(pitch: 0.030, amp: 0.08, tone: 0.10, rel: 0.11);
    final vr = vel / 3.0;
    // 세기 3 = **열린 하이햇.** 두 접시가 안 붙어 있으니 훨씬 오래 흔들린다
    // (1.8배로는 '조금 긴 닫힌 하이햇'이지 열린 소리가 아니다).
    final open = vel >= 3;
    final rel = k.rel * (open ? 3.2 : (vel == 2 ? 1.15 : 1.0)) * _hit.rel;
    // 세게 치면 밝다 — 심벌이 더 크게 휘면서 높은 배음이 살아난다
    final hi = k.hi * (0.88 + 0.18 * vr) * _hit.tone;
    // 살짝 스치면 심벌의 높은 모드가 아예 안 깨어난다 — 그래서 어둡다.
    // 세기로 **열리는 로우패스**가 그 차이를 낸다(하이패스 모서리만 움직여서는
    // 잡음이 워낙 넓어서 밝기가 거의 안 변한다).
    final lo = (7000 + 13000 * vr) * _hit.tone;

    // ── ① 스틱이 금속을 때리는 '칙' ── (5단계 53/N)
    // 2~3ms 짜리 앞머리. 이게 없으면 뒤의 잡음만 남아서 **셰이커처럼** 들린다.
    _addNoise(
      [(b) => b.bandpass(3600 * _hit.tone, 1.0)],
      a: 0.0003,
      h: 0.001,
      r: 0.009,
      peak: 0.32 * v * _hit.amp,
    );

    // ── ② 몸통(잡음) ──
    // 여태 이게 사실상 전부였다 — 어쿠스틱 킷에서 잡음 0.40 대 금속 0.039 로
    // **잡음이 열 배**였다. 그래서 하이햇이 아니라 '치익' 하는 소리가 났다
    // (사용자 지적: "하이햇 개선 요망").
    if (k.noise > 0) {
      _addNoise(
        [(b) => b.highpass(hi, 0), (b) => b.lowpass(lo, 0)],
        a: 0.0006,
        h: 0.005,
        r: rel,
        peak: 0.17 * k.noise * v * _hit.amp,
        // 스틱이 닿고 **그다음에** 접시가 운다. 1.5ms 늦춰야 '칙' 이 앞에 선다.
        delaySec: 0.0015,
      );
    }

    // ── ③ 금속 ── **하이햇을 하이햇으로 만드는 것은 이쪽이다.**
    // 서로 안 맞는(비배음) 여섯 개를 겹쳐 만든 쇳소리. 비중을 세 배로 올렸다.
    if (k.metal > 0) {
      _metalCluster(
        k.tune * _hit.pitch,
        highQuality,
        preFreq: hi * 0.72,
        a: 0.0006,
        h: 0.004,
        // 열린 하이햇은 쇳소리가 잡음보다 오래 남는다(그게 '샤—' 하는 꼬리다)
        r: rel * (open ? 1.05 : 0.75),
        peak: 0.78 * k.metal * v * _hit.amp,
      );
    }
    active = true;
  }

  void tom(DrumKit kit, int vel, {double freq = 180}) {
    reset();
    final k = kit.tom;
    final v = VG[vel] ?? 1.0;
    _vary(pitch: 0.022, amp: 0.06, tone: 0.07, rel: 0.07);
    final vr = vel / 3.0;
    final f0 = freq * (k.mul == 0 ? 1 : k.mul) * _hit.pitch;
    // 세게 칠수록 헤드가 더 눌려 **더 높은 데서 떨어진다.** 탐의 '뿅' 하는 느낌이
    // 세기를 타는 이유다(세기 2 에서 예전 값 1.28 과 같다).
    _addTone(
      wave: k.drive > 0 ? satWave(k.drive) : wSine,
      startFreq: f0 * (1.16 + 0.18 * vr),
      rampSegs: [
        [0.05, f0 * 0.86],
        [0.23, f0 * 0.60],
      ],
      a: 0.001,
      h: 0.03,
      r: k.rel * _hit.rel,
      peak: 0.85 * v * _hit.amp,
      postSetup: k.shell > 0 ? (b) => b.peaking(f0 * 2.4, 1.2, k.shell) : null,
    );
    _addNoise(
      [(b) => b.bandpass(f0 * 3 * _hit.tone, 1.2)],
      a: 0.0005,
      h: 0.002,
      r: 0.02,
      peak: 0.16 * v * _hit.amp,
    );
    active = true;
  }

  void crash(DrumKit kit, int vel, {bool highQuality = true}) {
    reset();
    final k = kit.crash;
    final v = VG[vel] ?? 1.0;
    _vary(pitch: 0.025, amp: 0.07, tone: 0.08, rel: 0.10);
    final vr = vel / 3.0;
    // 세게 칠수록 밝고 **길게** 운다 — 심벌에 들어간 에너지가 많을수록 오래 흔들린다
    final hi = k.hi * (0.88 + 0.18 * vr) * _hit.tone;
    final rel = k.rel * (0.55 + 0.68 * vr) * _hit.rel;
    _addNoise(
      [(b) => b.highpass(hi, 0)],
      a: 0.0015,
      h: 0.02,
      r: rel,
      peak: 0.36 * k.noise * v * _hit.amp,
    );
    _metalCluster(
      k.tune * _hit.pitch,
      highQuality,
      preFreq: hi * 0.7,
      a: 0.0015,
      h: 0.03,
      r: rel * 0.85,
      peak: 0.085 * k.metal * v * _hit.amp,
    );
    active = true;
  }

  void ride(DrumKit kit, int vel, {bool highQuality = true}) {
    reset();
    final k = kit.ride;
    final v = VG[vel] ?? 1.0;
    _vary(pitch: 0.020, amp: 0.07, tone: 0.08, rel: 0.09);
    final vr = vel / 3.0;
    // 라이드는 세게 칠수록 **컵(벨) 쪽 소리가 살아난다** — 실제로 세게 치면
    // 가장자리보다 가운데가 더 울려서 '핑' 하는 음정이 도드라진다.
    final hi = k.hi * (0.90 + 0.15 * vr) * _hit.tone;
    _addNoise(
      [(b) => b.highpass(hi, 0)],
      a: 0.001,
      h: 0.02,
      r: k.rel * _hit.rel,
      peak: 0.20 * v * _hit.amp,
    );
    _metalCluster(
      k.tune * _hit.pitch,
      highQuality,
      preFreq: hi * 0.8,
      a: 0.001,
      h: 0.02,
      r: k.rel * 0.7 * _hit.rel,
      peak: 0.055 * v * _hit.amp,
    );
    _addTone(
      wave: wSquare,
      startFreq: 1050 * k.tune * _hit.pitch,
      a: 0.001,
      h: 0.02,
      r: k.rel * 0.55 * _hit.rel,
      peak: k.bell * (0.20 + 0.30 * vr) * v * _hit.amp,
    );
    active = true;
  }

  void rim(DrumKit kit, int vel) {
    reset();
    final k = kit.rim;
    final v = VG[vel] ?? 1.0;
    _vary(pitch: 0.030, amp: 0.08, tone: 0.09, rel: 0.08);
    final f = k.f * _hit.pitch;
    _addTone(
      wave: wTriangle,
      startFreq: f,
      rampSegs: [
        [0.02, f * 0.45],
      ],
      a: 0.0004,
      h: 0.004,
      r: k.rel * _hit.rel,
      peak: 0.55 * k.wood * v * _hit.amp,
    );
    _addNoise(
      [(b) => b.bandpass(f * 1.5 * _hit.tone, 2.4)],
      a: 0.0004,
      h: 0.002,
      r: 0.016,
      peak: 0.9 * k.noise * v * _hit.amp,
    );
    active = true;
  }

  void clap(DrumKit kit, int vel) {
    reset();
    final k = kit.clap;
    final v = VG[vel] ?? 1.0;
    _vary(pitch: 0.02, amp: 0.07, tone: 0.08, rel: 0.08);
    for (var i = 0; i < k.n; i++) {
      // 박수는 여러 손이 **살짝 어긋나** 부딪히는 소리라 간격을 흔든다.
      // 다만 흔들림을 끈 상태(`Human.level == 0`)에서는 **건드리면 안 된다** —
      // 여기만 조건 없이 난수를 쓰고 있어서, 같은 곡을 두 번 내보내면
      // 박수 자리가 달라졌다(Phase 1 결정성 시험에서 잡았다).
      final off = i * k.spread * (_varyOn ? 1 + _rnd2() * 0.12 : 1.0);
      _addNoise(
        [(b) => b.bandpass(k.bp * _hit.tone, k.q)],
        a: 0.0004,
        h: 0.002,
        r: 0.020,
        // **박수를 2배로 올렸다** (2026-08-31). 재 보니 스네어 대비 −13dB 이었다.
        // 박수만 뒷박을 치는 판이 여덟이나 된다(`House Chorus Plain`·`House Break`·
        // `City Break`·`Clap Beat`·`Perc Layer`·`Prog Groove`·`Jazz B`·`Gospel Break`).
        // 거기서는 뒷박이 **거의 안 들렸다**. 스네어 위에 겹치는 판(트랩·팝·디스코)에서도
        // −7dB 이면 여전히 겹이지 주인공이 아니다.
        peak: (0.84 - i * 0.10) * v * _hit.amp,
        delaySec: off,
      );
    }
    _addNoise(
      [(b) => b.bandpass(k.bp * 0.85 * _hit.tone, 0.8)],
      a: 0.001,
      h: 0.006,
      r: k.rel * _hit.rel,
      peak: k.tail * 2.0 * v * _hit.amp,
      delaySec: k.spread * k.n,
    );
    active = true;
  }

  void shaker(DrumKit kit, int vel) {
    reset();
    final k = kit.shake;
    final v = VG[vel] ?? 1.0;
    // 셰이커도 계속 반복되는 악기다 — 알갱이가 매번 다르게 부딪힌다
    _vary(pitch: 0.03, amp: 0.10, tone: 0.12, rel: 0.12);
    _addNoise(
      [
        (b) => b.highpass(k.hi * _hit.tone, 0),
        (b) => b.bandpass(k.bp * _hit.tone, 0.9),
      ],
      a: 0.002,
      h: 0.005,
      r: k.rel * _hit.rel,
      peak: 0.3 * v * _hit.amp,
    );
    active = true;
  }

  void cowbell(DrumKit kit, int vel) {
    reset();
    final k = kit.cow;
    final v = VG[vel] ?? 1.0;
    _vary(pitch: 0.012, amp: 0.06, tone: 0.06, rel: 0.07);
    _addCluster(
      freqs: [k.f0 * _hit.pitch, k.f1 * _hit.pitch],
      waves: [wSquare, wSquare],
      preSetup: (b) => b.bandpass(k.bp * _hit.tone, 1.6),
      a: 0.0006,
      h: 0.02,
      r: k.rel * _hit.rel,
      peak: 0.3 * v * _hit.amp,
    );
    active = true;
  }

  void _metalCluster(
    double tune,
    bool highQuality, {
    required double preFreq,
    required double a,
    required double h,
    required double r,
    required double peak,
  }) {
    if (highQuality) {
      _addCluster(
        freqs: kMetalF.map((f) => f * tune).toList(),
        waves: List.filled(kMetalF.length, wSquare),
        preSetup: (b) => b.highpass(preFreq, 0),
        a: a,
        h: h,
        r: r,
        peak: peak,
      );
    } else {
      _addCluster(
        // **`kMetalFund` 이지 `kMetalF[0]` 이 아니다** — `metalWave()` 가 배음을
        // `kMetalFund` 기준 칸에 눌러 담아 뒀다(dsp.dart 참고). 재생 기본음이
        // 배음을 계산한 기준과 어긋나면 칸이 다시 엉뚱한 자리로 밀린다.
        freqs: [kMetalFund * tune],
        waves: [metalWave()],
        preSetup: (b) => b.highpass(preFreq, 0),
        a: a,
        h: h,
        r: r,
        peak: peak,
      );
    }
  }

  /// 표본으로 이 타격을 켠다 — 표본이 있으면 `true`(합성을 안 탄다), 없으면
  /// (또는 아직 로드 중이면) `false`(호출한 쪽이 합성으로 대신한다).
  ///
  /// 하이햇은 조각 자체가 갈린다 — 세기 3(열림)과 1~2(닫힘)가 다른 녹음이다
  /// (`hat()` 의 `open = vel >= 3` 과 같은 경계, `drum_sampler.dart` 문서).
  /// 림샷·박수·쉐이커·카우벨은 표본이 원래 없다(`_kDrumRRCount` 에 없음) —
  /// `ensureDrumPieceLoaded` 가 즉시 반환하고, 여기서도 바로 `false`.
  bool _startDrumSample(String inst, int vel, double tomFreq) {
    final piece = switch (inst) {
      'hat' => vel >= 3 ? 'hatOpen' : 'hatClosed',
      'kick' || 'snare' || 'crash' || 'ride' || 'tom' => inst,
      _ => null,
    };
    if (piece == null) return false;
    final bank = kDrumSampleBanks[piece];
    if (bank == null) {
      unawaited(ensureDrumPieceLoaded(piece));
      return false;
    }
    reset();
    _vary(pitch: 0.02, amp: 0.06, tone: 0.06, rel: 0.06);
    // 하이햇 열림은 항상 세기 3 벌에서 고른다 — 닫힘은 1·2 그대로.
    final bankVel = inst == 'hat' && vel >= 3 ? 3 : vel;
    final clip = bank.pick(bankVel, _rrRng);
    _sampleMode = true;
    _smPcm = clip.pcm;
    _smPos = 0;
    final rootFreq = kDrumRootFreq[piece];
    final pitchMul = _hit.pitch; // 라운드로빈 위에 얹는 아주 작은 흔들림
    _smRatio = rootFreq == null
        ? (clip.sampleRate / kSampleRate) * pitchMul
        : (tomFreq / rootFreq) * (clip.sampleRate / kSampleRate) * pitchMul;
    _smGain = (VG[vel] ?? 1.0) * _hit.amp;
    active = true;
    return true;
  }

  /// 표본 재생 한 샘플 — `SynthNote._nextSample` 과 같은 선형보간.
  /// 여기서 나온 값은 choke·pan 을 거쳐야 해서 `outL/outR` 에 직접 안 쓰고
  /// [next] 가 마무리한다.
  double _nextDrumSample() {
    final pcm = _smPcm;
    if (pcm == null) {
      active = false;
      return 0;
    }
    final idx = _smPos.floor();
    if (idx + 1 >= pcm.length) {
      active = false;
      return 0;
    }
    final frac = _smPos - idx;
    final s0 = pcm[idx] / 32768.0;
    final s1 = pcm[idx + 1] / 32768.0;
    final s = (s0 + (s1 - s0) * frac) * _smGain;
    _smPos += _smRatio;
    return s;
  }

  /// 이 타격을 트리거한다. [tomFreq] 는 tom 에서만 쓰인다.
  void trigger(
    String rawInst,
    DrumKit kit,
    int vel, {
    double tomFreq = 180,
    bool highQuality = true,
  }) {
    // 데이터 쪽 이름('shaker'·'cowbell')으로 와도 받는다 — [kDrumAlias] 참고.
    final inst = drumName(rawInst);
    this.inst = inst;
    // **표본이 있으면 합성을 아예 안 탄다** — `drum_sampler.dart`. 이 킷이
    // 표본을 안 켰거나(전자음 킷), 이 조각이 표본이 없거나, 아직 로드가
    // 안 끝났으면 그대로 아래 합성 경로로 간다(끊김 없음 — `sampler.dart`
    // 문서와 같은 이유).
    if (kit.sampled && _startDrumSample(inst, vel, tomFreq)) {
      final base = _panOf[inst] ?? 0.0;
      _setPan(base);
      return;
    }
    switch (inst) {
      case 'kick':
        kick(kit, vel);
        break;
      case 'snare':
        snare(kit, vel);
        break;
      case 'hat':
        hat(kit, vel, highQuality: highQuality);
        break;
      case 'tom':
        tom(kit, vel, freq: tomFreq);
        break;
      case 'crash':
        crash(kit, vel, highQuality: highQuality);
        break;
      case 'ride':
        ride(kit, vel, highQuality: highQuality);
        break;
      case 'rim':
        rim(kit, vel);
        break;
      case 'clap':
        clap(kit, vel);
        break;
      case 'shake':
        shaker(kit, vel);
        break;
      case 'cow':
        cowbell(kit, vel);
        break;
    }
    // 좌우 자리를 잡는다 — **각 타악기가 자기 자리에서** 난다.
    // 하이햇처럼 되풀이가 많은 것은 자리도 조금씩 흔든다(`_hit.tone` 재활용).
    // 매번 정확히 같은 점에서 나면 그게 또 하나의 '머신건'이다.
    final base = _panOf[inst] ?? 0.0;
    final jitter = _varyOn && (inst == 'hat' || inst == 'shake')
        ? (_hit.tone - 1) * 0.5
        : 0.0;
    _setPan(base + jitter);
  }

  bool _anyOn() {
    for (var i = 0; i < _nt; i++) {
      if (_tones[i].on) return true;
    }
    for (var i = 0; i < _nn; i++) {
      if (_noises[i].on) return true;
    }
    return _cluster.on;
  }

  /// 다음 샘플 한 개를 outL/outR 에 넣는다 (드럼은 아직 팬이 없다 — 3단계 믹서에서 다룬다).
  void next() {
    outL = 0;
    outR = 0;
    if (!active) return;

    if (_sampleMode) {
      var s = _nextDrumSample();
      if (_chokeLeft > 0) {
        s *= _chokeLeft / _chokeN;
        if (--_chokeLeft <= 0) {
          active = false;
          return;
        }
      }
      outL = s * _panL;
      outR = s * _panR;
      _age++;
      return;
    }

    var sum = 0.0;

    for (var i = 0; i < _nt; i++) {
      final t = _tones[i];
      if (!t.on) continue;
      final inc = t.ramp ? (t.freqEnv.next() / kSampleRate) : t.inc;
      var ph = t.phase + inc;
      if (ph >= 1.0) ph -= ph.floorToDouble();
      t.phase = ph;
      if (t.amp.done) {
        t.on = false;
        continue;
      }
      var s = readTable(t.tab!, ph) * t.amp.next();
      if (t.hasPost) s = t.post.process(s);
      sum += s;
    }

    for (var i = 0; i < _nn; i++) {
      final nl = _noises[i];
      if (!nl.on) continue;
      if (nl.delay > 0) {
        nl.delay--;
        continue;
      }
      if (nl.bpIdx >= 0) {
        final f = nl.bpFreq.next();
        if ((_age & (_kModStride - 1)) == 0) {
          nl.filt[nl.bpIdx].bandpass(f, nl.bpQ);
        }
      }
      if (nl.amp.done) {
        nl.on = false;
        continue;
      }
      var s = nl.rng.next();
      for (var k = 0; k < nl.nFilt; k++) {
        s = nl.filt[k].process(s);
      }
      s *= nl.amp.next();
      sum += s;
    }

    final c = _cluster;
    if (c.on) {
      if (c.amp.done) {
        c.on = false;
      } else {
        var s = 0.0;
        for (var i = 0; i < c.n; i++) {
          var ph = c.phase[i] + c.inc[i];
          if (ph >= 1.0) ph -= ph.floorToDouble();
          c.phase[i] = ph;
          s += readTable(c.tab[i]!, ph);
        }
        if (c.hasPre) s = c.pre.process(s);
        s *= c.amp.next();
        sum += s;
      }
    }

    // 초킹 — 하이햇을 닫으면 열려 있던 소리가 훑여 내려간다
    if (_chokeLeft > 0) {
      sum *= _chokeLeft / _chokeN;
      if (--_chokeLeft <= 0) {
        outL = 0;
        outR = 0;
        active = false;
        return;
      }
    }

    outL = sum * _panL;
    outR = sum * _panR;

    _age++;
    if (--_life <= 0 || !_anyOn()) active = false;
  }
}
