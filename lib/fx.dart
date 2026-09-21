// 인서트 플러그인 (5단계 45/N) — 트랙·마스터에 **꽂아서 소리를 바꾸는 것들.**
//
// ── 왜 이 구조인가 ──
// 요청은 앰프 3종 · 드라이브 · 컴프 3종 · 리버브 3종 · 딜레이 3종 · 그래픽 EQ ·
// 리미터, 열넷이다. 하나씩 화면을 손으로 그리면 열네 개의 화면을 따로 관리하게 된다.
// 그래서 **플러그인이 자기 손잡이를 스스로 설명하게** 했다([FxDef.params]).
// 화면은 그 설명을 읽어 손잡이를 만든다 — 새 플러그인을 더해도 UI 코드는 안 는다.
//
// ── 소리는 샘플 하나씩 ──
// 엔진이 `step(l, r)` 을 부르고 [outL]/[outR] 을 읽어 간다. 배열을 만들지 않는다
// (초당 48000번 × 트랙 수 × 인서트 수 — 할당이 생기면 그 자리에서 끊긴다).

import 'dart:math' as math;
import 'dart:typed_data';

import 'dsp.dart';
import 'mixer.dart' show MasterReverb;

/// 손잡이 하나의 설명. 화면은 이것만 보고 손잡이를 만든다.
class FxParam {
  final String key, label;

  /// 화면에 붙일 단위(%, dB, ms…). 없으면 빈 문자열.
  final String unit;
  final double min, max, def;

  /// 값이 골라 쓰는 것이면(모드 등) 이름들. 이때 [min]/[max] 는 0..길이-1.
  final List<String>? choices;

  const FxParam(
    this.key,
    this.label, {
    required this.min,
    required this.max,
    required this.def,
    this.unit = '',
    this.choices,
  });

  /// 화면에 보일 값 글자.
  String show(double v) {
    final c = choices;
    if (c != null) return c[v.round().clamp(0, c.length - 1)];
    if (unit == '%') return '${(v * 100).round()}%';
    if (unit == 'dB') return '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}dB';
    if (unit == 'ms') return '${v.round()}ms';
    if (unit == 'Hz') {
      return v >= 1000 ? '${(v / 1000).toStringAsFixed(1)}k' : '${v.round()}';
    }
    if (unit == ':1') return '${v.toStringAsFixed(1)}:1';
    return v.toStringAsFixed(2);
  }
}

/// 인서트 하나. 소리를 통과시키며 바꾼다.
abstract class Fx {
  Fx(this.type) {
    for (final p in def.params) {
      _v[p.key] = p.def;
    }
    reset();
  }

  final String type;
  bool on = true;

  final Map<String, double> _v = {};

  FxDef get def => kFxCatalog[type]!;

  double get(String key) => _v[key] ?? 0;
  void set(String key, double v) {
    _v[key] = v;
    onParam();
  }

  Map<String, double> get params => Map.unmodifiable(_v);

  /// 값이 바뀌면 계수를 다시 잡을 기회.
  void onParam() {}

  /// 꼬리(딜레이 버퍼 등)를 비운다.
  void reset() {}

  double outL = 0, outR = 0;

  /// 스테레오 한 샘플.
  void step(double l, double r);
}

/// 플러그인 종류 하나 — 이름·묶음·손잡이 설명·만드는 법.
class FxDef {
  final String type, name, group;
  final List<FxParam> params;
  final Fx Function() make;
  const FxDef(this.type, this.name, this.group, this.params, this.make);
}

// ══════════════════ 앰프 ══════════════════

/// 기타·베이스 앰프. 성향 셋 — **클린(펜더) · 크런치(복스) · 하이게인(마샬).**
///
/// 셋을 가르는 건 게인 양이 아니라 **어디가 도드라지고 어떻게 뭉개지는가** 다:
///  · 클린(펜더)  — 게인이 낮고 중역이 살짝 파여 있다(scooped). 고역이 밝다.
///  · 크런치(복스) — 중역(2kHz 언저리)이 솟는다. 그래서 코드가 앞으로 나온다.
///  · 하이게인(마샬) — 프리앰프를 두 번 통과시킨다. 저역을 먼저 깎아야
///    뭉개지지 않는다(실제 앰프도 게인 단 앞에서 베이스를 깎는다).
///
/// **캐비닛(스피커) 흉내가 없으면 전부 지직거리는 소리**로만 들린다 —
/// 진짜 앰프 소리의 절반은 스피커가 고역을 잘라 주는 데서 온다. 그래서 마지막에
/// 로우패스와 존재감 봉우리를 둔다.
class AmpFx extends Fx {
  AmpFx() : super('amp');

  final Biquad _preHpL = Biquad(), _preHpR = Biquad();
  final Biquad _voiceL = Biquad(), _voiceR = Biquad(); // 성향(고정 중역 성격)
  final Biquad _bassL = Biquad(), _bassR = Biquad();
  final Biquad _midL = Biquad(), _midR = Biquad();
  final Biquad _trebL = Biquad(), _trebR = Biquad();
  final Biquad _cabL = Biquad(), _cabR = Biquad();
  final Biquad _presL = Biquad(), _presR = Biquad();
  bool _dirty = true;

  @override
  void onParam() => _dirty = true;

  @override
  void reset() => _dirty = true;

  void _update() {
    final mode = get('mode').round().clamp(0, 2);
    // 게인 단 **앞**의 하이패스 — 하이게인일수록 저역을 더 깎는다.
    // 안 깎으면 저역이 먼저 뭉개져서 소리가 텁텁해진다(실제 앰프도 여기서 깎는다).
    _preHpL.highpass([90.0, 110.0, 150.0][mode], 0.7);
    _preHpR.highpass([90.0, 110.0, 150.0][mode], 0.7);
    // 성향 — 이건 **사용자가 못 만진다.** 앰프의 정체성이다.
    //   펜더: 중역이 파인다 / 복스: 2kHz 가 솟는다 / 마샬: 800Hz 가 살짝 솟는다
    _voiceL.peaking([500.0, 2000.0, 800.0][mode], 0.9, [-4.0, 6.0, 2.5][mode]);
    _voiceR.peaking([500.0, 2000.0, 800.0][mode], 0.9, [-4.0, 6.0, 2.5][mode]);

    // 톤 스택 — 실제 앰프 패널대로 셋을 따로 둔다.
    // 앰프마다 중심 주파수가 다르다(펜더는 미들이 더 낮다).
    _bassL.lowShelf(120, get('bass'));
    _bassR.lowShelf(120, get('bass'));
    final midHz = [400.0, 700.0, 650.0][mode];
    _midL.peaking(midHz, 0.7, get('mid'));
    _midR.peaking(midHz, 0.7, get('mid'));
    _trebL.highShelf(3000, get('treble'));
    _trebR.highShelf(3000, get('treble'));

    // 캐비닛(스피커) — **끄는 스위치가 없다.** 신호는 반드시 여길 지난다.
    // 진짜 앰프 소리의 절반은 스피커가 고역을 잘라 주는 데서 온다.
    // 안 넣으면 어떤 설정에서도 지직거리는 소리로만 들린다.
    final cab = [5200.0, 4600.0, 4000.0][mode]; // 마샬 캡이 제일 어둡다
    _cabL.lowpass(cab, 0.8);
    _cabR.lowpass(cab, 0.8);
    // 프레즌스 — 캐비닛 뒤에서 고역을 되살리는 양(실제 앰프의 그 손잡이)
    _presL.peaking(3200, 1.1, get('presence'));
    _presR.peaking(3200, 1.1, get('presence'));
    _dirty = false;
  }

  /// 비대칭 소프트 클리핑 — 진공관은 위아래를 **다르게** 뭉갠다.
  /// 대칭으로 자르면 홀수 배음만 나와서 트랜지스터처럼 딱딱해진다.
  @pragma('vm:prefer-inline')
  double _tube(double x, double bias) {
    final v = x + bias;
    return v >= 0
        ? 1 -
              math.exp(-v) // 위쪽은 부드럽게 눕는다
        : -1 + math.exp(v * 0.8); // 아래쪽은 조금 더 빨리 눕는다
  }

  @override
  void step(double l, double r) {
    if (_dirty) _update();

    final mode = get('mode').round().clamp(0, 2);
    final drive = 1 + get('gain') * [7.0, 22.0, 60.0][mode];
    final lvl = get('level');

    var a = _preHpL.process(l) * drive;
    var b = _preHpR.process(r) * drive;

    a = _tube(a, 0.08);
    b = _tube(b, 0.08);
    if (mode == 2) {
      // 하이게인 — 프리앰프 두 단. 한 번 더 통과시키면 배음이 촘촘해진다.
      a = _tube(a * 1.8, -0.05);
      b = _tube(b * 1.8, -0.05);
    }

    a = _voiceL.process(a);
    b = _voiceR.process(b);
    a = _trebL.process(_midL.process(_bassL.process(a)));
    b = _trebR.process(_midR.process(_bassR.process(b)));
    // 캐비닛 → 프레즌스 (이 순서라야 프레즌스가 들린다)
    a = _presL.process(_cabL.process(a));
    b = _presR.process(_cabR.process(b));

    // 게인을 올릴수록 커지지 않게 되돌린다 — 안 그러면 톤이 아니라 볼륨 비교가 된다
    final comp = 1 / (1 + get('gain') * 1.6);
    outL = a * lvl * comp;
    outR = b * lvl * comp;
  }
}

// ══════════════════ 딜레이 ══════════════════

/// 딜레이 — 되돌아오는 소리. 스테레오로 따로 물린다.
class DelayFx extends Fx {
  DelayFx() : super('delay');

  static const _maxSec = 2.0;
  final Float64List _bufL = Float64List((kSampleRate * _maxSec).round());
  final Float64List _bufR = Float64List((kSampleRate * _maxSec).round());
  int _w = 0;
  final Biquad _dampL = Biquad(), _dampR = Biquad();
  double _lastDamp = -1;

  @override
  void reset() {
    _bufL.fillRange(0, _bufL.length, 0);
    _bufR.fillRange(0, _bufR.length, 0);
    _w = 0;
    _lastDamp = -1;
  }

  @override
  void step(double l, double r) {
    // 테이프는 **기본으로 더 어둡다** — 손잡이와 별개로 방식이 성격을 정한다
    final modeNow = get('mode').round().clamp(0, 2);
    final damp = (get('damp') + (modeNow == 1 ? 0.3 : 0)).clamp(0.0, 1.0);
    if (damp != _lastDamp) {
      // 되돌아올수록 어두워진다 — 실제 테이프·아날로그 딜레이가 그렇다.
      // 이게 없으면 반복이 계속 밝아서 귀에 거슬린다.
      final f = 1200 + (1 - damp) * 12000;
      _dampL.lowpass(f, 0.7);
      _dampR.lowpass(f, 0.7);
      _lastDamp = damp;
    }
    final n = _bufL.length;
    var d = (get('time') / 1000 * kSampleRate).round();
    if (d < 1) d = 1;
    if (d >= n) d = n - 1;
    var ri = _w - d;
    if (ri < 0) ri += n;

    // 방식 — 디지털(0) · 테이프(1) · 핑퐁(2)
    final mode = get('mode').round().clamp(0, 2);
    final ping = mode == 2;
    final tl = _bufL[ri], tr = _bufR[ri];
    final fb = get('fb');
    final inL = l + (ping ? tr : tl) * fb;
    final inR = r + (ping ? tl : tr) * fb;
    _bufL[_w] = _dampL.process(inL);
    _bufR[_w] = _dampR.process(inR);
    if (++_w >= n) _w = 0;

    final mix = get('mix');
    outL = l * (1 - mix) + tl * mix;
    outR = r * (1 - mix) + tr * mix;
  }
}

// ══════════════════ 코러스 ══════════════════
//
// **모듈레이션이 통째로 없었다.** 얇은 소리를 두껍게 만드는 수단이 리버브뿐인데,
// 리버브는 멀리 보내는 것이지 두껍게 하는 것이 아니다. 패드·기타·일렉피아노는
// 코러스 하나로 완전히 달라진다.
//
// 원리는 간단하다: **아주 짧은 딜레이(5~30ms)의 길이를 느리게 흔든다.**
// 그러면 원음과 살짝 어긋난 복사본이 생기고, 어긋난 양이 계속 변해서
// 「여럿이 같이 치는」 소리가 된다.
//
// 좌우를 **반대 위상**으로 흔드는 것이 핵심이다 — 같이 흔들면 가운데서 뭉쳐서
// 두꺼워지기만 하고 안 넓어진다. 반대로 흔들면 좌우로 벌어진다.
class ChorusFx extends Fx {
  ChorusFx() : super('chorus');

  static const _maxSec = 0.05; // 50ms 면 코러스·플랜저 범위를 다 덮는다
  final Float64List _bufL = Float64List((kSampleRate * _maxSec).round());
  final Float64List _bufR = Float64List((kSampleRate * _maxSec).round());
  int _w = 0;
  double _ph = 0;

  @override
  void reset() {
    _bufL.fillRange(0, _bufL.length, 0);
    _bufR.fillRange(0, _bufR.length, 0);
    _w = 0;
    _ph = 0;
  }

  /// 소수 자리까지 읽는다 — **정수로 끊으면 지직거린다**(흔드는 폭이 계단이 된다).
  double _read(Float64List b, double back) {
    final n = b.length;
    var x = _w - back;
    while (x < 0) {
      x += n;
    }
    final i = x.floor() % n;
    final j = (i + 1) % n;
    final f = x - x.floor();
    return b[i] * (1 - f) + b[j] * f;
  }

  @override
  void step(double l, double r) {
    final n = _bufL.length;
    _bufL[_w] = l;
    _bufR[_w] = r;

    // 방식 — 아날로그(0): 느리고 넓게 / 디지털(1): 빠르고 촘촘
    final analog = get('mode').round() != 1;
    final rate = get('rate') * (analog ? 1.0 : 2.2);
    final depthMs = get('depth') * (analog ? 1.0 : 0.55);

    _ph += rate / kSampleRate;
    if (_ph >= 1) _ph -= 1;
    final tw = math.sin(_ph * 2 * math.pi);

    // 가운데 지연 + 흔들림. 좌우를 **반대로** 흔들어 넓힌다.
    final centre = 12.0 * kSampleRate / 1000; // 12ms
    final swing = depthMs * kSampleRate / 1000;
    var backL = centre + tw * swing;
    var backR = centre - tw * swing;
    final lim = (n - 2).toDouble();
    if (backL < 1) backL = 1;
    if (backR < 1) backR = 1;
    if (backL > lim) backL = lim;
    if (backR > lim) backR = lim;

    final wetL = _read(_bufL, backL);
    final wetR = _read(_bufR, backR);
    if (++_w >= n) _w = 0;

    final mix = get('mix');
    outL = l * (1 - mix) + wetL * mix;
    outR = r * (1 - mix) + wetR * mix;
  }
}

// ══════════════════ 컴프 ══════════════════

/// 컴프레서 — 큰 소리를 눌러 **작은 소리와의 차이를 줄인다.**
///
/// 성향 셋은 어택·릴리스와 무릎(knee)이 다르다. 진짜 기기들의 차이가 거기 있다:
///  · 옵토(LA-2A 계열) — 느리고 부드럽다. 무릎이 넓어 눌리는 게 티가 안 난다.
///  · FET(1176 계열)  — 아주 빠르다. 타격의 앞머리를 잡아 앞으로 끌어낸다.
///  · VCA(SSL 계열)   — 중간. 딱 떨어지게 눌러서 리듬이 또렷해진다.
class CompFx extends Fx {
  CompFx() : super('comp');

  double _env = 0;

  @override
  void reset() => _env = 0;

  @override
  void step(double l, double r) {
    final mode = get('mode').round().clamp(0, 2);
    // 옵토 · FET · VCA — 초 단위
    final atk = [0.030, 0.0004, 0.006][mode] * (0.3 + get('atk') * 1.7);
    final rel = [0.45, 0.08, 0.18][mode] * (0.3 + get('rel') * 1.7);
    final knee = [12.0, 3.0, 6.0][mode];
    final thr = get('thr');
    final ratio = get('ratio');

    final peak = math.max(l.abs(), r.abs());
    final c = peak > _env
        ? math.exp(-1 / (atk * kSampleRate))
        : math.exp(-1 / (rel * kSampleRate));
    _env = peak + (_env - peak) * c;

    final db = _env <= 1e-9 ? -120.0 : 20 * math.log(_env) / math.ln10;
    var over = db - thr;
    double gainDb;
    if (over <= -knee / 2) {
      gainDb = 0;
    } else if (over >= knee / 2) {
      gainDb = -over * (1 - 1 / ratio);
    } else {
      // 무릎 — 문턱 근처를 부드럽게 넘어간다
      final x = over + knee / 2;
      gainDb = -(1 - 1 / ratio) * x * x / (2 * knee);
    }
    final g = math.pow(10, (gainDb + get('makeup')) / 20).toDouble();
    outL = l * g;
    outR = r * g;
  }

  /// 지금 얼마나 누르고 있나(dB, 0 이하). 화면의 게인 리덕션 미터가 읽는다.
  double get reduction {
    final db = _env <= 1e-9 ? -120.0 : 20 * math.log(_env) / math.ln10;
    final over = db - get('thr');
    if (over <= 0) return 0;
    return -over * (1 - 1 / get('ratio'));
  }
}

// ══════════════════ 리버브 ══════════════════

/// 리버브 — **룸 · 플레이트 · 홀** 셋.
///
/// 알고리즘은 마스터가 쓰던 것(`MasterReverb`, 슈뢰더 콤 4 + 올패스 2)을 그대로 쓴다.
/// 새로 짜지 않는다 — 같은 소리가 나야 마스터에 걸든 트랙에 걸든 예측이 된다.
/// 셋의 차이는 **길이 · 프리딜레이 · 밝기**다(`kReverbKinds`):
///   룸 0.85초·4.2k / 플레이트 1.7초·8.6k(밝고 촘촘) / 홀 2.6초·5.2k(길고 넓다)
class ReverbFx extends Fx {
  ReverbFx() : super('reverb');

  final MasterReverb _rv = MasterReverb();
  int _lastMode = -1;

  static const _kinds = ['room', 'plate', 'hall'];

  @override
  void reset() => _lastMode = -1;

  @override
  void step(double l, double r) {
    final mode = get('mode').round().clamp(0, 2);
    if (mode != _lastMode) {
      _rv.setKind(_kinds[mode]);
      _lastMode = mode;
    }
    final (wl, wr) = _rv.process(l, r);
    final mix = get('mix');
    outL = l * (1 - mix) + wl * mix;
    outR = r * (1 - mix) + wr * mix;
  }
}

// ══════════════════ 그래픽 EQ ══════════════════

/// 8밴드 그래픽 EQ — 옥타브마다 하나씩.
///
/// 파라메트릭(주파수·Q 를 직접 잡는 것)과 달리 **자리가 고정**이라 손이 빠르다.
/// 믹싱 중에 "여기가 좀 답답하네" 싶을 때 바로 그 칸을 내리면 된다.
class GeqFx extends Fx {
  GeqFx() : super('geq');

  static const freqs = [
    63.0,
    125.0,
    250.0,
    500.0,
    1000.0,
    2000.0,
    4000.0,
    8000.0,
  ];
  final List<Biquad> _l = List.generate(8, (_) => Biquad());
  final List<Biquad> _r = List.generate(8, (_) => Biquad());
  bool _dirty = true;

  @override
  void onParam() => _dirty = true;

  @override
  void reset() => _dirty = true;

  @override
  void step(double l, double r) {
    if (_dirty) {
      for (var i = 0; i < 8; i++) {
        final db = get('b$i');
        // Q 1.4 — 옥타브 간격에서 서로 너무 겹치지도, 사이가 비지도 않는 값
        _l[i].peaking(freqs[i], 1.4, db);
        _r[i].peaking(freqs[i], 1.4, db);
      }
      _dirty = false;
    }
    var a = l, b = r;
    for (var i = 0; i < 8; i++) {
      a = _l[i].process(a);
      b = _r[i].process(b);
    }
    outL = a;
    outR = b;
  }
}

// ══════════════════ 리미터 ══════════════════

/// 리미터 — **천장을 절대 안 넘게** 누른다.
///
/// 컴프와 다른 점: 비율이 사실상 ∞ 이고 어택이 즉시다. 그래서 "이 위로는 안 간다" 가
/// 지켜진다. 마스터 맨 끝에 두는 물건이다.
///
/// 릴리스가 너무 빠르면 저역에서 **펌핑**(소리가 숨쉬듯 출렁임)이 생긴다 —
/// 그래서 최소 30ms 는 준다.
class LimiterFx extends Fx {
  LimiterFx() : super('limiter');

  double _env = 0;

  @override
  void reset() => _env = 0;

  /// 지금 누르고 있는 양(dB, 0 이하). 화면 미터가 읽는다.
  double reduction = 0;

  @override
  void step(double l, double r) {
    final ceil = math.pow(10, get('ceil') / 20).toDouble();
    final drive = math.pow(10, get('drive') / 20).toDouble();
    final rel = 0.03 + get('rel') * 0.4;

    final a = l * drive, b = r * drive;
    final peak = math.max(a.abs(), b.abs());
    // 올라갈 때는 **즉시**(그래야 천장을 안 넘는다), 내려갈 때만 천천히
    if (peak > _env) {
      _env = peak;
    } else {
      _env = peak + (_env - peak) * math.exp(-1 / (rel * kSampleRate));
    }

    var g = 1.0;
    if (_env > ceil) g = ceil / _env;
    reduction = g >= 1 ? 0 : 20 * math.log(g) / math.ln10;
    outL = a * g;
    outR = b * g;
  }
}

// ══════════════════ 드라이브(페달) ══════════════════

/// 오버드라이브 · 디스토션 · 퍼즈 — 앰프 **앞에** 거는 페달.
///
/// 앰프와 따로 두는 이유: 실제로도 따로다. 페달로 먼저 밀고 앰프에서 다시 뭉개는 게
/// 기타 소리의 기본이다. 순서를 바꿔 꽂아 보면 완전히 다른 소리가 난다.
///   오버드라이브 — 부드럽게 눕힌다(tanh). 원음 성격이 남는다.
///   디스토션    — 더 세게, 딱딱하게 자른다.
///   퍼즈        — 거의 사각파로 만든다. 원음이 안 남는다.
class DriveFx extends Fx {
  DriveFx() : super('drive');

  final Biquad _toneL = Biquad(), _toneR = Biquad();
  bool _dirty = true;

  @override
  void onParam() => _dirty = true;

  @override
  void reset() => _dirty = true;

  @pragma('vm:prefer-inline')
  double _shape(double x, int mode) {
    switch (mode) {
      case 0: // 오버드라이브
        return _tanh(x);
      case 1: // 디스토션 — 무릎을 세우고 자른다
        return x.abs() < 0.7
            ? x * 1.2
            : (x > 0 ? 1.0 : -1.0) * (0.84 + 0.16 * _tanh((x.abs() - 0.7) * 4));
      default: // 퍼즈 — 거의 사각파
        return _tanh(x * 8);
    }
  }

  @pragma('vm:prefer-inline')
  static double _tanh(double x) {
    if (x > 4) return 1;
    if (x < -4) return -1;
    final e = math.exp(2 * x);
    return (e - 1) / (e + 1);
  }

  @override
  void step(double l, double r) {
    if (_dirty) {
      // 톤 — 페달의 그 손잡이. 돌리면 고역이 열리고 닫힌다.
      final f = 700 + get('tone') * 6000;
      _toneL.lowpass(f, 0.7);
      _toneR.lowpass(f, 0.7);
      _dirty = false;
    }
    final mode = get('mode').round().clamp(0, 2);
    final d = 1 + get('drive') * [12.0, 30.0, 40.0][mode];
    final lvl = get('level');
    var a = _shape(l * d, mode);
    var b = _shape(r * d, mode);
    a = _toneL.process(a);
    b = _toneR.process(b);
    // 게인을 올려도 볼륨만 커지지 않게
    final comp = 1 / (1 + get('drive') * 1.2);
    outL = a * lvl * comp;
    outR = b * lvl * comp;
  }
}

// ══════════════════ 베이스 앰프 ══════════════════

/// 베이스 앰프 — 기타 앰프와 **다른 물건**이다.
///
/// 핵심은 **블렌드**: 저역은 깨끗하게 두고 중고역만 뭉갠다. 베이스를 통째로 뭉개면
/// 곡의 바닥이 사라진다(실제 베이스 앰프·페달이 전부 이 구조인 이유).
/// 캐비닛도 기타보다 훨씬 낮게 자른다(기타 4~5k, 베이스 2.5k 언저리).
class BassAmpFx extends Fx {
  BassAmpFx() : super('bassamp');

  final Biquad _splitLoL = Biquad(), _splitLoR = Biquad(); // 깨끗하게 둘 저역
  final Biquad _splitHiL = Biquad(), _splitHiR = Biquad(); // 뭉갤 중고역
  final Biquad _bassL = Biquad(), _bassR = Biquad();
  final Biquad _midL = Biquad(), _midR = Biquad();
  final Biquad _trebL = Biquad(), _trebR = Biquad();
  final Biquad _cabL = Biquad(), _cabR = Biquad();
  bool _dirty = true;

  @override
  void onParam() => _dirty = true;

  @override
  void reset() => _dirty = true;

  @override
  void step(double l, double r) {
    if (_dirty) {
      const split = 250.0; // 여기 아래는 안 건드린다
      _splitLoL.lowpass(split, 0.7);
      _splitLoR.lowpass(split, 0.7);
      _splitHiL.highpass(split, 0.7);
      _splitHiR.highpass(split, 0.7);
      _bassL.lowShelf(80, get('bass'));
      _bassR.lowShelf(80, get('bass'));
      _midL.peaking(600, 0.8, get('mid'));
      _midR.peaking(600, 0.8, get('mid'));
      _trebL.highShelf(2500, get('treble'));
      _trebR.highShelf(2500, get('treble'));
      _cabL.lowpass(2600, 0.8); // 베이스 캡은 기타보다 훨씬 어둡다
      _cabR.lowpass(2600, 0.8);
      _dirty = false;
    }

    final d = 1 + get('drive') * 25;
    final blend = get('blend'); // 0 = 깨끗, 1 = 다 뭉갬

    // 저역은 그대로, 중고역만 뭉개서 다시 섞는다
    final loL = _splitLoL.process(l), loR = _splitLoR.process(r);
    final hiL = _splitHiL.process(l), hiR = _splitHiR.process(r);
    final dirtyL = DriveFx._tanh(hiL * d) / (1 + get('drive') * 1.4);
    final dirtyR = DriveFx._tanh(hiR * d) / (1 + get('drive') * 1.4);

    var a = loL + hiL * (1 - blend) + dirtyL * blend;
    var b = loR + hiR * (1 - blend) + dirtyR * blend;

    a = _trebL.process(_midL.process(_bassL.process(a)));
    b = _trebR.process(_midR.process(_bassR.process(b)));
    a = _cabL.process(a);
    b = _cabR.process(b);

    outL = a * get('level');
    outR = b * get('level');
  }
}

// ══════════════════ 모듈레이션(사용자 요청, 2026-09-16) ══════════════════

/// 트레몰로 — 소리 크기를 LFO 로 흔든다. 셋 중 **가장 단순한 모듈레이션**
/// (지연선이 아니라 게인만 흔든다) — 트윈 리버브 앰프의 그 손잡이.
class TremoloFx extends Fx {
  TremoloFx() : super('tremolo');

  double _ph = 0;

  @override
  void reset() => _ph = 0;

  @override
  void step(double l, double r) {
    final rate = get('rate');
    final depth = get('depth');
    final square = get('shape').round() == 1;
    _ph += rate / kSampleRate;
    if (_ph >= 1) _ph -= 1;
    // 사인(부드럽게 숨쉬듯) · 사각(딱딱 끊어서, 옛 신스 스텝 트레몰로 느낌)
    final lfo = square ? (_ph < 0.5 ? 1.0 : -1.0) : math.sin(_ph * 2 * math.pi);
    // lfo=1 → 그대로, lfo=-1 → (1-depth)까지 죽는다
    final g = 1 - depth * (1 - lfo) / 2;
    outL = l * g;
    outR = r * g;
  }
}

/// 플랜저 — 아주 짧은(1~8ms) 지연을 LFO 로 흔들고 **피드백**을 걸어 쉬익거리는
/// 빗살(comb) 소리를 낸다. 코러스(`ChorusFx`)와 같은 지연선 구조를 쓰지만
/// 지연이 훨씬 짧고 피드백이 있다 — 그래서 "넓어진다"가 아니라 "쉭쉭거린다".
class FlangerFx extends Fx {
  FlangerFx() : super('flanger');

  static const _maxSec = 0.015; // 15ms 면 플랜저 범위를 다 덮는다
  final Float64List _bufL = Float64List((kSampleRate * _maxSec).round());
  final Float64List _bufR = Float64List((kSampleRate * _maxSec).round());
  int _w = 0;
  double _ph = 0;

  @override
  void reset() {
    _bufL.fillRange(0, _bufL.length, 0);
    _bufR.fillRange(0, _bufR.length, 0);
    _w = 0;
    _ph = 0;
  }

  double _read(Float64List b, double back) {
    final n = b.length;
    var x = _w - back;
    while (x < 0) {
      x += n;
    }
    final i = x.floor() % n;
    final j = (i + 1) % n;
    final f = x - x.floor();
    return b[i] * (1 - f) + b[j] * f;
  }

  @override
  void step(double l, double r) {
    final rate = get('rate');
    final depthMs = get('depth');
    final fb = get('fb');
    final mix = get('mix');
    _ph += rate / kSampleRate;
    if (_ph >= 1) _ph -= 1;
    final tw = math.sin(_ph * 2 * math.pi);

    final n = _bufL.length;
    final centre = (depthMs * 0.5 + 0.6) * kSampleRate / 1000;
    final swing = depthMs * 0.5 * kSampleRate / 1000;
    final lim = (n - 2).toDouble();
    final back = (centre + tw * swing).clamp(1.0, lim);

    final wetL = _read(_bufL, back);
    final wetR = _read(_bufR, back);
    _bufL[_w] = l + wetL * fb;
    _bufR[_w] = r + wetR * fb;
    if (++_w >= n) _w = 0;

    outL = l * (1 - mix) + wetL * mix;
    outR = r * (1 - mix) + wetR * mix;
  }
}

/// 페이저 — 1차 올패스 필터 여러 개를 이어 붙이고, 그 중심 주파수를 LFO 로
/// 쓸어 준다. 지연선이 아니라 **위상만** 돌리는 것이라 플랜저보다 훨씬
/// 부드럽고 "우웅~" 하고 도는 느낌이 난다(진짜 아날로그 페이저 회로와 같은
/// 원리 — 여긴 Biquad 를 새로 안 늘리고 1차 올패스를 직접 짰다, 이 자리
/// 말고는 안 쓰여서 공용 필터에 넣을 이유가 없다).
class PhaserFx extends Fx {
  PhaserFx() : super('phaser');

  static const _stages = 4;
  final List<double> _zL = List.filled(_stages, 0.0);
  final List<double> _zR = List.filled(_stages, 0.0);
  double _ph = 0;
  double _fbL = 0, _fbR = 0;

  @override
  void reset() {
    for (var i = 0; i < _stages; i++) {
      _zL[i] = 0;
      _zR[i] = 0;
    }
    _ph = 0;
    _fbL = 0;
    _fbR = 0;
  }

  @pragma('vm:prefer-inline')
  double _allpass(double x, int i, List<double> z, double a) {
    final y = -a * x + z[i];
    z[i] = x + a * y;
    return y;
  }

  @override
  void step(double l, double r) {
    final rate = get('rate');
    final depth = get('depth');
    final fb = get('fb');
    final mix = get('mix');
    _ph += rate / kSampleRate;
    if (_ph >= 1) _ph -= 1;
    final lfo = (math.sin(_ph * 2 * math.pi) + 1) / 2; // 0~1
    const fMin = 300.0, fSpan = 2200.0;
    final freq = fMin + lfo * fSpan * depth;
    final wT = math.tan(math.pi * freq / kSampleRate);
    final a = (wT - 1) / (wT + 1);

    var xl = l + _fbL * fb;
    var xr = r + _fbR * fb;
    for (var i = 0; i < _stages; i++) {
      xl = _allpass(xl, i, _zL, a);
      xr = _allpass(xr, i, _zR, a);
    }
    _fbL = xl;
    _fbR = xr;
    outL = l * (1 - mix) + xl * mix;
    outR = r * (1 - mix) + xr * mix;
  }
}

// ══════════════════ 로파이(사용자 요청, 2026-09-16) ══════════════════

/// 비트크러셔 — 비트 수를 줄여 계단처럼 뭉개고(양자화), 샘플을 몇 개씩
/// 묶어 붙잡아(샘플레이트를 낮춘 것과 같은 효과) 옛날 게임기·로파이 힙합
/// 특유의 지직거리는 소리를 낸다.
class BitcrusherFx extends Fx {
  BitcrusherFx() : super('bitcrusher');

  double _holdL = 0, _holdR = 0;
  int _count = 0;

  @override
  void reset() {
    _holdL = 0;
    _holdR = 0;
    _count = 0;
  }

  @override
  void step(double l, double r) {
    final bits = get('bits').round().clamp(1, 16);
    final steps = math.pow(2.0, bits - 1).toDouble();
    final rateDiv = get('rate').round().clamp(1, 40);
    final mix = get('mix');

    if (_count % rateDiv == 0) {
      _holdL = (l * steps).roundToDouble() / steps;
      _holdR = (r * steps).roundToDouble() / steps;
    }
    _count++;
    outL = l * (1 - mix) + _holdL * mix;
    outR = r * (1 - mix) + _holdR * mix;
  }
}

/// 테이프 새추레이션 — 아주 살짝만 눕히고(3차 곡선, tanh 보다 은은하다)
/// 고역을 부드럽게 죽여서 카세트 테이프에 녹음한 듯한 따뜻함을 낸다.
/// `DriveFx`(오버드라이브·디스토션·퍼즈)보다 훨씬 얌전한 뭉갬이다 — 이건
/// "찌그러뜨리는" 페달이 아니라 "데워 주는" 질감용.
class TapeSaturationFx extends Fx {
  TapeSaturationFx() : super('tape');

  final Biquad _lpL = Biquad(), _lpR = Biquad();
  bool _dirty = true;

  @override
  void onParam() => _dirty = true;

  @override
  void reset() => _dirty = true;

  @pragma('vm:prefer-inline')
  static double _sat(double x) {
    final c = x.clamp(-1.6, 1.6);
    return c - (c * c * c) / 3.0 * 0.6;
  }

  @override
  void step(double l, double r) {
    if (_dirty) {
      final f = 4500 - get('warmth') * 2500; // 따뜻할수록 더 일찍 자른다
      _lpL.lowpass(f, 0.6);
      _lpR.lowpass(f, 0.6);
      _dirty = false;
    }
    final drive = 1 + get('drive') * 4;
    final lvl = get('level');
    var a = _sat(l * drive) / drive;
    var b = _sat(r * drive) / drive;
    a = _lpL.process(a);
    b = _lpR.process(b);
    outL = a * lvl;
    outR = b * lvl;
  }
}

// ══════════════════ EQ 보강(사용자 요청, 2026-09-16) ══════════════════

/// 파라메트릭 EQ — 그래픽 EQ(`GeqFx`)는 8밴드가 자리·폭이 고정이다. 이건
/// 대역 3개를 **원하는 주파수**로 옮겨 문제 자리만 정밀하게 잡는다(믹싱
/// 엔지니어가 실제로 제일 자주 쓰는 도구 — "200Hz 근처가 텅 빈다"처럼
/// 자리가 곡마다 다를 때).
class ParametricEqFx extends Fx {
  ParametricEqFx() : super('peq');

  final Biquad _b1L = Biquad(), _b1R = Biquad();
  final Biquad _b2L = Biquad(), _b2R = Biquad();
  final Biquad _b3L = Biquad(), _b3R = Biquad();
  double _lf1 = -1, _lg1 = 0, _lf2 = -1, _lg2 = 0, _lf3 = -1, _lg3 = 0;

  @override
  void reset() {
    _lf1 = -1;
    _lf2 = -1;
    _lf3 = -1;
  }

  void _refresh() {
    final f1 = get('f1'), g1 = get('g1');
    final f2 = get('f2'), g2 = get('g2');
    final f3 = get('f3'), g3 = get('g3');
    if (f1 != _lf1 || g1 != _lg1) {
      _b1L.peaking(f1, 1.0, g1);
      _b1R.peaking(f1, 1.0, g1);
      _lf1 = f1;
      _lg1 = g1;
    }
    if (f2 != _lf2 || g2 != _lg2) {
      _b2L.peaking(f2, 1.0, g2);
      _b2R.peaking(f2, 1.0, g2);
      _lf2 = f2;
      _lg2 = g2;
    }
    if (f3 != _lf3 || g3 != _lg3) {
      _b3L.peaking(f3, 1.0, g3);
      _b3R.peaking(f3, 1.0, g3);
      _lf3 = f3;
      _lg3 = g3;
    }
  }

  @override
  void step(double l, double r) {
    _refresh();
    var a = _b1L.process(l);
    a = _b2L.process(a);
    a = _b3L.process(a);
    var b = _b1R.process(r);
    b = _b2R.process(b);
    b = _b3R.process(b);
    outL = a;
    outR = b;
  }
}

// ══════════════════ 마스터링(사용자 요청, 2026-09-16) ══════════════════

/// 새추레이터/익사이터 — 고역만 따로 떼어(하이패스) 살짝 뭉갠 뒤 원음에
/// 얹는다. 전체를 뭉개는 `TapeSaturationFx`와 달리 **고역에만** 배음을
/// 더해서 "화사함/공기감"을 얹는다 — 원음 자체는 안 건드리고 위에
/// 얹기만 하니 마스터링 자리에 걸어도 balance 가 안 무너진다.
class ExciterFx extends Fx {
  ExciterFx() : super('exciter');

  final Biquad _hpL = Biquad(), _hpR = Biquad();
  double _lf = -1;

  @override
  void reset() => _lf = -1;

  @pragma('vm:prefer-inline')
  static double _harm(double x) => x - (x * x * x) / 3.0; // 홀수 배음 위주

  @override
  void step(double l, double r) {
    final f = get('freq');
    if (f != _lf) {
      _hpL.highpass(f, 0.7);
      _hpR.highpass(f, 0.7);
      _lf = f;
    }
    final amt = 1 + get('amount') * 6;
    final mix = get('mix');
    final hiL = _hpL.process(l);
    final hiR = _hpR.process(r);
    final exL = _harm((hiL * amt).clamp(-3.0, 3.0)) / amt;
    final exR = _harm((hiR * amt).clamp(-3.0, 3.0)) / amt;
    outL = l + exL * mix;
    outR = r + exR * mix;
  }
}

/// 러프니스 맥시마이저 — `LimiterFx`(브릭월 리미터)의 상위 버전. 리미터는
/// "넘지만 않게 누른다"가 전부지만, 이건 **먼저 밀어 넣고**(드라이브) 누른
/// 뒤 [character]만큼 소프트클립을 더 섞어서 "꽉 찬" 스트리밍 수준
/// 음압까지 끌어올린다 — 릴리스도 리미터보다 느긋하게 잡아(펌핑이 덜
/// 들리게) 마스터링 자리에 맞췄다.
class MaximizerFx extends Fx {
  MaximizerFx() : super('maximizer');

  double _env = 0;

  @override
  void reset() => _env = 0;

  /// 지금 누르고 있는 양(dB, 0 이하) — 화면 미터가 읽는다.
  double reduction = 0;

  @pragma('vm:prefer-inline')
  static double _softClip(double x, double ceil) {
    final a = x.abs();
    if (a <= ceil) return x;
    final over = a / ceil - 1;
    return (x > 0 ? 1.0 : -1.0) * ceil * (1 + (1 - math.exp(-over)) * 0.15);
  }

  @override
  void step(double l, double r) {
    final drive = math.pow(10, get('drive') * 12 / 20).toDouble(); // 0~12dB
    final ceil = math.pow(10, get('ceil') / 20).toDouble();
    final character = get('character');
    const rel = 0.12; // 마스터링용 — 리미터(0.03~0.43)보다 느긋하게 눌린다

    var a = l * drive, b = r * drive;
    final peak = math.max(a.abs(), b.abs());
    if (peak > _env) {
      _env = peak;
    } else {
      _env = peak + (_env - peak) * math.exp(-1 / (rel * kSampleRate));
    }
    var g = 1.0;
    if (_env > ceil) g = ceil / _env;
    reduction = g >= 1 ? 0 : 20 * math.log(g) / math.ln10;
    a *= g;
    b *= g;
    a = a * (1 - character) + _softClip(a, ceil) * character;
    b = b * (1 - character) + _softClip(b, ceil) * character;
    outL = a;
    outR = b;
  }
}

// ══════════════════ 목록 ══════════════════

/// 꽂을 수 있는 플러그인 전부. 화면은 이 표만 보고 목록과 손잡이를 만든다.
final Map<String, FxDef> kFxCatalog = {
  // 캐비닛(스피커)은 **손잡이가 없다** — 항상 켜져 있다.
  'amp': FxDef('amp', '기타 앰프', '밴드', const [
    FxParam(
      'mode',
      '성향',
      min: 0,
      max: 2,
      def: 1,
      choices: ['클린', '크런치', '하이게인'],
    ),
    FxParam('gain', '게인', min: 0, max: 1, def: 0.45, unit: '%'),
    FxParam('bass', '베이스', min: -12, max: 12, def: 0, unit: 'dB'),
    FxParam('mid', '미들', min: -12, max: 12, def: 0, unit: 'dB'),
    FxParam('treble', '트레블', min: -12, max: 12, def: 0, unit: 'dB'),
    FxParam('presence', '프레즌스', min: 0, max: 8, def: 2.5, unit: 'dB'),
    FxParam('level', '출력', min: 0, max: 1.5, def: 0.9, unit: '%'),
  ], AmpFx.new),
  'delay': FxDef('delay', '딜레이', '공간', const [
    FxParam(
      'mode',
      '방식',
      min: 0,
      max: 2,
      def: 0,
      choices: ['디지털', '테이프', '핑퐁'],
    ),
    FxParam('time', '시간', min: 20, max: 1200, def: 320, unit: 'ms'),
    FxParam('fb', '반복', min: 0, max: 0.9, def: 0.35, unit: '%'),
    FxParam('damp', '어둡게', min: 0, max: 1, def: 0.4, unit: '%'),
    FxParam('mix', '섞기', min: 0, max: 1, def: 0.25, unit: '%'),
  ], DelayFx.new),
  'reverb': FxDef('reverb', '리버브', '공간', const [
    FxParam('mode', '공간', min: 0, max: 2, def: 2, choices: ['룸', '플레이트', '홀']),
    FxParam('mix', '섞기', min: 0, max: 1, def: 0.25, unit: '%'),
  ], ReverbFx.new),
  'geq': FxDef('geq', '그래픽 EQ', 'EQ', const [
    FxParam('b0', '63', min: -12, max: 12, def: 0, unit: 'dB'),
    FxParam('b1', '125', min: -12, max: 12, def: 0, unit: 'dB'),
    FxParam('b2', '250', min: -12, max: 12, def: 0, unit: 'dB'),
    FxParam('b3', '500', min: -12, max: 12, def: 0, unit: 'dB'),
    FxParam('b4', '1k', min: -12, max: 12, def: 0, unit: 'dB'),
    FxParam('b5', '2k', min: -12, max: 12, def: 0, unit: 'dB'),
    FxParam('b6', '4k', min: -12, max: 12, def: 0, unit: 'dB'),
    FxParam('b7', '8k', min: -12, max: 12, def: 0, unit: 'dB'),
  ], GeqFx.new),
  'limiter': FxDef('limiter', '리미터', '다이내믹', const [
    FxParam('drive', '밀어넣기', min: 0, max: 18, def: 0, unit: 'dB'),
    FxParam('ceil', '천장', min: -12, max: 0, def: -0.3, unit: 'dB'),
    FxParam('rel', '릴리스', min: 0, max: 1, def: 0.35, unit: '%'),
  ], LimiterFx.new),
  'drive': FxDef('drive', '드라이브', '밴드', const [
    FxParam(
      'mode',
      '방식',
      min: 0,
      max: 2,
      def: 0,
      choices: ['오버드라이브', '디스토션', '퍼즈'],
    ),
    FxParam('drive', '드라이브', min: 0, max: 1, def: 0.4, unit: '%'),
    FxParam('tone', '톤', min: 0, max: 1, def: 0.5, unit: '%'),
    FxParam('level', '출력', min: 0, max: 1.5, def: 1.0, unit: '%'),
  ], DriveFx.new),
  'bassamp': FxDef('bassamp', '베이스 앰프', '밴드', const [
    FxParam('drive', '드라이브', min: 0, max: 1, def: 0.3, unit: '%'),
    FxParam('blend', '블렌드', min: 0, max: 1, def: 0.5, unit: '%'),
    FxParam('bass', '베이스', min: -12, max: 12, def: 0, unit: 'dB'),
    FxParam('mid', '미들', min: -12, max: 12, def: 0, unit: 'dB'),
    FxParam('treble', '트레블', min: -12, max: 12, def: 0, unit: 'dB'),
    FxParam('level', '출력', min: 0, max: 1.5, def: 1.0, unit: '%'),
  ], BassAmpFx.new),
  'chorus': FxDef('chorus', '코러스', '두께', const [
    FxParam('mode', '방식', min: 0, max: 1, def: 0, choices: ['아날로그', '디지털']),
    FxParam('rate', '속도', min: 0.05, max: 6, def: 0.6, unit: 'Hz'),
    FxParam('depth', '깊이', min: 0.5, max: 10, def: 4, unit: 'ms'),
    FxParam('mix', '섞기', min: 0, max: 1, def: 0.35, unit: '%'),
  ], ChorusFx.new),
  'comp': FxDef('comp', '컴프', '다이내믹', const [
    FxParam(
      'mode',
      '방식',
      min: 0,
      max: 2,
      def: 2,
      choices: ['옵토', 'FET', 'VCA'],
    ),
    FxParam('thr', '문턱', min: -40, max: 0, def: -18, unit: 'dB'),
    FxParam('ratio', '비율', min: 1, max: 20, def: 4, unit: ':1'),
    FxParam('atk', '어택', min: 0, max: 1, def: 0.5, unit: '%'),
    FxParam('rel', '릴리스', min: 0, max: 1, def: 0.5, unit: '%'),
    FxParam('makeup', '보정', min: 0, max: 18, def: 0, unit: 'dB'),
  ], CompFx.new),

  // ── 모듈레이션(사용자 요청, 2026-09-16) ──
  'tremolo': FxDef('tremolo', '트레몰로', '모듈레이션', const [
    FxParam('rate', '속도', min: 0.5, max: 10, def: 4, unit: 'Hz'),
    FxParam('depth', '깊이', min: 0, max: 1, def: 0.5, unit: '%'),
    FxParam('shape', '파형', min: 0, max: 1, def: 0, choices: ['사인', '사각']),
  ], TremoloFx.new),
  'flanger': FxDef('flanger', '플랜저', '모듈레이션', const [
    FxParam('rate', '속도', min: 0.05, max: 2, def: 0.25, unit: 'Hz'),
    FxParam('depth', '깊이', min: 0.5, max: 6, def: 3, unit: 'ms'),
    FxParam('fb', '피드백', min: 0, max: 0.9, def: 0.5, unit: '%'),
    FxParam('mix', '섞기', min: 0, max: 1, def: 0.5, unit: '%'),
  ], FlangerFx.new),
  'phaser': FxDef('phaser', '페이저', '모듈레이션', const [
    FxParam('rate', '속도', min: 0.05, max: 3, def: 0.4, unit: 'Hz'),
    FxParam('depth', '깊이', min: 0, max: 1, def: 0.7, unit: '%'),
    FxParam('fb', '피드백', min: 0, max: 0.9, def: 0.3, unit: '%'),
    FxParam('mix', '섞기', min: 0, max: 1, def: 0.5, unit: '%'),
  ], PhaserFx.new),

  // ── 로파이(사용자 요청, 2026-09-16) ──
  'bitcrusher': FxDef('bitcrusher', '비트크러셔', '로파이', const [
    FxParam('bits', '비트', min: 1, max: 16, def: 8, unit: ''),
    FxParam('rate', '샘플 간격', min: 1, max: 40, def: 4, unit: ''),
    FxParam('mix', '섞기', min: 0, max: 1, def: 1.0, unit: '%'),
  ], BitcrusherFx.new),
  'tape': FxDef('tape', '테이프 새추레이션', '로파이', const [
    FxParam('drive', '드라이브', min: 0, max: 1, def: 0.4, unit: '%'),
    FxParam('warmth', '따뜻함', min: 0, max: 1, def: 0.5, unit: '%'),
    FxParam('level', '출력', min: 0, max: 1.5, def: 1.0, unit: '%'),
  ], TapeSaturationFx.new),

  // ── EQ 보강(사용자 요청, 2026-09-16) ──
  'peq': FxDef('peq', '파라메트릭 EQ', 'EQ', const [
    FxParam('f1', '저역 자리', min: 60, max: 500, def: 150, unit: 'Hz'),
    FxParam('g1', '저역 양', min: -12, max: 12, def: 0, unit: 'dB'),
    FxParam('f2', '중역 자리', min: 200, max: 5000, def: 1000, unit: 'Hz'),
    FxParam('g2', '중역 양', min: -12, max: 12, def: 0, unit: 'dB'),
    FxParam('f3', '고역 자리', min: 1000, max: 16000, def: 4000, unit: 'Hz'),
    FxParam('g3', '고역 양', min: -12, max: 12, def: 0, unit: 'dB'),
  ], ParametricEqFx.new),

  // ── 마스터링(사용자 요청, 2026-09-16) ──
  'exciter': FxDef('exciter', '익사이터', '마스터링', const [
    FxParam('freq', '자리', min: 1000, max: 8000, def: 3000, unit: 'Hz'),
    FxParam('amount', '양', min: 0, max: 1, def: 0.3, unit: '%'),
    FxParam('mix', '섞기', min: 0, max: 1, def: 0.5, unit: '%'),
  ], ExciterFx.new),
  'maximizer': FxDef('maximizer', '러프니스 맥시마이저', '마스터링', const [
    FxParam('drive', '밀어넣기', min: 0, max: 1, def: 0.5, unit: '%'),
    FxParam('ceil', '천장', min: -3, max: 0, def: -0.3, unit: 'dB'),
    FxParam('character', '단단함', min: 0, max: 1, def: 0.3, unit: '%'),
  ], MaximizerFx.new),
};

/// 이름으로 하나 만든다. 모르는 종류면 null.
Fx? makeFx(String type) => kFxCatalog[type]?.make();

// ── 원탭 프리셋 ──
//
// 랙을 열면 amp·delay·reverb·geq·limiter·drive·bassamp·comp 여덟 개 목록이 나온다.
// **무엇을 왜 꽂아야 하는지 모르면 아무것도 못 꽂는다.** 그런데 이 앱을 쓰는 사람은
// 대개 그걸 모르는 쪽이다 — 「노래하듯」이나 「따뜻하게」는 안다.
//
// 그래서 **결과의 이름**으로 조합을 만들어 둔다. 꽂고 나면 손잡이는 그대로 다 있으니
// 만져 보며 배울 수도 있다(감추는 게 아니라 첫걸음을 놔 주는 것이다).

/// 프리셋 하나 — 이름 · 한 줄 설명 · 꽂을 것들(순서가 곧 소리다).
class FxPresetDef {
  final String name;
  final String desc;

  /// (플러그인 종류, 손잡이 값). 값이 빈 것은 그 플러그인 기본값 그대로다.
  final List<(String, Map<String, double>)> chain;
  const FxPresetDef(this.name, this.desc, this.chain);
}

/// 트랙 하나에 꽂는 조합 — 악기를 **어떻게 들리게** 할 것인가.
const List<FxPresetDef> kTrackFxPresets = [
  FxPresetDef('노래하듯', '가까이서 부르는 것처럼 — 고르게 눌러 주고 살짝 띄운다', [
    ('comp', {'mode': 0, 'thr': -20, 'ratio': 3, 'makeup': 3}),
    ('reverb', {'mode': 1, 'mix': 0.18}),
  ]),
  FxPresetDef('넓게', '좌우로 벌어진다 — 패드·스트링에 잘 맞는다', [
    ('chorus', {'mode': 0, 'rate': 0.45, 'depth': 5, 'mix': 0.32}),
    ('delay', {'mode': 2, 'time': 380, 'fb': 0.28, 'damp': 0.5, 'mix': 0.22}),
    ('reverb', {'mode': 2, 'mix': 0.34}),
  ]),
  FxPresetDef('두껍게', '여럿이 같이 치는 것처럼 — 얇은 소리를 채운다', [
    ('chorus', {'mode': 1, 'rate': 1.4, 'depth': 3, 'mix': 0.45}),
    ('comp', {'mode': 0, 'thr': -18, 'ratio': 2.5, 'makeup': 2}),
  ]),
  FxPresetDef('단단하게', '앞으로 나온다 — 베이스·드럼처럼 뼈대를 맡는 자리', [
    ('comp', {'mode': 2, 'thr': -14, 'ratio': 6, 'atk': 0.2, 'makeup': 4}),
    ('limiter', {'drive': 2, 'ceil': -0.5}),
  ]),
  FxPresetDef('몽롱하게', '멀리서 들리는 것처럼 — 뒤로 물러난다', [
    ('delay', {'mode': 1, 'time': 500, 'fb': 0.45, 'damp': 0.75, 'mix': 0.3}),
    ('reverb', {'mode': 2, 'mix': 0.5}),
  ]),
  FxPresetDef('거칠게', '살짝 찌그러뜨린다 — 기타·리드에', [
    ('drive', {'mode': 0, 'drive': 0.45, 'tone': 0.55, 'level': 1.0}),
    ('comp', {'mode': 1, 'thr': -16, 'ratio': 4, 'makeup': 2}),
  ]),
];

/// 곡 전체에 거는 조합(마스터) — **맨 마지막에 지나가는 자리**다.
const List<FxPresetDef> kMasterFxPresets = [
  FxPresetDef('따뜻하게', '저음을 살짝 올리고 날을 눕힌다', [
    ('geq', {'b0': 1.5, 'b1': 2, 'b6': -1.5, 'b7': -2}),
    ('comp', {'mode': 0, 'thr': -16, 'ratio': 2, 'makeup': 2}),
    ('limiter', {'ceil': -0.3}),
  ]),
  FxPresetDef('또렷하게', '가운데를 비우고 위를 열어 준다', [
    ('geq', {'b2': -2, 'b3': -1.5, 'b6': 2, 'b7': 2.5}),
    ('limiter', {'drive': 1.5, 'ceil': -0.3}),
  ]),
  FxPresetDef('클럽감', '아래가 굵고 전체가 앞으로 밀린다', [
    ('geq', {'b0': 3, 'b1': 2, 'b5': 1, 'b7': 1.5}),
    ('comp', {'mode': 2, 'thr': -12, 'ratio': 4, 'atk': 0.15, 'makeup': 3}),
    ('limiter', {'drive': 4, 'ceil': -0.2}),
  ]),
  FxPresetDef('로파이', '위아래를 깎아 옛 기계처럼', [
    ('geq', {'b0': -3, 'b6': -5, 'b7': -8}),
    ('drive', {'mode': 0, 'drive': 0.22, 'tone': 0.4, 'level': 1.0}),
    ('limiter', {'ceil': -0.5}),
  ]),
  FxPresetDef('그대로', '아무것도 안 건다 — 꽂은 걸 전부 뺀다', []),
];

/// 장르별 **자동 마스터링** — 스타일을 고르면(`project_settings_sheet.dart`)
/// [kMasterFxPresets] 에서 이 이름의 것을 그대로 얹는다. 여기 없는 장르는
/// '그대로'(아무것도 안 건다) — 재즈·앰비언트처럼 마이크 앞 소리 그대로가
/// 정체성인 장르는 원래도 인서트를 안 걸었다(`genre_fx.dart` 참고, 같은 규칙).
const Map<String, String> kGenreMasterPreset = {
  'lofi': '로파이',
  'house': '클럽감',
  'hiphop': '클럽감',
  'citypop': '또렷하게',
  'ballad': '따뜻하게',
  'rock': '또렷하게',
  'trap': '클럽감',
  'proghouse': '클럽감',
  'pop': '또렷하게',
  'drill': '클럽감',
  'rnb': '따뜻하게',
  'disco': '클럽감',
  'gospel': '따뜻하게',
  'waltz': '따뜻하게',
  'ballad68': '따뜻하게',
};

/// [genre] 에 맞는 자동 마스터링 프리셋 — 없으면 '그대로'(마지막 항목).
FxPresetDef masterPresetForGenre(String genre) {
  final name = kGenreMasterPreset[genre];
  return kMasterFxPresets.firstWhere(
    (p) => p.name == name,
    orElse: () => kMasterFxPresets.last,
  );
}
