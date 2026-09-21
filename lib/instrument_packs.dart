// 악기 콘텐츠팩 — 「기본팩」과 「추가팩」을 코드로 나눈다 (2단계).
//
// 사용자 결정: 밴드 악기·오실레이터 악기는 **기본팩**(늘 들어있음), 실제
// 녹음(피아노·바이올린·트럼펫·첼로)은 **무료 추가팩**으로 분리한다. 지금
// 단계에서는 서버가 없다 — 그래서 추가팩도 물리적으로는 여전히 앱 안에 같이
// 들어있다(`assets/samples/`). 여기서 하는 일은 **구조만** 먼저 나누는 것:
//   - 어떤 악기가 어느 팩인지 코드 한 곳에 정리한다(고르는 화면·안내 문구가
//     나중에 이걸 그대로 쓸 수 있게).
//   - 표본팩 로딩은 이미 악기별로 갈라져 있다(`sampler.dart` 의
//     `ensureInstrumentLoaded`) — 나중에 `bundled: false` 로 바꾸고 그 함수
//     안의 `rootBundle.load` 를 네트워크 다운로드+캐시로 바꾸면, 부르는 쪽
//     (`synth.dart`)은 한 줄도 안 고쳐도 된다.
import 'instruments.dart';
import 'sampler.dart' show kAddonPackSampleKeys;

class InstrumentPack {
  /// 저장·설정에 남을 수 있는 키 — 바꾸지 말 것.
  final String id;

  /// 고르는 화면의 이름.
  final String label;

  /// 한 줄 설명.
  final String blurb;

  /// 무료인가(유료 추가팩은 나중 몫 — 지금은 전부 무료).
  final bool free;

  /// 지금 앱 설치 파일 안에 실제로 들어있는가. 지금은 추가팩도 `true`다
  /// (서버가 없어서) — 다운로드형으로 바뀌면 이 값이 `false` 로 바뀐다.
  final bool bundled;

  /// 이 팩이 담는 악기 voice 키들(`INSTRUMENTS`/`sampler.dart` 의 키).
  final List<String> instruments;

  const InstrumentPack({
    required this.id,
    required this.label,
    required this.blurb,
    required this.free,
    required this.bundled,
    required this.instruments,
  });
}

/// 표본(실제 녹음)이 있는 악기 중 **추가팩**(현악·관악)에 들어가는 것만.
/// `guitar`·`fingerbass` 도 표본이 있지만 밴드 악기라 기본팩에 남는다 —
/// `kAddonPackSampleKeys` 가 그 구분을 갖고 있다(`sampler.dart`).
final List<String> kAddonInstrumentKeys = kAddonPackSampleKeys.toList()
  ..sort();

/// 나머지 전부 — 「기본팩」(늘 들어있음). 오실레이터 악기뿐 아니라, 표본이
/// 있어도 밴드 악기라 분류된 것(`guitar`·`fingerbass`)도 여기 있다 —
/// **기본팩은 "합성만" 이 아니라 "늘 들어있음"이 기준**이다.
final List<String> kBaseInstrumentKeys =
    INSTRUMENTS.keys
        .where((k) => !kAddonPackSampleKeys.contains(k))
        .toList()
      ..sort();

List<InstrumentPack> get kInstrumentPacks => [
  InstrumentPack(
    id: 'base',
    label: '기본팩',
    blurb: '밴드 악기·신스 — 오실레이터로 소리 낸다. 늘 들어있다.',
    free: true,
    bundled: true,
    instruments: kBaseInstrumentKeys,
  ),
  InstrumentPack(
    id: 'sampled_strings_brass',
    label: '현악·관악 표본팩',
    blurb: '실제 녹음(피아노·바이올린·트럼펫·첼로). 무료 추가팩.',
    free: true,
    bundled: true, // 지금은 서버가 없어 앱과 같이 들어있다 — 나중에 false로.
    instruments: kAddonInstrumentKeys,
  ),
];

/// 이 악기가 속한 팩. 어디에도 없으면 null.
InstrumentPack? instrumentPackOf(String voice) {
  for (final p in kInstrumentPacks) {
    if (p.instruments.contains(voice)) return p;
  }
  return null;
}
