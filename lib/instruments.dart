// 악기 표 — 웹 버전(assets/app.html)에서 **검증이 끝난 값들을 그대로** 옮긴 것이다.
// 값을 바꾸면 소리가 달라진다. 왜 그 값인지는 웹 쪽 HANDOFF.md 6-A~6-L 에 있다.
//
// 표 이름을 웹과 똑같이(HARM, ADDITIVE …) 두는 것은 의도적이다.
// 두 코드를 나란히 놓고 대조할 일이 계속 생기므로, 이름이 다르면 그때마다 손해다.
// ignore_for_file: constant_identifier_names

import 'package:flutter/material.dart' show IconData, Icons;

import 'dsp.dart';
import 'sampler.dart' show kSampleInstrumentKeys;

/// hold(음을 붙들고 있는 시간) 를 정하는 방식
enum HoldKind {
  /// max(a, 음길이 - b)
  maxSub,

  /// min(a, 음길이)  — stab 만 쓴다
  minCap,

  /// 고정 a 초 — 치는·뜯는 악기 (뒤의 울림은 RING 이 정한다)
  fixed,
}

class Inst {
  final String wave;
  final double cut, peak, rel;
  final HoldKind holdKind;
  final double holdA, holdB;

  /// detune: 배음으로 얹는 오실레이터(cent), sub: 옥타브 아래, uni: 유니즌 폭(cent),
  /// q: 로우패스 레조넌스(dB — Web Audio 방식)
  final double detune, uni, q;
  final bool sub;

  const Inst({
    required this.wave,
    required this.cut,
    required this.peak,
    required this.rel,
    this.holdKind = HoldKind.maxSub,
    this.holdA = 0.05,
    this.holdB = 0.12,
    this.detune = 0,
    this.uni = 0,
    this.q = 0,
    this.sub = false,
  });

  double holdFor(double dur) {
    switch (holdKind) {
      case HoldKind.maxSub:
        final v = dur - holdB;
        return v > holdA ? v : holdA;
      case HoldKind.minCap:
        return dur < holdA ? dur : holdA;
      case HoldKind.fixed:
        return holdA;
    }
  }
}

const Inst kInstDefault = Inst(
  wave: 'triangle',
  cut: 3000,
  peak: 0.5,
  rel: 0.3,
);

const Map<String, Inst> INSTRUMENTS = {
  // ── 신스 기본 ──
  'bass': Inst(wave: 'sawtooth', cut: 560, peak: 0.8, rel: 0.18, holdB: 0.1),
  'pad': Inst(
    wave: 'triangle',
    cut: 1800,
    peak: 0.34,
    rel: 0.55,
    holdA: 0.08,
    holdB: 0.05,
    uni: 9,
    detune: 1200,
  ),
  'stab': Inst(
    wave: 'sawtooth',
    cut: 2400,
    peak: 0.32,
    rel: 0.16,
    holdKind: HoldKind.minCap,
    holdA: 0.09,
  ),
  'pluck': Inst(wave: 'triangle', cut: 3200, peak: 0.44, rel: 0.35),
  'lead': Inst(wave: 'square', cut: 2200, peak: 0.23, rel: 0.22),
  'organ': Inst(
    wave: 'sine',
    cut: 3400,
    peak: 0.3,
    rel: 0.14,
    holdA: 0.06,
    holdB: 0.04,
    sub: true,
    detune: 1200,
  ),
  'bell': Inst(
    wave: 'sine',
    cut: 5200,
    peak: 0.42,
    rel: 0.5,
    holdKind: HoldKind.fixed,
    holdA: 0.02,
    detune: 1902,
  ),
  'brass': Inst(
    wave: 'sawtooth',
    cut: 1500,
    peak: 0.34,
    rel: 0.2,
    holdA: 0.06,
    holdB: 0.06,
    uni: 8,
  ),
  'guitar': Inst(
    wave: 'triangle',
    cut: 2600,
    peak: 0.5,
    rel: 0.4,
    holdKind: HoldKind.fixed,
    holdA: 0.03,
    detune: 1902,
    uni: 5,
  ),
  'flute': Inst(
    wave: 'sine',
    cut: 2800,
    peak: 0.32,
    rel: 0.22,
    holdA: 0.08,
    holdB: 0.05,
  ),
  'chip': Inst(
    wave: 'square',
    cut: 4200,
    peak: 0.24,
    rel: 0.12,
    holdA: 0.03,
    holdB: 0.05,
  ),
  'marimba': Inst(
    wave: 'sine',
    cut: 4000,
    peak: 0.5,
    rel: 0.22,
    holdKind: HoldKind.fixed,
    holdA: 0.015,
    detune: 2400,
  ),
  'strings': Inst(
    wave: 'sawtooth',
    cut: 2000,
    peak: 0.26,
    rel: 0.5,
    holdA: 0.1,
    holdB: 0.02,
    uni: 11,
  ),
  'saw': Inst(wave: 'sawtooth', cut: 2800, peak: 0.26, rel: 0.24, detune: -9),
  'sine': Inst(wave: 'sine', cut: 5000, peak: 0.5, rel: 0.28, holdB: 0.1),
  'harp': Inst(
    wave: 'triangle',
    cut: 4200,
    peak: 0.46,
    rel: 0.5,
    holdKind: HoldKind.fixed,
    holdA: 0.02,
    detune: 1200,
  ),
  'wobble': Inst(
    wave: 'sawtooth',
    cut: 420,
    peak: 0.7,
    rel: 0.2,
    holdB: 0.08,
    detune: -1200,
  ),
  'piano': Inst(
    wave: 'triangle',
    cut: 3800,
    peak: 0.52,
    rel: 0.34,
    holdKind: HoldKind.fixed,
    holdA: 0.02,
    detune: 1200,
    uni: 6,
  ),
  'epiano': Inst(
    wave: 'sine',
    cut: 2600,
    peak: 0.44,
    rel: 0.42,
    holdKind: HoldKind.fixed,
    holdA: 0.03,
    detune: 1204,
    sub: true,
    uni: 4,
  ),
  'fingerbass': Inst(
    wave: 'triangle',
    cut: 700,
    peak: 0.78,
    rel: 0.16,
    holdA: 0.04,
    holdB: 0.08,
    uni: 5,
  ),

  // ── 빈티지 아날로그 신스 ──
  'moogbass': Inst(
    wave: 'sawtooth',
    cut: 480,
    peak: 0.85,
    rel: 0.2,
    holdB: 0.08,
    sub: true,
    q: 4.5,
  ),
  'moogleadv': Inst(
    wave: 'sawtooth',
    cut: 2400,
    peak: 0.3,
    rel: 0.26,
    holdB: 0.06,
    uni: 7,
    q: 3.2,
  ),
  'jpstrings': Inst(
    wave: 'sawtooth',
    cut: 2200,
    peak: 0.24,
    rel: 0.62,
    holdA: 0.12,
    holdB: 0,
    uni: 14,
  ),
  'vintorgan': Inst(
    wave: 'sine',
    cut: 3600,
    peak: 0.3,
    rel: 0.1,
    holdA: 0.06,
    holdB: 0.03,
    sub: true,
    detune: 1902,
  ),
  'analogbrass': Inst(
    wave: 'sawtooth',
    cut: 1700,
    peak: 0.32,
    rel: 0.24,
    holdA: 0.07,
    holdB: 0.05,
    uni: 9,
    q: 2.4,
  ),
  'analogpad': Inst(
    wave: 'sawtooth',
    cut: 1500,
    peak: 0.26,
    rel: 0.75,
    holdA: 0.12,
    holdB: 0,
    uni: 16,
  ),

  // ── 어쿠스틱 근사 ──
  'sax': Inst(
    wave: 'sawtooth',
    cut: 2100,
    peak: 0.3,
    rel: 0.2,
    holdA: 0.07,
    holdB: 0.05,
    uni: 4,
    q: 3.6,
  ),
  'trumpet': Inst(
    wave: 'square',
    cut: 2600,
    peak: 0.28,
    rel: 0.16,
    holdA: 0.06,
    holdB: 0.05,
    uni: 3,
    q: 2.8,
  ),
  'clarinet': Inst(
    wave: 'square',
    cut: 1700,
    peak: 0.3,
    rel: 0.18,
    holdA: 0.07,
    holdB: 0.04,
  ),
  'violin': Inst(
    wave: 'sawtooth',
    cut: 2600,
    peak: 0.24,
    rel: 0.3,
    holdA: 0.1,
    holdB: 0.02,
    uni: 8,
  ),
  'cello': Inst(
    wave: 'sawtooth',
    cut: 1200,
    peak: 0.3,
    rel: 0.35,
    holdA: 0.1,
    holdB: 0.02,
    uni: 7,
  ),
  'nylon': Inst(
    wave: 'triangle',
    cut: 2800,
    peak: 0.5,
    rel: 0.45,
    holdKind: HoldKind.fixed,
    holdA: 0.02,
    detune: 1902,
    uni: 4,
  ),
  'upright': Inst(
    wave: 'triangle',
    cut: 620,
    peak: 0.8,
    rel: 0.22,
    holdKind: HoldKind.fixed,
    holdA: 0.03,
    uni: 3,
  ),

  // ── 목소리 ──
  // **이 표에만 없었다.** SUSLV·ATK·KEYTRACK·SPACE·VOICE_LABEL·ALL_VOICES·
  // kVoiceFamily 일곱 표에는 다 있는데 정작 음색을 정하는 여기가 비어 있어서,
  // 팝·R&B·가스펠의 주선율이 `kInstDefault`(맹숭한 삼각파)로 울고 있었다.
  // 짝수 배음이 −118dB — 삼각파의 지문이다. 사람 목소리는 배음이 다 있다.
  // 컷오프는 포먼트(700·1220Hz)를 지나가게 열어 둔다 — 로우패스가 공명보다 앞이다.
  // 유니즌은 **일부러 0** 이다. 4cent 만 줘도 배음이 서로 맥놀이를 일으켜
  // 3배음이 20dB 씩 파인다(재 봤다: uni 4 → `-13 -30`, uni 0 → `-1 0`).
  // 혼자 부르는 목소리에 코러스가 걸려 있으면 그 순간 신스로 들린다.
  // 흔들림은 Human(사람 흉내)과 비브라토가 이미 만든다.
  'vocal': Inst(
    wave: 'sawtooth',
    cut: 2900,
    peak: 0.30,
    rel: 0.30,
    holdA: 0.06,
    holdB: 0.05,
  ),
};

/// 서스테인 레벨 — 어택 피크에서 이만큼까지 내려앉는다.
/// 활·입김으로 계속 소리를 넣는 악기(현·관·오르간)는 높고,
/// 튕기거나 때리는 악기(피아노·기타)는 아래 RING 이 따로 처리하므로 여기서 뺀다.
const Map<String, double> SUSLV = {
  'pad': 0.80,
  'analogpad': 0.78,
  'strings': 0.76,
  'jpstrings': 0.78,
  'brass': 0.70,
  'analogbrass': 0.70,
  'organ': 0.92,
  'vintorgan': 0.92,
  'sine': 0.86,
  'flute': 0.80,
  'clarinet': 0.82,
  'sax': 0.72,
  'trumpet': 0.70,
  'violin': 0.78,
  'cello': 0.78,
  'lead': 0.80,
  'saw': 0.80,
  'moogleadv': 0.78,
  'bass': 0.76,
  'fingerbass': 0.60,
  'moogbass': 0.72,
  'wobble': 0.86,
  'chip': 0.90,
  'stab': 0.58,
  'vocal': 0.82,
};

/// 울림 길이 — 치는·뜯는 악기는 '음표 길이만큼' 울려야 한다.
/// [기본 릴리즈, 최대 울림, 음표길이 대비 비율]
/// 비율 1.00 = 편집기에서 그린 길이만큼 그대로 울린다.
const Map<String, List<double>> RING = {
  'piano': [0.34, 5.0, 1.00],
  'epiano': [0.42, 4.0, 1.00],
  'guitar': [0.40, 3.5, 1.00],
  'nylon': [0.45, 3.0, 1.00],
  'harp': [0.50, 4.5, 1.00],
  'bell': [0.50, 6.0, 1.15],
  'marimba': [0.22, 2.0, 0.85],
  'upright': [0.22, 3.0, 1.00],
  'pluck': [0.35, 3.0, 1.00],
};

/// 이 음색이 **ADSR 손잡이**를 보여 줄 대상인가(사용자 요청, 2026-09-15:
/// "악기들 ADSR 필요한 악기들은 악기 설정에 넣어 놓자").
///
/// 표본 악기는 표본 자체의 소리 모양이 있어 대상이 아니고(`noteOn` 이
/// `buildAdsr` 를 아예 안 탄다), [RING] 에 있는 뜯는/치는 계열도 대상이
/// 아니다(그쪽은 buildRing — 어택 뒤 자연히 사그라드는 소리라 "서스테인
/// 레벨"이라는 개념 자체가 안 맞는다). 나머지 합성 음색만 대상이다.
/// **알려진 신스 음색인가부터 본다** — 드럼 트랙의 `voice` 는 킷 이름
/// ('로파이'·'808' 등)이라 표본·RING 어느 쪽에도 안 걸려서, 그것만 보면
/// 드럼 트랙에도 ADSR 이 뜨는 사고가 난다(실기기 시험으로 확인, 2026-09-15
/// — 트랙 지우기 시험이 「트랙 삭제」 버튼을 화면 밖으로 밀어냈다).
bool hasAdsr(String voice) =>
    INSTRUMENTS.containsKey(voice) &&
    !kSampleInstrumentKeys.contains(voice) &&
    !RING.containsKey(voice);

/// 어택 — **소리가 서는 데 걸리는 시간**(초)과 세기 민감도. (5단계 48/N)
///
/// 여태 모든 악기가 5ms 였다. 그게 "다 신스 같다"의 가장 큰 원인이다 —
/// 실제로 활을 긋는 바이올린은 소리가 서는 데 50ms 넘게 걸리고,
/// 피크로 긁는 기타는 2ms 도 안 걸린다. 그 차이가 악기를 구별하게 만든다.
///
/// [보통 세기 어택초, 세기 민감도]
/// 민감도 0.6 = 세게 치면 2^-0.6 배(0.66배) 빨라지고 여리게 치면 1.5배 늘어진다.
/// 실제 악기가 그렇다 — 해머·피크가 세게 밀수록 현이 더 빨리 튄다.
const Map<String, List<double>> ATK = {
  // ── 건반 ──
  'piano': [0.004, 0.6], // 해머가 현을 때린다
  'epiano': [0.006, 0.55], // 해머가 금속 타인을 때린다 — 조금 무르다
  'organ': [0.012, 0.08], // 바람은 세기와 상관없이 일정하게 찬다
  'vintorgan': [0.010, 0.08],
  // ── 뜯고 치는 ──
  'guitar': [0.0018, 0.5], // 피크 — 제일 빠르다
  'nylon': [0.005, 0.4], // 손가락 살이 닿아 피크보다 느리다
  'harp': [0.004, 0.35], 'pluck': [0.002, 0.4],
  'marimba': [0.0015, 0.45], 'bell': [0.0012, 0.35],
  // ── 베이스 ── 손가락으로 뜯으니 기타 피크보다 확연히 느리다
  'upright': [0.011, 0.5], 'fingerbass': [0.009, 0.5],
  'bass': [0.006, 0.35], 'moogbass': [0.005, 0.3],
  // ── 활·입김 ── 여기가 신스 티가 제일 많이 나던 자리
  'violin': [0.055, 0.5], 'cello': [0.070, 0.5],
  'strings': [0.090, 0.4], 'jpstrings': [0.080, 0.35],
  'sax': [0.030, 0.55], 'trumpet': [0.022, 0.6], 'clarinet': [0.028, 0.5],
  'flute': [0.045, 0.45], 'brass': [0.028, 0.6], 'analogbrass': [0.024, 0.5],
  // ── 신스 ── 원래 신스인 것들은 건드릴 이유가 없다
  'pad': [0.10, 0.2], 'analogpad': [0.13, 0.2],
  'lead': [0.006, 0.3], 'moogleadv': [0.006, 0.3], 'saw': [0.006, 0.3],
  'stab': [0.003, 0.3], 'chip': [0.001, 0], 'sine': [0.008, 0.2],
  'wobble': [0.010, 0.2], 'vocal': [0.040, 0.3],
};
const List<double> ATK_DEF = [0.005, 0.3];

/// 음정에 따른 울림 길이 — **높은 음일수록 빨리 죽는다.** (5단계 48/N)
///
/// 피아노 제일 낮은 음은 20초 넘게 울리는데 제일 높은 음은 1초도 안 간다.
/// 현이 짧고 얇을수록 에너지를 빨리 잃기 때문이다. 여태는 음높이와 상관없이
/// 똑같이 울려서, 높은 음을 치면 실제 피아노보다 훨씬 길게 늘어졌다.
///
/// 값 = 지수. 가온다(261.63Hz) 기준으로 `(261.63/주파수)^값` 배 울린다.
/// 0.62 면 한 옥타브 내려갈 때 1.54배 길어진다.
const Map<String, double> RINGKEY = {
  'piano': 0.62,
  'epiano': 0.42,
  'guitar': 0.55,
  'nylon': 0.50,
  'upright': 0.55,
  'harp': 0.60,
  'marimba': 0.70,
  'bell': 0.45,
  'pluck': 0.45,
};

/// 뜯는·치는 악기 — 어택 순간 밝았다가 닫힌다
const Map<String, bool> PLUCKY = {
  'piano': true,
  'epiano': true,
  'guitar': true,
  'pluck': true,
  'marimba': true,
  'harp': true,
  'bell': true,
  'stab': true,
  'chip': true,
};

/// 악기 고유 배음 구조. 기본 파형 3종만 돌려쓰면 무엇을 쳐도 '신스 소리'가 난다.
/// 숫자 = 1배음부터의 상대 세기 (클라리넷이 홀수 배음만 있는 게 대표적인 예)
const Map<String, List<double>> HARM = {
  'clarinet': [1, 0, .55, 0, .28, 0, .14, 0, .07],
  'sax': [1, .68, .45, .5, .28, .2, .14, .1, .06],
  'trumpet': [.6, .85, 1, .8, .55, .35, .22, .14, .08],
  'brass': [.7, .9, 1, .72, .5, .32, .2, .12],
  'analogbrass': [.75, .95, 1, .7, .45, .28, .16, .1],
  'flute': [1, .18, .08, .04, .02],
  'violin': [1, .78, .55, .42, .32, .24, .18, .13, .09, .06],
  'cello': [1, .85, .5, .38, .25, .18, .12, .08],
  'strings': [1, .7, .5, .36, .26, .18, .12, .08, .05],
  'jpstrings': [1, .72, .52, .34, .24, .16, .1, .07],
  'organ': [1, .55, .75, .35, .5, .2, .3, .15, .25],
  'vintorgan': [1, .6, .8, .3, .55, .18, .28],
  // 성대(글로탈) 파형 — 배음이 **빠짐없이** 있고 고르게 줄어든다.
  'vocal': [1, .70, .50, .35, .25, .18, .13, .09, .065, .045, .03, .02],
};

/// 배음별 독립 감쇠 (가산 합성)
/// 실제로 치는·뜯는 악기는 '높은 배음이 먼저 죽는다'. 로우패스로는 흉내만 낼 뿐이다.
/// [배음비, 세기, 감쇠배율] — 감쇠배율이 작을수록 빨리 사라진다.
const Map<String, List<List<double>>> ADDITIVE = {
  'piano': [
    [1, 1, 1],
    [2.002, .5, .62],
    [3.006, .3, .42],
    [4.012, .17, .3],
    [5.02, .1, .22],
    [6.03, .06, .16],
  ],
  'epiano': [
    [1, 1, 1],
    [2, .22, .6],
    [4.01, .34, .34],
    [6.02, .12, .22],
    [9.04, .05, .14],
  ],
  'guitar': [
    [1, 1, 1],
    [2, .55, .66],
    [3, .36, .5],
    [4, .24, .38],
    [5, .16, .28],
    [6, .1, .2],
  ],
  'nylon': [
    [1, 1, 1],
    [2, .38, .6],
    [3, .2, .42],
    [4, .11, .3],
    [5, .06, .2],
  ],
  'upright': [
    [1, 1, 1],
    [2, .5, .58],
    [3, .22, .4],
    [4, .11, .28],
  ],
  'harp': [
    [1, 1, 1],
    [2, .45, .62],
    [3, .28, .44],
    [4, .16, .32],
    [5, .09, .22],
  ],
  'marimba': [
    [1, 1, 1],
    [3.9, .42, .34],
    [9.2, .12, .18],
    [2, .08, .5],
  ],
  'bell': [
    [1, 1, 1],
    [2.76, .6, .8],
    [5.4, .3, .55],
    [8.2, .14, .35],
    [1.5, .1, .7],
  ],
  'pluck': [
    [1, 1, 1],
    [2, .4, .55],
    [3, .22, .38],
    [4, .12, .26],
  ],
};

/// 몸통 공명 — 어쿠스틱 악기는 음정이 바뀌어도 움직이지 않는 고정 공명이 있다.
/// [주파수, Q, 세기dB] — 최대 2개까지만 써서 비용을 묶어 둔다.
const Map<String, List<List<double>>> BODY_RES = {
  'guitar': [
    [102, 1.2, 6],
    [212, 1.6, 5],
  ],
  'nylon': [
    [95, 1.3, 5],
    [186, 1.5, 4],
  ],
  'upright': [
    [62, 1.2, 7],
    [124, 1.4, 4],
  ],
  'violin': [
    [285, 1.4, 5],
    [465, 1.6, 4],
  ],
  'cello': [
    [108, 1.3, 6],
    [205, 1.5, 4],
  ],
  'piano': [
    [132, 1.1, 3],
    [505, 0.9, 2],
  ],
  'sax': [
    [520, 1.3, 5],
    [1250, 1.2, 4],
  ],
  'trumpet': [
    [920, 1.4, 5],
    [1850, 1.2, 3],
  ],
  'flute': [
    [810, 1.1, 3],
  ],
  'clarinet': [
    [1500, 1.0, 3],
  ],
  'marimba': [
    [225, 1.4, 4],
  ],
  'harp': [
    [184, 1.3, 4],
  ],
  // 목소리의 **포먼트**. 몸통 공명과 원리가 같아 이 표를 그대로 쓴다 —
  // 음정이 올라가도 안 움직이는 고정 공명이라는 점이 핵심이다.
  // 700·1220Hz 는 「아」에 가깝다. 낮은 쪽을 앞에 두는 이유: 저사양에서 하나만
  // 쓰는데, 목소리라고 알아듣게 하는 힘은 F1 쪽이 세다.
  'vocal': [
    [700, 1.6, 7],
    [1220, 1.5, 5],
  ],
};

/// 필터 키 트래킹 — 컷오프가 고정이면 낮은 음은 먹먹하고 높은 음은 얇다.
const Map<String, double> KEYTRACK = {
  'piano': .55,
  'epiano': .5,
  'guitar': .55,
  'nylon': .5,
  'upright': .45,
  'harp': .5,
  'marimba': .5,
  'bell': .45,
  'violin': .6,
  'cello': .55,
  'strings': .5,
  'jpstrings': .5,
  'sax': .6,
  'trumpet': .6,
  'clarinet': .55,
  'flute': .55,
  'brass': .55,
  'analogbrass': .5,
  'organ': .4,
  'vintorgan': .4,
  'vocal': .4,
};
const double KT_DEF = .3;

/// 공간 — pan: 좌우 위치, rev: 리버브 보냄, w: 유니즌을 벌리는 폭
class Space {
  final double pan, rev, w;
  const Space(this.pan, this.rev, this.w);
}

const Map<String, Space> SPACE = {
  'drum': Space(0, 0.044, 0),
  'bass': Space(0, 0.022, 0.08),
  'fingerbass': Space(0, 0.028, 0.10),
  'moogbass': Space(0, 0.017, 0.06),
  'upright': Space(-0.05, 0.088, 0.12),
  'piano': Space(-0.10, 0.11, 0.42),
  'epiano': Space(0.10, 0.132, 0.36),
  'organ': Space(-0.14, 0.099, 0.30),
  'vintorgan': Space(0.14, 0.11, 0.34),
  'pad': Space(0, 0.187, 0.72),
  'analogpad': Space(0, 0.209, 0.80),
  'stab': Space(0.18, 0.088, 0.28),
  'strings': Space(-0.18, 0.198, 0.66),
  'jpstrings': Space(0.16, 0.209, 0.74),
  'violin': Space(-0.24, 0.176, 0.34),
  'cello': Space(0.20, 0.165, 0.30),
  'brass': Space(0.16, 0.121, 0.34),
  'analogbrass': Space(-0.16, 0.132, 0.38),
  'sax': Space(0.22, 0.143, 0.22),
  'trumpet': Space(-0.22, 0.132, 0.20),
  'clarinet': Space(0.18, 0.132, 0.18),
  'flute': Space(-0.18, 0.154, 0.16),
  'guitar': Space(0.22, 0.11, 0.34),
  'nylon': Space(-0.22, 0.132, 0.30),
  'pluck': Space(0.16, 0.11, 0.24),
  'harp': Space(-0.20, 0.165, 0.40),
  'bell': Space(0.24, 0.187, 0.30),
  'marimba': Space(-0.16, 0.121, 0.26),
  'lead': Space(0, 0.088, 0.20),
  'moogleadv': Space(0.08, 0.099, 0.28),
  'saw': Space(0, 0.099, 0.24),
  'chip': Space(0, 0.055, 0.14),
  'sine': Space(0, 0.11, 0),
  'wobble': Space(0, 0.066, 0.16),
  'vocal': Space(0, 0.165, 0.18),
};
const Space SPACE_DEF = Space(0, 0.10, 0.24);
Space spaceOf(String v) => SPACE[v] ?? SPACE_DEF;

/// 관악기·현악기는 어택에서 음이 살짝 아래에서 붙어 올라온다
const Map<String, double> BEND = {
  'brass': 0.020, 'analogbrass': 0.022, 'trumpet': 0.026, 'sax': 0.018,
  'clarinet': 0.012, 'violin': 0.010, 'cello': 0.010, 'flute': 0.008,
  'vocal': 0.014, // 스쿱 — 가수가 음 아래에서 끌어올려 붙는 그것
};

/// 느리게 걸리는 비브라토 (사람 연주 특징) [속도Hz, 깊이(비율), 걸리기까지 초]
const Map<String, List<double>> VIB = {
  'violin': [5.6, 0.010, 0.22],
  'cello': [5.0, 0.009, 0.26],
  'sax': [5.2, 0.008, 0.20],
  'flute': [5.4, 0.007, 0.24],
  'trumpet': [5.5, 0.006, 0.26],
  'clarinet': [5.0, 0.005, 0.26],
  'strings': [5.2, 0.006, 0.30],
  'jpstrings': [4.8, 0.005, 0.34],
  'vocal': [5.4, 0.011, 0.30],
};

/// 폰 스피커가 못 내는 저음을 위해 한 옥타브 위를 겹쳐 주는 악기들
const Map<String, bool> BASS_VOICE = {
  'bass': true,
  'fingerbass': true,
  'moogbass': true,
  'upright': true,
  'sine': true,
  'wobble': true,
};

/// 세기 1·2·3 → 음량
const Map<int, double> VG = {1: 0.30, 2: 0.60, 3: 1.0};

// 배음 구조가 있는 악기는 그 구조로 만든 웨이브테이블을 쓴다.
final Map<String, WaveSet> _harmWaves = {};
WaveSet waveFor(String voice, String basic) {
  final h = HARM[voice];
  if (h == null) return waveByName(basic);
  return _harmWaves.putIfAbsent(voice, () {
    return WaveSet.fromHarmonics(
      (n) => n <= h.length ? h[n - 1].toDouble() : 0.0,
      h.length,
    );
  });
}

/// 화면에 보여줄 이름
const Map<String, String> VOICE_LABEL = {
  'piano': '피아노', 'epiano': '일렉 피아노', 'guitar': '기타', 'nylon': '나일론 기타',
  'upright': '업라이트 베이스', 'harp': '하프', 'marimba': '마림바', 'bell': '벨',
  'pluck': '플럭', 'bass': '신스 베이스', 'fingerbass': '핑거 베이스', 'moogbass': '무그 베이스',
  'pad': '패드', 'analogpad': '아날로그 패드', 'strings': '스트링', 'jpstrings': 'JP 스트링',
  'violin': '바이올린', 'cello': '첼로', 'brass': '브라스', 'analogbrass': '아날로그 브라스',
  'sax': '색소폰', 'trumpet': '트럼펫', 'clarinet': '클라리넷', 'flute': '플루트',
  'organ': '오르간', 'vintorgan': '빈티지 오르간', 'lead': '리드', 'moogleadv': '무그 리드',
  'saw': '톱니', 'chip': '칩튠', 'sine': '사인', 'wobble': '워블', 'stab': '스탭',
  // 팝·R&B·가스펠이 쓰는 목소리. 소리는 나는데 **표 셋에서 빠져 있었다** —
  // 이름이 영어로 나오고, 고르는 목록에 없어서 한 번 바꾸면 되돌릴 수 없었다.
  'vocal': '보컬',
};

/// 시험용 — 계열별로 묶어 둔 순서
const List<String> ALL_VOICES = [
  'piano',
  'epiano',
  'guitar',
  'nylon',
  'harp',
  'marimba',
  'bell',
  'pluck',
  'upright',
  'bass',
  'fingerbass',
  'moogbass',
  'wobble',
  'pad',
  'analogpad',
  'strings',
  'jpstrings',
  'violin',
  'cello',
  'brass',
  'analogbrass',
  'sax',
  'trumpet',
  'clarinet',
  'flute',
  'organ',
  'vintorgan',
  'lead',
  'moogleadv',
  'saw',
  'chip',
  'sine',
  'stab',
  'vocal',
];

/// 악기 계열 — 고르는 화면에서 **묶어서** 보여 주려고 만든 표 (5단계 25/N).
///
/// 24~33개를 한 줄에 늘어놓으면 원하는 걸 찾으려고 계속 밀어야 한다. 사람은
/// "기타 비슷한 거"를 찾지 'nylon' 을 찾지 않는다 — 그래서 소리 나는 방식으로 묶었다.
const Map<String, List<String>> kVoiceFamily = {
  '건반': ['piano', 'epiano', 'organ', 'vintorgan'],
  '뜯고 치는': ['guitar', 'nylon', 'harp', 'pluck', 'marimba', 'bell'],
  '관악기': ['sax', 'trumpet', 'clarinet', 'flute', 'brass', 'analogbrass'],
  '현악기': ['violin', 'cello', 'strings', 'jpstrings'],
  '신스': [
    'lead',
    'moogleadv',
    'saw',
    'chip',
    'sine',
    'wobble',
    'stab',
    'pad',
    'analogpad',
  ],
  '베이스': ['upright', 'bass', 'fingerbass', 'moogbass'],
  '목소리': ['vocal'],
};

/// 악기 계열 아이콘 — 이름만으로 죽 늘어놓으면 훑어보기 어렵다(사용자
/// 요청, 2026-09-16: "악기선택시 악기들 카테고리로 정리해서 깔끔하게").
/// `kVoiceFamily` 와 같은 키 — 악기 고르는 시트 여러 곳(`live_view.dart`·
/// `scene_view.dart`·`mixer_view.dart`)이 다 이 표 하나를 같이 쓴다.
const Map<String, IconData> kVoiceFamilyIcon = {
  '건반': Icons.piano,
  '뜯고 치는': Icons.music_note,
  '관악기': Icons.air,
  '현악기': Icons.linear_scale,
  '신스': Icons.graphic_eq,
  '베이스': Icons.speaker,
  '목소리': Icons.mic,
};
