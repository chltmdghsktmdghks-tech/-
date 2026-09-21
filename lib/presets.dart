// 장르 프리셋 — (라벨, bpm, 드럼키트, 드럼패턴, 베이스패턴, 코드패턴, 멜로디패턴).
// 웹 `GENRE_PRESETS` 의 대표 섹션(대개 코러스/훅)을 그대로 짝지은 것.
//
// 원래 `main.dart` 시험 화면 안에 있던 표(`kTestSongPatterns`)를 여기로 옮겼다 —
// 5단계 3/N 부터 **씬(장르 전환)** 도 같은 표를 쓴다. 두 군데에 같은 표를 두면
// 한쪽만 고치는 날이 온다.
//
// 순수 Dart 다(Flutter 의존 없음) — `dart run tool/*.dart` 에서도 쓸 수 있다.

import 'genres.dart';

typedef GenrePreset = (String, double, String, String, String, String, String);

/// **`kGenres` 에서 뽑아 쓴다** (계획 7-1). 예전엔 여기에 라벨·템포·키트를 또 적었는데,
/// 그러면 `kSongGenres` 와 둘 중 한쪽만 고치는 날이 온다(실제로 같은 값이 두 벌 있었다).
final List<GenrePreset> kGenrePresets = [
  for (final g in kGenres)
    (g.label, g.bpm, g.kit, g.drumPat, g.bassPat, g.chordPat, g.melodyPat),
];

/// 곡 스타일 — (키, 표시이름, 템포, 드럼 키트, 조).
///
/// **곡 하나는 스타일 하나다.** 구간(인트로·벌스·코러스…)마다 장르가 바뀌면 곡이 아니라
/// 짜깁기가 된다 — 5단계 5/N 에서 그렇게 만들었다가 되돌렸다.
///
/// 앞 6개는 `song.dart kSongForms`(배열형 — 드럼/베이스/코드/멜로디 4트랙 고정),
/// 뒤 5개는 `kObjectSongForms`(객체형 — 곡마다 편성이 다르다. 트랩은 808·패드·브라스·
/// 벨·플럭 6트랙). 스타일을 고르면 **편성 자체가 그 곡의 것으로 바뀐다.**
///
/// 조(mode)까지 들고 있는 이유: **팝만 장조**다. 안 맞추면 완전히 다른 곡이 된다.
typedef SongGenre = (String, String, double, String, String);

/// **`kGenres` 에서 뽑아 쓴다** — 순서도 그 표의 순서다.
final List<SongGenre> kSongGenres = [
  for (final g in kGenres) (g.key, g.label, g.bpm, g.kit, g.mode),
];

/// 객체형 곡의 슬롯 이름 → 화면에 보일 트랙 이름.
const Map<String, String> kSlotLabel = {
  'drum': '드럼',
  'perc': '퍼커션',
  'bass': '베이스',
  'b808': '808 베이스',
  'sub': '서브 베이스',
  'pad': '패드',
  'brass': '브라스',
  'str': '스트링',
  'str2': '스트링 2',
  'piano': '피아노',
  'gtr': '기타',
  'stab': '스탭',
  'vib': '비브라폰',
  'bell': '벨',
  'plk': '플럭',
  'arp': '아르페지오',
  'keys': '건반',
  'lead': '리드',
  'sax': '색소폰',
  'harp': '하프',
  'voc': '보컬',
  'org': '오르간',
};

SongGenre songGenreOf(String key) =>
    kSongGenres.firstWhere((g) => g.$1 == key, orElse: () => kSongGenres.first);

/// 트랙 타입에 맞는 패턴 이름을 프리셋에서 꺼낸다.
String? presetPatternFor(GenrePreset p, String type) {
  switch (type) {
    case 'drum':
      return p.$4;
    case 'bass':
      return p.$5;
    case 'chord':
      return p.$6;
    case 'melody':
      return p.$7;
  }
  return null;
}

/// 패턴 이름 → 어느 스타일 것인가 (5단계 23/N).
///
/// 패턴 이름은 전부 스타일 머리말로 시작한다('Lofi Chorus', 'Trap Hook'…).
/// 목록이 드럼만 72개라, **이 곡의 스타일 것부터** 보여 주려고 만든 표다.
/// 여기 없는 머리말(Shuffle·Backbeat·Arp…)은 스타일에 안 묶인 **기본 패턴**이다.
///
/// ⚠️ **장르를 더할 때 여기를 빠뜨리면 조용히 두 가지가 망가진다** (2026-08-30 에 겪음):
///   ① 그 장르 것이 목록 위로 안 올라온다 — 208개 중에서 찾아야 한다
///   ② `patternIsBasic` 이 그 이름들을 「어느 스타일도 아닌 기본 패턴」으로 봐서
///      **다른 모든 장르의 목록에 섞여 나온다**
/// 드릴·R&B·디스코·가스펠 넷이 그 상태였다. `genre_check_test 5-j` 가 지킨다.
const Map<String, List<String>> kStylePrefixes = {
  'lofi': ['Lofi', 'Lo-fi'],
  'house': ['House'],
  'hiphop': ['Boom', '808', 'Dusty', 'Hip', 'Gfunk'],
  // 'Disco' 는 예전엔 여기 있었다 — 그때는 디스코가 장르가 아니라 시티팝의
  // 곁가지였기 때문이다. 이제 제 장르가 생겼으니 돌려준다.
  'citypop': ['City', 'Synthpop', 'French'],
  'ballad': ['Ballad'],
  'rock': ['Rock'],
  'trap': ['Trap'],
  'proghouse': ['Prog'],
  'pop': ['Pop'],
  'jazz': ['Jazz'],
  'drill': ['Drill'],
  'rnb': ['RnB'],
  'disco': ['Disco'],
  'gospel': ['Gospel'],
  'ambient': ['Amb'],
  'waltz': ['Waltz'],
  'ballad68': ['Sway'],
};

/// 그 패턴이 [genre] 스타일 것인가.
bool patternIsStyle(String name, String genre) {
  final ps = kStylePrefixes[genre];
  if (ps == null) return false;
  for (final p in ps) {
    if (name.startsWith(p)) return true;
  }
  return false;
}

/// 어느 스타일에도 안 묶인 기본 패턴인가.
bool patternIsBasic(String name) {
  for (final ps in kStylePrefixes.values) {
    for (final p in ps) {
      if (name.startsWith(p)) return false;
    }
  }
  return true;
}
