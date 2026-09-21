// 쇼 화면이 쓰는 계산 (5단계 16/N).
//
// 쇼는 "소리에 맞춰 움직이는 그림"이다. 보통은 출력 소리를 분석해서 만드는데,
// 이 앱은 **악보를 갖고 있다** — 언제 무슨 악기가 울리는지 이미 안다.
// 그래서 분석하지 않는다:
//   · 정확하다(분석은 늘 몇십 ms 늦고 큰 소리에 작은 소리가 묻힌다)
//   · 싸다(프레임마다 하는 일이 이진 탐색 한 번)
//   · **악기별로 나눌 수 있다** — 베이스가 울릴 때 베이스만 튄다
//
// 화면은 여기서 나온 숫자(0~1)를 크기·밝기로 바꿔 쓰기만 한다.

import 'dart:math' as math;
import 'arrange.dart';

import 'project.dart';
import 'sequencer.dart';

/// 곡 한 곡을 "언제 무엇이 울리는지"로 정리한 것.
class ShowScore {
  /// 구간 (시작 초, 길이 초) 와 이름.
  final List<(double, double)> spans;
  final List<String> sectionNames;

  /// 트랙 id → 그 트랙이 울리는 시각들(초, 오름차순).
  final Map<String, List<double>> trackTimes;

  /// [trackTimes] 와 **자리를 맞춘** 목록. i 번째 값은 "0~i 번째 음 중 가장 늦게
  /// 끝나는 시각"이다(그냥 그 음의 끝이 아니다).
  ///
  /// 이렇게 두는 이유: 패드가 4초 울리는 동안 짧은 음이 겹쳐 시작하면, 이진 탐색은
  /// **짧은 음**을 집는다. 그 음의 끝만 보면 아직 울리는 패드를 놓친다.
  /// 앞쪽 최댓값을 들고 있으면 그럴 일이 없다.
  final Map<String, List<double>> trackEnds;

  /// [trackTimes] 와 자리를 맞춘 **음 높이**(0~1). 그 트랙 안에서 제일 낮은 음이 0,
  /// 제일 높은 음이 1 이다. 쇼 화면의 기타리스트가 **넥 위 손 자리**를 여기서 정한다 —
  /// 높은 음일수록 헤드 쪽으로 올라간다.
  final Map<String, List<double>> trackPitch;

  /// 드럼 레인 → 타격 시각들.
  final Map<String, List<double>> drumTimes;

  final double total;

  const ShowScore({
    required this.spans,
    required this.sectionNames,
    required this.trackTimes,
    required this.trackEnds,
    required this.trackPitch,
    required this.drumTimes,
    required this.total,
  });

  /// 곡 전체를 한 번만 만들어서 시각표로 접는다(음 하나하나는 안 들고 있는다 —
  /// 3분짜리면 수천 개다. 화면에 필요한 건 **시각**뿐이다).
  factory ShowScore.from(Project p, Transport tr) {
    final b = SceneSequencer.buildSong(p, tr);
    final buses = b.busNames;
    final tt = <String, List<double>>{};
    final te = <String, List<double>>{};
    final tp = <String, List<double>>{};
    final dt = <String, List<double>>{};

    // 음은 (시작, 끝) 쌍으로 모은다 — **길게 눌린 음은 그 동안 계속 빛나야** 한다.
    // 시작만 들고 있으면 패드가 4초 울려도 화면은 0.3초 만에 꺼진다.
    final pairs = <String, List<(double, double, double)>>{};
    for (final n in b.notes) {
      final part = n[7] as int;
      if (part < 0 || part >= buses.length) continue;
      final st = n[6] as double;
      final dur = (n[2] as num).toDouble();
      final freq = (n[1] as num).toDouble();
      (pairs[buses[part]] ??= []).add((st, st + dur, freq));
    }
    for (final e in pairs.entries) {
      e.value.sort((a, b) => a.$1.compareTo(b.$1));
      tt[e.key] = [for (final v in e.value) v.$1];
      // 앞쪽 최댓값을 누적한다(위 [trackEnds] 설명 참고)
      var run = double.negativeInfinity;
      te[e.key] = [for (final v in e.value) run = math.max(run, v.$2)];
      // 음 높이는 **그 트랙 안에서** 0~1 로 편다. 절대 음높이로 하면 베이스는
      // 늘 아래쪽, 리드는 늘 위쪽에 손이 붙어 있어 안 움직이는 것으로 보인다.
      // 옥타브는 곱셈으로 올라가므로 로그로 잰다(사람 귀와 같은 자).
      var lo = double.infinity, hi = double.negativeInfinity;
      for (final v in e.value) {
        if (v.$3 <= 0) continue;
        lo = math.min(lo, v.$3);
        hi = math.max(hi, v.$3);
      }
      final span = (hi > lo) ? math.log(hi / lo) : 0.0;
      tp[e.key] = [
        for (final v in e.value)
          (v.$3 <= 0 || span <= 0)
              ? 0.5
              : (math.log(v.$3 / lo) / span).clamp(0.0, 1.0).toDouble(),
      ];
    }
    for (final d in b.drums) {
      (dt[d[1] as String] ??= []).add(d[4] as double);
    }
    for (final v in dt.values) {
      v.sort();
    }
    // **백비트는 장르마다 다른 악기가 친다** — 스네어·클랩·림.
    // 하우스·재즈·가스펠은 스네어를 아예 안 치고 클랩만 친다. 화면에서는 셋 다
    // 같은 자리(드러머 왼손·「스네어」 램프)이므로 한 목록으로 묶어 둔다.
    // 안 묶으면 그 장르에서는 램프도 손도 곡 내내 죽어 있다.
    // (`dt.values` 순회가 끝난 **뒤**에 넣어야 한다 — 도는 중에 키를 더하면 터진다)
    dt['backbeat'] = [...?dt['snare'], ...?dt['clap'], ...?dt['rim']]..sort();

    final spans = SceneSequencer.songSpans(p, tr);
    return ShowScore(
      spans: spans,
      sectionNames: [
        for (final s in p.song.sections)
          (s.scene >= 0 && s.scene < p.scenes.length)
              ? p.scenes[s.scene].name
              : '?',
      ],
      trackTimes: tt,
      trackEnds: te,
      trackPitch: tp,
      drumTimes: dt,
      total: spans.isEmpty ? 0 : spans.last.$1 + spans.last.$2,
    );
  }

  /// [t] 초는 몇 번째 구간인가. 없으면 -1.
  int sectionAt(double t) {
    for (var i = 0; i < spans.length; i++) {
      if (t >= spans[i].$1 && t < spans[i].$1 + spans[i].$2) return i;
    }
    return spans.isEmpty ? -1 : spans.length - 1;
  }

  /// 구간이 **막 바뀐 정도**(1 = 방금 넘어감, 0 = 한참 됨). [decay] 초에 걸쳐 잦아든다.
  ///
  /// 인트로 → 벌스 → 코러스가 귀로만 넘어가면 화면은 계속 같아 보인다.
  /// 쇼 화면은 이 값으로 무대를 한 번 환하게 만든다.
  /// 지금 무대가 얼마나 달아올랐는가 — 0(비었다) ~ 1(터진다). (Phase 6 · 계획 8)
  ///
  /// **구간 이름이 정한다.** 계획 8 이 든 예가 그대로다:
  ///   Drop → 밴드 활성화·무대 에너지 증가 / Break → 줄어들고 조명이 바뀜 / Build → 움직임 증가
  ///
  /// 음량으로 재지 않는 이유: 소리는 리미터가 눌러 놔서 구간끼리 크기 차이가 작다
  /// (Phase 4 에서 잰 값 — 드롭 페이더를 15% 내려도 0.2dB 밖에 안 움직였다).
  /// 화면은 **곡의 짜임**을 보여 줘야 하고, 그건 구간 이름이 이미 알고 있다.
  ///
  /// 빌드업·아웃트로는 구간 **안에서** 오르내린다 — 그게 「차오른다 / 잦아든다」다.
  double energyAt(double t) {
    final i = sectionAt(t);
    if (i < 0 || i >= spans.length || i >= sectionNames.length) return 0.55;
    final (st, du) = spans[i];
    final p = du <= 0 ? 0.0 : ((t - st) / du).clamp(0.0, 1.0);
    switch (roleOf(sectionNames[i])) {
      case SectionRole.drop:
        return 1.0;
      case SectionRole.build:
        return 0.35 + 0.60 * p;
      case SectionRole.breakDown:
        return 0.15;
      case SectionRole.intro:
        return 0.30;
      case SectionRole.outro:
        return 0.45 * (1 - p);
      case SectionRole.normal:
        return 0.55;
    }
  }

  double sectionPulse(double t, double decay) {
    final i = sectionAt(t);
    if (i < 0 || i >= spans.length) return 0;
    final dt = t - spans[i].$1;
    if (dt < 0 || dt >= decay) return 0;
    return 1 - dt / decay;
  }

  /// 그 시각에 얼마나 '방금 울렸나'(1 = 지금 막, 0 = 조용). [decay] 초에 걸쳐 잦아든다.
  ///
  /// 목록이 시간순이라 **이진 탐색**으로 바로 앞 타격을 찾는다 — 프레임마다 도는
  /// 코드라 음이 수천 개여도 부담이 없어야 한다.
  static double pulse(List<double>? times, double t, {double decay = 0.3}) {
    if (times == null || times.isEmpty || t < times.first) return 0;
    final at = _lastAtOrBefore(times, t);
    if (at < 0) return 0;
    final dt = t - times[at];
    if (dt >= decay) return 0;
    // 처음이 가파르게 떨어지는 게 타격처럼 보인다(직선이면 미는 느낌이 난다)
    return math.pow(1 - dt / decay, 2.2).toDouble();
  }

  /// [times] 에서 [t] 보다 앞선(같은 것 포함) 마지막 자리. 없으면 -1.
  /// 시간순 목록이라 **이진 탐색** — 프레임마다 도는 코드라 음이 수천 개여도
  /// 부담이 없어야 한다.
  static int _lastAtOrBefore(List<double> times, double t) {
    var lo = 0, hi = times.length - 1, at = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (times[mid] <= t) {
        at = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return at;
  }

  /// 음이 **아직 눌려 있는 동안** 유지하는 밝기. 때린 순간(1.0)보다는 낮지만
  /// 확실히 켜져 있다 — 패드처럼 길게 끄는 악기가 꺼져 보이면 안 된다.
  static const double kSustain = 0.45;

  /// 음이 끝난 뒤 잦아드는 시간(초). 뚝 끊으면 깜빡이는 것처럼 보인다.
  static const double kRelease = 0.22;

  /// 트랙 하나의 지금 밝기(0~1).
  ///
  /// 세 토막이다:
  ///  · **때림** — 시작 직후 [decay] 동안 1 에서 가파르게 떨어진다
  ///  · **서스테인** — 음이 아직 안 끝났으면 [kSustain] 아래로 안 내려간다
  ///  · **릴리스** — 끝나고 [kRelease] 동안 남은 빛이 스러진다
  double trackPulse(String trackId, double t, {double decay = 0.3}) {
    final times = trackTimes[trackId];
    if (times == null || times.isEmpty || t < times.first) return 0;
    final at = _lastAtOrBefore(times, t);
    if (at < 0) return 0;

    final dt = t - times[at];
    final hit = dt >= decay ? 0.0 : math.pow(1 - dt / decay, 2.2).toDouble();

    final ends = trackEnds[trackId];
    if (ends == null || at >= ends.length) return hit;
    final end = ends[at];

    if (t < end) return math.max(hit, kSustain); // 아직 울리는 중
    final rel = t - end;
    if (rel >= kRelease) return hit;
    return math.max(hit, kSustain * (1 - rel / kRelease));
  }

  /// 그 시각에 울리고 있는 음의 **높이**(0~1). 음이 바뀔 때만 값이 바뀐다 —
  /// 기타리스트의 손이 계속 흔들리지 않고 **음마다 자리를 옮기게** 하려는 것이다.
  /// 아직 아무 음도 안 울렸으면 0.5(가운데).
  double pitchAt(String trackId, double t) {
    final times = trackTimes[trackId];
    final pitch = trackPitch[trackId];
    if (times == null || pitch == null || times.isEmpty || t < times.first) {
      return 0.5;
    }
    final at = _lastAtOrBefore(times, t);
    if (at < 0 || at >= pitch.length) return 0.5;
    return pitch[at];
  }

  double drumPulse(String lane, double t, {double decay = 0.22}) =>
      pulse(drumTimes[lane], t, decay: decay);

  /// **다음 타격까지 얼마나 왔는가** — 0 = 방금 쳤다, 1 = 지금 친다. (5단계 53/N)
  ///
  /// 세기(`drumPulse`)만으로 팔을 움직이면 **대부분의 시간을 든 채로 있게 된다.**
  /// 세기는 0.22초면 0으로 떨어지는데 8분음표 간격은 88BPM 에서 0.34초다 —
  /// 그 사이 내내 팔이 허공에 멈춰 있다(사용자 지적: "드럼을 안 치고 팔을 어정쩡하게
  /// 들고 있어"). 실제 스틱은 치고 튀어 올랐다가 **다음 박에 맞춰 내려온다.**
  ///
  /// 다음 타격이 [maxGap] 초보다 멀면 −1 — 그때는 쉬는 자세다.
  double strokePhase(String lane, double t, {double maxGap = 1.4}) {
    final times = drumTimes[lane];
    if (times == null || times.length < 2) return -1;
    final at = _lastAtOrBefore(times, t);
    // 첫 타격 전 — 준비 동작으로 들어간다
    if (at < 0) {
      final d = times.first - t;
      return d > maxGap ? -1 : 1 - d / maxGap;
    }
    if (at + 1 >= times.length) return -1;
    final a = times[at], b = times[at + 1];
    final gap = b - a;
    if (gap <= 0 || gap > maxGap) return -1;
    return ((t - a) / gap).clamp(0.0, 1.0);
  }
}
