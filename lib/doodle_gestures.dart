// 두들플레이 제스처 규칙 (2026-09-29 (16)) — 소리 API(`audio_isolate.dart`)를 부르는 **손짓 판정**을
// 화면 밖으로 뗀 순수 함수들. 화면(`ui/doodle_play_view.dart`)은 손가락 위치·시간만 넘기고,
// 시험이 이 규칙을 시계·위젯 없이 직접 잰다.
//
//   · 순서 화면에서 고를 수 있는 악기 목록 (코드·베이스·드럼 킷)
//   · 808 붐(킥 홀드) · 오픈 하이햇 · 뮤트첩 · 스웰 · 롤 크레셴도 판정
//   · 코드 리듬 락(#9)
import 'drums.dart' show DRUM_KITS, DRUM_KIT_ORDER;
import 'instruments.dart' show VOICE_LABEL;
import 'tap_rec.dart' show TapHit;

// ── 1. 악기 고르기 ──

/// 코드 단계에서 고를 수 있는 음색 — 피아노/패드/스트링/오르간/브라스/기타.
const List<String> kDoodleChordVoices = [
  'piano',
  'pad',
  'strings',
  'organ',
  'brass',
  'guitar',
];

/// 베이스 단계에서 고를 수 있는 음색 — 핑거/jbass/신스.
const List<String> kDoodleBassVoices = ['fingerbass', 'jbass', 'bass'];

/// 드럼 단계에서 고를 수 있는 킷.
const List<String> kDoodleDrumKits = DRUM_KIT_ORDER;

/// 고르는 목록. 지금 값이 목록에 없으면(장르가 정해 준 'epiano' 등) **맨 앞에 끼운다** —
/// 안 그러면 지금 소리가 어느 칩에도 안 켜져 "무엇이 골라져 있나"가 안 보인다.
List<String> doodleChoicesWith(List<String> base, String current) =>
    base.contains(current) || current.isEmpty ? base : [current, ...base];

/// 화면에 보일 이름 — 음색표(`VOICE_LABEL`)·킷표(`DRUM_KITS`)에서.
String doodleVoiceLabel(String voice) => VOICE_LABEL[voice] ?? voice;
String doodleKitLabel(String kit) => DRUM_KITS[kit]?.label ?? kit;

// ── 2. 808 붐 ──

/// 킥 홀드 붐을 쓸 수 있는 킷인가. 표본 킷(어쿠스틱·록)은 붐이 합성 킥으로 **바뀌어** 나므로
/// (`drums.dart` 의 "표본을 못 늘이므로 합성 킥으로") 짧게 톡 친 킥의 소리가 통째로 달라진다 —
/// 그런 킷은 예전처럼 한 방만 친다. 전자음 킷(808·909·로파이)은 킥 위에 서브가 얹힐 뿐이다.
bool doodleBoomKit(String kit) => !(DRUM_KITS[kit]?.sampled ?? false);

/// 베이스 홀드에서 **이 시간 이상** 잡았을 때만 꼬리를 늘린다(초). 톡 친 스타카토는
/// 악기 원래 릴리스 그대로 — 안 그러면 `boomTailFor` 의 바닥(0.08s)이 짧게 끊어 버린다.
const double kBassBoomAfterSec = 0.25;

// ── 3. 오픈 하이햇 ──

/// 하이햇을 이만큼 **꾹** 누르고 있으면 오픈(ms). 롤 시작(`_kRollAfterMs`)과 같은 시각이다 —
/// 같은 「꾹」이 롤이 되느냐 오픈이 되느냐는 **세로 자리**로 가른다(아래).
const int kOpenHatAfterMs = 180;

/// 하이햇 세로 3구역의 경계(0=위, 1=아래). **위 = 16비트 · 가운데 = 8비트 · 아래 = 오픈.**
/// 톡 치는 건 어디든 닫힌 하이햇이고, 「꾹」(180ms)이 되면 손이 닿은 구역이 뜻을 정한다:
///  - 위(`< kHat16Zone`): 16분음표 롤(촘촘, 16비트)
///  - 가운데: 8분음표 롤(성긴, 8비트)
///  - 아래(`>= kOpenHatZone`): 열린 하이햇 한 번
/// (예전엔 8분 구역과 오픈 구역이 같은 자리(0.6 아래)라 처음부터 8비트를 못 골랐다 —
///  아래를 꾹 누르면 무조건 오픈이었다.)
const double kHat16Zone = 0.40;
const double kOpenHatZone = 0.72;

/// 구역 경계 목록 — `stickyBand` 에 그대로 넘긴다.
const List<double> kHatZoneEdges = [kHat16Zone, kOpenHatZone];

/// 하이햇 구역 번호. [kHatBand16] · [kHatBand8] · [kHatBandOpen].
const int kHatBand16 = 0, kHatBand8 = 1, kHatBandOpen = 2;

/// 롤의 굵기(16분 칸 단위) — 16비트는 매 칸(1), 8비트는 두 칸마다(2).
int hatRollUnit(int band) => band == kHatBand16 ? 1 : 2;

/// 하이햇을 [frac](세로 0~1)에서 꾹 눌렀을 때 오픈인가.
bool hatHoldOpens(double frac) => frac >= kOpenHatZone;

/// [frac] 의 하이햇 구역. [prev] 가 있으면 경계에서 [slop] 안의 흔들림은 직전 구역에 머문다.
int hatBandSticky(double frac, {int? prev, double slop = 0}) =>
    stickyBand(frac, kHatZoneEdges, prev: prev, slop: slop);

// ── 4. 스웰 ──

/// 패드/스트링 계열 — 스웰(볼륨 차오름)이 뜻 있는 음색.
const Set<String> kSwellVoices = {'pad', 'analogpad', 'strings', 'jpstrings'};
bool isSwellVoice(String voice) => kSwellVoices.contains(voice);

/// 스웰이 실리는 버스 이름 — 코드 트랙.
const String kSwellBus = 'chord';

/// 화면 **아래 이 비율 이하**(세로 0~1 에서 이 값 이상)에서 닿아야 「아래→위로 긋는」 스웰이다.
const double kSwellZone = 0.66;

/// 스웰이 시작하는 크기(0~1). 소리 크기는 level² 라 0.45 면 −14dB 쯤 — 톡 쳐도 안 들리지는 않는다.
const double kSwellStart = 0.45;

/// 끝까지 차오르려면 위로 밀어야 하는 거리(화면 높이 비율).
const double kSwellTravel = 0.45;

/// 스웰을 걸 자리인가 — [frac] 은 닿은 세로 위치(0=위, 1=아래).
bool swellStartsAt(double frac) => frac >= kSwellZone;

/// 손가락이 [downY] 에서 [y] 로 올라온 만큼의 스웰 크기(0~1). 위로 갈수록 커지고 내려가도
/// [kSwellStart] 밑으로는 안 간다. 손이 멈추면 값도 그대로다(호출부가 안 부르면 유지).
///
/// [deadPx] — 처음 이만큼(픽셀)은 **무시한다**(2026-09-30). 엄지는 톡 칠 때도 살짝 굴러서
/// 몇 픽셀 위로 흐르는데, 그게 스웰을 바로 밀어 올리면 "안 그었는데 볼륨이 튄다". 데드존을 넘은
/// 만큼부터 세고, 끝(가득 참)은 그대로 [kSwellTravel] 이다.
double swellLevel(double downY, double y, double height, {double deadPx = 0}) {
  if (height <= 0) return 1;
  final travel = height * kSwellTravel;
  final up = ((downY - y - deadPx) / travel).clamp(0.0, 1.0);
  return kSwellStart + (1 - kSwellStart) * up;
}

// ── 5. 뮤트첩 (기타) ──

bool isMuteVoice(String voice) => voice == 'guitar' || voice == 'nylon';

/// 뮤트 스트럼으로 칠 만큼 짧은가 — 스타카토 기준(`_kStaccatoMs`)과 같다. 손이 안 움직였을 때만.
bool isMuteStrum({required String voice, required int heldMs, required bool moved}) =>
    isMuteVoice(voice) && !moved && heldMs < kMuteMs;

const int kMuteMs = 90;

/// 뮤트 순간 꼬리를 자르는 길이(초) — 손바닥으로 줄을 덮은 「척」.
const double kMuteTailSec = 0.025;

/// 뮤트로 적힌 칸의 세기(여리게).
const int kMuteVel = 1;

// ── 6. 롤 크레셴도 ──

/// 롤 도중 손이 처음 자리에서 **오른쪽으로 민 만큼**(폭의 1/4 마다 한 단계) 세기가 오른다.
/// [dx] 는 (지금 X − 처음 X). 왼쪽으로 밀면 0 (기본 세기 밑으로는 안 내린다).
int rollBump(double dx, double width) {
  if (width <= 0 || dx <= 0) return 0;
  return (dx / (width / 4)).floor().clamp(0, 2);
}

/// 롤 한 번의 세기 — 기본 [base](1~3)에 밀어 준 만큼을 얹는다.
int rollVel(int base, double dx, double width) =>
    (base + rollBump(dx, width)).clamp(1, 3);

// ── 7. 코드 리듬 락 (#9) ──

/// 코드 단계에서 **마지막으로 친 마디의 타격 리듬**을 그 뒤 **안 친 마디**에 자동으로 반복한다.
///  · 친 마디는 친 대로(덮지 않는다).
///  · 첫 마디를 안 쳤으면 그 앞은 반복할 리듬이 없다 — 처음 친 마디 **뒤**부터만 채운다.
///  · 마디를 건너뛰며 쳐도 매 빈 마디는 **바로 앞까지 마지막으로 친 마디**를 따른다.
/// [hits] 의 step 은 판 안 칸 번호, 한 마디는 [spb] 칸, 판은 [bars] 마디다.
///
/// 돌려주는 것: (원래 + 새로 채운 타격, 새 칸 → 베낀 원래 칸). 두 번째는 톡·뮤트 같은
/// 칸별 손짓을 같이 옮기려고 호출부가 쓴다.
(List<TapHit>, Map<int, int>) lockChordRhythm(
  List<TapHit> hits, {
  required int spb,
  required int bars,
}) {
  if (spb <= 0 || bars <= 0 || hits.isEmpty) return (List.of(hits), const {});
  final byBar = <int, List<TapHit>>{};
  for (final h in hits) {
    if (h.step < 0 || h.step >= spb * bars) continue;
    byBar.putIfAbsent(h.step ~/ spb, () => []).add(h);
  }
  final out = List<TapHit>.of(hits);
  final from = <int, int>{};
  List<TapHit>? last;
  for (var b = 0; b < bars; b++) {
    final mine = byBar[b];
    if (mine != null && mine.isNotEmpty) {
      last = mine;
      continue;
    }
    if (last == null) continue;
    final srcBar = last.first.step ~/ spb;
    for (final h in last) {
      final st = b * spb + (h.step - srcBar * spb);
      out.add(TapHit(h.pad, st, h.len));
      from[st] = h.step;
    }
  }
  out.sort((a, b) => a.step.compareTo(b.step));
  return (out, from);
}

// ─────────────────────────────────────────────────────────────────────────────
// 2026-09-30 — 연주감 · 한손(엄지 하나) 오탐 줄이기
//
// 아래 상수는 전부 **실기기에서 만져 보며 맞추는 손잡이**다. 값을 바꿔도 화면·판정이 같은
// 상수를 보므로 서로 어긋나지 않는다.
// ─────────────────────────────────────────────────────────────────────────────

// ── 8. 손맛(햅틱) — 악기 × 세기 ──

/// 손끝 진동의 종류. `HapticFeedback` 의 네 가지(heavy·medium·light·selection)에 1:1 로 붙는다.
enum DoodleHaptic { heavy, medium, light, tick }

/// 악기마다 **바닥 무게**. 킥은 묵직, 스네어·코드·베이스는 중간, 하이햇은 가볍게.
const Map<String, DoodleHaptic> kHapticBase = {
  'kick': DoodleHaptic.heavy,
  'snare': DoodleHaptic.medium,
  'chord': DoodleHaptic.medium,
  'bass': DoodleHaptic.medium,
  'hat': DoodleHaptic.light,
};

/// 이 악기가 낼 수 있는 **가장 센 진동** — 하이햇은 16분으로 잘게 칠 일이 많아 세게 쳐도
/// 가볍게(강한 진동이 연달아 오면 손이 아프다). 나머지는 제한 없음.
const Map<String, DoodleHaptic> kHapticCap = {'hat': DoodleHaptic.light};

/// [instrument] ('kick' · 'snare' · 'hat' · 'chord' · 'bass') 를 세기 [vel](1~3)로 쳤을 때의 진동.
///
///  · 바닥 무게에서 여리게(1)는 한 단계 **내리고**, 세게(3)는 한 단계 **올린다**(상한 안에서).
///  · 킥: 고스트(1)=medium, 보통·세게=heavy.  스네어/베이스: 1=light · 2=medium · 3=heavy.
///  · 하이햇: 1=tick(가장 여린 똑) · 2·3=light.  코드: 세기가 늘 2 라 medium.
/// 친 소리의 무게와 손끝의 무게가 같은 방향으로 가야 "쳤다"가 산다.
DoodleHaptic doodleHaptic(String instrument, int vel) {
  final base = kHapticBase[instrument] ?? DoodleHaptic.medium;
  final shift = vel <= 1 ? -1 : (vel >= 3 ? 1 : 0);
  // 세기 단계로 셈한다: tick=0 · light=1 · medium=2 · heavy=3 (enum 순서의 거꾸로).
  var i = 3 - base.index;
  i = (i + shift).clamp(0, 3);
  final cap = kHapticCap[instrument];
  if (cap != null && i > 3 - cap.index) i = 3 - cap.index;
  return DoodleHaptic.values[3 - i];
}

/// 진동을 소리보다 **이만큼(ms) 늦춰** 낸다. 소리는 렌더 버퍼(≈32ms)를 지나 귀에 닿는데
/// 진동은 즉시 울려서 손이 귀보다 앞설 수 있다. 0 이면 즉시. 실기기에서 「소리보다 먼저 온다」
/// 싶으면 10~25 로 올려 본다(타이머 지터가 생기므로 필요할 때만).
const int kHapticDelayMs = 0;

// ── 9. 방향·세기 판정 — 데드존 · 히스테리시스 ──

/// 구역 경계에서 이만큼(픽셀) 더 나가야 **넘어간 것**으로 본다(직전 구역이 있을 때).
/// 엄지 살은 15~20px 넘게 닿아서 「경계에 걸친 탭」은 실제로 자주 흔들린다.
const double kBandSlopPx = 14;

/// 직전 탭의 구역을 **기억해 주는 시간**(ms). 이보다 오래 쉬었다 치면 새로 시작 — 의도한 위치로 본다.
const int kStickyMs = 700;

/// 이만큼(픽셀) 안에서 끝난 손짓은 **안 움직인 것**(톡)이다. 예전엔 8px 이었는데 엄지의 살짝 구름에도
/// 「움직였다」로 읽혀 스타카토·뮤트가 조용히 빠졌다(Flutter 의 터치 슬롭 18px 보다 작게).
const double kTapSlopPx = 14;

/// 코드 색(위 = 화려, 아래 = 담백)의 세로 경계(0=위, 1=아래). 정중앙(0.5)이던 것을 **살짝 아래로**
/// 내렸다 — 엄지는 화면 아래 2/3 에서 편하고 위쪽 끝은 손을 뻗어야 한다. 그래서 「위」 구역이
/// 엄지가 닿는 가운데까지 내려오게 넓혔다. 화면의 가운데 선도 이 값에 그린다.
const double kChordColorSplit = 0.55;

/// 여러 구역(밴드)으로 나뉜 값 [v] 가 어느 구역인가 — **히스테리시스**(되돌림) 포함.
///
/// [edges] 는 오름차순 경계들이라 구역은 0..edges.length. [prev] (직전 구역)가 있고 [v] 가 그
/// 이웃 구역에 막 넘어왔지만 **경계에서 [slop] 안**이면 직전 구역에 머문다 — 경계에 걸친 손이
/// 살짝 흔들려도 결과가 튀지 않는다. 두 구역 이상 건넜으면 (의도한 이동이므로) 그대로 넘어간다.
int stickyBand(double v, List<double> edges, {int? prev, double slop = 0}) {
  var raw = 0;
  for (final e in edges) {
    if (v >= e) raw++;
  }
  if (prev == null || prev == raw || slop <= 0) return raw;
  if (prev < 0 || prev > edges.length) return raw;
  if (raw == prev + 1 && v < edges[prev] + slop) return prev; // 위 구역으로 막 넘어옴
  if (raw == prev - 1 && v >= edges[prev - 1] - slop) return prev; // 아래 구역으로 막 넘어옴
  return raw;
}

/// 「직전 탭의 구역」을 시간 제한을 두고 들고 있는 판정기. 시계는 호출부가 [nowMs] 로 준다(시험 쉬움).
class StickyBand {
  final List<double> edges;
  StickyBand(this.edges);

  int? _band;
  int _atMs = -1 << 40;

  /// [v] 의 구역을 읽고 **기억한다**. [nowMs] − 직전 시각이 [kStickyMs] 를 넘으면 직전은 잊는다.
  int read(double v, int nowMs, {double slop = 0}) {
    final fresh = _band != null && nowMs - _atMs <= kStickyMs;
    final b = stickyBand(v, edges, prev: fresh ? _band : null, slop: slop);
    _band = b;
    _atMs = nowMs;
    return b;
  }

  /// 기억하지 않고 지금 판정이 어떻게 될지만 본다.
  int peek(double v, int nowMs, {double slop = 0}) {
    final fresh = _band != null && nowMs - _atMs <= kStickyMs;
    return stickyBand(v, edges, prev: fresh ? _band : null, slop: slop);
  }

  void reset() => _band = null;
}

/// 세로 위치 [frac] 을 코드 **색**으로. 위(화려)=1, 아래(담백)=0. [prev] 는 직전 색.
/// (`doodleColorOfY` 는 정중앙 0.5 고정 — 화면은 이 함수와 [kChordColorSplit] 를 쓴다.)
int chordColorOfBand(int band) => band == 0 ? 1 : 0;

/// 가로 3구역(0=왼, 1=가운데, 2=오른) → 진행 방향 −1 · 0 · +1.
int chordDirOfBand(int band) => band - 1;

/// 하이햇을 꾹 눌러 오픈이 되는 자리인가 — [hatHoldOpens] 에 **처음 닿은 자리**의 기억을 더했다.
/// 처음 닿은 곳이 위쪽 구역(롤)이었으면 경계를 [slop](0~1, 화면 높이 비율) 더 넘어야 오픈으로 바뀌고,
/// 처음이 아래쪽(오픈)이었으면 경계를 [slop] 더 올라가야 롤로 바뀐다.
bool hatHoldOpensSticky({
  required double downFrac,
  required double frac,
  double slop = 0,
}) =>
    hatBandSticky(
      frac,
      prev: hatBandSticky(downFrac),
      slop: slop,
    ) ==
    kHatBandOpen;

/// 스웰이 움직이기 시작하기 전 **무시하는 처음 거리**(픽셀) — 톡 칠 때 엄지가 구르는 만큼은 그은 게 아니다.
const double kSwellDeadPx = 10;

/// 롤 크레셴도 단계(0~2) — [rollBump] 에 되돌림을 더했다. 폭의 1/4 마다 한 단계인 경계에서
/// 손이 흔들려도 세기가 오락가락하지 않는다. [prev] 는 이 롤에서 직전에 쓴 단계.
int rollBumpSticky(double dx, double width, int prev, {double slop = 0}) {
  if (width <= 0) return 0;
  final q = width / 4;
  return stickyBand(dx, [q, 2 * q], prev: prev, slop: slop);
}

/// 롤 한 번의 세기 — 기본 [base](1~3)에 단계 [bump] 를 얹는다.
int rollVelOfBump(int base, int bump) => (base + bump).clamp(1, 3);

/// 베이스 사다리에서 미끄러뜨릴 때 칸을 넘기려면 경계에서 더 나가야 하는 거리(픽셀).
/// 톡 칠 때 엄지가 굴러 옆 칸으로 새 「덤 음」이 적히던 것을 막는다.
const double kSlideSlopPx = 14;
