// 결과 손잡이 — **음악 용어가 아니라 들리는 결과로 만진다.** (Phase 2 · 개선 계획 4-4)
//
// 계획의 요구:
//   Energy   Calm ───── Hype
//   Density  Simple ─── Busy
//   Groove   Straight ─ Swing
//   "처음부터 완벽한 자동화까지 구현할 필요는 없습니다. 우선 **구조를 확장 가능하게**."
//
// 그래서 여기는 **한 곳에서 끝나는 변환**으로 만들었다. 엔진도 신스도 패턴 데이터도
// 안 건드린다 — `SceneSequencer` 가 만들어 낸 (음 목록, 타격 목록)을 마지막에 한 번
// 주무를 뿐이다. 손잡이를 더 붙이고 싶으면 [applyFeel] 에 한 줄씩 더하면 된다.
//
// 이 자리를 고른 이유: 재생·내보내기가 **같은 목록**을 쓴다. 여기서 바꾸면
// 들은 것과 파일이 저절로 같아진다(Phase 1 에서 그게 같다는 걸 못 박아 뒀다).
import 'dart:math' as math;

import 'genre_mix.dart';

/// 잔가지 — 빼거나 더해도 곡이 안 무너지는 레인들. `arrange.dart`·`variation.dart`
/// 의 같은 이름 상수와 **뜻이 같다**(세 파일이 각자 정의를 들고 있다 — 공유 라이브러리를
/// 새로 만들 만큼 자주 바뀌는 목록은 아니지만, 그래서 한 번은 실제로 어긋났었다).
///
/// **이전에 `'shake'` 가 들어 있었다.** 드럼 레인 이름은 언제나 `kDrumLanes`
/// (patterns.dart)의 정식 이름 — `'cowbell'` — 을 쓴다. `'shake'`는 그 축약형이고
/// `drums.dart`의 **소리 낼 때만** 쓰는 내부 별명(`kDrumAlias`)이라, 여기(작곡 단계)
/// 목록에 넣으면 **아무 타격과도 안 맞는 죽은 항목**이 된다 — 동시에 `'cowbell'`이
/// 빠져 있어서 카우벨은 밀도를 올려도 그루브를 켜도 하이햇·라이드·셰이커가 받는
/// 처리를 하나도 못 받았다(2026-09-03 워크플로 사냥에서 잡았다).
const Set<String> _twigs = {'hat', 'ride', 'shaker', 'cowbell'};

/// 세 손잡이. 전부 0~1 이고 **가운데(0.5)가 지금까지의 소리**다 —
/// 기본값이 곧 '아무것도 안 한 상태'여야 예전 곡이 그대로 들린다.
/// (그루브만 0 이 기본이다. 반듯한 게 원래 모습이라서.)
class Feel {
  /// 차분 ↔ 신남. 세기(벨로시티)를 올리고 내린다.
  final double energy;

  /// 단순 ↔ 빽빽. 약박을 덜어 내거나, 하이햇을 잘게 쪼갠다.
  final double density;

  /// 반듯 ↔ 스윙. 뒷박을 뒤로 민다.
  final double groove;

  /// **필** — 몇 마디마다 매듭을 지을지. 0 이면 안 넣는다 (계획 6-2).
  /// 기본은 켬(0.6) — 필이 없으면 곡이 아니라 루프로 들린다.
  /// 다만 **가운데가 예전 소리** 원칙은 지킨다: `isDefault` 는 필을 안 본다.
  final double fill;

  /// **변화** — 같은 패턴이 되풀이될 때 얼마나 바꿀지 (계획 6-1).
  /// 0 이면 늘 똑같이. 기본은 켬(0.6) — 필과 같은 이유다.
  /// 이 값은 [applyFeel] 이 아니라 **시퀀서가 만들 때** 쓴다(`variation.dart`) —
  /// 어느 바퀴인지는 다 만들어 놓은 목록에서는 알 수 없기 때문이다.
  final double vary;

  const Feel({
    this.energy = 0.5,
    this.density = 0.5,
    this.groove = 0,
    this.fill = 0.6,
    this.vary = 0.6,
  });

  static const Feel none = Feel();

  /// **필은 안 본다** — 기본이 켬(0.6)이라 `isDefault` 에 넣으면
  /// "가운데면 아무것도 안 한다"는 규칙과 부딪힌다.
  /// (필은 `applyFill` 이 따로 보고, `applyFeel` 은 세기·빽빽함·그루브만 본다.)
  bool get isDefault =>
      (energy - 0.5).abs() < 1e-9 &&
      (density - 0.5).abs() < 1e-9 &&
      groove.abs() < 1e-9;

  Feel copyWith({
    double? energy,
    double? density,
    double? groove,
    double? fill,
    double? vary,
  }) => Feel(
    energy: energy ?? this.energy,
    density: density ?? this.density,
    groove: groove ?? this.groove,
    fill: fill ?? this.fill,
    vary: vary ?? this.vary,
  );

  Map<String, dynamic> toJson() => {
    'e': energy,
    'd': density,
    'g': groove,
    'f': fill,
    'v': vary,
  };

  factory Feel.fromJson(Map<String, dynamic>? j) => j == null
      ? Feel.none
      : Feel(
          energy: (j['e'] as num?)?.toDouble() ?? 0.5,
          density: (j['d'] as num?)?.toDouble() ?? 0.5,
          groove: (j['g'] as num?)?.toDouble() ?? 0,
          fill: (j['f'] as num?)?.toDouble() ?? 0.6,
          vary: (j['v'] as num?)?.toDouble() ?? 0.6,
        );

  /// 손잡이 값 → 사람 말. 숫자(0.73)는 아무 뜻도 없다.
  static String energyWord(double v) => v < 0.2
      ? '아주 차분'
      : v < 0.42
      ? '차분'
      : v <= 0.58
      ? '보통'
      : v < 0.8
      ? '신남'
      : '아주 신남';
  static String densityWord(double v) => v < 0.2
      ? '아주 단순'
      : v < 0.42
      ? '단순'
      : v <= 0.58
      ? '보통'
      : v < 0.8
      ? '빽빽'
      : '아주 빽빽';

  /// 칩에 한 마디로 적을 말 — **제일 많이 움직인 손잡이**를 보여 준다.
  /// 그루브만 만졌는데 칩에 「보통」(기운)이 뜨면 뭘 만졌는지 알 수가 없다.
  /// 제일 많이 벗어난 손잡이 하나를 말로. 칩은 한 줄이라 다 못 적는다.
  ///
  /// 예전엔 맨 앞에서 `isDefault` 로 걸러 냈는데, `isDefault` 는 매듭·변화를 안 본다 —
  /// 그래서 매듭만 껐을 때도 「느낌」이라고 적혔다(아래 매듭 가지가 닿지 않았다).
  /// 지금은 다섯 손잡이의 벗어난 정도를 다 재고, **전부 0 일 때만** 「느낌」이다.
  String get chipWord {
    final de = (energy - 0.5).abs() * 2;
    final dd = (density - 0.5).abs() * 2;
    final dg = groove;
    final df = (fill - 0.6).abs() / 0.6; // 기본 0.6 에서 얼마나 벗어났나
    final dv = (vary - 0.6).abs() / 0.6; // 기본 0.6 에서 얼마나 벗어났나
    final most = [de, dd, dg, df, dv].reduce((a, b) => a > b ? a : b);
    if (most < 1e-9) return '느낌';
    if (dv >= most) return '변화 ${varyWord(vary)}';
    if (df >= most) return '매듭 ${fillWord(fill)}';
    if (dg >= de && dg >= dd) return grooveWord(groove);
    return de >= dd ? energyWord(energy) : densityWord(density);
  }

  /// 말이 **실제 동작과 하나씩 짝**이어야 한다 — 손잡이는 움직이는데 하는 일이
  /// 같으면 그게 제일 나쁜 손잡이다. 상태가 셋(안 함 · 두 바퀴 · 네 바퀴)이라
  /// 말도 셋이다. (`VarySpec.cycle` 의 경계와 같은 자리에서 갈린다.)
  static String varyWord(double v) => v <= 0.05
      ? '없음'
      : v < 0.5
      ? '가끔'
      : '자주';

  static String fillWord(double v) => v < 0.05
      ? '없음'
      : v < 0.45
      ? '가끔'
      : v < 0.8
      ? '보통'
      : '자주';

  static String grooveWord(double v) => v < 0.08
      ? '반듯'
      : v < 0.4
      ? '살짝 스윙'
      : v < 0.75
      ? '스윙'
      : '많이 스윙';
}

/// 세기 1~3 을 [energy] 로 밀고 당긴다. 가운데면 그대로.
int _shiftVel(int vel, double energy) {
  final d = (energy - 0.5) * 2; // -1 ~ 1
  return (vel + d.round()).clamp(1, 3);
}

/// **뒷박을 뒤로 민다.** 두 칸 중 뒤엣것이 늦게 오는 것이 스윙이다.
///
/// [unit] 이 '한 칸' — 8분이면 8분 스윙, 16분이면 16분 스윙(셔플)이다.
/// 최대치(1.0)에서 셋잇단(2:1) — 한 칸의 1/3 만큼 민다. 그 이상은 스윙이 아니라
/// 박자가 틀린 것으로 들린다.
/// 스윙 = **시간을 늘였다 줄이는 것**이지 몇 개를 미는 것이 아니다.
///
/// 예전에는 「격자에 딱 맞는 홀수 칸만 뒤로 민다」였다. 두 가지가 걸렸다:
///  1. 격자에 안 맞는 음(필로 깔린 것, 글라이드)이 **혼자 제자리에 남아** 어긋났다
///  2. 8분 위의 음은 16분 격자에서 짝수 칸이라 **영원히 안 밀렸다** — 재즈 멜로디가
///     한 음도 안 움직인 이유다
///
/// 지금은 두 칸씩 묶어 **앞칸을 늘이고 뒷칸을 줄인다.** 격자 위든 사이든 전부
/// 같은 비율로 밀리므로 프레이즈가 통째로 스윙한다.
/// [amt] 는 앞칸이 얼마나 길어지는가 — 1/3 이면 삼잇단(정통 스윙 2:1)이다.
double _swing(double t, double unit, double amt) {
  if (amt <= 0 || unit <= 0) return t;
  final pair = unit * 2;
  final k = (t / pair).floor();
  final base = k * pair;
  final x = t - base; // 0 ~ 2u
  if (x < unit) return base + x * (1 + amt); // 앞칸: 늘어난다
  return base + unit * (1 + amt) + (x - unit) * (1 - amt); // 뒷칸: 줄어든다
}

/// 손잡이 → 실제 늘림 비율. **가운데에서 이미 스윙으로 들려야 한다.**
/// 선형이면 0.5 에서 1/6 밖에 안 밀려 「살짝 늦은 것」으로만 들린다.
/// 정렬된 목록에서 [v] 의 자리. 없으면 그보다 큰 첫 자리.
int _lowerBound(List<int> xs, int v) {
  var lo = 0, hi = xs.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (xs[mid] < v) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo;
}

double _swingAmount(double groove) =>
    groove <= 0 ? 0 : 0.34 * math.pow(groove, 0.65).toDouble();

/// **스윙을 걸 격자를 정한다.**
///
/// 처음엔 무조건 8분에 걸었다. 그런데 로파이·힙합·트랩은 **16분 기반**이라
/// 8분 자리에 있는 음이 몇 개 안 된다 — 타격 616개 중 88개만 밀렸고,
/// 그래서 슬라이더를 끝까지 올려도 **"스윙 모르겠음"** 이었다(사용자 지적).
///
/// 그 판이 16분을 쓰면 16분 셔플로, 8분만 쓰면 8분 스윙으로 건다.
/// **드럼으로 정하고 음정 악기도 같은 격자를 쓴다** — 악기마다 격자가 다르면
/// 그건 스윙이 아니라 어긋난 것이다.
/// 스윙 격자 — **장르가 정한다**(`kGenreSwingGrid`).
///
/// 예전에는 드럼 타격 자리를 세어서 추측했다. 두 번 고쳤는데 두 번 다 반대쪽이
/// 깨졌다(재즈를 살리면 로파이가 죽고, 로파이를 살리면 재즈가 죽었다).
/// 추측으로 될 일이 아니다 — 그 곡이 8분 스윙인지 16분 셔플인지는 **장르가 아는 것**이다.
/// 모르는 장르만 예전처럼 드럼을 세어 고른다.
double _swingUnit(
  String? genre,
  List<List<dynamic>> drums,
  List<List<dynamic>> notes,
  double stepSec,
) {
  final g = genre == null ? null : kGenreSwingGrid[genre];
  if (g == 8) return stepSec * 2;
  if (g == 16) return stepSec;

  (int, int) countOdd(Iterable<double> times) {
    var odd16 = 0, odd8 = 0;
    final eighth = stepSec * 2;
    for (final t in times) {
      final i16 = (t / stepSec).round();
      if ((t - i16 * stepSec).abs() < stepSec * 0.02 && i16.isOdd) odd16++;
      final i8 = (t / eighth).round();
      if ((t - i8 * eighth).abs() < eighth * 0.02 && i8.isOdd) odd8++;
    }
    return (odd16, odd8);
  }

  final (d16, d8) = countOdd([for (final d in drums) (d[4] as num).toDouble()]);
  if (d16 + d8 > 0) return d16 >= d8 ? stepSec : stepSec * 2;
  final (n16, n8) = countOdd([for (final n in notes) (n[6] as num).toDouble()]);
  return n16 >= n8 ? stepSec : stepSec * 2;
}

/// 목록을 **제자리에서** 주무른다. `SceneBuild` 를 새로 만들지 않는다
/// (재생 경로가 이 목록을 그대로 들고 가므로 복사하면 두 벌이 된다).
///
/// [stepSec] 은 16분음표 하나의 길이 — 스윙과 '약박' 판정에 쓴다.
void applyFeel(
  List<List<dynamic>> notes,
  List<List<dynamic>> drums,
  Feel f,
  double stepSec, {
  String? genre,
}) {
  if (f.isDefault) return; // 가운데면 아무것도 안 한다 — 예전 소리 그대로

  // ── ① 세기 (Energy) ──
  if ((f.energy - 0.5).abs() > 1e-9) {
    for (final n in notes) {
      n[3] = _shiftVel(n[3] as int, f.energy);
    }
    for (final d in drums) {
      d[2] = _shiftVel(d[2] as int, f.energy);
    }
  }

  // ── ② 빽빽함 (Density) ──
  //
  // **왼쪽(단순)은 덜어 낸다.** 약박에 있는 것부터 지운다 — 16분 뒷자리가 제일 먼저,
  // 그다음 8분 뒷자리. 골격(강박)은 끝까지 남는다.
  //
  // **오른쪽(빽빽)은 하이햇을 쪼갠다.** 없던 멜로디를 지어낼 수는 없으니
  // 리듬 쪽에서 늘린다 — 실제로 곡을 바쁘게 만드는 것도 대개 하이햇이다.
  if (f.density < 0.5 - 1e-9) {
    final cut = (0.5 - f.density) * 2; // 0~1
    bool weak(double t, int mod) {
      final step = (t / stepSec).round();
      return step % mod != 0;
    }

    // 0.0 에서 16분 뒷자리 전부 + 8분 뒷자리 절반까지 덜어 낸다
    notes.removeWhere((n) {
      final t = (n[6] as num).toDouble();
      if (cut > 0.15 && weak(t, 2)) return true; // 16분 뒷자리
      if (cut > 0.7 && weak(t, 4)) return true; // 8분 뒷자리
      return false;
    });
    drums.removeWhere((d) {
      final t = (d[4] as num).toDouble();
      final lane = d[1] as String;
      // 킥·스네어는 **골격**이다. 빼면 곡이 무너진다 — 마지막까지 남긴다.
      if (lane == 'kick' || lane == 'snare') return cut > 0.9 && weak(t, 4);
      if (cut > 0.15 && weak(t, 2)) return true;
      if (cut > 0.6 && weak(t, 4)) return true;
      return false;
    });
  } else if (f.density > 0.5 + 1e-9) {
    final add = (f.density - 0.5) * 2; // 0~1
    final extra = <List<dynamic>>[];
    // **하이햇만 쪼개면 재즈에서 손잡이가 죽는다.** 재즈는 하이햇이 없고
    // 라이드·셰이커로 시간을 센다(엠비언트도 셰이커뿐이다). 재 보니 재즈·엠비언트에서
    // 「빽빽」이 **0%** 였다 — 끌어도 아무 일이 안 일어났다.
    // 그루브가 이미 쓰는 「잔가지」 묶음을 여기서도 쓴다.
    final twigs = _twigs;
    // 레인마다 자리를 모아 둔다 — **고르게 놓인 줄만** 쪼갠다.
    final byLane = <String, List<int>>{};
    for (final d in drums) {
      final lane = d[1] as String;
      if (!twigs.contains(lane)) continue;
      (byLane[lane] ??= []).add(((d[4] as num).toDouble() / stepSec).round());
    }
    for (final e in byLane.entries) {
      e.value.sort();
    }
    for (final d in drums) {
      final lane = d[1] as String;
      if (!twigs.contains(lane)) continue;
      final t = (d[4] as num).toDouble();
      final step = (t / stepSec).round();
      final steps = byLane[lane]!;
      // 다음 타격까지의 간격 — 그 절반 자리에 끼운다.
      final at = _lowerBound(steps, step);
      if (at + 1 >= steps.length) continue;
      final gap = steps[at + 1] - steps[at];
      // 2칸(16분)·4칸(8분)은 그냥 쪼갠다. 이미 촘촘하면(1칸) 손대지 않는다.
      // 8·16칸으로 널찍한 줄(엠비언트 셰이커가 온음표다)은 **손잡이를 끝까지
      // 밀었을 때만** 쪼갠다 — 그 여백이 그 장르의 소리이기 때문이다.
      // (안 그러면 엠비언트에서 「빽빽」이 0% 로 죽어 있다.)
      if (gap != 2 && gap != 4 && gap != 8 && gap != 16) continue;
      if (gap >= 8 && add < 0.55) continue;
      // 얼마나 끼울지 — 0.5 이하면 한 칸 걸러, 1.0 이면 전부
      if (add < 0.55 && ((step ~/ gap).isOdd)) continue;
      extra.add([
        d[0],
        d[1],
        // 끼워 넣는 것은 **약하게** — 같은 세기로 넣으면 기계가 된다
        ((d[2] as int) - 1).clamp(1, 3),
        d[3],
        t + stepSec * (gap ~/ 2),
      ]);
    }
    drums.addAll(extra);
  }

  // ── ③ 그루브 (Groove) ──
  if (f.groove > 0) {
    final unit = _swingUnit(genre, drums, notes, stepSec);
    final amt = _swingAmount(f.groove);
    for (final n in notes) {
      n[6] = _swing((n[6] as num).toDouble(), unit, amt);
    }
    for (final d in drums) {
      d[4] = _swing((d[4] as num).toDouble(), unit, amt);
    }
    // **뒷칸은 여리게.** 스윙은 길이만이 아니라 세기의 무늬다 — 「따-단」의 '단'이
    // 같은 크기면 그냥 늦게 친 것으로 들린다. 골격(킥·스네어)은 안 건드리고
    // 잔가지(하이햇·라이드·셰이커)만 손본다.
    if (f.groove >= 0.35) {
      final twigs = _twigs;
      final pair = unit * 2;
      for (final d in drums) {
        if (!twigs.contains(d[1] as String)) continue;
        final t = (d[4] as num).toDouble();
        final x = t - (t / pair).floor() * pair;
        if (x > unit * (1 + amt) - 1e-9) {
          d[2] = ((d[2] as int) - 1).clamp(1, 3);
        }
      }
    }
  }

  // 시간 순서를 지킨다 — 뒤에서 예약 큐가 정렬하지만, 내보내기·시험이
  // 이 목록을 그대로 읽으므로 여기서 맞춰 두는 편이 덜 놀란다.
  notes.sort(
    (a, b) => (a[6] as num).toDouble().compareTo((b[6] as num).toDouble()),
  );
  drums.sort(
    (a, b) => (a[4] as num).toDouble().compareTo((b[4] as num).toDouble()),
  );
}
