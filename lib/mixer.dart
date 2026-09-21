// 3단계 — 마스터 버스 (HPF/LPF · 20밴드 그래픽 EQ(3밴드 모드 포함) · 컴프레서 · 리버브 ·
// EQ/컴프 순서 전환)
//
// 웹의 마스터 체인(`buildMasterChain`/`applyMaster`, app.html)을 옮긴 것. 3단계 1/N(EQ/컴프)·
// 2/N(리버브)에 이어 3/N 에서 **진짜 20밴드**로 바꿨다 — 예전엔 저(150Hz)/중(1kHz)/고(4kHz)
// 필터 3개로 3밴드 모드를 "근사"했는데, 웹은 실제로 20밴드 체인이 있고 3밴드 모드는 그
// 20밴드에 그룹으로 분배할 뿐이다(`MST_EQ3`). 이제 그 구조를 그대로 옮겼다 — 3밴드 모드도
// 20밴드 체인을 거치므로 더는 근사가 아니다. 웹 `MASTER.order`(EQ/컴프 순서)도 옮겼다.
//
// 아직 안 옮긴 것(다음 덩어리): 트랙별 FX·사이드체인 덕킹, 곡별 믹스(`GENRE_MIX`) — 트랙
// 개념 자체가 아직 없어서(4단계 곡 데이터 이식 전) 지금은 걸 자리가 없다.
//
// 기존 `Engine.render()` 의 룩어헤드 리미터(engine.dart)는 그대로 두고, 이 마스터 버스는
// masterGain(헤드룸) 적용 **뒤** · 리미터 **앞**에 끼운다. 웹의 순서(master gain → EQ/컴프 →
// 리버브 → 리미터)와 같다.
//
// 기본값은 전부 '투명'하다 (EQ 0dB·컴프 wet 0·HPF 20Hz·LPF 20000Hz) — 웹의 MASTER 기본값과
// 같다. 즉 아무도 손대지 않으면 1·2단계에서 검증된 소리가 그대로 나가야 한다.
// (peaking/shelf 필터는 gainDb=0 이면 RBJ 쿡북 계수가 항등필터로 접힌다 — 새로 만든 값이 아니다)

import 'dart:math' as math;
import 'dart:typed_data';
import 'dsp.dart';
import 'fx.dart';

/// 마스터 20밴드 EQ 중심 주파수 — 웹 `MST_EQ_FREQ` 그대로(1/3옥타브 근사).
const List<double> kMstEqFreq = [
  25, 32, 40, 50, 63, 80, 100, 125, 160, 200, //
  315, 500, 800, 1250, 2000, 3150, 5000, 8000, 12500, 16000,
];

/// 3밴드 모드가 20밴드 중 어느 인덱스를 묶는지 — 웹 `MST_EQ3` 그대로.
const List<int> kMstEq3Lo = [0, 1, 2, 3, 4, 5, 6];
const List<int> kMstEq3Mid = [7, 8, 9, 10, 11, 12, 13];
const List<int> kMstEq3Hi = [14, 15, 16, 17, 18, 19];

/// 컴프레서 소프트니 폭(dB) 표준식 — Giannoulis/Massberg/Reiss,
/// "Digital Dynamic Range Compressor Design" 의 static curve.
/// Web Audio 의 DynamicsCompressor 내부 알고리즘은 비공개라 그대로 옮길 수 없다.
/// **이건 웹에서 옮긴 게 아니라 새로 설계한 것이다** — 문·비·아탁·릴리즈·니 파라미터의
/// '의미'만 웹과 맞췄다(MASTER.compThr/compRatio/compAtk/compRel/compKnee 그대로 재사용 가능).
class MasterBus {
  // ── EQ 모드 — '3'=저/중/고 3밴드(20밴드에 그룹 분배) '20'=20밴드 직접 제어.
  // 웹 `MASTER.eqMode`/`applyMaster()` 의 if(eqMode==='20') 분기 그대로.
  String eqMode = '3';
  double eqLoDb = 0, eqMidDb = 0, eqHiDb = 0; // 3밴드 모드에서 쓴다
  final List<double> eq20 = List<double>.filled(
    20,
    0.0,
  ); // 20밴드 모드에서 쓴다(밴드별 dB)

  // ── EQ/컴프 순서 — 웹 `MASTER.order[0]==='eq'` 그대로. HPF/LPF 는 EQ 체인에 묶여 함께 움직인다
  // (웹 `wireMasterOrder()` 에서 `eqIn=n.eqLo`(=mHp)부터 시작하는 것과 같은 이유).
  bool eqFirst = true;

  // ── 하이패스/로우패스 (Hz) ──
  double hpfFreq = 20, lpfFreq = 20000;

  // ── 컴프레서 — 필드명·기본값은 웹 MASTER 그대로 ──
  double compWet = 0; // 0=완전 드라이(꺼짐) 1=완전 젖음 — 웹 MASTER.comp
  double compThr = -14,
      compRatio = 3,
      compAtk = 0.004,
      compRel = 0.2,
      compKnee = 8;
  double compMakeupDb = 0;

  // ── 마스터 리버브 — 웹 MASTER.rev/revKind 그대로 (양 0~0.4가 웹 UI 범위, 필드는 0~1 허용) ──
  double revWet = 0;
  String revKind = 'hall';
  final MasterReverb _reverb = MasterReverb();
  String _lastRevKind = '';

  final Biquad _hpfL = Biquad(), _hpfR = Biquad();
  final Biquad _lpfL = Biquad(), _lpfR = Biquad();
  final List<Biquad> _eqL = List.generate(20, (_) => Biquad());
  final List<Biquad> _eqR = List.generate(20, (_) => Biquad());
  final List<double> _lastEq20 = List<double>.filled(20, double.nan);

  bool _dirty = true;
  double _lastHpf = -1, _lastLpf = -1;

  /// 진단용 — 컴프가 지금 몇 dB 깎고 있나 (스무딩된 값, <=0)
  double compGrDb = 0;

  /// 파라미터를 바꾼 뒤 반드시 부른다(필터 계수는 값이 바뀔 때만 다시 구한다 — 매 샘플이면 낭비).
  void markDirty() => _dirty = true;

  void _updateFilters() {
    if (hpfFreq != _lastHpf) {
      _hpfL.highpass(hpfFreq, 0.7);
      _hpfR.highpass(hpfFreq, 0.7);
      _lastHpf = hpfFreq;
    }
    if (lpfFreq != _lastLpf) {
      _lpfL.lowpass(lpfFreq, 0.7);
      _lpfR.lowpass(lpfFreq, 0.7);
      _lastLpf = lpfFreq;
    }

    // 20밴드 게인 배열 — 3밴드 모드면 그룹으로 나눠 넣는다(웹 applyMaster 그대로).
    List<double> g;
    if (eqMode == '20') {
      g = eq20;
    } else {
      g = List<double>.filled(20, 0.0);
      for (final i in kMstEq3Lo) {
        g[i] = eqLoDb;
      }
      for (final i in kMstEq3Mid) {
        g[i] = eqMidDb;
      }
      for (final i in kMstEq3Hi) {
        g[i] = eqHiDb;
      }
    }
    for (var i = 0; i < 20; i++) {
      if (g[i] == _lastEq20[i]) continue;
      final f = kMstEqFreq[i];
      if (i == 0) {
        _eqL[i].lowShelf(f, g[i]);
        _eqR[i].lowShelf(f, g[i]);
      } else if (i == kMstEqFreq.length - 1) {
        _eqL[i].highShelf(f, g[i]);
        _eqR[i].highShelf(f, g[i]);
      } else {
        _eqL[i].peaking(f, 2.2, g[i]);
        _eqR[i].peaking(f, 2.2, g[i]);
      }
      _lastEq20[i] = g[i];
    }
    _dirty = false;
  }

  static double _coef(double sec) =>
      math.exp(-1 / (math.max(0.0005, sec) * kSampleRate));

  /// 하이패스·로우패스·20밴드 EQ 체인 — 웹 `wireMasterOrder()` 의 `eqIn..eqOut` 구간과 같다.
  @pragma('vm:prefer-inline')
  (double, double) _processEq(double l, double r) {
    l = _hpfL.process(l);
    r = _hpfR.process(r);
    l = _lpfL.process(l);
    r = _lpfR.process(r);
    for (var i = 0; i < 20; i++) {
      l = _eqL[i].process(l);
      r = _eqR[i].process(r);
    }
    return (l, r);
  }

  @pragma('vm:prefer-inline')
  (double, double) _processComp(double l, double r) {
    if (compWet > 0) {
      final dl = l, dr = r;
      final level = l.abs() > r.abs() ? l.abs() : r.abs();
      final xg = 20 * math.log(level < 1e-9 ? 1e-9 : level) / math.ln10;
      final w = compKnee <= 0 ? 0.01 : compKnee;
      final diff = xg - compThr;
      double yg;
      if (2 * diff <= -w) {
        yg = xg;
      } else if (2 * diff.abs() <= w) {
        yg =
            xg +
            (1 / compRatio - 1) * (diff + w / 2) * (diff + w / 2) / (2 * w);
      } else {
        yg = compThr + diff / compRatio;
      }
      final gc = yg - xg; // <= 0
      final coef = gc < compGrDb ? _coef(compAtk) : _coef(compRel);
      compGrDb = gc + (compGrDb - gc) * coef;

      final makeup = math.pow(10, compMakeupDb / 20).toDouble();
      final g = math.pow(10, compGrDb / 20).toDouble() * makeup;
      final wl = dl * g, wr = dr * g;
      l = dl + (wl - dl) * compWet;
      r = dr + (wr - dr) * compWet;
    } else if (compGrDb != 0) {
      // 꺼진 동안에도 상태를 0으로 되돌려 둔다 — 다시 켰을 때 갑자기 안 튀도록
      compGrDb += (0 - compGrDb) * _coef(compRel);
      if (compGrDb.abs() < 1e-4) compGrDb = 0;
    }
    return (l, r);
  }

  /// 스테레오 한 샘플을 처리한다. record 로 반환해 할당 없이 왕복한다(Dart 3).
  ///
  /// [sendL]/[sendR] — 4단계 4/N. 트랙 버스(TrackMix)의 리버브 send 합. 마스터의 [revWet]
  /// 과 **같은 탱크**를 나눠 쓴다. 탱크는 선형(LTI)이라 `H(a*x+b*y)=a*H(x)+b*H(y)` 가
  /// 성립하므로, `l*revWet + sendL` 을 한 번에 태워도 두 send 를 따로 태워 합친 것과
  /// 수학적으로 같다 — sendL/sendR 을 안 주면(기본값 0) 예전 수식과 완전히 같다.
  @pragma('vm:prefer-inline')
  (double, double) process(
    double l,
    double r, {
    double sendL = 0,
    double sendR = 0,
  }) {
    if (_dirty) _updateFilters();

    // EQ/컴프 순서 — 웹 `wireMasterOrder()` 그대로. 리버브는 항상 마지막(공간감)에 붙는다.
    if (eqFirst) {
      (l, r) = _processEq(l, r);
      (l, r) = _processComp(l, r);
    } else {
      (l, r) = _processComp(l, r);
      (l, r) = _processEq(l, r);
    }

    // 리버브는 켜져 있을 때만 돌린다(컴프와 같은 원칙) — 꺼진 기본값(웹과 같음)이고
    // 트랙 send 도 없으면 탱크가 아예 안 돌아서 비용도 0, 출력도 이전 단계와 완전히 같다.
    if (revWet > 0 || sendL != 0 || sendR != 0) {
      if (revKind != _lastRevKind) {
        _reverb.setKind(revKind);
        _lastRevKind = revKind;
      }
      final (rl, rr) = _reverb.process(l * revWet + sendL, r * revWet + sendR);
      l += rl;
      r += rr;
    }
    return (l, r);
  }
}

/// 4단계 4/N — 트랙(파트) 버스. `GENRE_MIX`(웹)를 걸 자리. 볼륨·팬·3밴드 EQ·HPF/LPF·
/// 마스터 리버브로 보내는 양을 갖는다. 마스터 버스(MasterBus)와 같은 원칙 —
/// **기본값은 전부 투명**해야 한다(vol=1·pan=0·eq=0dB·hpf=20·lpf=20000·rev=0).
/// 아무도 손대지 않으면 이전 단계(1~3단계·4단계 1~3/N) 소리가 그대로 나가야 한다.
class TrackMix {
  double vol = 1.0;
  double pan = 0.0; // -1(왼쪽)~1(오른쪽). 0=투명(그대로)
  double eqLoDb = 0, eqMidDb = 0, eqHiDb = 0;
  double hpfFreq = 20, lpfFreq = 20000;
  double rev = 0; // 0~1 — 마스터 리버브로 보내는 양 (MasterBus.process 의 sendL/sendR)

  /// 인서트 — **꽂은 순서대로** 통과한다 (5단계 45/N).
  /// 자리는 EQ 뒤, 팬·페이더 앞이다(로직의 채널 스트립과 같은 자리).
  /// 순서가 곧 소리다 — 컴프 뒤에 드라이브를 걸면 드라이브 뒤에 컴프를 건 것과
  /// 완전히 다른 소리가 난다. 그래서 목록을 그대로 쓴다(정렬하지 않는다).
  final List<Fx> inserts = [];

  /// ADSR 손잡이 — **신스 계열 악기만** 뜻이 있다(표본 악기는 표본 자체의
  /// 소리 모양이 있어 이 값을 안 본다, `synth.dart` `noteOn` 참고). null 이면
  /// 그 마디는 악기 기본값 그대로(사용자가 안 만졌다는 뜻).
  /// - [adsrAttack]/[adsrRelease]: 초 단위.
  /// - [adsrDecay]: 초 단위 — 피크에서 서스테인 레벨까지 내려가는 시간.
  /// - [adsrSustain]: 0~1 — 디케이 뒤 유지하는 레벨(피크 대비 비율).
  double? adsrAttack, adsrDecay, adsrSustain, adsrRelease;

  /// 유니즌 폭(cent) 손잡이 — ADSR과 같은 자리(신스 계열만). null 이면
  /// 악기 기본값(`Inst.uni`) 그대로. 사용자 요청, 2026-09-17.
  double? uniCents;

  /// ── 느린 필터 움직임 (엠비언트 패드용) ──
  /// 신스 패드는 소리가 시간에 따라 안 변하면 아무리 길게 끌어도 **그냥 비어 들린다**.
  /// 로우패스 컷오프를 아주 느리게(수십 초 주기) 열었다 닫으면 패드가 '숨을 쉰다'.
  /// [lfoHz] 0 이면 끔. [lfoDepth] 는 `lpfFreq` 대비 비율(0.45 = ±45%).
  /// `lpfFreq` 가 열려 있으면(20000) 움직여도 안 들리므로 GENRE_MIX 에서 같이 잡아 줘야 한다.
  double lfoHz = 0;
  double lfoDepth = 0;
  double _lfoPhase = 0;
  int _lfoTick = 0;

  /// 이 버스가 마지막으로 읽힌 뒤 낸 **제일 큰 값** — 미터가 읽고 비운다.
  ///
  /// 믹서에 페이더만 있고 「어느 트랙이 큰가」를 알려 주는 것이 없었다. 그러면
  /// 밸런스를 귀로만 잡아야 하는데, 폰 스피커로는 저음이 거의 안 들려서
  /// **베이스가 두 배로 커도 모른다.** 눈이 있으면 그건 바로 보인다.
  ///
  /// 재는 자리는 **팬·페이더까지 지난 뒤**다 — 실제로 나가는 크기가 그것이다.
  double peak = 0;

  /// 읽고 비운다. 안 비우면 한 번 커진 값이 영영 안 내려온다.
  double takePeak() {
    final v = peak;
    peak = 0;
    return v;
  }

  final Biquad _hpfL = Biquad(), _hpfR = Biquad();
  final Biquad _lpfL = Biquad(), _lpfR = Biquad();
  final Biquad _loL = Biquad(), _loR = Biquad();
  final Biquad _midL = Biquad(), _midR = Biquad();
  final Biquad _hiL = Biquad(), _hiR = Biquad();

  bool _dirty = true;
  double _lastHpf = -1, _lastLpf = -1;
  double _lastLo = double.nan, _lastMid = double.nan, _lastHi = double.nan;

  void markDirty() => _dirty = true;

  void _update() {
    if (hpfFreq != _lastHpf) {
      _hpfL.highpass(hpfFreq, 0.7);
      _hpfR.highpass(hpfFreq, 0.7);
      _lastHpf = hpfFreq;
    }
    if (lpfFreq != _lastLpf) {
      _lpfL.lowpass(lpfFreq, 0.7);
      _lpfR.lowpass(lpfFreq, 0.7);
      _lastLpf = lpfFreq;
    }
    // 저/중/고 중심 주파수 — 마스터 3밴드 근사(3단계 1/N)와 같은 값(150/1k/4kHz).
    if (eqLoDb != _lastLo) {
      _loL.lowShelf(150, eqLoDb);
      _loR.lowShelf(150, eqLoDb);
      _lastLo = eqLoDb;
    }
    if (eqMidDb != _lastMid) {
      _midL.peaking(1000, 0.8, eqMidDb);
      _midR.peaking(1000, 0.8, eqMidDb);
      _lastMid = eqMidDb;
    }
    if (eqHiDb != _lastHi) {
      _hiL.highShelf(4000, eqHiDb);
      _hiR.highShelf(4000, eqHiDb);
      _lastHi = eqHiDb;
    }
    _dirty = false;
  }

  @pragma('vm:prefer-inline')
  /// **레코드로 돌려준다** — 필드(outL/outR)로 바꿔 봤다가 되돌렸다.
  ///
  /// `Fx.step` 이 필드를 쓰길래 믹서도 같은 이유(샘플마다 객체 생성)로 느릴 줄 알고
  /// 바꿨는데, 재 보니 **오히려 3.5% 느렸다**(860ms → 890ms, 3회 반복).
  /// Dart 가 이 레코드는 이미 잘 풀어내고 있다. 추측으로 고치지 말 것 —
  /// `test/render_bench.dart` 로 재 보고 판단한다.
  (double, double) process(double l, double r) {
    if (_dirty) _update();
    // 컷오프를 64샘플(1.3ms)마다만 다시 잡는다 — 매 샘플 계수를 구하면 비싸고,
    // 이 정도로 느린 움직임에는 그 간격으로도 충분히 매끄럽다.
    if (lfoHz > 0 && lpfFreq < 19000 && (_lfoTick++ & 63) == 0) {
      _lfoPhase += lfoHz * 64 / kSampleRate;
      if (_lfoPhase >= 1) _lfoPhase -= 1;
      final c = (lpfFreq * (1 + lfoDepth * math.sin(2 * math.pi * _lfoPhase)))
          .clamp(120.0, 18000.0);
      _lpfL.lowpass(c, 0.7);
      _lpfR.lowpass(c, 0.7);
    }
    l = _hpfL.process(l);
    r = _hpfR.process(r);
    l = _lpfL.process(l);
    r = _lpfR.process(r);
    l = _loL.process(l);
    r = _loR.process(r);
    l = _midL.process(l);
    r = _midR.process(r);
    l = _hiL.process(l);
    r = _hiR.process(r);

    // 인서트 — 꽂은 순서대로. 꺼 둔 것은 건너뛴다.
    for (var i = 0; i < inserts.length; i++) {
      final fx = inserts[i];
      if (!fx.on) continue;
      fx.step(l, r);
      l = fx.outL;
      r = fx.outR;
    }

    // 팬 — 웹 StereoPannerNode 의 스테레오 입력 공식 그대로(스펙의 stereo-input 알고리즘).
    // pan=0 이면 항등(L/R 이 그대로 나간다) — 마스터와 달리 등파워가 아니라 채널을
    // 서로 크로스페이드하는 방식이라, 중앙일 때 -3dB 감쇠가 생기지 않는다.
    double ol, or_;
    if (pan <= 0) {
      ol = l + r * (-pan);
      or_ = r * (1 + pan);
    } else {
      ol = l * (1 - pan);
      or_ = r + l * pan;
    }
    ol *= vol;
    or_ *= vol;
    // 봉우리 — 샘플마다 비교 둘이라 렌더 시간에 거의 안 잡힌다(`render_bench` 로 확인).
    final a = ol < 0 ? -ol : ol;
    if (a > peak) peak = a;
    final b = or_ < 0 ? -or_ : or_;
    if (b > peak) peak = b;
    return (ol, or_);
  }
}

/// 드럼 + 멀로딕 트랙 버스 N개 묶음. Engine 이 하나씩 들고 있는다.
///
/// 4단계 4/N 까지는 멀로딕 버스가 bass/chord/melody 고정 3개였다(배열형 6곡이 딱
/// 그 구조라서). 4단계 5/N — **트랙 구조 일반화**: 객체형 롱폼(트랩 등)은 같은 타입
/// 트랙을 여러 개 둔다(예: 트랩은 패드·브라스가 둘 다 chord 타입인데 버스는 따로다).
/// 그래서 고정 필드 대신 **이름 있는 슬롯 목록**으로 바꿨다 — [configure] 로 곡을
/// 재생하기 직전에 그 곡의 슬롯 이름들을 세팅한다.
///
/// 드럼은 예외 — 모든 곡(배열형·객체형)이 드럼 타입 트랙을 정확히 하나만 두므로
/// 여기서는 계속 고정 버스 하나([drum])다. 일반화가 필요 없는 축은 안 건드렸다.
///
/// 기본값(슬롯 3개: bass/chord/melody)은 배열형 6곡이 지금까지 쓰던 것과 정확히
/// 같다 — [configure] 를 아무도 안 부르면 이전 단계와 동작이 같다.
class TrackMixSet {
  final TrackMix drum = TrackMix();

  /// 5단계 — 라이브(건반) 전용 버스. **[configure] 가 안 건드린다** — 곡을 틀어
  /// 트랙 편성이 통째로 바뀌어도 내가 손으로 맞춰 둔 건반 볼륨은 그대로 남아야 한다.
  /// `resetGenreMix()` 도 여기는 안 만진다(슬롯+드럼만 돈다).
  final TrackMix live = TrackMix();

  List<String> slotNames = const ['bass', 'chord', 'melody'];
  List<TrackMix> slots = [TrackMix(), TrackMix(), TrackMix()];

  // 하위호환 — 배열형 6곡이 쓰는 기본 슬롯 이름으로 바로 접근. [configure] 로 다른
  // 편성으로 바꾼 뒤에는 의미가 없어지므로(인덱스가 안 맞을 수 있다), 배열형 재생
  // 직전에는 항상 `configure(['bass','chord','melody'])` 로 되돌려 놓고 쓸 것.
  TrackMix get bass => slots[0];
  TrackMix get chord => slots[1];
  TrackMix get melody => slots[2];

  int indexOf(String slot) => slotNames.indexOf(slot);
  TrackMix? bus(String slot) {
    final i = slotNames.indexOf(slot);
    return i < 0 ? null : slots[i];
  }

  /// 트랙 편성을 바꾼다 — 곡을 재생하기 직전에 한 번 호출한다. 이미 같은 이름·순서면
  /// 아무것도 안 한다(값이 살아 있는 트랙 버스를 괜히 새로 만들지 않는다). 이름이
  /// 바뀌면 버스 전부 새 [TrackMix]() 로(투명 기본값) 다시 만든다 — 이전 곡의 vol/pan/
  /// EQ 가 새 편성에 남아 있으면 안 되므로, 값은 항상 그 뒤 GENRE_MIX 적용이 채운다.
  void configure(List<String> names) {
    if (names.length == slotNames.length) {
      var same = true;
      for (var i = 0; i < names.length; i++) {
        if (names[i] != slotNames[i]) {
          same = false;
          break;
        }
      }
      if (same) return;
    }
    slotNames = List.unmodifiable(names);
    slots = List.generate(names.length, (_) => TrackMix());
  }
}

/// 마스터 리버브 — Schroeder 구조(콤필터 4개 병렬 + 올패스 2개 직렬).
///
/// 웹은 `ConvolverNode` + 잡음 임펄스(REV_KINDS, makeRevImpulse)를 썼다. 브라우저의
/// 컨볼버는 OS/하드웨어가 FFT 컨벌루션으로 최적화해 주지만, Dart 로 그대로 옮기면
/// 순진한 시간영역 컨벌루션이 된다 — 임펄스 길이 2.6초(홀) = 샘플당 12만 번 곱셈이라
/// 실시간이 불가능하다(HANDOFF 3단계에 적어 둔 대로).
///
/// **이건 웹에서 옮긴 게 아니라 새로 설계한 것이다** — 컴프레서(마스터 버스 1/N)와
/// 같은 이유·같은 원칙. 다만 `dur`(감쇠시간)·`pre`(프리딜레이)·`tone`(밝기)는 웹
/// `REV_KINDS` 값을 그대로 재사용해 세 종류(홀/플레이트/룸)의 캐릭터를 맞췄다.
/// (`decay`·`er`(초기반사) 는 잡음 임펄스 전용 파라미터라 콤/올패스 구조엔 대응이 없다)
class ReverbKind {
  final double dur; // RT60 성격의 감쇠 시간(초) — 웹 REV_KINDS[k].dur 그대로
  final double preSec; // 프리딜레이(초) — 웹 REV_KINDS[k].pre 그대로
  final double toneHz; // 밝기 — 웹 REV_KINDS[k].tone 그대로. 낮을수록 어둡게(댐핑 큼)
  const ReverbKind(this.dur, this.preSec, this.toneHz);
}

const Map<String, ReverbKind> kReverbKinds = {
  'hall': ReverbKind(2.6, 0.028, 5200),
  'plate': ReverbKind(1.7, 0.006, 8600),
  'room': ReverbKind(0.85, 0.004, 4200),
};

// 콤/올패스 지연 길이(ms) — 서로 정수배가 아니게 흩어 놓아야 공진(콤 특유의 '삐-' 소리)이
// 덜 생긴다. R 채널은 살짝(0.53ms) 어긋나게 둬서 스테레오 폭을 만든다(프리버브류의 표준 수법).
const List<double> _kCombMsL = [29.7, 37.1, 41.1, 43.7];
const List<double> _kCombMsR = [30.2, 37.6, 41.7, 44.2];
const List<double> _kApMsL = [12.9, 10.0];
const List<double> _kApMsR = [13.4, 10.5];
const double _kMaxPreSec = 0.08; // 웹 REV_KINDS 중 가장 긴 pre(0.028)보다 여유 있게

class _Comb {
  final Float32List buf;
  int idx = 0;
  double fb = 0.5, damp = 0.2;
  double _lp = 0;
  _Comb(int size) : buf = Float32List(size);

  @pragma('vm:prefer-inline')
  double process(double x) {
    final y = buf[idx];
    _lp = y * (1 - damp) + _lp * damp; // 피드백 경로의 원폴 로우패스 — 고음이 먼저 죽는다
    buf[idx] = x + _lp * fb;
    idx++;
    if (idx >= buf.length) idx = 0;
    return y;
  }
}

class _Allpass {
  final Float32List buf;
  int idx = 0;
  static const double fb = 0.5;
  _Allpass(int size) : buf = Float32List(size);

  @pragma('vm:prefer-inline')
  double process(double x) {
    final bufOut = buf[idx];
    final y = bufOut - x;
    buf[idx] = x + bufOut * fb;
    idx++;
    if (idx >= buf.length) idx = 0;
    return y;
  }
}

/// 가변 길이 프리딜레이 — 종류가 바뀌면 delaySamples 만 바뀌고 버퍼는 그대로다
/// (재할당 없이 링 버퍼 안에서 읽는 위치만 옮긴다).
class _PreDelay {
  final Float32List buf;
  int _w = 0;
  int delaySamples = 0;
  _PreDelay(int maxSamples) : buf = Float32List(maxSamples);

  @pragma('vm:prefer-inline')
  double process(double x) {
    final size = buf.length;
    var r = _w - delaySamples;
    if (r < 0) r += size;
    final y = buf[r];
    buf[_w] = x;
    _w++;
    if (_w >= size) _w = 0;
    return y;
  }
}

class MasterReverb {
  late final List<_Comb> _combL, _combR;
  late final List<_Allpass> _apL, _apR;
  final _PreDelay _preL, _preR;

  MasterReverb()
    : _preL = _PreDelay((_kMaxPreSec * kSampleRate).round()),
      _preR = _PreDelay((_kMaxPreSec * kSampleRate).round()) {
    _combL = _kCombMsL
        .map((ms) => _Comb((ms / 1000 * kSampleRate).round()))
        .toList();
    _combR = _kCombMsR
        .map((ms) => _Comb((ms / 1000 * kSampleRate).round()))
        .toList();
    _apL = _kApMsL
        .map((ms) => _Allpass((ms / 1000 * kSampleRate).round()))
        .toList();
    _apR = _kApMsR
        .map((ms) => _Allpass((ms / 1000 * kSampleRate).round()))
        .toList();
    setKind('hall');
  }

  void setKind(String kind) {
    final k = kReverbKinds[kind] ?? kReverbKinds['hall']!;
    final damp = 1 - (k.toneHz / 12000).clamp(0.05, 0.95);
    for (final c in [..._combL, ..._combR]) {
      final sec = c.buf.length / kSampleRate;
      c.fb = math.pow(10, -3 * sec / k.dur).toDouble().clamp(0.0, 0.98);
      c.damp = damp;
    }
    final pre = (k.preSec * kSampleRate).round().clamp(0, _preL.buf.length - 1);
    _preL.delaySamples = pre;
    _preR.delaySamples = pre;
  }

  // 콤 4개 합의 레벨을 대략 1로 되돌리는 상수(경험적) — 정확한 유니티 게인이 목적이 아니라
  // 젖음 양(wet) 슬라이더가 예측 가능한 범위에서 움직이게 하는 것이 목적이다.
  static const double _outScale = 0.5;

  @pragma('vm:prefer-inline')
  (double, double) process(double l, double r) {
    final mono = (l + r) * 0.5;
    final pl = _preL.process(mono);
    final pr = _preR.process(mono);

    var sl = 0.0, sr = 0.0;
    for (final c in _combL) {
      sl += c.process(pl);
    }
    for (final c in _combR) {
      sr += c.process(pr);
    }
    for (final a in _apL) {
      sl = a.process(sl);
    }
    for (final a in _apR) {
      sr = a.process(sr);
    }
    return (sl * _outScale, sr * _outScale);
  }
}
