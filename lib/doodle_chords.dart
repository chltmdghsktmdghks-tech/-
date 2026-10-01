// 두들플레이 코드 기믹의 **순수 로직** — 화면(doodle_play_view.dart)과 떼어 둔다.
// (사용자 지시서 2026-09-29 (12) 2단계)
//
//  · 탭 = 리듬(세기 균일). 어느 코드가 울리는지는 **마디마다 깔린 진행**이 정한다.
//    깔리는 진행은 **장르마다 다르다**(`doodle_genre_chords.dart` — 로파이 7th·ii-V, 하우스 단순 반복,
//    시티팝 세컨더리 도미넌트, 록 I-IV-V …). 코드의 두께(3화음/7th/9th)도 장르가 정한다.
//  · 좌우(X) = 진행 방향. 한 마디의 **착지(마지막) 탭**이 왼쪽이면 다음 마디를 긴장으로,
//    오른쪽이면 해결로 한 걸음 갈아 끼운다.
//  · 상하(Y) = **대체코드(substitute)**. 위 = 기능이 비슷한 다른 코드(I↔vi/iii, IV↔ii, V↔vii° …),
//    아래 = 원래 코드. 좌우처럼 **다음 마디에 영향**을 준다 — 대체코드에서 이어지는 걸음을 걷는다.
//  · 한 박에 코드 둘(2026-10-01 #5) — 한 박의 머리를 친 뒤 같은 박의 **반박 자리**를 치면(빠르게
//    두 번 쳐도 같다) 반박에는 다른 코드가 들어간다(`doodleHalfChord`).
//
// 코드 하나는 (다이아토닉 도수, 종류 덮어쓰기) 로 적는다. 세컨더리 도미넌트는
// `(2,'dom7')`(= III7, 다음 vi 로 가는 V/vi)처럼 **도수 뿌리 + dom7 종류**로 표현해서
// 저장 형식(코드 줄 `[도수, 칸, 길이, 세기, 종류글]`)을 그대로 쓴다.
import 'dart:math' as math;

import 'doodle_genre_chords.dart';
import 'meter.dart' show MeterDef;
import 'theory.dart';

/// 한 마디에 깔린 코드.
class DoodleChordPick {
  /// 다이아토닉 도수 0~6.
  final int degree;

  /// 종류 덮어쓰기('dom7' 등). null 이면 그 도수의 기본 3화음.
  final String? type;
  const DoodleChordPick(this.degree, [this.type]);

  @override
  bool operator ==(Object other) =>
      other is DoodleChordPick && other.degree == degree && other.type == type;
  @override
  int get hashCode => Object.hash(degree, type);
  @override
  String toString() =>
      'DoodleChordPick($degree${type == null ? '' : ',$type'})';
}

/// 장르 팔레트(`kDoodleGenreChords`)가 **없는** 장르 중 세컨더리 도미넌트를 써도 어울리는 것.
/// (팔레트가 있는 장르는 팔레트의 `flavor` 가 정한다.)
const Set<String> _kJazzy = {'lofi', 'citypop', 'jazz', 'rnb', 'gospel'};

bool _isMajor(String mode) => mode == 'major';

/// 이 장르의 이동 성격. 팔레트가 있으면 그것, 없으면 [_kJazzy] 로 갈린다.
DoodleFlavor _flavorOf(String genre) =>
    kDoodleGenreChords[genre]?.flavor ??
    (_kJazzy.contains(genre) ? DoodleFlavor.jazzy : DoodleFlavor.plain);

/// 이 장르 코드의 **기본 두께** — 0 3화음 · 1 7th · 2 9th. 팔레트 없는 장르는 0.
/// 연주·저장·이름표가 전부 이 값을 같이 쓴다(소리·적힌 것·보이는 이름이 한 곳에서 나온다).
int doodleGenreColor(String genre) => kDoodleGenreChords[genre]?.color ?? 0;

List<DoodleChordPick> _parseProg(String s) => [
  for (final t in s.trim().split(RegExp(r'\s+')))
    t.endsWith('D')
        ? DoodleChordPick(int.parse(t.substring(0, t.length - 1)), 'dom7')
        : DoodleChordPick(int.parse(t)),
];

/// 장르 [genre] 의 [mode] 진행 풀(마디 4개짜리들). 팔레트가 없으면 null.
List<List<DoodleChordPick>>? doodleGenrePool(String genre, String mode) {
  final g = kDoodleGenreChords[genre];
  if (g == null) return null;
  return [for (final s in (_isMajor(mode) ? g.major : g.minor)) _parseProg(s)];
}

// ── 기본 진행 풀 ── (도수 0~6, 다이아토닉만 — 장르 없으면 이 풀)

const List<List<int>> _kMajor4 = [
  [0, 4, 5, 3], // I V vi IV
  [0, 5, 3, 4], // I vi IV V
  [0, 3, 5, 4], // I IV vi V
  [5, 3, 0, 4], // vi IV I V
  [0, 2, 3, 4], // I iii IV V
  [0, 3, 4, 3], // I IV V IV
];
const List<List<int>> _kMinor4 = [
  [0, 5, 2, 6], // i VI III VII
  [0, 6, 5, 6], // i VII VI VII
  [0, 3, 6, 2], // i iv VII III
  [0, 3, 4, 0], // i iv v i
  [0, 5, 3, 6], // i VI iv VII
];
const List<List<int>> _kMajor2 = [
  [0, 4],
  [0, 3],
  [0, 5],
  [3, 4],
];
const List<List<int>> _kMinor2 = [
  [0, 6],
  [0, 5],
  [0, 3],
  [5, 6],
];

/// 재즈 계열 장르 전용 — 2·5·1 이 들어간 진행.
const List<List<int>> _kMajorJazz4 = [
  [1, 4, 0, 5], // ii V I vi
  [0, 5, 1, 4], // I vi ii V
  [2, 5, 1, 4], // iii vi ii V
];
const List<List<int>> _kMinorJazz4 = [
  [1, 4, 0, 0], // ii° V i i
  [0, 3, 6, 2], // i iv VII III
];

/// [bars] 마디짜리 **기본 진행**을 뽑는다. [rng] 를 바꿔 끼우면 "매번 다르게"가 된다.
/// 후보 풀은 조(장/단)·**장르**로 갈린다 — 장르마다 고유한 팔레트(`kDoodleGenreChords`)에서 뽑고,
/// 팔레트가 없는 장르(빈 문자열 포함)는 단순 다이어토닉 풀이다.
List<DoodleChordPick> doodleBasePlan({
  required String mode,
  required int bars,
  String genre = '',
  math.Random? rng,
}) {
  final r = rng ?? math.Random();
  final major = _isMajor(mode);
  final prof = kDoodleGenreChords[genre];
  final jazzy = _flavorOf(genre) == DoodleFlavor.jazzy;
  List<T> pick<T>(List<List<T>> pool) => pool[r.nextInt(pool.length)];

  List<DoodleChordPick> seq;
  if (prof != null) {
    final pool = doodleGenrePool(genre, mode)!;
    final a = pick(pool);
    if (bars <= 2) {
      seq = a.take(2).toList();
    } else if (bars <= 4) {
      seq = a;
    } else if (prof.loop8) {
      // 최면적인 반복 장르 — 앞 넷을 그대로 한 번 더. 달라지는 건 사용자의 좌우·대체뿐이다.
      seq = [...a, ...a];
    } else {
      // 8마디 — 앞 넷을 되풀이하되 끝을 다른 진행의 끝으로 바꿔 한 바퀴 돈 느낌을 준다.
      final b = pick(pool);
      seq = [...a, ...a.take(2), b[2], b[3]];
    }
  } else {
    List<int> pickDeg(List<List<int>> pool) => pool[r.nextInt(pool.length)];
    List<int> degs;
    if (bars <= 2) {
      degs = pickDeg(major ? _kMajor2 : _kMinor2);
    } else {
      final pool = [
        ...(major ? _kMajor4 : _kMinor4),
        if (jazzy) ...(major ? _kMajorJazz4 : _kMinorJazz4),
      ];
      final a = pickDeg(pool);
      if (bars <= 4) {
        degs = a;
      } else {
        final b = pickDeg(pool);
        degs = [...a, ...a.take(2), b[2], b[3]];
      }
    }
    seq = [for (final d in degs) DoodleChordPick(d)];
  }
  final out = [for (var i = 0; i < bars; i++) seq[i % seq.length]];
  // 재즈 계열은 **토닉으로 가는 V 를 V7 으로** — 단조의 v(단3화음)는 해결감이 약하고, ii-V-I 의 V 는
  // 7음이 있어야 I 로 「풀린다」. 판이 도니까 마지막 마디의 V 도 첫 마디 I 로 이어진다.
  if (jazzy) {
    for (var i = 0; i < out.length; i++) {
      final nxt = out[(i + 1) % out.length];
      if (out[i].degree == 4 && out[i].type == null && nxt.degree == 0) {
        out[i] = const DoodleChordPick(4, 'dom7');
      }
    }
  }
  // 이웃 마디가 같은 코드로 붙으면(8마디 이음매에서 생긴다) **해결 한 걸음**으로 비켜 준다.
  // 한 코드에 머무는 장르(트랩·힙합)는 그 머묾이 곧 장르라 그대로 둔다.
  if (prof == null || !prof.repeatOk) {
    for (var i = 1; i < out.length; i++) {
      if (out[i] == out[i - 1]) {
        out[i] = doodleStepChord(
          out[i - 1],
          1,
          mode: mode,
          genre: genre,
          salt: i,
        );
      }
    }
  }
  return out;
}

// ── 좌우 = 진행 방향 ──
//
// 표는 **기능화성**으로 짰다. 같은 후보가 여러 번 적힌 것은 가중치다(더 자주 뽑힌다).
//  · 해결 = 토닉 쪽으로 안정: V→I(강), IV→I(플라갈), vii°→I, iii→vi, vi→I/IV …
//  · 긴장 = 불안·전진: 토닉·서브도미넌트에서 도미넌트(V7) 쪽으로, 또는 세컨더리 도미넌트
//    (III7=V/vi, VI7=V/ii, II7=V/V)로 다음 코드를 **끌어당긴다**. V→V7 은 같은 뿌리에
//    7음을 얹어 긴장을 더한다.
//  · **도미넌트 7(dom7)에서의 해결은 표가 아니라 규칙**: 뿌리가 5도 아래(=도수 +3)인 코드로
//    가서 진짜 「해결」로 들리게 한다(V7→I, III7→vi, VI7→ii, II7→V).
// 장르 없으면(재즈 계열 아님) 세컨더리 도미넌트는 빼고 V7 만 남는다.

const DoodleChordPick _c0 = DoodleChordPick(0),
    _c1 = DoodleChordPick(1),
    _c2 = DoodleChordPick(2),
    _c3 = DoodleChordPick(3),
    _c4 = DoodleChordPick(4),
    _c5 = DoodleChordPick(5),
    _c6 = DoodleChordPick(6),
    _v7 = DoodleChordPick(4, 'dom7'),
    _iii7 = DoodleChordPick(2, 'dom7'),
    _vi7 = DoodleChordPick(5, 'dom7'),
    _ii7 = DoodleChordPick(1, 'dom7');

/// 해결 쪽 후보(안정) — 그 조에서 어울리는 것만.
const Map<int, List<DoodleChordPick>> _kResolveMajor = {
  0: [_c5, _c5, _c3], // I → vi / IV
  1: [_c4, _c4, _c0], // ii → V (ii-V, 가장 자연스러운 걸음) / I
  2: [_c5, _c5, _c3], // iii → vi / IV
  3: [_c0, _c0, _c5], // IV → I (플라갈) / vi
  4: [_c0, _c0, _c0, _c5], // V → I / vi(기만)
  5: [_c0, _c3, _c3], // vi → I / IV
  6: [_c0], // vii° → I
};
const Map<int, List<DoodleChordPick>> _kResolveMinor = {
  0: [_c5, _c5, _c2], // i → VI / III
  1: [_c0], // ii° → i
  2: [_c0, _c5], // III → i / VI
  3: [_c0, _c0, _c2], // iv → i (플라갈) / III
  4: [_c0], // v → i
  5: [_c2, _c0], // VI → III / i
  6: [_c0, _c0, _c2], // VII → i / III
};

/// 긴장 쪽 후보(불안·전진). dom7 이 붙은 것은 V7/세컨더리 도미넌트.
const Map<int, List<DoodleChordPick>> _kTenseMajor = {
  0: [_v7, _v7, _c1, _iii7], // I → V7 / ii / III7
  1: [_v7, _v7, _v7, _c2], // ii → V7 / iii
  2: [_vi7, _c1, _c3], // iii → VI7 / ii / IV
  3: [_v7, _v7, _c1], // IV → V7 / ii
  4: [_v7, _c6], // V → V7 / vii°
  5: [_c1, _c1, _ii7, _c4], // vi → ii / II7 / V
  6: [_iii7, _v7], // vii° → III7 / V7
};
const Map<int, List<DoodleChordPick>> _kTenseMinor = {
  0: [_c3, _v7, _v7], // i → iv / V7
  1: [_v7], // ii° → V7
  2: [_c3, _c5], // III → iv / VI
  3: [_v7, _v7, _c6], // iv → V7 / VII
  4: [_v7, _c3], // v → V7 / iv
  5: [_c3, _v7], // VI → iv / V7
  6: [_c5, _v7], // VII → VI / V7
};

/// [from] 다음 마디를 **한 걸음** 갈아 끼운다. [dir] -1=긴장(왼쪽), +1=해결(오른쪽).
/// 0 이면 [from] 을 그대로 돌려준다(가운데는 "안 바꾼다").
///
/// **난수를 안 쓴다** — 후보 중 무엇을 고를지는 [salt] 가 정한다. 같은 (from, dir, salt) 는
/// 늘 같은 답이라, 화면이 **미리 보여 준 다음 코드가 마디 끝에 확정된 코드와 같다.**
/// 지금 코드와 같은 후보는 피한다. 재즈 계열이 아닌 장르에서는 세컨더리 도미넌트를 뺀다.
DoodleChordPick doodleStepChord(
  DoodleChordPick from,
  int dir, {
  required String mode,
  String genre = '',
  int salt = 0,
}) {
  if (dir == 0) return from;
  final major = _isMajor(mode);
  // 도미넌트 7 은 뿌리가 5도 아래인 코드로 풀린다 — 「해결」 방향에서만.
  if (dir > 0 && from.type == 'dom7') {
    final t = doodleResolveDom(from);
    if (t != from) return t;
  }
  // 세컨더리 도미넌트에서 **긴장**을 더 주면 5도권으로 한 칸 더 끈다(III7→VI7→II7→V7). 재즈 계열만,
  // 그리고 토닉(I7)으로는 가지 않는다 — 딴 조 소리가 난다.
  final flavor = _flavorOf(genre);
  if (dir < 0 &&
      from.type == 'dom7' &&
      from.degree != 4 &&
      flavor == DoodleFlavor.jazzy) {
    final d = (from.degree + 3) % 7;
    if (d != 0) return DoodleChordPick(d, 'dom7');
  }
  final table = dir < 0
      ? (major ? _kTenseMajor : _kTenseMinor)
      : (major ? _kResolveMajor : _kResolveMinor);
  var cands = table[from.degree % 7] ?? const <DoodleChordPick>[];
  if (flavor != DoodleFlavor.jazzy) {
    final plain = [
      for (final c in cands)
        if (c.type == null || c.degree == 4) c,
    ];
    if (plain.isNotEmpty) cands = plain;
  }
  if (flavor == DoodleFlavor.loop) {
    // 반복 루프 장르(하우스·트랩·힙합…)는 V7·딤 화음으로 끌지 않는다 — 클래식·재즈 소리가 난다.
    // 마이너 루프의 움직임은 iv·VI·VII 같은 선법적인 걸음이다.
    final dim = major ? 6 : 1;
    final modal = [
      for (final c in cands)
        if (c.type == null && c.degree != dim && !(c.degree == 4 && !major)) c,
    ];
    if (modal.isNotEmpty) cands = modal;
  }
  final diff = [
    for (final c in cands)
      if (c != from) c,
  ];
  final pool = diff.isEmpty ? cands : diff;
  if (pool.isEmpty) return from;
  return pool[salt.abs() % pool.length];
}

/// 도미넌트 7 이 **풀리는 자리** — 뿌리가 5도 아래(도수 +3)인 3화음.
/// dom7 이 아니면 그대로 돌려준다.
DoodleChordPick doodleResolveDom(DoodleChordPick p) =>
    p.type == 'dom7' ? DoodleChordPick((p.degree + 3) % 7) : p;

// ── 상하 = 대체코드 (substitute) ──
//
// 위쪽을 치면 **기능이 비슷한 다른 코드**가 울린다(아래 = 원래 코드). 색(밝기)이 아니다 —
// 화려/담백은 틀린 해석이었다(사용자 피드백 2026-10-01 #4). 대체는 같은 기능 가족끼리 바꾼다:
//   으뜸 가족   I ↔ vi · iii        (공통음 두 개 — 같은 자리에서 쉬는 코드)
//   버금딸림    IV ↔ ii · vi
//   딸림        V  ↔ vii° · iii     (V7 은 vii° 가 곧 근음 빠진 V7)
// 단조(자연단음계)는 i ↔ III · VI, iv ↔ VI · ii°, v ↔ VII · III, VII ↔ v · III …
// 세컨더리 도미넌트(dom7)는 풀어서 같은 뿌리의 3화음으로 대체한다(E7 → Em).

const Map<int, List<int>> _kSubMajor = {
  0: [5, 2], // I → vi / iii
  1: [3, 5], // ii → IV / vi
  2: [0, 5], // iii → I / vi
  3: [1, 5], // IV → ii / vi
  4: [6, 2], // V → vii° / iii
  5: [0, 3], // vi → I / IV
  6: [4, 2], // vii° → V / iii
};
const Map<int, List<int>> _kSubMinor = {
  0: [2, 5], // i → III / VI
  1: [3], // ii° → iv
  2: [0, 5], // III → i / VI
  3: [5, 1], // iv → VI / ii°
  4: [6, 2], // v → VII / III
  5: [3, 0], // VI → iv / i
  6: [2, 4], // VII → III / v
};

/// [from] 의 **대체코드**. 같은 입력·같은 [salt] 는 늘 같은 답(난수 없음) — 화면이 미리 보여 준
/// 코드가 마디 끝에 확정된 코드와 같다. [from] 과 같은 코드를 돌려주는 일은 없다.
///
/// 반복 루프 장르(`DoodleFlavor.loop`)는 딤 화음(ii°/vii°)을 대체 후보에서 뺀다.
DoodleChordPick doodleSubstitute(
  DoodleChordPick from, {
  required String mode,
  String genre = '',
  int salt = 0,
}) {
  final major = _isMajor(mode);
  final d = from.degree % 7;
  // 도미넌트 7: V7 은 vii°/iii 로, 세컨더리 도미넌트는 같은 뿌리 3화음으로.
  if (from.type == 'dom7' && d != 4) return DoodleChordPick(d);
  var cands = (major ? _kSubMajor : _kSubMinor)[d] ?? const <int>[];
  if (_flavorOf(genre) == DoodleFlavor.loop) {
    final dim = major ? 6 : 1;
    final modal = [
      for (final c in cands)
        if (c != dim) c,
    ];
    if (modal.isNotEmpty) cands = modal;
  }
  if (cands.isEmpty) return from;
  return DoodleChordPick(cands[salt.abs() % cands.length]);
}

/// 세로 위치(0=위, 1=아래) → 대체코드를 칠까. **두 구역**: 위 = 대체(true), 아래 = 원래(false).
/// 미세 조준이 필요 없게 한가운데 **한 줄**로만 가른다(화면에 선이 보인다).
/// (화면은 히스테리시스가 있는 `chordColorOfBand`·`kChordColorSplit` 을 쓴다.)
bool doodleSubOfY(double frac) => frac.clamp(0.0, 1.0) < 0.5;

/// 가로 위치(0=왼, 1=오른) → 진행 방향. -1 긴장(왼쪽 1/3), +1 해결(오른쪽 1/3), 0 가운데.
int doodleDirOfX(double frac) {
  final f = frac.clamp(0.0, 1.0);
  if (f < 1 / 3) return -1;
  if (f >= 2 / 3) return 1;
  return 0;
}

/// [pick] 에 색 [color] 를 입힌 **코드 종류 글**(`ChordSpec` 를 만드는 글). null 이면 3화음.
///
///  · 0  기본 — 덮어쓴 종류(dom7)만, 없으면 기본 3화음.
///  · -1 단순·차분 — 3음을 뺀 열린 소리('five').
///  · +1 7th — 그 도수의 다이아토닉 7화음(dom7 자리는 그대로 dom7).
///  · +2 9th — 9도까지(조 밖 음이 되면 7화음에서 멈춘다. dom7 자리면 dom9).
///  · +3 dom7 자리만 dom13 (나머지는 +2 와 같다).
/// 장르가 기본 두께를 정한다(`doodleGenreColor`) — 상하 제스처는 이제 색이 아니라 대체코드다.
String? doodleChordText(MusicKey key, DoodleChordPick pick, int color) {
  if (color <= -1) return 'five';
  if (color == 0) return pick.type;
  if (pick.type == 'dom7') {
    return color >= 3 ? 'dom13' : (color == 2 ? 'dom9' : 'dom7');
  }
  return _seventhText(key, pick.degree, color >= 2 ? 3 : 2) ?? pick.type;
}

/// 도수의 다이아토닉 7화음(thick 2)·9화음(thick 3) 글. 표에 없으면 null.
String? _seventhText(MusicKey key, int degree, int thick) {
  final sc = scaleOf(key.mode);
  int off(int x) => sc[x % 7] + 12 * (x ~/ 7);
  final r = degree % 7;
  final iv = [0, off(r + 2) - off(r), off(r + 4) - off(r), off(r + 6) - off(r)];
  String? type;
  for (final e in kChordTypeIntervals.entries) {
    final v = e.value;
    if (v.length == 4 &&
        v[0] == iv[0] &&
        v[1] == iv[1] &&
        v[2] == iv[2] &&
        v[3] == iv[3]) {
      type = e.key;
      break;
    }
  }
  if (type == null) return null;
  if (thick <= 2) return buildChordText(type, const [], null);
  final ninth = off(r + 8) - off(r);
  if (ninth != 14) return buildChordText(type, const [], null);
  return buildChordText(type, const ['t9'], null);
}

/// [pick]+[color] 의 **실제 코드 스펙**(소리·이름표가 같은 것을 쓴다).
ChordSpec doodleChordSpec(MusicKey key, DoodleChordPick pick, int color) {
  final base = diatonicChords(key)[pick.degree % 7];
  final text = doodleChordText(key, pick, color);
  if (text == null) return base;
  final c = parseChordText(text);
  return ChordSpec(
    root: base.root,
    type: c.type.isEmpty ? base.type : c.type,
    tensions: c.tensions,
  );
}

const List<String> _kPcName = [
  'C',
  'C#',
  'D',
  'Eb',
  'E',
  'F',
  'F#',
  'G',
  'Ab',
  'A',
  'Bb',
  'B',
];

/// 이름표 — `Am7`, `G`, `E7` 처럼 사람이 아는 코드 이름.
String doodleChordName(ChordSpec s) =>
    '${_kPcName[((s.root % 12) + 12) % 12]}${kChordSuffix[s.type] ?? ''}'
    '${s.tensions.contains('t9') ? '(9)' : ''}';

// ── 한 박에 코드 둘 (반박 코드) ──
//
// 한 박(4분)의 머리를 치고 **같은 박의 반박 자리**를 또 치면(빠르게 두 번 쳐도 같다) 반박에는
// 다른 코드가 들어간다. 머리 없이 반박만 친 것(싱코페이션·오프비트 스트럼)은 코드가 안 바뀐다 —
// 안 그러면 8분 오프비트로 같은 코드를 치는 평범한 리듬이 전부 코드 체인지가 된다.
//
// **박 길이는 박자표가 정한다** — 4/4·3/4·5/4 는 4분음표(4칸), 6/8·9/8 같은 겹박자는 점4분음표(6칸,
// 셋씩 한 박), 7/8 은 4칸 + 꼬리. 반박은 박 머리에서 4칸 박이면 +2칸(8분 뒷박), 6칸 박이면 +4칸
// (셋째 8분 — 다음 박을 앞당기는 자리)다. 코드 격자가 8분(2칸)이라 모든 반박이 짝수 칸에 놓인다.

/// 한 박이 몇 칸인가. [m] 은 곡의 박자(`Project.meterDef`).
int doodleBeatSteps(MeterDef m) => (m.unit == 8 && m.beats % 3 == 0) ? 6 : 4;

/// 박 머리에서 반박 자리까지의 칸 수.
int doodleHalfOffset(int beatSteps) => beatSteps == 6 ? 4 : beatSteps ~/ 2;

/// 마디 안 칸 [step](판 전체 칸이어도 된다)이 **반박 자리**인가. [spb] 는 한 마디 칸 수,
/// [beatSteps] 는 [doodleBeatSteps].
bool doodleIsHalfSlot(int step, {required int spb, required int beatSteps}) {
  if (spb <= 0 || beatSteps <= 0) return false;
  final local = ((step % spb) + spb) % spb;
  final off = doodleHalfOffset(beatSteps);
  return local % beatSteps == off && local < spb;
}

/// 반박 자리 [step] 이 그 마디의 **마지막 반박**인가 — 다음 마디를 앞당겨 거는(푸시) 자리.
bool doodleIsLastHalf(int step, {required int spb, required int beatSteps}) {
  final local = ((step % spb) + spb) % spb;
  final cell = local - local % beatSteps;
  return cell + beatSteps + doodleHalfOffset(beatSteps) >= spb;
}

/// 「빠르게 두 번」 — 이번 탭이 반올림된 칸 [step] 이 **직전 탭과 같은 박 머리 칸**이면 같은 박의
/// 반박 칸을 돌려준다(아니면 null). 같은 칸으로 모이면 `TapRecorder` 가 '판:칸' 키로 덮어써서
/// 두 번째 탭이 사라지므로, 의도(두 번 쳤다)를 살려 반박으로 옮긴다.
///  · [sinceMs] — 직전 탭 이후 흐른 시간. 반박 한 칸 길이([stepSec] × 반박 오프셋) 안이어야 한다
///    (그보다 늦으면 다음 바퀴에 같은 자리를 또 친 것이다).
///  · 이미 친 칸([tapped])으로는 옮기지 않는다 — 있는 것을 덮지 않는다.
///  · 박자표를 따른다: [spb]·[beatSteps] 를 빠뜨리면 3/4·6/8 에서 엉뚱한 칸으로 간다.
int? doodleQuickHalfStep({
  required int step,
  required int? prevStep,
  required int? sinceMs,
  required double stepSec,
  required Set<int> tapped,
  required int spb,
  required int beatSteps,
}) {
  if (prevStep == null || sinceMs == null || prevStep != step) return null;
  if (spb <= 0 || beatSteps <= 0) return null;
  final local = ((step % spb) + spb) % spb;
  if (local % beatSteps != 0) return null;
  final off = doodleHalfOffset(beatSteps);
  if (local + off >= spb) return null;
  if (sinceMs > off * stepSec * 1000) return null;
  final half = step + off;
  if (tapped.contains(half)) return null;
  return half;
}

/// 칸 [step] 을 `TapRecorder.stepOf` 가 같은 칸으로 되돌리는 **루프 안 위치**(0~1).
/// [loopSteps] 는 루프 한 바퀴 칸 수(`loopBars × spb`), [latencyFrac] 은 `latencySec / loopSec`.
double doodlePosOfStep(
  int step, {
  required int loopSteps,
  required double latencyFrac,
}) {
  if (loopSteps <= 0) return 0;
  final p = step / loopSteps + latencyFrac;
  return ((p % 1.0) + 1.0) % 1.0;
}

/// 반박 코드. [cur] 은 그 박 머리의 코드, [next] 는 다음 마디 코드(없으면 null).
///  · 마지막 반박(`lastBeat`) = 다음 마디 코드를 **앞당겨 건다**(푸시, 가장 흔한 팝의 화법).
///  · 그 밖의 반박 = 탭의 좌우를 따른다: 왼쪽 긴장 · 오른쪽 해결 걸음, 가운데는 대체코드(I→vi 처럼).
///  · 탭이 위쪽([sub])이면 한 번 더 대체해 본다(원래 코드로 돌아오면 안 한다).
/// 늘 [cur] 와 다른 코드를 돌려준다 — 같으면 반박에 코드가 둘이 아니다.
/// 난수 없음: [salt] 가 같으면 같은 답이다.
DoodleChordPick doodleHalfChord(
  DoodleChordPick cur,
  DoodleChordPick? next, {
  required bool lastBeat,
  required int dir,
  required bool sub,
  required String mode,
  String genre = '',
  int salt = 0,
}) {
  if (lastBeat && next != null && next != cur) return next;
  var h = dir != 0
      ? doodleStepChord(cur, dir, mode: mode, genre: genre, salt: salt)
      : doodleSubstitute(cur, mode: mode, genre: genre, salt: salt);
  if (sub) {
    final s = doodleSubstitute(h, mode: mode, genre: genre, salt: salt);
    if (s != cur) h = s;
  }
  if (h == cur) h = doodleSubstitute(cur, mode: mode, genre: genre, salt: salt);
  return h;
}

/// 한 판(녹음 한 바퀴)의 **코드 진행 상태** — 화면이 들고, 시험이 직접 돌려 본다.
///
/// 규칙
///  · 마디 b 의 **마지막 탭**의 좌우가 b+1 마디를 한 걸음 갈아 끼운다(가운데는 그대로).
///  · 마디 b 의 **마지막 일반 탭**(반박 코드가 아닌 탭)이 위쪽이면 그 마디는 **대체코드**다.
///    대체를 썼으면 가운데 착지여도 다음 마디는 **대체코드에서 이어지는 걸음**이 된다 —
///    I 대신 vi 를 쳤는데 다음이 원래 진행의 V 일 수는 없다.
///  · 반박 코드는 [recordHalfTap] — 마디 코드를 안 건드리고 그 칸만 따로 적힌다.
class DoodleChordPlan {
  final List<DoodleChordPick> base;
  final String mode;
  final String genre;

  /// 한 마디 칸 수·한 박 칸 수 — 박자표마다 다르다(`Project.spb`·`doodleBeatSteps`).
  /// 기본값이 없다: 빠뜨리면 4/4 에서만 맞는 반박 자리가 조용히 생긴다.
  final int spb;
  final int beatSteps;
  final math.Random rng;
  late List<DoodleChordPick> plan = List.of(base);
  late final int salt = rng.nextInt(1 << 20);
  final Map<int, int> _landDir = {};
  final Map<int, bool> _landSub = {};
  final Map<int, int> _halfDir = {};
  final Map<int, bool> _halfSub = {};
  int _settled = 0;

  DoodleChordPlan(
    this.base, {
    required this.mode,
    required this.spb,
    required this.beatSteps,
    this.genre = '',
    math.Random? rng,
  }) : rng = rng ?? math.Random();

  /// 이 장르 코드의 기본 두께(`doodleGenreColor`).
  int get color => doodleGenreColor(genre);

  /// 판을 처음(깔아 둔 진행)으로 되돌린다 — 다시 녹음.
  void reset() {
    plan = List.of(base);
    _landDir.clear();
    _landSub.clear();
    _halfDir.clear();
    _halfSub.clear();
    _settled = 0;
  }

  int _clamp(int bar) => bar.clamp(0, plan.length - 1);

  /// [bar] 마디까지 앞 마디들의 착지 방향을 반영해 확정한다.
  void settleUpTo(int bar) {
    final last = _clamp(bar);
    while (_settled < last) {
      plan[_settled + 1] = _nextOf(_settled);
      _settled++;
    }
  }

  /// [bar] 마디의 **대체코드** — 위쪽 탭이 울릴 코드.
  DoodleChordPick substituteOf(int bar) {
    final b = _clamp(bar);
    return doodleSubstitute(plan[b], mode: mode, genre: genre, salt: salt + b * 17);
  }

  /// [bar] 마디에 **적힐** 코드 — 착지(마지막 일반) 탭이 위쪽이면 대체코드.
  DoodleChordPick finalAt(int bar) {
    final b = _clamp(bar);
    return _landSub[b] == true ? substituteOf(b) : plan[b];
  }

  /// [bar] 다음 마디에 실제로 깔릴 코드. 착지가 가운데(0)라도 **떠 있는 도미넌트 7 은 풀어 준다** —
  /// 안 그러면 V7·III7 뒤에 깔린 진행의 아무 코드나 붙어 「풀리지 않은 채 딴 데로」 가 되어 어색하다.
  /// 대체코드를 썼으면 **그 코드에서 이어지는 해결 걸음**이다(원래 코드가 가려던 곳이 아니다).
  /// [dir] 을 주면 아직 기록 전인 탭의 방향으로 미리 가늠한다(반박 푸시 소리용).
  DoodleChordPick _nextOf(int bar, {int? dir}) {
    final d = dir ?? _landDir[bar] ?? 0;
    final cur = finalAt(bar);
    if (d != 0) {
      return doodleStepChord(cur, d, mode: mode, genre: genre, salt: salt + bar * 31);
    }
    final nxt = bar + 1 < plan.length ? plan[bar + 1] : plan.first;
    if (cur.type == 'dom7' && nxt.degree != (cur.degree + 3) % 7) {
      return doodleResolveDom(cur);
    }
    if (_landSub[bar] == true) {
      return doodleStepChord(cur, 1, mode: mode, genre: genre, salt: salt + bar * 31);
    }
    return nxt;
  }

  /// **다음 마디 코드 미리보기** — 지금 마디(들)의 착지 방향·대체가 이대로 확정될 때의 코드.
  /// 마디 끝에 [settleUpTo] 가 만드는 것과 **같은 값**이다(같은 salt). 판의 마지막 마디면 null.
  DoodleChordPick? previewNext(int bar) {
    final b = _clamp(bar);
    if (b + 1 >= plan.length) return null;
    settleUpTo(b);
    return _nextOf(b);
  }

  /// 지금 [bar] 마디에서 **적힐** 코드(앞 마디들을 먼저 확정한다).
  DoodleChordPick pickAt(int bar) {
    settleUpTo(bar);
    return finalAt(bar);
  }

  /// 위쪽(대체)·아래(원래) 중 [sub] 쪽을 쳤을 때 **그 순간 울릴** 코드.
  DoodleChordPick soundAt(int bar, {required bool sub}) {
    settleUpTo(bar);
    return sub ? substituteOf(bar) : plan[_clamp(bar)];
  }

  /// [bar] 마디에서 탭 하나 — 마지막에 친 탭이 이긴다(= 착지 탭). [sub] 는 위쪽(대체) 탭인가.
  void recordTap(int bar, {required int dir, required bool sub}) {
    _landDir[bar] = dir;
    _landSub[bar] = sub;
  }

  /// [step](판 안 칸) 반박 자리에서 탭 하나. 마디 코드(대체 여부)는 그대로 두고, 이 탭의 방향이
  /// 다음 마디를 정하는 **착지 방향**이 된다(마지막 탭이니까).
  void recordHalfTap(int step, {required int dir, required bool sub}) {
    _landDir[step ~/ spb] = dir;
    _halfDir[step] = dir;
    _halfSub[step] = sub;
  }

  /// [step] 이 **반박 코드를 받는 자리**인가 — 반박 자리이고, 같은 박의 머리([tapped] 에 있다)가
  /// 쳐져 있어야 한다. [tapped] 는 판에 친 칸들.
  bool isHalfChord(int step, Set<int> tapped) =>
      doodleIsHalfSlot(step, spb: spb, beatSteps: beatSteps) &&
      tapped.contains(step - doodleHalfOffset(beatSteps));

  /// 반박 자리 [step] 에 깔릴 코드. [dir]·[sub] 를 주면 지금 막 치는 탭 기준(소리용), 안 주면
  /// 기록된 탭(`recordHalfTap`) 기준(적기용 — 기록 없는 칸, 예: 리듬 락으로 베낀 칸은 가운데·아래).
  DoodleChordPick halfChordAt(int step, {int? dir, bool? sub}) {
    final bar = _clamp(step ~/ spb);
    settleUpTo(bar);
    final d = dir ?? _halfDir[step] ?? 0;
    final sb = sub ?? _halfSub[step] ?? false;
    final last = doodleIsLastHalf(step, spb: spb, beatSteps: beatSteps);
    return doodleHalfChord(
      finalAt(bar),
      last ? _nextOf(bar, dir: dir) : null,
      lastBeat: last,
      dir: d,
      sub: sb,
      mode: mode,
      genre: genre,
      salt: salt + step * 7,
    );
  }

  /// 그 마디에 적힌 방향/대체(시험·화면 표시용).
  int landDirOf(int bar) => _landDir[bar] ?? 0;
  bool landSubOf(int bar) => _landSub[bar] ?? false;
}

/// 판을 시작할 때 **앞 코드**로 삼을 자리 — 깔린 진행을 두 바퀴 돌려 마지막 화음의 자리를 구한다
/// (`buildChordPattern` 이 끝 코드 → 첫 코드로 이어 주는 것과 같은 방식). 연주 중 첫 탭이
/// 재생과 같은 자리로 나게 하려는 것이다. [color] 는 장르 두께(`doodleGenreColor`).
List<int> doodleVoiceSeed(
  MusicKey key,
  List<DoodleChordPick> plan, {
  int color = 0,
}) {
  List<int>? prev;
  for (var pass = 0; pass < 2; pass++) {
    for (final c in plan) {
      prev = voiceLead(chordMidiOf(doodleChordSpec(key, c, color)), prev);
    }
  }
  return prev ?? const [60, 64, 67];
}
