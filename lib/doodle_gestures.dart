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

/// 이 세로 위치(0=위, 1=아래)보다 **아래**를 꾹 누르면 오픈 하이햇, 위쪽이면 16분 롤.
/// (하이햇 롤 밀도 경계 `_kHatSparseFrac` 와 같은 값 — 아래 구역이 원래 「성긴」 자리였다.)
const double kOpenHatZone = 0.6;

/// 하이햇을 [frac](세로 0~1)에서 꾹 눌렀을 때 오픈인가.
bool hatHoldOpens(double frac) => frac >= kOpenHatZone;

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
double swellLevel(double downY, double y, double height) {
  if (height <= 0) return 1;
  final up = ((downY - y) / (height * kSwellTravel)).clamp(0.0, 1.0);
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
