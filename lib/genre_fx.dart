// 장르별 인서트(FX 프리셋) — **그 장르의 소리 성격.** (Phase 5 · 개선 계획 7)
//
// 계획 7: 「각 장르는 단순히 패턴만 다르게 하지 마십시오. 장르마다 Patterns ·
// Instruments · **Sound Character** · Genre Mix · **FX Presets** · Scene Presets ·
// Live Behavior 를 묶으십시오.」
//
// ── 믹스가 이미 하는 것은 안 한다 ──
// `kGenreMix` 가 이미 볼륨·좌우·EQ·리버브 센드를 장르마다 잡아 준다.
// 여기서 또 리버브를 걸면 **두 번 걸린다.** 그래서 인서트는 **믹스가 못 하는 것**만
// 맡는다 — 포화(드라이브·앰프), 다이내믹(컴프), 시간(딜레이).
//
// ── 사용자 것을 덮지 않는다 ──
// 이건 **기본값**이지 규칙이 아니다. 사용자가 인서트를 하나라도 만지면 그 트랙은
// `fxAuto = false` 가 되고, 그다음부터 장르를 바꿔도 그 트랙은 안 건드린다.
// (안 그러면 스타일을 바꿀 때마다 공들여 꽂아 둔 게 조용히 날아간다.)
//
// ── 안 거는 장르도 있다 ──
// 재즈는 비어 있다. **마이크 앞에서 친 소리**가 그 장르다 — 앰프도 딜레이도 걸면
// 그게 아니게 된다. 「장르마다 뭔가 하나씩」은 이유가 아니다.

// ── 컴프는 **붙잡는 것**이지 짓뭉개는 것이 아니다 ──
// 처음엔 문턱 -14~-16dB · 비율 4~6:1 · 보정 2dB 로 넣었다. 재 보니
// **트랩 피크가 0.655, 힙합이 0.741** 로 떨어졌다(다른 장르는 0.96~0.97).
// 크기도 3~4dB 빠지고 스타일 편차가 4.4 → 6.0dB 로 벌어졌다.
// 비율만큼 깎아 놓고 보정을 안 준 탓이다. 문턱을 올리고 비율을 낮춰
// **피크 몇 dB 만 붙잡는** 값으로 바꿨다.

/// 인서트 하나 — 종류와 손잡이 값.
class FxPreset {
  final String type;
  final Map<String, double> params;
  const FxPreset(this.type, [this.params = const {}]);
}

/// 장르 → 슬롯(배열형은 트랙 타입) → 꽂을 인서트 순서.
///
/// **순서가 곧 소리다** — 컴프 뒤 드라이브와 드라이브 뒤 컴프는 다르다.
const Map<String, Map<String, List<FxPreset>>> kGenreFx = {
  // 먼지 낀 소리 — 베이스는 둔탁하게, 건반은 살짝 태운다
  'lofi': {
    'bass': [
      FxPreset('bassamp', {'drive': 0.35, 'blend': 0.5, 'treble': -4}),
    ],
    'chord': [
      FxPreset('drive', {
        'mode': 0,
        'drive': 0.20,
        'tone': 0.35,
        'level': 0.95,
      }),
    ],
  },
  // 붐뱁 — 드럼을 붙잡아 앞으로 밀고, 베이스는 배음을 더한다
  'hiphop': {
    'drum': [
      FxPreset('comp', {
        'mode': 1,
        'thr': -8,
        'ratio': 3,
        'atk': 0.35,
        'rel': 0.45,
        'makeup': 3,
      }),
    ],
    'bass': [
      FxPreset('bassamp', {'drive': 0.42, 'blend': 0.6}),
    ],
  },
  // 반짝이는 밤 — 아주 옅은 포화 + 짧은 딜레이
  'citypop': {
    'chord': [
      FxPreset('drive', {'mode': 0, 'drive': 0.12, 'tone': 0.70, 'level': 1.0}),
    ],
    'melody': [
      FxPreset('delay', {'mode': 0, 'time': 220, 'fb': 0.18, 'mix': 0.14}),
    ],
  },
  // 넓게 — 테이프 딜레이가 꼬리를 만든다(리버브는 믹스가 이미 준다)
  'ballad': {
    'melody': [
      FxPreset('delay', {'mode': 1, 'time': 380, 'fb': 0.20, 'mix': 0.13}),
    ],
  },
  // 기타가 앞에 — **앰프**가 이 장르다
  'rock': {
    'melody': [
      FxPreset('amp', {'mode': 1, 'gain': 0.50, 'presence': 3, 'level': 0.85}),
    ],
    'bass': [
      FxPreset('bassamp', {'drive': 0.30, 'blend': 0.5}),
    ],
  },
  'trap': {
    'drum': [
      FxPreset('comp', {
        'mode': 2,
        'thr': -8,
        'ratio': 3.5,
        'atk': 0.30,
        'rel': 0.40,
        'makeup': 3.5,
      }),
    ],
    'bell': [
      FxPreset('delay', {'mode': 2, 'time': 300, 'fb': 0.28, 'mix': 0.18}),
    ],
  },
  'drill': {
    'b808': [
      FxPreset('bassamp', {'drive': 0.25, 'blend': 0.7, 'treble': -6}),
    ],
    'bell': [
      FxPreset('delay', {'mode': 2, 'time': 260, 'fb': 0.26, 'mix': 0.16}),
    ],
  },
  'house': {
    'drum': [
      FxPreset('comp', {
        'mode': 2,
        'thr': -7,
        'ratio': 3,
        'atk': 0.30,
        'rel': 0.40,
        'makeup': 3,
      }),
    ],
    'chord': [
      FxPreset('delay', {'mode': 0, 'time': 250, 'fb': 0.24, 'mix': 0.16}),
    ],
  },
  // 길게 쌓아 올리는 — 핑퐁이 좌우로 벌린다
  'proghouse': {
    'drum': [
      FxPreset('comp', {
        'mode': 2,
        'thr': -7,
        'ratio': 3,
        'atk': 0.30,
        'rel': 0.40,
        'makeup': 3,
      }),
    ],
    'pad': [
      FxPreset('delay', {'mode': 2, 'time': 375, 'fb': 0.32, 'mix': 0.20}),
    ],
  },
  'pop': {
    'drum': [
      FxPreset('comp', {
        'mode': 0,
        'thr': -9,
        'ratio': 2.5,
        'atk': 0.40,
        'rel': 0.50,
        'makeup': 2.5,
      }),
    ],
    'voc': [
      FxPreset('delay', {'mode': 0, 'time': 200, 'fb': 0.14, 'mix': 0.11}),
    ],
  },
  // 일렉 피아노의 온기 + 목소리 꼬리
  // 거울볼 — 킥이 네 박을 다 밟으니 드럼을 하나로 묶고, 브라스에 광을 낸다
  'disco': {
    'drum': [
      FxPreset('comp', {
        'mode': 1,
        'thr': -8,
        'ratio': 3,
        'atk': 0.30,
        'rel': 0.40,
        'makeup': 3,
      }),
    ],
    'lead': [
      FxPreset('drive', {
        'mode': 0,
        'drive': 0.18,
        'tone': 0.66,
        'level': 0.98,
      }),
    ],
  },
  // 오르간은 원래 살짝 물린 소리다 — 그 온기만 준다. 손뼉은 안 건드린다.
  'gospel': {
    'org': [
      FxPreset('drive', {
        'mode': 0,
        'drive': 0.20,
        'tone': 0.55,
        'level': 0.96,
      }),
    ],
    'voc': [
      FxPreset('delay', {'mode': 1, 'time': 340, 'fb': 0.20, 'mix': 0.12}),
    ],
  },
  'rnb': {
    'keys': [
      FxPreset('drive', {'mode': 0, 'drive': 0.11, 'tone': 0.60, 'level': 1.0}),
    ],
    'voc': [
      FxPreset('delay', {'mode': 1, 'time': 300, 'fb': 0.24, 'mix': 0.15}),
    ],
  },
  // 깔아 두는 — 길고 되풀이되는 꼬리
  'ambient': {
    'bell': [
      FxPreset('delay', {'mode': 1, 'time': 600, 'fb': 0.42, 'mix': 0.28}),
    ],
    'harp': [
      FxPreset('delay', {'mode': 1, 'time': 450, 'fb': 0.30, 'mix': 0.20}),
    ],
  },
  // 재즈는 **일부러 비워 둔다** — 위 주석 참고.
  'jazz': {},
};

/// 이 장르가 이 슬롯에 꽂아 줄 것. 없으면 빈 목록.
List<FxPreset> genreFxFor(String genre, String slot) =>
    kGenreFx[genre]?[slot] ?? const [];
