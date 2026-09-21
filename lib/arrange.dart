// 구간 성격(Build / Break / Drop) — **이름이 소리를 바꾸게 한다.** (Phase 4 · 계획 6-3)
//
// 곡에는 이미 구간 이름이 붙어 있다 — 인트로 · 벌스 · 빌드업 · 드롭 · 브레이크 · 아웃트로.
// 그런데 그 이름이 **아무 일도 안 했다.** 빌드업이 벌스와 똑같이 들리면 그건 빌드업이
// 아니라 그냥 이름표다. 계획 6-3 이 요구하는 것이 이것이다.
//
// ── 어디까지 하는가 ──
// 계획은 필터 열림 · 리버브 변화 · 라이저도 적었다. 그건 **구간 안에서 값이 움직이는
// 자동화**가 필요한데, 지금 엔진에는 그 길이 없다(버스 값은 재생 시작할 때 한 번 보낸다).
// 없는 길을 내려면 실시간 오디오 경로를 건드려야 하고, 그건 §15 가 막은 자리다.
//
// 그래서 **음 목록만으로 할 수 있는 것**에 집중한다 — 세기 곡선과 밀도.
// 이 둘만으로도 「점점 차오른다 / 확 비었다 / 꽉 찼다」는 다 들린다.
// 필·느낌·변형과 같은 자리에서 끝나므로 재생과 내보내기가 저절로 같다.
//
// ── 안전한 기본값 ──
// 계획의 단서: "자동화가 음악을 과하게 망가뜨리지 않도록." 그래서
// **골격(킥·스네어)은 안 지운다.** 딱 하나 예외가 빌드업의 마지막 마디인데,
// 그건 실수가 아니라 **드롭을 세게 만들려고 일부러 비우는 자리**다.
import 'patterns.dart';

/// 구간이 곡에서 하는 일. 이름에서 알아낸다.
enum SectionRole {
  /// 얇게 시작
  intro,

  /// 점점 차오른다 → 다음 구간을 세게 만든다
  build,

  /// 꽉 찬다
  drop,

  /// 확 빈다
  breakDown,

  /// 잦아든다
  outro,

  /// 아무것도 안 한다 — **모르는 이름은 여기로 온다**
  normal,
}

/// 구간 이름 → 성격.
///
/// 부분 일치로 본다 — 「브레이크다운」·「브레이크2」처럼 뒤에 뭐가 붙는다.
/// 엠비언트는 이름이 시적이라(여명·정적·해질녘) 따로 적어 뒀다.
SectionRole roleOf(String name) {
  final n = name.trim();
  bool has(String s) => n.contains(s);
  if (has('빌드') || has('프리')) return SectionRole.build;
  // 「브레이크다운」이 「브레이크」를 포함하므로 이 둘은 같이 본다
  if (has('브레이크') || n == '정적') return SectionRole.breakDown;
  if (has('드롭') || has('코러스') || has('훅')) return SectionRole.drop;
  if (has('인트로') || n == '여명') return SectionRole.intro;
  if (has('아웃트로') || n == '해질녘') return SectionRole.outro;
  return SectionRole.normal;
}

const Set<String> _twigs = {'hat', 'shaker', 'cowbell', 'ride'};
const Set<String> _bones = {'kick', 'snare', 'clap'};

/// 한 구간을 그 성격대로 손본다. [role] 이 `normal` 이면 **한 글자도 안 바꾼다**.
///
/// [at] 은 이 구간이 시작하는 시각, [totalSec] 은 길이. 세기 곡선은 그 안의
/// 진행도(0~1)로 정해진다 — 구간이 길든 짧든 「점점」이 구간 전체에 걸쳐 일어난다.
void applyArrange(
  List<List<dynamic>> notes,
  List<List<dynamic>> drums,
  SectionRole role,
  double stepSec, {
  double at = 0,
  required double totalSec,
  int spb = kStepsPerBar,
}) {
  if (role == SectionRole.normal || totalSec <= 0) return;
  double prog(double t) => ((t - at) / totalSec).clamp(0.0, 1.0);
  int bump(int v, int by) => (v + by).clamp(1, 3);

  switch (role) {
    case SectionRole.build:
      // ① 세기가 **구간 전체에 걸쳐** 오른다: 앞은 한 단 아래, 뒤는 한 단 위
      for (final d in drums) {
        final p = prog((d[4] as num).toDouble());
        d[2] = bump(d[2] as int, p < 0.35 ? -1 : (p > 0.75 ? 1 : 0));
      }
      for (final n in notes) {
        final p = prog((n[6] as num).toDouble());
        n[3] = bump(n[3] as int, p < 0.35 ? -1 : (p > 0.75 ? 1 : 0));
      }
      // ② 뒤로 갈수록 잔가지가 촘촘해진다 — 차오르는 느낌의 대부분이 여기서 나온다
      final add = <List<dynamic>>[];
      final busy = {
        for (final d in drums)
          '${d[1]}:${((d[4] as num).toDouble() / stepSec).round()}',
      };
      for (final d in drums) {
        if (!_twigs.contains(d[1] as String)) continue;
        final t = (d[4] as num).toDouble();
        if (prog(t) < 0.5) continue;
        final step = (t / stepSec).round();
        if (step.isOdd) continue;
        if (busy.contains('${d[1]}:${step + 1}')) continue;
        add.add([d[0], d[1], bump(d[2] as int, -1), d[3], t + stepSec]);
      }
      drums.addAll(add);
      // ③ **마지막 마디는 킥을 비운다.** 발이 멎으면 다음 구간의 첫 박이 훨씬 세다.
      //    빌드업에서만 골격을 지운다 — 실수가 아니라 이 구간의 목적이다.
      //    **짧은 구간에서는 안 한다** — 2마디짜리 빌드업이면 절반이 발 없이 간다.
      final bars = (totalSec / (stepSec * spb)).round();
      if (bars >= 4) {
        final lastBar = at + totalSec - stepSec * spb;
        drums.removeWhere(
          (d) => d[1] == 'kick' && (d[4] as num).toDouble() >= lastBar - 1e-9,
        );
      }

    case SectionRole.drop:
      // 꽉 찬다 — 다만 **골격과 음만** 올린다.
      //
      // 처음엔 전부 한 단 올렸더니 평균 세기가 2.95/3 이 됐다. 세기 단이 셋뿐이라
      // 그러면 거의 모두 3 이고, 하이햇의 강약 무늬가 통째로 사라진다.
      // 꽉 찬 게 아니라 **납작해지는 것**이다.
      //
      // 그리고 재 보니 드럼 쪽은 사실상 **아무 일도 안 한다** — 라이브러리 패턴의
      // 킥·스네어는 이미 세기 3(최대)이라 올릴 데가 없다. 그건 고칠 결함이 아니라
      // 이 시스템의 사실이다: **제일 큰 데를 더 키울 수는 없고, 나머지를 낮춰야 한다.**
      // 그래서 드롭의 대비는 여기가 아니라 앞의 빌드업(발이 멎는다)과
      // 인트로·브레이크·아웃트로를 낮추는 데서 나온다. 여기서 실제로 달라지는 것은
      // **멜로디·베이스가 한 단 세지는 것**(계획 6-3 의 "Main melody")이다.
      for (final d in drums) {
        if (!_bones.contains(d[1] as String)) continue;
        d[2] = bump(d[2] as int, 1);
      }
      for (final n in notes) {
        n[3] = bump(n[3] as int, 1);
      }

    case SectionRole.breakDown:
      // 확 빈다 — 잔가지를 걷고 세기를 내린다. **골격은 남긴다**(곡이 끊기면 안 된다).
      drums.removeWhere((d) => _twigs.contains(d[1] as String));
      for (final d in drums) {
        if (!_bones.contains(d[1] as String)) continue;
        d[2] = bump(d[2] as int, -1);
      }
      for (final n in notes) {
        n[3] = bump(n[3] as int, -1);
      }

    case SectionRole.intro:
      // 얇게 시작 — 잔가지 절반을 걷고, **잔가지와 음만** 한 단 아래.
      // 킥·스네어까지 내리면 인트로가 통째로 뭉개진다(들어오는 자리는 들려야 한다).
      var i = 0;
      drums.removeWhere((d) => _twigs.contains(d[1] as String) && (i++).isEven);
      for (final d in drums) {
        if (_bones.contains(d[1] as String)) continue;
        d[2] = bump(d[2] as int, -1);
      }
      for (final n in notes) {
        n[3] = bump(n[3] as int, -1);
      }

    case SectionRole.outro:
      // 잦아든다 — 뒤로 갈수록 여려진다
      for (final d in drums) {
        final p = prog((d[4] as num).toDouble());
        d[2] = bump(d[2] as int, p > 0.6 ? -2 : (p > 0.3 ? -1 : 0));
      }
      for (final n in notes) {
        final p = prog((n[6] as num).toDouble());
        n[3] = bump(n[3] as int, p > 0.6 ? -2 : (p > 0.3 ? -1 : 0));
      }

    case SectionRole.normal:
      break;
  }

  drums.sort(
    (a, b) => (a[4] as num).toDouble().compareTo((b[4] as num).toDouble()),
  );
}
