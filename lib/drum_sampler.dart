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

/// 표본 세트 — 폴더 앞머리(`assets/samples/<세트>_<조각>/`)다.
///  - `drum`  : FreePats MuldjordKit (22.05kHz, CC BY 4.0) — 기존, 지우지 않는다.
///  - `avirt` : sfzinstruments/virtuosity_drums `mid` 마이크 (44.1kHz, CC0-1.0).
///    2026-09-29 — 22.05kHz 표본은 11kHz 위가 통째로 없어 "형편없이" 들렸다.
const String kDefaultDrumSet = 'drum';

/// 세트별·조각별 라운드로빈 벌 수 — `assets/samples/<세트>_<조각>/` 에 실제로 있는
/// 파일 수와 맞아야 한다(`<조각>.<세기>.<n>.wav`, n=1..이 값).
const Map<String, Map<String, int>> _kDrumRRCount = {
  'drum': {
    'kick': 2,
    'snare': 2,
    'hatClosed': 2,
    'hatOpen': 2,
    'crash': 1,
    'ride': 1,
    'tom': 1,
  },
  'avirt': {
    'kick': 2,
    'snare': 2,
    'hatClosed': 2,
    'hatOpen': 2,
    'crash': 2,
    'ride': 2,
    // 톰은 [낮은 톰, 높은 톰] 두 벌을 번갈아(무작위) 친다 — 원음 그대로.
    'tom': 2,
  },
};

/// 피치가 있는 조각만 — 나머진 항상 원음 그대로 튼다. 기존 세트(`drum`) 전용:
/// avirt 톰은 낮은/높은 톰이 실제로 다른 북이라 늘이지 않는다.
const Map<String, double> kDrumRootFreq = {'tom': 180.0};

/// 뱅크 키 — 기존 세트는 예전 그대로 조각 이름, 그 외는 `세트:조각`.
String drumBankKey(String piece, [String set = kDefaultDrumSet]) =>
    set == kDefaultDrumSet ? piece : '$set:$piece';

/// 세트·조각별 음량 보정 — 원본 녹음 레벨이 세트마다 달라서 킷 사이(그리고
/// 스네어 대비 하이햇) 크기를 맞춘다. 재는 법: `test/drum_set_level_test.dart`.
const Map<String, Map<String, double>> kDrumSetTrim = {
  // 킷 사이 크기를 예전 어쿠스틱(v3 RMS)에 맞췄다 — 2026-09-29 측정,
  // 표는 `test/drum_set_level_test.dart`. 하이햇은 일부러 안 올렸다(스네어보다 작게).
  'avirt': {
    'kick': 2.09, // +6.4dB
    'snare': 0.85, // -1.4dB
    'tom': 1.08,
    'crash': 2.5, // +8dB
    'ride': 4.2, // +12.5dB (2026-09-30: 3.0 -> 4.2, 스네어 대비 rms -12.8 -> -9.8dB)
    // 2026-09-30: 고역 셸프(kDrumSetBright)가 하이햇을 +9dB(closed)/+1.5dB(open) 키워서
    // 되돌린다 — 닫힌 v2 피크가 스네어 v2 보다 컸다(-10.8 vs -12.5dB).
    'hatClosed': 0.41, // -7.7dB
    'hatOpen': 0.85, // -1.4dB
  },
};

/// 킥 비터 클릭 합성 겹침 세기(표본 킥 진폭 대비) — 세트별. 없으면 안 얹는다.
/// 2026-09-29: avirt 킥(펠트 비터 재즈 킥)은 클릭이 거의 없어 얹는다.
/// 값은 앞 20ms 의 2-6kHz 비율이 예전 세트(≈2.5%) 수준이 되게 잰 것 —
/// `test/drum_set_level_test.dart`. 끄려면 0 대신 항목을 지운다.
const Map<String, double> kDrumKickClick = {'avirt': 0.20};
const double kDrumKickClickSec = 0.006;
const double kDrumKickClickTau = 0.0009;

/// 세트가 자체 세기 층(pp/mf/ff 를 실제 세기로 골라 둔 표본)을 갖고 있으면
/// 신스용 `VG`(0.3/0.6/1.0)를 또 곱하지 않는다 — 두 번 깎으면 여린 소리가 안 들린다.
/// null 이면 호출한 쪽이 `VG` 를 쓴다.
///
/// 크래시·라이드는 원본 세기 층이 좁아(크래시 11dB · 라이드 mf/ff 는 같은 층)
/// 여린 쪽만 조금 낮춘다.
double? drumSetVelGain(String set, int vel, [String piece = '']) {
  if (set != 'avirt') return null;
  if (piece == 'crash' || piece == 'ride') {
    return const {1: 0.5, 2: 0.75, 3: 1.0}[vel] ?? 1.0;
  }
  return 1.0;
}

/// 고역 살리기(하이 셸프) — 세트·조각별 세기 배수 k. `out = s + k * (s - lowpass(s))`.
/// 2026-09-30: avirt 닫힌 하이햇(mid 마이크, 스틱 끝 재즈 연주)이 어둡고 둔해서
/// 「칫칫」이 아니라 「띳띳」으로 들렸다 — 4kHz 위를 들어 올린다(재는 표:
/// `test/hat_bright_test.dart`). 열린 하이햇은 살짝만.
const Map<String, Map<String, double>> kDrumSetBright = {
  'avirt': {'hatClosed': 3.5, 'hatOpen': 0.8},
};
const double kDrumBrightCutHz = 3500.0;

double drumSetBright(String set, String piece) => kDrumSetBright[set]?[piece] ?? 0.0;

double drumSetTrim(String set, String piece) => kDrumSetTrim[set]?[piece] ?? 1.0;

/// 이 세트의 조각이 음정 이동(톰 피치)을 쓰는가.
double? drumRootFreq(String piece, String set) =>
    set == kDefaultDrumSet ? kDrumRootFreq[piece] : null;

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
Future<void> ensureDrumPieceLoaded(
  String piece, {
  String set = kDefaultDrumSet,
}) async {
  final key = drumBankKey(piece, set);
  if (kDrumSampleBanks.containsKey(key) || _loadingDrum.contains(key)) {
    return;
  }
  final rr = _kDrumRRCount[set]?[piece];
  if (rr == null) return; // 표본이 원래 없는 조각(림샷·박수·쉐이커·카우벨)
  _loadingDrum.add(key);
  try {
    final rootFreq = drumRootFreq(piece, set) ?? 1.0;
    final byVel = <int, List<SampleClip>>{1: [], 2: [], 3: []};
    for (final entry in const {'pp': 1, 'mf': 2, 'ff': 3}.entries) {
      for (var n = 1; n <= rr; n++) {
        final path = 'assets/samples/${set}_$piece/$piece.${entry.key}.$n.wav';
        final data = await rootBundle.load(path);
        byVel[entry.value]!.add(
          parseSampleWav(data.buffer.asUint8List(), rootFreq),
        );
      }
    }
    kDrumSampleBanks[key] = DrumSampleBank(byVel);
  } catch (_) {
    // 못 읽으면 이 조각만 합성으로 대신한다 — 다른 조각 로드엔 영향 없다.
  } finally {
    _loadingDrum.remove(key);
  }
}
