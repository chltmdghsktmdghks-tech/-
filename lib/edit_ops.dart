// 편집기가 하는 **계산**만 모아 둔 곳 (5단계 12/N).
//
// 화면(`ui/editor_view.dart`)에 두면 시험이 못 찌른다 — 음 길이·세기·글라이드는
// "눈으로 보고 귀로 듣는" 것이라 **눈이 속기 쉬운 자리**다(막대는 길어졌는데 소리는
// 그대로일 수 있다). 그래서 순수 함수로 떼어내고, 시험은 여기를 고친 뒤
// **실제 재생 이벤트(초·세기·글라이드)** 까지 따라가서 확인한다.
//
// 노트 한 줄의 형식은 `patterns.dart` 와 같다:
//   베이스/멜로디: [도수, step, len(스텝), vel(1~3), glide?(1이면 켬)]
//   코드:          [코드번호, step, len, vel, 코드타입?(문자열)]
// **5번째 칸이 종류마다 다르다** — 코드 트랙에서 글라이드를 쓰면 코드 타입이 날아간다.
// 그래서 여기 함수들은 전부 `isChord` 를 받는다.

import 'patterns.dart';
import 'theory.dart';

/// 음 길이 최대(2마디) — 라이브러리 코드 패턴이 여기까지 쓴다.
const int kMaxNoteLen = 32;

/// 목록을 통째로 복사한다 — 원본을 그 자리에서 고치면 되돌리기가 불가능해진다.
List<List<Object?>> _copy(List<List<Object?>> list) => [
  for (final n in list) List<Object?>.from(n),
];

int _indexOf(List<List<Object?>> list, int degree, int step) =>
    list.indexWhere((n) => n[0] == degree && n[1] == step);

/// 멜로디/베이스/코드 음 목록 고치기. 전부 **새 목록을 돌려준다**(원본은 안 건드린다).
class NoteOps {
  /// 없으면 찍고, 있으면 그대로 둔다. 기본 길이는 코드 7칸·나머지 2칸,
  /// 패턴 끝을 넘지 않게 자른다.
  static List<List<Object?>> add(
    List<List<Object?>> list,
    int degree,
    int step, {
    required bool isChord,
    required int steps,
  }) {
    if (_indexOf(list, degree, step) >= 0) return _copy(list);
    final out = _copy(list);
    final want = isChord ? 7 : 2;
    // 코드 줄은 **층(6번째 칸)** 을 가진다(theory.dart `voiceLead`). 새로 찍는 음도
    // 그 줄의 층을 따라가야 한다 — 안 그러면 방금 찍은 음만 한 옥타브 아래로 떨어진다.
    final oct = isChord ? chordOct(list) : 0;
    out.add(
      oct == 0
          ? [degree, step, _fitLen(want, step, steps), 2]
          : [degree, step, _fitLen(want, step, steps), 2, null, oct],
    );
    return out;
  }

  /// **도수 줄 → 반음 줄.** 프로 모드로 넘어갈 때 찍어 둔 것을 옮긴다.
  ///
  /// 뜻이 다른 두 좌표계다 — 도수 7은 한 옥타브 위지만 반음 7은 5도다.
  /// 그냥 켜면 찍어 둔 가락이 **딴 가락이 된다.** 그래서 옮겨 준다.
  static List<List<Object?>> toChromatic(
    List<List<Object?>> list,
    String mode,
  ) {
    final sc = scaleOf(mode);
    return [
      for (final n in list)
        [
          _clampSemi(sc[(n[0] as int) % 7] + 12 * ((n[0] as int) ~/ 7)),
          ...n.skip(1),
        ],
    ];
  }

  /// **반음 줄 → 도수 줄.** 조에 없는 음은 **제일 가까운 조의 음**으로 붙인다
  /// (그 음은 도수 줄에 자리가 아예 없다 — 버리는 것보다 붙이는 편이 낫다).
  static List<List<Object?>> toDegrees(List<List<Object?>> list, String mode) {
    final sc = scaleOf(mode);
    int nearest(int semi) {
      var best = 0, bestGap = 1 << 20;
      for (var d = 0; d < 15; d++) {
        final s = sc[d % 7] + 12 * (d ~/ 7);
        final gap = (s - semi).abs();
        if (gap < bestGap) {
          bestGap = gap;
          best = d;
        }
      }
      return best;
    }

    return [
      for (final n in list) [nearest(n[0] as int), ...n.skip(1)],
    ];
  }

  static int _clampSemi(int v) =>
      v < 0 ? 0 : (v > kProRows - 1 ? kProRows - 1 : v);

  static List<List<Object?>> remove(
    List<List<Object?>> list,
    int degree,
    int step,
  ) {
    final out = _copy(list);
    final at = _indexOf(out, degree, step);
    if (at >= 0) out.removeAt(at);
    return out;
  }

  /// 같은 도수에서 [step] **다음 음이 시작하는 칸**. 없으면 판 끝([steps]).
  static int _nextStart(
    List<List<Object?>> list,
    int degree,
    int step,
    int steps,
  ) {
    var limit = steps;
    for (final n in list) {
      if (n[0] != degree) continue;
      final s = n[1] as int;
      if (s > step && s < limit) limit = s;
    }
    return limit;
  }

  /// 길이 바꾸기 — **뒷 음을 덮지 않는다.**
  ///
  /// 덮으면 그 음이 화면에서 가려지고, 편집기의 손끝 판정은 위에 그려진 음을
  /// 잡으므로 **덮인 음은 손으로 만질 수 없게 된다**(지울 수도 고를 수도 없다).
  /// 소리로는 계속 나는데 화면에서는 사라진 것처럼 보인다.
  ///
  /// 다만 **이미 겹쳐 있는 것을 줄이지는 않는다**: 「끌면 쫘르륵 깔린다」가
  /// 일부러 이웃끼리 1칸씩 겹쳐 놓기 때문이다(`editor_ui_test.dart` 10번).
  /// 무턱대고 자르면 그렇게 깐 줄의 음을 만지는 순간 전부 1칸으로 쪼그라든다.
  /// 그래서 **늘리는 쪽만** 막는다.
  static List<List<Object?>> setLen(
    List<List<Object?>> list,
    int degree,
    int step,
    int len, {
    required int steps,
  }) {
    final out = _copy(list);
    final at = _indexOf(out, degree, step);
    if (at < 0) return out;
    final cur = out[at][2] as int;
    final room = (_nextStart(out, degree, step, steps) - step).clamp(
      1,
      kMaxNoteLen,
    );
    final cap = room > cur ? room : cur; // 이미 겹친 것은 그대로 둔다
    out[at][2] = _fitLen(len, step, steps).clamp(1, cap);
    return out;
  }

  static List<List<Object?>> setVel(
    List<List<Object?>> list,
    int degree,
    int step,
    int vel,
  ) {
    final out = _copy(list);
    final at = _indexOf(out, degree, step);
    if (at >= 0) out[at][3] = vel.clamp(1, 3);
    return out;
  }

  /// 글라이드 켜기/끄기. **코드는 5번째 칸이 코드 타입이라 아무것도 안 한다.**
  static List<List<Object?>> toggleGlide(
    List<List<Object?>> list,
    int degree,
    int step, {
    required bool isChord,
  }) {
    final out = _copy(list);
    if (isChord) return out;
    final at = _indexOf(out, degree, step);
    if (at < 0) return out;
    final n = out[at];
    if (n.length > 4) {
      n[4] = n[4] == 1 ? 0 : 1;
    } else {
      n.add(1);
    }
    return out;
  }

  static bool glideOn(List<Object?> n) => n.length > 4 && n[4] == 1;

  /// 코드 한 자리의 **종류**를 바꾼다 — 3화음 → 7th · sus4 · dim …
  ///
  /// `theory.dart` 는 처음부터 스물네 가지를 알고 있었고 라이브러리 패턴도 쓰고
  /// 있었다(`min7`·`maj7`·`min9`…). 그런데 **편집기에서 고를 길이 없어서**,
  /// 사용자가 직접 찍는 코드는 무엇을 찍어도 기본 3화음뿐이었다 —
  /// 코드 트랙으로 만들 수 있는 색이 하나로 고정돼 있었다.
  ///
  /// [type] 이 null 이면 기본 3화음으로 되돌린다.
  /// **5번째 칸은 코드 줄에서 「종류」다**(음정 줄에서는 글라이드다) — 그래서
  /// 코드가 아니면 아무것도 안 한다.
  static List<List<Object?>> setChordType(
    List<List<Object?>> list,
    int degree,
    int step,
    String? type, {
    required bool isChord,
  }) {
    final out = _copy(list);
    if (!isChord) return out;
    final at = _indexOf(out, degree, step);
    if (at < 0) return out;
    final n = out[at];
    // 6번째 칸(층)이 있으면 5번째를 건너뛸 수 없다 — 자리를 맞춰 둔다
    while (n.length < 5) {
      n.add(null);
    }
    n[4] = type;
    return out;
  }

  /// 그 자리의 **코드 칸 글자 전체** — 종류·텐션·슬래시가 다 들어 있다.
  static String? chordTextOf(List<Object?> n) =>
      n.length > 4 && n[4] is String ? n[4] as String : null;

  /// 그 자리의 코드 종류만 — 없으면 null(기본 3화음).
  /// 텐션·슬래시가 붙어 있어도 **종류 칩은 종류만** 봐야 한다.
  static String? chordTypeOf(List<Object?> n) {
    final t = chordTextOf(n);
    if (t == null) return null;
    final ty = parseChordText(t).type;
    return ty.isEmpty ? null : ty;
  }

  /// 그 자리에 붙은 텐션들(`t9`·`t11`·`t13`).
  static List<String> chordTensionsOf(List<Object?> n) =>
      parseChordText(chordTextOf(n)).tensions;

  /// 그 자리의 슬래시 베이스 도수(0~6). 없으면 null.
  static int? chordBassOf(List<Object?> n) =>
      parseChordText(chordTextOf(n)).bassDegree;

  /// 코드 칸을 통째로 쓴다 — 종류·텐션·슬래시를 한 번에.
  static List<List<Object?>> setChordText(
    List<List<Object?>> list,
    int degree,
    int step,
    String? text, {
    required bool isChord,
  }) => setChordType(list, degree, step, text, isChord: isChord);

  /// 이 코드 줄이 앉은 층 — 첫 음이 말해 준다(한 줄은 한 층에 있다). 없으면 0.
  static int chordOct(List<List<Object?>> list) {
    for (final n in list) {
      if (n.length > 5 && n[5] is int) return n[5] as int;
    }
    return 0;
  }

  /// 좌우로 한 칸 옮기기. 갈 자리에 이미 음이 있거나 패턴 밖이면 **그대로 둔다**.
  static List<List<Object?>> move(
    List<List<Object?>> list,
    int degree,
    int step,
    int by, {
    required int steps,
  }) {
    final to = step + by;
    final out = _copy(list);
    if (to < 0 || to >= steps) return out;
    if (_indexOf(out, degree, to) >= 0) return out;
    final at = _indexOf(out, degree, step);
    if (at < 0) return out;
    out[at][1] = to;
    out[at][2] = _fitLen(out[at][2] as int, to, steps);
    return out;
  }

  /// 마디를 줄였을 때 — 범위 밖 음은 버리고, 걸친 꼬리는 자른다.
  static List<List<Object?>> trimTo(List<List<Object?>> list, int limit) {
    final out = <List<Object?>>[];
    for (final n in list) {
      final s = n[1] as int;
      if (s >= limit) continue;
      final c = List<Object?>.from(n);
      c[2] = _fitLen(c[2] as int, s, limit);
      out.add(c);
    }
    return out;
  }

  static int _fitLen(int len, int step, int steps) =>
      len.clamp(1, (steps - step).clamp(1, kMaxNoteLen));

  /// **판 안의 음 길이를 통째로** 한 칸씩 늘리거나 줄인다 — 스타카토 ↔ 레가토.
  ///
  /// 여태는 음을 하나씩 골라 「칸 +」를 눌러야 했다. 20음이면 20번이다.
  /// 베이스나 패드의 성격을 통째로 바꾸는 손잡이라 한 번에 되어야 한다.
  ///
  /// 늘릴 때는 **같은 줄의 다음 음에 안 부딪히게** 자른다 — 겹치면 앞음이
  /// 뒷음을 먹어서 소리가 사라진 것처럼 들린다. 줄일 때는 1칸이 바닥이다.
  static List<List<Object?>> stretchAll(
    List<List<Object?>> list,
    int dir, {
    required int steps,
  }) {
    if (dir == 0) return _copy(list);
    final out = _copy(list);
    // 줄(도수)마다 다음 음이 어디서 시작하는지 — 늘릴 때 거기까지만 간다.
    final byDeg = <int, List<int>>{};
    for (final n in out) {
      (byDeg[(n[0] as num).toInt()] ??= []).add((n[1] as num).toInt());
    }
    for (final v in byDeg.values) {
      v.sort();
    }
    for (final n in out) {
      final deg = (n[0] as num).toInt();
      final st = (n[1] as num).toInt();
      final len = (n[2] as num).toInt();
      var limit = steps - st; // 판 끝을 넘지 않는다
      if (dir > 0) {
        for (final other in byDeg[deg]!) {
          if (other > st) {
            final gap = other - st;
            if (gap < limit) limit = gap;
            break;
          }
        }
      }
      n[2] = (len + dir).clamp(1, limit.clamp(1, kMaxNoteLen));
    }
    return out;
  }
}

/// 드럼 패턴 하나를 **자리가 맞는 두 목록**(스텝·세기)으로 펼치고 되접는다.
///
/// 저장 형식은 레인별 스텝 목록 하나뿐이라(웹 그대로) 세기를 담을 곳이 없었다 →
/// `DrumPatternDef.vels` 를 나란한 목록으로 붙였다. 나란한 목록은 **순서가 어긋나면
/// 조용히 망가지므로**(킥 세기가 스네어에 붙는 식) 정렬은 여기 한 곳에서만 한다.
class DrumOps {
  final Map<String, List<int>> steps;
  final Map<String, List<int>> vels;
  DrumOps(this.steps, this.vels);

  /// 저장된 패턴을 펼친다. 세기가 없는 타격은 `defaultDrumVel` 로 메운다 —
  /// 화면과 소리가 **같은 값**을 보게 하려면 읽는 쪽에서 한 번에 메워야 한다.
  factory DrumOps.read(DrumPatternDef? def) {
    final ss = {for (final l in kDrumLanes) l: <int>[]};
    final vv = {for (final l in kDrumLanes) l: <int>[]};
    def?.hits.forEach((ab, list) {
      final lane = kDrumAbbrevToLane[ab];
      if (lane == null) return;
      final mine = def.vels?[ab];
      for (var i = 0; i < list.length; i++) {
        ss[lane]!.add(list[i]);
        vv[lane]!.add(
          (mine != null && i < mine.length)
              ? mine[i].clamp(1, 3)
              : defaultDrumVel(lane, list[i]),
        );
      }
    });
    return DrumOps(ss, vv);
  }

  int indexOf(String lane, int step) => steps[lane]!.indexOf(step);

  int velAt(String lane, int step) {
    final i = indexOf(lane, step);
    return i < 0 ? 0 : vels[lane]![i];
  }

  void add(String lane, int step) {
    if (indexOf(lane, step) >= 0) return;
    steps[lane]!.add(step);
    vels[lane]!.add(defaultDrumVel(lane, step));
  }

  void remove(String lane, int step) {
    final i = indexOf(lane, step);
    if (i < 0) return;
    steps[lane]!.removeAt(i);
    vels[lane]!.removeAt(i);
  }

  void setVel(String lane, int step, int vel) {
    final i = indexOf(lane, step);
    if (i >= 0) vels[lane]![i] = vel.clamp(1, 3);
  }

  /// 좌우로 한 칸. 갈 자리에 타격이 있거나 패턴 밖이면 그대로 둔다.
  bool move(String lane, int step, int by, int total) {
    final to = step + by;
    if (to < 0 || to >= total) return false;
    if (indexOf(lane, to) >= 0) return false;
    final i = indexOf(lane, step);
    if (i < 0) return false;
    steps[lane]![i] = to;
    return true;
  }

  void trimTo(int limit) {
    for (final lane in kDrumLanes) {
      final ss = steps[lane]!, vv = vels[lane]!;
      for (var i = ss.length - 1; i >= 0; i--) {
        if (ss[i] >= limit) {
          ss.removeAt(i);
          vv.removeAt(i);
        }
      }
    }
  }

  /// 저장 형식으로 되접는다 — **스텝 순으로 정렬하되 세기도 같이 따라간다.**
  DrumPatternDef toDef(String name, int bars) {
    final hits = <String, List<int>>{};
    final vs = <String, List<int>>{};
    steps.forEach((lane, list) {
      if (list.isEmpty) return;
      final ab = kDrumLaneToAbbrev[lane];
      if (ab == null) return;
      final order = List<int>.generate(list.length, (i) => i)
        ..sort((a, b) => list[a].compareTo(list[b]));
      hits[ab] = [for (final i in order) list[i]];
      vs[ab] = [for (final i in order) vels[lane]![i]];
    });
    return DrumPatternDef(name, bars, bars, hits, vs);
  }
}
