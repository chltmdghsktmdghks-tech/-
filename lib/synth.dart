// 신디사이저 — 웹의 pitched() 를 네이티브로 옮긴 것.
//
// 웹은 음 하나마다 오실레이터·필터·게인 '노드'를 만들어 브라우저에 넘겼다.
// 여기서는 노드를 만들지 않는다. 음 하나 = SynthNote 객체 하나이고,
// 그 안에서 부분음(partial)·필터·엔벨로프를 직접 계산해 샘플을 뱉는다.
//
// 신호 흐름은 웹과 같게 맞췄다:
//   부분음들 ─┬─▶ 로우패스 ─▶ 몸통공명(최대2) ─▶ 앰프 엔벨로프 ─▶ 출력
//             └─▶ (가산합성·디테일 레이어는 자기 엔벨로프를 갖고 바로 출력으로)

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dsp.dart';
import 'instruments.dart';
import 'sampler.dart';

/// 휴머나이즈 세기 — 0 끔 / 1 자연스럽게 / 2 많이
class Human {
  static double t = 0.0055; // 타이밍 ±초
  static double c = 4; // 음정 ±cent
  static double v = 0.055; // 세기 ±비율
  static int level = 1;
  static void setLevel(int lv) {
    level = lv;
    const tt = [0.0, 0.0055, 0.014];
    const cc = [0.0, 4.0, 9.0];
    const vv = [0.0, 0.055, 0.13];
    t = tt[lv];
    c = cc[lv];
    v = vv[lv];
  }
}

final math.Random _rng = math.Random(20260811);
double _rnd2() => _rng.nextDouble() * 2 - 1;
double _hCent() =>
    Human.c == 0 ? 1.0 : math.pow(2, _rnd2() * Human.c / 1200).toDouble();
double _hVel() => Human.v == 0 ? 1.0 : 1 + _rnd2() * Human.v;

/// **박을 사람처럼 조금 흔든다** — 예약한 시각을 ±[Human.t] 안에서 밀고 당긴다.
///
/// 여태 흔든 것은 음정(cent)과 세기뿐이었다. `Human.t` 는 **선언만 되고 아무 데서도
/// 안 쓰였다** — 그래서 박이 자로 잰 듯 딱 맞았다. 사람이 친 것과 기계가 친 것의
/// 차이는 대개 거기서 난다.
///
/// 그루브·스윙(`feel.dart`)과는 다른 일이다. 그쪽은 **일부러** 미는 것이고
/// (뒷박을 늦추면 그게 스윙이다) 이건 **매번 조금씩 다른** 흔들림이다.
/// 둘 다 있어야 사람처럼 들린다.
///
/// **0보다 작아지지 않는다** — 앞으로 당겨 봐야 이미 지난 시각이라 곧바로 울리고,
/// 그러면 흔든 게 아니라 앞으로 튄 것이 된다.
double humanNudge(double delaySec) {
  if (Human.t <= 0) return delaySec;
  final v = delaySec + _rnd2() * Human.t;
  return v < 0 ? 0 : v;
}

const int _kMaxParts = 12;
const int _kMaxBursts = 2;

/// 치는·뜯는 악기가 음표 끝에서 남아 있는 크기 (peak 대비).
/// 0 에 가까울수록 웹처럼 금방 사라지고, 크면 끝까지 또렷하게 남는다.
const double kRingTail = 0.20;

/// 필터 계수를 매 샘플 다시 구하면 비싸다. 이 간격마다만 갱신한다.
/// 바이쿼드는 계수가 갑자기 바뀌면 상태와 안 맞아 '탁' 소리가 난다.
/// 간격이 넓을수록 그 튐이 커지므로 16샘플(0.3ms)로 좁혔다. 음이 여러 개 겹칠수록 티가 난다.
const int _kModStride = 16;

class _Burst {
  final Biquad f = Biquad();
  final Env env = Env();
  double panL = 1, panR = 1;
  int left = 0;
  bool on = false;
}

/// 4단계 4/N — 이 음이 어느 트랙 버스(mixer.dart TrackMixSet)로 갈지. 신호 생성과는
/// 무관하고 engine.dart 의 라우팅에서만 쓴다. 드럼은 별도 풀(DrumVoice)이라 여기 없다.
const int kPartBass = 0;
const int kPartChord = 1;
const int kPartMelody = 2;

/// 5단계 — **라이브 전용 버스**(손으로 치는 건반). 슬롯 인덱스가 아니라 표시값이라
/// 음수를 쓴다. 곡의 트랙 편성(`configure()`)이 바뀌어도 이 버스는 안 사라진다.
///
/// 왜 따로 두나: 이게 없으면 건반 소리가 멜로디 트랙 버스로 섞여서, 멜로디 페이더를
/// 내리면 **내가 치는 소리까지 같이 작아진다**. 웹도 라이브 채널을 따로 뒀다.
const int kPartLive = -2;

class SynthNote {
  bool active = false;
  int part = kPartMelody;

  // ── 부분음 (구조체 배열 대신 병렬 배열 — 할당을 줄이려고) ──
  int _np = 0;
  final List<Float32List?> _tab = List.filled(_kMaxParts, null);
  final Float64List _phase = Float64List(_kMaxParts);
  final Float64List _inc = Float64List(_kMaxParts); // 기본 위상증가(변조 전)
  final Float64List _gain = Float64List(_kMaxParts);
  final Float64List _panL = Float64List(_kMaxParts);
  final Float64List _panR = Float64List(_kMaxParts);
  final List<bool> _direct = List.filled(_kMaxParts, false);
  // 음마다 Env 를 새로 만들면 (가산합성 최대 6개 + 디테일 2개, 각각 안에 리스트 3개)
  // **음 하나에 객체가 30개 넘게** 생긴다. 트랩처럼 박자마다 여러 음이 한꺼번에 켜지는
  // 곡에서는 딱 그 순간 GC 가 돌아 렌더가 튀고, 그게 곧 오디오 끊김이다.
  // (A17 실측: 버퍼를 키울수록 언더런이 줄었다 = 스파이크 문제라는 뜻)
  // 그래서 미리 만들어 두고 재사용한다. `_pUseEnv` 가 그 자리를 쓰는지 표시한다.
  final List<Env> _pEnv = List.generate(_kMaxParts, (_) => Env());
  final List<bool> _pUseEnv = List.filled(_kMaxParts, false);
  final Int32List _pLeft = Int32List(_kMaxParts); // 남은 샘플 수

  // ── 필터 ──
  final Biquad _lpL = Biquad(), _lpR = Biquad();
  final List<Biquad> _brL = [Biquad(), Biquad()];
  final List<Biquad> _brR = [Biquad(), Biquad()];
  int _nbr = 0;
  bool _hasFilter = false;

  // 컷오프 변화 (뜯는 악기의 밝기 감소 · 워블 LFO)
  double _cutBase = 3000, _cutQ = 0.7;
  double _cutFrom = 0, _cutTo = 0;
  int _cutN = 0;
  bool _wobble = false;
  double _lfoPhase = 0;

  // ── 앰프 엔벨로프 ──
  final Env _env = Env();
  bool _envUsed = false;

  // ── 변조 (글라이드 · 벤드 · 비브라토) ──
  bool _mod = false;
  double _glideMul = 1; // 시작 배율
  int _glideN = 0;
  double _bendMul = 1;
  int _bendN = 0;
  double _vibHz = 0, _vibDepth = 0;
  int _vibDelay = 0;
  int _age = 0;
  double _freqMul = 1;

  // ── 디테일 레이어(노이즈 버스트) ──
  final List<_Burst> _bursts = List.generate(_kMaxBursts, (_) => _Burst());
  int _nb = 0;

  int _life = 0; // 남은 샘플 (안전장치)
  final Noise _noise = Noise();

  double outL = 0, outR = 0;

  // ── 표본 재생(악기 품질 1단계, `sampler.dart`) ──
  //
  // 이 넷만 쓰고 위의 오실레이터·필터·엔벨로프 필드는 하나도 안 건드린다 —
  // 합성 경로와 완전히 갈라 둬야, 표본이 없는 악기(대부분)는 지금까지와
  // 한 샘플도 안 달라진다.
  bool _sampleMode = false;
  Int16List? _smPcm;
  double _smPos = 0, _smRatio = 1, _smGain = 0;
  int _smRelStart = 0, _smRelLen = 1;
  double _smPanL = 1, _smPanR = 1;

  /// **손을 뗐을 때** 표본을 몇 샘플에 걸쳐 재울 것인가.
  ///
  /// 악기마다 다르다 — 뜯는·치는 악기(피아노·기타)는 손을 떼도 줄이 좀 더
  /// 울어야 자연스럽고(`RING` 의 첫 값), 켜는·부는 악기(바이올린·색소폰)는
  /// 활·숨이 멎으면 바로 멎는다. 시작할 때 정해 두고 `release()` 가 쓴다.
  int _smRelHold = 1;

  /// 부분음 자리를 잡는다. 자리 번호를 돌려주므로, 자기 엔벨로프가 필요한 층은
  /// `_pEnv[번호]` 를 받아서 채우면 된다(새로 만들지 않는다).
  int _addPart(
    Float32List tab,
    double freq,
    double gain, {
    double pan = 0,
    bool direct = false,
    bool useEnv = false,
    int lifeSamples = 1 << 30,
  }) {
    if (_np >= _kMaxParts) return -1;
    final i = _np++;
    _tab[i] = tab;
    _phase[i] = 0;
    _inc[i] = freq / kSampleRate;
    _gain[i] = gain;
    // 등파워 패닝 (Web Audio StereoPanner 와 같은 방식)
    final p = (pan.clamp(-1.0, 1.0) + 1) * math.pi / 4;
    _panL[i] = math.cos(p);
    _panR[i] = math.sin(p);
    _direct[i] = direct;
    _pUseEnv[i] = useEnv;
    _pLeft[i] = lifeSamples;
    return i;
  }

  /// 웹의 pitched(c,d,voice,t,freq,dur,v,soft,glideF) 와 같은 자리의 인자들.
  /// [vel] 1~3, [soft] 화음 반주처럼 살짝 죽여야 할 때, [glideF] 앞 음의 주파수(0이면 없음)
  void noteOn(
    String voice,
    double freq,
    double dur,
    int vel, {
    bool soft = false,
    double glideF = 0,
    bool highQuality = true,
    int part = kPartMelody,
    // ADSR 손잡이(사용자 요청, 2026-09-15) — null 이면 악기 기본값 그대로.
    // 표본 악기는 아래에서 `_startSample` 로 일찍 빠져나가 이 값을 안 본다.
    double? atkOverride,
    double? decOverride,
    double? susOverride,
    double? relOverride,
    // 유니즌 폭(cent) 손잡이(사용자 요청, 2026-09-17) — null 이면 악기
    // 기본값(`Inst.uni`) 그대로.
    double? uniOverride,
  }) {
    reset();
    active = true;
    this.part = part;

    freq *= _hCent(); // ① 사람다움: 음정 미세 흔들기
    if (glideF > 0 && (glideF - freq).abs() <= 0.5) glideF = 0; // 같은 높이면 의미 없음

    // **표본이 있으면 합성을 아예 안 탄다** — `sampler.dart`. 없으면(대부분의
    // 악기, 그리고 표본을 못 불러온 상황) 그대로 아래 합성 경로로 간다.
    final bank = kSampleBanks[voice];
    if (bank != null) {
      _startSample(bank, freq, dur, vel, soft, kSamplePan[voice] ?? 0.0, voice);
      return;
    }
    // 표본팩 악기인데 아직 안 읽었으면 지금 트리거한다(끝날 때까지 이번
    // 음은 합성으로 대신 나간다 — 끊김 없다, `sampler.dart` 문서 참고). 곡이
    // 안 쓰는 표본 악기는 이 줄을 아예 안 타서 미리 안 읽는다.
    if (kSampleInstrumentKeys.contains(voice)) {
      unawaited(ensureInstrumentLoaded(voice));
    }

    final I = INSTRUMENTS[voice] ?? kInstDefault;
    // 유니즌 폭 — 사용자가 손잡이를 만졌으면 그 값이 악기 기본값을 이긴다.
    final uni = uniOverride ?? I.uni;
    // `soft` = 반주로 깔리는 음(코드 트랙은 **전부** 이걸 단다).
    // 0.55 는 **너무 깊었다** — 코드 패턴에 이미 낮은 세기가 들어 있는데 그 위에
    // −5.2dB 를 또 깎아서, 재즈 피아노가 전체 대비 −14.9dB 로 묻혔다
    // (사용자 지적: "피아노 기타 안 들려", 트랙별 렌더로 확인).
    // 0.82 = −1.7dB — 멜로디를 안 가리면서 반주가 들리는 선.
    final V = (VG[vel] ?? 1.0) * (soft ? 0.82 : 1.0);
    double peak = I.peak;
    // 릴리스는 사용자가 만졌으면 그 값이 악기 기본값을 이긴다.
    double rel = relOverride ?? I.rel;
    double hold = I.holdFor(dur);

    // ── 어택 (5단계 48/N) ──
    // 악기마다 '소리가 서는' 시간이 다르고, **세게 칠수록 빨라진다.**
    // 여태 전부 5ms 였다 — 활 긋는 바이올린과 피크로 긁는 기타가 같을 수는 없다.
    // 사용자가 어택을 직접 잡아 뒀으면(ADSR 손잡이) 세기별 곡선을 안 타고
    // 그 값을 그대로 쓴다 — "느리게 서는 패드"처럼 확실하게 들려야 한다.
    final ak = ATK[voice] ?? ATK_DEF;
    var atk = atkOverride ?? (ak[0] * math.pow(2, -((vel - 2) / 1.0) * ak[1]).toDouble());
    if (soft && atkOverride == null) atk *= 1.25; // 반주로 살살 짚으면 더 무르게 선다
    // 짧은 음을 어택이 통째로 삼키면 안 된다 — 음 길이의 절반을 넘지 못하게.
    atk = atk.clamp(0.0008, math.max(0.0015, dur * 0.5));

    // 치는·뜯는 악기: 울림을 음표 길이에 맞춘다.
    // ringLen = 실제로 울릴 총 길이, rel = 그 뒤 짧게 정리하는 시간(댐퍼)
    final rg = RING[voice];
    final ringy = rg != null;
    double ringLen = 0;
    // 음정 보정 — 높은 음일수록 짧게 운다(RINGKEY 주석 참고). 1.0 이면 보정 없음.
    final rk = RINGKEY[voice];
    final kmul = rk == null
        ? 1.0
        : math.pow(261.63 / freq, rk).toDouble().clamp(0.5, 1.8);
    if (ringy) {
      ringLen = math.max(
        rg[0] * 0.7,
        math.min(rg[1] * kmul, dur * rg[2] * kmul),
      );
      // 댐퍼도 같이 — 굵은 저음현은 펠트를 대도 천천히 멎는다
      rel = rg[0] * (0.6 + 0.4 * kmul);
    } else {
      // 어택이 길어진 만큼 유지 구간을 줄인다 — **음 전체 길이는 그대로여야 한다.**
      // (안 그러면 스트링을 90ms 어택으로 바꾼 순간 곡 전체가 밀린다)
      hold = math.max(0.02, hold - (atk - 0.005));
    }

    // 세게 칠수록 밝게 · 키 트래킹
    final bright = 0.66 + 0.34 * (vel / 3);
    final kt = KEYTRACK[voice] ?? KT_DEF;
    final cutV = (I.cut * bright * math.pow(freq / 261.63, kt))
        .clamp(180.0, 16000.0)
        .toDouble();
    _cutQ = _wobbleOf(voice) ? 6.0 : (I.q != 0 ? I.q : 0.7);
    _cutBase = cutV;
    _wobble = _wobbleOf(voice);

    // 뜯는/치는 악기는 어택 순간 밝았다가 닫힌다
    if (PLUCKY[voice] == true) {
      // 세게 칠수록 더 활짝 열렸다 닫힌다 — 피아노에서 세기 차이가 '음량'이 아니라
      // '음색'으로 들리는 이유가 이것이다.
      final open = (1.45 + 0.95 * (vel / 3)) * (soft ? 0.82 : 1.0);
      // 밝기가 닫히는 속도는 **울림 길이를 따라간다.** 길게 우는 저음은 천천히
      // 어두워지고, 짧게 끊기는 고음은 금방 어두워진다.
      final dec = ringy
          ? (ringLen * 0.45).clamp(0.06, 1.4)
          : math.min(0.4, hold + rel);
      _cutFrom = math.min(16000.0, cutV * open);
      _cutTo = math.max(220.0, cutV * 0.64);
      _cutN = (math.max(0.04, dec) * kSampleRate).round();
    } else {
      _cutFrom = cutV;
      _cutTo = cutV;
      _cutN = 0;
    }
    _lpL.lowpass(_cutFrom, _cutQ);
    _lpR.lowpass(_cutFrom, _cutQ);
    _hasFilter = true;

    // 오실레이터 수만큼 음량 보정
    final uniCount = uni != 0 ? (highQuality ? 2 : 1) : 0;
    final voices =
        1 +
        uniCount +
        ((I.detune != 0 && highQuality) ? 1 : 0) +
        (I.sub ? 1 : 0);
    final comp = 1 / math.sqrt(math.max(1, voices)) * 1.35;
    final ampRaw = peak * V * _hVel(); // 오실레이터 수 보정 전
    final amp = ampRaw * comp;

    // 앰프 엔벨로프 — atk 는 위에서 악기·세기에 맞춰 구해 뒀다.
    // ringy(뜯는/치는) 악기는 buildRing 이라 ADSR 개념(디케이 시간·서스테인
    // 레벨)이 안 맞는다 — 그 계열은 어택·릴리스만 손잡이 대상이다
    // (`hasAdsr()`/`mixer_view.dart` 가 이 계열은 아예 안 보여 준다).
    if (ringy) {
      buildRing(_env, atk, ringLen, rel, amp, kRingTail);
    } else {
      buildAdsr(
        _env,
        atk,
        hold,
        rel,
        amp,
        susOverride ?? SUSLV[voice],
        decOverride: decOverride,
      );
    }
    _envUsed = true;
    _life = _env.totalSamples + (0.12 * kSampleRate).round();

    // ② 몸통 공명 — 로우패스 뒤, 엔벨로프 앞
    final br = BODY_RES[voice];
    if (br != null) {
      final n = highQuality ? math.min(2, br.length) : 1;
      for (var i = 0; i < n; i++) {
        _brL[i].peaking(br[i][0], br[i][1], br[i][2]);
        _brR[i].peaking(br[i][0], br[i][1], br[i][2]);
      }
      _nbr = n;
    }

    // ── 변조 준비 ──
    if (glideF > 0) {
      final gt = math.max(0.03, math.min(0.20, dur * 0.35));
      _glideMul = glideF / freq;
      _glideN = (gt * kSampleRate).round();
      _mod = true;
    }
    final bend = BEND[voice];
    if (glideF <= 0 && bend != null) {
      _bendMul = 1 - bend;
      _bendN = (0.05 * kSampleRate).round();
      _mod = true;
    }
    final vb = VIB[voice];
    if (vb != null && hold + rel > vb[2]) {
      _vibHz = vb[0];
      _vibDepth = vb[1];
      _vibDelay = (vb[2] * kSampleRate).round();
      _mod = true;
    }

    final sp = spaceOf(voice);
    final width = soft ? sp.w * 0.6 : sp.w;

    // ── ⑤ 배음별 독립 감쇠 (가산 합성) ──
    // 이 경로를 타는 악기는 기본 오실레이터를 쓰지 않는다.
    final add = ADDITIVE[voice];
    if (add != null) {
      final parts = highQuality ? add : add.sublist(0, math.min(3, add.length));
      final cmp = 1 / math.sqrt(parts.length) * 1.3;
      // 세게 칠수록 **위 배음이 살아난다** (5단계 48/N).
      // 여태 배음 세기가 고정이라 살살 친 피아노와 세게 친 피아노가 크기만 다르고
      // 음색은 똑같았다. 실제 피아노에서 세기 차이는 음량보다 음색으로 먼저 들린다.
      final hb = (0.45 + 0.55 * (vel / 3)) * (soft ? 0.9 : 1.0);
      // 울려야 할 총 길이. 치는·뜯는 악기는 '그린 음표 길이'가 곧 이 값이다.
      final life = ringy ? ringLen : math.max(0.12, hold + rel);
      // 웹과 같은 라우팅: 몸통 공명이 있으면 필터 체인을 타고, 없으면 바로 출력으로.
      final direct = br == null;
      // ── 앰프 엔벨로프는 **크기가 아니라 모양이다** (Phase 3) ──
      //
      // 여기 크기를 실으면 배음 쪽(`pk`)에 이미 들어 있는 것과 **겹쳐 곱해진다.**
      // 48/N 에서 세기(V)가 두 번 곱해지던 것을 잡았는데, 재 보니 두 개가 더 있었다:
      //
      //  · `I.peak` 이 두 번 — 0.52 짜리 피아노는 0.27 이 된다(−11dB)
      //  · `comp` 가 **만들지도 않은 오실레이터** 수로 나눈다. 유니즌·디튠은
      //    가산합성 경로에서 아예 안 만들어진다(배음이 그 자리를 대신한다).
      //    그런데도 √4 로 나누고 있었다(−6dB).
      //
      // 그래서 피아노가 다른 악기보다 **23.5dB** 작았다 — 킥보다 22.3dB 작다.
      // 혼자 들으면 멀쩡한데 곡에 넣으면 사라진다. 계획 5-2 가 제일 앞에 둔
      // 기준("단독으로 좋은 소리보다 Mix 안에서 좋은 소리")이 정확히 이걸 말한다.
      //
      // 크기는 전부 배음 쪽에 있다. 여기는 1.0 — 모양만 싣는다.
      if (!direct) buildRing(_env, atk, ringLen, rel, 1.0, kRingTail);
      var longest = 0;
      for (final p in parts) {
        final ratio = p[0], dm = p[2];
        // 배음이 높을수록 세기의 영향을 크게 받는다(1배음은 거의 그대로)
        final pa = p[1] * math.pow(hb, (ratio - 1) * 0.75).toDouble();
        // 배음마다 다른 속도로 사그라든다 — 높은 배음이 먼저 죽는 게 실제 악기다.
        // 감쇠배율(dm)이 body 길이를 정하므로 1배음은 음표 길이만큼, 위 배음은 그보다 짧게 산다.
        final body = math.max(0.05, life * dm);
        final pRel = math.max(0.04, rel * dm);
        final pk = math.max(0.0002, ampRaw * pa * cmp); // 웹: peak*V*amp*cmp
        final n = ((body + pRel + 0.03) * kSampleRate).round();
        if (n > longest) longest = n;
        final pi = _addPart(
          wSine.tableFor(freq * ratio),
          freq * ratio,
          1.0,
          direct: direct,
          useEnv: true,
          lifeSamples: n,
        );
        if (pi >= 0) {
          final e = _pEnv[pi];
          e.clear();
          // 배음도 **같은 어택으로** 선다. 여기가 0.004 로 박혀 있으면 기타를
          // 1.8ms 로 잡아도 소용이 없다 — 실제로 들리는 어택은 이쪽이다.
          e.add(atk, pk);
          e.add(body, math.max(0.0002, pk * kRingTail), exp: true);
          e.add(pRel, kSilent, exp: true);
          e.start();
        }
      }
      if (!direct) _envUsed = true;
      _life = math.max(_life, longest);
      if (highQuality) _charLayer(voice, freq, V, hold, rel, width, vel);
      return;
    }

    // ── 기본 경로 ──
    final tab = waveFor(voice, I.wave);
    _addPart(tab.tableFor(freq), freq, 1.0);

    // 폰 스피커는 60Hz 아래를 물리적으로 못 낸다.
    // 한 옥타브 위에 작게 겹쳐 두면 뇌가 원래 저음을 채워 들어서, 낮춘 베이스가 '들리게' 된다.
    if (BASS_VOICE[voice] == true && freq < 95) {
      _addPart(tab.tableFor(freq * 2), freq * 2, 0.30);
    }
    // 유니즌: 살짝 어긋난 복수 오실레이터 → 두께 + 좌우로 벌려 공간감
    if (uni != 0) {
      final up = freq * math.pow(2, uni / 1200);
      _addPart(tab.tableFor(up), up, 0.7, pan: -width);
      if (highQuality) {
        final dn = freq * math.pow(2, -uni / 1200);
        _addPart(tab.tableFor(dn), dn, 0.7, pan: width);
      }
    }
    if (I.detune != 0 && highQuality) {
      final f2 = freq * math.pow(2, I.detune / 1200);
      _addPart(tab.tableFor(f2), f2, 0.55, pan: width * 0.5);
    }
    if (I.sub) {
      _addPart(wSine.tableFor(freq / 2), freq / 2, 0.7); // 서브는 항상 가운데
    }
    if (highQuality) _charLayer(voice, freq, V, hold, rel, width, vel);
  }

  bool _wobbleOf(String v) => v == 'wobble';

  /// 악기별 정밀 튜닝 — 메인 오실레이터 위에 그 악기만의 실제 소리 특징을 한 겹 더.
  /// 음질 '보통'에서는 통째로 건너뛴다.
  void _charLayer(
    String voice,
    double f,
    double V,
    double hold,
    double rel,
    double width,
    int vel,
  ) {
    void part(double mul, double amt, double decay) {
      if (amt <= 0) return;
      final pi = _addPart(
        wSine.tableFor(f * mul),
        f * mul,
        1.0,
        direct: true,
        useEnv: true,
        lifeSamples: ((decay + 0.05) * kSampleRate).round(),
      );
      if (pi >= 0) {
        final e = _pEnv[pi];
        e.clear();
        e.add(0.004, amt * V);
        e.add(decay, kSilent, exp: true);
        e.start();
      }
    }

    void burst(
      double dur2,
      String type,
      double freqv,
      double q,
      double amt, [
      double pan = 0,
    ]) {
      if (_nb >= _kMaxBursts) return;
      final b = _bursts[_nb++];
      switch (type) {
        case 'lowpass':
          b.f.lowpass(freqv, 0);
          break;
        case 'highpass':
          b.f.highpass(freqv, 0);
          break;
        default:
          b.f.bandpass(freqv, q <= 0 ? 1.0 : q);
      }
      b.f.reset();
      b.env.clear();
      b.env.add(0.002, math.max(0.0002, amt * V));
      b.env.add(dur2, kSilent, exp: true);
      b.env.start();
      final p = (pan.clamp(-1.0, 1.0) + 1) * math.pi / 4;
      b.panL = math.cos(p);
      b.panR = math.sin(p);
      b.left = ((dur2 + 0.02) * kSampleRate).round();
      b.on = true;
    }

    // 세기 비율 — 디테일 층은 **세기에 따라 양이 달라진다**(5단계 48/N).
    // 살살 짚은 피아노에서 해머 소리가 쿵 하고 나면 그게 제일 먼저 가짜로 들린다.
    final vr = vel / 3.0;

    switch (voice) {
      case 'piano':
        part(2.002, 0.055, math.min(1.2, hold + rel)); // 약간 어긋난 2배음 = 현의 불협
        part(3.006, 0.022, math.min(0.7, hold + rel));
        // 해머가 현을 때리는 둔탁한 소리 — 세게 칠수록 크고 짧고 밝다
        burst(
          0.020 + 0.014 * vr,
          'lowpass',
          300 + 260 * vr,
          0,
          0.045 + 0.085 * vr,
        );
        break;
      case 'epiano':
        part(4.01, 0.036, 0.28); // 타인(tine)의 종소리
        part(6.02, 0.013, 0.16);
        burst(0.014, 'lowpass', 900, 0, 0.030 + 0.045 * vr); // 해머 펠트가 닿는 소리
        break;
      case 'guitar':
      case 'nylon':
        // 피크가 현을 긁는 소리. 세게 뜯을수록 크고 날카롭다.
        // 나일론은 손톱·살이라 훨씬 무디다 — 같은 코드로 두면 둘이 구별이 안 된다.
        final ny = voice == 'nylon';
        burst(
          ny ? 0.022 : 0.016,
          'bandpass',
          ny ? 1500 : 2400 + 700 * vr,
          ny ? 1.4 : 2.2,
          (ny ? 0.10 : 0.13) + (ny ? 0.06 : 0.13) * vr,
        );
        break;
      case 'pluck':
      case 'harp':
        burst(0.012, 'bandpass', 3200, 2.6, 0.14);
        break;
      case 'marimba':
        part(3.9, 0.065, 0.16);
        break;
      case 'bell':
        part(2.76, 0.075, math.min(2.0, hold + rel));
        part(5.4, 0.032, 0.9);
        break;
      case 'upright':
      case 'bass':
      case 'fingerbass':
        // 손가락이 현을 놓는 소리. 업라이트는 현이 굵고 장력이 낮아 훨씬 크다.
        burst(
          0.020,
          'lowpass',
          700,
          0,
          (voice == 'upright' ? 0.11 : 0.05) +
              (voice == 'upright' ? 0.11 : 0.07) * vr,
        );
        // 지판을 짚는 '딱' — 세게 뜯을 때만 들린다(약하게 뜯으면 안 난다)
        if (voice != 'bass' && vel >= 2) {
          burst(0.010, 'bandpass', 1900, 2.0, 0.030 * vr);
        }
        break;
      case 'strings':
      case 'jpstrings':
      case 'violin':
      case 'cello':
        burst(
          math.min(0.5, hold + rel),
          'highpass',
          2400,
          0,
          0.020,
          width * 0.5,
        );
        break;
      case 'flute':
        burst(math.min(0.6, hold + rel), 'highpass', 3000, 0, 0.036); // 숨소리
        break;
      case 'clarinet':
      case 'sax':
        burst(0.05, 'bandpass', 1800, 1.2, 0.04); // 리드 떨림
        break;
      case 'trumpet':
      case 'brass':
      case 'analogbrass':
        burst(0.03, 'highpass', 2600, 0, 0.033); // 입술 어택
        break;
      case 'organ':
      case 'vintorgan':
        // **키 클릭** — 해먼드는 건반을 누르는 순간 접점이 붙으며 '틱' 한다.
        // 이게 없으면 아무리 배음을 맞춰도 오르간이 아니라 그냥 사인 패드로 들린다.
        // 세기와 거의 무관하다(접점은 세게 눌러도 똑같이 붙는다).
        burst(0.006, 'bandpass', 2400, 1.3, 0.11);
        break;
    }
  }

  /// 표본으로 노트를 켠다 — 오실레이터·필터·엔벨로프를 하나도 안 쓴다.
  ///
  /// [dur] 보다 길게 눌려 있으면(손을 늦게 뗀 라이브 연주 등) 표본이 자연
  /// 감쇄로 다 울기 전에 짧게 눌러 끈다(release) — 안 그러면 손을 뗀 지
  /// 한참 지나서도 5초짜리 표본이 계속 운다.
  void _startSample(
    SampleBank bank,
    double freq,
    double dur,
    int vel,
    bool soft,
    double pan,
    String voice,
  ) {
    final c = bank.pick(vel, freq);
    _sampleMode = true;
    _smPcm = c.pcm;
    _smPos = 0;
    _smRatio = freq / c.rootFreq * (c.sampleRate / kSampleRate);
    // 세기별 음량 — **녹음이 세기를 이미 담고 있는 악기는 완만한 표**를 쓴다
    // (`kRealVelSamples`). 신스용 VG 를 그대로 곱하면 첼로·바이올린의 여리게가
    // −43dB 까지 내려가 안 들렸다. 거기에 악기별 음량 맞추기(`kSampleTrim`)를
    // 곱한다 — 녹음 레벨이 33dB 까지 벌어져 있어서 안 맞추면 한 밴드가 안 된다.
    final vg = kRealVelSamples.contains(voice)
        ? (kSampleVG[vel] ?? 0.9)
        : (VG[vel] ?? 0.6);
    _smGain = vg * (kSampleTrim[voice] ?? 1.0) * (soft ? 0.82 : 1.0);
    _smRelLen = (0.08 * kSampleRate).round(); // 80ms — 손 뗀 순간의 클릭을 없앤다
    _smRelStart = math.max(_smRelLen, (dur * kSampleRate).round());
    // 손을 뗐을 때 쓸 길이. 뜯는·치는 악기는 줄이 좀 더 울어야 자연스럽다
    // (`RING` 의 첫 값 = 그 악기의 기본 릴리즈). 표에 없는 켜는·부는 악기는
    // 활·숨이 멎으면 바로 멎으므로 80ms 그대로.
    final ring = RING[voice];
    _smRelHold = ring == null
        ? _smRelLen
        : math.max(_smRelLen, (ring[0] * kSampleRate).round());
    // 등파워 패닝 — **`sqrt2` 로 보정한다**(드럼과 같은 방식, `drums.dart` 의
    // `_setPan` 참고). 안 하면 가운데(pan=0)가 두 채널 다 0.707배로
    // 조용해지고, 오른쪽으로 15%만 틀어도(바이올린 0.35) 왼쪽 채널이
    // 0.49배(-6dB)까지 떨어진다 — **모노였을 때보다 또렷이 조용해진다.**
    // 표본 세기 표(VG)는 이 패닝이 없던 시절에 맞춰 둔 값이라, 보정을 안
    // 하면 표본 악기 전체가 합성 악기보다 뒤로 밀려 들린다(사용자 지적:
    // "밴드(재즈·기타·베이스)가 특히 안 좋게 들린다" — 최근 표본화한 것들이
    // 바로 이 무보정 패닝을 먼저 탔다).
    final p = (pan.clamp(-1.0, 1.0) + 1) * math.pi / 4;
    _smPanL = math.cos(p) * math.sqrt2;
    _smPanR = math.sin(p) * math.sqrt2;
    _age = 0;
  }

  void reset() {
    _sampleMode = false;
    _np = 0;
    _nb = 0;
    _nbr = 0;
    _mod = false;
    _glideMul = 1;
    _glideN = 0;
    _bendMul = 1;
    _bendN = 0;
    _vibHz = 0;
    _vibDepth = 0;
    _vibDelay = 0;
    _age = 0;
    _freqMul = 1;
    _lfoPhase = 0;
    _cutN = 0;
    _wobble = false;
    _envUsed = false;
    _hasFilter = false;
    _life = 0;
    _lpL.reset();
    _lpR.reset();
    for (var i = 0; i < 2; i++) {
      _brL[i].reset();
      _brR[i].reset();
    }
    for (final b in _bursts) {
      b.on = false;
    }
    for (var i = 0; i < _kMaxParts; i++) {
      _pUseEnv[i] = false;
      _tab[i] = null;
    }
    active = false;
  }

  /// **잡아 둔 소리를 놓는다** — 손가락을 뗀 순간.
  ///
  /// 엔벨로프를 릴리스 구간으로 옮기고 수명을 그만큼으로 줄인다. 수명을 안 줄이면
  /// 소리는 멎었는데 목소리는 계속 물고 있어서, 빨리 여러 번 치면 목소리가 바닥난다.
  void release() {
    if (!active) return;
    // ── 표본 경로는 **따로 재워야 한다** (2026-09-22) ──
    //
    // `_nextSample` 은 `_env` 도 `_life` 도 안 읽고, `_life` 를 깎는 줄(아래
    // 합성 경로)도 `next()` 가 표본일 때 먼저 `return` 해서 안 탄다. 그래서
    // 여기서 엔벨로프만 놓아 봐야 **표본에는 아무 일도 안 일어났다** —
    // 손을 떼도 그 표본이 끝까지(길면 몇 초) 그대로 울었고, 빨리 연타하면
    // 안 꺼진 음이 겹겹이 쌓여 뭉갰다. `_startSample` 의 머리말이 "손을 늦게
    // 뗀 라이브 연주는 짧게 눌러 끈다"고 적어 둔 그 동작이 배선만 빠져 있었다.
    //
    // `math.min` 이어야 한다 — 그냥 대입하면 이미 잦아들던 음에 release 가
    // 한 번 더 왔을 때 페이드가 처음으로 되감긴다.
    if (_sampleMode) {
      _smRelLen = _smRelHold < 1 ? 1 : _smRelHold;
      if (_age < _smRelStart) _smRelStart = _age;
      return;
    }
    _env.release();
    final left = _env.releaseSamples + (0.05 * kSampleRate).round();
    if (left < _life) _life = left;
  }

  /// 다음 샘플 한 개를 outL/outR 에 넣는다
  void next() {
    outL = 0;
    outR = 0;
    if (!active) return;
    if (_sampleMode) {
      _nextSample();
      return;
    }

    // ── 변조 갱신 ──
    if (_mod) {
      var m = 1.0;
      if (_glideN > 0) {
        // 지수 램프: glideMul → 1
        final t = _age >= _glideN ? 1.0 : _age / _glideN;
        m *= math.pow(_glideMul, 1 - t).toDouble();
      }
      if (_bendN > 0 && _age < _bendN) {
        final t = _age / _bendN;
        m *= math.pow(_bendMul, 1 - t).toDouble();
      }
      if (_vibHz > 0 && _age > _vibDelay) {
        // 걸리기까지 0.18초 동안 서서히 깊어진다
        final ramp = math.min(1.0, (_age - _vibDelay) / (0.18 * kSampleRate));
        _lfoPhase += _vibHz / kSampleRate;
        if (_lfoPhase >= 1) _lfoPhase -= 1;
        m *= 1 + _vibDepth * ramp * readTable(wSine.tables[10], _lfoPhase);
      }
      _freqMul = m;
    }

    // ── 필터 계수 갱신 (32샘플마다) ──
    if (_hasFilter && (_age & (_kModStride - 1)) == 0) {
      double cut = _cutBase;
      if (_cutN > 0) {
        final t = _age >= _cutN ? 1.0 : _age / _cutN;
        cut = _cutFrom * math.pow(_cutTo / _cutFrom, t).toDouble();
      }
      if (_wobble) {
        _lfoPhase += 5.0 * _kModStride / kSampleRate; // 필터 LFO 5Hz
        if (_lfoPhase >= 1) _lfoPhase -= 1;
        cut += 260 * readTable(wSine.tables[10], _lfoPhase);
      }
      if (_cutN > 0 || _wobble) {
        final c = cut.clamp(60.0, 18000.0);
        _lpL.lowpass(c, _cutQ);
        _lpR.lowpass(c, _cutQ);
      }
    }

    // ── 부분음 ──
    double busL = 0, busR = 0; // 필터를 타는 신호
    double dirL = 0, dirR = 0; // 바로 출력으로 가는 신호
    var alive = false;
    for (var i = 0; i < _np; i++) {
      if (_pLeft[i] <= 0) continue;
      _pLeft[i]--;
      alive = true;
      final t = _tab[i]!;
      var ph = _phase[i] + _inc[i] * _freqMul;
      if (ph >= 1.0) ph -= ph.floorToDouble();
      _phase[i] = ph;
      var s = readTable(t, ph) * _gain[i];
      if (_pUseEnv[i]) {
        final e = _pEnv[i];
        if (e.done) {
          _pLeft[i] = 0;
          continue;
        }
        s *= e.next();
      }
      if (_direct[i]) {
        dirL += s * _panL[i];
        dirR += s * _panR[i];
      } else {
        busL += s * _panL[i];
        busR += s * _panR[i];
      }
    }

    // ── 필터 → 몸통 공명 → 앰프 엔벨로프 ──
    if (_hasFilter) {
      busL = _lpL.process(busL);
      busR = _lpR.process(busR);
      for (var i = 0; i < _nbr; i++) {
        busL = _brL[i].process(busL);
        busR = _brR[i].process(busR);
      }
    }
    if (_envUsed) {
      if (!_env.done) {
        final g = _env.next();
        busL *= g;
        busR *= g;
        alive = true;
      } else {
        busL = 0;
        busR = 0;
      }
    }

    // ── 디테일 레이어 ──
    for (var i = 0; i < _nb; i++) {
      final b = _bursts[i];
      if (!b.on) continue;
      if (b.left-- <= 0 || b.env.done) {
        b.on = false;
        continue;
      }
      final n = b.f.process(_noise.next()) * b.env.next();
      dirL += n * b.panL;
      dirR += n * b.panR;
      alive = true;
    }

    outL = busL + dirL;
    outR = busR + dirR;

    _age++;
    if (--_life <= 0 || !alive) active = false;
  }

  /// 표본 재생 한 샘플 — 선형보간으로 표본 자신의 자에서 목표 자로 늘이거나
  /// 줄인다(피치 시프트). 다른 부분음·필터·엔벨로프 필드는 손대지 않는다.
  void _nextSample() {
    final pcm = _smPcm;
    if (pcm == null) {
      active = false;
      return;
    }
    final idx = _smPos.floor();
    if (idx + 1 >= pcm.length) {
      active = false;
      return;
    }
    final frac = _smPos - idx;
    final s0 = pcm[idx] / 32768.0;
    final s1 = pcm[idx + 1] / 32768.0;
    var s = (s0 + (s1 - s0) * frac) * _smGain;
    if (_age >= _smRelStart) {
      final t = ((_age - _smRelStart) / _smRelLen).clamp(0.0, 1.0);
      s *= 1 - t;
      if (t >= 1.0) active = false;
    }
    outL = s * _smPanL;
    outR = s * _smPanR;
    _smPos += _smRatio;
    _age++;
  }
}
