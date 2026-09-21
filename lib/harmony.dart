// 어울리는 코드 고르기(Auto Harmony) — **이론을 몰라도 화성이 맞게.** (Phase 4 · 계획 6-4)
//
// 계획의 요구: 「현재 Key + 현재 Melody → 추천 Chord」.
//
// ── 왜 쉬운 문제인가 ──
// 이 프로젝트는 멜로디도 코드도 **도수**로 저장한다(멜로디는 스케일 도수 0~14,
// 코드는 다이아토닉 번호 0~6). 주파수를 거칠 일이 없다 — 조를 바꾸면 둘 다 같이
// 옮겨 가므로, **어느 조에서 풀든 답이 같다.** 그래서 여기는 조를 거의 안 본다
// (코드의 성질이 장/단/dim 중 무엇인지 볼 때만 쓴다).
//
// ── 무엇을 고르는가 ──
// 마디(또는 반 마디)마다 다이아토닉 7화음 중 하나를 고른다. 고르는 기준 넷:
//  1. **코드톤이 많이 맞을수록** 좋다 — 멜로디 음이 그 코드에 들어 있는가
//  2. **긴 음·센 음·강박의 음**이 더 중요하다 (지나가는 16분음표는 화성을 안 정한다)
//  3. **dim 은 웬만하면 피한다** — 이론상 맞아도 초보 귀에는 「틀린 소리」로 들린다
//  4. **처음과 끝은 으뜸화음 쪽으로** — 그래야 곡처럼 시작하고 끝난다
//
// ── 마디별로 고르면 안 된다 ──
// 처음엔 마디마다 제일 잘 맞는 코드를 따로 골랐다. 자기 채점표로는 89% 가 나왔는데
// **사람이 쓴 코드와 같은 것을 고른 건 34% 뿐이었다.** 제 답을 제 채점표로 채점한 것이다.
//
// 사람이 쓰는 진행은 마디별 최적이 아니라 **흐름**이다 — 5도 아래로 떨어지고(V→I),
// 한 음 올라가고(IV→V), 3도 아래로 미끄러진다(I→vi). 지나가는 음 때문에 그 마디만
// 보면 딴 코드가 더 맞아 보여도, 흐름을 지키는 쪽이 음악으로 들린다.
// 그래서 **한 줄 전체를 한 번에** 고른다(자리마다 7가지 × 이어지는 점수, 동적 계획법).
//
// 값을 돌려주기만 한다. 무엇을 언제 바꿀지는 부르는 쪽이 정한다.
import 'patterns.dart';
import 'theory.dart';

/// 한 자리의 추천 — [index] 는 `diatonicChords` 의 번호(0=i, 4=V …).
class ChordPick {
  final int index;
  final int step;
  final int len;

  /// 0~1. 1에 가까울수록 「이 코드가 확실히 낫다」.
  /// 멜로디가 비어 있거나 어느 코드나 비슷하면 낮게 나온다.
  final double confidence;
  const ChordPick(this.index, this.step, this.len, this.confidence);
}

/// 코드가 코드로 **이어지는** 점수. 뿌리 움직임(root motion)으로만 본다 —
/// 도수 공간이라 조와 무관하다. 값은 화성학의 흔한 순서를 그대로 옮긴 것이다.
///
///  +3 = 5도 아래로(V→i, i→iv) — 제일 강한 진행
///  +1 = 한 음 위로(iv→v)
///  +5 = 3도 아래로(i→VI)
///  +6 = 한 음 아래로(VII→VI)
const List<double> _motion = [
  -0.12, // 0 제자리 — 안 움직이면 곡이 안 흐른다(아주 약하게만 민다)
  0.20, // 1 한 음 위
  0.05, // 2 3도 위
  0.30, // 3 5도 아래 ★
  0.05, // 4 5도 위
  0.15, // 5 3도 아래
  0.10, // 6 한 음 아래
];

/// 그 코드의 코드톤인가 — 도수 공간에서 보면 조와 무관하다.
bool _isChordTone(int degree, int chordIndex) {
  final d = ((degree % 7) + 7) % 7;
  final r = ((chordIndex % 7) + 7) % 7;
  final iv = (d - r + 7) % 7;
  return iv == 0 || iv == 2 || iv == 4;
}

/// 멜로디 한 줄에 어울리는 코드를 자리마다 고른다.
///
/// [melody] 는 편집기·패턴과 같은 형식 `[도수, 스텝, 길이, 세기, 글라이드?]`.
/// [bars] 는 몇 마디짜리인지, [perBar] 는 한 마디에 코드를 몇 개 놓을지(1 또는 2).
/// [flow] 는 **흐름을 얼마나 중히 보는가** — 0 이면 마디마다 따로 고르고(그러면
/// 진행이 안 나온다), 크면 멜로디를 좀 덜 맞추더라도 흔한 진행 쪽으로 간다.
List<ChordPick> suggestChords(
  List<List<Object?>> melody, {
  required int bars,
  required MusicKey key,
  int perBar = 1,
  double flow = 1.0,
  int spb = kStepsPerBar,
}) {
  if (bars <= 0) return const [];
  final slots = bars * (perBar < 1 ? 1 : perBar);
  final slotSteps = bars * spb ~/ slots;
  final quals = diatonicChords(key).map((c) => c.type).toList();

  // ── ① 자리마다 7가지 코드의 「맞는 정도」 ──
  final fit = List.generate(slots, (_) => List<double>.filled(7, 0));
  final mass = List<double>.filled(slots, 0);
  for (var s = 0; s < slots; s++) {
    final from = s * slotSteps, to = from + slotSteps;
    final weights = <int, double>{};
    var total = 0.0;
    for (final n in melody) {
      final step = (n[1] as num).toInt();
      final len = n.length > 2 ? (n[2] as num).toInt() : 1;
      final lo = step > from ? step : from;
      final hi = (step + len) < to ? (step + len) : to;
      final overlap = hi - lo;
      if (overlap <= 0) continue;
      final vel = n.length > 3 ? (n[3] as num).toDouble() : 2.0;
      // **강박의 음이 화성을 정한다.** 지나가는 뒷박 16분은 거의 안 본다.
      final onBeat = step % 4 == 0 ? 1.6 : (step % 2 == 0 ? 1.0 : 0.5);
      final w = overlap * vel * onBeat;
      final d = ((n[0] as num).toInt() % 7 + 7) % 7;
      weights[d] = (weights[d] ?? 0) + w;
      total += w;
    }
    mass[s] = total;
    for (var c = 0; c < 7; c++) {
      var sc = 0.0;
      for (final e in weights.entries) {
        sc += _isChordTone(e.key, c) ? e.value * 2 : -e.value;
      }
      // dim 은 이론상 맞아도 초보 귀에는 틀린 소리다
      if (quals[c] == 'dim') sc -= (total <= 0 ? 1.0 : total) * 0.9;
      if (c == 0) {
        // 처음은 곡이 시작하는 자리, 끝은 돌아오는 자리 — 으뜸화음 쪽으로 민다
        if (s == 0) sc += (total <= 0 ? 1.0 : total) * 0.5;
        if (s == slots - 1) sc += (total <= 0 ? 1.0 : total) * 0.6;
      }
      // 멜로디가 쉬는 자리는 맞고 틀리고가 없다 — 흐름이 정하게 둔다
      fit[s][c] = total <= 0 ? 0 : sc / total;
    }
  }

  // ── ② 한 줄 전체를 한 번에 고른다 (동적 계획법) ──
  //
  // 마디별로 따로 고르면 「그 마디만 보면 맞는데 진행이 아닌」 줄이 나온다.
  // 앞 코드에서 이어지는 점수(_motion)를 같이 더해 **전체 합이 최대**인 줄을 찾는다.
  final best = List.generate(slots, (_) => List<double>.filled(7, -1e9));
  final from = List.generate(slots, (_) => List<int>.filled(7, -1));
  for (var c = 0; c < 7; c++) {
    best[0][c] = fit[0][c];
  }
  for (var s = 1; s < slots; s++) {
    for (var c = 0; c < 7; c++) {
      for (var pc = 0; pc < 7; pc++) {
        if (best[s - 1][pc] <= -1e8) continue;
        // **멜로디가 쉬는 자리는 코드를 안 바꾼다.** 맞고 틀리고가 없으니
        // 흐름 점수만 남는데, 그러면 「움직이면 좋다」만 보고 혼자 돌아다닌다
        // (실제로 0→3→6→2 가 나왔다). 바꿀 이유가 없으면 그대로 두는 게 맞다.
        final move = mass[s] <= 0
            ? (c == pc ? 0.5 : -0.5)
            : _motion[(c - pc + 7) % 7] * flow;
        final v = best[s - 1][pc] + fit[s][c] + move;
        if (v > best[s][c]) {
          best[s][c] = v;
          from[s][c] = pc;
        }
      }
    }
  }

  var last = 0;
  var lastScore = -1e9, secondScore = -1e9;
  for (var c = 0; c < 7; c++) {
    if (best[slots - 1][c] > lastScore) {
      secondScore = lastScore;
      lastScore = best[slots - 1][c];
      last = c;
    } else if (best[slots - 1][c] > secondScore) {
      secondScore = best[slots - 1][c];
    }
  }
  final path = List<int>.filled(slots, 0);
  path[slots - 1] = last;
  for (var s = slots - 1; s > 0; s--) {
    path[s - 1] = from[s][path[s]] < 0 ? 0 : from[s][path[s]];
  }

  // 얼마나 확실한가 — 1등 줄과 2등 줄의 차이. 멜로디가 비면 0 이다.
  final conf = ((lastScore - secondScore) / slots).clamp(0.0, 1.0);
  final out = <ChordPick>[];
  for (var s = 0; s < slots; s++) {
    out.add(
      ChordPick(path[s], s * slotSteps, slotSteps, mass[s] <= 0 ? 0 : conf),
    );
  }
  return out;
}

/// 추천을 **코드 패턴 줄**로 바꾼다 — `NotePatternDef.notes` 와 같은 형식
/// `[코드번호, 스텝, 길이, 세기]`. 편집기에 그대로 넣을 수 있다.
List<List<Object?>> chordRowsOf(List<ChordPick> picks, {int vel = 2}) => [
  for (final p in picks) <Object?>[p.index, p.step, p.len, vel],
];

/// 코드 줄이 멜로디와 얼마나 맞는지 — 0~1. **고치기 전에 견줘 보라고** 있는 함수다.
///
/// 이 값이 이미 높으면 자동 화성은 도움이 안 된다(라이브러리 곡들이 그렇다).
/// 낮을 때만 권하는 게 맞다.
double harmonyFit(
  List<List<Object?>> melody,
  List<List<Object?>> chords, {
  required int bars,
}) {
  if (melody.isEmpty || chords.isEmpty || bars <= 0) return 1;
  var hit = 0.0, total = 0.0;
  for (final n in melody) {
    final step = (n[1] as num).toInt();
    final len = n.length > 2 ? (n[2] as num).toInt() : 1;
    final vel = n.length > 3 ? (n[3] as num).toDouble() : 2.0;
    final onBeat = step % 4 == 0 ? 1.6 : (step % 2 == 0 ? 1.0 : 0.5);
    final w = len * vel * onBeat;
    // 이 음이 울릴 때 실제로 깔려 있는 코드를 찾는다
    var cur = -1, curStep = -1;
    for (final c in chords) {
      final cs = (c[1] as num).toInt();
      if (cs <= step && cs > curStep) {
        curStep = cs;
        cur = (c[0] as num).toInt();
      }
    }
    if (cur < 0) continue;
    total += w;
    if (_isChordTone((n[0] as num).toInt(), cur)) hit += w;
  }
  return total <= 0 ? 1 : hit / total;
}
