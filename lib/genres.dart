// 장르 표 — **한 장르에 대한 모든 것을 한 줄에.** (Phase 5 · 개선 계획 7-1)
//
// 계획 7-1: 「새 장르를 추가할 때 엔진 코드를 대량 수정하지 않도록 구조를 데이터
// 중심으로 개선하십시오.」
//
// ── 왜 필요했나 ──
// 장르 하나를 더하려면 **6개 파일의 8개 표**를 고쳐야 했다:
//   presets.dart  kSongGenres(키·이름·템포·키트·조) · kGenrePresets(대표 패턴 4개)
//   genre_mix.dart kGenreDuck(비켜 주기) · kGenreSwingGrid(스윙 격자) · GENRE_MIX
//   song.dart      kSongForms 또는 kObjectSongForms(구간 구성)
//   create_sheet   kGenreFeel(한 줄 설명)
//   show_band      kStageLights(무대 조명 색)
// 하나만 빠뜨려도 **조용히 반쪽짜리 장르**가 된다 — 소리는 나는데 펌핑이 없거나,
// 스윙이 안 걸리거나, 무대가 파랗기만 하거나, 고르는 화면에 설명이 비어 있다.
// 오류도 안 난다. 그게 제일 나쁘다.
//
// ── 어디까지 모았나 ──
// **얇은 값들만** 여기로 모았다. 구간 구성(`kSongForms`)과 믹스 편성(`GENRE_MIX`)은
// 덩치가 크고 성격이 달라 제자리에 둔다 — 대신 `genre_check_test` 가
// **모든 장르가 그 둘에도 있는지** 지킨다. 표를 합치는 것보다 빠뜨림을 못 하게 막는 게
// 목적이므로, 그 목적은 시험으로도 똑같이 이룬다.
//
// 순수 Dart 다(Flutter 의존 없음) — 조명 색도 `Color` 가 아니라 int 로 둔다.

/// 장르 하나가 아는 모든 얇은 값.
class GenreDef {
  /// 저장 파일에 남는 키 — **절대 바꾸지 말 것**(옛 곡이 안 열린다).
  final String key;
  final String label;
  final double bpm;

  /// 드럼 키트(`DRUM_KITS` 의 키).
  final String kit;

  /// 'minor' | 'major' — **팝만 장조**다.
  final String mode;

  /// 이 스타일의 **박자** — `kMeters` 의 키 (5단계 47/N).
  ///
  /// **박자를 스타일이 정한다.** 판 라이브러리가 박자마다 따로라, 스타일을 고르는
  /// 순간 그 박자의 판이 실려야 어긋나지 않는다. 왈츠를 고르면 3/4 판이,
  /// 하우스를 고르면 4/4 판이 온다. 기본값이 '4/4' 라 여태 스타일은 안 달라진다.
  final String meter;

  /// 고르는 화면의 한 줄 설명. 음악 용어 대신 **들리는 느낌**으로.
  final String feel;

  /// 킥이 칠 때 나머지를 얼마나 낮출지 (계획 6-5). 0 이면 안 한다.
  final double duck;

  /// 스윙 격자 — 8(8분 스윙) 또는 16(16분 셔플) (계획 4-4·6-1).
  final int swingGrid;

  /// 무대 조명 세 기둥의 색(0xAARRGGBB).
  final List<int> lights;

  /// 대표 패턴 넷 — 씬을 처음 만들 때 실리는 것.
  final String drumPat, bassPat, chordPat, melodyPat;

  // ── 라이브 기본값 (계획 7 의 「Live Behavior」) ──
  //
  // 라이브 패드는 여태 **어떤 장르든 피아노 · 한 음 · 보통 길이**였다.
  // 트랩을 만들다 라이브를 열면 피아노가 나왔다. 그 장르로 만들고 있었는데 말이다.
  //
  // 음계는 안 건드린다 — 「아무 패드나 눌러도 맞는 음이 나온다」가 이 화면의 약속이고,
  // 장르마다 음을 빼면 그 약속이 흔들린다. 바꾸는 건 **음색·주법·길이**뿐이다.

  /// 라이브 패드의 음색.
  final String liveVoice;

  /// 'single'(한 음) · 'chord'(화음) · 'arp'(펼쳐서).
  final String liveMode;

  /// 음 길이 — 0 짧게 · 1 보통 · 2 길게.
  final int liveLen;

  const GenreDef({
    required this.key,
    required this.label,
    required this.bpm,
    required this.kit,
    required this.mode,
    this.meter = '4/4',
    required this.feel,
    required this.duck,
    required this.swingGrid,
    required this.lights,
    required this.drumPat,
    required this.bassPat,
    required this.chordPat,
    required this.melodyPat,
    required this.liveVoice,
    required this.liveMode,
    required this.liveLen,
  });
}

/// **이 목록의 순서가 화면 순서다.**
const List<GenreDef> kGenres = [
  GenreDef(
    key: 'lofi',
    label: '로파이',
    bpm: 78,
    kit: 'lofi',
    mode: 'minor',
    feel: '느긋하고 먼지 낀 — 공부할 때 틀어 두는',
    duck: 0.10,
    swingGrid: 16,
    lights: [0xFFFFB74D, 0xFFBA68C8, 0xFF4DB6AC],
    drumPat: 'Lofi Chorus',
    bassPat: 'Lofi Walk C',
    chordPat: 'Lofi Keys C',
    melodyPat: 'Lofi Hook',
    liveVoice: 'epiano',
    liveMode: 'single',
    liveLen: 1,
  ),
  GenreDef(
    key: 'house',
    label: '하우스',
    bpm: 124,
    kit: 'k909',
    mode: 'minor',
    feel: '네 박에 쿵쿵 — 몸이 움직이는',
    duck: 0.42,
    swingGrid: 16,
    lights: [0xFF42A5F5, 0xFF26C6DA, 0xFFEC407A],
    drumPat: 'House Chorus',
    bassPat: 'House Off C',
    chordPat: 'House Stab C',
    melodyPat: 'House Lead C',
    liveVoice: 'stab',
    liveMode: 'chord',
    liveLen: 0,
  ),
  GenreDef(
    key: 'hiphop',
    label: '힙합',
    bpm: 88,
    kit: 'k808',
    mode: 'minor',
    feel: '묵직하게 끄는 — 고개가 끄덕여지는',
    // 붐뱁 하이햇이 8분이라 16분으로 밀면 안 움직인다(측정 결과 20%)
    duck: 0.14,
    swingGrid: 8,
    lights: [0xFFFF7043, 0xFF7E57C2, 0xFFFFCA28],
    drumPat: 'Boom Chorus',
    bassPat: '808 Chorus',
    chordPat: 'Dusty Keys C',
    melodyPat: 'Hip Riff C',
    liveVoice: 'epiano',
    liveMode: 'single',
    liveLen: 1,
  ),
  GenreDef(
    key: 'citypop',
    label: '시티팝',
    bpm: 106,
    kit: 'acoustic',
    mode: 'minor',
    feel: '반짝이는 밤 도시 — 드라이브',
    duck: 0.08,
    swingGrid: 8,
    lights: [0xFFFF8A65, 0xFF4FC3F7, 0xFFF06292],
    drumPat: 'City Chorus',
    bassPat: 'City Slap C',
    chordPat: 'City Maj C',
    melodyPat: 'City Hook C',
    liveVoice: 'epiano',
    liveMode: 'chord',
    liveLen: 1,
  ),
  GenreDef(
    key: 'ballad',
    label: '발라드',
    bpm: 68,
    kit: 'acoustic',
    mode: 'minor',
    feel: '느리고 넓게 — 이야기하는',
    // 사람이 친 드럼은 안 비켜 준다
    duck: 0,
    swingGrid: 8,
    lights: [0xFF9FA8DA, 0xFFFFF176, 0xFFCE93D8],
    drumPat: 'Ballad Chorus',
    bassPat: 'Ballad Long C',
    chordPat: 'Ballad Keys C',
    melodyPat: 'Ballad Line C',
    liveVoice: 'piano',
    liveMode: 'chord',
    liveLen: 2,
  ),
  GenreDef(
    key: 'rock',
    label: '록',
    bpm: 138,
    kit: 'rock',
    mode: 'minor',
    feel: '거칠고 밀어붙이는 — 기타가 앞에',
    duck: 0,
    swingGrid: 8,
    lights: [0xFFEF5350, 0xFFFFFFFF, 0xFFFFA726],
    drumPat: 'Rock Chorus',
    bassPat: 'Rock Drive C',
    chordPat: 'Rock Power C',
    melodyPat: 'Rock Riff C',
    liveVoice: 'guitar',
    liveMode: 'single',
    liveLen: 1,
  ),
  GenreDef(
    key: 'trap',
    label: '트랩',
    bpm: 140,
    kit: 'k808',
    mode: 'minor',
    feel: '잘게 쪼갠 하이햇 — 저음이 크게',
    duck: 0.32,
    swingGrid: 16,
    lights: [0xFF7C4DFF, 0xFF00E5FF, 0xFFFF4081],
    drumPat: 'Trap Hook',
    bassPat: 'Trap 808 H',
    chordPat: 'Trap Pad H',
    melodyPat: 'Trap Bell H',
    liveVoice: 'bell',
    liveMode: 'single',
    liveLen: 0,
  ),
  GenreDef(
    key: 'proghouse',
    label: '프로그하우스',
    bpm: 128,
    kit: 'k909',
    mode: 'minor',
    feel: '길게 쌓아 올리는 — 터지는 순간',
    // 이 장르는 펌핑이 곧 정체성이다
    duck: 0.50,
    swingGrid: 16,
    lights: [0xFF29B6F6, 0xFF66BB6A, 0xFF5C6BC0],
    drumPat: 'Prog Drop',
    bassPat: 'Prog Bass D',
    chordPat: 'Prog Pad D',
    melodyPat: 'Prog Lead D',
    liveVoice: 'pluck',
    liveMode: 'arp',
    liveLen: 0,
  ),
  GenreDef(
    key: 'pop',
    label: '팝',
    bpm: 104,
    kit: 'acoustic',
    mode: 'major',
    feel: '밝고 또렷한 — 따라 부르기 좋은',
    duck: 0.18,
    swingGrid: 8,
    lights: [0xFFFFD54F, 0xFF4FC3F7, 0xFFFF80AB],
    drumPat: 'Pop Chorus',
    bassPat: 'Pop Bass C',
    chordPat: 'Pop Keys C',
    melodyPat: 'Pop Voc C',
    liveVoice: 'piano',
    liveMode: 'chord',
    liveLen: 1,
  ),
  GenreDef(
    key: 'jazz',
    label: '재즈',
    bpm: 116,
    kit: 'acoustic',
    mode: 'minor',
    feel: '자유롭게 흔들리는 — 늦은 밤 가게',
    duck: 0,
    swingGrid: 8,
    lights: [0xFFFFB300, 0xFF8D6E63, 0xFF4DD0E1],
    drumPat: 'Jazz Solo',
    bassPat: 'Jazz Walk H',
    chordPat: 'Jazz Keys H',
    melodyPat: 'Jazz Sax H',
    liveVoice: 'piano',
    liveMode: 'single',
    liveLen: 1,
  ),
  GenreDef(
    key: 'drill',
    label: '드릴',
    bpm: 142,
    kit: 'k808',
    mode: 'minor',
    feel: '스네어가 늦게 떨어지는 — 어둡고 팽팽한',
    duck: 0.30,
    swingGrid: 16,
    lights: [0xFF5C6BC0, 0xFF26A69A, 0xFFEC407A],
    drumPat: 'Drill Hook',
    bassPat: 'Drill 808 H',
    chordPat: 'Drill Pad H',
    melodyPat: 'Drill Bell H',
    liveVoice: 'bell',
    liveMode: 'single',
    liveLen: 0,
  ),
  GenreDef(
    key: 'rnb',
    label: 'R&B',
    bpm: 92,
    kit: 'acoustic',
    mode: 'minor',
    feel: '뒤로 눕는 — 부드럽고 끈적한',
    duck: 0.10,
    swingGrid: 16,
    lights: [0xFFBA68C8, 0xFF4DD0E1, 0xFFFFB74D],
    drumPat: 'RnB Chorus',
    bassPat: 'RnB Bass C',
    chordPat: 'RnB Keys C',
    melodyPat: 'RnB Line C',
    liveVoice: 'epiano',
    liveMode: 'chord',
    liveLen: 1,
  ),
  GenreDef(
    key: 'disco',
    label: '디스코',
    bpm: 116,
    kit: 'acoustic',
    mode: 'minor',
    feel: '거울볼 아래 — 네 박에 쿵, 위로 튀는',
    duck: 0.12,
    swingGrid: 16,
    lights: [0xFFF06292, 0xFF4DD0E1, 0xFFFFD54F],
    drumPat: 'Disco Chorus',
    bassPat: 'Disco Bass C',
    chordPat: 'Disco Keys C',
    melodyPat: 'Disco Line C',
    liveVoice: 'epiano',
    liveMode: 'chord',
    liveLen: 0,
  ),
  GenreDef(
    key: 'gospel',
    label: '가스펠',
    bpm: 84,
    kit: 'acoustic',
    mode: 'major',
    feel: '넓게 흔들리는 — 오르간과 손뼉',
    duck: 0,
    swingGrid: 8,
    lights: [0xFF66BB6A, 0xFFFFCA28, 0xFF9575CD],
    drumPat: 'Gospel Chorus',
    bassPat: 'Gospel Bass C',
    chordPat: 'Gospel Keys C',
    melodyPat: 'Gospel Line C',
    liveVoice: 'organ',
    liveMode: 'chord',
    liveLen: 2,
  ),
  GenreDef(
    key: 'ambient',
    label: '엠비언트',
    bpm: 72,
    kit: 'lofi',
    mode: 'minor',
    feel: '거의 멈춘 — 배경처럼 깔리는',
    duck: 0.18,
    swingGrid: 8,
    lights: [0xFF80DEEA, 0xFFB39DDB, 0xFFA5D6A7],
    drumPat: 'Amb Perc',
    bassPat: 'Amb Sub',
    chordPat: 'Amb Pad A',
    melodyPat: 'Amb Bell A',
    liveVoice: 'pad',
    liveMode: 'chord',
    liveLen: 2,
  ),
  GenreDef(
    key: 'waltz',
    label: '왈츠',
    bpm: 132,
    kit: 'acoustic',
    mode: 'major',
    meter: '3/4', // 5단계 47/N — 왈츠는 3/4 판 라이브러리를 쓴다
    feel: '세 박에 빙글빙글 — 춤추듯 도는',
    duck: 0,
    swingGrid: 8,
    lights: [0xFFF48FB1, 0xFFFFF9C4, 0xFFB39DDB],
    drumPat: 'Waltz Chorus',
    bassPat: 'Waltz Walk',
    chordPat: 'Waltz Keys',
    melodyPat: 'Waltz Line',
    liveVoice: 'piano',
    liveMode: 'chord',
    liveLen: 1,
  ),
  GenreDef(
    key: 'ballad68',
    label: '흔들발라드',
    bpm: 76,
    kit: 'acoustic',
    mode: 'minor',
    meter: '6/8', // 5단계 47/N — 여섯 박을 셋씩 두 갈래로 센다(strongAt [0,6])
    feel: '여섯 박에 흔들흔들 — 배 젓듯 걷는 옛 발라드',
    duck: 0,
    swingGrid: 8,
    lights: [0xFFA1887F, 0xFFFFCC80, 0xFF90A4AE],
    drumPat: 'Sway Chorus',
    bassPat: 'Sway Walk',
    chordPat: 'Sway Keys',
    melodyPat: 'Sway Line',
    liveVoice: 'piano',
    liveMode: 'chord',
    liveLen: 2,
  ),
];

/// 키로 찾는다. 모르는 키는 **첫 장르**로 떨어진다(옛 파일이 안 죽게).
GenreDef genreDef(String key) =>
    kGenres.firstWhere((g) => g.key == key, orElse: () => kGenres.first);

/// 키가 표에 있는가 — 저장 파일을 읽을 때 쓴다.
bool isKnownGenre(String key) => kGenres.any((g) => g.key == key);

/// 그 스타일의 박자 키 — 모르는 스타일은 4/4.
String genreMeter(String key) => genreDef(key).meter;
