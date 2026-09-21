// 5단계 34/N — 스타일 11개의 **소리 크기**를 잰다. (측정 도구 — 손으로 돌린다)
//   flutter test test/mix_meter.dart
//
// 파일 이름이 `_test.dart` 가 **아닌 이유**: 11곡을 통째로 렌더하느라 10분 넘게 걸린다.
// `flutter test` 는 `_test.dart` 만 자동으로 집어가므로 평소 시험에는 안 낀다.
// GENRE_MIX 나 kStyleGain 을 건드렸을 때만 돌리면 된다.
//
// 귀로는 못 잡는 문제가 있다: 스타일마다 GENRE_MIX 값이 따로 있어서 어떤 곡은
// 작고 어떤 곡은 크다. 곡을 바꿔 가며 듣다가 **볼륨을 계속 만져야 하면** 그게 고장이다.
// 눈으로는 안 보이고 귀로는 기억이 안 나므로 잰다.
//
//  · peak — 가장 큰 샘플(1.0 이면 깎였다는 뜻)
//  · RMS  — 평균 크기(dBFS). 사람이 느끼는 '음량'에 제일 가깝다
//  · clip — 꽉 찬 샘플 수
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/export.dart';
import 'package:music_doodle_engine/genre_mix.dart';
import 'package:music_doodle_engine/presets.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/synth.dart';

/// 한 스타일을 잰 결과.
class _Meas {
  final double peak;

  /// 곡 전체 평균(dBFS).
  final double avgDb;

  /// **제일 시끄러운 3초 구간**의 평균(dBFS). 사람이 "이 곡 크다/작다"를 정하는 건
  /// 곡 전체 평균이 아니라 제일 큰 대목(보통 코러스)이다.
  final double loudDb;

  final int clip;
  const _Meas(this.peak, this.avgDb, this.loudDb, this.clip);
}

_Meas _meter(String genre) {
  final p = Project.initial();
  final g = songGenreOf(genre);
  final tr = Transport()
    ..bpm = g.$3
    ..mode = g.$5;
  p.setGenre(genre);

  // **곡 전체**를 렌더한다. 두 번 지름길을 찾다가 두 번 다 틀렸다:
  //  · 앞 20초만 → 빠른 스타일은 그 안에 코러스가 들어오고 느린 스타일은 인트로만
  //    들어온다. 느린 쪽이 조용해 보인다('재즈가 15dB 작다'는 결론을 낼 뻔했다).
  //  · 코러스 씬만 → **객체형 스타일(트랩·재즈 등)은 씬 클립과 곡의 구간이 다르다.**
  //    트랩 피크가 0.96 → 0.70 으로 떨어졌다. 같은 소리가 아니다.
  // 그래서 느려도 통째로 렌더한다(11개에 10분 남짓 — 그래서 이 파일은
  // `_test.dart` 가 아니다. `flutter test` 가 자동으로 안 집어간다).
  final b = SceneSequencer.buildSong(p, tr);

  // **내보내기와 같은 것을 넘긴다.** 예전엔 인서트와 비켜 주기를 안 넘겨서
  // 실제로 나가는 소리와 **다른 신호를 재고 있었다** — 장르 인서트를 넣었는데
  // 숫자가 하나도 안 움직여서 알았다(자가 틀린 다섯 번째다).
  final wav = renderWav(
    ExportJob(
      notes: b.notes,
      drums: b.drums,
      busNames: b.busNames,
      buses: SceneSequencer.mixSnapshot(p),
      inserts: SceneSequencer.insertSnapshot(p),
      duck: kGenreDuck[genre] ?? 0,
      masterVol: styleGain(genre), // 스타일 보정까지 넣은 **실제로 나가는 소리**를 잰다
      seconds: b.totalSec,
    ),
  );

  // WAV 44바이트 헤더 뒤부터 16비트 스테레오 리틀엔디언
  const win = 3 * 48000 * 2; // 3초 = 샘플 수 × 채널 2
  var peak = 0.0, sum = 0.0;
  var clip = 0, n = 0;
  var winSum = 0.0, winN = 0, loudest = 0.0;
  for (var i = 44; i + 1 < wav.length; i += 2) {
    var v = wav[i] | (wav[i + 1] << 8);
    if (v >= 0x8000) v -= 0x10000;
    final f = v / 32768.0;
    final a = f.abs();
    if (a > peak) peak = a;
    if (a >= 0.999) clip++;
    sum += f * f;
    n++;
    winSum += f * f;
    if (++winN >= win) {
      final w = winSum / winN;
      if (w > loudest) loudest = w;
      winSum = 0;
      winN = 0;
    }
  }
  double db(double meanSq) => meanSq <= 0 ? -99.0 : 10 * (log(meanSq) / ln10);
  return _Meas(peak, db(n == 0 ? 0 : sum / n), db(loudest), clip);
}

void main() {
  test('스타일별 소리 크기', () {
    Human.setLevel(0);
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    // ignore: avoid_print
    print('스타일         peak   전체(dB)  제일큰3초  clip');
    final rows = <(String, _Meas)>[];
    for (final g in kSongGenres) {
      final m = _meter(g.$1);
      rows.add((g.$2, m));
      // ignore: avoid_print
      print(
        '${g.$2.padRight(13)} ${m.peak.toStringAsFixed(3)}  '
        '${m.avgDb.toStringAsFixed(1).padLeft(6)}   '
        '${m.loudDb.toStringAsFixed(1).padLeft(6)}    ${m.clip}',
      );
    }

    // 1) 깎이는 곡이 없어야 한다 — 깎이면 지직거린다
    final clipped = [
      for (final r in rows)
        if (r.$2.clip > 0) '${r.$1}(${r.$2.clip})',
    ];
    check(
      '1) 클리핑 없음',
      clipped.isEmpty,
      clipped.isEmpty ? '${rows.length}개 모두 0' : clipped.join(', '),
    );

    // 2) 소리가 나긴 나야 한다(무음 스타일이 있으면 그 곡은 통째로 고장이다)
    final silent = [
      for (final r in rows)
        if (r.$2.loudDb < -40) r.$1,
    ];
    check(
      '2) 다 소리가 난다',
      silent.isEmpty,
      silent.isEmpty ? '전부 -40dB 위' : '조용한 스타일 ${silent.join(', ')}',
    );

    // 3) **스타일끼리 크기가 비슷해야 한다.** 곡을 바꿀 때마다 볼륨을 만져야 하면
    //    그게 고장이다. 제일 큰 대목끼리 견준다(사람이 크기를 정하는 건 거기다).
    //    6dB = 체감 두 배쯤 — 그 안으로 붙인다.
    final dbs = [for (final r in rows) r.$2.loudDb];
    final lo = dbs.reduce(min), hi = dbs.reduce(max);
    final loName = rows.firstWhere((r) => r.$2.loudDb == lo).$1;
    final hiName = rows.firstWhere((r) => r.$2.loudDb == hi).$1;
    check(
      '3) 스타일끼리 크기 차이',
      hi - lo <= 6.0,
      '${(hi - lo).toStringAsFixed(1)}dB '
          '(가장 작은 $loName ${lo.toStringAsFixed(1)} · 가장 큰 $hiName ${hi.toStringAsFixed(1)})',
    );

    // ignore: avoid_print
    print(fail == 0 ? '소리 크기 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
