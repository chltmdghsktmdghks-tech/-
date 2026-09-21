// 표본(샘플) 재생 — 악기 품질 1단계 (5단계 47/N 이후), 2단계 콘텐츠팩 분리.
//
// 여태 모든 악기는 `synth.dart` 의 합성(오실레이터+필터+엔벨로프)으로 흉내 냈다.
// 여기서는 **실제 녹음**을 트는 길을 하나 더 낸다 — 신스 경로와는 완전히 갈라
// 둔다. `kSampleBanks` 에 그 악기가 있으면 `SynthNote.noteOn` 이 여기로 바로
// 빠지고, 오실레이터·필터·엔벨로프를 하나도 안 만든다(합성 쪼가리와 안 섞인다).
//
// ── 표본을 **자동으로 안 부른다** ──
// `rootBundle.load` 는 Flutter 엔진이 붙어 있어야 한다. 이 앱의 시험은 대부분
// `SynthNote()` 를 맨 Dart 테스트에서 직접 만든다(위젯을 안 띄운다) — 거기서
// 표본을 자동으로 불러오려 하면 시험이 깨지거나 멈춘다.
//
// ── 왜 **악기별로** 로드하는가 (2단계) ──
// 예전엔 오디오 아이솔레이트가 시작할 때 네 악기 표본을 통째로 다 읽었다.
// 이제 표본 악기는 「무료 추가팩」(`instrument_packs.dart`)으로 따로 묶인다 —
// 곡 하나가 실제로 쓰는 악기는 보통 한둘뿐인데, 나머지 표본까지 미리 다 읽는 건
// 낭비다. 그래서 `ensureInstrumentLoaded(voice)` 는 **그 악기 하나만** 읽고,
// `SynthNote.noteOn` 이 처음 그 악기를 만났을 때 스스로 트리거한다(아래).
// 로드가 끝나기 전에 친 음은 지금처럼 합성으로 대신 나가고(끊김 없음), 로드가
// 끝나면 다음 음부터 표본으로 바뀐다 — **이 전환은 새 코드가 아니라 원래도
// 있던 안전장치**(표본 로드가 하나든 넷이든 똑같이 통한다).
//
// 나중에 진짜 다운로드형 추가팩으로 바꿀 때도 **호출하는 쪽(synth.dart)은 그대로
// 두고 이 파일의 로드 로직만 (rootBundle → 네트워크/캐시 파일) 로 바꾸면 된다.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// 표본 하나 — 한 마디음(root) · 한 세기의 PCM(모노, 16비트).
class SampleClip {
  final Int16List pcm;
  final int sampleRate;
  final double rootFreq;
  const SampleClip(this.pcm, this.sampleRate, this.rootFreq);
}

/// 악기 하나가 든 표본 — 세기(1~3) 별로 갈리고, 세기 안에서 root 주파수 오름차순.
class SampleBank {
  final Map<int, List<SampleClip>> byVel;
  const SampleBank(this.byVel);

  /// [vel] 층에서 [freq] 에 **제일 가까운** 표본 — 반음 로그 스케일로 잰다
  /// (Hz 차이로 재면 저음에서 어긋난다 — 100Hz 차이가 저음에선 반음도 안 되지만
  /// 고음에선 몇 옥타브다).
  SampleClip pick(int vel, double freq) {
    final list = byVel[vel] ?? byVel[2] ?? byVel.values.first;
    var best = list.first;
    var bestDiff = (freq / best.rootFreq).abs();
    for (final c in list) {
      final ratio = freq / c.rootFreq;
      final d = ratio > 1 ? ratio : 1 / ratio; // 로그 거리와 같은 순서
      if (d < bestDiff) {
        bestDiff = d;
        best = c;
      }
    }
    return best;
  }
}

/// 채워지면 그 악기는 표본으로 운다. 비어 있으면(기본) 합성으로 운다.
final Map<String, SampleBank> kSampleBanks = {};

/// 악기 → (표본 이름 접두, {세기: root 주파수}). 새 표본 악기를 더할 땐 여기와
/// `assets/samples/<접두 소문자>/` 폴더, `pubspec.yaml` 세 곳을 같이 고친다.
const Map<String, (String, Map<String, double>)> _kSampleSets = {
  // Salamander Grand Piano V3(퍼블릭도메인, Yamaha C5, 세기 16단계 중 3벌
  // 골라 옴)로 교체 — 예전엔 옥타브마다 한 자리(C만)라 반음 다섯 개를
  // 피치 시프트로 메꿨는데, 단3도(장3화음 자리)마다 한 자리씩 둬서 어느
  // 음을 눌러도 실제 녹음에서 최대 반음 1.5개 안으로 붙게 했다.
  'piano': (
    'Piano',
    {
      'C2': 65.41,
      'Ds2': 77.78,
      'Fs2': 92.50,
      'A2': 110.00,
      'C3': 130.81,
      'Ds3': 155.56,
      'Fs3': 185.00,
      'A3': 220.00,
      'C4': 261.63,
      'Ds4': 311.13,
      'Fs4': 369.99,
      'A4': 440.00,
      'C5': 523.25,
    },
  ),
  // VSCO2 Community Edition(CC0, sgossner)로 교체 — 예전 University of
  // Iowa 표본은 pp·mf·ff 세 파일이 다 같은 녹음(세기 한 벌뿐)이었다.
  // 여기서는 실제로 세게·여리게 두 벌 녹음(Arco Vib f/p)을 받아 pp=여리게,
  // mf·ff=세게로 나눴다 — 완전히 다른 세 벌은 아니지만 최소한 세기가
  // 실제로 갈린다. 자리도 8자리 → 14자리(A3~C7)로 넓혔다.
  'violin': (
    'Violin',
    {
      'A3': 220.00,
      'C4': 261.63,
      'E4': 329.63,
      'G4': 392.00,
      'A4': 440.00,
      'C5': 523.25,
      'E5': 659.26,
      'G5': 783.99,
      'A5': 880.00,
      'C6': 1046.50,
      'E6': 1318.51,
      'G6': 1567.98,
      'A6': 1760.00,
      'C7': 2093.00,
    },
  ),
  // VSCO2 CE 트럼펫(Sustain, v1/v3 두 세기 → pp/mf·ff)로 교체.
  'trumpet': (
    'Trumpet',
    {
      'F2': 87.31,
      'G3': 196.00,
      'As3': 233.08,
      'C3': 130.81,
      'Ds3': 155.56,
      'D4': 293.66,
      'F4': 349.23,
      'A2': 110.00,
      'A4': 440.00,
      'C5': 523.25,
    },
  ),
  // VSCO2 CE 첼로 섹션(Sustain Vib, v1/v3 두 세기 → pp/mf·ff)로 교체 —
  // 독주 첼로 CC0 소스가 없어 섹션(여럿이 함께 켠) 녹음을 썼다. 독주보다
  // 살짝 더 풍성하게 들리지만 음정·세기는 그대로 melodic 하게 쓸 수 있다.
  // 자리도 C2~C4 한 옥타장 반뿐이던 것을 C1~D4로 넓혔다.
  'cello': (
    'Cello',
    {
      'C1': 32.70,
      'D2': 73.42,
      'E1': 41.20,
      'F2': 87.31,
      'G1': 49.00,
      'A2': 110.00,
      'B1': 61.74,
      'C3': 130.81,
      'D4': 293.66,
      'E3': 164.81,
      'F4': 349.23,
      'G3': 196.00,
      'B3': 246.94,
    },
  ),
  // ── 여기부터 「기본팩」 표본(밴드 악기) — `instrument_packs.dart` 의
  // `kBaseSampleInstrumentKeys` 에 들어간다. FreePats(CC0) — 세기 두 벌
  // (pp·mf = soft 녹음, ff = 세게 친 녹음)이라 다른 표본 악기보다 다이내믹이
  // 실제로 갈린다. `assets/samples/guitar/SOURCE.md` 참고.
  'guitar': (
    'Guitar',
    {
      'C2': 65.41,
      'E2': 82.41,
      'F2': 87.31,
      'A2': 110.00,
      'C3': 130.81,
      'D3': 146.83,
      'E3': 164.81,
      'G3': 196.00,
      'B3': 246.94,
      'C#4': 277.18,
      'E4': 329.63,
      'G4': 392.00,
      'B4': 493.88,
      'D5': 587.33,
      'F5': 698.46,
      'G#5': 830.61,
      'A#5': 932.33,
      'C#6': 1108.73,
    },
  ),
  // Karoryfer "Fashionbass"(CC0, sfzinstruments)로 교체 — 예전 FreePats
  // "Finger Bass YR"는 세기 한 벌뿐이라 pp·mf·ff 세 파일이 다 같은
  // 녹음이었다(옥타브는 E1~D#2 반음 간격이라 그 안에서는 피치 시프트가
  // 없었지만, 다이내믹이 가짜였다). 여기서는 **진짜 pp/mf/ff 세 벌**
  // 녹음이 있어서 다른 표본 악기들과 달리 이번엔 세기가 정말 셋 다
  // 다르다. 자리는 F#0~A4 19군데(단3도 간격)로 넓어졌다 — 한 옥타브
  // 안(E1~D#2)보다 자리 수는 줄었지만 피치 시프트 폭은 최대 반음 1.5개로
  // 여전히 좁다(다른 악기들과 같은 기준). `assets/samples/fingerbass/
  // SOURCE.md` 참고.
  'fingerbass': (
    'FingerBass',
    {
      'Fs0': 23.12,
      'A0': 27.50,
      'C1': 32.70,
      'D1': 36.71,
      'F1': 43.65,
      'Gs1': 51.91,
      'B1': 61.74,
      'D2': 73.42,
      'F2': 87.31,
      'Gs2': 103.83,
      'B2': 123.47,
      'D3': 146.83,
      'F3': 174.61,
      'Gs3': 207.65,
      'B3': 246.94,
      'D4': 293.66,
      'F4': 349.23,
      'Gs4': 415.30,
      'A4': 440.00,
    },
  ),
  // VSCO2 Community Edition(CC0, sgossner)로 교체 — 예전 University of
  // Iowa 표본은 세기 한 벌(ff)뿐이라 pp·mf·ff 세 파일이 다 같은 녹음이었다.
  // 여기서는 v1/v3 두 벌 녹음이 있는 자리(6곳)는 실제로 여리게·세게를
  // 나눴고, 한 벌뿐인 자리(8곳)는 예전처럼 세 파일이 같다. 자리도
  // 9군데(단3도 간격, C1~C3)에서 14군데(대략 반음~장2도 간격, E0~B2)로
  // 넓혀서 피치 시프트 폭을 줄이고 저음역을 더 채웠다.
  // (`assets/samples/upright/SOURCE.md` 참고. `sax`는 아직 University of
  // Iowa 세기 한 벌 표본 그대로다.)
  'upright': (
    'Upright',
    {
      'E0': 20.60,
      'Fs0': 23.12,
      'G0': 24.50,
      'As0': 29.14,
      'C1': 32.70,
      'D1': 36.71,
      'E1': 41.20,
      'Fs1': 46.25,
      'Gs1': 51.91,
      'A1': 55.00,
      'Cs2': 69.30,
      'E2': 82.41,
      'Gs2': 103.83,
      'B2': 123.47,
    },
  ),
  // FreePats(CC0) "Tenor Saxophone" — Versilian Community Sample Library
  // 소스. 예전(University of Iowa, 알토 색소폰) 표본은 비브라토 세기
  // 한 벌뿐이라 pp·mf·ff 세 파일이 다 같은 녹음이었다. 여기서는 v2/v3
  // 두 벌 녹음이 있는 자리 5곳(C3·C4·E3·G#2·G#3)은 pp·mf=v2(여리게),
  // ff=v3(세게)로 나눴다. 나머지 8곳은 v3 한 벌뿐이라 예전처럼 세
  // 파일이 같다. 자리도 9군데(단3도 간격, Db3~Db5)에서 13군데(장3도
  // 간격, E2~E6)로 넓혔다. 테너라 알토보다 한 옥타브 가까이 낮지만,
  // `sampler.dart` 는 어차피 피치 시프트로 음 높이를 맞추므로 재즈·
  // 팝의 서브 멜로디 용도로는 문제없다.
  'sax': (
    'Sax',
    {
      'E2': 82.41,
      'Gs2': 103.83,
      'C3': 130.81,
      'E3': 164.81,
      'Gs3': 207.65,
      'C4': 261.63,
      'E4': 329.63,
      'Gs4': 415.30,
      'C5': 523.25,
      'E5': 659.25,
      'Gs5': 830.61,
      'C6': 1046.50,
      'E6': 1318.51,
    },
  ),
  // FreePats(CC0) "FM Piano 1" — 진짜 DX7(1980년대 FM 신스) 의 "E. Piano 1"
  // 패치를 그대로 재현한 표본(합성기 자체가 아니라 그 출력을 녹음한 것).
  // 재즈·디스코·R&B 세 장르가 `epiano` 를 쓰는데 지금까지 합성이었다.
  // **세기가 진짜 세 벌**이다(v60/v80/v100 → pp/mf/ff) — 다른 Iowa 표본
  // 악기들과 달리 다이내믹이 실제로 갈린다.
  'epiano': (
    'EPiano',
    {
      'F#1': 46.25,
      'C2': 65.41,
      'F#2': 92.50,
      'C3': 130.81,
      'F#3': 185.00,
      'C4': 261.63,
      'F#4': 369.99,
      'C5': 523.25,
      'F#5': 739.99,
      'C6': 1046.50,
      'F#6': 1479.98,
      'C7': 2093.00,
    },
  ),
};
const Map<String, int> _kVelName = {'pp': 1, 'mf': 2, 'ff': 3};

/// 악기별 고정 스테레오 위치(-1 왼쪽 ~ 0 가운데 ~ 1 오른쪽). 표본은 지금
/// 원본이 모노라 좌우가 완전히 같은 소리였다 — 방 안에 서 있는 느낌을 조금
/// 주려고 실내악 자리처럼 갈라 둔다(첼로·바이올린은 양옆, 피아노·트럼펫은
/// 가운데 쪽). 라운드로빈처럼 원본이 더 필요한 개선이 아니라, 지금 있는
/// 표본 그대로 값싸게 되는 것부터 한다.
const Map<String, double> kSamplePan = {
  'piano': 0.0,
  'violin': 0.35,
  'trumpet': -0.15,
  'cello': -0.4,
  'guitar': 0.2,
  'fingerbass': 0.0, // 베이스는 가운데 — 좌우로 치우치면 저음 무게감이 갈린다
  'upright': 0.0, // 마찬가지로 베이스 — 가운데
  'sax': -0.25,
  'epiano': 0.1,
};

/// 표본이 있는 악기 키 전체(기본팩+추가팩 다 포함) — 로딩 로직이 "표본이
/// 원래 없는 악기"와 구분하려고 쓴다.
Set<String> get kSampleInstrumentKeys => _kSampleSets.keys.toSet();

/// 표본 중에서 **추가팩**(현악·관악, 무료지만 밴드 악기가 아님)에 들어가는
/// 것만. 나머지 표본(`guitar`·`fingerbass`)은 밴드 악기라 「기본팩」에 남는다
/// — `instrument_packs.dart` 가 이 목록으로 기본팩/추가팩을 가른다.
const Set<String> kAddonPackSampleKeys = {
  'piano',
  'violin',
  'trumpet',
  'cello',
  'upright',
  'sax',
  'epiano',
};

/// 지금 로드 중인 악기 — 같은 악기를 여러 음이 동시에 처음 쳐도 한 번만 읽는다.
final Set<String> _loading = {};

/// [voice] 표본 **하나만** 읽는다. 이미 읽었거나(`kSampleBanks` 에 있음) 읽는
/// 중이면 아무 일도 안 한다(중복 호출 안전). 표본 악기가 아니면(합성 전용
/// 「기본팩」 악기) 즉시 반환한다 — 없는 폴더를 찾다가 예외를 만들지 않는다.
Future<void> ensureInstrumentLoaded(String voice) async {
  if (kSampleBanks.containsKey(voice) || _loading.contains(voice)) return;
  final set = _kSampleSets[voice];
  if (set == null) return; // 합성 전용 악기 — 표본이 원래 없다
  _loading.add(voice);
  try {
    final (prefix, roots) = set;
    final byVel = <int, List<SampleClip>>{1: [], 2: [], 3: []};
    for (final root in roots.entries) {
      for (final vn in _kVelName.entries) {
        final path = 'assets/samples/$voice/$prefix.${vn.key}.${root.key}.wav';
        final data = await rootBundle.load(path);
        final clip = _parseWav(data.buffer.asUint8List(), root.value);
        byVel[vn.value]!.add(clip);
      }
    }
    for (final l in byVel.values) {
      l.sort((a, b) => a.rootFreq.compareTo(b.rootFreq));
    }
    kSampleBanks[voice] = SampleBank(byVel);
  } catch (_) {
    // 표본을 못 읽으면(자산이 안 딸려 있는 빌드 등) **합성으로 대신한다** —
    // 이 악기 하나 못 찾았다고 무음이 되면 그게 더 나쁜 고장이다. 다른 악기
    // 로드에는 영향이 없다(악기별로 갈라져 있어서).
  } finally {
    _loading.remove(voice);
  }
}

/// 표본 악기 전체를 한꺼번에 읽는다 — **시험 편의용**(`sampler_check_test.dart`
/// 의 `setUpAll` 이 네 악기를 다 확인해야 해서). 실제 앱은 이걸 안 쓴다 —
/// `synth.dart` 가 악기별로 [ensureInstrumentLoaded] 를 부른다.
Future<void> ensureSamplesLoaded() async {
  for (final voice in _kSampleSets.keys) {
    await ensureInstrumentLoaded(voice);
  }
}

/// 드럼 표본(`drum_sampler.dart`)도 같은 WAV 파서를 쓴다 — 형식이 완전히
/// 같은데 (모노 16비트) 또 만들 이유가 없다.
SampleClip parseSampleWav(Uint8List bytes, double rootFreq) =>
    _parseWav(bytes, rootFreq);

/// 표준 PCM WAV(모노 16비트)만 읽는다 — `tool/prep_samples.dart` 가 이 형식으로
/// 미리 다듬어 둔다(원본은 스테레오·44.1kHz·36초짜리라 그대로 못 쓴다).
SampleClip _parseWav(Uint8List bytes, double rootFreq) {
  final bd = ByteData.sublistView(bytes);
  var pos = 12;
  int sampleRate = 0, bitsPerSample = 0, channels = 0;
  Uint8List? data;
  while (pos < bytes.length - 8) {
    final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
    final size = bd.getUint32(pos + 4, Endian.little);
    final body = pos + 8;
    if (id == 'fmt ') {
      channels = bd.getUint16(body + 2, Endian.little);
      sampleRate = bd.getUint32(body + 4, Endian.little);
      bitsPerSample = bd.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      data = bytes.sublist(body, body + size);
    }
    pos = body + size + (size.isOdd ? 1 : 0);
  }
  if (data == null || sampleRate == 0 || channels != 1 || bitsPerSample != 16) {
    throw StateError('예상과 다른 WAV 형식(모노 16비트여야 함)');
  }
  return SampleClip(Int16List.sublistView(data), sampleRate, rootFreq);
}
