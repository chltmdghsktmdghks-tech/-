// **연주해서 곡을 만든다** — 씬을 눌러 가며 넘긴 순서가 그대로 구간표가 된다.
//
// 여태 곡을 만드는 길은 하나였다: 곡 화면에서 「＋구간 붙이기」로 하나씩 놓기.
// 그건 **적는 일**이지 만드는 일이 아니다. 씬을 틀어 놓고 인트로 → 벌스 → 코러스로
// 넘겨 보는 것이 훨씬 자연스럽고, 그때 이미 사람은 곡을 만들고 있다.
// 그 손짓을 그냥 받아 적으면 된다.
//
// ── 화면에서 떼어 놓은 이유 ──
// 「몇 판이나 머물렀나」를 초에서 판 수로 바꾸는 셈이 이 기능의 전부다. 그 셈이
// 틀리면 곡 길이가 통째로 어긋나는데, 화면 안에 있으면 눌러 보지 않고는 못 잰다.

import 'project.dart';

/// 씬을 하나 골라 머문 기록.
class ArrangeStep {
  /// 몇 번째 씬인가.
  final int scene;

  /// 언제 골랐나 — 재생을 시작한 뒤 흐른 초.
  final double at;
  const ArrangeStep(this.scene, this.at);
}

/// 씬 전환을 받아 적는다.
///
/// **같은 씬을 다시 누른 것은 안 적는다** — 그건 넘어간 게 아니라 다시 튼 것이다
/// (씬 칩을 두 번 눌렀다고 구간이 둘이 되면 곡이 이상해진다).
class ArrangeRecorder {
  final List<ArrangeStep> steps = [];

  void mark(int scene, double atSec) {
    if (steps.isNotEmpty && steps.last.scene == scene) return;
    steps.add(ArrangeStep(scene, atSec));
  }

  int get count => steps.length;
  bool get isEmpty => steps.isEmpty;

  void clear() => steps.clear();
}

/// 받아 적은 것을 **구간표**로 바꾼다.
///
/// [endSec] 은 멈춘 시각. 마지막 구간은 거기까지 머문 것으로 친다.
/// [loopSecOf] 는 그 씬 한 판이 몇 초인가 — 씬마다 패턴 길이·템포가 달라서
/// 밖에서 받는다(`SceneSequencer.songSpans` 와 같은 셈을 쓰는 쪽이 준다).
///
/// **판 수는 반올림한다.** 사람이 손으로 넘기면 판 경계에 딱 맞을 리가 없다 —
/// 0.8판 머문 것은 1판으로 보는 게 맞다(내림하면 스치듯 지난 구간이 통째로 사라진다).
/// 0판이 되는 일은 없다: 눌렀다는 것 자체가 「여기 한 판」이라는 뜻이다.
List<Section> sectionsFrom(
  ArrangeRecorder rec,
  double endSec, {
  required double Function(int scene) loopSecOf,
  int maxReps = 32,
}) {
  final out = <Section>[];
  for (var i = 0; i < rec.steps.length; i++) {
    final s = rec.steps[i];
    final until = i + 1 < rec.steps.length ? rec.steps[i + 1].at : endSec;
    final held = until - s.at;
    final one = loopSecOf(s.scene);
    // 한 판이 0초일 수는 없다(빈 씬이면 밖에서 4마디로 친다) — 나눗셈을 지킨다
    final reps = one <= 0 ? 1 : (held / one).round().clamp(1, maxReps);
    out.add(Section(s.scene, reps: reps));
  }
  return out;
}

// ── 곡 길이를 목표에 맞추기 ──
//
// 「짧게 / 보통 / 길게」를 고르면 그 길이에 가까워지게 구간을 덜거나 더한다.
// **마디가 아니라 초로 잰다** — 78BPM 로파이와 128BPM 하우스는 같은 마디 수라도
// 길이가 배로 다르다.
//
// 인트로·아웃트로는 안 건드린다. 곡의 처음과 끝은 **자리를 지켜야 하는 것**이라
// 길이를 맞추자고 뺐다 붙였다 할 자리가 아니다.

/// 목표 길이(초). 옛 웹 판과 같은 값을 쓴다.
const Map<String, double> kSongTargets = {'짧게': 125, '보통': 205, '길게': 285};

/// [sections] 를 [targetSec] 에 가깝게 만든다. **원본은 안 건드린다.**
///
/// [secOf] 는 그 씬 한 판이 몇 초인가(`SceneSequencer.sceneLoopSec`).
/// [roleOfSection] 은 그 구간이 인트로·아웃트로인지 — 그 둘은 안 건드린다.
///
/// 길면 **가운데에서 판 수를 줄이고**, 그래도 길면 구간을 덜어낸다.
/// 짧으면 가운데 구간의 판 수를 늘린다. 구간을 **새로 만들지는 않는다** —
/// 없던 대목을 지어내면 사용자가 만든 곡이 아니게 된다.
List<Section> fitToLength(
  List<Section> sections,
  double targetSec, {
  required double Function(int scene) secOf,
  required bool Function(int index) isEnd,
  int maxReps = 16,
}) {
  final out = [for (final s in sections) Section(s.scene, reps: s.reps)];
  if (out.isEmpty || targetSec <= 0) return out;

  double total() {
    var t = 0.0;
    for (final s in out) {
      t += secOf(s.scene) * s.reps;
    }
    return t;
  }

  /// 가운데(인트로·아웃트로가 아닌) 구간 번호들 — 긴 것부터.
  List<int> middle() {
    final idx = [
      for (var i = 0; i < out.length; i++)
        if (!isEnd(i)) i,
    ];
    idx.sort(
      (a, b) => (secOf(out[b].scene) * out[b].reps).compareTo(
        secOf(out[a].scene) * out[a].reps,
      ),
    );
    return idx;
  }

  // 한 번에 한 판씩 고친다 — 목표를 지나치기 직전에 멈춘다.
  // (한 번에 크게 바꾸면 목표를 훌쩍 넘어가서 「맞췄다」가 무색해진다)
  var guard = 0;
  while (guard++ < 400) {
    final now = total();
    final mid = middle();
    if (mid.isEmpty) break;
    if (now > targetSec) {
      // 제일 긴 가운데 구간에서 한 판 뺀다
      final i = mid.first;
      final one = secOf(out[i].scene);
      if (out[i].reps <= 1 || one <= 0) break;
      // 빼서 목표에 **더 가까워질 때만** 뺀다
      if ((now - one - targetSec).abs() >= (now - targetSec).abs()) break;
      out[i].reps--;
    } else {
      // 제일 짧은 가운데 구간에 한 판 더한다 — 고르게 자란다
      final i = mid.last;
      final one = secOf(out[i].scene);
      if (one <= 0 || out[i].reps >= maxReps) break;
      if ((now + one - targetSec).abs() >= (now - targetSec).abs()) break;
      out[i].reps++;
    }
  }
  return out;
}
