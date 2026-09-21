// 콘텐츠 팩 — **장르를 묶음으로 관리한다.** (Phase 5 · 개선 계획 7-2)
//
// 계획 7-2: 「콘텐츠 시스템은 나중에 Pack 으로 확장할 수 있어야 합니다. 하지만
// Phase 5에서는 **결제 기능을 먼저 만들지 마십시오.** 먼저 콘텐츠를 독립적인
// 패키지 단위로 관리할 수 있게 만드는 것이 우선입니다.」
//
// 그래서 여기에는 값도, 잠금도, 무료/유료 구분도 없다. **묶음과 이름뿐**이다.
//
// ── 묶는 기준 ──
// 「무엇을 만들고 싶은가」로 묶었다. 음악 이론이나 연도가 아니라, 처음 여는 사람이
// 자기 자리를 찾을 수 있는 말로 묶어야 한다(고르는 화면의 소제목이 곧 이것이다).
//
// ── 나눌 수 있는 상태인가 ──
// 재 봤다: 장르가 쓰는 패턴 168개 중 **둘 이상이 같이 쓰는 것은 0개**다.
// 즉 팩 하나를 통째로 들어내도 남은 곡은 멀쩡하다. `pack_check_test` 가 그걸 지킨다.
// (라이브러리에는 어느 곡도 안 쓰는 패턴이 72개 더 있다 — 그건 **공용**이다.
//  사용자가 편집기에서 직접 고르라고 둔 것이라 어느 팩에도 안 속한다.)
import 'genres.dart';

class Pack {
  /// 저장·설정에 남을 수 있는 키 — 바꾸지 말 것.
  final String id;

  /// 고르는 화면의 소제목.
  final String label;

  /// 이 묶음이 무엇인지 한 줄. 장르 설명과 같은 말투로.
  final String blurb;

  /// 이 팩이 들고 있는 장르 키들(`GenreDef.key`).
  final List<String> genres;

  const Pack({
    required this.id,
    required this.label,
    required this.blurb,
    required this.genres,
  });
}

/// **이 순서가 고르는 화면의 순서다.**
const List<Pack> kPacks = [
  Pack(
    id: 'starter',
    label: '느긋하게',
    blurb: '처음이라면 여기서',
    genres: ['lofi', 'pop', 'ballad', 'waltz', 'ballad68'],
  ),
  Pack(
    id: 'beat',
    label: '비트',
    blurb: '랩을 얹거나 고개를 끄덕이거나',
    genres: ['hiphop', 'trap', 'drill'],
  ),
  Pack(
    id: 'club',
    label: '춤',
    blurb: '네 박에 쿵쿵',
    genres: ['house', 'proghouse', 'disco'],
  ),
  Pack(id: 'city', label: '도시', blurb: '부드럽고 반짝이는', genres: ['citypop', 'rnb']),
  Pack(
    id: 'band',
    label: '연주',
    blurb: '사람이 치는 소리',
    genres: ['rock', 'jazz', 'gospel'],
  ),
  Pack(id: 'air', label: '공기', blurb: '깔아 두는', genres: ['ambient']),
];

/// 이 장르가 속한 팩. 어디에도 없으면 null — **`pack_check_test` 가 그걸 막는다.**
Pack? packOf(String genreKey) {
  for (final p in kPacks) {
    if (p.genres.contains(genreKey)) return p;
  }
  return null;
}

/// 팩 순서대로 편 장르 목록. 고르는 화면이 이 순서로 그린다.
List<(Pack, List<GenreDef>)> packedGenres() => [
  for (final p in kPacks) (p, [for (final k in p.genres) genreDef(k)]),
];
