// 변형(Variation) — **되풀이되는 것만 바꾼다.** (Phase 4 · 개선 계획 6-1)
//
// 계획 6-1 의 요구:
//   각 Pattern 에 Original / Variation 1 / 2 / 3 / Fill / Break 개념을 구조화하고,
//   "사용자가 직접 모든 노트를 만드는 것이 아니라 기존 Pattern 을 기반으로
//    자연스러운 변형을 생성해야 한다."
//
// ── 무엇을 바꾸고 무엇을 안 바꾸는가 ──
// **작곡된 것은 안 바꾸고, 되풀이된 것만 바꾼다.**
// 4마디짜리 패턴은 4마디로 작곡된 것이다 — 그 안을 손대면 원곡이 망가진다.
// 반면 2마디 패턴이 4마디 판을 채우려고 **두 번 도는 것**은 작곡이 아니라 되풀이다.
// 그 두 번째 바퀴가 변형을 받는다. 필에서 배운 것과 같은 원칙이다
// (「패턴이 이미 자기 필을 갖고 있었다」 — 있는 것 위에 덧칠하지 않는다).
//
// ── 난수를 안 쓴다 ──
// 변형 번호(0·1·2·3)만으로 결정된다. 같은 곡은 몇 번을 틀어도, 내보내도 같다.
// (`drums.dart` 의 흔들림처럼 씨앗을 관리할 필요조차 없다.)
//
// ── 못 하면 다음 것을 한다 ──
// 하우스 패턴에는 스네어가 없다(박수를 쓴다). 「고스트 스네어」를 그런 패턴에
// 걸면 **아무 일도 안 일어난다** — 변형 번호는 올라갔는데 소리는 그대로다.
// 그래서 각 수는 「할 게 없으면 null」을 돌려주고, 그러면 다음 수를 시도한다.
// 변형 번호가 올라가면 **반드시 뭔가 달라진다**는 것이 이 파일의 약속이다.
import 'dart:math' as math;
import 'patterns.dart';

/// 얼마나 자주 바꿀지. 손잡이는 **하나**다(사람은 「조금/많이」로 생각한다).
class VarySpec {
  /// 0 이면 늘 똑같이 — 예전 소리 그대로.
  final double amount;
  const VarySpec({this.amount = 0.5});
  static const VarySpec none = VarySpec(amount: 0);

  /// 몇 바퀴마다 원본으로 돌아오는지.
  /// 조금(2) = 원본↔변형 1 이 번갈아, 많이(4) = 원본→1→2→3 한 바퀴.
  /// 값이 클수록 **원본이 나오는 비율이 줄어든다**(1/2 → 1/4).
  int get cycle => amount <= 0.05 ? 1 : (amount < 0.5 ? 2 : 4);
}

/// 이 바퀴가 몇 번째 변형인지. 0 이면 **원본 그대로**.
///
/// [turn] 은 이 패턴이 몇 바퀴째 도는지 — 판 안의 되풀이(짧은 패턴이 판을 채우는 것)와
/// 판 자체의 되풀이를 합쳐 센 값이다. 그래서 2마디 패턴은 4마디 판 **안에서도** 변한다.
int varyIndex(int turn, VarySpec s) =>
    s.cycle <= 1 ? 0 : ((turn % s.cycle) + s.cycle) % s.cycle;

// ── 드럼 ───────────────────────────────────────────────────────────────

/// 잔가지 — 빼도 곡이 안 무너지는 것들. 킥·스네어·박수는 **골격**이라 안 건드린다.
const Set<String> _twigs = {'hat', 'shaker', 'cowbell', 'ride'};

/// 골격 — 세기조차 안 건드린다. 킥이 여려지면 곡이 주저앉는다.
const Set<String> _bones = {'kick', 'snare', 'clap'};

/// 드럼 한 바퀴를 [v] 번째 변형으로 바꾼다. [v] 가 0 이면 **받은 것을 그대로** 돌려준다.
List<DrumHit> varyDrums(List<DrumHit> hits, int v, {int spb = kStepsPerBar}) {
  if (v <= 0 || hits.isEmpty) return hits;
  // **잔가지 밀도가 제일 잘 들린다.** 처음엔 「약박 하나 걸러 하나」처럼 조심스럽게
  // 만들었는데 사용자가 「모르겠다」고 했다 — 4마디 안에서 타격 몇 개가 바뀌는 건
  // 귀에 안 걸린다. 지금은 **한 바퀴의 성격을 통째로 바꾼다**:
  // 성기게(16분 하이햇 → 8분) ↔ 촘촘하게(8분 → 16분). 골격은 그대로라 안전하다.
  final moves = [
    _thinTwigs,
    _doubleTwigs,
    (List<DrumHit> h) => _ghostPush(h, spb),
    _accent,
  ];
  for (var i = 0; i < moves.length; i++) {
    final r = moves[(v - 1 + i) % moves.length](hits);
    if (r != null) return r;
  }
  return hits;
}

/// ① 성기게 — 잔가지의 **약박을 전부** 뺀다. 16분 하이햇이 8분이 된다.
///
/// 약박을 두 단계로 본다. 먼저 16분 뒷자리(홀수 칸)를 노린다 — 제일 안전하다.
/// 그런데 8분으로만 치는 패턴(셰이커 0·2·4·…)에는 홀수 칸이 아예 없어서
/// **아무 일도 안 일어난다.** 그때는 8분 뒷자리(4로 나눠 2 남는 칸)까지 본다.
List<DrumHit>? _thinTwigs(List<DrumHit> hits) {
  for (final weak in [(int s) => s.isOdd, (int s) => s % 4 == 2]) {
    final out = <DrumHit>[];
    var cut = 0;
    for (final h in hits) {
      if (_twigs.contains(h.lane) && weak(h.step)) {
        cut++;
        continue;
      }
      out.add(h);
    }
    if (cut > 0) return out;
  }
  return null;
}

/// ② 촘촘하게 — 잔가지를 **배로 쪼갠다**. 8분 하이햇이 16분이 된다.
/// 끼워 넣는 것은 한 단 여리게 — 같은 세기로 넣으면 기계가 된다(느낌 손잡이와 같은 규칙).
List<DrumHit>? _doubleTwigs(List<DrumHit> hits) {
  final busy = {for (final h in hits) '${h.lane}:${h.step}'};
  final add = <DrumHit>[];
  for (final h in hits) {
    if (!_twigs.contains(h.lane) || h.step.isOdd) continue;
    final s = h.step + 1;
    if (busy.contains('${h.lane}:$s')) continue;
    add.add(DrumHit(h.lane, s, (h.vel - 1).clamp(1, 3)));
  }
  return add.isEmpty ? null : [...hits, ...add];
}

/// ③ 고스트 + 밀기 — 둘 다 작은 수라 **묶어서** 한 바퀴 몫으로 만든다.
/// 따로 두면 「타격 하나 늘었다」뿐이라 아무도 못 알아챈다.
List<DrumHit>? _ghostPush(List<DrumHit> hits, int spb) {
  final a = _ghostSnare(hits);
  final b = _pushKick(a ?? hits, spb);
  return b ?? a;
}

/// 스네어 바로 앞 16분에 **아주 여린**(세기 1) 스네어.
/// 실제 드러머가 무의식적으로 넣는 것이고, 세기가 낮아 골격을 안 흔든다.
List<DrumHit>? _ghostSnare(List<DrumHit> hits) {
  final busy = {for (final h in hits) '${h.lane}:${h.step}'};
  final add = <DrumHit>[];
  var n = 0;
  for (final h in hits) {
    if (h.lane != 'snare') continue;
    final s = h.step - 1;
    if (s < 0 || busy.contains('snare:$s')) continue;
    if ((n++).isEven) continue; // 스네어마다 넣으면 과하다 — 하나 걸러 하나
    add.add(DrumHit('snare', s, 1));
  }
  return add.isEmpty ? null : [...hits, ...add];
}

/// 마지막 16분에 킥 하나 — 다음 바퀴로 밀어 넣는 느낌이 난다.
/// 킥이 아예 없는 패턴(브레이크)에는 안 넣는다 — 없던 발이 생기면 딴 곡이 된다.
List<DrumHit>? _pushKick(List<DrumHit> hits, int spb) {
  if (!hits.any((h) => h.lane == 'kick')) return null;
  var last = 0;
  for (final h in hits) {
    if (h.step > last) last = h.step;
  }
  final s = (last ~/ spb + 1) * spb - 1;
  if (hits.any((h) => h.lane == 'kick' && h.step == s)) return null;
  return [...hits, DrumHit('kick', s, 2)];
}

/// ④ 악센트 옮기기 — **마지막 수.** 위 셋이 전부 할 게 없는 패턴이 있다
/// (발라드 인트로·프로그 브레이크는 림과 셰이커뿐이고, 그 셰이커가 4분마다만 친다).
/// 그런 패턴은 뺄 것도 더할 것도 없으니 **세기의 무늬**를 바꾼다 —
/// 강박은 세게, 약박은 여리게. 골격(킥·스네어·박수)은 세기조차 안 건드린다.
List<DrumHit>? _accent(List<DrumHit> hits) {
  final out = <DrumHit>[];
  var did = false;
  for (final h in hits) {
    if (_bones.contains(h.lane)) {
      out.add(h);
      continue;
    }
    final v = (h.step % 4 == 0 ? h.vel + 1 : h.vel - 1).clamp(1, 3);
    if (v != h.vel) did = true;
    out.add(DrumHit(h.lane, h.step, v));
  }
  return did ? out : null;
}

// ── 베이스 · 멜로디 ────────────────────────────────────────────────────

/// 음정 있는 한 바퀴를 [v] 번째 변형으로. [type] 에 따라 **수의 순서**가 다르다 —
/// 베이스는 끝을 들어 올리는 게 제일 자연스럽고, 멜로디는 덜어 내는 게 제일 자연스럽다.
List<MelodicHit> varyMelodic(
  List<MelodicHit> hits,
  String type,
  int v, {
  int spb = kStepsPerBar,
}) {
  if (v <= 0 || hits.isEmpty) return hits;
  // 세 수는 **자리를 바꾸는** 것들이다. 세기만 바꾸는 수(`_softer`)는 맨 뒤에 둔다 —
  // 세기 단이 셋뿐이라 한 단만 내려도 바퀴 전체가 눈에 띄게 작아진다. 앞의 셋이
  // 전부 할 게 없을 때(음이 강박에만 있고, 너무 높고, 이미 이어져 있을 때)만 쓴다.
  List<MelodicHit>? legato(List<MelodicHit> h) => _legato(h, spb);
  final moves = type == 'bass'
      ? [_liftLast, _thinWeak, legato, _softer]
      // 멜로디는 **통째로 옥타브 위**가 제일 잘 들린다 — 「두 번째 벌스는 한 옥타브
      // 위로」는 실제 편곡에서 늘 쓰는 수이고, 음이 그대로라 틀릴 수가 없다.
      : [_thinWeak, _octaveUp, legato, _liftLast, _softer];
  for (var i = 0; i < moves.length; i++) {
    final r = moves[(v - 1 + i) % moves.length](hits);
    if (r != null) return r;
  }
  return hits;
}

/// ① 덜어 내기 — **약박(16분 뒷자리)** 만 하나 걸러 하나 뺀다. 강박은 골격이라 남는다.
List<MelodicHit>? _thinWeak(List<MelodicHit> hits) {
  final out = <MelodicHit>[];
  var n = 0, cut = 0;
  for (final h in hits) {
    if (h.step.isOdd) {
      if ((n++).isEven) {
        cut++;
        continue;
      }
    }
    out.add(h);
  }
  return cut == 0 ? null : out;
}

/// 한 바퀴를 **통째로 옥타브 위**로. 화성은 그대로고 자리도 그대로다 —
/// 바뀌는 건 높이뿐이라 안전한데 귀에는 제일 크게 걸린다.
/// 너무 높아지면(1400Hz 위) 안 올린다.
List<MelodicHit>? _octaveUp(List<MelodicHit> hits) {
  var hi = 0.0;
  for (final h in hits) {
    if (h.freq > hi) hi = h.freq;
  }
  if (hi <= 0 || hi * 2 > 1400) return null;
  return [
    for (final h in hits)
      MelodicHit(
        h.step,
        h.len,
        h.vel,
        h.freq * 2,
        h.glideFromFreq > 0 ? h.glideFromFreq * 2 : 0,
      ),
  ];
}

/// 끝을 들어 올리기 — 마지막 음을 한 옥타브 위로. 악구가 끝났다는 표시가 된다.
/// 너무 높아지면(1600Hz 위) 안 올린다 — 삑 소리가 나느니 안 하는 게 낫다.
List<MelodicHit>? _liftLast(List<MelodicHit> hits) {
  var idx = 0;
  for (var i = 1; i < hits.length; i++) {
    if (hits[i].step >= hits[idx].step) idx = i;
  }
  final x = hits[idx];
  final f = x.freq * 2;
  if (f > 1600) return null;
  final out = List<MelodicHit>.of(hits);
  out[idx] = MelodicHit(x.step, x.len, x.vel, f, x.glideFromFreq);
  return out;
}

/// ③ 이어 붙이기 — 음을 **다음 음이 시작할 때까지** 늘인다(레가토).
/// 끊어 치던 바퀴가 이어지면 같은 음인데도 딴 연주처럼 들린다.
/// **겹치게는 안 늘인다** — 겹치면 베이스가 두 음 울려 탁해진다.
List<MelodicHit>? _legato(List<MelodicHit> hits, int spb) {
  final order = [for (var i = 0; i < hits.length; i++) i]
    ..sort((a, b) => hits[a].step.compareTo(hits[b].step));
  final len = [for (final h in hits) h.len];
  var did = false;
  for (var i = 0; i < order.length - 1; i++) {
    final a = order[i], b = order[i + 1];
    final gap = hits[b].step - hits[a].step;
    // **원래 끄는 음만 잇는다.** 16분·8분으로 스쳐 가는 음(len<3)까지 늘이면
    // 지나가는 음이 눌러앉아 코드와 단2도로 운다 — 록 리프의 Ab, 발라드의 Eb 가
    // 실제로 그랬다(`melody_clash_test` 가 변형 3바퀴에서 잡았다).
    // 레가토는 원래 「끄는 음들을 이어 붙이는 것」이지 스치는 음을 늘이는 게 아니다.
    if (len[a] < 3) continue;
    // 한 마디를 넘겨서까지 늘이지는 않는다 — 엠비언트처럼 음 사이가 먼 곡에서
    // 몇 초짜리 음이 겹겹이 쌓인다(소리도 탁하고 목소리도 낭비된다).
    if (gap > len[a] && gap <= spb) {
      len[a] = gap;
      did = true;
    }
  }
  if (!did) return null;
  return [
    for (var i = 0; i < hits.length; i++)
      MelodicHit(
        hits[i].step,
        len[i],
        hits[i].vel,
        hits[i].freq,
        hits[i].glideFromFreq,
      ),
  ];
}

/// ④ 여리게 — 한 바퀴를 통째로 한 단 낮춘다. **다음 바퀴가 더 세게 들린다**(대비).
/// 위 셋이 전부 할 게 없을 때만 쓰는 마지막 수다.
List<MelodicHit>? _softer(List<MelodicHit> hits) {
  if (hits.every((h) => h.vel <= 1)) return null;
  return [
    for (final h in hits)
      MelodicHit(
        h.step,
        h.len,
        (h.vel - 1).clamp(1, 3),
        h.freq,
        h.glideFromFreq,
      ),
  ];
}

// ── 코드 ──────────────────────────────────────────────────────────────

/// 코드 한 바퀴를 [v] 번째 변형으로.
///
/// **코드에서는 타격을 안 뺀다.** 코드 하나가 곧 그 마디의 화성이라, 빼면 진행이
/// 사라진다(Am–F 에서 F 를 빼면 그냥 Am 두 마디다). 그래서 화성은 그대로 두고
/// **두께와 세기**만 만진다.
List<ChordHit> varyChord(List<ChordHit> hits, int v, {int spb = kStepsPerBar}) {
  if (v <= 0 || hits.isEmpty) return hits;
  final moves = [
    _openChord,
    (List<ChordHit> h) => _legatoChord(h, spb),
    _softChord,
  ];
  for (var i = 0; i < moves.length; i++) {
    final r = moves[(v - 1 + i) % moves.length](hits);
    if (r != null) return r;
  }
  return hits;
}

/// ① 얇게 — 코드의 **맨 윗음**만 뺀다.
///
/// 자리바꿈(theory.dart `voiceLead`)이 들어온 뒤로는 맨 윗음이 근음일 수도 있다.
/// 그래도 괜찮다 — 베이스 트랙이 근음을 따로 짚으니 근음 없는 자리도 성립한다.
///
/// 다만 3화음의 **둘째 자리바꿈**(5음–근음–3음)에서 맨 윗음을 빼면 5음+근음, 즉
/// 텅 빈 4도만 남아 **장단이 사라진다.** 그때는 가운데를 뺀다 — 맨 밑음은 그대로
/// 남고(변형이 화성을 안 잃는다는 약속) 3음이 살아난다.
List<ChordHit>? _openChord(List<ChordHit> hits) {
  var did = false;
  final out = <ChordHit>[];
  for (final c in hits) {
    if (c.freqs.length < 3) {
      out.add(c);
      continue;
    }
    final sorted = List<double>.of(c.freqs)..sort();
    int drop;
    if (c.freqs.length >= 4) {
      // 네 음 이상이면 **속 성부**(밑에서 셋째)를 뺀다 — 근음 자리에서는 대개 5음이다.
      // 맨 윗음을 빼면 안 된다: 멜로디가 그 음을 겹쳐 짚고 있을 때 그걸 빼면
      // 멜로디만 덩그러니 남아 밑음과 단2도로 운다(시티팝 인트로가 그랬다).
      // 바깥 두 음(밑음·윗음)을 남기는 것이 건반에서 화음을 얇게 하는 법이다.
      drop = c.freqs.indexOf(sorted[2]);
    } else {
      var top = 0;
      for (var i = 1; i < c.freqs.length; i++) {
        if (c.freqs[i] > c.freqs[top]) top = i;
      }
      drop = top;
      final rest = List<double>.of(c.freqs)..removeAt(top);
      rest.sort();
      final semi = (12 * math.log(rest[1] / rest[0]) / math.ln2).round();
      if (semi == 5 || semi == 7) {
        // 빈 4·5도만 남는다 — 가운데를 대신 뺀다
        drop = c.freqs.indexOf(sorted[1]);
      }
    }
    out.add(
      ChordHit(c.step, c.len, c.vel, List<double>.of(c.freqs)..removeAt(drop)),
    );
    did = true;
  }
  return did ? out : null;
}

/// ② 이어 붙이기 — 코드를 다음 코드까지 늘인다. 끊어 치던 것이 깔리는 것으로 바뀐다.
List<ChordHit>? _legatoChord(List<ChordHit> hits, int spb) {
  final order = [for (var i = 0; i < hits.length; i++) i]
    ..sort((a, b) => hits[a].step.compareTo(hits[b].step));
  final len = [for (final c in hits) c.len];
  var did = false;
  for (var i = 0; i < order.length - 1; i++) {
    final a = order[i], b = order[i + 1];
    final gap = hits[b].step - hits[a].step;
    if (gap > len[a] && gap <= spb) {
      len[a] = gap;
      did = true;
    }
  }
  if (!did) return null;
  return [
    for (var i = 0; i < hits.length; i++)
      ChordHit(hits[i].step, len[i], hits[i].vel, hits[i].freqs),
  ];
}

/// ③ 여리게 — 코드는 배경이라, 한 단 낮추면 멜로디가 앞으로 나온다.
List<ChordHit>? _softChord(List<ChordHit> hits) {
  if (hits.every((c) => c.vel <= 1)) return null;
  return [
    for (final c in hits)
      ChordHit(c.step, c.len, (c.vel - 1).clamp(1, 3), c.freqs),
  ];
}
