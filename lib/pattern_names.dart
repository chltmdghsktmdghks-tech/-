// 패턴 이름을 **한국어로 읽어 준다** (5단계 36/N).
//
// 화면 전체가 한국어인데 패턴 이름만 「Lofi Walk C」 「House Off V」 처럼 영어다.
// 악보를 몰라도 쓰라고 만든 앱에서 **제일 많이 누르는 칸**이 그렇다.
//
// ── 왜 표만 만들고 원래 이름은 안 바꾸나 ──
// 이름은 곧 **키**다. 씬의 클립·저장 파일·`kStylePrefixes` 가 전부 이 문자열로 묶여 있다.
// 바꾸면 예전에 저장한 곡이 자기 패턴을 못 찾는다. 그래서 **보여 줄 때만** 옮긴다.
//
// ── 낱말 단위로 옮긴다 ──
// 이름이 `<스타일> <구실> <자리>` 꼴이라 낱말 표 하나로 208개가 거의 다 덮인다.
// 모르는 낱말은 **그대로 둔다** — 억지로 옮기다 틀린 말을 만드는 것보다 낫다.

/// 낱말 → 한국어. 없으면 원래 낱말을 그대로 쓴다.
const Map<String, String> kPatternWord = {
  // 스타일
  'Lofi': '로파이', 'Lo-fi': '로파이', 'House': '하우스', 'Hip': '힙합',
  'City': '시티팝', 'Ballad': '발라드', 'Rock': '록', 'Trap': '트랩',
  'Prog': '프로그', 'Pop': '팝', 'Jazz': '재즈', 'Amb': '엠비언트',
  'Synthpop': '신스팝', 'Disco': '디스코', 'Funk': '펑크', 'Gfunk': '지펑크',
  'Drill': '드릴', 'Gospel': '가스펠', 'Waltz': '왈츠', 'Sway': '흔들발라드',
  // 장르 칩에는 「R&B」로 적지만 **패턴 이름에는 한글로** 쓴다 —
  // 화면이 전부 한국어인데 목록 한 줄만 알파벳이면 그게 더 눈에 걸린다.
  // (짧은 꼴에서는 스타일 낱말이 떨어져 나가 거의 안 보인다.)
  'RnB': '알앤비',
  'French': '프렌치', 'Latin': '라틴',

  // 구간
  'Intro': '인트로', 'Verse': '벌스', 'Chorus': '코러스', 'Bridge': '브릿지',
  'Break': '브레이크', 'Outro': '아웃트로', 'Pre': '프리', 'Build': '빌드',
  'Drop': '드롭', 'Fill': '필인', 'Head': '헤드', 'Solo': '솔로',

  // 구실 — 무엇을 하는 패턴인가
  'Bass': '베이스', 'Sub': '서브', 'Sub2': '서브2', 'Walk': '워킹',
  'Keys': '건반', 'Pad': '패드', 'Lead': '리드', 'Hook': '훅',
  'Arp': '아르페지오', 'Stab': '스탭', 'Stabs': '스탭', 'Pluck': '플럭',
  'Riff': '리프', 'Line': '라인', 'Comp': '컴핑', 'Groove': '그루브',
  'Rhythm': '리듬', 'Beat': '비트', 'Chop': '찹', 'Swell': '스웰',
  'Layer': '레이어', 'Slide': '슬라이드', 'Trill': '트릴', 'Roll': '롤',
  'Bounce': '바운스', 'Pump': '펌프', 'Drive': '드라이브', 'Boom': '붐',
  'Bap': '뱁', 'Slap': '슬랩', 'Power': '파워', 'Backbeat': '백비트',

  // 악기
  'Gtr': '기타', 'Sax': '색소폰', 'Vib': '비브라폰', 'Bell': '벨',
  'Harp': '하프',
  'Str': '스트링',
  'Str2': '스트링2',
  'Org': '오르간',
  'Brass': '브라스',
  'Perc': '퍼커션',
  'Voc': '보컬', 'Kick': '킥', 'Snare': '스네어', 'Hat': '하이햇',
  'Hats': '하이햇', 'Clap': '클랩', 'Rim': '림', 'Tom': '탐',
  'Crash': '크래시', 'Ride': '라이드', '808': '808',

  // 꾸밈말
  'Plain': '단순', 'Simple': '쉽게', 'Sparse': '성글게', 'Big': '크게',
  'Wide': '넓게', 'Long': '길게', 'Short': '짧게', 'Slow': '느리게',
  'Half-time': '하프타임', 'Double': '더블', 'Shuffle': '셔플',
  'Swing': '스윙', 'Syncopated': '엇박', 'Off': '오프비트',
  'Offbeat': '오프비트', 'Dusty': '먼지낀', 'Minor': '단조', 'Maj': '장조',
  'Octave': '옥타브', 'Root': '근음', 'Pentatonic': '5음', 'Leaps': '도약',
  'Four': '네박', 'In': '인', 'Up': '업', 'Down': '다운', 'Bk': '백',
  '4/4': '4/4', '4ths': '4도', '8ths': '8분', '8': '8',
};

/// 이름 뒤에 붙는 **한 글자 표시**. 같은 구실의 패턴이 구간마다 다를 때 쓴다
/// (`Lofi Keys C` = 코러스용 건반, `Lofi Keys V` = 벌스용 건반).
/// 무엇의 약자인지 모르면 화면에서 「C」 「V」 는 그냥 소음이다.
const Map<String, String> kPatternSuffix = {
  'C': '코러스용',
  'V': '벌스용',
  'I': '인트로용',
  'B': '브릿지용',
  'P': '프리코러스용',
  'H': '헤드용',
  'O': '아웃트로용',
  'S': '솔로용',
  // A·D·G 는 안 넣는다 — 구간 표시가 아니라 **조 이름**이거나 그냥 갈래 표시다
  // (`Prog Bass G`, `Amb Pad A`). 넣었더니 「프로그 베이스 · G」 처럼
  // 있지도 않은 '구간'을 만들어 냈다.
};

/// 스타일 낱말 — 짧게 쓸 때 **떼어 낸다**. 한 곡은 스타일 하나라 트랙마다
/// 「로파이 …」 를 네 번 반복해 봐야 자리만 먹는다.
const Set<String> kStyleWords = {
  'Lofi',
  'Lo-fi',
  'House',
  'Hip',
  'City',
  'Ballad',
  'Rock',
  'Trap',
  'Prog',
  'Pop',
  'Jazz',
  'Amb',
  'Synthpop',
  'Drill',
  'RnB',
  'Disco',
  'Gospel',
  'Waltz',
  'Sway',
};

/// 자리 표시의 **짧은 꼴** — 좁은 칸에서는 '용' 을 뗀다.
const Map<String, String> kPatternSuffixShort = {
  'C': '코러스',
  'V': '벌스',
  'I': '인트로',
  'B': '브릿지',
  'P': '프리',
  'H': '헤드',
  'O': '아웃트로',
  'S': '솔로',
};

/// 낱말로 쪼개면 어색해지는 이름 몇 개는 **통째로** 적어 둔다.
/// (`Call & Answer` 를 낱말로 옮기면 「주고 & 받기」 같은 이상한 말이 된다)
const Map<String, String> kPatternWhole = {'Call & Answer': '묻고 답하기'};

/// 화면에 보일 이름. 못 옮기는 낱말은 그대로 남는다.
///
/// 보기: `Lofi Walk C` → `로파이 워킹 · 코러스용`
///       `Amb Pad A`   → `엠비언트 패드 A`
String patternLabel(String name) {
  final whole = kPatternWhole[name];
  if (whole != null) return whole;

  final parts = name.split(' ');
  if (parts.isEmpty) return name;

  // 마지막 낱말이 한 글자면 '자리' 표시로 본다 — 뒤에 가운뎃점을 찍어 떼어 놓는다
  String? tail;
  var body = parts;
  if (parts.length > 1 && parts.last.length == 1) {
    tail = kPatternSuffix[parts.last];
    if (tail != null) body = parts.sublist(0, parts.length - 1);
  }

  final out = [for (final w in body) kPatternWord[w] ?? w].join(' ');
  return tail == null ? out : '$out · $tail';
}

/// 좁은 칸(트랙 줄)용 **짧은 이름**. 스타일 낱말을 떼고 '용' 도 뗀다.
///
/// 보기: `Lofi Walk C` → `워킹 코러스` · `Lofi Chorus` → `코러스`
/// 한 곡은 스타일 하나다 — 트랙 네 줄에 「로파이」 가 네 번 나올 이유가 없다.
String patternShort(String name) {
  if (kPatternWhole.containsKey(name)) return kPatternWhole[name]!;

  var parts = name.split(' ');
  if (parts.length > 1 && kStyleWords.contains(parts.first)) {
    parts = parts.sublist(1);
  }
  if (parts.isEmpty) return patternLabel(name);

  String? tail;
  if (parts.length > 1 && parts.last.length == 1) {
    tail = kPatternSuffixShort[parts.last];
    if (tail != null) parts = parts.sublist(0, parts.length - 1);
  }
  final out = [for (final w in parts) kPatternWord[w] ?? w].join(' ');
  return tail == null ? out : '$out $tail';
}
