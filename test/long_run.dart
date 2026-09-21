// **수동 도구** — 13곡 전부를 끝까지 렌더한다. `flutter test test/long_run.dart`
//
// 자동 시험(`long_run_test.dart`)은 대표 세 곡만 본다. 열세 곡은 35분 분량이라
// 매번 돌리기엔 무겁고, 이 기계는 그 사이 **15분씩 멈추는 일**이 있다
// (같은 곡이 8초였다가 900초가 된다 — 멈추는 곡이 매번 바뀌므로 코드 성질이 아니다).
// 그래서 깊이 보는 것은 여기, 매번 도는 것은 저기로 나눴다.
// P0 — **곡을 끝까지 돌려 본다.** (개선 계획 3-1·3-6 · §19 P0)
//   flutter test test/long_run_test.dart
//
// 골든 시험(`engine_guard_test`)은 **4초**만 렌더한다. 짧게 보면 못 잡는 것들이 있다:
//  · 목소리가 새는 것(음이 안 꺼져서 조금씩 쌓이는 것)
//  · 뒤로 갈수록 커지거나 작아지는 것
//  · DC 가 서서히 밀리는 것(스피커를 밀어 놓는다)
//  · 특정 구간에서만 넘치는 것(드롭은 3분짜리 곡의 2분 30초에 온다)
//
// Phase 3~6 에서 얹은 것이 많다 — 변형(판이 4배), 구간 성격, 3배 길어진 킥, 장르 13개.
// **그 전부를 얹고 끝까지 돌려 본 적이 없다.** 여기서 한 번에 본다.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/engine.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/synth.dart';

class _Run {
  final String genre;
  final double sec, peak, dcHead, dcTail, rmsHead, rmsTail, renderMs;
  final int clipped, starved, drumStarved, maxVoice, maxDrum, bad, endActive;
  const _Run(
    this.genre,
    this.sec,
    this.peak,
    this.dcHead,
    this.dcTail,
    this.rmsHead,
    this.rmsTail,
    this.renderMs,
    this.clipped,
    this.starved,
    this.drumStarved,
    this.maxVoice,
    this.maxDrum,
    this.bad,
    this.endActive,
  );
}

/// 곡을 끝까지 렌더해 보고 위생을 검사한다.
/// [only] 를 주면 그 장르만 본다(자동 시험은 대표 셋만 돌린다).
void runLongCheck({List<String>? only}) {
  test('곡을 끝까지', () {
    Human.setLevel(0);
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final runs = <_Run>[];
    for (final g in kGenres) {
      if (only != null && !only.contains(g.key)) continue;
      final p = Project.initial()..setGenre(g.key);
      final tr = Transport()
        ..bpm = g.bpm
        ..mode = g.mode;
      final b = SceneSequencer.buildSong(p, tr);
      final e = Engine()..trackMix.configure(b.busNames);
      for (final d in b.drums) {
        e.scheduleDrum(
          (d[4] as num).toDouble(),
          d[0] as String,
          d[1] as String,
          d[2] as int,
          tomFreq: (d[3] as num).toDouble(),
        );
      }
      for (final n in b.notes) {
        e.schedule(
          (n[6] as num).toDouble(),
          n[0] as String,
          (n[1] as num).toDouble(),
          (n[2] as num).toDouble(),
          n[3] as int,
          soft: n[4] as bool,
          glideF: (n[5] as num).toDouble(),
          part: n[7] as int,
        );
      }

      // 꼬리까지 — 마지막 음이 다 사라지도록 3초 더 돌린다
      final total = ((b.totalSec + 3) * kSampleRate).round();
      final buf = Int16List(1024 * 2);
      var done = 0, clipped = 0, bad = 0;
      var peak = 0.0;
      var dcHead = 0.0, dcTail = 0.0, rmsHead = 0.0, rmsTail = 0.0;
      var nHead = 0, nTail = 0;
      final headEnd = (total * 0.15).round(),
          tailStart = (total * 0.85).round();
      final sw = Stopwatch()..start();
      while (done < total) {
        final n = math.min(1024, total - done);
        e.renderInto(buf, n);
        for (var i = 0; i < n * 2; i++) {
          final v = buf[i] / 32768.0;
          if (v.isNaN || v.isInfinite) bad++;
          final a = v.abs();
          if (a > peak) peak = a;
          if (a >= 0.9999) clipped++;
          if (done + (i ~/ 2) < headEnd) {
            dcHead += v;
            rmsHead += v * v;
            nHead++;
          } else if (done + (i ~/ 2) >= tailStart) {
            dcTail += v;
            rmsTail += v * v;
            nTail++;
          }
        }
        done += n;
      }
      sw.stop();
      runs.add(
        _Run(
          g.key,
          b.totalSec,
          peak,
          nHead == 0 ? 0 : dcHead / nHead,
          nTail == 0 ? 0 : dcTail / nTail,
          nHead == 0 ? 0 : math.sqrt(rmsHead / nHead),
          nTail == 0 ? 0 : math.sqrt(rmsTail / nTail),
          sw.elapsedMilliseconds.toDouble(),
          clipped,
          e.starved,
          e.drumStarved,
          e.maxActive,
          e.maxActiveDrums,
          bad,
          e.activeCount + e.drumActiveCount,
        ),
      );
    }

    // ignore: avoid_print
    print('장르        길이   렌더    실시간%  피크  클립  음부족  최대음/드럼  끝난뒤');
    for (final r in runs) {
      final rt = r.renderMs / (r.sec * 1000) * 100;
      // ignore: avoid_print
      print(
        '${r.genre.padRight(11)} ${r.sec.round().toString().padLeft(3)}초 '
        '${r.renderMs.round().toString().padLeft(5)}ms '
        '${rt.toStringAsFixed(1).padLeft(6)}% '
        '${r.peak.toStringAsFixed(3)} '
        '${r.clipped.toString().padLeft(5)} '
        '${(r.starved + r.drumStarved).toString().padLeft(6)} '
        '${'${r.maxVoice}/${r.maxDrum}'.padLeft(12)}   ${r.endActive}',
      );
    }

    // ── 1) 위생 ──
    final nan = [
      for (final r in runs)
        if (r.bad > 0) '${r.genre}(${r.bad})',
    ];
    final all = '${runs.length}곡 전부';
    check('1) NaN·무한대 없음', nan.isEmpty, nan.isEmpty ? all : nan.join(', '));
    final clip = [
      for (final r in runs)
        if (r.clipped > 0) '${r.genre}(${r.clipped})',
    ];
    check('1-b) 하드클립 없음', clip.isEmpty, clip.isEmpty ? all : clip.join(', '));

    // ── 2) 목소리가 새지 않는다 ──
    //
    // 곡이 끝나고 3초를 더 돌렸는데도 울리고 있으면 **안 꺼지는 음**이 있는 것이다.
    // 짧은 시험으로는 절대 안 잡힌다 — 3분을 돌려야 쌓인다.
    final leak = [
      for (final r in runs)
        if (r.endActive > 0) '${r.genre}(${r.endActive}개)',
    ];
    check(
      '2) 끝나면 다 꺼진다',
      leak.isEmpty,
      leak.isEmpty ? '$all 0개' : leak.join(', '),
    );

    final starve = [
      for (final r in runs)
        if (r.starved + r.drumStarved > 0)
          '${r.genre}(${r.starved}+${r.drumStarved})',
    ];
    check(
      '2-b) 목소리가 모자라지 않는다',
      starve.isEmpty,
      starve.isEmpty ? all : starve.join(', '),
    );

    // ── 3) 뒤로 갈수록 밀리지 않는다 ──
    final drift = [
      for (final r in runs)
        if (r.dcTail.abs() > 0.004)
          '${r.genre}(${r.dcTail.toStringAsFixed(4)})',
    ];
    check(
      '3) DC 가 안 밀린다',
      drift.isEmpty,
      drift.isEmpty ? '끝 15% 구간 전부 |DC|<0.004' : drift.join(', '),
    );

    // 앞 15% 와 뒤 15% 의 크기 — **10배 넘게 벌어지면** 뭔가 새거나 죽은 것이다.
    // (인트로가 여리고 아웃트로가 잦아드는 것은 정상이라 넉넉히 잡는다.)
    final lop = [
      for (final r in runs)
        if (r.rmsHead > 0 &&
            r.rmsTail > 0 &&
            (r.rmsTail / r.rmsHead > 10 || r.rmsHead / r.rmsTail > 10))
          '${r.genre}(${(r.rmsTail / r.rmsHead).toStringAsFixed(1)}배)',
    ];
    check(
      '3-b) 앞뒤 크기가 뒤집히지 않는다',
      lop.isEmpty,
      lop.isEmpty ? all : lop.join(', '),
    );

    // ── 성능은 여기서 안 잰다 ──
    //
    // 처음엔 「실시간의 12% 안」을 넣었다가 두 번 데었다:
    //   · 같은 곡이 혼자 돌리면 4.6%, 다 같이 돌리면 45.6%
    //   · 상대값(제일 무거운 곡 ÷ 제일 가벼운 곡)으로 바꿔도 182배가 나왔다
    // `flutter test` 는 시험들을 **동시에** 돌린다. 시계로 재는 것은 그 안에서
    // 어떤 방식으로든 흔들리고, **흔들리는 시험은 결국 아무도 안 본다** — 없는 것보다 나쁘다.
    //
    // 그래서 여기는 **맞고 틀림**만 본다(NaN·클립·새는 목소리·DC). 그건 몇 번을 돌려도
    // 같은 답이 나온다. 성능은 조용한 기계에서 일부러 돌리는 도구가 맡는다
    // (`render_bench` · `mix_meter`) — 위에 찍힌 렌더 시간도 **참고값**일 뿐이다.

    // ignore: avoid_print
    print(fail == 0 ? '곡 끝까지 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}

void main() => runLongCheck();
