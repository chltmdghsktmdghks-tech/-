// Phase 1 후속 — **급식 경로 비용 측정.** (측정 도구 — 손으로 돌린다)
//   flutter test test/render_bench.dart
//
// '급식 지체'(20ms 넘게 늦은 횟수)의 원인을 좁히려고 만들었다.
// 실시간 급식 루프는 3ms 마다 `render` 를 부른다. 그 한 번이 얼마나 걸리는지,
// 그리고 **버퍼를 새로 만드는 것**이 그중 얼마인지를 잰다.
//
// 주의: 이 시험은 맥에서 JIT 로 돈다. 폰(AOT)과 절대값은 다르다.
// **상대 비교**(전 대 후)만 의미가 있다.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/engine.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/genre_mix.dart';
import 'package:music_doodle_engine/export.dart';
import 'package:music_doodle_engine/synth.dart';

/// 실제 곡과 비슷한 밀도로 채운다 — 빈 엔진을 재면 아무 의미가 없다.
Engine _busy() {
  final e = Engine()..trackMix.configure(['a', 'b', 'c']);
  for (var bar = 0; bar < 60; bar++) {
    final t = bar * 0.5;
    for (var s = 0; s < 4; s++) {
      e.scheduleDrum(t + s * 0.125, 'acoustic', 'hat', s == 0 ? 2 : 1);
    }
    e.scheduleDrum(t, 'acoustic', 'kick', 3);
    e.scheduleDrum(t + 0.25, 'acoustic', 'snare', 3);
    e.schedule(t, 'fingerbass', 98.0, 0.45, 3, part: kPartBass);
    for (final f in [261.63, 311.13, 392.0]) {
      e.schedule(t, 'epiano', f, 0.9, 2, soft: true, part: kPartChord);
    }
    e.schedule(t + 0.25, 'sax', 523.25, 0.3, 3, part: kPartMelody);
  }
  return e;
}

void main() {
  test('급식 경로 비용', () {
    Human.setLevel(0);
    const chunk = 1024; // 급식 루프가 쓰는 크기(_kChunk)
    const seconds = 20.0;
    final rounds = (seconds * kSampleRate / chunk).round();

    // (가) 예전 방식 — 부를 때마다 새 버퍼
    final e1 = _busy();
    final sw1 = Stopwatch()..start();
    for (var i = 0; i < rounds; i++) {
      e1.render(chunk);
    }
    sw1.stop();

    // (나) 지금 방식 — 버퍼 하나를 돌려쓴다
    final e2 = _busy();
    final buf = Int16List(chunk * 2);
    final sw2 = Stopwatch()..start();
    for (var i = 0; i < rounds; i++) {
      e2.renderInto(buf, chunk);
    }
    sw2.stop();

    final ms1 = sw1.elapsedMicroseconds / 1000.0;
    final ms2 = sw2.elapsedMicroseconds / 1000.0;
    final per1 = sw1.elapsedMicroseconds / rounds / 1000.0;
    final per2 = sw2.elapsedMicroseconds / rounds / 1000.0;
    // 오디오 1초를 만드는 데 실제로 몇 초를 쓰는가 — 1.0 이면 실시간 한계
    final rt1 = ms1 / 1000.0 / seconds;
    final rt2 = ms2 / 1000.0 / seconds;
    // 버퍼를 새로 만들면서 버리는 쓰레기 — 초당 몇 KB인가
    final garbagePerSec = chunk * 2 * 2 * (kSampleRate / chunk) / 1024.0;

    // ignore: avoid_print
    print('''
  오디오 ${seconds.toStringAsFixed(0)}초 · 청크 $chunk프레임 · $rounds번 호출

  새 버퍼(예전)   총 ${ms1.toStringAsFixed(0)}ms · 한 번 ${per1.toStringAsFixed(3)}ms · 실시간 대비 ${(rt1 * 100).toStringAsFixed(1)}%
  버퍼 재사용(지금) 총 ${ms2.toStringAsFixed(0)}ms · 한 번 ${per2.toStringAsFixed(3)}ms · 실시간 대비 ${(rt2 * 100).toStringAsFixed(1)}%
  차이            ${(ms1 - ms2).toStringAsFixed(0)}ms (${((1 - ms2 / ms1) * 100).toStringAsFixed(1)}%)
  없앤 쓰레기      초당 ${garbagePerSec.toStringAsFixed(0)}KB''');

    // 두 방식의 **결과가 같아야** 비교가 의미 있다
    final a = _busy(), b = _busy();
    final bufB = Int16List(chunk * 2);
    var same = true;
    for (var i = 0; i < 20 && same; i++) {
      final x = a.render(chunk);
      b.renderInto(bufB, chunk);
      for (var k = 0; k < chunk * 2; k++) {
        if (x[k] != bufB[k]) {
          same = false;
          break;
        }
      }
    }
    // ignore: avoid_print
    print('  두 방식 결과 ${same ? "완전히 같음" : "**다름 — 고칠 것**"}');
    expect(same, true);
  });

  // ── 곡 전체 · 장르 인서트까지 ──
  //
  // 성능 문턱은 **여기 있어야 한다.** `long_run_test`(자동)에 넣었더니 병렬 실행에서
  // 4.6% ↔ 45.6% 로 흔들렸다 — 시계로 재는 것은 조용한 기계에서 일부러 돌려야 한다.
  // 이 파일은 `_test.dart` 가 아니라 `flutter test` 가 자동으로 안 집어간다.
  test('곡 전체 렌더 — 인서트 포함', () {
    Human.setLevel(0);
    // ignore: avoid_print
    print('장르        길이   인서트없이 → 켜고        실시간%');
    for (final key in ['trap', 'proghouse', 'rock', 'ambient', 'lofi']) {
      final g = genreDef(key);
      final p = Project.initial()..setGenre(key);
      final tr = Transport()
        ..bpm = g.bpm
        ..mode = g.mode;
      final b = SceneSequencer.buildSong(p, tr);
      ExportJob job({required bool fx}) => ExportJob(
        notes: b.notes,
        drums: b.drums,
        busNames: b.busNames,
        buses: SceneSequencer.mixSnapshot(p),
        inserts: fx ? SceneSequencer.insertSnapshot(p) : const {},
        duck: kGenreDuck[key] ?? 0,
        masterVol: styleGain(key),
        seconds: b.totalSec,
      );
      int ms(bool fx) {
        final sw = Stopwatch()..start();
        renderWav(job(fx: fx));
        return sw.elapsedMilliseconds;
      }

      ms(false); // 예열
      final off = ms(false), on = ms(true);
      final n = SceneSequencer.insertSnapshot(
        p,
      ).values.fold<int>(0, (a, l) => a + l.length);
      // ignore: avoid_print
      print(
        '${key.padRight(11)} ${b.totalSec.round().toString().padLeft(3)}초 '
        '인서트 $n개 · ${off}ms → ${on}ms (+${((on / off - 1) * 100).round()}%)   '
        '${(on / (b.totalSec * 1000) * 100).toStringAsFixed(1)}%',
      );
    }
  });
}
