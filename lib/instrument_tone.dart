// 악기 설정 — 기타 본체·픽업, 피아노 모델·에이징, 베이스 바디, 현악 편성,
// 관악 뮤트(2026-09 · 2026-09-13 확장, 사용자 요청: "악기들 상세설정도
// 추가해").
//
// 이 앱은 표본(`sampler.dart`)으로 기타·피아노를 낸다 — 스트랫과 레스폴을
// **다른 녹음**으로 두려면 표본을 통째로 새로 구해야 한다(이번엔 그럴 수 없다).
// 대신 **이미 재생에 실려 있는 자리**를 쓴다: 트랙의 3밴드 EQ(`TrackEq`,
// `sequencer.dart` 가 실제로 버스에 얹는 값). 픽업 위치·바디 목재·오래된 정도가
// 소리를 가르는 것도 결국 **주파수 균형**이라 — 브릿지 픽업은 밝고 얇게, 넥
// 픽업은 어둡고 도톰하게, 오래된 피아노는 위가 죽고 아래가 뭉근해진다 —
// EQ 하나로도 "그렇게 들리게" 하는 데는 충분하다.
//
// **믹서의 수동 EQ 손잡이와 같은 자리를 쓴다.** 그래서 악기 설정을 만지면
// (기존 `eqChanged()` 규칙대로) 그 트랙은 `mixAuto` 가 꺼진다 — 장르를 나중에
// 바꿔도 애써 고른 소리가 안 덮인다.

/// 기타 본체 — 목재·픽업 종류가 만드는 전체 성격.
const Map<String, String> kGuitarBodyLabel = {
  'strat': '스트랫캐스터',
  'lespaul': '레스폴',
};
const Map<String, String> kGuitarBodyDesc = {
  'strat': '밝고 쨍한 싱글코일 — 펜더 특유의 청량한 소리',
  'lespaul': '두껍고 따뜻한 험버커 — 마호가니 바디의 묵직함',
};
const Map<String, (double, double, double)> kGuitarBodyEq = {
  // (lo, mid, hi) dB
  'strat': (-2, -1, 3),
  'lespaul': (1, 2, -1),
};

/// 픽업 선택 — 넥(어둡다)·미들(중간)·브릿지(밝다). 스트랫 5단·레스폴 3단
/// 셀렉터를 이 세 자리로 단순화했다(가운데 자리 두 개는 소리가 서로 가깝다).
const Map<String, String> kGuitarPickupLabel = {
  'neck': '넥',
  'mid': '미들',
  'bridge': '브릿지',
};
const Map<String, String> kGuitarPickupDesc = {
  'neck': '어둡고 도톰하게 — 리드·솔로에 흔히 쓴다',
  'mid': '치우치지 않은 자리',
  'bridge': '밝고 쨍하게 — 커팅·리프에 흔히 쓴다',
};
const Map<String, (double, double, double)> kGuitarPickupEq = {
  'neck': (2, 1, -3),
  'mid': (0, 0, 0),
  'bridge': (-2, 0, 4),
};

/// 피아노 모델 — 몸통 크기가 만드는 울림의 차이(전자 피아노는 이미 딴 음색
/// `epiano` 라 여기 안 둔다 — 겹치는 이름을 또 만들 이유가 없다).
const Map<String, String> kPianoModelLabel = {
  'grand': '그랜드',
  'upright': '업라이트',
};
const Map<String, String> kPianoModelDesc = {
  'grand': '넓게 울리는 콘서트 그랜드 — 기준이 되는 소리',
  'upright': '작은 울림통 — 가운데가 좁고 위아래가 일찍 준다',
};
const Map<String, (double, double, double)> kPianoModelEq = {
  'grand': (0, 0, 0),
  'upright': (-1, 1, -2),
};

/// 에이징(0=새 것 ~ 1=오래된 것) — 위가 죽고 아래가 살짝 뭉근해진다.
/// 해머 펠트가 닳고 현이 삭으면 배음이 줄어드는 것을 흉내 낸다.
(double, double, double) pianoAgingEq(double aging) {
  final a = aging.clamp(0.0, 1.0);
  return (1.5 * a, -1.0 * a, -6.0 * a);
}

/// 베이스 바디 — 프리시전(굵고 중역이 뭉친다)과 재즈(스쿱드, 더 밝고 넓다).
/// 실제 베이스 기타에서 가장 흔히 갈리는 두 바디를 그대로 옮겼다.
const Map<String, String> kBassBodyLabel = {
  'precision': '프리시전',
  'jazz': '재즈',
};
const Map<String, String> kBassBodyDesc = {
  'precision': '굵고 곧은 중역 — 록·팝의 기본 저음',
  'jazz': '스쿱드 — 낮고 높은 쪽이 더 살고 중역은 파인다',
};
const Map<String, (double, double, double)> kBassBodyEq = {
  'precision': (1, 2, -1),
  'jazz': (2, -2, 2),
};

/// 현악 편성 — 솔로(가깝고 또렷)와 합주(넓고 배음이 흐리다).
/// 바이올린·첼로·스트링 패드 전부 같은 규칙을 쓴다 — 독주자 한 명과
/// 섹션 전체가 가르는 것은 결국 이 정도다.
const Map<String, String> kStringsEnsembleLabel = {
  'solo': '솔로',
  'section': '합주',
};
const Map<String, String> kStringsEnsembleDesc = {
  'solo': '독주자 한 명 — 가깝고 활 소리까지 또렷하다',
  'section': '섹션 전체 — 넓게 퍼지고 위아래가 부드러워진다',
};
const Map<String, (double, double, double)> kStringsEnsembleEq = {
  'solo': (0, 1, 2),
  'section': (1, -1, -1),
};

/// 관악 뮤트 — 오픈(그대로)과 뮤트(관 입구를 막아 종이 소리처럼 얇고
/// 콧소리 나게). 트럼펫·색소폰·브라스가 실제로 이렇게 갈린다.
const Map<String, String> kBrassMuteLabel = {'open': '오픈', 'mute': '뮤트'};
const Map<String, String> kBrassMuteDesc = {
  'open': '막지 않은 원래 소리',
  'mute': '관 입구를 막은 소리 — 얇고 콧소리 나며 위가 도드라진다',
};
const Map<String, (double, double, double)> kBrassMuteEq = {
  'open': (0, 0, 0),
  'mute': (-3, -2, 4),
};

const Set<String> _kBassVoices = {'bass', 'fingerbass', 'moogbass', 'upright'};
const Set<String> _kStringsVoices = {'strings', 'jpstrings', 'violin', 'cello'};
const Set<String> _kBrassVoices = {
  'brass',
  'analogbrass',
  'trumpet',
  'sax',
  'clarinet',
  'flute',
};

/// 지금 이 트랙에 실려야 할 EQ — 손잡이가 없는 음색이면 (0,0,0).
(double, double, double) instrumentToneEq({
  required String voice,
  String? guitarBody,
  String? guitarPickup,
  String? pianoModel,
  double pianoAging = 0,
  String? bassBody,
  String? stringsEnsemble,
  String? brassMute,
}) {
  if (voice == 'guitar') {
    final b = kGuitarBodyEq[guitarBody] ?? (0.0, 0.0, 0.0);
    final p = kGuitarPickupEq[guitarPickup] ?? (0.0, 0.0, 0.0);
    return (b.$1 + p.$1, b.$2 + p.$2, b.$3 + p.$3);
  }
  if (voice == 'piano' || voice == 'epiano') {
    final m = kPianoModelEq[pianoModel] ?? (0.0, 0.0, 0.0);
    final a = pianoAgingEq(pianoAging);
    return (m.$1 + a.$1, m.$2 + a.$2, m.$3 + a.$3);
  }
  if (_kBassVoices.contains(voice)) {
    return kBassBodyEq[bassBody] ?? (0.0, 0.0, 0.0);
  }
  if (_kStringsVoices.contains(voice)) {
    return kStringsEnsembleEq[stringsEnsemble] ?? (0.0, 0.0, 0.0);
  }
  if (_kBrassVoices.contains(voice)) {
    return kBrassMuteEq[brassMute] ?? (0.0, 0.0, 0.0);
  }
  return (0.0, 0.0, 0.0);
}

/// 이 음색이 악기 설정 손잡이를 보여 줄 대상인가.
bool hasInstrumentTone(String voice) =>
    voice == 'guitar' ||
    voice == 'piano' ||
    voice == 'epiano' ||
    _kBassVoices.contains(voice) ||
    _kStringsVoices.contains(voice) ||
    _kBrassVoices.contains(voice);
