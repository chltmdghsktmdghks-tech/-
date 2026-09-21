// Phase 1 — **엔진 안전망.** (Music Doodle Engine 개선 계획 3장)
//   flutter test test/engine_guard_test.dart
//
// 이 파일이 지키는 것은 '소리가 좋은가'가 아니라 **'엔진이 깨지지 않는가'** 다.
// 음색을 고치는 작업(48~53/N)은 계속 이어질 텐데, 그때마다 아래가 조용히
// 망가졌는지 확인할 방법이 없으면 손댈 때마다 도박이 된다.
//
//  1. 결정성   — 같은 입력이면 **항상 같은 소리**가 나오는가 (회귀 시험의 전제)
//  2. 회귀     — 기준 곡의 지문(피크·RMS·DC·대역별 에너지·체크섬)이 그대로인가
//  3. 스케줄러 — 이벤트가 빠지거나 겹치거나 잘못된 시각에 터지지 않는가
//  4. 보이스   — 폴리포니를 넘겨도 죽지 않고, 멈춘 뒤 남는 음이 없는가
//  5. 재생=내보내기 — 들은 것과 파일이 같은가
//  6. 위생     — NaN · Infinity · DC 치우침 · 하드클립이 없는가
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/drums.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/engine.dart';
import 'package:music_doodle_engine/export.dart';
import 'package:music_doodle_engine/instruments.dart' show ALL_VOICES;
import 'package:music_doodle_engine/synth.dart';

// ───────────────────────── 도구 ─────────────────────────

/// 16비트 인터리브 → −1..1 두 채널 평균
List<double> _mono(List<int> pcm) {
  final out = List<double>.filled(pcm.length ~/ 2, 0);
  for (var i = 0; i < out.length; i++) {
    out[i] = (pcm[i * 2] + pcm[i * 2 + 1]) / 2 / 32768.0;
  }
  return out;
}

/// 렌더 결과의 **지문**. 숫자 하나만 보면 어디가 틀어졌는지 모른다.
class _Print {
  final double peak, rms, dc;
  final int clip, bad;
  final List<double> bands; // 5개 대역 에너지 비율
  final int sum; // 샘플 체크섬 — 한 샘플이라도 달라지면 바뀐다
  const _Print(
    this.peak,
    this.rms,
    this.dc,
    this.clip,
    this.bad,
    this.bands,
    this.sum,
  );

  @override
  String toString() =>
      '피크 ${peak.toStringAsFixed(4)} · RMS ${rms.toStringAsFixed(4)} · '
      'DC ${dc.toStringAsFixed(5)} · 클립 $clip · 이상값 $bad · '
      '대역 [${bands.map((b) => (b * 100).toStringAsFixed(1)).join(', ')}]';
}

_Print _fingerprint(List<double> x) {
  var peak = 0.0, sq = 0.0, sum = 0.0;
  var clip = 0, bad = 0, chk = 0;
  for (var i = 0; i < x.length; i++) {
    final v = x[i];
    if (v.isNaN || v.isInfinite) {
      bad++;
      continue;
    }
    final a = v.abs();
    if (a > peak) peak = a;
    if (a >= 0.9999) clip++;
    sq += v * v;
    sum += v;
    // 체크섬 — 부동소수점을 그대로 더하면 순서에 따라 흔들린다. 정수로 굳혀서 센다.
    chk = (chk * 31 + (v * 32768).round()) & 0x7FFFFFFF;
  }
  final n = math.max(1, x.length);
  final edges = [120.0, 500.0, 2000.0, 6000.0];
  final bands = <double>[];
  var total = 0.0;
  final raw = <double>[];
  for (var b = 0; b <= edges.length; b++) {
    final hp = b == 0 ? null : (Biquad()..highpass(edges[b - 1], 0.707));
    final lp = b == edges.length ? null : (Biquad()..lowpass(edges[b], 0.707));
    var e = 0.0;
    for (final v in x) {
      if (v.isNaN || v.isInfinite) continue;
      var y = v;
      if (hp != null) y = hp.process(y);
      if (lp != null) y = lp.process(y);
      e += y * y;
    }
    raw.add(e);
    total += e;
  }
  for (final e in raw) {
    bands.add(total <= 0 ? 0 : e / total);
  }
  return _Print(peak, math.sqrt(sq / n), sum / n, clip, bad, bands, chk);
}

/// 기준 곡 — **짧고 빽빽하게.** 길게 만들면 시험이 느려서 아무도 안 돌린다.
/// 드럼 10종 + 음정 악기 여러 종을 한 번에 섞어 엔진 경로를 골고루 지나가게 한다.
Engine _refEngine() {
  final e = Engine()..trackMix.configure(['a', 'b', 'c']);
  const kit = 'acoustic';
  for (var bar = 0; bar < 2; bar++) {
    final t = bar * 2.0;
    for (var s = 0; s < 8; s++) {
      e.scheduleDrum(t + s * 0.25, kit, 'hat', s.isEven ? 2 : 1);
    }
    e.scheduleDrum(t + 0.0, kit, 'kick', 3);
    e.scheduleDrum(t + 1.0, kit, 'snare', 3);
    e.scheduleDrum(t + 1.5, kit, 'clap', 2); // 결정성 구멍이 있던 자리
    e.scheduleDrum(t + 1.75, kit, 'tom', 2);
    e.scheduleDrum(t + 0.5, kit, 'shake', 1);
    e.scheduleDrum(t + 0.75, kit, 'rim', 2);
    if (bar == 0) e.scheduleDrum(t, kit, 'crash', 3);
    e.scheduleDrum(t + 1.25, kit, 'ride', 2);
    e.scheduleDrum(t + 1.9, kit, 'cow', 1);
    // 베이스 · 코드(soft) · 멜로디
    e.schedule(t, 'fingerbass', 98.0, 0.9, 3, part: kPartBass);
    e.schedule(t + 1.0, 'fingerbass', 130.8, 0.9, 3, part: kPartBass);
    for (final f in [261.63, 311.13, 392.0]) {
      e.schedule(t + 0.1, 'epiano', f, 1.6, 2, soft: true, part: kPartChord);
    }
    e.schedule(t + 0.5, 'guitar', 523.25, 0.5, 3, part: kPartMelody);
    e.schedule(t + 1.25, 'sax', 466.16, 0.7, 2, part: kPartMelody);
  }
  return e;
}

List<double> _render(Engine e, double sec) {
  final total = (sec * kSampleRate).round();
  final out = <double>[];
  var done = 0;
  while (done < total) {
    final n = math.min(512, total - done);
    out.addAll(_mono(e.render(n)));
    done += n;
  }
  return out;
}

void main() {
  _holdTests();
  _humanTests();
  test('엔진 안전망', () {
    var fail = 0;
    void check(String name, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $name — $detail');
      if (!ok) fail++;
    }

    Human.setLevel(0); // 흔들림을 끄면 **완전히 결정적**이어야 한다

    // ══ 1. 결정성 ══
    // 같은 입력이 같은 소리를 내지 않으면 아래 회귀 시험은 전부 의미가 없다.
    final r1 = _render(_refEngine(), 4);
    final r2 = _render(_refEngine(), 4);
    var firstDiff = -1;
    for (var i = 0; i < math.min(r1.length, r2.length); i++) {
      if (r1[i] != r2[i]) {
        firstDiff = i;
        break;
      }
    }
    check(
      '1) 같은 입력 → 같은 소리',
      r1.length == r2.length && firstDiff < 0,
      firstDiff < 0
          ? '${r1.length}샘플 전부 일치'
          : '${(firstDiff / kSampleRate * 1000).toStringAsFixed(1)}ms 지점부터 다름',
    );

    // 타악기 10종 각각 — 어느 하나라도 난수를 조건 없이 쓰면 여기서 걸린다
    final wobbly = <String>[];
    for (final inst in DRUM_ORDER) {
      List<double> one() {
        final d = DrumVoice()..trigger(inst, DRUM_KITS['k909']!, 2);
        final o = <double>[];
        for (var i = 0; i < 9600 && d.active; i++) {
          d.next();
          o.add(d.outL);
        }
        return o;
      }

      final a = one(), b = one();
      if (a.length != b.length) {
        wobbly.add(inst);
        continue;
      }
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) {
          wobbly.add(inst);
          break;
        }
      }
    }
    check(
      '1-b) 타악기 10종 결정적',
      wobbly.isEmpty,
      wobbly.isEmpty ? '${DRUM_ORDER.length}종 통과' : '흔들림: ${wobbly.join(', ')}',
    );

    // ══ 2. 회귀 — 기준 곡의 지문 ══
    final fp = _fingerprint(r1);
    // ignore: avoid_print
    print('     기준 곡 지문 → $fp · 체크섬 ${fp.sum}');

    // ── 골든 값 ── 2026-08-23 기준 (Phase 3 에서 한 번 갱신).
    //
    // 갱신 이력:
    //  · 2026-08-22 첫 기준 (피크 0.9635 · RMS 0.1745)
    //  · 2026-08-23 Phase 3 — 두 가지를 일부러 바꿔서 옮겼다:
    //      ① 가산합성 악기의 크기 보정 (피아노가 23.5dB 작던 것)
    //      ② 드럼 좌우 자리 (전부 가운데였던 것)
    //    피크가 0.9635 → 0.9474 로 내려갔다 — 좌우로 벌리면 한쪽에 몰리던 것이
    //    나뉘어서다. RMS·대역은 거의 그대로(총 힘은 안 변한다).
    //  · 2026-08-23 Phase 3(2) — 킥·스네어를 고쳤다(사용자: 「너무 구려」):
    //      ① 킥이 75~142ms 밖에 안 울렸다 → 176~405ms (「톡」이 「둥」이 됨)
    //      ② 스네어가 34~60ms → 95~130ms, 타점 5.9~7.7ms → 1.4ms
    //    RMS 가 0.1736 → 0.1816 로 올랐다 — 더 오래 울리니 당연하다.
    //    2번 대역(저-중역)이 50.2% → 48.6%: 스네어 몸통이 바로 감쇠하면서
    //    상대적으로 고역 몫이 늘었다.
    //  · 2026-08-30 킥을 조였다 (사용자: 「킥이 전반적으로 너무 뚱뚱거려」):
    //      ① 울림 길이 176~541ms → 138~379ms (다섯 키트 전부 22~37% 짧게)
    //      ② 음정이 바닥에 앉는 시간 0.26 → 0.19초 — 「둥—」 하고 끌리던 꼬리
    //      ③ 비터 딱 소리 0.30~0.85 → 0.40~0.88 (길이를 줄인 만큼 윤곽을 세운다)
    //    RMS 0.1816 → 0.1896: 짧아졌는데 오히려 올랐다. 딱 소리를 키운 몫과,
    //    음정이 빨리 앉아 **효율 좋은 저역에 머무는 시간**이 늘어난 몫이다.
    //    1번 대역 45.4% → 47.8%, 2번 46.8%: 같은 이유다(스윕 구간이 짧아졌다).
    //    ⚠️ 2026-08-23 에 「75~142ms 는 너무 짧다」고 늘렸던 그 값이다.
    //    이번엔 반대로 줄였다 — **되돌린 게 아니라** 그 사이에서 자리를 찾은 것이다
    //    (139~379ms). 다음에 또 만질 때 이 두 줄을 같이 볼 것.
    //
    // **이 시험이 깨졌다고 무조건 버그는 아니다.** 음색을 일부러 고치면 당연히 바뀐다.
    // 이 시험이 하는 일은 "바뀌었다는 사실을 놓치지 않게" 하는 것이다.
    // 고친 게 의도한 것이면 아래 값을 새 값으로 갱신하고, **왜 바꿨는지 HANDOFF 에 적는다.**
    // 의도한 적 없는데 바뀌었다면 그게 회귀다 — 바로 앞 커밋과 견줘 볼 것.
    const gPeak = 0.9480, gRms = 0.1896;
    const gBands = [0.478, 0.468, 0.034, 0.010, 0.010];
    var drift = <String>[];
    if ((fp.peak - gPeak).abs() > 0.01) {
      drift.add('피크 $gPeak → ${fp.peak.toStringAsFixed(4)}');
    }
    if ((fp.rms - gRms).abs() > gRms * 0.02) {
      drift.add('RMS $gRms → ${fp.rms.toStringAsFixed(4)}');
    }
    for (var i = 0; i < gBands.length; i++) {
      if ((fp.bands[i] - gBands[i]).abs() > 0.015) {
        drift.add(
          '${i + 1}번 대역 ${(gBands[i] * 100).toStringAsFixed(1)}% → '
          '${(fp.bands[i] * 100).toStringAsFixed(1)}%',
        );
      }
    }
    check(
      '2-f) 기준 곡이 그대로다',
      drift.isEmpty,
      drift.isEmpty ? '피크·RMS·대역 5개 모두 허용 오차 안' : drift.join(' · '),
    );
    check('2) 위생 — NaN·무한대 없음', fp.bad == 0, '이상값 ${fp.bad}개');
    check('2-b) 하드클립 없음', fp.clip == 0, '${fp.clip}개 / ${r1.length}샘플');
    // DC 치우침 — 스피커를 밀어 놓는 성분. 0.002 넘으면 어딘가 비대칭이다.
    check('2-c) DC 치우침 없음', fp.dc.abs() < 0.002, fp.dc.toStringAsFixed(6));
    check(
      '2-d) 소리가 들어 있다',
      fp.rms > 0.02 && fp.peak > 0.1,
      'RMS ${fp.rms.toStringAsFixed(4)} · 피크 ${fp.peak.toStringAsFixed(4)}',
    );
    // 대역 균형 — 저역만 남거나 고역만 남으면 어딘가 필터가 뒤집힌 것이다
    check(
      '2-e) 대역이 고르게 있다',
      fp.bands.every((b) => b > 0.005),
      '[${fp.bands.map((b) => (b * 100).toStringAsFixed(1)).join(', ')}]%',
    );

    // ══ 3. 스케줄러 ══
    // 3-a) 예약한 개수만큼 정확히 터지는가
    {
      final e = Engine()..trackMix.configure(['a']);
      for (var i = 0; i < 200; i++) {
        e.schedule(i * 0.005, 'chip', 440.0, 0.05, 2, part: kPartBass);
      }
      check('3) 예약이 다 남아 있다', e.pendingCount == 200, '${e.pendingCount}/200');
      _render(e, 0.4); // 0.005 × 200 = 1.0초 중 앞 0.4초
      final leftover = e.pendingCount;
      _render(e, 0.8);
      check(
        '3-b) 전부 소진',
        e.pendingCount == 0,
        '0.4초 뒤 $leftover개 남음 → 끝나고 ${e.pendingCount}개',
      );
    }
    // 3-b) **같은 시각에 몰아넣어도** 순서가 뒤집히거나 빠지지 않는가
    {
      final e = Engine()..trackMix.configure(['a']);
      for (var i = 0; i < 64; i++) {
        e.schedule(0.5, 'chip', 220.0 + i, 0.1, 1, part: kPartBass);
      }
      _render(e, 0.6);
      check(
        '3-c) 동시 64음',
        e.pendingCount == 0 && e.maxActive > 0,
        '최대 동시 ${e.maxActive}음 · 남은 예약 ${e.pendingCount}',
      );
    }
    // 3-c) 정지하면 **남는 음이 없어야** 한다
    {
      final e = Engine()..trackMix.configure(['a']);
      for (var i = 0; i < 8; i++) {
        e.schedule(i * 0.01, 'pad', 220.0, 4.0, 3, part: kPartBass); // 4초짜리 긴 음
      }
      _render(e, 0.3);
      final before = e.activeCount;
      e.allOff();
      // 바로 뒤는 **리버브 꼬리와 룩어헤드 지연선**이 남아 있는 게 정상이다
      // (여기를 0 으로 못 박으면 리버브를 잘라 내라는 시험이 된다).
      // 확인할 것은 두 가지: 목소리가 다 반납됐는가, 그리고 **꼬리가 사그라드는가**.
      final justAfter = _fingerprint(_render(e, 0.3));
      final later = _fingerprint(_render(e, 2.0));
      check(
        '3-d) 정지하면 목소리가 다 반납된다',
        e.activeCount == 0 && e.pendingCount == 0,
        '멈추기 전 $before음 → 뒤 ${e.activeCount}음 · 예약 ${e.pendingCount}',
      );
      check(
        '3-d2) 꼬리가 사그라든다',
        later.peak < justAfter.peak * 0.05,
        '직후 ${justAfter.peak.toStringAsFixed(4)} → 2초 뒤 '
            '${later.peak.toStringAsExponential(1)}',
      );
    }
    // 3-d) 예약을 지운 뒤 새로 예약해도 옛 것이 안 나온다(씬 교체가 이 경로다)
    {
      final e = Engine()..trackMix.configure(['a']);
      for (var i = 0; i < 32; i++) {
        e.schedule(0.5 + i * 0.01, 'chip', 880.0, 0.1, 3, part: kPartBass);
      }
      e.clearSchedule();
      check('3-e) 예약 비우기', e.pendingCount == 0, '${e.pendingCount}개');
      final quiet = _fingerprint(_render(e, 1.0));
      check(
        '3-f) 지운 예약은 안 울린다',
        quiet.peak < 1e-6,
        '피크 ${quiet.peak.toStringAsExponential(1)}',
      );
    }

    // ══ 4. 보이스 ══
    // 폴리포니를 훌쩍 넘겨도 죽지 않고, 굶었다는 사실이 **세어져** 있어야 한다
    {
      final e = Engine()..trackMix.configure(['a']);
      for (var i = 0; i < 400; i++) {
        e.schedule(0.02, 'pad', 110.0 + i * 3, 2.0, 3, part: kPartBass);
      }
      final fpx = _fingerprint(_render(e, 0.5));
      check(
        '4) 폴리포니 초과에도 안 깨진다',
        fpx.bad == 0 && e.maxActive <= kPolyphony,
        '최대 ${e.maxActive}/$kPolyphony · 굶음 ${e.starved}회 · 이상값 ${fpx.bad}',
      );
    }
    // 드럼 풀도 같다
    {
      final e = Engine()..trackMix.configure(['a']);
      for (var i = 0; i < 200; i++) {
        e.scheduleDrum(0.02 + i * 0.0005, 'k909', 'hat', 2);
      }
      final fpx = _fingerprint(_render(e, 0.5));
      check(
        '4-b) 드럼 풀 초과에도 안 깨진다',
        fpx.bad == 0 && e.maxActiveDrums <= kDrumPolyphony,
        '최대 ${e.maxActiveDrums}/$kDrumPolyphony · 굶음 ${e.drumStarved}회',
      );
    }
    // 4-c) **목소리를 못 얻어도 덕은 걸려야 한다.**
    //
    // "킥이 났다는 사실은 변함이 없다"는 주석이 실제로 지켜지는지 — 드럼 풀을
    // 통째로 비우고(24개, render 를 한 번도 안 돌려 하나도 안 돌아온다) 그 위에
    // 킥을 하나 더 친다. 목소리는 못 받아 굶음으로 세이지만, 사이드체인은
    // 걸려야 한다.
    {
      final e = Engine()..trackMix.configure(['a']);
      e.duckAmount = 0.8;
      check('4-c) 처음엔 덕이 안 걸려 있다', e.duckLevel == 1.0, '${e.duckLevel}');
      for (var i = 0; i < kDrumPolyphony; i++) {
        e.drumOn('acoustic', 'tom', 3);
      }
      check(
        '4-c) 24개로 풀을 다 썼다',
        e.maxActiveDrums == kDrumPolyphony,
        '${e.maxActiveDrums}/$kDrumPolyphony',
      );
      final beforeStarved = e.drumStarved;
      e.drumOn('acoustic', 'kick', 3); // 이제 목소리가 없다
      check(
        '4-c) 이 킥은 목소리를 못 받는다(굶음으로 센다)',
        e.drumStarved == beforeStarved + 1,
        '굶음 ${e.drumStarved}',
      );
      check(
        '4-c) 그래도 덕은 걸린다',
        (e.duckLevel - (1 - e.duckAmount)).abs() < 1e-9,
        '덕 ${e.duckLevel} (바라는 값 ${1 - e.duckAmount})',
      );
    }
    // 4-d) **오른쪽만 넘쳐도 하드클립을 센다.**
    //
    // 리미터가 왼쪽·오른쪽을 각자 ±0.999 로 자르는데, 셈은(`clipped`) 예전엔
    // 왼쪽 것만 셌다. 드럼 버스 팬을 오른쪽 끝(1.0)으로 밀면 `ol = l*(1-pan)` 이
    // **정확히 0** 이 된다(1-1=0) — 왼쪽은 무슨 소리를 넣어도 절대 못 넘친다.
    // (룩어헤드 리미터가 웬만한 소리는 다 눌러 주므로, **뾰족한 타격**을 몰아
    // 쳐서 리미터가 반응하기 전 몇 샘플이 새게 만든다 — 볼륨을 실제로 탐색해
    // 확인했다: 5·20 은 안 넘고 100 부터 넘는다.)
    {
      final e = Engine()..trackMix.configure(['a']);
      e.trackMix.drum
        ..vol = 1000.0
        ..pan = 1.0;
      for (var i = 0; i < 8; i++) {
        e.drumOn('acoustic', 'clap', 3);
      }
      _render(e, 0.1);
      check(
        '4-d) 오른쪽만 넘쳐도 하드클립을 센다',
        e.clipped > 0,
        '하드클립 ${e.clipped}회 (왼쪽은 팬으로 항상 0)',
      );
    }
    // 33종 전부 한 번씩 — 어느 악기가 NaN 을 뱉는지 여기서 걸린다
    {
      final bad = <String>[];
      for (final v in ALL_VOICES) {
        final e = Engine()..trackMix.configure(['a']);
        e.schedule(0.01, v, 220.0, 0.4, 3, part: kPartBass);
        e.schedule(0.01, v, 1760.0, 0.4, 1, part: kPartBass); // 높은 음도
        final fpx = _fingerprint(_render(e, 0.8));
        if (fpx.bad > 0 || fpx.peak > 4.0 || fpx.peak < 1e-5) {
          bad.add('$v(피크 ${fpx.peak.toStringAsFixed(2)} 이상값 ${fpx.bad})');
        }
      }
      check(
        '4-c) 악기 33종 정상',
        bad.isEmpty,
        bad.isEmpty ? '${ALL_VOICES.length}종 통과' : bad.join(', '),
      );
    }

    // ══ 5. 재생 = 내보내기 ══
    // **들은 것과 파일이 달라지면** 그건 앱이 거짓말을 한 것이다.
    {
      final notes = <List<dynamic>>[];
      final drums = <List<dynamic>>[];
      for (var bar = 0; bar < 2; bar++) {
        final t = bar * 1.0;
        drums.add(['acoustic', 'kick', 3, 180.0, t]);
        drums.add(['acoustic', 'snare', 3, 180.0, t + 0.5]);
        drums.add(['acoustic', 'clap', 2, 180.0, t + 0.75]);
        notes.add(['fingerbass', 98.0, 0.8, 3, false, 0.0, t, kPartBass]);
        notes.add(['epiano', 261.63, 1.2, 2, true, 0.0, t + 0.1, kPartChord]);
        notes.add(['guitar', 523.25, 0.4, 3, false, 0.0, t + 0.5, kPartMelody]);
      }
      const buses = ['x', 'y', 'z'];
      final mix = {
        for (final b in buses) b: [0.9, 0.0, 0.1, 0.0, 0.0, 0.0],
        'drum': [0.8, 0.0, 0.05, 0.0, 0.0, 0.0],
      };
      // (가) 내보내기 경로
      final wav = renderWav(
        ExportJob(
          notes: notes,
          drums: drums,
          busNames: buses,
          buses: mix,
          masterVol: 1.0,
          seconds: 2.5,
          // **지금 걸린 흔들림을 그대로 실어야 한다** — 안 실으면 내보내기만
          // 흔들려서 두 길이 영영 안 맞는다(화면도 `Human.level` 을 실어 보낸다).
          human: Human.level,
        ),
      );
      final fromWav = <double>[];
      for (var i = 44; i + 3 < wav.length; i += 4) {
        int s16(int a) {
          final v = wav[a] | (wav[a + 1] << 8);
          return v >= 0x8000 ? v - 0x10000 : v;
        }

        fromWav.add((s16(i) + s16(i + 2)) / 2 / 32768.0);
      }
      // (나) 재생 경로 — 같은 재료를 엔진에 그대로 넣는다
      final e = Engine()..trackMix.configure(buses);
      e.userGain = 1.0;
      for (final b in [...buses, 'drum']) {
        final m = b == 'drum' ? e.trackMix.drum : e.trackMix.bus(b);
        final v = mix[b]!;
        m!
          ..vol = v[0]
          ..pan = v[1]
          ..rev = v[2]
          ..markDirty();
      }
      for (final d in drums) {
        e.scheduleDrum(
          d[4] as double,
          d[0] as String,
          d[1] as String,
          d[2] as int,
          tomFreq: d[3] as double,
        );
      }
      for (final n in notes) {
        e.schedule(
          n[6] as double,
          n[0] as String,
          n[1] as double,
          n[2] as double,
          n[3] as int,
          soft: n[4] as bool,
          glideF: n[5] as double,
          part: n[7] as int,
        );
      }
      final fromPlay = _render(e, 2.5);
      // 내보내기는 **일부러 2초를 더** 렌더한다(export.dart: seconds + 2.0) —
      // 마지막 음과 리버브가 잘리면 안 되니까. 그러니 길이는 다른 게 맞고,
      // **겹치는 구간이 샘플 단위로 같은가**를 본다.
      final len = math.min(fromWav.length, fromPlay.length);
      var worst = 0.0;
      var worstAt = 0;
      for (var i = 0; i < len; i++) {
        final d = (fromWav[i] - fromPlay[i]).abs();
        if (d > worst) {
          worst = d;
          worstAt = i;
        }
      }
      // 16비트로 굳히면서 생기는 반올림(1/32768 ≈ 3e-5)까지는 같은 것으로 본다
      check(
        '5) 재생 = 내보내기',
        worst <= 4e-5 && len >= (2.4 * kSampleRate).round(),
        '겹치는 ${(len / kSampleRate).toStringAsFixed(1)}초에서 최대 차이 '
            '${worst.toStringAsExponential(1)} '
            '(${(worstAt / kSampleRate * 1000).toStringAsFixed(0)}ms 지점) · '
            '내보내기가 ${((fromWav.length - fromPlay.length) / kSampleRate).toStringAsFixed(1)}초 더 김(여운)',
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '엔진 안전망 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}

/// **꾹 눌러 소리 유지** — 손을 뗄 때까지 나고, 떼면 사그라든다.
///
/// 여태 `noteOn` 은 길이를 미리 받아 그만큼만 울렸다(fire-and-forget). 라이브 패드가
/// 어떻게 만지든 미리 고른 길이로만 난 이유가 그것이다 — **라이브인데 표현이 없었다.**
void _holdTests() {
  test('꾹 눌러 소리 유지', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    Engine mk() => Engine()..trackMix.configure(['a']);

    /// [sec]초 렌더하고 그 구간의 봉우리를 돌려준다.
    double peak(Engine e, double sec) {
      final v = _render(e, sec);
      var p = 0.0;
      for (final x in v) {
        final a = x.abs();
        if (a > p) p = a;
      }
      return p;
    }

    // 1) **놓기 전에는 계속 난다.** `noteOn(dur: 0.3)` 은 1초 뒤 조용하지만
    //    잡아 둔 것은 그때도 나야 한다.
    {
      final fire = mk()..noteOn('piano', 440, 0.3, 3);
      _render(fire, 1.2);
      final firePeak = peak(fire, 0.4);

      final held = mk()..noteHold(1, 'piano', 440, 3);
      _render(held, 1.2);
      final heldPeak = peak(held, 0.4);
      check(
        '1) 놓기 전에는 계속 난다',
        heldPeak > 0.01 && heldPeak > firePeak * 8,
        '잡아 둠 ${heldPeak.toStringAsFixed(4)} · '
            '0.3초짜리 ${firePeak.toStringAsFixed(4)}',
      );
    }

    // 2) **놓으면 사그라든다** — 뚝 끊기지 않고, 결국 조용해진다.
    {
      final e = mk()..noteHold(1, 'piano', 440, 3);
      _render(e, 0.5);
      e.noteRelease(1);
      final justAfter = peak(e, 0.02); // 뗀 직후 — 아직 소리가 남아 있다
      // **끝자락을 봐야 한다.** 2초 구간의 봉우리를 재면 뗀 직후의 큰 값이
      // 그대로 잡혀서 「안 사그라든다」로 나온다 — 자가 엉뚱한 데를 보는 것이다.
      final tail = _render(e, 2.0);
      var later = 0.0;
      for (
        var i = tail.length - (0.2 * kSampleRate).round();
        i < tail.length;
        i++
      ) {
        final a = tail[i].abs();
        if (a > later) later = a;
      }
      check(
        '2) 놓으면 사그라든다',
        justAfter > 0.005 && later < justAfter * 0.5,
        '뗀 직후 ${justAfter.toStringAsFixed(4)} → 2초 뒤 ${later.toStringAsFixed(4)}',
      );
    }

    // 3) **목소리를 돌려준다.** 안 돌려주면 몇 번 치고 나면 소리가 안 난다.
    {
      final e = mk();
      for (var i = 0; i < 40; i++) {
        e.noteHold(i, 'piano', 220 + i * 5, 3);
        _render(e, 0.02);
        e.noteRelease(i);
        _render(e, 0.4); // 릴리스가 끝날 만큼
      }
      check(
        '3) 목소리를 돌려준다',
        e.heldCount == 0 && e.starved == 0 && e.activeCount < 8,
        '잡고 있는 것 ${e.heldCount}개 · 바닥남 ${e.starved}번 · '
            '아직 우는 것 ${e.activeCount}개',
      );
    }

    // 4) **같은 손가락은 하나만 문다.** 같은 id 로 다시 누르면 앞의 것을 놓는다.
    {
      final e = mk()
        ..noteHold(7, 'piano', 220, 3)
        ..noteHold(7, 'piano', 330, 3);
      check('4) 한 손가락에 하나', e.heldCount == 1, '${e.heldCount}개');
    }

    // 5) **두 번 떼도 안전하고, 모르는 번호도 안전하다.**
    {
      final e = mk()..noteHold(1, 'piano', 440, 3);
      _render(e, 0.1);
      e
        ..noteRelease(1)
        ..noteRelease(1)
        ..noteRelease(999);
      final v = _render(e, 1.0);
      final bad = v.where((x) => !x.isFinite).length;
      check('5) 두 번 떼도·모르는 번호도 안전', bad == 0, '이상한 값 $bad개');
    }

    // 6) **손을 안 떼도 언젠가는 놓는다.** 화면이 죽거나 메시지를 놓쳐도
    //    목소리가 영영 물려 있으면 안 된다(그때부터 그 자리는 영영 못 쓴다).
    {
      final e = mk()..noteHold(1, 'piano', 440, 3, maxSec: 0.4);
      _render(e, 1.2);
      check(
        '6) 안 떼도 언젠가는 놓는다',
        e.activeCount == 0 && e.heldCount == 0,
        '우는 것 ${e.activeCount}개 · 잡고 있는 것 ${e.heldCount}개',
      );
    }

    // 7) **저절로 끝난 자리를 다른 음이 물려받아도 안 꺼진다.**
    //    회수 루프가 손잡이를 같이 안 떼면, 그 자리에 들어온 **다른 음**을
    //    손 떼는 순간 꺼 버린다 — 소리가 이유 없이 사라지는 종류다.
    {
      final e = mk()..noteHold(1, 'piano', 440, 3, maxSec: 0.3);
      _render(e, 1.0); // 1번이 저절로 끝난다
      final goneOk = e.heldCount == 0;
      e.noteOn('piano', 660, 3.0, 3); // 그 자리를 다른 음이 쓴다
      _render(e, 0.2);
      e.noteRelease(1); // 옛 번호로 떼 본다
      final still = peak(e, 0.2);
      check(
        '7) 남의 소리를 안 끈다',
        goneOk && still > 0.005,
        '손잡이 정리 $goneOk · 그 뒤 소리 ${still.toStringAsFixed(4)}',
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '꾹 눌러 유지 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}

/// **연주 흔들림 — 타이밍.**
///
/// 여태 흔든 것은 음정(cent)과 세기뿐이었다. `Human.t` 는 **선언만 되고 아무 데서도
/// 안 쓰였다** — 그래서 박이 자로 잰 듯 딱 맞았다. 사람이 친 것과 기계가 친 것의
/// 차이는 대개 거기서 난다.
void _humanTests() {
  test('연주 흔들림 — 타이밍', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    /// 같은 시각을 [n]번 흔들어 보고 (제일 작은 값, 제일 큰 값, 평균)
    (double, double, double) spread(double t, int n) {
      var lo = double.infinity, hi = -double.infinity, sum = 0.0;
      for (var i = 0; i < n; i++) {
        final v = humanNudge(t);
        if (v < lo) lo = v;
        if (v > hi) hi = v;
        sum += v;
      }
      return (lo, hi, sum / n);
    }

    // 1) **끄면 한 치도 안 움직인다** — 시험은 늘 이 상태로 돈다.
    //    여기가 새면 지문 시험(기준 곡)이 매번 다른 답을 낸다.
    {
      Human.setLevel(0);
      var exact = true;
      for (var i = 0; i < 500; i++) {
        final t = i * 0.013;
        if (humanNudge(t) != t) exact = false;
      }
      check('1) 끄면 한 치도 안 움직인다', exact, '500번 전부 그대로');
    }

    // 2) **켜면 흔들린다 · 정해 둔 폭 안에서만**
    {
      Human.setLevel(1);
      final (lo, hi, avg) = spread(1.0, 4000);
      check(
        '2) 켜면 흔들린다 (±5.5ms 안)',
        hi > lo &&
            (1.0 - lo) <= Human.t + 1e-9 &&
            (hi - 1.0) <= Human.t + 1e-9 &&
            (avg - 1.0).abs() < Human.t * 0.15,
        '${((1 - lo) * 1000).toStringAsFixed(1)}ms 이르게 ~ '
            '${((hi - 1) * 1000).toStringAsFixed(1)}ms 늦게 · '
            '평균 ${((avg - 1) * 1000).toStringAsFixed(2)}ms',
      );
    }

    // 3) **「많이」가 실제로 더 흔들린다** — 손잡이가 뜻이 있어야 한다
    {
      Human.setLevel(1);
      final (l1, h1, _) = spread(1.0, 4000);
      Human.setLevel(2);
      final (l2, h2, _) = spread(1.0, 4000);
      check(
        '3) 「많이」가 더 흔들린다',
        (h2 - l2) > (h1 - l1) * 1.6,
        '자연스럽게 ${((h1 - l1) * 1000).round()}ms · '
            '많이 ${((h2 - l2) * 1000).round()}ms',
      );
    }

    // 4) **0보다 앞으로 당기지 않는다** — 앞으로 당겨 봐야 이미 지난 시각이라
    //    곧바로 울린다. 그건 흔든 게 아니라 앞으로 튄 것이다.
    {
      Human.setLevel(2);
      var neg = 0;
      for (var i = 0; i < 2000; i++) {
        if (humanNudge(0) < 0) neg++;
        if (humanNudge(0.001) < 0) neg++;
      }
      check('4) 0보다 앞으로 안 간다', neg == 0, '$neg번');
    }

    // 5) **실제 소리에도 걸린다** — 함수만 맞고 배선이 끊겼으면 아무 일도 안 한다.
    //    같은 곡을 두 번 만들었을 때 흔들림을 켜면 달라야 하고, 끄면 같아야 한다.
    {
      List<double> once(int level) {
        Human.setLevel(level);
        final e = Engine()..trackMix.configure(['a']);
        for (var i = 0; i < 8; i++) {
          e.schedule(i * 0.05, 'piano', 440, 0.1, 3);
        }
        return _render(e, 0.6);
      }

      final off1 = once(0), off2 = once(0);
      var offSame = off1.length == off2.length;
      for (var i = 0; offSame && i < off1.length; i++) {
        if (off1[i] != off2[i]) offSame = false;
      }
      final on1 = once(2), on2 = once(2);
      var onSame = true;
      for (var i = 0; i < on1.length && i < on2.length; i++) {
        if (on1[i] != on2[i]) {
          onSame = false;
          break;
        }
      }
      check(
        '5) 소리까지 간다 (끄면 같고 켜면 다르다)',
        offSame && !onSame,
        '끔 같음 $offSame · 켬 다름 ${!onSame}',
      );
      Human.setLevel(0); // 다음 시험을 위해 되돌린다
    }

    // ignore: avoid_print
    print(fail == 0 ? '연주 흔들림 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
