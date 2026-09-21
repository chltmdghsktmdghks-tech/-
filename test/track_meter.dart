// 5단계 53/N — **트랙별로 얼마나 크게 들리는가**를 잰다. (측정 도구 — 손으로 돌린다)
//   flutter test test/track_meter.dart
//
// ── 왜 RMS 만으로는 모자란가 (2026-08-29) ──
// 처음엔 「그 트랙만 남긴 렌더의 RMS」로 봤다. 그런데 재즈 비브라폰을 한 옥타브
// 올렸더니 **숫자가 내려갔다** — 소리는 더 잘 들리는데. RMS 는 저역이 좌우한다.
// 높은 악기는 RMS 가 작아도 **아무도 안 쓰는 대역**에 있어서 잘 들린다.
//
// 그래서 재는 것을 바꿨다 — **마스킹 여유**:
//   1) 그 트랙만 렌더 → 5개 대역 중 **어느 대역이 이 악기의 자리인가**
//   2) 곡 전체에서 그 대역이 얼마나 큰가
//   3) 둘의 차 = 이 악기가 제 자리에서 얼마나 차지하는가
// 0dB 에 가까우면 그 대역은 사실상 이 악기 것이고, 크게 음수면 **덮여** 있다.
//
// ── 어느 토막을 볼 것인가 (여기서 한 번 틀렸다) ──
// 대역 필터는 무겁다(초당 4.8만 샘플 × 5대역). 곡을 통째로 거르면 몇십 분이 걸린다.
// 처음엔 **곡의 1/4·1/2·3/4 지점**에서 5초씩 봤다 — 그랬더니 재즈 기타가 −81dB,
// 즉 '무음'으로 나왔다. 기타는 곡의 **33~49%** 구간에서만 친다. 세 토막이 전부
// 비껴간 것이다. 악기를 의심하기 전에 **내가 어디를 봤는지**를 봐야 했다.
//
// 지금은 **그 악기가 제일 크게 우는 5초 토막 세 개**를 그 트랙 스스로 고르고,
// 곡 전체도 **같은 토막**에서 잰다. 「이 악기가 울 때, 뚫고 나오는가」가 질문이다.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/export.dart';
import 'package:music_doodle_engine/genre_mix.dart';
import 'package:music_doodle_engine/instruments.dart' show VOICE_LABEL;
import 'package:music_doodle_engine/presets.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/synth.dart';

const _edges = [120.0, 500.0, 2000.0, 6000.0];
const _bandName = ['저역', '저중', '중역', '중고', '고역'];

double _db(double e, int n) {
  final r = sqrt(e / max(1, n));
  return r <= 1e-9 ? -120 : 20 * (log(r) / ln10);
}

/// 이 소리가 제일 큰 5초 토막 세 개의 시작 위치.
List<int> _hotSpots(List<double> x) {
  const win = 5 * 48000;
  const hop = 48000;
  final scores = <(int, double)>[];
  for (var st = 0; st + win <= x.length; st += hop) {
    var e = 0.0;
    for (var i = st; i < st + win; i += 8) {
      e += x[i] * x[i];
    }
    scores.add((st, e));
  }
  if (scores.isEmpty) return [0];
  scores.sort((a, b) => b.$2.compareTo(a.$2));
  // 겹치지 않는 것으로 셋
  final out = <int>[];
  for (final s in scores) {
    if (out.every((o) => (o - s.$1).abs() >= win)) out.add(s.$1);
    if (out.length == 3) break;
  }
  return out;
}

/// 5개 대역의 dB — 주어진 토막들만 본다.
List<double> _bandDb(List<double> x, List<int> spots) {
  const win = 5 * 48000;
  final out = <double>[];
  for (var b = 0; b <= _edges.length; b++) {
    var e = 0.0;
    var n = 0;
    for (final st in spots) {
      final hp = b == 0 ? null : (Biquad()..highpass(_edges[b - 1], 0.707));
      final lp = b == _edges.length
          ? null
          : (Biquad()..lowpass(_edges[b], 0.707));
      for (var i = st; i < st + win && i < x.length; i++) {
        var y = x[i];
        if (hp != null) y = hp.process(y);
        if (lp != null) y = lp.process(y);
        e += y * y;
        n++;
      }
    }
    out.add(_db(e, n));
  }
  return out;
}

double _rmsDb(List<double> x) {
  var e = 0.0;
  for (final v in x) {
    e += v * v;
  }
  return _db(e, x.length);
}

List<double> _render(Project p, SceneBuild b, Map<String, List<double>> buses) {
  final wav = renderWav(
    ExportJob(
      notes: b.notes,
      drums: b.drums,
      busNames: b.busNames,
      buses: buses,
      inserts: SceneSequencer.insertSnapshot(p),
      masterVol: styleGain(p.genre),
      // **곡 전체를 다 렌더해야 한다.** 앞 45초만 잘랐더니 비브라폰(50초 등장)과
      // 기타(66초 등장)가 '무음'으로 나왔다 — 악기가 늦게 들어오는 편곡이라 그렇다.
      seconds: b.totalSec,
    ),
  );
  final out = <double>[];
  for (var i = 44; i + 3 < wav.length; i += 4) {
    int s16(int a) {
      final v = wav[a] | (wav[a + 1] << 8);
      return v >= 0x8000 ? v - 0x10000 : v;
    }

    out.add((s16(i) + s16(i + 2)) / 2 / 32768.0);
  }
  return out;
}

void main() {
  test('트랙별 크기', () {
    Human.setLevel(0);
    for (final g in ['jazz', 'rnb', 'pop']) {
      final p = Project.initial()..setGenre(g);
      final tr = Transport()
        ..bpm = songGenreOf(g).$3
        ..mode = songGenreOf(g).$5;
      final b = SceneSequencer.buildSong(p, tr);
      final full = SceneSequencer.mixSnapshot(p);
      final all = _render(p, b, full);
      // ignore: avoid_print
      print(
        '\n── ${songGenreOf(g).$2} ── 전체 ${_rmsDb(all).toStringAsFixed(1)}dB',
      );
      // ignore: avoid_print
      print('   트랙          음색          제자리  차지  RMS   울리는때');
      for (final t in p.tracks) {
        final bus = SceneSequencer.busOf(t);
        final only = _render(p, b, {
          for (final e in full.entries)
            e.key: [e.key == bus ? e.value[0] : 0.0, ...e.value.sublist(1)],
        });
        final spots = _hotSpots(only);
        final eo = _bandDb(only, spots);
        final ea = _bandDb(all, spots);
        var top = 0;
        for (var i = 1; i < eo.length; i++) {
          if (eo[i] > eo[top]) top = i;
        }
        final margin = eo[top] - ea[top];
        final mark = margin < -18 ? '  ← 묻힘' : (margin < -12 ? '  ← 작다' : '');
        final when = spots.map((s) => '${(s / 48000).round()}초').join(',');
        // ignore: avoid_print
        print(
          '   ${t.name.padRight(12)} ${(VOICE_LABEL[t.voice] ?? t.voice).padRight(12)}'
          ' ${_bandName[top]}  ${margin.toStringAsFixed(1).padLeft(6)}dB'
          '  ${_rmsDb(only).toStringAsFixed(1).padLeft(6)}  $when$mark',
        );
      }
    }
  });
}
