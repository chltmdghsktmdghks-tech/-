// 드럼 표본 — `sampler.dart` 와 같은 생각이지만 드럼 조각용.
//
// 왜 따로인가 — `sampler.dart` 는 "악기 하나 = 음 하나(root+세기)로 피치
// 시프트" 를 전제로 한다. 드럼은 다르다:
//   - 대부분 조각(킥·스네어·크래시·라이드·하이햇)은 **피치가 없다** — 항상
//     같은 높이로 튼다.
//   - 세기 세 벌이 "더 큰 소리"가 아니라 **다른 조각**일 수 있다 — 특히
//     하이햇은 세기 3(열림)과 1~2(닫힘)가 아예 다른 녹음이다(`drums.dart`
//     의 `hat()` 참고, `open = vel >= 3`).
//   - **라운드로빈이 진짜 있다** — 조각당 여러 벌을 갖고 있다가 매번
//     하나를 무작위로 골라서, 16비트 하이햇처럼 자주 반복되는 소리가
//     기계총처럼 안 들리게 한다(`drums.dart` 의 `_Hit` 흔들림과 같은 목적,
//     다만 표본은 진짜 다른 녹음이라 더 낫다).
//
// 톰만 예외 — 실제로 음정이 있어서(곡마다 다른 `tomFreq`) 피치 시프트가
// 필요하다. `kDrumRootFreq` 에 있는 조각만 피치를 바꾸고, 나머진 원음
// 그대로 튼다.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

import 'sampler.dart' show SampleClip, parseSampleWav;

/// 조각별 라운드로빈 벌 수 — `assets/samples/drum_<조각>/` 에 실제로 있는
/// 파일 수와 맞아야 한다(`<조각>.<세기>.<n>.wav`, n=1..이 값).
const Map<String, int> _kDrumRRCount = {
  'kick': 2,
  'snare': 2,
  'hatClosed': 2,
  'hatOpen': 2,
  'crash': 1,
  'ride': 1,
  'tom': 1,
};

/// 피치가 있는 조각만 — 나머진 항상 원음 그대로 튼다.
const Map<String, double> kDrumRootFreq = {'tom': 180.0};

class DrumSampleBank {
  final Map<int, List<SampleClip>> byVel;
  const DrumSampleBank(this.byVel);

  /// [vel] 층에서 라운드로빈 하나를 무작위로 고른다.
  SampleClip pick(int vel, math.Random rng) {
    final list = byVel[vel] ?? byVel[2] ?? byVel.values.first;
    return list[rng.nextInt(list.length)];
  }
}

/// 채워지면 그 조각은 표본으로 운다. 비어 있으면 `drums.dart` 가 합성으로
/// 대신한다 — `sampler.dart` 와 같은 안전장치.
final Map<String, DrumSampleBank> kDrumSampleBanks = {};

final Set<String> _loadingDrum = {};

/// [piece] 표본 하나만 읽는다(악기별 지연 로딩과 같은 이유— `sampler.dart`
/// 문서 참고). 곡이 안 쓰는 조각은 안 읽는다.
Future<void> ensureDrumPieceLoaded(String piece) async {
  if (kDrumSampleBanks.containsKey(piece) || _loadingDrum.contains(piece)) {
    return;
  }
  final rr = _kDrumRRCount[piece];
  if (rr == null) return; // 표본이 원래 없는 조각(림샷·박수·쉐이커·카우벨)
  _loadingDrum.add(piece);
  try {
    final rootFreq = kDrumRootFreq[piece] ?? 1.0;
    final byVel = <int, List<SampleClip>>{1: [], 2: [], 3: []};
    for (final entry in const {'pp': 1, 'mf': 2, 'ff': 3}.entries) {
      for (var n = 1; n <= rr; n++) {
        final path = 'assets/samples/drum_$piece/$piece.${entry.key}.$n.wav';
        final data = await rootBundle.load(path);
        byVel[entry.value]!.add(
          parseSampleWav(data.buffer.asUint8List(), rootFreq),
        );
      }
    }
    kDrumSampleBanks[piece] = DrumSampleBank(byVel);
  } catch (_) {
    // 못 읽으면 이 조각만 합성으로 대신한다 — 다른 조각 로드엔 영향 없다.
  } finally {
    _loadingDrum.remove(piece);
  }
}
