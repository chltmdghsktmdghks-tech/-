// DSP 기반 — 웹에서 Web Audio 가 공짜로 해주던 것들을 직접 만든다.
//
// 웹 버전은 브라우저에 다음을 맡겼다:
//   OscillatorNode.setPeriodicWave  → 배음 구조를 가진 파형 (에일리어싱 없이)
//   BiquadFilterNode                → 로우패스/피킹/밴드패스
//   GainNode + AudioParam 램프       → 엔벨로프
// 네이티브로 옮기면 이 셋을 우리가 만들어야 한다. 여기가 그 셋이다.

import 'dart:math' as math;
import 'dart:typed_data';

/// 48000 이어야 한다. 44100 을 쓰면 안드로이드가 매 샘플 리샘플링을 하고,
/// 그 과정에서 **저지연 경로(fast mixer)를 아예 못 탄다.**
/// A17 실기 확인: `dumpsys media.audio_flinger` → 모든 출력 스레드가 48000Hz,
/// 그 중 하나는 HAL 프레임 256 (= 저지연 경로).
const int kSampleRate = 48000;

// ───────────────────────── 사인 테이블 ─────────────────────────
// 파형을 만들 때 sin() 을 수백만 번 부르면 앱 시작이 느려진다.
// 길이가 한 주기와 정확히 같은 표를 만들어 두면, n배음은 인덱스를 n배로 건너뛰기만 하면 된다.
const int kTable = 2048;
const int _mask = kTable - 1;

final Float32List _sin = () {
  final t = Float32List(kTable);
  for (var i = 0; i < kTable; i++) {
    t[i] = math.sin(2 * math.pi * i / kTable);
  }
  return t;
}();

// ───────────────────────── 웨이브테이블 ─────────────────────────
// 톱니파를 단순히 `2*phase-1` 로 만들면 높은 음에서 **에일리어싱**이 생긴다.
// 표본화 주파수의 절반(22050Hz)을 넘는 배음이 엉뚱한 낮은 음으로 접혀 들어와,
// 화음이 안 맞는 쇳소리가 섞인다. 브라우저는 이걸 알아서 막아 준다.
//
// 막는 방법: 음높이 대역(옥타브)마다 배음 개수를 다르게 한 표를 여러 장 만들어 두고
// 그때그때 골라 쓴다. 낮은 음은 배음 많이(밝게), 높은 음은 적게(접히지 않게).
const int _kOctaves = 11; // 20Hz 부터 한 옥타브씩

class WaveSet {
  final List<Float32List> tables; // 옥타브별 한 장씩
  WaveSet._(this.tables);

  /// 배음 세기 목록으로 만든다. amps[0] = 1배음.
  /// [maxHarm] 은 기본 파형(톱니 등)처럼 배음이 무한한 경우의 상한.
  factory WaveSet.fromHarmonics(double Function(int n) amp, int maxHarm) {
    final out = <Float32List>[];
    final acc = Float64List(kTable);

    // 배음을 1번부터 차례로 더해 나가면서, 각 옥타브의 한계에 닿을 때마다 그 시점을 찍어 둔다.
    // (높은 옥타브일수록 배음이 적으므로, 한 번의 누적으로 전부 만들 수 있다)
    final limits = List<int>.generate(_kOctaves, (k) {
      final fMax = 20.0 * math.pow(2, k + 1);
      final h = (kSampleRate / 2 / fMax).floor();
      return h.clamp(1, maxHarm);
    });
    // 배음이 많은 쪽(낮은 옥타브)부터 채워야 하므로 역순으로 스냅샷을 뜬다
    final order = List<int>.generate(_kOctaves, (i) => i)
      ..sort((a, b) => limits[a].compareTo(limits[b]));

    var n = 1;
    final snaps = <int, Float32List>{};
    for (final oct in order) {
      final lim = limits[oct];
      for (; n <= lim; n++) {
        final a = amp(n);
        if (a == 0) continue;
        for (var i = 0; i < kTable; i++) {
          acc[i] += a * _sin[(n * i) & _mask];
        }
      }
      snaps[oct] = _normalized(acc);
    }
    for (var k = 0; k < _kOctaves; k++) {
      out.add(snaps[k]!);
    }
    return WaveSet._(out);
  }

  static Float32List _normalized(Float64List acc) {
    var peak = 0.0;
    for (final v in acc) {
      final a = v.abs();
      if (a > peak) peak = a;
    }
    final g = peak > 1e-9 ? 1.0 / peak : 1.0;
    final t = Float32List(kTable);
    for (var i = 0; i < kTable; i++) {
      t[i] = acc[i] * g;
    }
    return t;
  }

  /// 이 음높이에 맞는 표를 고른다
  Float32List tableFor(double freq) {
    if (freq <= 20) return tables[0];
    final k = (math.log(freq / 20.0) / math.ln2).floor();
    return tables[k.clamp(0, _kOctaves - 1)];
  }
}

// 기본 파형 4종 — 실제 톱니/사각/삼각의 배음 공식 그대로
final WaveSet wSine = WaveSet.fromHarmonics((n) => n == 1 ? 1.0 : 0.0, 1);
final WaveSet wSaw = WaveSet.fromHarmonics((n) => 1.0 / n, 256);
final WaveSet wSquare = WaveSet.fromHarmonics(
  (n) => n.isOdd ? 1.0 / n : 0.0,
  256,
);
final WaveSet wTriangle = WaveSet.fromHarmonics(
  (n) => n.isOdd ? (n % 4 == 1 ? 1.0 : -1.0) / (n * n) : 0.0,
  256,
);

WaveSet waveByName(String t) {
  switch (t) {
    case 'sawtooth':
      return wSaw;
    case 'square':
      return wSquare;
    case 'triangle':
      return wTriangle;
    default:
      return wSine;
  }
}

/// 표에서 한 점을 읽는다 (선형 보간)
@pragma('vm:prefer-inline')
double readTable(Float32List t, double phase) {
  final x = phase * kTable;
  final i = x.toInt() & _mask;
  final f = x - x.floorToDouble();
  final a = t[i];
  return a + (t[(i + 1) & _mask] - a) * f;
}

// ───────────────────────── 바이쿼드 필터 ─────────────────────────
// RBJ 쿡북 계수 — Web Audio 의 BiquadFilterNode 와 같은 식이다.
//
// 함정 하나: Web Audio 의 lowpass/highpass 는 Q 를 **데시벨로** 받는다.
// 웹 코드의 `lp.Q.value=0.7` 은 Q=0.7 이 아니라 10^(0.7/20)=1.08 이다.
// 이 변환을 빼먹으면 필터가 웹보다 훨씬 날카로워진다.
class Biquad {
  double _b0 = 1, _b1 = 0, _b2 = 0, _a1 = 0, _a2 = 0;
  double _x1 = 0, _x2 = 0, _y1 = 0, _y2 = 0;

  void reset() {
    _x1 = _x2 = _y1 = _y2 = 0;
  }

  void lowpass(double freq, double qDb) {
    final q = math.pow(10, qDb / 20).toDouble();
    _set(freq, q, 0, _Kind.lowpass);
  }

  void highpass(double freq, double qDb) {
    final q = math.pow(10, qDb / 20).toDouble();
    _set(freq, q, 0, _Kind.highpass);
  }

  void bandpass(double freq, double q) => _set(freq, q, 0, _Kind.bandpass);

  void peaking(double freq, double q, double gainDb) =>
      _set(freq, q, gainDb, _Kind.peaking);

  /// 마스터 3밴드 EQ 의 저역·고역 밴드용 — Web Audio 의 lowshelf/highshelf 와 같은 식(RBJ 쿡북).
  /// [shelfS] 는 셸프 기울기(Web Audio 기본값 1). gainDb=0 이면 계수가 항등필터로 접힌다(투명).
  void lowShelf(double freq, double gainDb, {double shelfS = 1.0}) =>
      _set(freq, shelfS, gainDb, _Kind.lowShelf);

  void highShelf(double freq, double gainDb, {double shelfS = 1.0}) =>
      _set(freq, shelfS, gainDb, _Kind.highShelf);

  void _set(double freq, double q, double gainDb, _Kind kind) {
    final f = freq.clamp(10.0, kSampleRate * 0.49);
    final qq = q < 1e-4 ? 1e-4 : q;
    final w0 = 2 * math.pi * f / kSampleRate;
    final cw = math.cos(w0), sw = math.sin(w0);
    final alpha = sw / (2 * qq);
    double b0, b1, b2, a0, a1, a2;
    switch (kind) {
      case _Kind.lowpass:
        b0 = (1 - cw) / 2;
        b1 = 1 - cw;
        b2 = b0;
        a0 = 1 + alpha;
        a1 = -2 * cw;
        a2 = 1 - alpha;
        break;
      case _Kind.highpass:
        b0 = (1 + cw) / 2;
        b1 = -(1 + cw);
        b2 = b0;
        a0 = 1 + alpha;
        a1 = -2 * cw;
        a2 = 1 - alpha;
        break;
      case _Kind.bandpass: // 정점 이득 1
        b0 = alpha;
        b1 = 0;
        b2 = -alpha;
        a0 = 1 + alpha;
        a1 = -2 * cw;
        a2 = 1 - alpha;
        break;
      case _Kind.peaking:
        final a = math.pow(10, gainDb / 40).toDouble();
        b0 = 1 + alpha * a;
        b1 = -2 * cw;
        b2 = 1 - alpha * a;
        a0 = 1 + alpha / a;
        a1 = -2 * cw;
        a2 = 1 - alpha / a;
        break;
      case _Kind.lowShelf:
        {
          final a = math.pow(10, gainDb / 40).toDouble();
          final sq = math.sqrt(a);
          final shelfAlpha = sw / 2 * math.sqrt((a + 1 / a) * (1 / qq - 1) + 2);
          b0 = a * ((a + 1) - (a - 1) * cw + 2 * sq * shelfAlpha);
          b1 = 2 * a * ((a - 1) - (a + 1) * cw);
          b2 = a * ((a + 1) - (a - 1) * cw - 2 * sq * shelfAlpha);
          a0 = (a + 1) + (a - 1) * cw + 2 * sq * shelfAlpha;
          a1 = -2 * ((a - 1) + (a + 1) * cw);
          a2 = (a + 1) + (a - 1) * cw - 2 * sq * shelfAlpha;
          break;
        }
      case _Kind.highShelf:
        {
          final a = math.pow(10, gainDb / 40).toDouble();
          final sq = math.sqrt(a);
          final shelfAlpha = sw / 2 * math.sqrt((a + 1 / a) * (1 / qq - 1) + 2);
          b0 = a * ((a + 1) + (a - 1) * cw + 2 * sq * shelfAlpha);
          b1 = -2 * a * ((a - 1) + (a + 1) * cw);
          b2 = a * ((a + 1) + (a - 1) * cw - 2 * sq * shelfAlpha);
          a0 = (a + 1) - (a - 1) * cw + 2 * sq * shelfAlpha;
          a1 = 2 * ((a - 1) - (a + 1) * cw);
          a2 = (a + 1) - (a - 1) * cw - 2 * sq * shelfAlpha;
          break;
        }
    }
    _b0 = b0 / a0;
    _b1 = b1 / a0;
    _b2 = b2 / a0;
    _a1 = a1 / a0;
    _a2 = a2 / a0;
  }

  @pragma('vm:prefer-inline')
  double process(double x) {
    final y = _b0 * x + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }
}

enum _Kind { lowpass, highpass, bandpass, peaking, lowShelf, highShelf }

// ───────────────────────── 엔벨로프 ─────────────────────────
// 웹의 adsr() 과 **같은 모양**이어야 한다. 지수 램프는 Web Audio 와 같은 식:
//   v(t) = v0 * (v1/v0)^(경과/구간길이)  → 샘플당 고정 배율로 곱해 나가면 된다.
const double kSilent = 0.0001;

class Env {
  final List<int> _n = [];
  final List<double> _to = [];
  final List<bool> _exp = [];
  int _seg = -1;
  int _left = 0;
  double _step = 0; // 지수면 배율, 선형이면 증분
  double value = kSilent;
  bool done = true;

  void clear() {
    _n.clear();
    _to.clear();
    _exp.clear();
  }

  void add(double seconds, double to, {bool exp = false}) {
    final s = (seconds * kSampleRate).round();
    _n.add(s < 1 ? 1 : s);
    _to.add(to);
    _exp.add(exp);
  }

  /// [from] 을 주면 무음이 아니라 그 값에서 시작한다 — 드럼 피치 스윕처럼
  /// '음량'이 아니라 '값'을 실어 나르는 용도로도 이 엔벨로프를 재사용하기 위함.
  void start({double from = kSilent}) {
    value = from;
    _seg = -1;
    done = false;
    _next();
  }

  void _next() {
    _seg++;
    if (_seg >= _n.length) {
      done = true;
      value = 0;
      return;
    }
    _left = _n[_seg];
    final to = _to[_seg];
    if (_exp[_seg]) {
      final from = value < kSilent ? kSilent : value;
      _step = math.pow(to / from, 1.0 / _left).toDouble();
      value = from;
    } else {
      _step = (to - value) / _left;
    }
  }

  @pragma('vm:prefer-inline')
  double next() {
    if (done) return 0;
    final v = value;
    if (_exp[_seg]) {
      value *= _step;
    } else {
      value += _step;
    }
    if (--_left <= 0) _next();
    return v;
  }

  /// **지금부터 릴리스로 건너뛴다** — 꾹 누르고 있던 소리를 손 뗄 때 쓴다.
  ///
  /// 마지막 마디는 늘 「무음까지 내려가는 구간」이다([buildAdsr]·[buildRing] 둘 다
  /// 그렇게 만든다). 그래서 거기로 옮기면 **지금 값에서** 자연스럽게 사그라든다
  /// (`_next` 가 현재 `value` 에서 기울기를 다시 잡는다 — 뚝 끊기지 않는다).
  ///
  /// 이미 릴리스에 들어섰거나 끝났으면 아무 일도 안 한다 — 두 번 떼도 안전하다.
  void release() {
    if (done || _n.length < 2) return;
    if (_seg >= _n.length - 1) return;
    _seg = _n.length - 2; // `_next` 가 하나 올리므로 한 칸 앞에 둔다
    _next();
  }

  /// 릴리스까지 합쳐 남은 샘플 — 잡아 둔 소리를 놓을 때 수명을 다시 잡는 데 쓴다.
  int get releaseSamples => _n.isEmpty ? 0 : _n.last;

  /// 이 엔벨로프가 끝날 때까지 몇 샘플인가
  int get totalSamples {
    var s = 0;
    for (final n in _n) {
      s += n;
    }
    return s;
  }
}

/// 치는·뜯는 악기용 엔벨로프.
///
/// 웹 버전은 어택 뒤 곧바로 **0 까지 지수로 떨어뜨렸다**(`exponentialRampToValueAtTime(0.0001, t+rel)`).
/// 지수 곡선은 앞쪽에서 대부분을 잃는다 — 3초짜리 음이라도 1초 지나면 -25dB,
/// 1.5초면 -37dB 라 사실상 안 들린다. "온음표를 그렸는데 금방 끊긴다"의 진짜 원인이 이것이다.
/// RING 비율을 1.00 으로 올려도 이 곡선 모양 때문에 체감이 거의 안 바뀌었다.
///
/// 그래서 토막을 나눈다. 실제 현은 **두 단계로** 사그라든다 —
/// 때린 직후 빠르게 한 번 떨어지고(현의 초기 에너지), 그 뒤로는 아주 천천히 남는다.
/// 한 개의 지수 곡선으로는 이 둘 중 하나밖에 흉내내지 못한다.
/// 앞을 느리게 잡으면 '띵—' 하고 뭉개지고, 빠르게 잡으면 금방 사라진다.
///   knock — 음표 앞 12% 동안 peak → peak*0.45  (때린 느낌)
///   body  — 나머지 동안 peak*0.45 → peak*tail  (긴 꼬리)
///   rel   — 그 뒤 짧게 정리 (실제 피아노의 댐퍼)
void buildRing(
  Env e,
  double a,
  double body,
  double rel,
  double peak,
  double tail,
) {
  e.clear();
  e.add(a, peak);
  final rest = math.max(0.02, body - a);
  final knock = math.min(0.18, rest * 0.12);
  e.add(knock, math.max(0.0002, peak * 0.45), exp: true);
  e.add(rest - knock, math.max(0.0002, peak * tail), exp: true);
  e.add(rel, kSilent, exp: true);
  e.start();
}

/// 웹의 adsr(c,t,a,h,r,p,s) 와 같은 모양을 만든다.
///
/// [decOverride] 를 주면 "피크 → 서스테인 레벨" 로 내려가는 시간을 그 값으로
/// 쓴다(사용자 ADSR 손잡이, 2026-09-15) — 안 주면 여태처럼 `h`(길이)에서
/// 자동으로 잡는다.
void buildAdsr(
  Env e,
  double a,
  double h,
  double r,
  double peak,
  double? sus, {
  double? decOverride,
}) {
  e.clear();
  e.add(a, peak); // 어택: 선형
  if (sus != null && sus < 0.999 && h > 0.03) {
    final dec = (decOverride ?? math.min(h * 0.55, 0.16)).clamp(0.005, h);
    final s = math.max(0.0002, peak * sus);
    e.add(dec, s, exp: true);
    e.add(math.max(0.001, h - dec), s); // 서스테인 유지
  } else {
    e.add(h, peak);
  }
  e.add(r, kSilent, exp: true);
  e.start();
}

// ───────────────────────── 잡음 ─────────────────────────
class Noise {
  int _s = 0x2545F491;

  /// 씨앗을 갈아 끼운다 — **타격마다 다른 잡음**을 내려고.
  /// 하이햇·셰이커는 거의 전부가 잡음이라, 같은 잡음이면 파형이 통째로 같다.
  void seed(int v) => _s = (v & 0x7FFFFFFF) | 1;
  @pragma('vm:prefer-inline')
  double next() {
    // xorshift — Random() 보다 훨씬 싸고 오디오용으로 충분하다
    _s ^= (_s << 13) & 0x7FFFFFFF;
    _s ^= _s >> 17;
    _s ^= (_s << 5) & 0x7FFFFFFF;
    return (_s / 0x3FFFFFFF) - 1.0;
  }
}

// ───────────────────────── 드럼 전용 파형 ─────────────────────────
// 새추레이션(드라이브) — 사인을 tanh 로 눌러 만든 **홀수 배음** 파형. 킥·탐의 '펀치'를 낸다.
// 웹은 타격마다 WaveShaper 를 새로 만들었지만, 사인파를 tanh 에 통과시킨 결과는
// 고정된 배음 구조이므로 한 번 구워서 WaveSet 으로 캐싱해 둔다(타격당 비용 0).
double _tanh(double x) {
  if (x > 20) return 1.0;
  if (x < -20) return -1.0;
  final e2x = math.exp(2 * x);
  return (e2x - 1) / (e2x + 1);
}

final Map<int, WaveSet> _satWaves = {};
WaveSet satWave(double amt) {
  final k = (amt * 20).round();
  return _satWaves.putIfAbsent(k, () {
    const h = 20, n = 1024;
    final drive = 1 + k * 1.6;
    final dmax = _tanh(drive);
    final amps = Float64List(h);
    for (var harm = 1; harm <= h; harm += 2) {
      var s = 0.0;
      for (var i = 0; i < n; i++) {
        final th = i * 2 * math.pi / n;
        s += (_tanh(math.sin(th) * drive) / dmax) * math.sin(harm * th);
      }
      amps[harm - 1] = 2 * s / n;
    }
    return WaveSet.fromHarmonics((nn) => nn <= h ? amps[nn - 1] : 0.0, h);
  });
}

/// 금속 클러스터(하이햇·크래시·라이드) — 비조화(정수배가 아닌) 사각파 6개를 겹치면
/// 실제 심벌처럼 들린다. 16분 하이햇이면 초당 오실레이터가 6배로 늘어 보급형 폰에서
/// 오디오가 밀리므로, 6개를 한 파형에 미리 구워 **타격당 오실레이터 1개**로 만든다.
const List<double> kMetalF = [821, 1153, 1478, 1865, 2247, 2996];

/// [metalWave] 를 재생할 때 쓸 **기본음**(재생 쪽 `freqs: [kMetalFund * tune]`).
///
/// `kMetalF[0]`(821Hz) 을 그대로 기본음으로 쓰면 배음 칸이 성겨서 6개 중 둘씩
/// 겹쳐 버린다(아래 [metalWave] 설명). **5로 나눈다** — 나눌수록 칸이 촘촘해서
/// 정확해지지만, `metalWave` 가 3배음까지 같이 굽는 탓에 `최대칸 × 3` 이 64를
/// 넘으면 그 3배음들이 64번 칸에 몰려 도로 뭉갠다. 5가 그 한계 안에서 제일 정확하다:
/// ```
///   나누는 값   서로 다른 칸   최대 오차     3배음
///        1        4/6         588센트      OK   ← 예전
///        3        6/6         133센트      OK
///        5        6/6          55센트      OK   ← 지금
///        7        6/6          54센트      넘침
/// ```
/// **`821` 은 `kMetalF[0]` 과 같은 값이다** — 상수 목록은 인덱스로 `const` 계산이
/// 안 돼서 그대로 옮겨 적었다. `kMetalF[0]` 을 바꾸면 이 값도 같이 고칠 것
/// (`instrument_quality_test` 의 「금속 6칸」 확인이 어긋나면 잡힌다).
const double kMetalFund = 821 / 5;
WaveSet? _metalWaveCache;

/// 6개 비조화 주파수를 **배음 칸**에 눌러 담는다 — 진짜 오실레이터 6개 대신
/// 하나로 구우려면 전부 `kMetalFund` 의 정수배 칸에 반올림해 넣을 수밖에 없다.
///
/// **칸이 너무 성기면 서로 겹친다.** 기본음을 `kMetalF[0]`(821Hz) 그대로 쓰면
/// 1153Hz 는 821Hz 와 같은 1번 칸에, 1865Hz 는 1478Hz 와 같은 2번 칸에 얹혀서
/// 6개가 4개로 뭉개졌다 — 게다가 살아남은 두 칸(821·1642Hz)이 정확히 옥타브(2:1)
/// 라 「정수배가 아니어야 심벌답다」는 이 함수의 목적과 정반대로 갔다.
/// [kMetalFund] 로 칸을 다섯 배 촘촘히 하면 여섯이 각자 칸을 얻는다.
WaveSet metalWave() {
  final cached = _metalWaveCache;
  if (cached != null) return cached;
  const h = 64;
  final amps = Float64List(h);
  for (final f in kMetalF) {
    final hh = (f / kMetalFund).round().clamp(1, h);
    amps[hh - 1] += 1 / kMetalF.length;
    final h3 = (hh * 3).clamp(1, h);
    amps[h3 - 1] += 0.33 / kMetalF.length;
  }
  final w = WaveSet.fromHarmonics((n) => n <= h ? amps[n - 1] : 0.0, h);
  _metalWaveCache = w;
  return w;
}
