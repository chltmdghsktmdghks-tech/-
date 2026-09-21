// 씬의 **코드 진행**을 읽고 바꾸는 계산 — 화면은 이걸 부르기만 한다.
//
// 여태 코드는 클립 안에만 있었다. 코러스 화성을 하나 바꾸려면 코드 패턴을 열어
// 고치고, 베이스를 열어 같은 만큼 옮기고, 멜로디도 다시 맞춰야 했다 —
// **세 군데를 손으로 맞추는 일**이고, 하나라도 빠뜨리면 그 마디만 어긋난 채 돈다.
//
// 여기서는 코드 자리 하나를 바꾸면 그 구간의 베이스·멜로디를 **도수 차만큼**
// 같이 옮긴다. 이 프로젝트는 멜로디도 코드도 도수로 저장하므로(주파수를 안 거친다)
// 옮기는 일이 그냥 덧셈이다 — 조가 무엇이든 답이 같다.
//
// 옛 앱(뮤직 두들)의 `P.tl.prog[마디]` 를 가져온 것이되 **단위가 다르다.**
// 거기는 마디마다 하나였는데, 여기서는 **코드 음 하나가 곧 한 자리**다 —
// 반 마디에 코드가 둘인 패턴(로파이·시티팝에 흔하다)을 마디로 묶으면
// 뒤 코드는 바꿀 길이 없다.

import 'meter.dart';
import 'patterns.dart';
import 'theory.dart';

/// 멜로디·베이스 줄이 쓰는 도수 범위(웹 `ROWS` 와 같다 — 2옥타브+1).
const int kMaxDegree = 14;

/// 코드 트랙의 코드 자리 하나.
class ProgSlot {
  /// 지금 걸려 있는 다이아토닉 번호 0~6 (0=1도).
  final int degree;
  final int step;

  /// 다음 코드가 시작하는 스텝(마지막이면 패턴 끝). 따라 옮길 구간이 이만큼이다.
  final int untilStep;

  /// 이 코드가 도는 곡의 박자 — 기본은 4/4(여태와 같은 답).
  final MeterDef meter;
  const ProgSlot(this.degree, this.step, this.untilStep, {this.meter = kMeterFour});

  int get bar => step ~/ meter.stepsPerBar;

  /// 마디 안 몇 박째(0=마디 머리).
  int get beat => meterBeatAt(meter, step) - 1;

  /// 「3마디」 처럼 마디 머리면 마디만, 아니면 박까지 적는다.
  String get label => beat == 0 ? '${bar + 1}마디' : '${bar + 1}마디 ${beat + 1}박';
}

/// 코드 목록에서 자리들을 뽑는다. [steps] 는 패턴 전체 칸 수.
///
/// 같은 칸에 코드 음이 둘 이상이면 **하나로 본다** — 코드 한 덩어리를 두 줄로
/// 찍어 둔 패턴이 있다(그걸 두 자리로 세면 같은 자리가 두 번 나온다).
List<ProgSlot> readProg(
  List<List<Object?>> notes,
  int steps, {
  MeterDef meter = kMeterFour,
}) {
  final byStep = <int, int>{}; // step → degree (제일 낮은 번호)
  for (final n in notes) {
    final d = n[0] as int;
    final s = n[1] as int;
    if (s < 0 || s >= steps) continue;
    final cur = byStep[s];
    if (cur == null || d < cur) byStep[s] = d;
  }
  final at = byStep.keys.toList()..sort();
  return [
    for (var i = 0; i < at.length; i++)
      ProgSlot(
        byStep[at[i]]!,
        at[i],
        i + 1 < at.length ? at[i + 1] : steps,
        meter: meter,
      ),
  ];
}

/// [from] 에서 [to] 로 갈 때 **가까운 쪽** 도수 차 (−3~+3).
///
/// 1도에서 7도로 가는 것은 여섯 칸 올라가는 게 아니라 **한 칸 내려가는** 것이다.
/// 이걸 안 하면 베이스가 옥타브를 넘나들며 뛴다.
int progDelta(int from, int to) {
  var d = (to - from) % 7;
  if (d > 3) d -= 7;
  return d;
}

/// 코드 자리 하나의 번호를 [to] 로 바꾼 **새 목록**. 원본은 안 건드린다.
///
/// 코드 타입(5번째 칸)과 층(6번째 칸)은 그대로 둔다 — 「m7 으로 해 뒀다」·
/// 「한 옥타브 아래로 내려 뒀다」는 화성을 바꾼다고 없어질 뜻이 아니다.
List<List<Object?>> setProg(List<List<Object?>> notes, ProgSlot slot, int to) {
  return [
    for (final n in notes)
      if (n[1] == slot.step && n[0] == slot.degree)
        [to, ...n.skip(1)]
      else
        List<Object?>.from(n),
  ];
}

/// 도수 차를 **반음 수**로 — 반음 줄(프로 모드) 판을 옮길 때 쓴다.
///
/// 도수 줄은 「3도 위」가 조에 따라 3반음일 수도 4반음일 수도 있다. 반음 줄에서
/// 도수만큼 옮기면 **딴 음**이 된다(옛 앱의 `progSemi` 가 있던 이유).
int progSemiDelta(int from, int to, String mode) {
  final sc = scaleOf(mode);
  var s = sc[((to % 7) + 7) % 7] - sc[((from % 7) + 7) % 7];
  if (s > 6) {
    s -= 12;
  } else if (s < -6) {
    s += 12;
  }
  return s;
}

/// 따라가는 트랙(베이스·멜로디)의 음을 [slot] 구간 안에서 옮긴다.
///
/// [delta] 는 **도수 차**다. [chromatic] 판(프로 모드)이면 도수가 아니라 반음이
/// 들어 있으므로 [semiDelta] 만큼 옮긴다 — 안 그러면 3도 올리려다 3반음만
/// 올라가 화성이 어긋난다(소리는 나므로 오류로는 안 잡힌다).
///
/// 범위를 벗어나면 **한 옥타브씩 되돌린다**(자르지 않는다) — 자르면 여러 음이
/// 맨 윗줄에 겹쳐 붙어서 가락이 뭉개진다.
List<List<Object?>> followProg(
  List<List<Object?>> notes,
  ProgSlot slot,
  int delta, {
  bool chromatic = false,
  int semiDelta = 0,
}) {
  final move = chromatic ? semiDelta : delta;
  if (move == 0) return [for (final n in notes) List<Object?>.from(n)];
  final span = chromatic ? 12 : 7;
  final top = chromatic ? kProRows - 1 : kMaxDegree;
  return [
    for (final n in notes)
      if ((n[1] as int) >= slot.step && (n[1] as int) < slot.untilStep)
        [_wrap((n[0] as int) + move, span, top), ...n.skip(1)]
      else
        List<Object?>.from(n),
  ];
}

int _wrap(int d, int span, int top) {
  var v = d;
  while (v > top) {
    v -= span;
  }
  while (v < 0) {
    v += span;
  }
  return v;
}

/// [Project.changeChord] 를 되돌리는 표 — 바꾸기 **직전**의 패턴들.
///
/// 새로 만들지 않고 이미 잘 도는 그릇(`NotePatternDef`)을 그대로 담는다.
/// `clips` 는 씬이 가리키던 패턴 이름이다 — 라이브러리 패턴을 고치면
/// 「내 패턴」 복사본으로 갈아 끼워지므로, 되돌릴 때 이것도 같이 돌려놔야 한다.
class ProgUndo {
  final Map<String, NotePatternDef> notes;
  final Map<String, String?> clips;
  const ProgUndo(this.notes, this.clips);
}
