// 4단계 4/N — GENRE_MIX(웹) 이식 · 트랙 버스(TrackMix) 적용.
// 4단계 5/N — 트랙 구조 일반화(mixer.dart TrackMixSet)에 맞춰 슬롯 이름 기반으로 다시 짬.
//
// 웹 GENRE_MIX 는 트랙 "슬롯" 이름으로 갈린다(예: 트랩은 drum/b808/pad/brass/bell/plk
// 여섯 슬롯). **배열형 6곡**(song.dart 의 kSongForms — lofi/house/hiphop/citypop/
// ballad/rock)은 슬롯이 정확히 drum/bass/chord/melody 네 개뿐이라 여기서도 그대로
// 그 이름을 쓴다. **객체형 롱폼**은 이번 세션에 트랙 버스가 N개로 일반화되면서
// (mixer.dart `TrackMixSet.configure`) 처음으로 걸 자리가 생겼다 — 이번엔 트랩 하나만
// 옮겼다(HANDOFF "한 번에 한 덩어리" 원칙 — proghouse/pop/jazz/ambient 는 다음).
//
// 값은 `~/AI Company/music_doodle/assets/app.html` 의 GENRE_MIX(7952줄)에서
// 그대로 옮겼다 — 바꾸지 않았다.

import 'genres.dart';
import 'mixer.dart';

/// 트랙 하나 몫(vol/pan/3밴드 EQ/리버브 send, 객체형은 hpf/lpf 도) — 웹
/// GENRE_MIX[genre][slot] 한 항목. [hpf]/[lpf] 는 배열형 6곡 항목엔 웹에도 없어서
/// null 이면 손대지 않는다(TrackMix 기본값 20Hz/20000Hz, 투명 그대로 유지).
class PartMixSpec {
  final double vol, pan, eqLo, eqMid, eqHi, rev;
  final double? hpf, lpf;

  /// 느린 로우패스 움직임(엠비언트 패드용). 0 이면 안 움직인다.
  final double lfoHz, lfoDepth;
  const PartMixSpec(
    this.vol,
    this.pan,
    this.eqLo,
    this.eqMid,
    this.eqHi,
    this.rev, {
    this.hpf,
    this.lpf,
    this.lfoHz = 0,
    this.lfoDepth = 0,
  });
}

/// 장르 하나 몫 — 슬롯 이름 → PartMixSpec. `Map` 리터럴의 삽입 순서가 그대로
/// [melodicSlotsFor] 가 돌려주는 순서다(드럼 제외) — 노트에 태그하는 슬롯 인덱스가
/// 이 순서를 기준으로 정해지므로 순서를 바꾸면 안 된다.
/// 장르별 **킥↔베이스 비켜 주기**(사이드체인) 세기. 0 이면 안 한다.
///
/// 계획 6-5 가 제일 먼저 꼽은 충돌이 Kick↔Bass 다. 둘 다 저역을 쓰니 겹치면
/// 킥이 뭉개지거나 베이스가 안 들린다. 표준 처리는 **킥이 칠 때 나머지를 잠깐
/// 낮추는 것**이다 — 하우스·트랩에서는 그게 곧 그 장르의 소리(펌핑)이기도 하다.
///
/// **장르마다 다르다.** 재즈·발라드·록에 펌핑을 걸면 그건 개선이 아니라 고장이다.
/// 그래서 값으로 둔다 — 데이터로 두면 장르를 더할 때 코드를 안 고친다(계획 7-1).
/// **`kGenres` 에서 뽑아 쓴다** (계획 7-1) — 값은 거기 적혀 있다.
final Map<String, double> kGenreDuck = {for (final g in kGenres) g.key: g.duck};

/// 장르별 **스윙 격자** — 8분을 미는가, 16분을 미는가.
///
/// 이걸 데이터로 뺀 이유가 있다. 원래는 드럼 타격 자리를 세어서 격자를 추측했는데,
/// **한 격자로는 두 장르를 같이 만족시킬 수 없었다.** 재즈는 라이드가 16분이라
/// 16분 격자가 뽑히고, 그러면 8분 위에 앉은 멜로디는 전부 '앞칸'이 되어
/// **한 음도 안 밀렸다(0/92).** 반대로 8분 격자를 고르면 로파이 16분 하이햇이 죽었다.
/// 고칠 때마다 반대쪽이 깨졌다 — 추측이 아니라 **장르가 아는 것**이기 때문이다.
///
///  8  = 8분 스윙(재즈·발라드처럼 「따-단, 따-단」)
///  16 = 16분 셔플(로파이·힙합·하우스처럼 잘게 끄는 느낌)
/// **`kGenres` 에서 뽑아 쓴다** (계획 7-1).
final Map<String, int> kGenreSwingGrid = {
  for (final g in kGenres) g.key: g.swingGrid,
};

class GenreMixSpec {
  final Map<String, PartMixSpec> parts;

  /// 드럼 버스로 보낼 슬롯 이름. 대부분 'drum' 인데 **엠비언트만 'perc'** 다 —
  /// 웹 `GENRE_MIX.ambient` 에 `drum` 키가 아예 없고 `perc` 로 들어 있다
  /// (SONG_FORMS 쪽도 `{slot:'perc', type:'drum'}`). 이름을 박아 두면 그 곡의 드럼이
  /// 멀로딕 버스로 잘못 들어가고 드럼 버스는 투명하게 남는다.
  final String drumSlot;
  const GenreMixSpec(this.parts, {this.drumSlot = 'drum'});
}

/// 웹 GENRE_MIX 그대로(app.html 7952줄~, 값 하나 안 바꿈).
/// 배열형 6곡: drum/bass/chord/melody. 객체형(지금은 trap 만): drum + 곡별 슬롯.
const Map<String, GenreMixSpec> kGenreMix = {
  'lofi': GenreMixSpec({
    'drum': PartMixSpec(0.80, 0, 1.5, -1.5, -4, 0.10),
    'bass': PartMixSpec(1.05, 0, 2, -1, -3, 0.04),
    'chord': PartMixSpec(0.95, -0.14, -1, 0.5, -2.5, 0.20),
    'melody': PartMixSpec(0.72, 0.14, -3, 0.5, -1, 0.24),
  }),
  'house': GenreMixSpec({
    'drum': PartMixSpec(1.10, 0, 3, -1.5, 2, 0.05),
    'bass': PartMixSpec(1.05, 0, 2.5, -1, -2, 0.02),
    'chord': PartMixSpec(0.78, -0.20, -4, 0, 2, 0.16),
    'melody': PartMixSpec(0.72, 0.16, -5, 0.5, 2.5, 0.20),
  }),
  'hiphop': GenreMixSpec({
    'drum': PartMixSpec(1.05, 0, 2.5, -1, 0, 0.05),
    'bass': PartMixSpec(1.15, 0, 4, -2, -5, 0.02),
    'chord': PartMixSpec(0.70, -0.18, -3, -0.5, -2, 0.22),
    'melody': PartMixSpec(0.80, 0.12, -2, 1, 0, 0.16),
  }),
  'citypop': GenreMixSpec({
    'drum': PartMixSpec(0.95, 0, 1, -0.5, 2, 0.08),
    'bass': PartMixSpec(1.05, 0, 1.5, 1, -1, 0.04),
    'chord': PartMixSpec(0.88, -0.16, -2, 0, 1.5, 0.16),
    'melody': PartMixSpec(0.85, 0.14, -3, 0.5, 2, 0.18),
  }),
  'ballad': GenreMixSpec({
    'drum': PartMixSpec(0.72, 0, 0.5, -1, -1, 0.14),
    'bass': PartMixSpec(0.95, 0, 2, -0.5, -3, 0.06),
    'chord': PartMixSpec(1.00, -0.12, -1, 0.5, 1, 0.24),
    'melody': PartMixSpec(0.88, 0.18, -4, 1, 1.5, 0.28),
  }),
  'rock': GenreMixSpec({
    'drum': PartMixSpec(1.05, 0, 2, -1, 2, 0.08),
    'bass': PartMixSpec(1.00, 0, 2, 0.5, -2, 0.03),
    'chord': PartMixSpec(1.00, -0.22, -2, 1.5, 1, 0.10),
    'melody': PartMixSpec(0.80, 0.22, -4, 1, 2, 0.12),
  }),
  // 5단계 47/N — 왈츠(3/4). 발라드와 같은 편성(어쿠스틱)이라 성격도 가깝게 잡았다.
  'waltz': GenreMixSpec({
    'drum': PartMixSpec(0.80, 0, 1, -0.5, 0, 0.16),
    'bass': PartMixSpec(0.98, 0, 2, 0, -2, 0.08),
    'chord': PartMixSpec(0.95, -0.10, -1, 0.5, 1, 0.22),
    'melody': PartMixSpec(0.88, 0.14, -3, 1, 1.5, 0.24),
  }),
  // 5단계 47/N — 흔들발라드(6/8). 4/4 발라드와 같은 편성·성향.
  'ballad68': GenreMixSpec({
    'drum': PartMixSpec(0.72, 0, 0.5, -1, -1, 0.14),
    'bass': PartMixSpec(0.95, 0, 2, -0.5, -3, 0.06),
    'chord': PartMixSpec(1.00, -0.12, -1, 0.5, 1, 0.24),
    'melody': PartMixSpec(0.88, 0.18, -4, 1, 1.5, 0.28),
  }),

  // ===== 완성곡 믹스(객체형 롱폼) =====
  // 핵심은 **음역 정리(hpf)** — 저역은 킥과 베이스만 갖고 나머지는 잘라낸다.
  // 이걸 안 하면 악기가 늘수록 아래가 뭉쳐서 "드럼은 큰데 악기는 안 들리는" 소리가 된다.
  'trap': GenreMixSpec({
    'drum': PartMixSpec(0.80, 0, 2, -1, 1, 0.04, hpf: 30),
    'b808': PartMixSpec(1.12, 0, 4, -2, -6, 0.00, hpf: 22, lpf: 2500),
    'pad': PartMixSpec(0.72, -0.22, -4, -1, -1, 0.28, hpf: 220),
    'brass': PartMixSpec(0.62, 0.30, -4, 1, 1, 0.16, hpf: 320),
    'bell': PartMixSpec(0.90, 0.10, -5, 0.5, 2, 0.24, hpf: 260),
    'plk': PartMixSpec(0.50, -0.32, -6, 0, 2, 0.20, hpf: 420),
  }),

  // 프로그하우스 — 리드가 가장 크고(0.90) 가운데 살짝 오른쪽. 아르페지오는 왼쪽으로 빼서
  // 스탭(오른쪽)과 좌우로 갈라 놓는다. 베이스는 lpf 3000 으로 위를 덮어 패드에 자리를 준다.
  'proghouse': GenreMixSpec({
    'drum': PartMixSpec(0.84, 0, 2.5, -1.5, 2, 0.05, hpf: 30),
    'bass': PartMixSpec(1.10, 0, 2.5, -1, -4, 0.02, hpf: 28, lpf: 3000),
    'pad': PartMixSpec(0.80, -0.24, -4, -0.5, 1, 0.32, hpf: 200),
    'stab': PartMixSpec(0.62, 0.30, -5, 0.5, 2, 0.18, hpf: 320),
    'arp': PartMixSpec(0.52, -0.30, -6, 0, 2.5, 0.24, hpf: 450),
    'lead': PartMixSpec(0.90, 0.10, -4, 1, 2, 0.20, hpf: 240),
  }),

  // 팝 — 보컬이 주인공이라 가장 크고(0.96) 정가운데. 피아노는 왼쪽, 기타는 오른쪽으로
  // 갈라서 보컬 자리를 비운다. 스트링은 웹 GENRE_MIX 에 항목이 없어서 투명(기본값)으로 둔다.
  'pop': GenreMixSpec({
    'drum': PartMixSpec(0.78, 0, 1.5, -0.5, 2, 0.09, hpf: 30),
    'bass': PartMixSpec(1.08, 0, 2.5, 0.5, -3, 0.03, hpf: 28, lpf: 3500),
    'piano': PartMixSpec(0.88, -0.18, -2, 0.5, 1.5, 0.15, hpf: 190),
    'gtr': PartMixSpec(0.60, 0.32, -4, 1, 2, 0.14, hpf: 300),
    'voc': PartMixSpec(0.96, 0, -5, 1.5, 2.5, 0.18, hpf: 200),
    'plk': PartMixSpec(0.46, -0.32, -6, 0, 2, 0.20, hpf: 450),
    // 스트링은 **편성에 아예 없었다** — 페이더도 팬도 리버브도 안 걸린 채로
    // 기본값(투명) 그대로 나오고 있었다. 오류가 안 나서 오래 남았다(2026-08-29).
    // 위층에서 넓게 깔리는 자리라 낮게 두고 리버브를 길게 준다.
    'str': PartMixSpec(0.50, -0.22, -5, 0, 1.5, 0.30, hpf: 380),
  }),

  // 재즈 — 드럼(브러시)이 가장 작다(0.66). 업라이트 베이스가 주인공(1.05).
  // 피아노 오른쪽·색소폰 왼쪽으로 갈라 놓는다.
  'jazz': GenreMixSpec({
    'drum': PartMixSpec(0.66, 0, 0.5, -0.5, 1, 0.15, hpf: 40),
    'bass': PartMixSpec(1.05, -0.06, 2, 0.5, -4, 0.07, hpf: 26, lpf: 3000),
    'piano': PartMixSpec(0.88, 0.20, -2, 0.5, 1, 0.20, hpf: 180),
    'vib': PartMixSpec(0.58, -0.26, -5, 0, 2, 0.26, hpf: 380),
    'sax': PartMixSpec(0.92, -0.18, -4, 1, 1.5, 0.22, hpf: 260),
    'gtr': PartMixSpec(0.70, 0.28, -4, 0.5, 1.5, 0.24, hpf: 240),
  }),

  // 엠비언트 — 리버브가 전부 0.3~0.5 로 깊다. 퍼커션이 가장 작고(0.34) 패드가 주인공(0.95).
  // **드럼 버스 이름이 'perc'** 다 — 웹 GENRE_MIX.ambient 에 drum 키가 없다.
  // 엠비언트 — 사용자 지시로 두 가지를 더 걸었다(2026-08-14):
  //  (b) 패드·스트링에 **느린 로우패스 움직임**. 컷오프를 같이 내려야(20000→2400/3200)
  //      움직임이 들린다. 주기 14초·20초로 서로 다르게 둬서 둘이 같이 숨쉬지 않게 했다
  //      — 같은 주기면 맥놀이처럼 뭉쳐 들린다.
  //  (c) **리버브를 더 깊게**. 단 서브(sub)는 그대로 둔다 — 저음에 리버브를 먹이면
  //      곡 전체가 흐려진다.
  'ambient': GenreMixSpec({
    'pad': PartMixSpec(
      0.95,
      -0.14,
      -1,
      -1,
      0.5,
      0.62,
      hpf: 120,
      lpf: 2400,
      lfoHz: 0.071,
      lfoDepth: 0.45,
    ),
    'str': PartMixSpec(
      0.72,
      0.22,
      -4,
      -0.5,
      1,
      0.66,
      hpf: 260,
      lpf: 3200,
      lfoHz: 0.050,
      lfoDepth: 0.34,
    ),
    'sub': PartMixSpec(0.92, 0, 3, -2, -8, 0.05, hpf: 22, lpf: 1200),
    'bell': PartMixSpec(0.66, 0.26, -6, 0, 2, 0.58, hpf: 400),
    'harp': PartMixSpec(0.48, -0.32, -6, 0, 2.5, 0.56, hpf: 500),
    'perc': PartMixSpec(0.34, 0.12, -3, -1, 1, 0.44, hpf: 200),
    // 해질녘의 둘째 스트링도 편성에 없었다(2026-08-29). 첫째보다 한 층 위에서
    // 훨씬 여리게 — 겹이지 또 하나의 주인공이 아니다.
    'str2': PartMixSpec(
      0.40,
      -0.30,
      -6,
      -0.5,
      1.5,
      0.70,
      hpf: 420,
      lpf: 4200,
      lfoHz: 0.037,
      lfoDepth: 0.30,
    ),
  }, drumSlot: 'perc'),

  // 드릴 — 808 이 주인공이라 위를 덮고(lpf), 나머지는 저역을 걷어 자리를 비운다.
  // 처음 값으로는 **드릴이 곡 중에 제일 컸다**(-8.1dB · 편차가 3.4 → 4.6dB 로 벌어짐).
  // 페이더를 15% 내려 봤더니 **0.2dB 밖에 안 움직였다**(-8.1 → -8.3) —
  // 마스터 리미터가 그만큼을 도로 밀어 올린다. 이 편차는 페이더가 아니라 **밀도**가
  // 만든 것이다(드릴은 원래 빽빽하고 눌린 장르다). 그래도 값은 낮춰 둔다 —
  // 크기는 그대로여도 **리미터가 덜 물어서** 다이내믹이 덜 뭉갠다.
  'drill': GenreMixSpec({
    'drum': PartMixSpec(0.70, 0, 2.5, -1, 1.5, 0.04, hpf: 30),
    'b808': PartMixSpec(0.98, 0, 4.5, -2, -6, 0.00, hpf: 22, lpf: 2200),
    'pad': PartMixSpec(0.53, -0.20, -5, -1, -1.5, 0.30, hpf: 240),
    'bell': PartMixSpec(0.72, 0.12, -5, 0.5, 2.5, 0.26, hpf: 280),
    'plk': PartMixSpec(0.41, -0.30, -6, 0, 2, 0.22, hpf: 420),
  }),

  // R&B — 목소리(voc)가 제일 앞. 키보드와 패드가 같은 자리를 쓰므로
  // 패드를 왼쪽으로 빼고 위를 덮어 키보드에 가운데를 내준다.
  // 디스코 — 킥이 네 박을 다 밟으니 베이스를 살짝 비켜 준다. 스트링은 뒤에서 넓게.
  'disco': GenreMixSpec({
    'drum': PartMixSpec(0.80, 0, 1.5, -0.5, 2, 0.10, hpf: 34),
    'bass': PartMixSpec(1.02, 0, 2, 0.5, -3, 0.04, hpf: 28, lpf: 3600),
    'keys': PartMixSpec(0.72, 0.24, -3, 1, 1.5, 0.16, hpf: 220),
    'str': PartMixSpec(0.56, -0.28, -5, 0, 1, 0.28, hpf: 320),
    'lead': PartMixSpec(0.86, -0.12, -4, 1, 2, 0.18, hpf: 260),
  }),

  // 가스펠 — 펌핑을 안 건다(duck 0). 피아노가 주인공이고 오르간은 뒤를 채운다.
  'gospel': GenreMixSpec({
    'drum': PartMixSpec(0.72, 0, 1, -0.5, 1, 0.14, hpf: 36),
    'bass': PartMixSpec(0.98, 0, 2.5, 0, -3.5, 0.05, hpf: 26, lpf: 3000),
    'keys': PartMixSpec(0.86, 0.16, -2, 0.5, 1.5, 0.20, hpf: 170),
    'org': PartMixSpec(0.52, -0.24, -4, 0, 0.5, 0.26, hpf: 240),
    'voc': PartMixSpec(0.92, 0, -4, 1.5, 2, 0.22, hpf: 200),
  }),

  'rnb': GenreMixSpec({
    'drum': PartMixSpec(0.68, 0, 1, -0.5, 0.5, 0.10, hpf: 32),
    'bass': PartMixSpec(0.89, 0, 2.5, -0.5, -4, 0.03, hpf: 24, lpf: 3200),
    'keys': PartMixSpec(0.75, 0.10, -2, 0.5, 1, 0.22, hpf: 180),
    'pad': PartMixSpec(0.44, -0.26, -5, -1, -1, 0.32, hpf: 260, lpf: 6000),
    'voc': PartMixSpec(0.78, 0, -4, 1, 2, 0.24, hpf: 220),
  }),
};

void _apply(TrackMix m, PartMixSpec s) {
  m.vol = s.vol;
  m.pan = s.pan;
  m.eqLoDb = s.eqLo;
  m.eqMidDb = s.eqMid;
  m.eqHiDb = s.eqHi;
  m.rev = s.rev;
  // **null 이면 넘어가지 않는다 — 투명한 기본값으로 되돌린다.**
  // 드럼 버스(`mixes.drum`)는 씬을 새로 짜지 않는 한(`TrackMixSet.configure`)
  // 재생 내내 **같은 객체를 계속 쓴다.** hpf 를 건 장르(트랩 등)를 들었다가
  // 안 거는 장르(로파이 등)로 넘어가면, 예전 장르가 걸어 둔 hpf 가 그대로
  // 남아 있었다 — 소리가 그 판을 틀기 전 재생 이력에 따라 달라졌다.
  // (mixer.dart 의 「기본값은 전부 투명해야 한다: hpf=20·lpf=20000」과 같은 값.)
  m.hpfFreq = s.hpf ?? 20;
  m.lpfFreq = s.lpf ?? 20000;
  m.lfoHz = s.lfoHz;
  m.lfoDepth = s.lfoDepth;
  m.markDirty();
}

/// 이 장르의 멀로딕 트랙 버스 이름들 — 'drum' 은 뺀다(드럼은 항상 별도 고정 버스).
/// [TrackMixSet.configure] 에 넘기는 리스트와, 노트에 태그할 슬롯 인덱스
/// (`slotNamesFor(genre).indexOf(slot)`) 가 전부 이 순서를 기준으로 한다 — 호출부가
/// 전부 같은 리스트를 봐야 인덱스가 맞다. 모르는 장르는 배열형 6곡의 기본 편성으로.
List<String> melodicSlotsFor(String genre) {
  final g = kGenreMix[genre];
  if (g == null) return const ['bass', 'chord', 'melody'];
  return g.parts.keys.where((k) => k != g.drumSlot).toList(growable: false);
}

/// 장르 몫 GENRE_MIX 를 트랙 버스로 적용한다 — 웹 `applyGenreMix()`.
/// **호출 전에 `mixes.configure(melodicSlotsFor(genre))` 로 편성을 먼저 맞춰야 한다**
/// (audio_isolate.dart `_cGenreMix` 핸들러가 항상 그렇게 한다). 모르는 장르면
/// 아무것도 안 하고 조용히 돌아간다.
void applyGenreMixTo(TrackMixSet mixes, String genre) {
  final g = kGenreMix[genre];
  if (g == null) return;
  g.parts.forEach((slot, spec) {
    final m = slot == g.drumSlot ? mixes.drum : mixes.bus(slot);
    if (m == null) return; // 편성이 안 맞으면 조용히 건너뜀(방어적)
    _apply(m, spec);
  });
}

/// 전부 투명한 기본값으로 되돌린다 — 장르 믹스 없이 들어볼 때(시험 화면 리셋 버튼 등).
void resetGenreMix(TrackMixSet mixes) {
  // lfo 도 같이 꺼야 한다 — 안 그러면 엠비언트를 튼 뒤 다른 곡에서도 패드가 계속 움직인다
  for (final m in [mixes.drum, ...mixes.slots]) {
    m.vol = 1.0;
    m.pan = 0.0;
    m.eqLoDb = 0;
    m.eqMidDb = 0;
    m.eqHiDb = 0;
    m.rev = 0;
    m.hpfFreq = 20;
    m.lpfFreq = 20000;
    m.lfoHz = 0;
    m.lfoDepth = 0;
    m.markDirty();
  }
}

// ══════════════════ 스타일 보정 (5단계 34/N) ══════════════════

/// 스타일마다 소리 크기를 붙이는 배수. **왜 필요한가:**
/// GENRE_MIX 값이 스타일마다 따로라서, 곡 전체를 렌더해 제일 시끄러운 3초를 재 보니
/// 트랩 −7.7 dBFS · 재즈 −17.9 dBFS 로 **10.2dB(체감 두 배쯤)** 벌어져 있었다.
/// 곡을 바꿀 때마다 볼륨을 만져야 하면 그게 고장이다.
///
/// 목표는 −13 dBFS. 다만 **완전히 평평하게는 안 맞춘다** — 재즈가 성긴 건 원래
/// 그런 음악이고, 억지로 끌어올리면 리미터에 눌려 납작해진다.
/// 보정 폭을 −5 ~ +3.5dB 로 묶었다(그래서 재즈는 아직 조금 작다).
// 2026-08-29 재조정 — 자리바꿈·층·베이스 손질로 장르마다 크기가 다시 어긋났다.
// (프로그하우스 스탭이 위층으로 가면서 저역이 줄어 −13.8dB 까지 내려갔고,
//  새로 들어온 드릴·R&B·디스코·가스펠은 아예 보정이 없어 −8.3dB 로 튀었다.)
// 값 뒤 주석은 **보정 전 「제일 큰 3초」 값**이다.
const Map<String, double> kStyleGain = {
  'lofi': 0.95, // −9.9
  'house': 1.45, // −14.5
  'hiphop': 0.70, // −11.8
  'citypop': 1.05, // −11.2
  'ballad': 0.96, // −11.8
  'rock': 1.00, // −11.5
  'trap': 0.61, // −12.1
  'proghouse': 1.33, // −13.8
  'pop': 0.71, // −9.5
  'jazz': 1.72, // −12.7
  'drill': 0.73, // −8.3 (제일 컸다)
  'rnb': 0.86, // −9.7
  'disco': 1.06, // −11.8
  'gospel': 0.79, // −9.0
  'ambient': 1.06, // −12.6
  'waltz': 1.00, // 아직 측정 전 — 발라드 값을 임시로 따른다
  'ballad68': 0.96, // 아직 측정 전 — 4/4 발라드 값을 그대로 따른다
};

/// 그 스타일의 보정 배수. 모르는 스타일은 1.0(안 건드림).
double styleGain(String genre) => kStyleGain[genre] ?? 1.0;
