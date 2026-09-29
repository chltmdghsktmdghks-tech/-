// 두들플레이 코드 기믹의 **순수 로직** — 화면(doodle_play_view.dart)과 떼어 둔다.
// (사용자 지시서 2026-09-29 (12) 2단계)
//
//  · 탭 = 리듬(세기 균일). 어느 코드가 울리는지는 **마디마다 깔린 진행**이 정한다.
//  · 좌우(X) = 진행 방향. 한 마디의 **착지(마지막) 탭**이 왼쪽이면 다음 마디를 긴장으로,
//    오른쪽이면 해결로 한 걸음 갈아 끼운다.
//  · 상하(Y) = 같은 자리 코드의 **색**(밝기). "다른 코드 고르기"가 아니다.
//
// 코드 하나는 (다이아토닉 도수, 종류 덮어쓰기) 로 적는다. 세컨더리 도미넌트는
// `(2,'dom7')`(= III7, 다음 vi 로 가는 V/vi)처럼 **도수 뿌리 + dom7 종류**로 표현해서
// 저장 형식(코드 줄 `[도수, 칸, 길이, 세기, 종류글]`)을 그대로 쓴다.
import 'dart:math' as math;

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
      other is DoodleChordPick &&
      other.degree == degree &&
      other.type == type;
  @override
  int get hashCode => Object.hash(degree, type);
  @override
  String toString() => 'DoodleChordPick($degree${type == null ? '' : ',$type'})';
}

/// 세컨더리 도미넌트를 써도 어울리는 장르(재즈 계열·도시적인 것).
const Set<String> _kJazzy = {'lofi', 'citypop', 'jazz', 'rnb', 'gospel', 'pop'};

bool _isMajor(String mode) => mode == 'major';

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
/// 후보 풀은 조(장/단)·장르로 갈리고, 장르가 없으면(빈 문자열) 단순 다이어토닉이다.
List<DoodleChordPick> doodleBasePlan({
  required String mode,
  required int bars,
  String genre = '',
  math.Random? rng,
}) {
  final r = rng ?? math.Random();
  final major = _isMajor(mode);
  final jazzy = _kJazzy.contains(genre);
  List<int> pick(List<List<int>> pool) => pool[r.nextInt(pool.length)];

  List<int> degs;
  if (bars <= 2) {
    degs = pick(major ? _kMajor2 : _kMinor2);
  } else {
    final pool = [
      ...(major ? _kMajor4 : _kMinor4),
      if (jazzy) ...(major ? _kMajorJazz4 : _kMinorJazz4),
    ];
    final a = pick(pool);
    if (bars <= 4) {
      degs = a;
    } else {
      // 8마디 — 앞 넷을 되풀이하되 끝을 다른 진행의 끝으로 바꿔 한 바퀴 돈 느낌을 준다.
      final b = pick(pool);
      degs = [...a, ...a.take(2), b[2], b[3]];
    }
  }
  final out = [
    for (var i = 0; i < bars; i++) DoodleChordPick(degs[i % degs.length]),
  ];
  // 이웃 마디가 같은 코드로 붙으면(8마디 이음매에서 생긴다) **해결 한 걸음**으로 비켜 준다.
  for (var i = 1; i < out.length; i++) {
    if (out[i] == out[i - 1]) {
      out[i] = doodleStepChord(out[i - 1], 1, mode: mode, genre: genre, salt: i);
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
  1: [_c0, _c3], // ii → I / IV
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
  1: [_v7, _v7, _c6], // ii → V7 / vii°
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
    final t = DoodleChordPick((from.degree + 3) % 7);
    if (t != from) return t;
  }
  final table = dir < 0
      ? (major ? _kTenseMajor : _kTenseMinor)
      : (major ? _kResolveMajor : _kResolveMinor);
  var cands = table[from.degree % 7] ?? const <DoodleChordPick>[];
  if (!_kJazzy.contains(genre)) {
    final plain = [
      for (final c in cands)
        if (c.type == null || c.degree == 4) c,
    ];
    if (plain.isNotEmpty) cands = plain;
  }
  final diff = [for (final c in cands) if (c != from) c];
  final pool = diff.isEmpty ? cands : diff;
  if (pool.isEmpty) return from;
  return pool[salt.abs() % pool.length];
}

// ── 상하 = 코드 색 ──

/// 세로 위치(0=위, 1=아래) → 색 단계. **두 구역**: 위 = 화려(+1, 7th/9th), 아래 = 담백(0, 기본).
/// 미세 조준이 필요 없게 한가운데 **한 줄**로만 가른다(화면에 선이 보인다).
/// 단계 -1(five)·+2(9th/13th)는 함수가 지원하지만 손짓에서는 안 쓴다.
int doodleColorOfY(double frac) => frac.clamp(0.0, 1.0) < 0.5 ? 1 : 0;

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
///  · +1 밝음 — 그 도수의 다이아토닉 7화음(dom7 자리면 dom9).
///  · +2 화려 — 9도까지(조 밖 음이 되면 7화음에서 멈춘다. dom7 자리면 dom13).
String? doodleChordText(MusicKey key, DoodleChordPick pick, int color) {
  if (color <= -1) return 'five';
  if (color == 0) return pick.type;
  if (pick.type == 'dom7') return color >= 2 ? 'dom13' : 'dom9';
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
  'C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B',
];

/// 이름표 — `Am7`, `G`, `E7` 처럼 사람이 아는 코드 이름.
String doodleChordName(ChordSpec s) =>
    '${_kPcName[((s.root % 12) + 12) % 12]}${kChordSuffix[s.type] ?? ''}'
    '${s.tensions.contains('t9') ? '(9)' : ''}';

/// 한 판(녹음 한 바퀴)의 **코드 진행 상태** — 화면이 들고, 시험이 직접 돌려 본다.
///
/// 규칙: 마디 b 의 **마지막 탭**의 좌우가 b+1 마디를 한 걸음 갈아 끼운다(가운데는 그대로).
/// 마디의 기록 색은 그 마디 **마지막 탭**의 색 하나다.
class DoodleChordPlan {
  final List<DoodleChordPick> base;
  final String mode;
  final String genre;
  final math.Random rng;
  late List<DoodleChordPick> plan = List.of(base);
  late final int salt = rng.nextInt(1 << 20);
  final Map<int, int> _landDir = {};
  final Map<int, int> _barColor = {};
  int _settled = 0;

  DoodleChordPlan(this.base, {required this.mode, this.genre = '', math.Random? rng})
    : rng = rng ?? math.Random();

  /// 판을 처음(깔아 둔 진행)으로 되돌린다 — 다시 녹음.
  void reset() {
    plan = List.of(base);
    _landDir.clear();
    _barColor.clear();
    _settled = 0;
  }

  int _clamp(int bar) => bar.clamp(0, plan.length - 1);

  /// [bar] 마디까지 앞 마디들의 착지 방향을 반영해 확정한다.
  void settleUpTo(int bar) {
    final last = _clamp(bar);
    while (_settled < last) {
      final dir = _landDir[_settled] ?? 0;
      if (dir != 0) {
        plan[_settled + 1] = _stepFor(_settled, dir);
      }
      _settled++;
    }
  }

  DoodleChordPick _stepFor(int bar, int dir) =>
      doodleStepChord(plan[bar], dir, mode: mode, genre: genre, salt: salt + bar * 31);

  /// **다음 마디 코드 미리보기** — 지금 마디(들)의 착지 방향이 이대로 확정될 때의 코드.
  /// 마디 끝에 [settleUpTo] 가 만드는 것과 **같은 값**이다(같은 salt). 판의 마지막 마디면 null.
  DoodleChordPick? previewNext(int bar) {
    final b = _clamp(bar);
    if (b + 1 >= plan.length) return null;
    settleUpTo(b);
    final dir = _landDir[b] ?? 0;
    return dir == 0 ? plan[b + 1] : _stepFor(b, dir);
  }

  /// 지금 [bar] 마디에서 울릴 코드(앞 마디들을 먼저 확정한다).
  DoodleChordPick pickAt(int bar) {
    settleUpTo(bar);
    return plan[_clamp(bar)];
  }

  /// [bar] 마디에서 탭 하나 — 마지막에 친 탭이 이긴다(= 착지 탭).
  void recordTap(int bar, {required int dir, required int color}) {
    _landDir[bar] = dir;
    _barColor[bar] = color;
  }

  /// 그 마디에 **적힐** 색(착지 탭). 친 게 없으면 0.
  int colorOf(int bar) => _barColor[bar] ?? 0;
  int landDirOf(int bar) => _landDir[bar] ?? 0;
}

/// 판을 시작할 때 **앞 코드**로 삼을 자리 — 깔린 진행을 두 바퀴 돌려 마지막 화음의 자리를 구한다
/// (`buildChordPattern` 이 끝 코드 → 첫 코드로 이어 주는 것과 같은 방식). 연주 중 첫 탭이
/// 재생과 같은 자리로 나게 하려는 것이다.
List<int> doodleVoiceSeed(MusicKey key, List<DoodleChordPick> plan) {
  List<int>? prev;
  for (var pass = 0; pass < 2; pass++) {
    for (final c in plan) {
      prev = voiceLead(chordMidiOf(doodleChordSpec(key, c, 0)), prev);
    }
  }
  return prev ?? const [60, 64, 67];
}
