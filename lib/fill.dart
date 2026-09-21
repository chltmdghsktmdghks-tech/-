// 필(Fill) — **한 판이 끝나는 자리를 표시한다.** (Phase 4 · 개선 계획 6-2)
//
// 지금 문제: 2분짜리 곡이 **똑같은 4마디의 되풀이**다. 사람이 만든 음악은
// 4·8마디마다 매듭을 짓는다 — 마지막 마디에서 드럼이 달라지고, 다음 구간
// 첫 박에 크래시가 터진다. 그게 없으면 아무리 음색이 좋아도 '루프'로 들린다.
//
// 여기도 `applyFeel` 과 같은 자리에서 끝낸다 — 시퀀서가 만들어 낸 타격 목록을
// 마지막에 한 번 고쳐 쓴다. 엔진·패턴 데이터는 안 건드린다.
// 재생과 내보내기가 같은 목록을 쓰므로 둘이 저절로 같다.
import 'dart:math' as math;

/// 필을 넣을지, 얼마나 자주·얼마나 길게.
///
/// 손잡이는 **하나**다. 사람이 「가끔 / 보통 / 자주」로 생각하지
/// 「8마디마다 4스텝」으로 생각하지 않는다 — 빈도와 길이를 같이 정한다.
class FillSpec {
  /// 0 이면 안 넣는다.
  final double amount;
  const FillSpec({this.amount = 0.6});
  static const FillSpec none = FillSpec(amount: 0);

  /// 구간 **안쪽**에 몇 마디마다 넣을지. 0 이면 안쪽에는 안 넣고 **구간 끝에만** 넣는다.
  ///
  /// 사용자 지적: 「필인은 송폼이 넘어갈 때나 송폼이 많이 반복되면 넣어야지」.
  /// 맞는 말이다 — 필은 **매듭**이지 장식이 아니다. 4마디마다 기계처럼 넣으면
  /// 매듭이 너무 잦아서 아무것도 매듭이 아니게 된다.
  ///  가끔  → 구간 끝에만
  ///  보통  → 구간 끝 + 8마디마다
  ///  자주  → 구간 끝 + 4마디마다
  int get insideBars => amount < 0.45
      ? 0
      : amount < 0.8
      ? 8
      : 4;

  /// 몇 스텝짜리 — 보통은 한 박(4), 세게 걸면 반 마디(8).
  int get steps => amount < 0.8 ? 4 : 8;
}

/// 마지막 마디의 **마지막 한 박**을 필로 바꾼다.
///
/// 하는 일 셋:
///  1. 그 자리의 하이햇·라이드를 걷어낸다 — 필과 겹치면 지저분하다
///  2. 스네어·탐을 16분으로 깔되 **세기를 점점 올린다**(밀어 올리는 느낌)
///  3. 바로 다음 마디 첫 박에 **크래시** — 매듭이 지어졌다는 신호
///
/// [loopBars] 는 한 판의 마디 수, [reps] 는 그 판을 몇 번 도는지 —
/// 둘을 곱한 것이 **이 구간의 길이**이고, 그 마지막 마디가 필 자리다.
/// [totalSec] 을 넘어가는 크래시는 안 넣는다(다음 구간이 자기 것을 넣는다).
/// 필을 **그 판이 이미 쓰는 악기로** 친다.
///
/// 여태 무조건 스네어 → 탐이었다. 그런데 엠비언트의 타악기 판(`Amb Perc`)에는
/// 크래시·림·셰이커만 있다 — 곡 전체에 스네어도 탐도 없는데 **필에서만 나왔다.**
/// 그 장르에 없는 악기가 매듭에서만 튀어나오면 그건 매듭이 아니라 사고다.
/// 있는 것 중에서 **굴릴 것**과 **떨어뜨릴 것**을 고른다.
(String, String)? _fillLanes(Set<String> have) {
  const rollOrder = ['snare', 'rim', 'clap', 'tom', 'hat', 'shaker'];
  const dropOrder = ['tom', 'snare', 'rim', 'clap', 'shaker', 'hat'];
  final roll = rollOrder.where(have.contains).firstOrNull;
  if (roll == null) return null; // 칠 것이 아무것도 없으면 필도 없다
  final drop = dropOrder.where(have.contains).firstOrNull ?? roll;
  return (roll, drop);
}

void applyFill(
  List<List<dynamic>> drums,
  String kit,
  double stepSec,
  int loopBars,
  int reps,
  FillSpec spec, {
  double at = 0,
  double? totalSec,
  bool crashOnStart = false,
  int spb = 16,
}) {
  if (spec.amount <= 0 || loopBars <= 0 || reps <= 0) return;
  // 구간 **첫 박의 크래시.**
  //
  // 매듭의 크래시는 「필이 끝난 다음 마디 첫 박」에 온다. 그런데 구간 끝 필의
  // 다음 마디는 **다음 구간**이라, 이 구간 안에서는 넣을 자리가 없었다 —
  // 그래서 정작 송폼이 넘어가는 자리에만 크래시가 없었다. 앞 구간이 필로 끝났다는
  // 것은 부르는 쪽이 아니까(`crashOnStart`), 여기서는 첫 박에 얹기만 한다.
  if (crashOnStart &&
      !drums.any(
        (d) => d[1] == 'crash' && ((d[4] as num).toDouble() - at).abs() < 1e-6,
      )) {
    drums.add([kit, 'crash', 3, 180.0, at]);
  }
  final stepsPerBar = spb;
  final barSec = stepsPerBar * stepSec;
  final totalBars = loopBars * reps;

  // ── 필을 넣을 마디 고르기 ──
  //
  // **구간이 끝나는 자리에 넣는다.** 이 함수는 한 구간(씬 루프 한 판, 또는 곡의
  // 한 구간)마다 한 번 불리므로, `totalBars - 1` 이 곧 그 구간의 마지막 마디다.
  // 여기가 「송폼이 넘어가는 자리」다.
  //
  // 구간이 길면(많이 반복되면) 안쪽에도 넣는다 — 2분짜리 한 구간에 매듭이
  // 하나뿐이면 그 안은 여전히 루프로 들린다.
  final fillBars = <int>{totalBars - 1};
  final inside = spec.insideBars;
  if (inside > 0) {
    for (var b = inside - 1; b < totalBars - 1; b += inside) {
      fillBars.add(b);
    }
  }
  if (fillBars.isEmpty) return;

  final fillSteps = math.min(spec.steps, stepsPerBar - 1);

  // **이 구간이 실제로 쓰는 악기**로만 친다(위 [_fillLanes] 참고).
  final have = <String>{
    for (final d in drums)
      if ((d[4] as num).toDouble() >= at - 1e-9 &&
          (d[4] as num).toDouble() < at + totalBars * barSec + 1e-9)
        d[1] as String,
  };
  final lanes = _fillLanes(have);
  if (lanes == null) return;
  final (rollLane, dropLane) = lanes;

  for (final bar in fillBars.toList()..sort()) {
    final barStart = at + bar * barSec;
    final fillStart = barStart + (stepsPerBar - fillSteps) * stepSec;
    final fillEnd = barStart + barSec;

    // ① **필 자리는 갈아엎는다.**
    //
    // 잔가지(하이햇·라이드·셰이커)만 걷어내려 했는데, 재 보니 패턴이 **이미
    // 자기 필을 갖고 있는 경우가 많았다**(로파이 코러스는 마지막 마디에
    // 스네어 3연타가 들어 있다). 그 위에 또 깔면 타격이 겹쳐 지저분해진다.
    //
    // 킥만 남긴다 — 킥은 발이라 필 중에도 계속 밟는다(실제 드러머가 그렇다).
    drums.removeWhere((d) {
      final t = (d[4] as num).toDouble();
      if (t < fillStart - 1e-9 || t >= fillEnd - 1e-9) return false;
      return d[1] != 'kick';
    });

    // ② 스네어·탐을 16분으로 깔며 세기를 올린다.
    //    **탐으로 내려가며 끝낸다** — 실제 드러머가 필 끝에서 하는 것이다.
    for (var i = 0; i < fillSteps; i++) {
      final t = fillStart + i * stepSec;
      if (totalSec != null && t >= at + totalSec - 1e-9) break;
      final k = fillSteps <= 1 ? 1.0 : i / (fillSteps - 1); // 0 → 1
      final vel = (1 + (k * 2).round()).clamp(1, 3);
      // 앞쪽은 굴리고, 뒤쪽은 떨어뜨린다 — 음정이 내려가며 다음 마디로 간다
      final lane = k < 0.5 ? rollLane : dropLane;
      final tomF = 200.0 - k * 70; // 탐이 점점 낮아진다
      drums.add([kit, lane, vel, tomF, t]);
    }

    // ③ 다음 마디 첫 박에 크래시 — 매듭
    final crashAt = fillEnd;
    final withinThisBlock = crashAt < at + totalBars * barSec - 1e-9;
    final withinSong = totalSec == null || crashAt < at + totalSec - 1e-9;
    if (withinThisBlock && withinSong) {
      drums.add([kit, 'crash', 3, 180.0, crashAt]);
    }
  }

  drums.sort(
    (a, b) => (a[4] as num).toDouble().compareTo((b[4] as num).toDouble()),
  );
}
