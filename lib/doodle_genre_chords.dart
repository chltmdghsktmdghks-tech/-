// 두들플레이 **장르별 코드 팔레트** — 데이터만 둔다(순수 Dart, 의존 없음).
// (사용자 피드백 2026-10-01 #3 "장르마다 코드가 달라야 한다")
//
// 예전엔 장르와 무관하게 같은 풀(I V vi IV …)에서 뽑고 「재즈 계열」만 ii-V-I 가 섞였다.
// 그래서 하우스도 로파이도 힙합도 똑같이 들렸다. 이제 장르마다 **고유한 진행 풀 + 코드 색 +
// 이동 성격**을 갖는다.
//
// 근거
//  · 웹 원본 app.html `SONG_FORMS` 주석(읽기만 했다): 로파이 벌스 iv-VII-III-VI(재즈 턴어라운드) /
//    코러스 ii°-v-i-VI · 하우스 i-VI 최면 / 코러스 VI-VII-III-v · 힙합 벌스 i-VI 두 코드 /
//    코러스 iv-VII-i · 시티팝 VI-VII-III(=IV-V-I) / iv-VII-III-i(=ii-V-I-vi) · 발라드 i-VII-VI-v 하행 /
//    VI-III-VII-i · 록 i-VII 파워코드 / VI-VII-i 앤섬.
//  · 엔진 기본 코드 판(patterns.dart `Lofi Keys V` = iv m7 · VII dom7 · III maj7 · VI maj7)과 같은
//    색채를 쓰도록 맞췄다 — 연주한 코드와 기본으로 깔리는 판이 한 장르로 들린다.
//
// 표기: 한 진행은 도수(0~6, 0=으뜸) 공백 구분. 뒤에 D 가 붙으면 그 도수 뿌리의 **도미넌트 7**
// (예: `1 4D 0 5` = ii · V7 · I · vi, 시티팝 `3 6D 2 5` = ii · V7 · I · IV 의 단조 버전).
// 세컨더리 도미넌트는 `0D`(→iv/ii 로 풀림) `2D`(→vi) 처럼 같은 방식으로 적는다.

/// 이동 성격(좌우 긴장/해결·대체코드가 이 성격을 따른다).
///  · `plain` — 일반. 다이아토닉 + V7.
///  · `loop`  — 반복 루프 장르(하우스·트랩·힙합…). 도미넌트 7·딤 화음을 안 쓴다 — 클래식 소리가 난다.
///  · `jazzy` — 재즈 계열. 세컨더리 도미넌트·5도권·ii-V 를 쓴다.
enum DoodleFlavor { plain, loop, jazzy }

class DoodleGenreChords {
  /// 코드 기본 두께 — 0 3화음 · 1 7th(maj7·m7·dom7) · 2 9th.
  /// (상하 제스처는 이제 색이 아니라 「대체코드」다. 색채는 장르가 정한다.)
  final int color;
  final DoodleFlavor flavor;

  /// 8마디를 4마디 되풀이로 채운다(최면적인 반복 장르).
  final bool loop8;

  /// 이웃 마디가 같은 코드로 붙어도 둔다(트랩의 i-i-VI-VII 처럼 한 코드에 머무는 진행).
  final bool repeatOk;

  /// 단조·장조 진행 풀.
  final List<String> minor;
  final List<String> major;

  const DoodleGenreChords({
    required this.color,
    required this.flavor,
    required this.minor,
    required this.major,
    this.loop8 = false,
    this.repeatOk = false,
  });
}

const Map<String, DoodleGenreChords> kDoodleGenreChords = {
  // 로파이 — 7th·9th·maj7 색채, 느슨한 ii-V. iv-VII-III-VI(재즈 턴어라운드)가 얼굴.
  'lofi': DoodleGenreChords(
    color: 2,
    flavor: DoodleFlavor.jazzy,
    minor: ['3 6 2 5', '1 4D 0 5', '2 5 1 4D', '5 6 2 0'],
    major: ['1 4D 0 5', '3 2 1 0', '2 5 1 4D', '0 5 1 4D'],
  ),
  // 하우스 — 단순 반복. i-VI-III-VII 류를 그대로 돌린다.
  'house': DoodleGenreChords(
    color: 0,
    flavor: DoodleFlavor.loop,
    loop8: true,
    minor: ['0 5 2 6', '0 5 0 5', '0 6 0 5', '0 2 5 6'],
    major: ['0 5 3 4', '0 3 0 3', '5 3 0 4', '0 5 0 3'],
  ),
  // 프로그레시브 하우스 — 길게 쌓이는 i-VI-III-VII, 같은 모양 반복.
  'proghouse': DoodleGenreChords(
    color: 0,
    flavor: DoodleFlavor.loop,
    loop8: true,
    minor: ['0 5 2 6', '0 2 5 6', '0 6 5 2', '5 6 0 2'],
    major: ['0 4 5 3', '0 5 3 4', '3 0 4 5', '0 3 5 4'],
  ),
  // 힙합 — 마이너 루프. i-VI 두 코드, 가끔 iv-VII 로 움직인다. 먼지 낀 7th.
  'hiphop': DoodleGenreChords(
    color: 1,
    flavor: DoodleFlavor.loop,
    loop8: true,
    minor: ['0 5 0 5', '0 3 0 6', '0 5 6 5', '0 6 5 6'],
    major: ['0 5 0 5', '0 3 0 3', '5 3 5 4', '0 5 3 3'],
    repeatOk: true,
  ),
  // 트랩 — 미니멀 마이너. 한 코드에 오래 머물고 어둡게 한 번 내려간다.
  'trap': DoodleGenreChords(
    color: 0,
    flavor: DoodleFlavor.loop,
    loop8: true,
    repeatOk: true,
    minor: ['0 0 5 6', '0 0 3 6', '0 5 0 6', '0 0 6 5'],
    major: ['0 0 5 3', '0 0 3 4', '5 5 3 4', '0 5 0 3'],
  ),
  // 드릴 — 트랩보다 더 어둡게. i 에 머물다 VI·VII 로 눌러 내린다.
  'drill': DoodleGenreChords(
    color: 0,
    flavor: DoodleFlavor.loop,
    loop8: true,
    repeatOk: true,
    minor: ['0 0 6 5', '0 6 0 5', '0 0 3 6', '0 0 5 5'],
    major: ['0 0 5 3', '5 5 3 3', '0 0 3 4', '0 3 0 5'],
  ),
  // 시티팝 — 복잡한 전개. 세컨더리 도미넌트(V7/ii=0D, V7/vi=2D)와 ii-V-I-vi.
  'citypop': DoodleGenreChords(
    color: 2,
    flavor: DoodleFlavor.jazzy,
    minor: ['5 6D 2 0', '3 6D 2 5', '2 0D 3 6D', '3 6D 2 0D'],
    major: ['3 4D 2 5', '3 4D 2D 5', '0 2D 5 3', '1 4D 2 5'],
  ),
  // 재즈 — ii-V-I 와 5도권(VI→ii→V→i, iii→vi→ii→V).
  'jazz': DoodleGenreChords(
    color: 1,
    flavor: DoodleFlavor.jazzy,
    minor: ['1 4D 0 5', '5 1 4D 0', '2 5 1 4D', '0 5 1 4D'],
    major: ['1 4D 0 5', '2 5 1 4D', '0 5 1 4D', '5 1 4D 0'],
  ),
  // 발라드 — 다이아토닉 서정. 하행(i-VII-VI-v)과 들어올림(VI-III-VII-i). 꾸밈 없는 3화음.
  'ballad': DoodleGenreChords(
    color: 0,
    flavor: DoodleFlavor.plain,
    minor: ['0 6 5 4', '5 2 6 0', '0 5 3 6', '0 2 5 6'],
    major: ['0 2 3 4', '0 4 5 2', '3 4 2 5', '5 2 3 4'],
  ),
  // 6/8 발라드 — 흔들리며 걷는 서정. 3화음, 완만한 하행.
  'ballad68': DoodleGenreChords(
    color: 0,
    flavor: DoodleFlavor.plain,
    minor: ['0 5 3 6', '0 6 5 4', '5 2 6 0', '0 3 6 2'],
    major: ['0 4 5 3', '0 5 3 4', '0 3 4 0', '5 3 0 4'],
  ),
  // 록 — 파워풀. 장조 I-IV-V, 단조 i-VII-VI-VII / i-iv-VII (기타는 파워코드로 친다).
  'rock': DoodleGenreChords(
    color: 0,
    flavor: DoodleFlavor.plain,
    minor: ['0 6 5 6', '0 3 6 0', '0 5 6 0', '0 3 6 5'],
    major: ['0 3 4 3', '0 3 4 0', '0 4 3 0', '0 3 0 4'],
  ),
  // 팝 — 밝은 장조의 정석. I-V-vi-IV 계열.
  'pop': DoodleGenreChords(
    color: 0,
    flavor: DoodleFlavor.plain,
    minor: ['0 5 2 6', '5 3 0 4', '0 2 6 5', '0 6 5 3'],
    major: ['0 4 5 3', '3 0 4 5', '0 5 3 4', '5 3 0 4'],
  ),
  // R&B — 9th 가 깔리는 네오소울. i-iv 를 오가고 ii-V 로 돌아온다.
  'rnb': DoodleGenreChords(
    color: 2,
    flavor: DoodleFlavor.jazzy,
    minor: ['0 3 6 5', '3 0 5 6', '0 5 3 6', '1 4D 0 3'],
    major: ['1 4D 0 3', '0 5 1 4D', '3 4D 2 5', '0 3 1 4D'],
  ),
  // 가스펠 — I-IV-I-V 의 쌓아 올림, 6-2-5-1 로 감동을 만든다. 7th 색.
  'gospel': DoodleGenreChords(
    color: 1,
    flavor: DoodleFlavor.jazzy,
    minor: ['0 3 0 4D', '5 1 4D 0', '0 3 6 2', '0 5 3 4D'],
    major: ['0 3 0 4', '0 5 1 4D', '0 3 1 4D', '5 1 4D 0'],
  ),
  // 디스코 — 5도권으로 미끄러지는 펑키 7th (VI→ii→V→i, "I Will Survive" 식).
  'disco': DoodleGenreChords(
    color: 1,
    flavor: DoodleFlavor.jazzy,
    minor: ['5 1 4D 0', '0 3 6 2', '0 3 0 6', '2 5 1 4D'],
    major: ['5 1 4D 0', '0 3 1 4D', '0 5 3 4D', '3 6D 2 5'],
  ),
  // 앰비언트 — 느리게 한 코드씩 번진다. maj7 숨결, 급한 해결이 없다.
  'ambient': DoodleGenreChords(
    color: 1,
    flavor: DoodleFlavor.loop,
    loop8: true,
    minor: ['0 5 0 6', '0 2 5 2', '0 5 3 5', '5 0 2 6'],
    major: ['0 3 0 5', '0 5 3 5', '3 0 3 4', '0 2 3 0'],
  ),
  // 왈츠 — 3박 한 마디에 한 코드. I-IV-V 의 정통 순환.
  'waltz': DoodleGenreChords(
    color: 0,
    flavor: DoodleFlavor.plain,
    minor: ['0 3 4 0', '0 5 3 4', '0 6 5 4', '0 3 6 0'],
    major: ['0 3 0 4', '0 5 3 4', '0 4 0 3', '0 3 4 0'],
  ),
};
