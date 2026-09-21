// 「두드려 넣기」가 **무엇을 어느 칸에 남길지** 정하는 계산 (5단계 46/N).
//
// 어려운 박자는 손으로 못 찍는다. 머릿속에 있는 리듬을 16칸 격자의 몇 번째 칸으로
// 옮겨 적으려면 그 리듬을 **이미 셀 줄 알아야** 하는데, 셀 줄 알면 어렵지 않다.
// 그래서 순서를 바꾼다 — **박자는 손으로 두드리고, 높낮이는 나중에.**
// 사람이 한 번에 하나씩만 하면 되는 일이 된다.
//
// 화면(`ui/tap_sheet.dart`)에서 떼어 놓은 이유는 `live_ops`·`prog_ops` 와 같다.
// 여기가 틀릴 수 있는 전부다:
//   · 손가락이 닿은 순간을 **몇 번째 칸**으로 볼 것인가(되접기·지연·칸 맞추기)
//   · 누르고 있던 동안을 **몇 칸 길이**로 적을 것인가
//   · 처음 높이를 **무슨 음**으로 할 것인가
// 셋 다 귀로는 「좀 이상한데」로만 느껴지고 무엇이 틀렸는지는 안 보인다. 숫자로 잰다.

import 'edit_ops.dart' show kMaxNoteLen;
import 'patterns.dart' show kStepsPerBar;
import 'prog_ops.dart';
import 'theory.dart';

/// 두드린 자리를 **어느 칸에 붙일 것인가.**
///
/// 초보가 두드리면 16분(한 박에 4칸)으로는 거의 늘 어긋난다 — 살짝 이른 것이
/// 옆 칸에 붙어 리듬이 삐뚤어진다. 8분(한 박에 2칸)이 기본인 이유다:
/// **친 대로 들리는 쪽**이 정확한 쪽보다 낫다. 잘게 쪼갠 리듬만 16분으로 바꾼다.
enum TapSnap { eighth, sixteenth }

extension TapSnapX on TapSnap {
  /// 칸 몇 개마다 붙는가. 8분 = 2칸, 16분 = 1칸.
  int get unit => this == TapSnap.eighth ? 2 : 1;
  String get label => this == TapSnap.eighth ? '8분' : '16분';
}

/// 두드림 하나 — 어느 판을 몇 번째 칸에, 몇 칸 길이로.
class TapHit {
  /// 두드린 판 번호. 가락·베이스·화음은 판이 하나라 늘 0, 드럼은 0~3.
  final int pad;
  final int step;
  final int len;
  const TapHit(this.pad, this.step, this.len);

  @override
  String toString() => 'TapHit($pad, $step, $len)';
}

/// 드럼에서 두드릴 네 자리. **더 늘리지 않는다** — 손가락 둘로 닿을 수 있는 만큼이
/// 여기까지다. 나머지 여섯(크래시·림·클랩…)은 찍어 넣거나, 찍힌 음을 위아래로
/// 끌어 옮기면 된다.
const List<(String lane, String label)> kTapDrumPads = [
  ('kick', '쿵'),
  ('snare', '탁'),
  ('hat', '치'),
  ('tom', '둥'),
];

/// 두드린 것을 모은다.
///
/// ── 늦게 잡히는 문제 ──
/// 귀에 들리는 소리는 엔진이 만든 것보다 **한 박자 늦게** 나온다(앞질러 만든 양 +
/// 장치 버퍼). "제때 쳤다"고 느낀 순간의 위치는 실제보다 그만큼 뒤다. 그대로
/// 반올림하면 **한 칸씩 밀린 판**이 나온다 → [latencySec] 만큼 되돌린 뒤 맞춘다.
/// (`LiveRecorder` 와 같은 이유·같은 처방이다. 둘이 어긋나면 안 되니 시험이 맞대 본다)
class TapRecorder {
  /// 지금 고치는 **판**의 칸 수(마디 × 16).
  final int steps;

  /// **씬 루프** 한 바퀴가 몇 마디인가. 판보다 길 수 있다(2마디 판을 고치는데
  /// 씬에 4마디 패드가 있으면 루프는 4마디) — 그때 위치를 그대로 쓰면 두 배로 샌다.
  final int loopBars;

  final double loopSec;
  final TapSnap snap;
  final double latencySec;

  /// 이 곡의 한 마디가 몇 칸인가 — 기본은 16(4/4, 여태와 같은 답).
  final int spb;

  /// 아직 안 뗀 손가락 — 판 번호 → 누른 자리(루프 안 0~1).
  final Map<int, double> _open = {};

  /// (판, 칸) → 두드림. 같은 자리를 다시 치면 덮어쓴다.
  final Map<String, TapHit> _hits = {};

  TapRecorder({
    required this.steps,
    required this.loopBars,
    required this.loopSec,
    this.snap = TapSnap.eighth,
    this.latencySec = 0,
    this.spb = kStepsPerBar,
  });

  int get count => _hits.length;

  int get _bars => loopBars > 0 ? loopBars : (steps ~/ spb);

  /// 루프 안 위치([pos], 0~1) → **이 판의 칸.**
  ///
  /// 되접는 규칙은 재생 막대(`headStep`)와 **같아야 한다** — 막대가 가리키는 칸과
  /// 두드린 것이 담기는 칸이 다르면, 보면서 쳤는데 딴 데 찍힌다.
  /// (시험이 둘을 맞대 본다. 「말없이 어긋난 두 표」는 여기서 제일 나기 쉽다)
  int stepOf(double pos) {
    if (steps <= 0) return 0;
    final back = loopSec > 0 ? latencySec / loopSec : 0.0;
    final p = ((pos - back) % 1.0 + 1.0) % 1.0;
    final raw = p * _bars * spb;
    final u = snap.unit;
    var s = (raw / u).round() * u;
    s %= steps;
    return s < 0 ? s + steps : s;
  }

  /// 누르고 있던 동안 → **몇 칸 길이.** 톡 친 것도 한 칸은 남는다(안 남으면 안 들린다).
  int lenOf(double from, double to) {
    var frac = to - from;
    if (frac < 0) frac += 1.0; // 판을 넘어갔다
    var n = (frac * _bars * spb).round();
    if (n < snap.unit) n = snap.unit;
    return n.clamp(1, steps < kMaxNoteLen ? steps : kMaxNoteLen);
  }

  void down(int pad, double pos) => _open[pad] = pos;

  /// 누른 것을 **안 적고 버린다** — 손가락이 눌리긴 했지만 음이 아니라
  /// 다른 뜻(위아래로 쓸어 음 높이 옮기기)으로 쓰였을 때. `up` 으로 닫으면
  /// 의도 없던 짧은 음이 한 칸 남는다.
  void cancel(int pad) => _open.remove(pad);

  /// 손가락을 뗐다 — **누른 자리**에 **잡고 있던 길이**로 적는다.
  /// 누른 적이 없으면(화면 밖에서 들어온 손가락) 아무 일도 안 한다.
  void up(int pad, double pos) {
    final from = _open.remove(pad);
    if (from == null) return;
    final step = stepOf(from);
    _hits['$pad:$step'] = TapHit(pad, step, lenOf(from, pos));
  }

  /// 한 바퀴가 끝났는데 아직 누르고 있는 것들 — **거기서 끊어 담는다.**
  /// 안 담으면 마지막 음이 통째로 사라진다(꾹 누른 마지막 음일수록 중요하다).
  void closeAll(double pos) {
    for (final pad in _open.keys.toList()) {
      up(pad, pos);
    }
  }

  /// 칸 순서로 — 편집기가 읽는 순서와 같게.
  List<TapHit> hits() {
    final out = _hits.values.toList();
    out.sort((a, b) => a.step == b.step
        ? a.pad.compareTo(b.pad)
        : a.step.compareTo(b.step));
    return out;
  }
}

/// 그 칸에 **흐르는 코드의 뿌리음.**
///
/// 두드려 넣은 음을 전부 같은 줄에 찍으면 「박자만 넣었다」가 눈에 보이긴 하지만,
/// 들으면 한 음이 계속 반복된다 — 방금 친 리듬이 음악으로 안 들린다.
/// 코드의 뿌리음에 놓으면 **그 자리에서 이미 어울린다.** 높낮이를 고치는 것이
/// 「틀린 것을 고치는 일」이 아니라 「더 낫게 만드는 일」이 된다.
///
/// [prog] 가 비었으면(코드 트랙이 없는 씬) 1도로 놓는다 — 조의 중심이라 안 튄다.
int tapDegree({
  required List<ProgSlot> prog,
  required int progSteps,
  required int step,
  required String type,
  required bool chord,
  required bool chromatic,
  required String mode,
}) {
  final d = _rootAt(prog, progSteps, step);
  // 화음 줄은 도수 0~6 을 그대로 쓴다(코드 판의 좌표계다)
  if (chord) return d;
  if (chromatic) {
    // 반음 줄은 0~24 — 가운데 옥타브에 놓는다(위아래로 옮길 자리가 양쪽에 남는다)
    final sc = scaleOf(mode);
    return (sc[d % 7] + 12).clamp(0, kProRows - 1);
  }
  // 낱음 줄은 0~14. 베이스는 아래 옥타브가 제 자리, 가락은 가운데(7~13)에 놓는다 —
  // 15줄의 한가운데라 위로도 아래로도 끌어 옮길 자리가 있다.
  return type == 'bass' ? d : d + 7;
}

/// [step] 자리에 걸려 있는 코드의 도수. 코드 판이 이 판보다 짧거나 길 수 있어
/// **코드 판 길이로 되접어** 찾는다.
int _rootAt(List<ProgSlot> prog, int progSteps, int step) {
  if (prog.isEmpty || progSteps <= 0) return 0;
  final s = ((step % progSteps) + progSteps) % progSteps;
  // 첫 코드가 0칸에서 시작하지 않을 수 있다 — 그 앞은 **마지막 코드**가 걸려 있다
  // (판이 도니까). 이걸 빠뜨리면 판 첫머리만 늘 1도가 된다.
  var found = prog.last.degree;
  for (final slot in prog) {
    if (s >= slot.step && s < slot.untilStep) {
      found = slot.degree;
      break;
    }
  }
  return found;
}

/// 두드린 것을 **음 목록에 얹는다.** 원본은 안 건드린다(새 목록을 돌려준다).
///
/// 화면에 두면 시험이 못 본다 — 여기가 「지우고 시작 / 위에 더하기」가 갈리는
/// 자리이고, 같은 자리에 이미 음이 있을 때 무엇이 남는지가 정해지는 자리다.
///
/// [oct] 는 코드 줄의 층(`NoteOps.chordOct`) — 새로 얹는 음도 그 줄의 층을 따라가야
/// 방금 넣은 것만 한 옥타브 아래로 떨어지지 않는다.
List<List<Object?>> tapToNotes(
  List<List<Object?>> notes,
  List<TapHit> hits, {
  required List<ProgSlot> prog,
  required int progSteps,
  required int steps,
  required String type,
  required bool chord,
  required bool chromatic,
  required String mode,
  int oct = 0,
  bool clear = false,
}) {
  final out = clear
      ? <List<Object?>>[]
      : [for (final n in notes) List<Object?>.from(n)];
  for (final h in hits) {
    if (h.step < 0 || h.step >= steps) continue;
    final degree = tapDegree(
      prog: prog,
      progSteps: progSteps,
      step: h.step,
      type: type,
      chord: chord,
      chromatic: chromatic,
      mode: mode,
    );
    // 꼬리가 판을 넘지 않게 자른다 — 넘긴 채로 두면 다음 바퀴 첫 음과 겹쳐 울린다
    final len = h.len.clamp(1, (steps - h.step).clamp(1, kMaxNoteLen));
    final row = oct == 0
        ? <Object?>[degree, h.step, len, 2]
        : <Object?>[degree, h.step, len, 2, null, oct];
    final at = out.indexWhere((n) => n[0] == degree && n[1] == h.step);
    if (at >= 0) {
      out[at] = row;
    } else {
      out.add(row);
    }
  }
  out.sort((a, b) => (a[1] as int).compareTo(b[1] as int));
  return out;
}

// ── 대목이 흘러가는 규칙 ──
//
// 「미리 세기 한 마디 → 판 한 바퀴 → 끝」은 **시간이 흐르는 일**이라 화면 안에 두면
// 시험이 못 본다. 못 보면 확인할 길은 실기뿐이고, 실기는 「넷부터 셌나」·「정말 한
// 바퀴만 돌았나」를 눈으로 세야 한다 — 그건 재는 시늉이다.
//
// 그래서 **박만 넣으면 대목이 나오는 것**으로 떼어 놨다. 화면은 오디오 시계에서
// 박을 읽어 여기에 넣고, 나온 대목을 그리기만 한다.

enum TapPhase {
  /// 마디 첫 박을 기다린다 — 박 중간에 「넷」이 시작되면 그 넷이 안 맞는다.
  wait,

  /// 미리 세기(4→3→2→1).
  count,

  /// 두드리는 중.
  rec,

  /// 한 바퀴가 다 돌았다.
  done,
}

class TapClock {
  /// 씬 루프 한 바퀴가 몇 박인가(마디×4). 박 번호가 여기서 되돈다.
  final int beatsPerLoop;

  /// **판** 한 바퀴가 몇 박인가 — 녹음은 이만큼만 돈다.
  final int lapBeats;

  final int countBeats;
  final int beatsPerBar;

  TapClock({
    required this.beatsPerLoop,
    required this.lapBeats,
    this.countBeats = 4,
    this.beatsPerBar = 4,
  });

  TapPhase phase = TapPhase.wait;

  /// 시작부터 지난 박 — **단조 증가**한다. 루프 위치는 되도니까(0.9 → 0.1) 그대로
  /// 빼면 음수가 나온다. 넘어간 만큼을 더해서 쌓는다.
  double _run = 0;
  double? _prev;

  /// 지금 대목이 시작된 자리(`_run` 기준).
  double _mark = 0;

  /// 미리 세기에 **남은 박**(4→3→2→1). 다른 대목에서는 0.
  int get left {
    if (phase != TapPhase.count) return 0;
    final n = countBeats - (_run - _mark).floor();
    return n.clamp(1, countBeats);
  }

  /// 녹음이 얼마나 갔나(0~1). 다른 대목에서는 0.
  double get progress {
    if (phase != TapPhase.rec || lapBeats <= 0) return 0;
    return ((_run - _mark) / lapBeats).clamp(0.0, 1.0);
  }

  /// 루프 안 위치를 **박 단위**로 넣는다(0 ~ [beatsPerLoop]).
  /// 대목이 바뀌었으면 true — 그때만 다시 그리면 된다.
  bool update(double beatF) {
    final p = _prev;
    _prev = beatF;
    if (p == null) return false; // 첫 값은 기준으로만 쓴다
    var d = beatF - p;
    // **판이 진짜로 넘어간 것과 그냥 흔들린 것을 가른다.** `LoopClock.pos()`
    // 는 0.25초마다 오는 실측값과 그 사이 보간이 만나는 자리에서 아주 살짝
    // 뒤로 흔들릴 수 있다(스톱워치 보간이 다음 실측을 살짝 앞질렀다가 값이
    // 오면 도로 맞춰지는 정도). 이걸 "판을 한 바퀴 다 돌았다"로 잘못 읽으면
    // 그 자리에서 `_run` 이 `beatsPerLoop` 만큼 통째로 튀어 미리 세기·녹음이
    // 실제로는 몇 백 ms 만에 "다 끝난 것"처럼 되어 버린다(실기기에서 재현—
    // 흔들림 −0.18박을 반 바퀴 넘게 잘못 되접어 15.8박을 얹었다). 진짜
    // 한 바퀴(거의 −beatsPerLoop)와 흔들림(0에 가까운 음수)은 크기 차이가
    // 뚜렷하니 절반을 기준으로 가른다 — 흔들림은 그냥 0으로(전진도 후퇴도
    // 안 한 것으로) 무시한다.
    if (d < -beatsPerLoop / 2) {
      d += beatsPerLoop; // 진짜로 판이 넘어갔다
    } else if (d < 0) {
      d = 0; // 흔들림 — 무시
    }
    _run += d;

    final was = phase;
    switch (phase) {
      case TapPhase.wait:
        // 마디 첫 박을 **넘어서는 순간**에 시작한다. 창을 연 그 순간이 마침
        // 첫 박이어도 세지 않는다 — 이미 반쯤 지났을 수 있다.
        if (p.floor() != beatF.floor() && beatF.floor() % beatsPerBar == 0) {
          phase = TapPhase.count;
          _mark = _run;
        }
      case TapPhase.count:
        if (_run - _mark >= countBeats) {
          phase = TapPhase.rec;
          // **딱 그 자리에서** 시작한 것으로 친다. 지나친 만큼을 안 빼면
          // 녹음이 그만큼 늦게 끝나 판 앞머리를 두 번 돌게 된다.
          _mark += countBeats;
        }
      case TapPhase.rec:
        if (_run - _mark >= lapBeats) {
          phase = TapPhase.done;
          _mark += lapBeats;
        }
      case TapPhase.done:
        break;
    }
    return phase != was;
  }
}
