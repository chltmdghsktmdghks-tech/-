// Doodle Play — 장르를 고르면 드럼(킥→스네어→하이햇)을 한 악기씩 두드려서
// 쌓아 올리는 새 제작 입력 방식(사용자 지시서, 2026-09-17).
//
// ── 기존 것을 그대로 쓴 것들 ──
// 이 화면은 **새 오디오 엔진·새 녹음·새 데이터 모델을 만들지 않는다.**
//   · 소리 내기            → `AudioClient.drumOn` (라이브 화면과 같은 경로)
//   · 박 세기(미리 세기 4→REC→끝) → `TapClock` (`tap_rec.dart`, 두드려 넣기 화면이
//     이미 쓰던 것 그대로)
//   · 손끝 위치 → 칸 변환   → `TapRecorder` (역시 두드려 넣기 화면과 같은 것)
//   · Clip 만들기           → `DrumOps` + `Project.putUserPattern`/`setClip`
//     (편집기의 "두드려 넣기"가 쓰는 것과 완전히 같은 파이프라인)
//   · 다음 화면 연결        → `EditorView`를 그대로 연다("다듬기")
//
// 새로 만든 것은 **한 화면 = 한 악기**로 채우는 이 위젯 자체와 장르별 순서 표
// (`kDoodleStages`)뿐이다. 순서는 더는 강제가 아니다 — 진행 표시(`_progress`)를
// 눌러 아무 단계로나 건너뛸 수 있다(사용자 지시, 2026-09-24: "킥에서 바로
// 하이햇·코드로 갈 수 있게"). `kDoodleStages`는 이제 **기본 순서**일 뿐이다.
//
// ── 범위 ──
// 1차: 드럼(킥+스네어+하이햇). 2차(이번): 베이스 추가 — TAP하면 그 자리
// 코드의 뿌리음이 난다(지시서 28번 "TAP → 현재 추천 음"). UP/DOWN(스케일
// 이동)·HOLD(길게 연주)는 지시서 자체가 "향후 확장"으로 남긴 부분이라
// 이번에도 TAP만 구현한다. 코드도 같은 방식으로 이어 붙였다(지시서 29번
// "TAP → 현재 추천 코드"). 멜로디는 다음 배치.
//
// ── 드럼 구조 결정(사용자 확인, 2026-09-17) ──
// 지금 엔진은 드럼이 트랙 하나·패턴 하나(모든 레인 포함)라 킥/스네어/하이햇을
// 각각 독립 트랙으로 쪼개지 않는다. 그래서 이 화면은 **한 드럼 패턴에 레인만
// 순서대로 채워 넣는다** — 킥 단계에서 'kick' 레인만, 스네어 단계에서 'snare'
// 레인만 두드려 같은 패턴에 쌓는다. 화면(연주 경험)은 한 번에 한 악기지만,
// 데이터로는 계속 같은 드럼 트랙 하나다.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';

import '../audio_isolate.dart';
import '../doodle_chords.dart';
import '../doodle_hints.dart';
import '../doodle_gestures.dart';
import '../drums.dart' show DRUM_KITS;
import '../edit_ops.dart' show DrumOps;
import '../engine.dart' show boomTailFor;
import '../genre_mix.dart' show kGenreDuck;
import '../genres.dart' show genreDef;
import '../live_ops.dart' show MetTick, beatsToSend, metroBatch;
import '../meter.dart';
import '../patterns.dart' show NotePatternDef;
import '../prog_ops.dart' show ProgSlot, kMaxDegree;
import '../project.dart';
import '../sequencer.dart';
import '../synth.dart' show kPartChord, kPartLive;
import '../tap_rec.dart';
import '../theory.dart'
    show
        ChordSpec,
        MusicKey,
        chordMidiOf,
        degreeFreq,
        genreChordType,
        guitarChordMidi,
        midiFreq,
        voiceLead;
import 'design.dart' show DS;
import 'editor_view.dart';
import 'play_head.dart';

/// 이 단계에서 무엇을 만드는가 — 드럼은 **레인**(같은 드럼 패턴 안의 한
/// 줄), 베이스는 **음**(코드 뿌리음), 코드는 **화음 전체**(별도 note
/// 패턴, 화음 좌표계), 멜로디는 **스케일 안전음**(그 칸의 코드에 어울리는
/// 음, `tapDegree`가 type!='bass'&&!chord 일 때 돌려주는 값 — 지시서 28번:
/// "피아노 건반처럼 모든 음이 아니라, 현재 Scale 기준 안전한 음만")이다.
enum DoodleKind { drum, bass, chord }

/// 장르별 제작 순서 하나. 데이터로 뒀으니 나중에 코드·멜로디를 더해도
/// 이 화면의 진행 로직(_tick/_keep 등)은 안 바뀐다(지시서 30번: "장르가
/// 늘어도 UI 코드는 그대로").
class DoodleStage {
  final DoodleKind kind;
  final String label;

  /// [kind]==drum 일 때만 뜻이 있다 — `kTapDrumPads`/`DrumOps`가 쓰는 레인 이름.
  final String? drumLane;
  const DoodleStage.drum(String lane, this.label)
    : kind = DoodleKind.drum,
      drumLane = lane;
  const DoodleStage.bass(this.label) : kind = DoodleKind.bass, drumLane = null;
  const DoodleStage.chord(this.label) : kind = DoodleKind.chord, drumLane = null;
}

/// 이번 배치의 순서 — 드럼 셋(킥·스네어·하이햇) + 코드 + 베이스.
///
/// ── 코드가 베이스보다 **먼저**인 이유 (2026-09-21, 시험으로 확인) ──
/// 베이스 음높이는 `_degreeAt` → `tapDegree` → `_rootAt` 으로 **그 칸에 흐르는
/// 코드**를 읽어서 정한다. 그런데 이 화면은 들어올 때 코드 판을 비워 두므로
/// (아래 `initState`), 베이스가 코드보다 먼저 오면 진행이 빈 목록이라
/// `_rootAt` 이 **32칸 전부 0**을 돌려준다 — 좌우로 음을 고르든 뭘 하든
/// 베이스 단계가 통째로 한 음짜리가 된다. 시험 출력:
///   빈 진행  → 32칸의 도수 = {0}
///   진행 있음 → {0, 5}
/// 코드를 먼저 치게 하면 그 판이 곧 진행이 되고, 베이스가 그것을 따라 걷는다.
const List<DoodleStage> kDoodleStages = [
  DoodleStage.drum('kick', 'KICK'),
  DoodleStage.drum('snare', 'SNARE'),
  DoodleStage.drum('hat', 'HI-HAT'),
  DoodleStage.chord('CHORD'),
  DoodleStage.bass('BASS'),
  // 멜로디는 **일부러 뺐다**(사용자 결정, 2026-09-21). 두드려서 만드는 것은
  // 곡의 바닥(리듬·화음·베이스)까지고, 그 위에 얹는 가락은 씬 화면에서
  // 트랙으로 쌓는다 — "두드리기"로 다 하려 들면 화면이 길어지기만 한다.
];

/// 2마디 — 지시서 10번의 기본 녹음 단위.
/// 녹음 단위로 **쓸 수 있는** 마디 수. 씬 길이를 여기에 맞춰 고른다.
///
/// 2마디로 박혀 있던 것이 두 가지를 한꺼번에 망가뜨렸다(사용자 신고, 2026-09-21:
/// "씬 재생이랑 두들플레이 박자가 안 맞아 / 왜 두마디만 하는 거야"):
///  1. 4마디 씬이면 **한 바퀴의 절반만** 녹음되고 나머지 절반은 앞 2마디의
///     복사본으로 들린다(8마디면 1/4).
///  2. 더 나쁜 것 — `initState` 가 `playLoop` **보다 먼저** 드럼·코드·베이스
///     클립을 2마디 빈 패턴으로 갈아 끼우는데, 씬 루프 길이는 `SceneSequencer`
///     가 "그 씬에서 제일 긴 패턴"으로 정한다(`sequencer.dart`). 그래서 이
///     화면에 들어오는 것만으로 **씬 루프가 2마디로 잘려 버린다.**
const List<int> kDoodleBarChoices = [2, 4, 8];

/// Doodle Play 화면을 전체 화면으로 연다. 장르는 **이미 골라서 적용된 뒤**라고
/// 가정한다(호출부가 `project.setGenre(...)` 까지 마친다) — 이 위젯은 드럼
/// 진행만 맡는다.
///
/// [initialBars] — 진입 화면(`doodle_setup_sheet.dart`)에서 사용자가 미리
/// 고른 판 길이(2·4·8). 주면 씬 길이로 갈무리하는 [_pickBars] 대신 **이 값을
/// 그대로** 쓴다 — 사용자가 "8마디로 시작"을 골랐는데 지금 씬이 짧다고 말없이
/// 2마디로 잘리면 고른 것이 무시된 꼴이 된다. `kDoodleBarChoices` 밖의 값이
/// 넘어와도(방어적으로) 가까운 쪽으로 갈무리한다.
Future<void> openDoodlePlay(
  BuildContext context, {
  required Project project,
  required Transport transport,
  required AudioClient? host,
  int? initialBars,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => DoodlePlayView(
        project: project,
        transport: transport,
        host: host,
        initialBars: initialBars,
      ),
    ),
  );
}

class DoodlePlayView extends StatefulWidget {
  final Project project;
  final Transport transport;
  final AudioClient? host;

  /// 진입 화면에서 미리 고른 판 길이. null 이면 여태처럼 씬 길이에서 갈무리한다.
  final int? initialBars;
  const DoodlePlayView({
    super.key,
    required this.project,
    required this.transport,
    required this.host,
    this.initialBars,
  });

  @override
  State<DoodlePlayView> createState() => _DoodlePlayViewState();
}

/// 닿아 있는 손가락 하나.
class _Finger {
  /// `TapRecorder` 의 판 번호 — 손가락마다 달라야 서로 안 닫는다.
  final int pad;

  /// 처음 닿은 자리(쓸기·미끄러뜨리기를 재려고).
  final double downX, downY;

  /// 닿은 시각 — **시간 축**은 어느 손짓과도 안 겹쳐서 판정에 제일 안전하다.
  /// 스타카토(톡)·롤(꾹)·쓸기 창(160ms)이 전부 여기서 갈린다.
  final DateTime downAt;

  /// 누른 자리로 정해진 세기(1~3).
  final int vel;

  /// 이 손가락이 음이 아니라 쓸기로 쓰였나.
  bool swiped = false;

  /// 8px 넘게 움직였나 — 움직였으면 「톡」(스타카토)이 아니다.
  bool moved = false;

  /// 지금 손가락의 세로 위치(0=위, 1=아래) — 하이햇 롤 밀도를 **롤 도중에도** 따라간다.
  double frac;

  /// 처음 닿은 세로 위치 — 오픈/롤·8분/16분 경계의 되돌림(히스테리시스)이 「처음 어느 쪽이었나」를 본다.
  final double downFrac;

  /// 지금 손가락의 세로 좌표(픽셀) — 스웰이 올라온 만큼을 화면에 그리려고.
  double curY;

  /// 롤 크레셴도의 지금 단계(0~2) — 경계에서 흔들려도 안 튀게 직전 단계를 기억한다.
  int rollBump = 0;

  /// 코드: 이 탭이 정한 진행 방향(−1·0·+1)과 색(1=위 화려·0=아래 담백) — 화면 표시용.
  int dir = 0, color = 0;

  /// 하이햇 지금 구역(`kHatBand16`·`kHatBand8`·`kHatBandOpen`) — 경계에서 흔들려도 안 튀게
  /// 직전 구역을 기억하고, 바뀌는 순간에만 손끝으로 알린다. null 이면 아직 안 읽었다.
  int? hatBand;

  /// 지금 머무는 좌우 구역(0~3). 넘어가면 미끄러뜨리기다.
  int zone;

  /// 지금 소리 나고 있는 주파수 — 미끄러뜨릴 때 **출발점**이 된다.
  double freq = 0;

  /// 이 손가락이 마지막으로 음을 연 칸. 미끄러진 뒤에도 앞 칸을 안다.
  int step;

  /// 드럼에서 꾹 눌러 롤이 도는 중인가. null 이면 아직 한 방뿐.
  /// 값은 **다음 연타를 낼 시각**이다.
  DateTime? rollNext;

  /// 이 손가락이 롤로 넘어간 순간을 이미 손끝으로 알렸나 — **상태가 바뀌는
  /// 순간에만** 한 번 울리기 위한 깃발(계속 울리면 드르륵거려 더 나쁘다,
  /// `_Drag.blocked`와 같은 원칙 — `editor_view.dart` 참고).
  bool rolled = false;

  /// 롤이 도는 동안 **다음에 실제로 소리가 들릴 시각** — `_tickRoll`이 연타를
  /// 예약할 때마다 갱신한다. 화면이 이 시각 바로 뒤 짧은 창 안에 있으면
  /// "방금 울렸다"로 보고 패드를 깜빡인다(`_rollFlashing`).
  DateTime? flashAt;

  /// 지금 손가락의 가로 위치 — 롤 크레셴도(밀수록 세기 상승)가 롤 도중에도 따라간다.
  double curX;

  /// 킥을 **홀드 붐**(`drumHoldOn`)으로 잡고 있나 — 떼는 순간 `drumHoldOff` 로 꼬리를 놓는다.
  bool boomHeld = false;

  /// 하이햇이 이 손가락으로 **오픈**으로 넘어갔나(한 번만 울린다).
  bool openFired = false;

  /// 패드/스트링 스웰을 걸고 있는 손가락인가 — 움직일 때마다 `setSwell`, 뗄 때 되돌린다.
  bool swell = false;

  _Finger({
    required this.pad,
    required this.downX,
    required this.downY,
    required this.downAt,
    required this.vel,
    required this.zone,
    required this.step,
    this.frac = 0.5,
  }) : curX = downX,
       curY = downY,
       downFrac = frac;
}

/// 한 판을 칠 때 칸별로 모은 손짓(세기·음 고르기·미끄러짐·톡) — 판을 적을 때 쓴다.
class _TakeMaps {
  final Map<int, int> vel, tone;
  final Set<int> glide, stac;
  const _TakeMaps(this.vel, this.tone, this.glide, this.stac);

  /// 지금 값의 **복사본** — 판마다 원본이 비워지므로 간직할 땐 복사해야 한다.
  factory _TakeMaps.copyOf(
    Map<int, int> vel,
    Map<int, int> tone,
    Set<int> glide,
    Set<int> stac,
  ) => _TakeMaps(Map.of(vel), Map.of(tone), Set.of(glide), Set.of(stac));
}

/// 적어 둔 베이스 한 판 — 친 칸들 + 손짓.
class _BassTake {
  final List<TapHit> hits;
  final _TakeMaps maps;
  const _BassTake(this.hits, this.maps);
}

/// 친 자리에서 퍼지는 물결 한 개(화면 이펙트 전용 — 판정·소리와 무관).
class _Ripple {
  final Offset at;
  final int vel;
  final DateTime born;

  /// 롤로 넘어간 순간의 큰 물결인가(한 방과 구분해서 보여 준다).
  final bool roll;

  /// 어느 악기로 쳤나('kick'·'snare'·'hat'·'hatopen'·'bass'·'chord') — 악기마다 물결 모양이 다르다.
  final String lane;

  /// 코드 탭이면 그 방향(−1·0·+1)과 색(1=위 화려) — 방향 화살표·반짝임을 물결에 얹는다.
  final int dir, color;
  const _Ripple(
    this.at,
    this.vel,
    this.born, {
    this.roll = false,
    this.lane = '',
    this.dir = 0,
    this.color = 0,
  });
}

class _FxRepaint extends ChangeNotifier {
  void poke() => notifyListeners();
}

class _DoodlePlayViewState extends State<DoodlePlayView>
    with SingleTickerProviderStateMixin {
  final _clock = LoopClock();
  Timer? _timer;

  late final Track _drumTrack;
  late final String _drumPatternName;
  late DrumOps _ops;

  late final Track _bassTrack;
  late final String _bassPatternName;
  List<List<Object?>> _bassNotes = [];

  /// 마지막으로 **적은** 베이스 한 판의 리듬·손짓 — 코드 진행이 바뀌면 이걸로 음높이만 다시 얹는다.
  _BassTake? _bassSnap;

  late final Track _chordTrack;
  late final String _chordPatternName;
  List<List<Object?>> _chordNotes = [];

  double _loopSec = 0;
  int _loopBars = 0;

  int _stage = 0;
  TapClock? _clockState;
  TapRecorder? _rec;

  /// 칠 순서 — 기본은 [kDoodleStages] 그대로지만, 시작 전 "순서 정하기"
  /// 화면(`_orderBody`)에서 사용자가 드래그로 바꿀 수 있다(사용자 요청,
  /// 2026-09-22: "진행순서 변경가능하게"). 전역 상수는 **기본값**으로만 쓰고,
  /// 이 화면 안의 모든 진행 로직은 이 인스턴스 목록을 본다.
  final List<DoodleStage> _stages = List.of(kDoodleStages);

  /// 순서를 고르는 중인가 — 참이면 아직 박 세기·녹음이 시작되지 않는다.
  /// `_tick`이 이 동안은 그냥 아무 일도 안 하고 돌아간다.
  bool _ordering = true;

  bool _reviewing = false;
  bool _allDone = false;
  List<TapHit> _pending = const [];

  /// 「사용하기」를 적어도 한 번 눌러 **확정한** 단계들 (사용자 지시,
  /// 2026-09-24: "킥에서 바로 하이햇·코드로 갈 수 있게" — 진행 표시를 눌러
  /// 자유로 오갈 수 있게 되면서, "완성"을 더는 "마지막 자리까지 순서대로
  /// 왔는가"로 못 잰다. 대신 **이 판이 몇 개 찼는가**로 잰다 — 순서와 무관하게
  /// 모든 단계가 한 번씩 확정되면 완성이다. `_retake()`로 다시 비운 단계는
  /// 여기서 빠진다(재확정 전까지는 "완성"에 안 든다).
  final Set<int> _keptStages = {};

  final Set<int> _metSent = {};

  /// 판 끝 쪽에서 **다음 판 머리 박**을 미리 잡아 둔 것(다음 판 기준 번호).
  /// 판이 넘어가면 이것이 그대로 `_metSent` 가 된다(같은 박을 두 번 안 보내려고).
  final Set<int> _metNext = {};
  double _metLastNow = 0;

  /// 이 판이 몇 마디인가 — **씬 길이를 따라간다**(2·4·8). `initState` 가
  /// 클립을 비우기 **전에** 재서 넣는다.
  late final int _bars;

  /// 씬 길이를 쓸 수 있는 판 길이로 갈무리한다. 1·3마디처럼 어중간한 씬은
  /// 2로 올린다 — 더 짧게 자르면 사용자가 친 것이 잘린다.
  static int _pickBars(int sceneBars) =>
      sceneBars >= 8 ? 8 : (sceneBars >= 4 ? 4 : 2);

  /// 엔진이 **실제로** 들고 있는 버퍼(프레임). `AudioStats` 가 `aheadFrames`
  /// 라는 이름으로 보내지만 실은 실측 `buffered` 다(`audio_isolate.dart` 의
  /// 보내는 쪽 10번 칸). 목표치(`AudioClient.aheadFrames`)와 달라질 수 있어서
  /// **예약 시각 보정은 이 실측값으로 한다.**
  int _buffered = 3072;
  StreamSubscription<AudioStats>? _statsSub;

  /// 들어오면서 재운 트랙들의 **원래 음소거 상태** — 나갈 때 그대로 되돌린다.
  /// 이 화면은 빈 씬에서 시작해야 하지만(사용자 지시), 남의 가락을 뺏으면 안 된다.
  final Map<String, bool> _priorMute = {};

  /// 들어올 때의 **원래 음색·킷**(트랙 id → 값) — 순서 화면에서 악기를 바꿨는데 그 단계를
  /// 씬에 남기지 않고 나가면 되돌린다(`dispose`). 드럼 트랙은 킷을 든다.
  final Map<String, String> _origVoice = {};

  /// 들어올 때의 레인별 킷 덮어쓰기(`Scene.laneKits`) — 나갈 때 되돌리기용.
  Map<String, String> _origLaneKits = {};

  /// [lane] 을 칠 킷 — 레인 덮어쓰기가 있으면 그것, 없으면 트랙 킷(=옛 동작).
  String _kitOfLane(String lane) =>
      drumKitFor(_drumTrack.kit, _origScene.laneKits, lane);

  /// 마지막으로 치는 자리의 크기 — 롤 도중 크레셴도가 폭(1/4 단위)을 재려고 쓴다.
  Size _area = Size.zero;

  /// 들어올 때의 **원래 클립**(트랙 id → 패턴 이름) — 확정 없이 나가면 되돌린다.
  /// `initState` 가 드럼·베이스·코드 클립을 빈 패턴으로 갈아 끼우므로, 안 챙기면
  /// 「두드려서 채우기」로 기존 곡에 들어갔다 그냥 나오는 것만으로 세 트랙이 사라진다.
  final Map<String, String?> _origClip = {};
  late final Scene _origScene;

  /// 씬에 **실제로 남긴** 단계들 — 「사용하기」(`_keep`)나 진행 표시로 건너뛰며
  /// 치던 것을 닫은 것(`_gotoStage`). 이 단계의 악기 종류는 나갈 때 되돌리지 않는다.
  final Set<int> _savedStages = {};

  /// 마지막 4박 피드백을 한 번만 울리게(같은 박에서 여러 번 안 떨게).
  int? _lastHapticBeat;

  // ── 손짓(제스처) ──
  //
  // 여태는 TAP 하나뿐이었다(톡 치면 한 칸). 지시서가 "향후 확장"으로
  // 미뤄 둔 HOLD·UP/DOWN 을 여기서 더한다. 셋 다 **손가락 하나**로 갈리므로
  // `GestureDetector` 대신 `Listener`(날 포인터 이벤트)를 쓴다 — 탭과 끌기
  // 인식기가 경합하면 "누가 이겼나"가 정해질 때까지 음이 늦게 나는데,
  // 박자를 치는 화면에서 그 지연은 그대로 틀린 박이 된다.

  /// 지금 닿아 있는 손가락들 — 포인터 번호 → 그 손가락 상태.
  /// **여러 개를 동시에 받는다**(사용자 요청, 2026-09-21): 한 손가락만 받으면
  /// 빠른 연타를 두 손으로 번갈아 칠 수 없어서 "치는 느낌"이 안 난다.
  final Map<int, _Finger> _fingers = {};

  /// HOLD 중인가 — 화면 표시에 쓴다.
  bool get _pressed => _fingers.values.any((f) => !f.swiped);

  // ── 코드 기믹 (2026-09-29 (12)) ──
  //
  // 탭 = 리듬. 어느 코드가 울리는지는 **마디마다 미리 깔린 진행**(`_plan`)이 정한다.
  // 좌우(X): 한 마디의 **착지(마지막) 탭**이 있던 쪽이 **다음 마디**를 그 방향으로 한 걸음
  // 갈아 끼운다(왼=긴장, 오=해결). 상하(Y): 같은 자리 코드의 **색**(밝기).
  // 전위(자리바꿈) 쓸기는 없앴다 — 세로가 색이 됐고, 화음도 늘 기본형이다.

  /// 이번 세션에 깔아 둔 기본 진행(매번 다르게)과 이번 판의 진행 상태. 규칙은
  /// `DoodleChordPlan`(시험이 직접 돌린다) — 화면은 손짓만 넘긴다.
  late DoodleChordPlan _cp;
  List<DoodleChordPick> get _basePlan => _cp.base;

  final math.Random _rng = math.Random();

  /// 방금 친 코드 이름·가장 최근 좌우 방향 — 은은한 힌트(색·화살표)와 이름표용.
  ChordSpec? _lastSpec;
  int _lastDir = 0;

  /// **착지 탭**(이 마디에서 마지막으로 친 탭)의 마디 번호·화면 자리. 마디가 바뀌면
  /// (`_landBar != 지금 마디`) 표시가 사라진다 — 새 마디는 아직 착지가 없다.
  int _landBar = -1;
  Offset? _landPos;

  /// 앞에 울린 코드의 자리(MIDI) — `voiceLead` 로 **공통음을 살려 잇는다**.
  /// 재생(`buildChordPattern`)이 같은 함수로 이으므로 친 소리와 재생이 같은 자리로 난다.
  List<int> _prevVoiced = const [];

  /// 친 자리마다 하나씩 퍼지는 타격 물결 — **손가락이 닿은 그 자리**에서
  /// 퍼진다(감사 2026-09-29: 예전엔 화면 한가운데 패드에서만 퍼져서 어디를 쳐도
  /// 같은 자리가 반짝였고, 패드를 안 그리는 베이스는 물결이 아예 없었다).
  /// 크기·진하기는 세기(1~3)를 따른다. 시계(`_tick`)가 30ms마다 다시 그리므로
  /// 따로 애니메이션 장치를 두지 않고 친 시각과 지금의 차로 셈한다.
  final List<_Ripple> _ripples = [];

  // ── 60fps 타격 화면 (2026-09-30, B) ──
  // 물결·충전 링·스웰 진행은 위젯이 아니라 **한 장의 그림**(`_HitFxPainter`)으로 그린다. 30ms 시계
  // (`_tick`)의 `setState` 로는 33fps 라 물결이 뚝뚝 끊겼다. 손이 닿아 있거나 물결이 남아 있는 동안만
  // 프레임마다(`_fxTicker`) 다시 그리고, 다 사그라들면 멈춘다(`_onFx`) — 놀 때는 배터리를 안 쓴다.
  final _FxRepaint _fx = _FxRepaint();
  late final Ticker _fxTicker;

  /// 물결 하나가 완전히 사라지는 데 걸리는 최대 시간(ms) — 세게(3)·롤이 제일 오래 남는다.
  static const int _kRippleMaxMs = 560;

  /// 코드 탭 직후 구역이 번쩍이는 시간(ms).
  static const int _kZoneFlashMs = 480;

  /// 가장 최근 코드 탭의 시각·방향·색 — 구역 번쩍임(`_ChordZonePainter`)용.
  DateTime? _flashAt;
  int _flashDir = 0, _flashColor = 0;

  // ── 손짓 오인식 줄이기 (2026-09-30, E) — 직전 탭의 구역을 기억해 경계에서 안 튀게 한다 ──
  // 값/시간 상수는 `doodle_gestures.dart` (`kBandSlopPx`·`kStickyMs`·`kTapSlopPx`…).
  final StickyBand _velX = StickyBand(const [1 / 3, 2 / 3]);
  final StickyBand _velCtr = StickyBand(const [_kHardR, _kSoftR]);
  final StickyBand _ghost = StickyBand(const [_kGhostFrac]);
  final StickyBand _dirBand = StickyBand(const [1 / 3, 2 / 3]);
  final StickyBand _colorBand = StickyBand(const [kChordColorSplit]);
  final StickyBand _swellBand = StickyBand(const [kSwellZone]);
  int? _lastRow;
  int _lastRowMs = -1 << 40;

  void _resetSticky() {
    _velX.reset();
    _velCtr.reset();
    _ghost.reset();
    _dirBand.reset();
    _colorBand.reset();
    _swellBand.reset();
    _lastRow = null;
    _flashAt = null;
  }

  // ── 첫 안내 카드 (2026-09-30, D) ──
  /// 「?」를 눌러 이미 본 안내를 다시 띄우는 중인가.
  bool _coachForce = false;

  /// 사다리 칸별 **마지막으로 지나온 시각** — 베이스에서 미끄러뜨릴 때
  /// (`_slideTo`) 남기는 궤적이다. [_kLadderTrailMs] 안이면 그 칸이 잠깐
  /// 밝아진다(지나온 흔적, 시각만 — 판정과 무관).
  final Map<int, DateTime> _rowVisitAt = {};

  /// 리뷰 화면(`_reviewBody`) 전용 깜빡임 재생기 — `_tick`은 `_reviewing`
  /// 동안 아무 일도 안 하고 돌아가므로(위 `_tick` 참고), "지금 들려주는 중"
  /// 표시 하나만을 위해 아주 가볍게 따로 돌린다. 리뷰가 끝나면 바로 멈춘다.
  Timer? _reviewBlink;

  /// HOLD 로 잡고 있는 손가락 번호의 **시작값**. 손가락마다 +1 해서 쓴다
  /// (라이브 화면과 겹치지 않게 큰 수로 둔다).
  static const int _kHoldId = 9001;

  /// 코드 단계에서 잡고 있는 화음 음들의 번호 시작값 — 손가락 번호와 겹치면
  /// 안 되므로 따로 뗀 자리에 둔다.
  static const int _kChordId = 9200;

  /// 한 화음에 낼 수 있는 음 수 — 9화음(5음)까지.
  static const int _kMaxChordTones = 5;

  /// 이 시간 안에 떼면 **톡**(스타카토). 시간 축이라 다른 손짓과 안 겹친다.
  static const int _kStaccatoMs = 90;

  /// 「톡」으로 치려면 이만큼 안에서 끝나야 한다 — 값은 `kTapSlopPx`(엄지가 구르는 만큼 넉넉히).
  static const double _kStaccatoSlop = kTapSlopPx;

  /// 드럼에서 이만큼 붙이고 있으면 **롤**이 돈다.
  static const int _kRollAfterMs = 180;

  /// 롤 충전 링을 **보이기 시작하는 시각**(ms) — 톡 치는 손가락(보통 60~90ms)에는
  /// 링이 안 깜빡이게, 「꾹」이 시작된 뒤부터만 차오른다(감사 2026-09-29: 220→180ms
  /// 전체에 걸쳐 그리면 모든 탭마다 링이 번쩍여 "롤 예고"가 잡음이 된다).
  static const int _kRollShowMs = 70;

  /// 롤을 앞질러 예약하는 창 — 길면 뗐는데 계속 쳐서 "화면이 안 먹는다"가 된다.
  static const double _kRollAheadSec = 0.12;

  /// 한 번에 받을 손가락 수 — `TapRecorder` 의 판이 넷이라 거기에 맞춘다.
  static const int _kMaxFingers = 4;


  /// 이번 판에서 그 칸을 **얼마나 세게** 쳤나(칸 → 1~3).
  /// `TapHit` 에는 세기 칸이 없어서(박자만 담는 그릇이다) 여기 따로 들고 있다가
  /// 판에 적을 때 얹는다.
  final Map<int, int> _velOf = {};

  /// 그 칸에서 **코드 안의 몇 번째 음**을 골랐나(칸 → 도수 더하기 0·2·4·6).
  /// **베이스 단계에서만 쓴다** — 코드 줄의 첫 칸은 도수가 아니라 코드 번호라
  /// 거기 더하면 딴 코드가 적힌다(아래 `_decorate` 주석).
  final Map<int, int> _toneOf = {};

  /// **미끄러뜨려서** 들어온 칸 — 음 줄 다섯째 칸에 1 을 적으면 재생도
  /// 앞 음에서 미끄러진다(`patterns.dart buildRowsPattern` 의 `n[4]==1`).
  final Set<int> _glideAt = {};

  /// **톡** 쳐서 짧게 끊은 칸 — 길이를 한 칸으로 줄인다.
  final Set<int> _staccatoAt = {};

  /// **꾹 눌러 롤**로 들어온 드럼 칸들 — 사람이 친 게 아니라 기계가 낸
  /// 정확한 시각이라 `TapRecorder`(사람 반응 지연을 되돌리는 계산)를 안 거친다.
  final Set<int> _rollSteps = {};

  /// 화면에 들어올 때 씬에 **이미 있던** 코드 진행. 이 화면은 코드 판을
  /// 비우고 시작하므로(그래야 안 친 악기가 안 울린다), 비우기 전에 챙겨 뒀다가
  /// 코드 단계를 건너뛰었을 때 베이스가 이걸 따라 걷게 한다.
  List<ProgSlot> _priorProg = const [];
  int _priorProgSteps = 0;

  /// 이 화면이 쓰는 앞질러 만드는 양(프레임) — 48kHz 에서 32ms. **탭→소리 지연의
  /// 가장 큰 몫**이다(귀에 닿기까지 이만큼 큐에 쌓여 있다).
  ///
  /// 2026-09-29 (11): 3072(64ms) → 1536(32ms). 앞 회차(2560)는 **효과가 없었다** —
  /// 예전 코드가 `prevAhead < 바닥` 일 때만 값을 바꿨는데 기본 `aheadFrames` 가
  /// 3072 라 2560 바닥은 한 번도 안 걸렸다. 이제는 무조건 이 값으로 맞춘다.
  /// 실기기에서 찢어지면 이 한 줄을 올린다: 1536 → 2048(43ms) → 2560(53ms) → 3072(64ms).
  static const int _kDoodleAhead = 1536;

  /// 손이 화면에 닿고 앱이 그것을 받기까지 걸리는 시간(초).
  ///
  /// 예전엔 이 값으로 `aheadFrames`(렌더 버퍼)를 그대로 썼는데 그건 틀렸다 —
  /// 엔진이 보고하는 위치(`loopPos`)는 이미 `nowFrames - buffered`, 즉
  /// **귀에 들리는 자리**라서 출력 버퍼는 거기서 이미 빠져 있다. 남은 것은
  /// 터치 입력 지연뿐이므로 버퍼 손잡이와 떼어 놓는다(손잡이를 만질 때마다
  /// 찍히는 자리가 따라 움직이면 안 된다).
  static const double _kTouchLatencySec = 0.03;

  /// 들어오기 전 값 — 나갈 때 그대로 되돌린다.
  int? _prevAhead;

  MeterDef get _meter => widget.project.meterDef;

  /// 16분 한 칸이 몇 초인가 — 롤(연타) 간격의 바탕.
  double get _stepSec => 60.0 / widget.transport.bpm / 4;

  /// 자가 **한 번 칠 때마다** 몇 초인가.
  ///
  /// 그냥 `60/bpm`(4분음표)을 쓰면 6/8·7/8 에서 어긋난다 — 거기서는 한 클릭이
  /// 8분음표(`clickSteps = 2`)라, 화면이 세는 박(`_meter.clicksPerBar` 기준)의
  /// **절반 속도**로만 울렸다. 박자표에서 끌어와야 세는 것과 울리는 것이 같다.
  double get _beatSec => _stepSec * _meter.clickSteps;
  DoodleStage get _stageDef => _stages[_stage];

  /// 드럼(킥·스네어·하이햇) 단계가 **전부** 확정됐는가 — `_sendMet`이 코드·
  /// 베이스 녹음 중 자를 꺼도 되는지 여기로 잰다. 자유 순서 이동으로
  /// 드럼 단계가 뒤섞여도 자리가 아니라 **종류**로 찾는다.
  bool get _drumsConfirmed {
    for (var i = 0; i < _stages.length; i++) {
      if (_stages[i].kind == DoodleKind.drum && !_keptStages.contains(i)) {
        return false;
      }
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    _fxTicker = createTicker(_onFx);
    final p = widget.project;
    // **들어오면서 아직 울리고 있을 수 있는 소리부터 끊는다** (사용자 신고,
    // 2026-09-22: "가락이 들려 — 두드린 것만 나와야지"). 씬 화면에서 멜로디
    // 음을 미리 듣던 손가락을 뗀 그 순간 이 화면으로 넘어오면, 그 음은
    // `holdOff` 로 끈 적이 없어 두들플레이 내내 계속 잡혀 있는다(아래
    // `dispose`가 나갈 때는 이미 `holdOff(-1)`을 부르는데, **들어올 때는
    // 안 불렀다** — 짝이 안 맞았다). 아직 트랙을 재우기도 전이라 맨 먼저 한다.
    widget.host?.holdOff(-1);
    // **코드 판을 비우기 전에** 지금 씬에 걸려 있는 진행을 챙긴다.
    // `readSceneProg` 는 코드 트랙의 **패턴 음들**을 읽어서 진행을 뽑는데,
    // 조금 아래에서 그 패턴을 빈 것으로 갈아 끼우므로 여기서 안 챙기면
    // 영영 못 읽는다. 코드 단계를 대충 넘겨도 베이스가 원래 화성을 따라
    // 걷게 하는 것이 이것 하나다.
    final (pp, pps) = p.readSceneProg();
    _priorProg = pp;
    _priorProgSteps = pps;
    // **씬이 몇 마디인가** — 이것도 클립을 비우고 트랙을 재우기 전에 재야
    // 한다. 나중에 재면 방금 깔아 둔 빈 판을 재게 되어 늘 같은 수가 나온다.
    // **`SceneSequencer.sceneLoopBars` 를 쓴다** — `Project.loopBarsOf` 는
    // `audible(t)`(음소거·빈 클립)를 안 보는데 실제 루프를 만드는 `build()` 는
    // 본다. 규칙이 다른 두 셈을 쓰면 반드시 어긋난다(이 저장소가 여러 번 겪었다).
    // 진입 화면에서 고른 값이 있으면 **그걸 우선한다** — 없을 때만 씬 길이로
    // 갈무리한다(여태 하던 대로, `scene_view.dart` 의 "두드려서 채우기"처럼
    // 진입 화면 없이 바로 여는 길도 있다).
    final ib = widget.initialBars;
    _bars = ib != null
        ? _pickBars(ib)
        : _pickBars(SceneSequencer.sceneLoopBars(p, p.currentScene));
    _cp = DoodleChordPlan(
      doodleBasePlan(
        mode: widget.transport.mode,
        bars: _bars,
        genre: p.genre,
        rng: _rng,
      ),
      mode: widget.transport.mode,
      genre: p.genre,
      rng: _rng,
    );
    final ts = DateTime.now().millisecondsSinceEpoch;
    p.quietly(() {
    // 클립을 갈아 끼우는 동안(그리고 나가서 되돌리기 전까지) 자동 저장이 이
    // **임시 상태**를 파일에 쓰지 못하게 막는다(`Store.saveNow`).
    p.transientEdit = true;
    _origScene = p.scene;
    _drumTrack = p.tracks.firstWhere(
      (t) => t.type == 'drum',
      orElse: () => p.tracks.first,
    );
    _origClip.putIfAbsent(_drumTrack.id, () => _origScene.clips[_drumTrack.id]);
    _drumPatternName = 'doodle_drum_$ts';
    _ops = DrumOps.read(null);
    p.putUserPattern(
      'drum',
      _drumPatternName,
      drum: _ops.toDef(_drumPatternName, _bars),
    );
    p.setClip(_drumTrack, _drumPatternName);

    // 베이스도 드럼과 같은 이유로 **미리 비워 둔다** — 그래야 화면이
    // BASS 단계로 넘어가기 전까지 조용하다가, 사용자가 친 것만 남는다.
    _bassTrack = p.tracks.firstWhere(
      (t) => t.type == 'bass',
      orElse: () => p.tracks.length > 1 ? p.tracks[1] : p.tracks.first,
    );
    _origClip.putIfAbsent(_bassTrack.id, () => _origScene.clips[_bassTrack.id]);
    _bassPatternName = 'doodle_bass_$ts';
    p.putUserPattern(
      'bass',
      _bassPatternName,
      note: NotePatternDef(_bassPatternName, _bars, _bars, const [], spb: p.spb),
    );
    p.setClip(_bassTrack, _bassPatternName);

    // 코드도 마찬가지로 미리 비워 둔다.
    _chordTrack = p.tracks.firstWhere(
      (t) => t.type == 'chord',
      orElse: () => p.tracks.length > 2 ? p.tracks[2] : p.tracks.first,
    );
    _origClip.putIfAbsent(_chordTrack.id, () => _origScene.clips[_chordTrack.id]);
    _chordPatternName = 'doodle_chord_$ts';
    p.putUserPattern(
      'chord',
      _chordPatternName,
      note: NotePatternDef(_chordPatternName, _bars, _bars, const [], spb: p.spb),
    );
    p.setClip(_chordTrack, _chordPatternName);
    _origVoice[_drumTrack.id] = _drumTrack.kit;
    _origLaneKits = Map<String, String>.from(_origScene.laneKits);
    _origVoice[_bassTrack.id] = _bassTrack.voice;
    _origVoice[_chordTrack.id] = _chordTrack.voice;

    // ── 씬을 **완전히 빈 상태**로 시작한다 (사용자 지시, 2026-09-22) ──
    // "두들플레이 시작할 때 멜로디 넣지마 씬 아무것도 없는상태에서 해야지
    //  메트로놈만 넣어."
    //
    // 여기서 두드려 채울 세 트랙(드럼·베이스·코드)은 바로 위에서 빈 판으로
    // 깔았으니 이미 조용하다. 남은 것 — 가락·패드 등 — 을 **재운다.**
    //
    // **지우지 않고 음소거다.** `setClip(t, null)` 로 비우면 이미 골라 둔
    // 가락이 씬에서 떨어져 나가고, 0.8초 뒤 자동 저장(`store.touch`)이 그
    // 상태를 파일에 그대로 쓴다 — 중간에 앱이 죽으면 영영 못 되찾는다.
    // 음소거는 나갈 때 되돌리고, 혹시 못 되돌려도 사용자가 믹서에서 바로 켠다.
    final keep = {_drumTrack.id, _bassTrack.id, _chordTrack.id};
    for (final t in p.tracks) {
      if (keep.contains(t.id)) continue;
      _priorMute[t.id] = t.mute;
      t.mute = true;
    }
    });
    // 조용히 바꾼 것은 첫 프레임이 끝난 뒤 알린다(만드는 중에 알리면 터진다).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) p.poke();
    });

    final h = widget.host;
    _clock.attach(h);
    if (h != null) {
      final b = SceneSequencer.playLoop(p, widget.transport, h);
      _applyPump(h); // `playLoop` 이 킥 덕 대상을 "전부"로 되돌렸다 — 다시 건다.
      widget.transport.playing = true;
      widget.transport.songLoop = false;
      _loopSec = b.loopSec;
      _loopBars = b.loopBars;
      h.setSongMode(false); // 손가락에 붙어야 한다
      // ── (2026-09-29 (11)) 이제 **올리기만 하지 않고 정해 둔 값으로 맞춘다** ──
      // 아래 2026-09-21 설명은 "내리지 말자"였으나, 탭 지연이 최우선이라 뒤집었다.
      // 그때 근거(급식 지체 20~36ms + 장치 1024)는 여전히 위험 요인이다 —
      // 찢어짐은 실기기에서 보고 `_kDoodleAhead` 를 올려 맞춘다.
      // ── (원문) 버퍼를 **내리지 않고 바닥만 올린다** (2026-09-21) ──
      //
      // 여기서 2048(43ms)로 낮췄었다. "눌러도 늦게 난다"를 버퍼로 때우려던
      // 것인데, 늦게 나던 진짜 이유는 버퍼가 아니라 **메트로놈이 예약 시각을
      // 잘못 재고 있던 것**이었다(아래 `_sendMet`). 그리고 이 화면은 씬 루프를
      // **틀어 놓은 채** 도는데, 곡 재생에 `kAheadSong` 을 쓰는 근거가
      // "급식 루프가 상시 20~36ms 밀린다"(36ms = 1728프레임)이다. 거기에
      // 장치 버퍼 1024를 더하면 2752 — 2048로는 **평소에도 모자란다.**
      // 마르면 위치 보고가 한 통만큼 앞으로 튀었다 되돌아와서, 고치려던
      // 「박자 안 맞음」을 오히려 만든다.
      final prevAhead = h.aheadFrames;
      _prevAhead = prevAhead;
      if (prevAhead != _kDoodleAhead) h.setAhead(_kDoodleAhead);
      _buffered = h.aheadFrames;
      // 예약 시각 보정은 **실측 버퍼**로 한다(목표치와 다를 수 있다).
      _statsSub = h.statsStream.listen((s) {
        if (s.aheadFrames > 0) _buffered = s.aheadFrames;
      });
    }
    // 이 곡이 쓸 악기·드럼 표본을 **미리 읽어 둔다**(2026-09-30, C) — 안 그러면 첫 타격이 표본이
    // 아니라 합성음으로 난다. 순서 정하기 화면에서 사용자가 고르는 동안 뒤에서 읽힌다.
    _preloadSamples();
    // 첫 안내를 이미 봤는지 읽는다(파일이라 늦게 온다 — 오면 다시 그린다).
    unawaited(DoodleHints.load().then((_) {
      if (mounted) setState(() {});
    }));
    // **박 세기는 아직 안 시작한다** — 먼저 순서 정하기 화면을 보여 주고,
    // `_startStages()`가 확정된 뒤에 `_armStage()`를 부른다. 시계(`_timer`)는
    // 미리 켜 둬도 안전하다 — `_tick()`이 `_ordering` 동안은 그냥 돌아간다.
    _timer = Timer.periodic(const Duration(milliseconds: 30), (_) => _tick());
  }

  /// 이 곡의 악기·드럼 표본을 오디오 아이솔레이트가 **미리** 읽게 한다(2026-09-30, C).
  ///
  /// 표본은 오디오 쪽 메모리에 올라가므로 UI 에서 `ensureInstrumentLoaded` 를 불러도 소용없다 —
  /// 이름만 보내 그쪽이 **기존 로드 함수**를 부르게 한다(`AudioClient.preloadSamples`). 이미 읽었거나
  /// 읽는 중이면 아무 일도 안 하니 여러 번 불러도 안전하다. 진입 지연은 없다(메시지 하나, 읽기는 뒤에서).
  /// 드럼은 표본 킷일 때만, 그리고 이 화면이 실제로 치는 조각(킥·스네어·닫힌/열린 하이햇)만.
  void _preloadSamples() {
    final h = widget.host;
    if (h == null) return;
    final voices = <String>{_bassTrack.voice, _chordTrack.voice};
    final pieces = <(String, String)>{};
    const pieceOf = {
      'kick': 'kick',
      'snare': 'snare',
      'hat': 'hatClosed',
      'hatopen': 'hatOpen',
    };
    for (final e in pieceOf.entries) {
      final kit = DRUM_KITS[_kitOfLane(e.key)];
      if (kit != null && kit.sampled) pieces.add((e.value, kit.sampleSet));
    }
    h.preloadSamples(voices: voices.toList(), drumPieces: pieces.toList());
  }

  /// **킥 사이드체인 펌핑**(하우스 계열만 자동 ON, `setSidechainPump`). `playLoop`/`refreshLoop`/
  /// `setGenreMix` 는 킥 덕의 대상을 "전부"로 되돌리므로 **그 뒤마다** 다시 건다.
  /// 펌핑 장르가 아니면 `playLoop` 이 걸어 둔 장르 기본 덕(사용자 손잡이 우선) 그대로 둔다 —
  /// 여기서 0 으로 꺼 버리면 트랩 등의 원래 비켜 주기가 두들에서만 사라진다.
  void _applyPump(AudioClient h) {
    final p = widget.project;
    final g = p.genre;
    h.setSidechainPump(
      g.isEmpty ? null : g,
      offDepth: p.duckAmountOverride ?? kGenreDuck[g] ?? 0,
    );
  }

  /// 판을 다시 싣는다 — `refreshLoop` + 펌핑 대상 복구.
  void _refreshLoop(AudioClient h) {
    SceneSequencer.refreshLoop(widget.project, widget.transport, h);
    _applyPump(h);
  }

  /// 순서 정하기 화면에서 "이 순서로 시작"을 눌렀다 — 이제부터 박이 돈다.
  void _startStages() {
    widget.host?.clearSwell(); // 편성(악기)이 정해졌다 — 미리 듣기로 남은 스웰은 걷는다.
    setState(() => _ordering = false);
    _armStage();
    // 첫 단계도 **씬 머리에서** 시작한다. 씬 루프는 `initState` 의 `playLoop`
    // 부터 계속 돌아 왔고, 그동안 사용자가 순서를 고르느라 시간을 썼으니
    // 지금쯤 루프는 아무 자리에나 가 있다 — 되감지 않으면 첫 악기의 미리
    // 세기가 씬 중간에서 시작한다. 단계 전환(`_keep`)과 같은 결로 맞춘다.
    _rewindLoop();
  }

  /// 미리 세기 한 마디(초) — 판 머리를 이만큼 미룬다. 판이 한 마디보다 짧으면 0.
  double get _leadSec {
    final s = _meter.clicksPerBar * _beatSec;
    return (_loopSec > s && _loopBars > 1) ? s : 0;
  }

  /// 되감은 직후의 (들리는) 위치 — 미리 세기가 판 끝쪽에서 시작한다.
  double _leadInPos() => leadInStartPos(
    loopSec: _loopSec,
    leadSec: _leadSec,
    bufferedSec: _buffered / 48000.0,
  );

  /// 미리 세기 첫 박의 판 안 번호 — 판 끝에서 한 마디 앞. 미루기가 없으면 0.
  int _leadBeat() => _leadSec > 0
      ? _loopBars * _meter.clicksPerBar - _meter.clicksPerBar
      : 0;

  /// 씬 루프를 **머리(0)로 되감는다** — 새 악기가 씬 처음부터 흐르고 미리
  /// 세기도 거기서 시작하게(사용자 신고, 2026-09-23: "악기 넘어갈 때 처음부터
  /// 흐름이 돌게 만들어야지"). `refreshLoop(restart: true)` 가 방금 확정한 앞
  /// 악기까지 실은 새 루프를 만들고 **엔진 재생 위치를 0으로** 돌린다
  /// (`setLoop` 의 restart 경로). `_clock`(화면이 읽는 위치)도 같이 0으로
  /// 맞춰, 다음 실측(0.25초 간격)이 올 때까지 보간이 옛 위치에서 앞으로
  /// 흘러 새 `TapClock` 을 엉뚱한 자리에서 깨우지 않게 한다.
  void _rewindLoop() {
    final h = widget.host;
    if (h == null) return;
    // **미리 세기 한 마디를 판의 마지막 마디 자리에 놓는다**(2026-09-29 (14)). 판 머리(0)에서
    // 되감으면 미리 세기가 0~1마디, 녹음이 1마디째부터라 친 것이 통째로 한 마디 밀려 담겼다.
    // 판 머리를 한 마디(`_leadSec`) 뒤로 미뤄 카운트가 끝나는 순간 = 판 0 이 되게 한다.
    SceneSequencer.refreshLoop(
      widget.project,
      widget.transport,
      h,
      restart: true,
      startDelaySec: _leadSec,
    );
    _applyPump(h);
    _clock.reset(_leadInPos());
    // 되감기는 엔진 예약(`clearSchedule`)을 통째로 비운다 — 이미 앞질러 보낸 자(최대
    // 0.5초 치)도 같이 사라진다. 기록(`_metSent`)을 그대로 두면 「이미 보냈다」로
    // 읽혀 그 박들이 **영영 안 울린다**(메트로놈 가끔 누락의 원인, 2026-09-29 (11)).
    _metSent.clear();
    _metNext.clear();
    _metLastNow = 0;
    _sendMetHead(h);
  }

  /// 되감은 **바로 그 자리(판 머리)** 의 첫 박. 새 판이 렌더 커서에서 시작하므로
  /// delay 0 으로 같은 자리에 놓는다. 여기서 안 내면 0박은 `gap` 안쪽이라 다시는
  /// 안 잡힌다. 자가 꺼져야 하는 대목이면(`doodleShouldSendMet`) 내지 않는다.
  void _sendMetHead(AudioClient h) {
    final cs = _clockState;
    if (cs == null || cs.phase == TapPhase.done) return;
    if (!doodleShouldSendMet(
      phase: cs.phase,
      isDrumStage: _stageDef.kind == DoodleKind.drum,
      drumsConfirmed: _drumsConfirmed,
    )) {
      return;
    }
    // 되감은 바로 그 자리의 첫 박 — 미리 세기 첫 박은 판 끝에서 한 마디 앞(`_leadBeat`)이다
    // (`_leadSec` 가 0 이면 예전처럼 판 0박).
    final beat = _leadBeat();
    h.batch(metroBatch([MetTick(beat, 0.0)], beatsPerBar: _meter.clicksPerBar));
    _metSent.add(beat);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _reviewBlink?.cancel();
    _statsSub?.cancel();
    _fxTicker.dispose();
    _fx.dispose();
    _clock.dispose();
    final h = widget.host;
    h?.holdOff(-1);
    h?.clearSwell(); // 패드/스트링 스웰이 남아 다른 화면의 코드 버스를 누르지 않게
    for (var i = 0; i < _kMaxFingers; i++) {
      h?.drumHoldOff(_kHoldId + i, tailSec: 0.05);
    }
    // 재워 뒀던 트랙을 **먼저** 깨운다 — `pushMix` 가 그 상태를 읽어 간다.
    for (final t in widget.project.tracks) {
      final was = _priorMute[t.id];
      if (was != null && t.mute != was) t.mute = was;
    }
    // 씬에 남기지 않은 악기(확정 안 한 것)는 **원래 클립으로 되돌린다.**
    final savedKinds = {for (final i in _savedStages) _stages[i].kind};
    void restore(Track t, DoodleKind k) {
      if (savedKinds.contains(k) || !_origClip.containsKey(t.id)) return;
      _origScene.clips[t.id] = _origClip[t.id];
      if (identical(widget.project.scene, _origScene)) t.pattern = _origClip[t.id];
    }
    restore(_drumTrack, DoodleKind.drum);
    restore(_bassTrack, DoodleKind.bass);
    restore(_chordTrack, DoodleKind.chord);
    // 순서 화면에서 바꾼 악기(음색·킷)도 — 그 종류를 씬에 남기지 않았으면 원래대로.
    void restoreVoice(Track t, DoodleKind k) {
      final o = _origVoice[t.id];
      if (savedKinds.contains(k) || o == null) return;
      if (k == DoodleKind.drum) {
        t.kit = o;
        _origScene.laneKits
          ..clear()
          ..addAll(_origLaneKits);
      } else {
        t.voice = o;
      }
    }
    restoreVoice(_drumTrack, DoodleKind.drum);
    restoreVoice(_bassTrack, DoodleKind.bass);
    restoreVoice(_chordTrack, DoodleKind.chord);
    widget.project.endTransientEdit(); // 되돌린 상태를 저장 대상으로 돌려놓는다
    if (h != null) SceneSequencer.pushMix(widget.project, h);
    final prev = _prevAhead;
    if (h != null && prev != null && prev != h.aheadFrames) h.setAhead(prev);
    h?.setSongMode(true);
    super.dispose();
  }

  void _armStage() {
    _stopReviewBlink(); // 리뷰를 나가는 모든 길이 여기를 지난다.
    _clockState = TapClock(
      beatsPerLoop: _loopBars * _meter.clicksPerBar,
      lapBeats: _bars * _meter.clicksPerBar,
      countBeats: _meter.clicksPerBar,
      beatsPerBar: _meter.clicksPerBar,
      // `_armStage`를 부르는 모든 자리(`_startStages`·`_keep`·`_gotoStage`·
      // `_retake`)가 반드시 `_rewindLoop()`도 같이 부른다 — 그래서 이 화면의
      // TapClock은 늘 씬 머리(0)에서 만들어진다. `wait` 단계로 "마디 머리를
      // 기다리는" 계산을 또 거치면 오히려 판을 한 바퀴 거의 다 돌아야
      // 시작된다(`tap_rec.dart`의 `armedAtHead` 문서 참고).
      armedAtHead: true,
      startBeat: _loopSec > 0
          ? _leadInPos() * _loopBars * _meter.clicksPerBar
          : null,
    );
    // 녹음 전에도 "지금 몇 번째 칸인가"를 알아야 미리 들려주는 소리가 그
    // 자리 코드에 맞는다 — 그래서 녹음기를 미리 만들어 둔다. 실제 담기는
    // 것은 `_startRec` 이 새로 끼우는 깨끗한 녹음기다.
    _rec = _newRecorder();
    _reviewing = false;
    _pending = const [];
    _lastHapticBeat = null;
    // 손짓 상태도 같이 되돌린다 — 다시 녹음인데 앞 판에서 잡고 있던 손가락이
    // 남아 있으면 첫 음이 잘못 닫힌다. 음 높이는 단계가 바뀌면 0으로.
    _fingers.clear();
    _velOf.clear();
    _toneOf.clear();
    _glideAt.clear();
    _staccatoAt.clear();
    _resetChordPlan();
    _rollSteps.clear();
    _ripples.clear();
    _resetSticky();
    // 잡고 있던 것을 **손가락 수만큼** 놓는다 — `_kHoldId` 하나만 놓으면
    // 두 번째 손가락 이후가 계속 울린다(판마다 +pad 로 쓰기 때문이다).
    for (var i = 0; i < _kMaxFingers; i++) {
      widget.host?.holdOff(_kHoldId + i);
    }
    // 코드 음들도 따로 번호를 쓰므로 같이 놓는다 — 안 놓으면 「다시 녹음」을
    // 누른 뒤에도 앞 화음이 계속 울린다.
    for (var i = 0; i < _kMaxChordTones; i++) {
      widget.host?.holdOff(_kChordId + i);
    }
    // 잡고 있던 808 킥(홀드 붐)도 놓고, 단계가 바뀌면(편성이 바뀌면) 스웰도 걷는다.
    for (var i = 0; i < _kMaxFingers; i++) {
      widget.host?.drumHoldOff(_kHoldId + i, tailSec: 0.05);
    }
    widget.host?.clearSwell();
    // 자(메트로놈)가 보낸 기록도 비운다 — 안 비우면 앞 단계에서 이미 보낸
    // 박 번호가 남아 새 단계의 미리 세기 첫 박이 막힐 수 있다.
    _metSent.clear();
    _metNext.clear();
    _metLastNow = 0;
  }

  /// 리뷰 화면의 "지금 들려주는 중" 표시를 깜빡이게 한다. `_tick`(30ms)은
  /// `_reviewing` 동안 그냥 돌아가기만 하고 `setState`를 안 부르므로(위
  /// `_tick` 참고), 이 표시 하나만을 위해 따로 아주 가벼운 시계를 켠다 —
  /// 400ms면 깜빡임을 느끼기에 충분하고 부담도 없다.
  void _startReviewBlink() {
    _reviewBlink?.cancel();
    _reviewBlink = Timer.periodic(const Duration(milliseconds: 400), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopReviewBlink() {
    _reviewBlink?.cancel();
    _reviewBlink = null;
  }

  // ── 박 세기 ── (두드려 넣기 화면과 같은 계산, `tap_sheet.dart` 참고)

  void _tick() {
    final h = widget.host;
    if (!mounted ||
        h == null ||
        _loopSec <= 0 ||
        _ordering ||
        _reviewing ||
        _allDone) {
      return;
    }
    final pos = _clock.pos(_loopSec);
    _sendMet(pos, h);
    final cs = _clockState!;
    final was = cs.phase;
    cs.update(pos * _loopBars * _meter.clicksPerBar);
    if (was != TapPhase.rec && cs.phase == TapPhase.rec) _startRec();
    _maybeHaptic(cs);
    if (cs.phase == TapPhase.rec && _stageDef.kind == DoodleKind.chord) {
      final r = _rec;
      if (r != null) _cp.settleUpTo(_barOf(r.stepOf(pos)));
    }
    _tickRoll();
    if (cs.phase == TapPhase.done) {
      _finishLap(pos);
      return;
    }
    _fx.poke(); // 그림(물결·힌트 맥박)은 setState 없이도 다시 그린다
    setState(() {});
  }

  void _sendMet(double pos, AudioClient h) {
    final cs = _clockState;
    if (cs == null) return;
    // **대기 때부터 울린다.** 여태는 미리 세기(count)부터였는데, 그때는 씬의
    // 가락이 깔려 있어서 화면이 조용하지 않았다. 이제 씬을 통째로 재우므로
    // (사용자 지시: "메트로놈만 넣어") 대기 구간이 **완전한 침묵**이 된다 —
    // 4마디 씬이면 길게는 12초다. 그동안 아무 소리도 안 나면 사용자에겐
    // 고장 난 화면이고, 박을 미리 타 볼 수도 없다.
    if (cs.phase == TapPhase.done) return;
    // 드럼이 이미 확정된 뒤 코드·베이스를 **녹음하는 동안**은 자를 끈다 —
    // 계산은 `doodleShouldSendMet`(`tap_rec.dart`, 시험이 잰다).
    if (!doodleShouldSendMet(
      phase: cs.phase,
      isDrumStage: _stageDef.kind == DoodleKind.drum,
      drumsConfirmed: _drumsConfirmed,
    )) {
      return;
    }
    // ── 「씬 재생이랑 박자가 안 맞아」의 몸통 (사용자 신고, 2026-09-21) ──
    //
    // 두 경로가 **서로 다른 시계**로 시각을 쟀다.
    //   · 씬 루프: `delay = (nextAt - engine.nowFrames)/SR` 로 재고, 엔진이
    //     `_now + delay` 를 더하면 정확히 `nextAt` 이 된다 — **렌더 시계** 기준.
    //   · 자(메트로놈): `pos * _loopSec` 로 쟀는데, 그 `pos` 는
    //     `loop.posOf(nowFrames - buffered)` = **귀에 들리는 자리**다.
    //     그런데 그 delay 도 결국 렌더 시계에 얹히므로, 자만 정확히
    //     **버퍼 한 통만큼 늦게** 울렸다(3072프레임이면 64ms — 92BPM 16분의 39%).
    //
    // 그래서 넘기는 기준을 렌더 시계로 올려 준다. 그러면 `t - nowSec` 가
    // 「렌더 커서에서 t 까지」가 되어 자가 정확히 t 에 들린다.
    final nowSec = pos * _loopSec + _buffered / 48000.0;
    // 판이 **진짜로** 넘어갔을 때만 비운다. 위치 보간은 실측값과 만나는 자리에서
    // 조금씩 뒤로 흔들리는데(`TapClock` 도 같은 이유로 전용 가드를 둔다),
    // 그 미세한 역행까지 「한 바퀴 돌았다」로 읽으면 같은 박을 두 번 보내
    // 플램으로 들린다.
    if (_metLastNow - nowSec > _loopSec / 2) {
      _metSent
        ..clear()
        ..addAll(_metNext);
      _metNext.clear();
    }
    if (nowSec > _metLastNow) _metLastNow = nowSec;
    final ticks = beatsToSend(
      nowSec: nowSec,
      loopSec: _loopSec,
      beatSec: _beatSec,
      sent: _metSent,
      lead: 0.5,
      wrap: true,
      sentNext: _metNext,
    );
    if (ticks.isEmpty) return;
    h.batch(metroBatch(ticks, beatsPerBar: _meter.clicksPerBar));
    for (final t in ticks) {
      (t.next ? _metNext : _metSent).add(t.beat);
    }
  }

  /// 마지막 4박 — 화면(도트)과 촉각으로 "곧 끝난다"를 알린다(지시서 20번).
  /// 촉각이 없는 기기에서도 `HapticFeedback` 은 조용히 아무 일도 안 하므로
  /// 따로 감쌀 필요가 없다 — 화면 표시는 [_beatsLeft] 가 별도로 맡는다.
  void _maybeHaptic(TapClock cs) {
    if (cs.phase != TapPhase.rec) return;
    final left = (_bars * _meter.clicksPerBar * (1 - cs.progress))
        .round();
    if (left <= 4 && left >= 1 && left != _lastHapticBeat) {
      _lastHapticBeat = left;
      HapticFeedback.lightImpact();
    }
  }

  TapRecorder _newRecorder() => TapRecorder(
    steps: _bars * widget.project.spb,
    loopBars: _loopBars,
    loopSec: _loopSec,
    snap: _snapOf(_stageDef),
    latencySec: _kTouchLatencySec,
    spb: widget.project.spb,
  );

  void _startRec() => _rec = _newRecorder();

  void _finishLap(double pos) {
    _rec?.closeAll(pos);
    // 한 판을 **실제로 쳐 봤다** = 이 악기의 손짓을 알았다 — 첫 안내는 다시 안 띄운다.
    if ((_rec?.hits().isNotEmpty ?? false) || _rollSteps.isNotEmpty) {
      DoodleHints.markSeen(_coachKey);
      _coachForce = false;
    }
    widget.host?.holdOff(-1);
    setState(() {
      _pending = _rec?.hits() ?? const [];
      _reviewing = true;
    });
    // **방금 친 것을 바로 들려준다**(사용자 요청, 2026-09-22: "재생 미리듣기").
    // 여태는 리뷰 화면에 "5번 쳤어요" 같은 숫자만 뜨고, 「사용하기」를 눌러야만
    // `_commit()`이 돌아 씬에 얹혔다 — 「다시 녹음 vs 사용하기」를 귀가 아니라
    // 숫자로 판단해야 했다. `_commit()`은 `_pending`/`_rollSteps`를 **통째로
    // 다시 쓰는** 함수라(드럼은 `clear()` 뒤 다시 채움, 베이스·코드는 `const []`를
    // 이전 목록 삼아 새로 지음) 여기서 미리 불러도, 나중에 「사용하기」에서 다시
    // 불러도 결과가 같다 — 두 번 부르는 것이 안전하다.
    _commit();
    final h = widget.host;
    if (h != null) _refreshLoop(h);
    // 리뷰 화면 진입 — "지금 들려주는 중" 표시를 깜빡이기 시작한다.
    _startReviewBlink();
  }

  /// 이 단계의 판을 **빈 상태로 되돌린다** — 미리듣기로 심어 둔 것을 다시
  /// 녹음하기 전에 지운다. 드럼은 **이 레인만**(다른 레인은 앞 단계에서 이미
  /// 확정된 것이니 손대지 않는다), 베이스·코드는 판 전체를 비운다 — `initState`가
  /// 처음 들어올 때 비우는 것과 같은 모양이다.
  void _blankStage() {
    switch (_stageDef.kind) {
      case DoodleKind.drum:
        final lane = _stageDef.drumLane!;
        _ops.steps[lane]?.clear();
        _ops.vels[lane]?.clear();
        widget.project.putUserPattern(
          'drum',
          _drumPatternName,
          drum: _ops.toDef(_drumPatternName, _bars),
        );
      case DoodleKind.bass:
        _bassSnap = null;
        _bassNotes = const [];
        widget.project.putUserPattern(
          'bass',
          _bassPatternName,
          note: NotePatternDef(_bassPatternName, _bars, _bars, const [],
              spb: widget.project.spb),
        );
      case DoodleKind.chord:
        _chordNotes = const [];
        widget.project.putUserPattern(
          'chord',
          _chordPatternName,
          note: NotePatternDef(_chordPatternName, _bars, _bars, const [],
              spb: widget.project.spb),
        );
        // 코드가 비었으니 이미 친 베이스는 기본 진행으로 되돌린다.
        _repitchBass();
    }
  }

  // ── 두드리기 ── 이 화면은 늘 판 하나("악기 하나")만 활성화한다 — 손가락은 늘 pad 0.

  /// 지금 이 칸에 흐르는 코드의 도수 — 베이스는 그 코드의 뿌리음(지시서
  /// 28번: "TAP → 현재 추천 음"), 코드 단계는 화음 그 자체(지시서 29번:
  /// "TAP → 현재 추천 코드")로 쓴다. `tap_sheet.dart`의 `_sound()`와
  /// 같은 계산이다.
  int _degreeAt(int step, {required String type, required bool chord}) {
    final (prog, progSteps) = _prog();
    return tapDegree(
      prog: prog,
      progSteps: progSteps,
      step: step,
      type: type,
      chord: chord,
      chromatic: false,
      mode: widget.transport.mode,
    );
  }

  /// 이 단계에 음 높이가 있는가 — 드럼만 없다(타악은 옮길 높이가 없다).
  bool get _hasPitch => _stageDef.kind != DoodleKind.drum;

  /// 좌우로 음을 고를 수 있는 단계인가 — **베이스만**이다.
  ///
  /// 코드 단계에서도 좌우를 읽던 때가 있었는데, 코드 줄의 첫 칸은 도수가
  /// 아니라 **코드 번호**(`buildChordPattern` 이 `% chords.length` 로 읽는다)라
  /// 거기 3·5·7도를 더하면 아예 다른 코드가 적혔다 — 친 소리(Am)와 적힌
  /// 것(전혀 다른 코드)이 달랐다. 코드의 표현은 대신 **두께**(손가락 수)가 맡는다.
  bool get _hasTone => _stageDef.kind == DoodleKind.bass;

  /// 지금 쓸 코드 진행 — 코드 단계에서 친 것이 있으면 그것, 없으면 들어올
  /// 때 챙겨 둔 원래 진행.
  (List<ProgSlot>, int) _prog() {
    final (prog, steps) = widget.project.readSceneProg();
    if (prog.isNotEmpty) return (prog, steps);
    if (_priorProg.isNotEmpty) return (_priorProg, _priorProgSteps);
    // 빈 프로젝트로 시작하면 원래 진행이 없다 — 코드를 아직 안 쳤어도 베이스가
    // 한 음짜리가 되지 않게 **미리 깔아 둔 진행**을 따라 걷게 한다.
    final spb = widget.project.spb;
    return ([
      for (var b = 0; b < _basePlan.length; b++)
        ProgSlot(_basePlan[b].degree, b * spb, (b + 1) * spb, meter: _meter),
    ], _basePlan.length * spb);
  }

  /// 이 단계의 격자 — **하이햇만 16분**, 나머지는 8분.
  ///
  /// 여태 `_newRecorder()` 가 `snap` 을 안 넘겨 전부 8분(`TapSnap.eighth`,
  /// 2칸 단위)으로 굳어 있었다. 16분 하이햇을 치면 두 방이 같은 칸으로
  /// 반올림되고, `TapRecorder._hits` 가 `'판:칸'` 키라 **뒤엣것이 앞엣것을
  /// 덮어써서** 친 것이 조용히 사라졌다. 8분이 기본인 데는 이유가 있으니
  /// (`tap_rec.dart` 머리말: "친 대로 들리는 쪽이 정확한 쪽보다 낫다")
  /// 잘게 치는 것이 당연한 하이햇만 올린다.
  TapSnap _snapOf(DoodleStage s) =>
      (s.kind == DoodleKind.drum && s.drumLane == 'hat')
      ? TapSnap.sixteenth
      : TapSnap.eighth;

  /// **꾹 눌러 굴리는 것이 이 악기에 뜻이 있는가** (사용자 지적, 2026-09-22:
  /// "킥에서 누르고있으면 연타하는 기능이 왜 필요하니").
  ///
  /// 맞는 말이다. 악기마다 손이 하는 일이 다르다:
  ///  · **킥** — 굴릴 일이 거의 없다. 킥은 *몇 번*이 아니라 **어디**가 전부다.
  ///    16분 연타는 메탈의 더블 페달이지 이 앱이 만드는 음악이 아니다.
  ///  · **스네어** — 필인이 곧 롤이다. 마지막 반 마디를 굴리는 것이 기본기다.
  ///  · **하이햇** — 16비트 자체가 굴리는 것이다. 격자도 여기만 16분이다.
  ///
  /// 그래서 킥에서는 꾹 눌러도 **한 방**이다. 안내 문구도 그에 맞춰 갈린다.
  bool get _canRoll =>
      _stageDef.kind == DoodleKind.drum && _stageDef.drumLane != 'kick';

  /// 손짓으로 정해진 것들을 **음 줄에 한꺼번에 얹는다.**
  ///
  /// `tapToNotes` 는 박자만 담는 함수라 세기를 늘 2로 적고 높이도 그 칸의
  /// 기본음으로만 적는다. 여기서 칸 번호로 맞춰 갈아 끼운다.
  /// 행 모양은 `[도수, 칸, 길이, 세기, 글라이드·코드종류, 층, 전위]`.
  ///
  /// **베이스와 코드가 다섯째 칸을 서로 다르게 읽는다** — 낱음 줄은
  /// `n[4]==1` 을 "앞 음에서 미끄러짐"으로(`buildRowsPattern`), 코드 줄은
  /// `n[4] is String` 을 "코드 종류"로(`buildChordPattern`) 읽는다. 그래서
  /// [chord] 로 갈라 둔다.
  ///
  /// 코드 줄에는 **좌우로 고른 음을 절대 더하지 않는다.** 코드 줄의 첫 칸은
  /// 도수가 아니라 **코드 번호**(`% chords.length` 로 읽힌다)라, 거기 3·5·7도를
  /// 더하면 친 것과 전혀 다른 코드가 적힌다 — 들린 Am 이 다른 코드로 저장됐다.
  ///
  /// **일곱째 칸(`n[6]`)은 전위다** — `_voicingOf[step]`(그 칸을 쳤을 때의
  /// `_voicing`)을 그대로 못 박는다. 여섯째 칸(층·`voiceLead` 의 `oct`)은
  /// 이 화면에서 안 쓰므로 늘 비운다 — 다른 화면(편집기의 다중 코드 트랙
  /// 층 나누기)이 쓰는 자리라 건드리면 그쪽이 깨진다.
  List<List<Object?>> _decorate(
    List<List<Object?>> rows, {
    required bool chord,
    _TakeMaps? maps,
  }) {
    // [maps] 를 주면 **그 판을 칠 때 모아 둔 손짓**으로 적는다(베이스 음높이 다시 얹기) —
    // 안 주면 지금 판의 것.
    final m = maps ?? _TakeMaps(_velOf, _toneOf, _glideAt, _staccatoAt);
    return [
      for (final r in rows)
        () {
          final step = r[1] as int;
          final len = m.stac.contains(step) ? 1 : r[2];
          final vel = m.vel[step] ?? r[3];
          if (chord) {
            // 도수·종류는 **마디 단위**로 정리한다 — 그 마디에 깔린 코드 + 그 마디
            // **착지 탭**의 색. 탭마다 색이 다르면 한 마디 안에서 들쭉날쭉해진다.
            final bar = _barOf(step);
            final pick = _cp.pickAt(bar);
            final ty = doodleChordText(_key, pick, _cp.colorOf(bar));
            // 전위 칸은 **비운다** — 재생(`buildChordPattern`)이 `voiceLead` 로 앞 코드와
            // 공통음을 살려 잇는다. 연주 중에도 같은 함수로 잇는다(`_chordDown`).
            // 기타를 **톡** 쳐서(뮤트첩) 짧게 끊은 칸은 여리게 적는다 — 재생도 「척」으로 나게.
            final vel = m.stac.contains(step) && isMuteVoice(_chordTrack.voice)
                ? kMuteVel
                : 2;
            return <Object?>[pick.degree, step, len, vel, ty, null];
          }
          // 낱음 줄(베이스) — **소리 낼 때 쓴 바로 그 함수**로 도수를 구한다.
          // `tapToNotes` 가 적어 둔 `r[0]` 은 좌우·옥타브를 모르는 기본음이다.
          // 여기서 따로 더하면 clamp 순서가 달라져 소리와 갈린다(전에 그랬다).
          final deg = _writeDegree(step, m.tone[step] ?? 0);
          final glide = m.glide.contains(step) ? 1 : null;
          if (glide == null) return <Object?>[deg, step, len, vel];
          return <Object?>[deg, step, len, vel, glide];
        }(),
    ];
  }

  /// **가운데를 치면 세게, 가장자리를 치면 여리게.**
  ///
  /// 세기를 재는 방법을 세 번 바꿨다. 압력은 이 폰이 손가락 세기와 무관하게
  /// 늘 같은 값을 줘서 못 썼고(2026-09-21 확인), 그다음 「위를 치면 세게」로
  /// 옮겼는데 사용자가 직관적이지 않다고 했다 — **맞는 지적이다. 실제 악기에
  /// 그런 것이 없다.** 드럼을 위쪽에서 친다고 커지지 않는다. 순수 암기였다.
  ///
  /// 진짜 드럼은 **한가운데를 때리면 꽉 차고 가장자리를 치면 여리다.** 그래서
  /// 화면 한가운데의 동그라미를 그대로 과녁으로 쓴다. 여태 그 동그라미는
  /// 아무 기능 없는 장식이었다 — 보이는 것과 하는 일이 이제 같아졌다.
  ///
  /// 세 칸의 크기는 min(폭,높이) 기준 비율이라 어느 기기에서나 같은 느낌이다.
  ///
  /// 경계(`_kHardR`·`_kSoftR`)에서는 **직전 탭의 구역을 기억**해(`_velCtr`, 히스테리시스) 손이
  /// 살짝 흔들려도 세게↔보통이 오락가락하지 않는다.
  int _velFromCenter(Offset at, Size area, {int? nowMs}) {
    final m = area.width < area.height ? area.width : area.height;
    if (m <= 0) return 2;
    final dx = at.dx - area.width / 2, dy = at.dy - area.height / 2;
    final r = math.sqrt(dx * dx + dy * dy) / m;
    // 구역 0=한가운데(악센트 3) · 1=그 바깥(보통 2) · 2=가장자리(고스트 1)
    final band = _velCtr.read(
      r,
      nowMs ?? DateTime.now().millisecondsSinceEpoch,
      slop: kBandSlopPx / m,
    );
    return 3 - band;
  }

  /// 한가운데(세게) 구역의 반지름 — min(폭,높이) 대비.
  /// 화면에 그려지는 190px 동그라미와 같은 크기로 맞춘다.
  static const double _kHardR = 0.24;

  /// 드럼 세기 — 악기마다 축이 다르다(2026-09-29 (12)).
  ///  · **킥**: 세로 = 고스트(아래, 여리게 1)↔정타(위). 정타의 세기는 가로(오른쪽이 셈, 2~3).
  ///  · **하이햇**: 세로가 롤 밀도라 세로로 세기를 못 읽는다 → 가로(왼쪽 여리게↔오른쪽 세게).
  ///  · **스네어**: 여태처럼 한가운데가 세게, 가장자리가 여리게.
  int _drumVel(Offset at, Size area, {int? nowMs}) {
    final t = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    switch (_stageDef.drumLane) {
      case 'kick':
        // 고스트 경계도 직전 탭을 기억한다 — 경계에 걸친 킥이 세게↔고스트로 튀지 않게.
        if (area.height > 0 &&
            _ghost.read(at.dy / area.height, t, slop: kBandSlopPx / area.height) == 1) {
          return 1;
        }
        final v = _velFromX(at.dx, area.width, nowMs: t);
        return v < 2 ? 2 : v;
      case 'hat':
        return _velFromX(at.dx, area.width, nowMs: t);
      default:
        return _velFromCenter(at, area, nowMs: t);
    }
  }

  /// 킥에서 이 세로 위치(0=위, 1=아래)보다 아래를 치면 **고스트**(여리게).
  static const double _kGhostFrac = 0.68;

  /// 하이햇 세로 3구역(`kHat16Zone`·`kOpenHatZone`, doodle_gestures.dart): 위 = 16비트 롤,
  /// 가운데 = 8비트 롤, 아래 = 오픈. 롤 도중 위로 밀면 16분으로 올라간다(필인).
  /// 32분·셋잇단은 못 넣는다 — 드럼 판이 16분 칸 격자라 저장이 안 된다(친 소리 = 적힌 음).

  /// 이 손가락의 하이햇 구역 — 경계 되돌림 포함(읽기 전용, 상태는 `_tickRoll`·`_pressMove` 가 갱신).
  int _hatBandOf(_Finger f) => hatBandSticky(
    f.frac,
    prev: f.hatBand ?? hatBandSticky(f.downFrac),
    slop: _area.height <= 0 ? 0 : kBandSlopPx / _area.height,
  );

  /// **베이스 전용 세기 — 가로(x)로 읽는다.**
  ///
  /// 베이스는 세로가 이미 사다리(음 높이, `_rowFromY`)라 `_velFromCenter`
  /// 처럼 세로 자리로 세기를 읽으면 두 뜻이 한 축에서 부딪힌다(사용자 지적,
  /// 2026-09-24: "세로가 음높이라 세기를 자리로 못 읽는다" → "가로축으로
  /// 읽어라"). 가로는 사다리가 안 쓰는 축이라 안 겹친다. **왼쪽이 여리게,
  /// 오른쪽이 세게** — `_velFromCenter`와 같은 1~3 눈금을 가로 폭 3등분으로
  /// 준다.
  ///
  /// 1/3·2/3 경계에서는 **직전 탭의 구역을 기억**한다(`_velX`, 히스테리시스 `kBandSlopPx`) —
  /// 엄지 살이 경계에 걸쳐 빠르게 연타할 때 세기가 1·2·1·2 로 튀던 것을 막는다.
  int _velFromX(double dx, double width, {int? nowMs}) {
    if (width <= 0) return 2;
    final t = (dx / width).clamp(0.0, 1.0);
    return _velX.read(
          t,
          nowMs ?? DateTime.now().millisecondsSinceEpoch,
          slop: kBandSlopPx / width,
        ) +
        1; // 0 왼쪽=여리게(1) · 1 가운데=보통(2) · 2 오른쪽=세게(3)
  }

  /// 여기서부터 바깥은 여리게.
  ///
  /// **0.44는 너무 좁았다**(사용자 지적, 2026-09-22: "아무 데나 쳐도 됩니다"라고
  /// 안내하면서 실제로는 안 그랬다). 이 화면은 원이 아니라 위아래로 긴 사각형을
  /// 치는 자리로 쓰는데, `r`은 **짧은 변**(보통 가로) 기준이라 세로로 조금만
  /// 벗어나도 r이 금방 0.44를 넘었다 — 예컨대 가로 400·세로 600짜리 화면에서
  /// 화면 위아래 끝(가운데서 세로로만 300 떨어진 자리)조차 r=0.75로 이미
  /// "가장자리(고스트)"였다. 화면 대부분이 약하게만 나는데 안내는 "아무 데나"라
  /// 말이 안 맞았다. 0.85로 넓혀 **실제 모서리에 가까운 곳만** 여리게로 남긴다.
  static const double _kSoftR = 0.85;

  /// **세로 사다리로 음 고르기**(베이스 전용) — 아래가 낮은 음, 위가 높은 음.
  ///
  /// 여태는 **좌우**로 1·3·5·7도를 골랐는데 사용자가 직관적이지 않다고 했다.
  /// 옳은 지적이다 — 「3도」는 악보를 아는 사람의 말이고, 이 앱의 첫 규칙은
  /// 악보를 몰라도 되는 것이다. 게다가 그 구역은 눈에 거의 안 보였다.
  ///
  /// **「높은 음은 위」는 배울 필요가 없는 유일한 음악 상식**이다. 그래서
  /// 화면을 가로줄 다섯 칸으로 나누고 띠로 보여 준다. 고르는 것은 여전히
  /// 그 칸 코드 안의 음뿐이라(`_kLadderTone`) 무엇을 눌러도 안 틀린다.
  ///
  /// 이러면 「좌우 = 도수」도 「위아래 쓸기 = 옥타브」도 한꺼번에 없어진다 —
  /// 사다리가 이미 한 옥타브를 덮고, **세로축의 뜻이 하나로 정리된다**(전에는
  /// 세로 위치가 세기, 세로 이동이 옥타브라 둘이 싸웠다).
  ///
  /// [from] 을 주면 그 칸에서 나올 때만 바뀐다(히스테리시스) — 경계에 걸친
  /// 손가락이 두 음 사이를 덜덜 떠는 것을 막는다.
  ///
  /// 처음 닿을 때도 [from] 에 **직전 탭의 칸**을 주면(시간 안이면) 경계에 걸친 톡이 옆 칸으로 새지 않는다.
  int _rowFromY(double dy, double height, {int? from}) {
    if (height <= 0) return 0;
    final h = height / _kLadderRows;
    // 화면 좌표는 **위가 작은 값**이라 뒤집는다 — 맨 아래 칸이 0(제일 낮은 음).
    var r = (_kLadderRows - 1 - (dy / h).floor()).clamp(0, _kLadderRows - 1);
    if (from != null && r != from) {
      final top = (_kLadderRows - 1 - from) * h;
      if (dy > top - _kZoneSlop && dy < top + h + _kZoneSlop) r = from;
    }
    return r;
  }

  /// 사다리 칸 수.
  static const int _kLadderRows = 5;

  /// 칸 번호 → 그 코드 안에서 몇 도 위인가. 뿌리·3도·5도·7도·한 옥타브 위.
  static const List<int> _kLadderTone = [0, 2, 4, 6, 7];

  /// 구역 경계에서 이만큼 더 나가야 넘어간 것으로 본다 — `kSlideSlopPx`.
  static const double _kZoneSlop = kSlideSlopPx;

  /// 사다리에서 **지나온 칸이 밝게 남는 시간**(ms) — 미끄러뜨리기(`_slideTo`)
  /// 궤적을 보여 준다. 물결(`_kRippleMaxMs`)보다 살짝 짧게 둬 너무 오래 안 끈다.
  static const int _kLadderTrailMs = 260;

  /// 손가락이 닿았다 — **누른 동안 계속 나는 소리**로 낸다(HOLD).
  /// 드럼만 예외로 톡 치는 한 방이다(타악은 잡고 있을 것이 없다).
  void _pressDown(PointerDownEvent e, Size area) {
    final pointer = e.pointer;
    final at = e.localPosition;
    _area = area;
    // **어느 대목이든 소리는 바로 낸다.** 예전엔 녹음(rec) 중이 아니면 여기서
    // 그냥 돌아가서, 대기·미리 세기 동안(길면 6초) 눌러도 소리도 화면도
    // 아무 반응이 없었다 — 사용자에겐 "눌러도 안 되는 화면"으로 보인다.
    // 담는 것만 녹음 중에 하고, 들려주는 것은 늘 한다.
    //
    // **베이스는 한 손가락만.** 단선율 악기라 두 음이 동시에 찍히면 의도치 않은
    // 화음 베이스가 된다 — 손이 스치거나 무심코 두 손가락으로 짚기만 해도
    // 그랬다(제스처 검수에서 잡음). 사용자 방침도 "웬만하면 한 손가락"이다.
    // **코드도 한 손가락만**(2026-09-29 (12): 한 엄지 원핸드 — 손가락 수로 코드
    // 두께를 재던 것을 없앴다). 여럿이 닿으면 **가장 먼저 닿은 하나만** 받는다.
    // 드럼만 두 손 번갈아 연타가 뜻이 있어 여러 개를 받는다.
    final maxFingers = (_hasTone || _stageDef.kind == DoodleKind.chord)
        ? 1
        : _kMaxFingers;
    if (_fingers.containsKey(pointer)) return;
    if (_fingers.length >= maxFingers) {
      // 막혔다 — 베이스·코드는 한 손가락만 받는다. 아무 반응이 없으면 "안 눌렸나?"
      // 하고 더 세게 누르게 되므로 손끝으로 "받지 않았다"를 알린다(무반응은
      // 버그로 친다). 물결은 안 그린다 — 소리가 안 났는데 친 것처럼 보이면 거짓.
      if (maxFingers == 1) HapticFeedback.heavyImpact();
      return;
    }
    final pos = _clock.pos(_loopSec);
    final cs = _clockState;
    // 대목 판정을 **이 손가락이 닿은 시각의 위치**로 한 번 더 굴린다 — 30ms 시계 틱이 아직
    // 미리 세기로 보고 있는 판 머리 바로 뒤 몇 ms 에 친 첫 박이 버려지지 않게(녹음 시작 직후 탭).
    if (cs != null && !_ordering && !_reviewing && !_allDone && _loopSec > 0) {
      final was = cs.phase;
      cs.update(pos * _loopBars * _meter.clicksPerBar);
      if (was != TapPhase.rec && cs.phase == TapPhase.rec) _startRec();
    }
    final recording = cs != null && cs.phase == TapPhase.rec;
    final rec = _rec;
    // 손가락마다 판(pad)을 따로 준다 — 같은 판을 쓰면 두 번째 손가락이
    // 첫 번째가 누르고 있던 것을 닫아 버린다.
    final used = {for (final f in _fingers.values) f.pad};
    var pad = 0;
    while (used.contains(pad) && pad < _kMaxFingers - 1) {
      pad++;
    }
    final now = DateTime.now();
    final nowMs = now.millisecondsSinceEpoch;
    // 베이스는 **세로가 이미 음 높이**(사다리)라 세기를 세로 자리로 못
    // 읽는다. 그래서 **가로**를 쓴다(사용자 지시, 2026-09-24: "가로축으로
    // 세기를 읽어라") — 왼쪽이 여리게, 오른쪽이 세게. 사다리(세로)와 안 겹친다.
    // 코드는 세기 **균일**(2) — 좌우·상하가 다른 뜻(진행·색)을 가져갔다.
    final vel = _stageDef.kind == DoodleKind.chord
        ? 2
        : (_hasTone
              ? _velFromX(at.dx, area.width, nowMs: nowMs)
              : _drumVel(at, area, nowMs: nowMs));
    // 사다리 칸도 직전 탭이 시간 안이면 그 칸을 「출발 칸」으로 쓴다 — 경계에 걸친 톡의 히스테리시스.
    final zone = _hasTone
        ? _rowFromY(
            at.dy,
            area.height,
            from: nowMs - _lastRowMs <= kStickyMs ? _lastRow : null,
          )
        : 0;
    if (_hasTone) {
      _lastRow = zone;
      _lastRowMs = nowMs;
    }
    final tone = _hasTone ? _kLadderTone[zone] : 0;
    final step = rec?.stepOf(pos) ?? 0;
    final f = _Finger(
      pad: pad,
      downX: at.dx,
      downY: at.dy,
      downAt: now,
      vel: vel,
      zone: zone,
      step: step,
      frac: area.height <= 0 ? 0.5 : (at.dy / area.height).clamp(0.0, 1.0),
    );
    _fingers[pointer] = f;
    if (_hasTone) _rowVisitAt[zone] = now; // 사다리 궤적 — 첫 자리도 한 번 밝힌다.
    if (recording) {
      rec?.down(pad, pos);
      _velOf[step] = vel;
      if (tone != 0) _toneOf[step] = tone;
    }
    switch (_stageDef.kind) {
      case DoodleKind.drum:
        final lane = _stageDef.drumLane!;
        final laneKit = _kitOfLane(lane);
        if (lane == 'kick' && doodleBoomKit(laneKit)) {
          // **808 붐** — 누르는 동안 서브가 유지되고, 뗄 때 누른 만큼(`boomTailFor`) 울다 진다
          // (`_pressUp`). 표본 킷(어쿠스틱·록)은 붐이 합성 킥으로 바뀌므로 한 방만 친다.
          f.boomHeld = true;
          widget.host?.drumHoldOn(_kHoldId + pad, laneKit, vel);
        } else {
          widget.host?.drumOn(laneKit, lane, vel);
        }
        // 타악은 길이가 없다 — 그 자리에 한 칸.
        if (recording) rec?.up(pad, pos);
        // 붙이고 있으면 **롤**이 돈다 — 단, `_canRoll` 인 악기만.
        // 실제 연타는 `_tickRoll` 이 앞질러 예약한다(30ms 화면 시계로 내면
        // 덜컹거린다). 여기서는 시작 시각만 잡아 둔다.
        if (_canRoll) {
          f.rollNext = now.add(const Duration(milliseconds: _kRollAfterMs));
        }
      case DoodleKind.bass:
        f.freq = _bassFreq(step, tone);
        widget.host?.holdOn(_kHoldId + pad, _bassTrack.voice, f.freq, vel);
      case DoodleKind.chord:
        _chordDown(step, at, area, f, recording: recording);
    }
    _hapticHit(vel);
    setState(() {
      _addRipple(at, vel, now: now, dir: f.dir, color: f.color);
    });
  }

  /// [at] 에서 퍼지는 타격 물결을 하나 더한다. 오래된 것은 같이 치운다.
  /// 악기(레인)는 이 순간의 단계에서 읽는다 — 물결 모양이 악기마다 다르다(`_HitFxPainter`).
  void _addRipple(
    Offset at,
    int vel, {
    required DateTime now,
    bool roll = false,
    String? lane,
    int dir = 0,
    int color = 0,
  }) {
    _ripples.removeWhere(
      (r) => now.difference(r.born).inMilliseconds > _kRippleMaxMs,
    );
    _ripples.add(
      _Ripple(
        at,
        vel.clamp(1, 3),
        now,
        roll: roll,
        lane: lane ?? _instKey,
        dir: dir,
        color: color,
      ),
    );
    _wakeFx();
  }

  /// 프레임 그림을 깨운다 — 이미 돌고 있으면 아무 일도 안 한다.
  void _wakeFx() {
    if (!_fxTicker.isActive) _fxTicker.start();
  }

  /// 프레임마다 — 그림을 다시 그리고, 할 일이 없으면(손도 물결도 구역 번쩍임도 없음) 멈춘다.
  void _onFx(Duration _) {
    _fx.poke();
    final now = DateTime.now();
    final live = _fingers.isNotEmpty ||
        _ripples.any((r) => now.difference(r.born).inMilliseconds <= _kRippleMaxMs) ||
        (_flashAt != null &&
            now.difference(_flashAt!).inMilliseconds <= _kZoneFlashMs);
    if (!live && _fxTicker.isActive) _fxTicker.stop();
  }

  /// 햅틱·물결이 쓰는 악기 이름 — 드럼은 레인, 나머지는 종류.
  String get _instKey => switch (_stageDef.kind) {
    DoodleKind.drum => _stageDef.drumLane ?? 'kick',
    DoodleKind.bass => 'bass',
    DoodleKind.chord => 'chord',
  };

  /// 이 단계의 첫 안내 카드를 기억하는 이름 — 드럼은 레인별로.
  String get _coachKey => _instKey;

  /// 친 세기에 맞는 손끝 되울림(사용자 요청, 2026-09-22: "타격 햅틱 추가") —
  /// 화면 잔물결(시각) 하나로만 "쳤다"를 확인해야 했다. 리듬을 탈 때는 화면을
  /// 안 보므로(힌트 문구도 그렇게 적혀 있다) 손끝 신호가 있어야 한다. 롤(연타)
  /// 도중에는 여기를 안 거친다 — `_tickRoll`이 따로, **상태가 바뀌는 순간에만**
  /// 한 번 울린다(계속 울리면 드르륵거려 더 나쁘다).
  ///
  /// 2026-09-30 (A): 세기만이 아니라 **악기도** 본다 — 킥은 묵직(heavy), 스네어·코드·베이스는
  /// 중간(medium), 하이햇은 짧고 가볍게(light·똑). 규칙은 `doodleHaptic`(시험이 직접 잰다).
  /// 친 소리의 무게와 손끝의 무게가 같은 방향이어야 "쳤다"가 산다.
  void _hapticHit(int vel) => _fireHaptic(doodleHaptic(_instKey, vel));

  void _fireHaptic(DoodleHaptic h) {
    void go() {
      switch (h) {
        case DoodleHaptic.heavy:
          HapticFeedback.heavyImpact();
        case DoodleHaptic.medium:
          HapticFeedback.mediumImpact();
        case DoodleHaptic.light:
          HapticFeedback.lightImpact();
        case DoodleHaptic.tick:
          HapticFeedback.selectionClick();
      }
    }

    // 소리는 버퍼를 지나 늦게 닿는다 — 필요하면 진동도 그만큼 미룬다(기본 0 = 즉시).
    if (kHapticDelayMs > 0) {
      Timer(const Duration(milliseconds: kHapticDelayMs), go);
    } else {
      go();
    }
  }

  /// 그 칸 · 그 도수의 베이스 주파수. **들리는 음과 적히는 음이 같아야 하므로**
  /// 소리 낼 때와 판에 적을 때가 같은 계산을 쓴다(아래 `_writeDegree`).
  double _bassFreq(int step, int tone) {
    final key = MusicKey(root: widget.transport.root, mode: widget.transport.mode);
    final degree = _writeDegree(step, tone);
    // 도수로 이미 옥타브를 올려 뒀으면(`_writeDegree`) 배수를 또 곱하지 않는다.
    return degreeFreq(degree, 'bass', key);
  }

  /// 판에 **적힐** 도수 — 좌우로 고른 음과 옥타브를 한 자리에서 셈한다.
  ///
  /// 예전엔 소리 낼 때는 `(도수 + 좌우).clamp()`, 적을 때는 `+7*옥타브` 뒤에
  /// 다시 `+좌우` 로 **clamp 순서가 달라서** 둘이 갈렸다. 한 함수로 묶어
  /// 「친 소리 = 적힌 음」을 구조적으로 보장한다.
  ///
  /// 베이스 도수는 0~6(제일 아래 옥타브)이라 **아래로 갈 자리가 없다** —
  /// `-7` 하면 전부 0 으로 뭉개진다(시험으로 확인: {0,3,4,5} → {0}).
  /// 그래서 베이스의 옥타브는 0/+1 두 칸뿐이다(`_pressMove` 에서 막는다).
  int _writeDegree(int step, int tone) {
    final base = _degreeAt(step, type: 'bass', chord: false);
    // `_voicing` 은 코드 단계 전용 쓸기로만 바뀐다(`_pressMove` 의 `!_hasTone`
    // 분기) — 베이스는 그 분기를 안 타니(사다리로 일찍 빠진다) 여기서는 늘 0.
    return (base + tone).clamp(0, kMaxDegree);
  }

  MusicKey get _key =>
      MusicKey(root: widget.transport.root, mode: widget.transport.mode);

  /// 칸 → 마디 번호(판 안).
  int _barOf(int step) => step ~/ widget.project.spb;

  /// 판을 새로 시작한다 — 깔아 둔 기본 진행으로 되돌리고 손짓 기록을 비운다.
  void _resetChordPlan() {
    _cp.reset();
    _lastSpec = null;
    _lastDir = 0;
    _landBar = -1;
    _landPos = null;
    _prevVoiced = doodleVoiceSeed(_key, _cp.base);
  }

  /// 코드 한 방 — **탭 = 리듬, 세기는 균일.** 어느 코드인지는 그 마디에 깔린 진행이,
  /// 색은 **탭 순간의 세로 위치**가 정한다(즉시 들린다). 좌우는 소리를 안 바꾸고
  /// 뒤 마디의 진행만 바꾼다 — 그 마디 **마지막 탭**의 자리가 남는다.
  void _chordDown(
    int step,
    Offset at,
    Size area,
    _Finger f, {
    required bool recording,
  }) {
    final bar = _barOf(step);
    final pick = recording ? _cp.pickAt(bar) : _cp.plan[bar.clamp(0, _cp.plan.length - 1)];
    // 방향(좌·중·우 3구역)과 색(위·아래)은 경계에서 **직전 탭을 기억**한다(히스테리시스) —
    // 「마지막 탭이 다음 마디를 정한다」라서 경계에 걸친 탭이 반대쪽으로 읽히면 진행이 뒤집힌다.
    // 세로 경계는 엄지가 닿는 가운데 쪽으로 내렸다(`kChordColorSplit`).
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final dir = area.width <= 0
        ? 0
        : chordDirOfBand(
            _dirBand.read(
              (at.dx / area.width).clamp(0.0, 1.0),
              nowMs,
              slop: kBandSlopPx / area.width,
            ),
          );
    final color = area.height <= 0
        ? 0
        : chordColorOfBand(
            _colorBand.read(
              (at.dy / area.height).clamp(0.0, 1.0),
              nowMs,
              slop: kBandSlopPx / area.height,
            ),
          );
    f.dir = dir;
    f.color = color;
    _flashAt = DateTime.now();
    _flashDir = dir;
    _flashColor = color;
    var spec = doodleChordSpec(_key, pick, color);
    // 록 기타의 파워코드 — 재생(`buildChordPattern` 의 plainType)과 같은 규칙.
    // 종류를 안 적은 자리(=담백)만 스타일이 정한다.
    final plain = doodleChordText(_key, pick, color) == null
        ? genreChordType(widget.project.genre, _chordTrack.voice)
        : null;
    if (plain != null) {
      spec = ChordSpec(root: spec.root, type: plain);
    }
    // **친 소리 = 재생.** 기타/나일론은 바레 모양(자리바꿈 없음), 나머지는 `voiceLead` —
    // 앞 코드와 공통음을 살리고 움직임을 최소로(음역 G3~F#4 라 베이스와 안 엉킨다).
    final isGuitar = _chordTrack.voice == 'guitar' || _chordTrack.voice == 'nylon';
    final List<int> voicedMidi;
    if (isGuitar) {
      voicedMidi = guitarChordMidi(spec);
    } else {
      voicedMidi = voiceLead(
        chordMidiOf(spec),
        _prevVoiced.isEmpty ? null : _prevVoiced,
      );
      _prevVoiced = voicedMidi;
    }
    // **잡고 있는 소리로 낸다.** 예전엔 `batch` 로 8초짜리 한 방을 냈는데,
    // `batch` 는 번호가 없어서 `holdOff` 로 못 끊는다.
    for (var i = 0; i < _kMaxChordTones; i++) {
      widget.host?.holdOff(_kChordId + i);
    }
    // **패드/스트링 스웰** — 화면 아래에서 닿으면 작게 시작해 **위로 그을수록** 차오른다
    // (`_pressMove` 가 `setSwell`). 스웰은 코드 버스(`kSwellBus`)에 걸리므로, 라이브 전용
    // 버스(`kPartLive`)로 내면 안 걸린다 — 스웰 음색은 코드 버스로 낸다.
    final swellVoice = isSwellVoice(_chordTrack.voice);
    if (swellVoice &&
        area.height > 0 &&
        _swellBand.read(
              (at.dy / area.height).clamp(0.0, 1.0),
              nowMs,
              slop: kBandSlopPx / area.height,
            ) ==
            1) {
      f.swell = true;
      widget.host?.setSwell(kSwellBus, kSwellStart, smoothSec: 0.005);
    }
    for (var i = 0; i < voicedMidi.length && i < _kMaxChordTones; i++) {
      widget.host?.holdOn(
        _kChordId + i,
        _chordTrack.voice,
        midiFreq(voicedMidi[i]),
        2,
        part: swellVoice ? kPartChord : kPartLive,
      );
    }
    _lastSpec = spec;
    _lastDir = dir;
    // 이 탭이 **지금 마디의 착지 탭**이다 — 다음에 치면 이 자리가 덮어써진다.
    _landBar = bar;
    _landPos = at;
    if (recording) {
      // 마지막에 친 탭이 이긴다 — 덮어쓰면 그게 곧 착지 탭이다.
      _cp.recordTap(bar, dir: dir, color: color);
    }
  }

  /// 손가락이 움직였다.
  ///
  /// **베이스**는 세로가 사다리(음 높이)라, 칸을 넘으면 그 음으로
  /// **미끄러진다**. 옥타브 쓸기는 없다 — 사다리가 그 자리를 가져갔고,
  /// 한 축에 두 뜻을 얹으면 사람이 구분해서 움직일 수 없다.
  ///
  /// **코드**는 움직임을 안 읽는다 — 닿은 순간의 자리가 전부다(`_chordDown`).
  void _pressMove(int pointer, Offset at, Size area) {
    final f = _fingers[pointer];
    if (f != null && area.height > 0) {
      f.frac = (at.dy / area.height).clamp(0.0, 1.0);
    }
    if (f != null) {
      f.curX = at.dx;
      f.curY = at.dy;
    }
    if (area.width > 0) _area = area;
    if (f == null || f.swiped || !_hasPitch) return;
    final dx = at.dx - f.downX;
    final dy = at.dy - f.downY;
    if (dx.abs() > _kStaccatoSlop || dy.abs() > _kStaccatoSlop) f.moved = true;

    if (_hasTone) {
      // ── 사다리를 타고 미끄러진다 ──
      final r = _rowFromY(at.dy, area.height, from: f.zone);
      if (r == f.zone) return;
      f.zone = r;
      _slideTo(f, r);
      return;
    }

    // ── 코드: 움직임은 (스웰 말고는) 소리를 안 바꾼다 ──
    // 스웰 손가락이면 올라온 만큼 코드 버스를 차오르게 한다. 손이 멈추면 값도 그대로 남는다.
    if (f.swell) {
      widget.host?.setSwell(
        kSwellBus,
        swellLevel(f.downY, at.dy, area.height, deadPx: kSwellDeadPx),
      );
    }
    // 좌우·상하는 **닿은 순간의 자리**로 읽는다(`_chordDown`) — 즉시 들려야 하고,
    // 쓸기를 기다리면 리듬이 늦는다. 전위 쓸기는 없앴다(2026-09-29 (12)).
  }

  /// 미끄러뜨려 다음 음으로 — 소리는 앞 주파수에서 이어 붙이고(`glideF`),
  /// 판에는 다섯째 칸에 1 을 적는다. 재생 쪽(`buildRowsPattern` 의 `n[4]==1`)이
  /// 같은 방식으로 앞 음에서 미끄러뜨리므로 **친 소리와 재생이 일치한다.**
  void _slideTo(_Finger f, int zone) {
    // 지나온 칸을 남긴다(시각 궤적만 — 소리·판정과 무관) — `_toneLadder`가
    // `_kLadderTrailMs` 동안 이 칸을 잠깐 밝힌다.
    _rowVisitAt[zone] = DateTime.now();
    final cs = _clockState;
    final recording = cs != null && cs.phase == TapPhase.rec;
    final pos = _clock.pos(_loopSec);
    final rec = _rec;
    final step = rec?.stepOf(pos) ?? f.step;
    final tone = _kLadderTone[zone];
    final from = f.freq;
    final freq = _bassFreq(step, tone);
    widget.host?.holdOn(
      _kHoldId + f.pad,
      _bassTrack.voice,
      freq,
      f.vel,
      glideF: from,
    );
    f.freq = freq;
    HapticFeedback.selectionClick();
    if (!recording) return;
    if (step == f.step) {
      // 같은 칸 안에서 미끄러졌다 — 쪼개면 `TapRecorder` 가 '판:칸' 키로
      // 덮어써서 **앞 토막이 사라진다.** 음은 그대로 두고 높이만 갈아 끼운다.
      _toneOf[step] = tone;
      return;
    }
    // 칸이 넘어갔다 — 앞 음을 여기서 닫고 새 음을 연다.
    rec?.up(f.pad, pos);
    rec?.down(f.pad, pos);
    f.step = step;
    _velOf[step] = f.vel;
    _toneOf[step] = tone;
    _glideAt.add(step);
  }

  /// 손가락을 뗐다 — 그 자리까지가 음의 길이다(HOLD).
  void _pressUp(int pointer) {
    final f = _fingers.remove(pointer);
    if (f == null) return;
    final cs = _clockState;
    final recording = cs != null && cs.phase == TapPhase.rec;
    final pos = _clock.pos(_loopSec);
    final heldMs = DateTime.now().difference(f.downAt).inMilliseconds;
    final heldSec = heldMs / 1000.0;
    // 베이스: **오래 잡았으면 잡은 만큼 꼬리**(808 서브 붐). 톡 친 것은 악기 원래 릴리스.
    widget.host?.holdOff(
      _kHoldId + f.pad,
      tailSec: _stageDef.kind == DoodleKind.bass && heldSec >= kBassBoomAfterSec
          ? boomTailFor(heldSec)
          : 0,
    );
    // 킥: 누른 만큼 서브가 울다 진다.
    if (f.boomHeld) {
      widget.host?.drumHoldOff(_kHoldId + f.pad, tailSec: boomTailFor(heldSec));
    }
    if (_stageDef.kind == DoodleKind.chord && _fingers.isEmpty) {
      // **뮤트첩** — 기타를 아주 짧게 떼면 줄을 덮어 「척」(꼬리를 바로 자른다).
      final mute = isMuteStrum(voice: _chordTrack.voice, heldMs: heldMs, moved: f.moved);
      for (var i = 0; i < _kMaxChordTones; i++) {
        widget.host?.holdOff(_kChordId + i, tailSec: mute ? kMuteTailSec : 0);
      }
    }
    // 스웰 손가락이 떼졌다 — 다음 코드·다른 트랙이 작게 들리지 않게 서서히 원래 크기로.
    if (f.swell) widget.host?.setSwell(kSwellBus, 1.0, smoothSec: 0.5);
    if (!f.swiped && recording) {
      _rec?.up(f.pad, pos);
      // **톡** 치면 짧게 — 시간 축이라 어느 손짓과도 안 겹친다.
      // `lenOf` 의 바닥값이 격자 한 단위(8분이면 2칸)라, 이게 없으면 아무리
      // 톡 쳐도 전부 8분이 되어 스타카토 베이스를 아예 못 만든다.
      if (_hasPitch && !f.moved && heldMs < _kStaccatoMs) {
        _staccatoAt.add(f.step);
      }
    }
    setState(() {});
  }

  /// 꾹 누르고 있는 드럼 손가락에 **연타**(롤)를 앞질러 예약한다.
  ///
  /// 화면 시계(30ms)로 그때그때 소리를 내면 간격이 들쑥날쑥해 롤이 아니라
  /// 덜컹거림이 된다. 그래서 `drumBatch` 의 `delaySec` 로 **엔진에 시각까지
  /// 맡긴다.** 예약 창을 짧게(0.12초) 두는 이유는, 길면 손을 뗀 뒤에도 예약된
  /// 것이 계속 나서 "화면이 안 먹는다"가 되기 때문이다.
  /// **롤 굵기** — 누른 **세기**로 고른다(사용자 지시, 2026-09-24: "누른
  /// 세기나 세로 위치로 8분/16분을 고르게" → 세로는 이미 다른 악기와
  /// 판이 다르지만 세기는 `_velFromCenter`가 이미 모든 드럼에서 자리로
  /// 재고 있으므로 그대로 쓴다). **여리게(가장자리, vel 1~2)=8분,
  /// 세게(한가운데, vel 3)=16분** — 세게 칠수록 촘촘하게, 실제 타법과
  /// 롤 밀도가 같이 간다. 반환값은 **16분 칸 수**다(1=16분, 2=8분) —
  /// 격자 시간(`_stepSec * unit`)과 기록 칸 번호(`k * unit`)를 한 값으로
  /// 같이 구할 수 있게.
  int _rollUnit(int vel) => vel >= 3 ? 1 : 2;

  void _tickRoll() {
    final h = widget.host;
    if (h == null || _stageDef.kind != DoodleKind.drum) return;
    if (_fingers.isEmpty || _loopSec <= 0) return;
    if (_stepSec <= 0) return;
    final now = DateTime.now();
    final pos = _clock.pos(_loopSec);
    final tInLoop = pos * _loopSec;
    final cs = _clockState;
    final recording = cs != null && cs.phase == TapPhase.rec;
    final steps = _bars * widget.project.spb;
    final lane = _stageDef.drumLane!;
    final hits = <List<dynamic>>[];
    for (final f in _fingers.values) {
      var next = f.rollNext;
      if (next == null) continue;
      // **오픈 하이햇** — 하이햇을 꾹(180ms) 누르고 있는데 손이 아래 구역이면 롤이 아니라
      // 한 번 「지잉」(`hatopen`). 위쪽이면 예전처럼 16분 롤이다. 미리 예약하지 않고
      // **실제로 180ms 를 채운 뒤에** 낸다 — 톡 친 손가락(60~90ms)이 오픈이 되면 안 되므로.
      // 경계(`kOpenHatZone`)는 **처음 닿은 자리를 기억**한다 — 롤을 하려고 위쪽에 닿았는데 손이
      // 살짝 내려와 경계를 스치기만 해도 오픈으로 뒤집히던 것을 막는다(`hatHoldOpensSticky`).
      if (lane == 'hat' &&
          !f.rolled &&
          !f.openFired &&
          hatHoldOpensSticky(
            downFrac: f.downFrac,
            frac: f.frac,
            slop: _area.height <= 0 ? 0 : kBandSlopPx / _area.height,
          )) {
        if (now.isBefore(next)) continue;
        f.openFired = true;
        f.rollNext = null;
        hits.add([_kitOfLane('hatopen'), 'hatopen', f.vel, 180.0, 0.0]);
        HapticFeedback.selectionClick(); // 「열렸다」 — 상태가 바뀌는 순간 한 번
        _addRipple(Offset(f.downX, f.downY), 3, now: now, roll: true, lane: 'hatopen');
        continue;
      }
      // 아직 롤이 시작될 때가 아니다(180ms 전에 떼면 그냥 한 방이다).
      if (next.isAfter(now.add(Duration(milliseconds: (_kRollAheadSec * 1000).round())))) {
        continue;
      }
      // 이 손가락의 롤 굵기 — 누른 세기로 이미 정해졌다(`_pressDown`이 잰
      // `f.vel`). 롤 도중 세기를 바꾸는 손짓은 없으니 손가락마다 한 번 고르면 된다.
      final int unit;
      if (lane == 'hat') {
        // 하이햇은 **지금 손가락의 세로 위치**가 밀도다(롤 도중 위로 밀면 촘촘해진다).
        // 8분↔16분 경계도 되돌림이 있다 — 처음엔 닿은 자리, 그 뒤엔 직전 밀도를 기억한다.
        // 롤이 이미 돌기 시작한 뒤 오픈 구역까지 내려가도 오픈으로 바꾸지 않고 8비트로 둔다.
        var band = _hatBandOf(f);
        if (band == kHatBandOpen) band = kHatBand8;
        if (f.hatBand != null && f.hatBand != band) {
          HapticFeedback.selectionClick(); // 밀도가 바뀐 순간만 한 번
        }
        f.hatBand = band;
        unit = hatRollUnit(band);
      } else {
        unit = _rollUnit(f.vel);
      }
      final grid = _stepSec * unit;
      // 롤은 **격자에 맞춰** 돈다 — 기계가 내는 소리라 정확할 수 있고,
      // 격자에서 벗어나면 되레 어긋난 것으로 들린다.
      var guard = 0;
      while (next!.difference(now).inMicroseconds / 1e6 <= _kRollAheadSec &&
          guard++ < 8) {
        final ahead = next.difference(now).inMicroseconds / 1e6;
        // 지금부터 다음 격자까지 남은 시간.
        final k = ((tInLoop + (ahead > 0 ? ahead : 0)) / grid).ceil();
        final gridT = k * grid;
        // `tInLoop` 은 **들리는** 자리인데 이 delay 는 **렌더 시계**에 얹힌다
        // (`_sendMet` 과 같은 함정). 빼 주지 않으면 롤이 버퍼 한 통만큼 늦게
        // 들리는데 판에는 격자에 정확히 찍혀서, 연주 중 귀와 「사용하기」 뒤
        // 재생이 서로 다르다. 칸 번호(`st`)는 그대로 둔다 — 그쪽이 맞다.
        var delay = gridT - tInLoop - _buffered / 48000.0;
        // 이미 지나간 격자는 **건너뛴다.** 0 으로 밀면 앞으로 튀어 박이 겹친다.
        if (delay < 0) {
          next = now.add(
            Duration(microseconds: ((gridT - tInLoop + grid) * 1e6).round()),
          );
          continue;
        }
        if (delay > _kRollAheadSec) break;
        // **롤로 넘어간 순간**을 손끝으로 한 번만 알린다(사용자 요청, 2026-09-22:
        // "타격 햅틱 추가") — 한 방을 친 건지 롤이 도는 건지 HOLD 글자 말고는
        // 구분할 길이 없었다. `f.rolled`가 상태 깃발이라 이 손가락이 쥐고 있는
        // 동안 한 번만 울린다(계속 울리면 드르륵거려 더 나쁘다).
        if (!f.rolled) {
          f.rolled = true;
          HapticFeedback.selectionClick();
          // 롤로 넘어간 자리에서 큰 물결 한 번 — 충전 링이 다 차는 순간의 "터짐".
          _addRipple(Offset(f.downX, f.downY), 3, now: now, roll: true);
        }
        // 첫 한 방보다 살짝 여리게 — 진짜 롤이 그렇다.
        // **크레셴도** — 롤 도중 손을 처음 자리에서 오른쪽으로 밀수록(폭의 1/4마다 한 단계)
        // **지금 X 로** 세기가 오른다(가로 = 세기 그대로). 밀지 않으면 예전과 같다.
        final base = f.vel > 1 ? f.vel - 1 : 1;
        // 단계 경계도 되돌림(`rollBumpSticky`) — 폭의 1/4 선에서 손이 떨려도 세기가 안 튄다.
        // 단계가 **올라간** 순간만 손끝으로 한 번 알린다(상태가 바뀌는 순간에만).
        final bump = rollBumpSticky(
          f.curX - f.downX,
          _area.width,
          f.rollBump,
          slop: kBandSlopPx,
        );
        if (bump > f.rollBump) HapticFeedback.selectionClick();
        f.rollBump = bump;
        final rv = rollVelOfBump(base, bump);
        hits.add([_kitOfLane(lane), lane, rv, 180.0, delay]);
        // **도는 중 표시**(사용자 지시, 2026-09-24) — 이 연타가 실제로 들릴
        // 시각을 남겨 두면, 화면(`_rollFlashing`)이 그 시각 바로 뒤 짧은
        // 창에서 패드를 깜빡여 "지금 격자에 맞춰 돌고 있다"를 보여 준다.
        f.flashAt = now.add(Duration(microseconds: (delay * 1e6).round()));
        if (recording) {
          // 격자 번호(`k`)에 굵기(`unit`)를 곱하면 16분 칸 번호가 된다 —
          // **기록도 연주와 같은 간격으로 찍힌다**(연주=기록 일치, 사용자
          // 지시). 기계가 낸 시각이라 `TapRecorder`(사람 반응 지연을 되돌리는
          // 계산)를 안 거친다.
          final st16 = k * unit;
          final st = ((st16 % steps) + steps) % steps;
          _rollSteps.add(st);
          _velOf[st] = rv;
        }
        next = now.add(
          Duration(microseconds: ((delay + grid) * 1e6).round()),
        );
      }
      f.rollNext = next;
    }
    if (hits.isNotEmpty) h.drumBatch(hits);
  }

  void _retake() {
    // 미리듣기로 씬에 얹어 둔 것을 지운다 — 안 지우면 재녹음하는 동안 앞
    // 테이크가 라이브 타격 소리와 겹쳐 들린다.
    _blankStage();
    // 비운 단계는 "완성" 집계에서도 뺀다 — 재확정 전까지는 안 채워진 것이다.
    _keptStages.remove(_stage);
    _savedStages.remove(_stage);
    setState(_armStage);
    // 다시 녹음도 **씬 머리에서** 시작한다 — 단계 전환과 같은 결. 안 되감으면
    // 앞서 확정된 악기들이 씬 중간부터 들리다가 미리 세기가 붙어 자리가 튄다.
    // `_rewindLoop` 이 `_blankStage` 로 비운 판까지 실어 새 루프를 만든다.
    _rewindLoop();
  }

  /// 진행 표시(✓●○)를 눌러 **아무 단계로나** 건너뛴다(사용자 지시,
  /// 2026-09-24: "킥에서 바로 하이햇·코드로 갈 수 있게" — 예전엔 순서를
  /// 강제해서 못 눌렀다).
  ///
  /// 지금 치던 것은 **잃지 않는다** — 열려 있던 음을 그 자리에서 닫아
  /// (`_rec.closeAll`) 판에 반영한 뒤 `_commit()`한다. 단, **이번 방문에서
  /// 실제로 친 것이 있을 때만** 커밋한다 — 안 그러면 아무것도 안 친 채
  /// 잠깐 들렀다 나가는 것만으로 지난 방문에서 이미 씬에 남은 것을 빈
  /// 판으로 덮어써 버린다(`_commit()`은 `_pending`을 판 전체로 삼는다).
  void _gotoStage(int i) {
    if (_ordering || i == _stage || i < 0 || i >= _stages.length) return;
    final pos = _clock.pos(_loopSec);
    _rec?.closeAll(pos);
    final hits = _rec?.hits() ?? const <TapHit>[];
    final playedSomething = hits.isNotEmpty ||
        (_stageDef.kind == DoodleKind.drum && _rollSteps.isNotEmpty);
    if (playedSomething) {
      _pending = hits;
      _commit();
      _savedStages.add(_stage);
    }
    setState(() {
      _stage = i;
      _armStage();
    });
    // 새 단계도 씬 처음부터 — 단계 전환(`_keep`)과 같은 결.
    _rewindLoop();
  }

  /// **그만하고 나가기.** 이미 「사용하기」로 넘긴 단계는 씬에 남아 있고,
  /// 지금 치던 판만 버려진다 — 그걸 그대로 적어서 알려 준다.
  ///
  /// 다 끝냈으면 묻지 않고 바로 나간다(물어볼 것이 없다).
  Future<void> _confirmExit() async {
    if (_allDone) {
      Navigator.of(context).pop();
      return;
    }
    // 「사용하기」로 **확정한** 단계들 — 지금 보는 번호(`_stage`)가 아니다.
    // 건너뛰기만 해도 번호는 올라가지만 씬에는 아무것도 안 남는다.
    final keptIdx = _keptStages.toList()..sort();
    final kept = keptIdx.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1C20),
        title: const Text('그만할까요?', style: TextStyle(color: Colors.white)),
        content: Text(
          kept == 0
              ? '아직 아무것도 안 남겼어요. 지금 나가면 이 씬은 그대로입니다.'
              : '$kept개(${keptIdx.map((i) => _stages[i].label).join(' · ')})는 '
                    '이미 씬에 남았어요.\n지금 치던 ${_stageDef.label}만 버려집니다.',
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('계속하기'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              '그만하기',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok == true && mounted) Navigator.of(context).pop();
  }

  /// 방금 친 것을 **판에 적는다.** 「사용하기」와 「다듬기」가 같이 쓴다 —
  /// 예전엔 「사용하기」에만 있어서, 치자마자 「다듬기」를 누르면 편집기가
  /// **빈 판**으로 열렸다(방금 친 게 아직 `_pending` 에만 있었다). 치고 나서
  /// 바로 고치고 싶은 것이 사람 마음인데 그때 빈 격자가 뜨면 친 게 날아간
  /// 줄 안다.
  void _commit() {
    switch (_stageDef.kind) {
      case DoodleKind.drum:
        final lane = _stageDef.drumLane!;
        _ops.steps[lane]?.clear();
        _ops.vels[lane]?.clear();
        // 손으로 친 칸 + **꾹 눌러 롤**로 들어온 칸. 롤은 기계가 낸 시각이라
        // `TapRecorder` 를 안 거치고 따로 모아 뒀다(`_tickRoll`). 같은 칸이
        // 겹치면 집합이라 한 번만 남는다.
        final steps = <int>{
          for (final ht in _pending) ht.step,
          ..._rollSteps,
        }.toList()..sort();
        for (final st in steps) {
          _ops.add(lane, st);
          // 친 세기를 그대로 얹는다 — `DrumOps.add` 는 레인·자리로 정해진
          // 기본 세기를 넣으므로, 손으로 친 것이 있으면 덮어쓴다.
          final v = _velOf[st];
          if (v != null) {
            final i = _ops.indexOf(lane, st);
            if (i >= 0) _ops.vels[lane]![i] = v;
          }
        }
        widget.project.putUserPattern(
          'drum',
          _drumPatternName,
          drum: _ops.toDef(_drumPatternName, _bars),
        );
      case DoodleKind.bass:
        // 친 리듬·세기·음 고르기를 **따로 간직**한다 — 코드 진행이 나중에 바뀌면
        // 음높이만 새 진행에 맞춰 다시 얹는다(`_repitchBass`, 순서 무관).
        _bassSnap = _BassTake(List.of(_pending), _TakeMaps.copyOf(_velOf, _toneOf, _glideAt, _staccatoAt));
        _bassNotes = _buildBassNotes(_bassSnap!);
        widget.project.putUserPattern(
          'bass',
          _bassPatternName,
          note: NotePatternDef(_bassPatternName, _bars, _bars, _bassNotes,
              spb: widget.project.spb),
        );
      case DoodleKind.chord:
        // 코드 단계는 **자기가 쓸 진행을 자기가 만든다** — 들어올 때 챙겨 둔
        // 원래 진행을 바탕으로 삼아, 안 친 칸은 원래 화성을 따라간다.
        final (prog, progSteps) = _prog();
        // **리듬 락(#9)** — 마지막으로 친 마디의 타격 리듬을 그 뒤 안 친 마디에 자동으로 반복한다
        // (친 마디는 친 대로, 첫 마디를 안 쳤으면 반복 없음). 톡(뮤트)도 같이 옮긴다.
        final (locked, lockFrom) = lockChordRhythm(
          _pending,
          spb: widget.project.spb,
          bars: _bars,
        );
        final lockMaps = _TakeMaps(_velOf, _toneOf, _glideAt, {
          ..._staccatoAt,
          for (final e in lockFrom.entries)
            if (_staccatoAt.contains(e.value)) e.key,
        });
        _chordNotes = _decorate(tapToNotes(
          const [],
          locked,
          prog: prog,
          progSteps: progSteps,
          steps: _bars * widget.project.spb,
          type: 'chord',
          chord: true,
          chromatic: false,
          mode: widget.transport.mode,
          // 층(`oct`)은 이 화면에서 안 쓴다 — 전위는 `_decorate` 가
          // `_voicingOf` 로 따로(일곱째 칸에) 적는다.
        ), chord: true, maps: lockMaps);
        widget.project.putUserPattern(
          'chord',
          _chordPatternName,
          note: NotePatternDef(_chordPatternName, _bars, _bars, _chordNotes,
              spb: widget.project.spb),
        );
        // 코드 진행이 확정/바뀌었다 — 이미 친 베이스를 **이 진행으로** 다시 얹는다.
        _repitchBass();
    }
  }

  // ── 시험용 손잡이 — 시계 없이 「한 판을 쳤다」를 흉내 내려고만 쓴다 ──

  @visibleForTesting
  void debugCommit(DoodleKind kind, List<TapHit> hits) {
    final i = _stages.indexWhere((s) => s.kind == kind);
    if (i < 0) return;
    _stage = i;
    _pending = hits;
    _commit();
  }

  @visibleForTesting
  void debugBlank(DoodleKind kind) {
    final i = _stages.indexWhere((s) => s.kind == kind);
    if (i < 0) return;
    _stage = i;
    _blankStage();
  }

  @visibleForTesting
  void debugTapChord(int bar, {required int dir, int color = 0}) =>
      _cp.recordTap(bar, dir: dir, color: color);

  @visibleForTesting
  List<List<Object?>> get debugBassNotes => _bassNotes;

  @visibleForTesting
  List<List<Object?>> get debugChordNotes => _chordNotes;

  /// 베이스 한 판을 [t] 의 리듬·세기로 **지금 진행**(`_prog()`)에 맞춰 적는다.
  List<List<Object?>> _buildBassNotes(_BassTake t) {
    final (prog, progSteps) = _prog();
    return _decorate(
      tapToNotes(
        const [],
        t.hits,
        prog: prog,
        progSteps: progSteps,
        steps: _bars * widget.project.spb,
        type: 'bass',
        chord: false,
        chromatic: false,
        mode: widget.transport.mode,
      ),
      chord: false,
      maps: t.maps,
    );
  }

  /// **코드 진행이 바뀌면 베이스를 그 진행으로 갱신한다**(순서 무관, 2026-09-29 (14)).
  /// 이미 친 베이스의 리듬·세기·길이·미끄러짐은 그대로, 음높이(도수)만 새 진행에 맞춘다.
  /// 코드가 아직 없으면 `_prog()` 가 깔아 둔 기본 진행을 돌려주므로 그대로 그것을 따른다.
  /// 베이스를 아직 안 쳤으면 아무것도 안 한다.
  void _repitchBass() {
    final t = _bassSnap;
    if (t == null || t.hits.isEmpty) return;
    _bassNotes = _buildBassNotes(t);
    widget.project.putUserPattern(
      'bass',
      _bassPatternName,
      note: NotePatternDef(_bassPatternName, _bars, _bars, _bassNotes,
          spb: widget.project.spb),
    );
  }

  void _keep() {
    final h = widget.host;
    _commit();
    _keptStages.add(_stage);
    _savedStages.add(_stage);
    if (_keptStages.length >= _stages.length) {
      // **모든 단계가 적어도 한 번은 확정됐다** — 자유 이동으로 순서가
      // 뒤섞여도 이걸로 "완성"을 잰다(자리 기준이 아니라 개수 기준).
      // 되감을 필요가 없다(다음 악기로 넘어가는 게 아니다). 확정한 것만 싣는다.
      if (h != null) _refreshLoop(h);
      _stopReviewBlink(); // 완성 화면으로 가니 리뷰의 깜빡임은 그만.
      setState(() => _allDone = true);
      return;
    }
    // 아직 안 찬 단계가 남았다 — **다음으로 안 찬 단계**로 간다(순서대로
    // 치는 사람에게는 예전과 똑같이 느껴진다). 자유 이동으로 먼저 갔다 온
    // 단계는 건너뛴다.
    var next = (_stage + 1) % _stages.length;
    while (_keptStages.contains(next) && next != _stage) {
      next = (next + 1) % _stages.length;
    }
    setState(() {
      _stage = next;
      _armStage();
    });
    // 새 악기가 씬 처음부터 흐르게 루프를 머리로 되감는다 —
    // `_rewindLoop` 이 방금 확정한 앞 악기까지 실은 새 루프를 만들고(그래서
    // 여기서 따로 `refreshLoop` 을 부르지 않는다) 재생 위치를 0으로 돌린다.
    _rewindLoop();
  }

  void _openEditor() {
    // 방금 친 것부터 판에 적고 연다 — 안 적으면 빈 격자가 뜬다.
    _commit();
    final h = widget.host;
    if (h != null) _refreshLoop(h);
    final track = switch (_stageDef.kind) {
      DoodleKind.drum => _drumTrack,
      DoodleKind.bass => _bassTrack,
      DoodleKind.chord => _chordTrack,
    };
    final title = switch (_stageDef.kind) {
      DoodleKind.drum => '드럼 다듬기',
      DoodleKind.bass => '베이스 다듬기',
      DoodleKind.chord => '코드 다듬기',
    };
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SafeArea(
            top: false,
            child: EditorView(
              project: widget.project,
              transport: widget.transport,
              track: track,
              host: widget.host,
            ),
          ),
        ),
      ),
    );
  }

  // ── 그리기 ──

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 연주 도중 실수로 뒤로 나가 방금 것을 잃지 않게 — 명시적으로만 나간다
      // (지시서 32번: "실수로 다른 악기로 넘어가는 일이 없어야 한다").
      //
      // **다만 막기만 하면 안 된다** (2026-09-22 실기기에서 잡았다): 여태
      // `canPop:false` 뿐이라 X 도 뒤로가기도 아무 일을 안 했다 — 다섯 단계를
      // 다 끝내기 전에는 **나갈 길이 아예 없었다.** 게다가 이 화면에 있는 동안은
      // 씬의 다른 트랙을 재워 두므로, 갇힌 사람이 앱을 강제 종료하면 `dispose`
      // 의 복구가 안 돌고 자동 저장이 **음소거된 채로** 파일에 쓴다.
      // 그래서 이제는 묻고 나간다. **순서 정하기 화면은 예외**다 — 아직 아무것도
      // 안 쳤으니 잃을 것이 없다. 묻지 않고 바로 나가게 둔다.
      canPop: _allDone || _ordering,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmExit();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF101114),
        body: SafeArea(
          child: _ordering
              ? _orderBody()
              : (_allDone ? _doneBody() : (_reviewing ? _reviewBody() : _playBody())),
        ),
      ),
    );
  }

  // ── 순서 화면의 악기 고르기 (2026-09-29 (16)) ──
  //
  // 단계마다 **음색(코드·베이스)·킷(드럼)** 을 고른다. 고른 값은 **트랙 자체**(`Track.voice`/
  // `Track.kit`)에 쓴다 — 연주(`_pressDown` 이 트랙에서 읽는다)·기록·씬 재생(`SceneSequencer` 도 트랙에서
  // 읽는다)이 한 곳을 보므로 「친 소리 = 저장된 소리 = 재생」이 구조적으로 같다. 씬에 남기지 않고
  // 나가면 `dispose` 가 원래 값으로 되돌린다.

  String _instrumentOf(DoodleStage s) => switch (s.kind) {
    DoodleKind.drum => _kitOfLane(s.drumLane ?? 'kick'),
    DoodleKind.bass => _bassTrack.voice,
    DoodleKind.chord => _chordTrack.voice,
  };

  String _instrumentLabel(DoodleStage s) => s.kind == DoodleKind.drum
      ? doodleKitLabel(_instrumentOf(s))
      : doodleVoiceLabel(_instrumentOf(s));

  List<String> _instrumentChoices(DoodleStage s) => doodleChoicesWith(
    switch (s.kind) {
      DoodleKind.drum => kDoodleDrumKits,
      DoodleKind.bass => kDoodleBassVoices,
      DoodleKind.chord => kDoodleChordVoices,
    },
    _instrumentOf(s),
  );

  /// [v] 를 그 단계의 악기로 삼는다. 드럼 세 단계(킥·스네어·하이햇)는 한 트랙이지만 **킷은 레인마다 따로**(`Scene.laneKits`) 고른다.
  void _setInstrument(DoodleStage s, String v) {
    if (_instrumentOf(s) == v) {
      _previewInstrument(s);
      return;
    }
    switch (s.kind) {
      case DoodleKind.drum:
        // 이 단계의 레인만 바꾼다 — 킥 단계에선 킥 킷만, 하이햇 단계에선 하이햇 킷만.
        final key = laneKitKey(s.drumLane ?? 'kick');
        if (v == _drumTrack.kit) {
          _origScene.laneKits.remove(key); // 기본 킷으로 돌아오면 덮어쓰기를 걷는다
        } else {
          _origScene.laneKits[key] = v;
        }
        _drumTrack.ping();
      case DoodleKind.bass:
        _bassTrack.voice = v;
      case DoodleKind.chord:
        _chordTrack.voice = v;
    }
    // 편성이 바뀌었다 — 이전 음색에 걸어 둔 스웰은 걷는다.
    widget.host?.clearSwell();
    _preloadSamples(); // 새로 고른 악기의 표본도 첫 타격 전에 읽어 둔다
    _previewInstrument(s);
    if (mounted) setState(() {});
  }

  /// 고른 소리를 **바로 들려준다** — 이름만 보고 고르면 어떤 소리인지 모른다.
  void _previewInstrument(DoodleStage s) {
    final h = widget.host;
    if (h == null) return;
    switch (s.kind) {
      case DoodleKind.drum:
        h.drumOn(_instrumentOf(s), s.drumLane ?? 'kick', 2);
      case DoodleKind.bass:
        h.noteOn(
          _bassTrack.voice,
          degreeFreq(0, 'bass', _key),
          0.6,
          2,
          part: kPartLive,
        );
      case DoodleKind.chord:
        final spec = doodleChordSpec(_key, _cp.base.first, 0);
        final guitar = isMuteVoice(_chordTrack.voice);
        final midi = guitar ? guitarChordMidi(spec) : chordMidiOf(spec);
        for (final m in midi) {
          h.noteOn(_chordTrack.voice, midiFreq(m), 0.9, 2, part: kPartLive);
        }
    }
  }

  Future<void> _pickInstrument(DoodleStage s) {
    final color = switch (s.kind) {
      DoodleKind.drum => DS.trackDrum,
      DoodleKind.bass => DS.trackBass,
      DoodleKind.chord => DS.trackChord,
    };
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1C20),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.kind == DoodleKind.drum ? '드럼 킷' : '${s.label} 악기',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  s.kind == DoodleKind.drum
                      ? '킥·스네어·하이햇이 한 킷을 같이 써요. 누르면 소리가 나요.'
                      : '누르면 소리가 나요. 고른 음색으로 치고, 저장하고, 재생해요.',
                  style: const TextStyle(color: Colors.white54, fontSize: 12.5),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final v in _instrumentChoices(s))
                      ChoiceChip(
                        key: ValueKey('inst-$v'),
                        label: Text(
                          s.kind == DoodleKind.drum
                              ? doodleKitLabel(v)
                              : doodleVoiceLabel(v),
                        ),
                        selected: _instrumentOf(s) == v,
                        selectedColor: color.withValues(alpha: 0.55),
                        labelStyle: const TextStyle(color: Colors.white),
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        onSelected: (_) {
                          _setInstrument(s, v);
                          setSheet(() {});
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// **순서 정하기** — 5단계를 드래그로 재배열한다(사용자 요청, 2026-09-22:
  /// "진행순서 변경가능하게"). 박 세기는 아직 안 돈다(`_startStages`가 눌려야
  /// `_armStage`가 불린다).
  ///
  /// 베이스가 코드보다 앞에 와도 **막지는 않는다** — `_prog()`가 이미 들어올 때
  /// 챙겨 둔 원래 진행(`_priorProg`)으로 자연스럽게 넘어가는 안전장치가 있다
  /// (`initState`의 `readSceneProg` 주석 참고). 다만 그 경우 베이스가 코드
  /// 단계에서 새로 정한 화성이 아니라 **원래 화성**을 따라간다는 것은 알려 준다.
  Widget _orderBody() {
    final bassIdx = _stages.indexWhere((s) => s.kind == DoodleKind.bass);
    final chordIdx = _stages.indexWhere((s) => s.kind == DoodleKind.chord);
    final bassBeforeChord =
        bassIdx >= 0 && chordIdx >= 0 && bassIdx < chordIdx;
    // **추천 상태** — 코드가 베이스보다 앞이면(기본 순서 그대로) 베이스가
    // 방금 친 화성을 따라간다(맨 위 `kDoodleStages` 주석 참고). 굳이 안
    // 바꿔도 된다는 것을 "추천" 배지로 알려 준다(이번 배치, B6).
    final chordRecommended =
        bassIdx >= 0 && chordIdx >= 0 && chordIdx < bassIdx;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 16, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: '나가기',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white54),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '칠 순서를 정하세요',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '손잡이를 끌어서 순서를 바꿀 수 있어요. 그대로 시작해도 됩니다.',
                style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            // `onReorderItem` 은 **이미 보정된** 새 자리를 준다(옛 `onReorder` 는
            // 빼기 전 기준이라 직접 -1 해야 했다 — song_view.dart와 같은 이유).
            onReorderItem: (oldIndex, newIndex) {
              setState(() {
                final s = _stages.removeAt(oldIndex);
                _stages.insert(newIndex, s);
              });
            },
            children: [
              for (var i = 0; i < _stages.length; i++)
                _OrderRow(
                  key: ValueKey(_stages[i]),
                  stage: _stages[i],
                  index: i,
                  instrument: _instrumentLabel(_stages[i]),
                  onPickInstrument: () => _pickInstrument(_stages[i]),
                  recommended:
                      chordRecommended && _stages[i].kind == DoodleKind.chord,
                ),
            ],
          ),
        ),
        if (bassBeforeChord)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 6),
            child: Text(
              '베이스를 코드보다 앞에 두면, 베이스는 지금 씬에 있던 화성을 따라가요 —\n'
              '나중에 코드에서 새로 친 것과 다를 수 있어요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.amber.withValues(alpha: 0.85),
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _startStages,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.tealAccent.shade400,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                '이 순서로 시작',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// [onRetake] 를 주면 오른쪽에 작은 "다시" 버튼이 뜬다 — 연주 화면
  /// (`_playBody`)에서만 쓴다(사용자 지시, 2026-09-24: "REC 중에도 다시
  /// 버튼을" — 여태는 리뷰 화면까지 가야만 다시 녹음할 수 있었다). **버튼**
  /// 이지 제스처가 아니다(사용자 지시) — 연주 자리(가운데 과녁·사다리)를
  /// 전혀 안 가리는 위쪽 띠에 둔다.
  Widget _header({VoidCallback? onRetake}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: '그만하고 나가기',
            onPressed: _confirmExit,
            icon: const Icon(Icons.close, color: Colors.white54),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  widget.project.genre.isEmpty
                      ? '내 곡'
                      : genreDef(widget.project.genre).label,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  '${widget.transport.bpm.round()} BPM',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
          if (onRetake != null && !_reviewing)
            IconButton(
              key: const ValueKey('doodle-coach-toggle'),
              tooltip: '손짓 안내 (안내가 떠 있으면 닫기)',
              onPressed: () {
                if (_coachForce || !DoodleHints.seen(_coachKey)) {
                  DoodleHints.markSeen(_coachKey);
                  setState(() => _coachForce = false);
                } else {
                  setState(() => _coachForce = true);
                }
              },
              icon: Icon(
                Icons.help_outline,
                size: 22,
                color: (_coachForce || !DoodleHints.seen(_coachKey))
                    ? Colors.white
                    : Colors.white54,
              ),
            ),
          if (onRetake != null)
            // 아이콘만 있으면 "되감기·다시 시작"인 줄 모른다 — 글자를 붙여 눈에 띄게
            // (감사 2026-09-29). 누르면 이 악기를 **처음부터 다시** 친다.
            TextButton.icon(
              onPressed: onRetake,
              icon: const Icon(Icons.replay, size: 18, color: Colors.white60),
              label: const Text(
                '다시',
                style: TextStyle(color: Colors.white60, fontSize: 13),
              ),
            )
          else
            const SizedBox(width: 48), // 왼쪽 닫기 버튼과 균형
        ],
      ),
    );
  }

  /// 진행 표시 — ✓(확정됨) · ●(지금) · ○(아직). 여태는 "메뉴가 아니라
  /// 진행 상황 표시"라 눌러도 안 움직였는데, 사용자 지시(2026-09-24:
  /// "킥에서 바로 하이햇·코드로 갈 수 있게")로 **눌러서 그 단계로 건너뛸 수
  /// 있다** — `_gotoStage`가 지금 치던 것을 커밋해 잃지 않고 옮긴다. ✓는
  /// 이제 "지나간 자리"가 아니라 "「사용하기」로 확정된 단계"를 뜻한다
  /// (`_keptStages`) — 자유 이동 중엔 자리와 확정 여부가 따로 논다.
  Widget _progress() {
    return Padding(
      // 위아래 14 → 10, 칸 안 세로 4 → 6: 칸(누르는 면)은 ≥44dp 로 키우고
      // 전체 높이는 그대로 둬 치는 자리(아래 Expanded)가 줄지 않게 했다.
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _stages.length; i++)
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _gotoStage(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  child: Column(
                    children: [
                      Icon(
                        _keptStages.contains(i)
                            ? Icons.check_circle
                            : i == _stage
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: _keptStages.contains(i) || i == _stage
                            ? Colors.tealAccent
                            : Colors.white38,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _stages[i].label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: i == _stage ? FontWeight.w800 : FontWeight.w500,
                          color: _keptStages.contains(i) || i == _stage
                              ? Colors.white70
                              : Colors.white38,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 단계마다 다른 색 — 씬·믹서 화면의 트랙 색과 **같은 값**을 쓴다(드럼
  /// 초록·베이스 파랑·코드 보라·가락 주황, `DS.trackDrum` 등). 여태는 이
  /// 화면만 따로 `Colors.lightGreenAccent` 같은 네온 계열을 써서, 같은
  /// 드럼인데 씬 화면(짙은 연두)과 두들플레이(형광 연두)가 다른 색으로
  /// 보였다 — 사용자가 "이게 그 악기 맞나" 다시 확인해야 했다(디자인 감사,
  /// 2026-09-29). `DS.*`로 맞춘다.
  Color _stageColor() => switch (_stageDef.kind) {
    DoodleKind.drum => DS.trackDrum,
    DoodleKind.bass => DS.trackBass,
    DoodleKind.chord => DS.trackChord,
  };

  /// **친 자리에서** 퍼지는 물결 + 꾹 누르는 손가락의 충전 링 + 스웰·크레셴도 진행 —
  /// 전부 **한 장의 그림**(`_HitFxPainter`)이다. 화면 전체가 치는 자리라(`Listener` 가 통째로 받는다)
  /// 화면 좌표로 그린다. 그림이 프레임마다(60fps) 다시 그려지므로 물결이 부드럽게 퍼진다.
  ///
  /// 세기 3단계가 눈으로 갈리게 크기·밝기 차를 키웠다 — 여리게 56 · 보통 96 · 세게 150px,
  /// 세게는 흰 코어 번쩍임과 두 겹 고리. 악기마다 모양도 다르다(킥=묵직한 채운 원·스네어=이중 고리·
  /// 하이햇=작고 빠른 불꽃·코드=방향 쐐기와 반짝임). 색은 그 단계의 트랙 색(`_stageColor`)이다.
  Widget _touchFx() => Positioned.fill(
    child: IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          key: const ValueKey('doodle-fx'),
          painter: _HitFxPainter(this, _fx),
        ),
      ),
    ),
  );

  /// 물결 하나가 사라지기까지(ms) — 세게일수록·킥일수록 오래, 하이햇은 짧고 빠르게.
  int _rippleLife(_Ripple r) {
    var ms = switch (r.vel) { 1 => 240, 2 => 320, _ => 440 };
    if (r.roll) ms = 460;
    if (r.lane == 'kick') ms = (ms * 1.2).round();
    if (r.lane == 'hat') ms = (ms * 0.75).round();
    return math.min(ms, _kRippleMaxMs);
  }

  @visibleForTesting
  int get debugLiveRipples {
    final now = DateTime.now();
    return _ripples.where((r) => now.difference(r.born).inMilliseconds <= _rippleLife(r)).length;
  }

  @visibleForTesting
  bool get debugFxActive => _fxTicker.isActive;

  /// 가장 최근 코드 탭의 (방향, 색) — 구역 번쩍임이 무엇을 가리켰는지.
  @visibleForTesting
  (int, int) get debugFlash => (_flashDir, _flashColor);

  @visibleForTesting
  List<String> get debugRippleLanes => [for (final r in _ripples) r.lane];

  static const Color _kCool = Color(0xFF6EA8FF), _kWarm = Color(0xFFFFB067);

  /// 좌우(진행 방향)·상하(색)가 뜻하는 것을 깐다(코드 단계만).
  ///  · 좌 1/3 찬색 = 긴장, 우 1/3 따뜻한색 = 해결, 가운데는 「그대로」.
  ///  · 세로는 **한가운데 한 줄**로 위(화려)·아래(담백) 두 구역 — 미세 조준이 없다.
  ///  · 이 마디의 **착지 방향 쪽이 진하게** 켜져 있다(마디가 넘어가면 꺼진다).
  /// 경계는 `doodleDirOfX`(1/3·2/3)·`doodleColorOfY`(1/2)와 같다 — 다르면 보이는 것과 나는
  /// 소리가 어긋난다.
  Widget _chordZones(Size area) {
    final dir = _curDir();
    Widget label(String t, Alignment a, {double alpha = 0.22}) => Align(
      alignment: a,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Text(
          t,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: alpha),
          ),
        ),
      ),
    );
    // 라벨의 세로 자리는 경계(`kChordColorSplit`)를 기준으로 두 구역 각각의 한가운데쯤.
    final upY = 2 * (kChordColorSplit * 0.36) - 1;
    final downY = 2 * (kChordColorSplit + (1 - kChordColorSplit) * 0.55) - 1;
    return IgnorePointer(
      child: Stack(
        children: [
          // 구역 색·경계선·맥박 치는 쐐기·탭 순간 번쩍임 — 한 장의 그림(60fps).
          // 「긴장 = 왼쪽 · 해결 = 오른쪽 · 위 = 화려 · 아래 = 담백」이 처음 보는 사람에게도 보이게
          // 옅은 띠가 아니라 **움직이는 화살표**로 알린다(감사 2026-09-30: 제스처 존재를 몰랐다).
          Positioned.fill(
            child: CustomPaint(
              key: const ValueKey('doodle-chord-zones'),
              painter: _ChordZonePainter(this, _fx),
            ),
          ),
          label('◀ 긴장', Alignment.centerLeft, alpha: dir < 0 ? 0.7 : 0.3),
          label('해결 ▶', Alignment.centerRight, alpha: dir > 0 ? 0.7 : 0.3),
          label('위 · 화려하게 (7th)', Alignment(0, upY)),
          label('아래 · 담백하게', Alignment(0, downY)),
          if (isSwellVoice(_chordTrack.voice))
            label('▲ 아래에서 위로 그으면 차올라요', const Alignment(0, 0.92), alpha: 0.32),
        ],
      ),
    );
  }

  /// **지금 마디의 착지 방향**(-1/0/+1) — 이 마디에서 마지막으로 친 탭의 쪽. 마디가 넘어가면
  /// 0(새 마디는 아직 착지가 없다).
  int _curDir() {
    final rec = _rec;
    final bar = rec == null ? 0 : _barOf(rec.stepOf(_clock.pos(_loopSec)));
    return _landBar == bar ? _lastDir : 0;
  }

  /// **착지 탭 표시** — 이 마디에서 마지막으로 친 자리에 고리를 남긴다. "지금 이 탭이 다음
  /// 코드를 정한다"가 눈에 보이게. 새로 치면 고리가 옮겨 간다.
  Widget _landMarker() {
    final at = _landPos;
    final dir = _curDir();
    if (_stageDef.kind != DoodleKind.chord || at == null || _landBar < 0) {
      return const SizedBox.shrink();
    }
    if (_landBar != _barNow()) return const SizedBox.shrink();
    final tone = dir < 0 ? _kCool : (dir > 0 ? _kWarm : Colors.white70);
    return Positioned(
      left: at.dx - 24,
      top: at.dy - 24,
      child: IgnorePointer(
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: tone.withValues(alpha: 0.9), width: 2.5),
          ),
          alignment: Alignment.center,
          child: Text(
            '착지',
            style: TextStyle(color: tone, fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }

  int _barNow() {
    final rec = _rec;
    return rec == null ? 0 : _barOf(rec.stepOf(_clock.pos(_loopSec)));
  }

  /// 코드 이름표 — **지금 코드 · 다음 코드 미리보기**. 다음 코드는 마지막으로 친 탭의 방향이
  /// 이대로 마디 끝에 확정될 때의 코드다(`DoodleChordPlan.previewNext`, 확정과 같은 값).
  Widget _chordBadge() {
    if (_stageDef.kind != DoodleKind.chord) {
      return const SizedBox(height: 44);
    }
    final bar = _barNow();
    final cur = _cp.plan[bar.clamp(0, _cp.plan.length - 1)];
    final spec = _lastSpec ?? doodleChordSpec(_key, cur, 0);
    final nextPick = _cp.previewNext(bar);
    final dir = _curDir();
    final nextName = nextPick == null
        ? '끝'
        : doodleChordName(doodleChordSpec(_key, nextPick, 0));
    final tone = dir < 0 ? _kCool : (dir > 0 ? _kWarm : _stageColor());
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 26,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: tone.withValues(alpha: dir == 0 ? 0.35 : 0.7)),
            ),
            child: Text(
              '지금 ${doodleChordName(spec)}  ·  다음 → $nextName',
              style: TextStyle(
                color: dir == 0 ? Colors.white70 : tone,
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            dir == 0 ? '마지막에 친 쪽이 다음 코드를 정해요' : (dir < 0 ? '긴장 쪽으로 이어져요' : '해결 쪽으로 이어져요'),
            style: const TextStyle(color: Colors.white38, fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  String _statusText(TapPhase phase) => switch (phase) {
    TapPhase.wait => '마디가 시작되면 시작할게요',
    TapPhase.count => '준비 — ${_clockState?.left ?? 0}',
    TapPhase.rec => 'REC',
    TapPhase.done => '',
  };

  Widget _playBody() {
    final cs = _clockState;
    final phase = cs?.phase ?? TapPhase.wait;
    final recording = phase == TapPhase.rec;
    final coachOn = _coachVisible(phase);
    return Column(
      children: [
        _header(onRetake: _retake),
        _progress(),
        // ── 치는 자리 = **화면에서 위아래 안내줄을 뺀 전부** ──
        //
        // 예전엔 190px 동그라미 안만 받았다. 악기를 치는 화면인데 과녁이
        // 작으면 조준부터 하게 된다(사용자: "화면은 UI칸 제외하고 전부 사용").
        // 동그라미는 이제 **과녁이 아니라 표시**다 — 아무 데나 치면 된다.
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final area = Size(box.maxWidth, box.maxHeight);
              // 첫 안내 카드는 **Listener 밖**에 얹는다 — 안에 두면 카드의 「알겠어요」 를 누를 때도
              // 드럼이 울린다. 카드 본문은 터치를 통과시키고(치는 자리를 안 가린다) 버튼만 받는다.
              // `StackFit.expand` 필수: 카드가 안 뜰 때 `SizedBox.shrink()`(위치 없는 자식)가 들어오면
              // Stack 이 그 크기(폭 0)로 줄어들어 안의 글자가 세로 기둥이 된다(2026-09-30 회귀).
              return Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (e) => _pressDown(e, area),
                onPointerMove: (e) => _pressMove(e.pointer, e.localPosition, area),
                onPointerUp: (e) => _pressUp(e.pointer),
                onPointerCancel: (e) => _pressUp(e.pointer),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 베이스는 **사다리**(세로 = 음 높이), 나머지는 **과녁**
                    // (가운데 = 세게). 한 화면에 한 가지 축만 둔다 — 세로
                    // 위치와 세로 이동에 서로 다른 뜻을 얹으면 손이 헷갈린다.
                    if (_hasTone)
                      _toneLadder()
                    else if (_stageDef.kind == DoodleKind.chord)
                      _chordZones(area)
                    else if (_stageDef.drumLane == 'kick' ||
                        _stageDef.drumLane == 'hat')
                      _drumZones(area)
                    else
                      _velTarget(area),
                    // 패드는 **「세게」 구역 그 자체**이고 화면 한가운데에 있다.
                    // 보이는 동그라미와 실제 과녁이 어긋나면 "가운데가 세게"가
                    // 그냥 거짓말이 된다(실기기에서 두 원이 따로 놀던 것을 보고
                    // 고쳤다). 베이스는 사다리가 악기라 패드를 안 그린다 —
                    // 없는 과녁을 그리면 거기를 치게 된다.
                    if (!_hasTone) _padCircle(area, phase, recording),
                    // 친 자리 물결·롤 충전 링 — 패드 위, 글자 아래. 화면 좌표라
                    // `Positioned` 로 그린다(전체가 치는 자리이므로).
                    _landMarker(),
                    // 이름·상태는 위, 안내는 아래 — **치는 자리를 안 가린다.**
                    Align(
                      alignment: Alignment.topCenter,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _stageDef.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          // 이 단계가 **무슨 악기이고 곡에서 무슨 일을 하는지** 한 줄 —
                          // 첫 진입에 "지금 뭘 하는 거지"가 안 남게(감사 2026-09-29).
                          Text(
                            _roleText(),
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _statusText(phase),
                            style: TextStyle(
                              color: recording
                                  ? Colors.redAccent
                                  : Colors.white54,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _chordBadge(),
                        ],
                      ),
                    ),
                    if (!coachOn)
                      Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          _hintText(),
                          textAlign: TextAlign.center,
                          // **녹음 전(대기·미리 세기)에는 안내를 또렷하게** — 이때가
                          // 손짓을 읽을 유일한 여유다. REC 가 시작되면 리듬을 타느라
                          // 어차피 안 보므로 원래 옅기로 물러난다.
                          style: TextStyle(
                            color: recording ? Colors.white54 : Colors.white70,
                            fontSize: recording ? 12 : 13.5,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                    ),
                  ),
                  _coachOverlay(phase),
                  // 물결·링은 **카드 위**에 그린다 — 카드 밑에서 치면 손끝 반응이 가려진다.
                  _touchFx(),
                ],
              );
            },
          ),
        ),
        _beatDots(cs),
        const SizedBox(height: 24),
      ],
    );
  }

  /// 좌우 음 구역 — 왼쪽부터 뿌리음·3도·5도·7도.
  ///
  /// 세기는 이제 **누르는 힘**으로 재므로(`_velFrom`) 자리로 알려 줄 것이
  /// 없어졌고, 대신 **좌우가 음을 고른다**는 것을 눈으로 알려 준다.
  /// 경계는 `_toneFromX` 와 같아야 한다 — 다르면 보이는 것과 나는 소리가
  /// 어긋난다.
  /// 방금 판에 **실제로 적힐 개수.**
  ///
  /// `_pending`(손으로 친 것)만 세면 안 된다 — 꾹 눌러 굴린 연타는
  /// `TapRecorder` 를 안 거치고 `_rollSteps` 에 따로 모이므로, 그것까지 세야
  /// 이 숫자가 「사용하기」를 누른 뒤 실제로 남는 것과 같아진다. 화면에 적힌
  /// 수와 실제가 다르면 그것 자체가 고장으로 보인다.
  String _playedText() {
    final n = _stageDef.kind == DoodleKind.drum
        ? <int>{for (final h in _pending) h.step, ..._rollSteps}.length
        : _pending.length;
    if (n == 0) return '아무것도 안 쳤어요';
    final rolled = _stageDef.kind == DoodleKind.drum && _rollSteps.isNotEmpty;
    return rolled ? '$n번 쳤어요 (굴린 것 포함)' : '$n번 쳤어요';
  }

  /// 단계 이름 밑 한 줄 — 이 악기가 곡의 뼈대에서 하는 일.
  /// 악보 말(도수·전위)을 안 쓴다: 이 앱의 첫 규칙이 "몰라도 된다"이다.
  String _roleText() => '${_roleBase()} · ${_instrumentLabel(_stageDef)}';

  String _roleBase() => switch (_stageDef.kind) {
    DoodleKind.drum => switch (_stageDef.drumLane) {
      'kick' => '곡의 심장박동 · 박의 바닥을 깔아요',
      'snare' => '박에 힘을 주는 탁 · 뒷박에 얹어요',
      'hat' => '박 사이를 잘게 채우는 째깍',
      _ => '드럼 한 줄',
    },
    DoodleKind.chord => '곡의 색깔 · 화음을 눌러 깔아요',
    DoodleKind.bass => '화음의 뿌리 · 낮게 받쳐 줘요',
  };

  // ── 첫 안내 카드 (2026-09-30, D. 발견성) ──
  //
  // 처음 그 악기를 만나면 **어떤 손짓이 있는지** 그림글자와 한 줄씩으로 알려 준다.
  //  · 카드 본문은 터치를 통과시킨다(`IgnorePointer`) — 치는 자리를 안 가린다. 받는 것은 버튼뿐.
  //  · 대기·미리 세기 동안만 뜬다. REC 가 시작되면 리듬을 타야 하니 사라진다(본 것으로 치진 않는다).
  //  · 머리줄 「?」 를 누르거나 그 악기를 실제로 한 판 쳐 보면 다시 안 뜬다(`DoodleHints`, 파일에 기억).
  //  · 「?」 로 언제든 다시 볼 수 있다.

  bool _coachVisible(TapPhase phase) =>
      !_ordering &&
      !_reviewing &&
      !_allDone &&
      phase != TapPhase.rec &&
      (_coachForce || !DoodleHints.seen(_coachKey));

  Widget _coachOverlay(TapPhase phase) {
    if (!_coachVisible(phase)) return const SizedBox.shrink();
    final tips = doodleCoachTips(
      _coachKey,
      swell: isSwellVoice(_chordTrack.voice),
      mute: isMuteVoice(_chordTrack.voice),
      boom: doodleBoomKit(_kitOfLane('kick')),
    );
    if (tips.isEmpty) return const SizedBox.shrink();
    final color = _stageColor();
    return Positioned(
      left: 12,
      right: 12,
      bottom: 8,
      // 카드 전체가 터치를 통과시킨다 — 버튼을 두면 엄지가 제일 편한 아래쪽 치는 자리를 가로챈다.
      // 닫는 길은 머리줄의 「?」 하나(누르면 이 악기 안내를 끈다)와 「한 판 쳐 보기」다.
      child: IgnorePointer(
        key: const ValueKey('doodle-coach'),
        child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              decoration: BoxDecoration(
                color: const Color(0xEB15171B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    height: 34,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${_stageDef.label} 손짓',
                        style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ),
                  for (final t in tips)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 24,
                            height: 24,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: color.withValues(alpha: 0.2),
                            ),
                            child: Text(
                              t.glyph,
                              style: TextStyle(
                                color: color,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              t.text,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Text(
                    '위쪽 ? 를 누르면 닫혀요 · 한 판 쳐 보면 다시 안 떠요',
                    style: TextStyle(color: Colors.white38, fontSize: 11.5),
                  ),
                ],
              ),
            ),
      ),
    );
  }

  /// 이 단계에서 **실제로 듣는 손짓만** 적는다. 안 쓰는 것까지 적어 두면
  /// 해 봤는데 아무 일도 안 일어나서 "고장 난 화면"으로 보인다.
  String _hintText() => switch (_stageDef.kind) {
    // **악기마다 다르게 적는다.** 못 하는 것을 적어 두면 해 보고 아무 일도
    // 안 일어나서 고장으로 보인다(킥에는 롤이 없다 — `_canRoll`).
    DoodleKind.drum =>
      _canRoll
          ? (_stageDef.drumLane == 'hat'
                ? '오른쪽일수록 세게 · 톡 치면 닫힌 하이햇\n'
                      '꾹 누르면(0.18초) 자리가 모드 — 위 16비트 롤 · 가운데 8비트 롤 · 아래 열린 하이햇 · 롤 중 위로 밀면 촘촘, 오른쪽으로 밀면 세져요'
                : '아무 데나 쳐도 됩니다 · 한가운데가 세게, 가장자리가 여리게\n'
                      '꾹 누르면 굴러갑니다 · 세게 누르면 16분, 여리게 누르면 8분으로 · 롤 중 오른쪽으로 밀면 점점 세져요')
          : '위쪽은 정타, 아래쪽은 고스트(여린 킥) · 오른쪽일수록 세게\n'
                '킥은 **어디에 놓는가**가 전부입니다 · 두 손가락으로 번갈아 쳐도 됩니다'
                '${doodleBoomKit(_kitOfLane('kick')) ? '\n길게 누르면 808 서브가 그만큼 웅— 울어요' : ''}',
    DoodleKind.bass =>
      '위로 갈수록 높은 음 · 오른쪽으로 갈수록 세게\n'
          '톡 치면 짧게, 잡으면 길게(오래 잡을수록 꼬리도 길게) · 잡은 채 위아래로 끌면 미끄러집니다',
    DoodleKind.chord =>
      '박자에 맞춰 톡톡 · 손가락 하나면 됩니다\n'
          '마디의 마지막 탭이 다음 코드를 정해요 — 왼쪽 긴장 · 오른쪽 해결 · 위 화려 · 아래 담백'
          '${isSwellVoice(_chordTrack.voice) ? '\n아래에서 위로 그으면 볼륨이 차올라요(스웰)' : ''}'
          '${isMuteVoice(_chordTrack.voice) ? '\n아주 짧게 톡 떼면 줄을 덮는 뮤트 「척」' : ''}'
          '\n한 마디만 쳐 두면 안 친 뒷마디에 그 리듬이 이어져요',
  };

  /// 킥·하이햇의 **세로 구역**을 옅게 깐다 — 킥: 아래 = 고스트.
  /// 하이햇: 위 = 16비트 롤 · 가운데 = 8비트 롤 · 아래 = 오픈(경계는 `kHat16Zone`·`kOpenHatZone`).
  /// 손가락이 닿아 있는 구역은 밝게 켜지고 글자도 또렷해진다(지금 어느 모드인지 즉시 보이게).
  Widget _drumZones(Size area) {
    final kick = _stageDef.drumLane == 'kick';
    Widget zone(double flex, String label, bool on, {bool top = false}) => Expanded(
      flex: (flex * 1000).round(),
      child: Container(
        alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: _stageColor().withValues(alpha: on ? 0.16 : 0.03),
          border: top
              ? null
              : Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: on ? 13 : 11,
            fontWeight: FontWeight.w800,
            color: Colors.white.withValues(alpha: on ? 0.75 : 0.20),
          ),
        ),
      ),
    );
    if (kick) {
      final live = _fingers.values.map((f) => f.frac).toList();
      return IgnorePointer(
        child: Column(
          children: [
            zone(_kGhostFrac, '정타 · 오른쪽일수록 세게', live.any((y) => y < _kGhostFrac), top: true),
            zone(1 - _kGhostFrac, '고스트', live.any((y) => y >= _kGhostFrac)),
          ],
        ),
      );
    }
    final bands = _fingers.values.map(_hatBandOf).toList();
    return IgnorePointer(
      child: Column(
        children: [
          zone(kHat16Zone, '16비트 · 꾹 누르면 촘촘한 롤', bands.contains(kHatBand16), top: true),
          zone(kOpenHatZone - kHat16Zone, '8비트 · 꾹 누르면 성긴 롤', bands.contains(kHatBand8)),
          zone(1 - kOpenHatZone, 'OPEN · 꾹 누르면 열린 하이햇', bands.contains(kHatBandOpen)),
        ],
      ),
    );
  }

  /// **세기 과녁** — 한가운데가 세게, 가장자리가 여리게(`_velFromCenter`).
  ///
  /// 화면 한가운데 동그라미는 여태 아무 기능 없는 장식이었다. 이제 그것이
  /// 「세게」 구역 그 자체다 — **보이는 것과 하는 일이 같다.** 바깥 테두리는
  /// 「여리게」가 시작되는 자리다. 둘 다 아주 옅게 깔아, 연주 중에 눈이
  /// 안 가도 되게 둔다(리듬을 탈 때는 어차피 화면을 안 본다).
  Widget _velTarget(Size area) {
    final m = area.width < area.height ? area.width : area.height;
    // 「여리게」가 시작되는 테두리만 옅게 하나. 한가운데 「세게」 구역은
    // 패드 동그라미 자체가 보여 주므로 여기서 또 그리지 않는다 — 두 번
    // 그리면 원이 겹쳐 보여 어느 것이 과녁인지 되레 헷갈린다.
    return IgnorePointer(
      child: Container(
        width: m * _kSoftR * 2,
        height: m * _kSoftR * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.055)),
        ),
      ),
    );
  }

  /// **롤 예고 진행도**(0~1) — `_canRoll` 인 악기를 꾹 누르고 있는 손가락 하나가
  /// 롤이 돌기 시작하는 180ms(`_kRollAfterMs`)를 향해 얼마나 찼는가. 톡 치는
  /// 동안(`_kRollShowMs` 전)이거나 이미 롤로 넘어갔으면(`f.rolled`) null —
  /// 예고는 **꾹 누르기 시작한 뒤 롤이 돌기 전까지만** 뜻이 있다.
  double? _chargeOf(_Finger f, DateTime now) {
    if (!_canRoll || f.swiped || f.rolled) return null;
    final ms = now.difference(f.downAt).inMilliseconds;
    if (ms <= _kRollShowMs) return null;
    final v = (ms - _kRollShowMs) / (_kRollAfterMs - _kRollShowMs);
    return v >= 1 ? null : v.clamp(0.0, 1.0);
  }

  /// **롤이 도는 동안** 패드를 격자에 맞춰 깜빡인다 — `_tickRoll`이 실제로
  /// 연타를 예약할 때마다 `f.flashAt`(그 소리가 들릴 시각)을 남기므로, 지금이
  /// 그 시각 바로 뒤(짧은 창)인 손가락이 있으면 "지금 막 울렸다"로 본다
  /// (사용자 지시, 2026-09-24: "도는 중 표시").
  bool _rollFlashing() {
    if (!_canRoll) return false;
    final now = DateTime.now();
    for (final f in _fingers.values) {
      if (!f.rolled) continue;
      final at = f.flashAt;
      if (at == null) continue;
      final diff = now.difference(at).inMilliseconds;
      if (diff >= 0 && diff < 90) return true;
    }
    return false;
  }

  /// 잡고 있는 동안 패드에 적는 글자. 코드는 **지금 울리는 코드 이름**(Am7 등)을 적는다.
  String _holdLabel() {
    if (_stageDef.kind != DoodleKind.chord) return 'HOLD';
    final sp = _lastSpec;
    return sp == null ? 'HOLD' : doodleChordName(sp);
  }

  /// 치는 패드 = **「세게」 구역 그 자체**(`_kHardR`). 화면 한가운데.
  Widget _padCircle(Size area, TapPhase phase, bool recording) {
    final m = area.width < area.height ? area.width : area.height;
    final d = m * _kHardR * 2;
    final flashing = _rollFlashing();
    // 코드 화음을 잡고 있는 동안 = **홀드 글로우**(사용자 지시, 이번 배치:
    // "잡고 있는 동안 계속, 떼면 사라지게"). 드럼은 톡 치는 악기라 길게
    // 잡을 일이 없어 여기선 안 켠다(`_hasTone`인 베이스는 사다리가 대신
    // 맡는다 — 아래 `_toneLadder`).
    final holdGlow = _stageDef.kind == DoodleKind.chord && _pressed;
    const ringExtra = 0.0;
    return IgnorePointer(
      child: SizedBox(
        width: d + 16 + ringExtra,
        height: d + 16 + ringExtra,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: d,
              height: d,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: flashing
                    ? _stageColor().withValues(alpha: 0.55)
                    : _pressed
                    ? _stageColor().withValues(alpha: 0.30)
                    : recording
                    ? Colors.redAccent.withValues(alpha: 0.18)
                    : Colors.white10,
                border: Border.all(
                  color: flashing
                      ? _stageColor()
                      : _pressed
                      ? _stageColor()
                      : recording
                      ? Colors.redAccent
                      : Colors.white24,
                  width: flashing ? 4 : 3,
                ),
                boxShadow: holdGlow
                    ? [
                        BoxShadow(
                          color: _stageColor().withValues(alpha: 0.45),
                          blurRadius: 22,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Text(
                  // 누르고 있으면 **대기 중이어도** 잡은 글자를 보여 준다 — "곧
                  // 시작"이 남아 있으면 소리가 나는데도 안 눌린 화면처럼 보인다.
                  _pressed
                      ? _holdLabel()
                      : (phase == TapPhase.wait || phase == TapPhase.count)
                      ? '곧 시작'
                      : 'TAP',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// **음 사다리**(베이스) — 아래가 낮은 음, 위가 높은 음.
  ///
  /// 「3도」 같은 말을 안 쓴다. 칸이 위로 갈수록 음이 높아진다는 것만 보이면
  /// 되고, 그건 아무도 안 배워도 안다. 지금 손가락이 있는 칸은 밝게 켠다 —
  /// 눈으로 어디를 잡고 있는지 알 수 있어야 미끄러뜨리기도 손에 붙는다.
  Widget _toneLadder() {
    final live = {for (final f in _fingers.values) if (!f.swiped) f.zone};
    // **홀드 글로우 — 숨 쉬듯 은은하게.** 잡고 있는 칸은 계속 밝지만, 고정된
    // 값이면 "지금도 잡고 있다"가 죽은 장식처럼 보인다. 그래서 시각에 따라
    // 살짝 오르내리는 밝기를 쓴다(판정과 무관 — 화면 표시만).
    final now = DateTime.now();
    final pulse = 0.5 + 0.5 * math.sin(now.millisecondsSinceEpoch / 260);
    final glowAlpha = 0.20 + 0.10 * pulse; // 0.20~0.30
    return Stack(
      children: [
        Column(
          children: [
            for (var i = _kLadderRows - 1; i >= 0; i--)
              Expanded(
                child: Container(
                  width: double.infinity,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 14),
                  decoration: BoxDecoration(
                    color: _stageColor().withValues(
                      alpha: live.contains(i) ? glowAlpha : (i.isEven ? 0.045 : 0.020),
                    ),
                    border: Border(
                      top: BorderSide(
                        color: Colors.white.withValues(
                          alpha: i == _kLadderRows - 1 ? 0 : 0.05,
                        ),
                      ),
                      // 잡고 있는 칸만 왼쪽에 밝은 결을 세워 "빛"이 나는
                      // 자리를 더 또렷이 보여 준다.
                      left: live.contains(i)
                          ? BorderSide(color: _stageColor(), width: 3)
                          : BorderSide.none,
                    ),
                  ),
                  child: Text(
                    i == 0 ? '낮게' : (i == _kLadderRows - 1 ? '높게' : ''),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white.withValues(alpha: 0.20),
                    ),
                  ),
                ),
              ),
          ],
        ),
        // **슬라이드 궤적** — 미끄러뜨리며 지나온 칸이 잠깐 밝아진다
        // (`_slideTo`가 `_rowVisitAt`에 시각을 남긴다). 지금 잡고 있는 칸
        // (`live`)은 위에서 이미 켜 뒀으니 겹쳐 이중으로 밝아지지 않게 뺀다.
        // 손끝 판정과 무관한 순수 오버레이라 `IgnorePointer`로 올린다.
        IgnorePointer(
          child: Column(
            children: [
              for (var i = _kLadderRows - 1; i >= 0; i--)
                Expanded(
                  child: Builder(
                    builder: (_) {
                      if (live.contains(i)) return const SizedBox.expand();
                      final at = _rowVisitAt[i];
                      if (at == null) return const SizedBox.expand();
                      final ms = now.difference(at).inMilliseconds;
                      if (ms < 0 || ms > _kLadderTrailMs) {
                        return const SizedBox.expand();
                      }
                      final t = ms / _kLadderTrailMs; // 0 → 1
                      return Container(
                        width: double.infinity,
                        color: _stageColor().withValues(alpha: 0.22 * (1 - t)),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        // **세기 3구역 — 지금 잡은 구역이 밝다**(감사 2026-09-29: 왼쪽이 여리게라는
        // 결만 있었고 경계(1/3·2/3)가 안 보여, 어디서부터 "세게"인지 손이 몰랐다).
        // 경계는 `_velFromX` 와 같은 1/3·2/3 — 다르면 보이는 것과 나는 세기가 어긋난다.
        IgnorePointer(
          child: Row(
            children: [
              for (var v = 1; v <= 3; v++)
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: _fingers.values.any((f) => !f.swiped && f.vel == v)
                            ? 0.07
                            : 0,
                      ),
                      border: v == 1
                          ? null
                          : Border(
                              left: BorderSide(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      const ['여리게', '보통', '세게'][v - 1],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // **가로 = 세기**(사용자 지시, 2026-09-24: "가로축 세기") — 오른쪽으로
        // 갈수록 밝아지는 옅은 결을 깔아, 눈으로도 "오른쪽이 세다"를 알 수
        // 있게 한다. 사다리(세로 칸)를 가리지 않도록 아주 옅게만 얹는다.
        IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Colors.transparent, Colors.white.withValues(alpha: 0.06)],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 지금 몇 박째인지 — REC 중엔 마지막 넷을 다르게(지시서 20번).
  Widget _beatDots(TapClock? cs) {
    final total = _bars * _meter.clicksPerBar;
    final progressed = cs != null && cs.phase == TapPhase.rec
        ? (cs.progress * total).floor()
        : -1;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: [
        for (var i = 0; i < total; i++)
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i == progressed
                  ? Colors.redAccent
                  : (i < progressed ? Colors.white38 : Colors.white12),
            ),
          ),
      ],
    );
  }

  /// **"지금 들려주는 중" 표시** — 리뷰 화면은 녹음이 끝나자마자 이미 씬에
  /// 얹혀 미리듣기 소리가 나는데(`_finishLap`의 `_commit()` + `refreshLoop`),
  /// 그 사실을 알려 주는 표시가 없었다(이번 배치, B5). 작은 스피커 아이콘이
  /// `_reviewBlink`(400ms 시계)에 맞춰 깜빡인다.
  Widget _nowPlayingBadge() {
    final on = DateTime.now().millisecondsSinceEpoch ~/ 400 % 2 == 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.volume_up,
          size: 15,
          color: (on ? _stageColor() : _stageColor().withValues(alpha: 0.35)),
        ),
        const SizedBox(width: 6),
        Text(
          '지금 들려주는 중',
          style: TextStyle(
            color: on ? Colors.white54 : Colors.white24,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _reviewBody() {
    return Column(
      children: [
        _header(),
        _progress(),
        const Spacer(),
        Text(
          '방금 연주한 ${_stageDef.label}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _playedText(),
          style: const TextStyle(color: Colors.white54, fontSize: 14),
        ),
        const SizedBox(height: 14),
        _nowPlayingBadge(),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _retake,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Colors.white24),
                  ),
                  child: const Text(
                    '다시 녹음',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: _openEditor,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: Colors.white24),
                  ),
                  child: const Text(
                    '다듬기',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _keep,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.tealAccent.shade400,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: Text(
                _keptStages.length +
                            (_keptStages.contains(_stage) ? 0 : 1) >=
                        _stages.length
                    ? '사용하기 · 완성'
                    : '사용하기',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
      ],
    );
  }

  Widget _doneBody() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.celebration, color: Colors.tealAccent, size: 56),
          const SizedBox(height: 16),
          const Text(
            '기본 비트 완성!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '킥·스네어·하이햇·베이스·코드를 직접 쳐서 이 씬의 바닥을\n깔았어요. 가락은 씬 화면에서 트랙으로 쌓으면 됩니다.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, fontSize: 13.5, height: 1.4),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.tealAccent.shade400,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text(
                '내 곡으로 가기',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 순서 정하기 화면의 줄 하나. `ReorderableListView`가 기본 손잡이를 그려
/// 주므로(`buildDefaultDragHandles` 기본값 true) 여기서는 번호·이름만 보여 준다.
class _OrderRow extends StatelessWidget {
  final DoodleStage stage;
  final int index;

  /// 이 단계가 지금 자리에서 "추천" 순서인가 — 코드가 베이스보다 앞이면 베이스가
  /// 그 화성을 따라 걸을 수 있어(코드 단계에 추천 배지를 단다). 순서를 굳이
  /// 안 바꿔도 되는 이유를 사용자에게 보여 준다.
  final bool recommended;

  /// 이 단계가 지금 쓰는 악기 이름 — 눌러서 바꾼다(`onPickInstrument`).
  final String instrument;
  final VoidCallback onPickInstrument;
  const _OrderRow({
    required super.key,
    required this.stage,
    required this.index,
    required this.instrument,
    required this.onPickInstrument,
    this.recommended = false,
  });

  // `_DoodlePlayViewState._stageColor()`와 같은 값(`DS.*`) — 순서 정하기
  // 화면과 실제 연주 화면에서 같은 악기가 다른 색으로 보이면 안 된다.
  Color get _color => switch (stage.kind) {
    DoodleKind.drum => DS.trackDrum,
    DoodleKind.bass => DS.trackBass,
    DoodleKind.chord => DS.trackChord,
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _color.withValues(alpha: 0.18),
            ),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                color: _color,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              stage.label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                letterSpacing: 1,
              ),
            ),
          ),
          // 악기 칩 — 누르면 이 단계의 음색(코드·베이스)·킷(드럼)을 고른다.
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              color: _color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                key: ValueKey('order-inst-$index'),
                borderRadius: BorderRadius.circular(16),
                onTap: onPickInstrument,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        instrument,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 18, color: Colors.white70),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (recommended)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.tealAccent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.5)),
              ),
              child: const Text(
                '추천',
                style: TextStyle(
                  color: Colors.tealAccent,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 타격 그림 (2026-09-30, B) — 판정·소리와 무관한 순수 화면 표시. 상태(`_ripples`·`_fingers`…)는
// 화면이 들고 있고, 여기서는 시계와 값만 읽어 그린다.
// ─────────────────────────────────────────────────────────────────────────────

Color _alpha(Color c, double a) => c.withValues(alpha: a.clamp(0.0, 1.0));

/// [center] 에서 [dirSign](−1 왼·+1 오른)쪽을 가리키는 쐐기(›) 하나.
void _chevron(Canvas c, Offset center, double size, int dirSign, Paint paint) {
  final p = Path()
    ..moveTo(center.dx - dirSign * size * 0.5, center.dy - size)
    ..lineTo(center.dx + dirSign * size * 0.5, center.dy)
    ..lineTo(center.dx - dirSign * size * 0.5, center.dy + size);
  c.drawPath(p, paint);
}

/// 위(+1)·아래(−1)를 가리키는 쐐기 하나.
void _chevronV(Canvas c, Offset center, double size, int up, Paint paint) {
  final p = Path()
    ..moveTo(center.dx - size, center.dy + up * size * 0.5)
    ..lineTo(center.dx, center.dy - up * size * 0.5)
    ..lineTo(center.dx + size, center.dy + up * size * 0.5);
  c.drawPath(p, paint);
}

/// 네 갈래 반짝임(✦) — 화려한 코드(위)를 쳤을 때 떠오른다.
void _sparkle(Canvas c, Offset o, double r, Paint paint) {
  c.drawLine(Offset(o.dx - r, o.dy), Offset(o.dx + r, o.dy), paint);
  c.drawLine(Offset(o.dx, o.dy - r), Offset(o.dx, o.dy + r), paint);
  final d = r * 0.55;
  c.drawLine(Offset(o.dx - d, o.dy - d), Offset(o.dx + d, o.dy + d), paint);
  c.drawLine(Offset(o.dx - d, o.dy + d), Offset(o.dx + d, o.dy - d), paint);
}

class _HitFxPainter extends CustomPainter {
  final _DoodlePlayViewState s;
  _HitFxPainter(this.s, Listenable repaint) : super(repaint: repaint);

  @override
  bool shouldRepaint(covariant _HitFxPainter old) => true;

  @override
  void paint(Canvas canvas, Size size) {
    final now = DateTime.now();
    final base = s._stageColor();
    for (final f in s._fingers.values) {
      if (!f.swiped) _finger(canvas, size, f, now, base);
    }
    for (final r in s._ripples) {
      _ripple(canvas, r, now, base);
    }
  }

  // ── 물결 ──
  void _ripple(Canvas c, _Ripple r, DateTime now, Color base) {
    final life = s._rippleLife(r);
    final ms = now.difference(r.born).inMilliseconds;
    if (ms < 0 || ms > life) return;
    final t = ms / life;
    final e = Curves.easeOutCubic.transform(t);
    final fade = 1 - t;
    final v = r.vel;
    final kick = r.lane == 'kick', hat = r.lane == 'hat', snare = r.lane == 'snare';
    final laneK = kick ? 1.15 : (hat ? 0.72 : 1.0);
    final reach = (v == 1 ? 56.0 : (v == 2 ? 96.0 : 150.0)) * laneK * (r.roll ? 1.15 : 1.0);
    final rad = 12 + (reach / 2 - 12) * e;
    // 고리는 악기 색을 지킨다(세게일수록 살짝 밝게) — 흰색은 코어 번쩍임에만 쓴다.
    final hot = Color.lerp(base, Colors.white, v == 3 ? 0.22 : (v == 2 ? 0.1 : 0))!;

    // 1) 부드러운 빛무리 — 세기가 셀수록 진하다.
    final gr = rad * 1.25;
    c.drawCircle(
      r.at,
      gr,
      Paint()
        ..shader = RadialGradient(
          colors: [_alpha(base, (0.22 + 0.12 * v) * fade), _alpha(base, 0)],
        ).createShader(Rect.fromCircle(center: r.at, radius: gr)),
    );
    // 채워진 원 — 세기가 셀수록 진하다. 킥은 더 크고 묵직하게(북이 울리는 결).
    c.drawCircle(
      r.at,
      rad * (kick ? 0.85 : 0.7),
      Paint()..color = _alpha(base, (kick ? 0.20 : 0.12) * fade * (v / 3)),
    );
    // 2) 고리
    c.drawCircle(
      r.at,
      rad,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ((r.roll ? 4 : 2) + v * 0.7 + (kick ? 1.5 : 0)) * (1 - 0.5 * t)
        ..color = _alpha(hot, (0.42 + 0.18 * v) * fade),
    );
    // 스네어 — 안쪽 고리가 하나 더(탁 하는 결).
    if (snare) {
      c.drawCircle(
        r.at,
        rad * 0.55,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = _alpha(hot, 0.5 * fade),
      );
    }
    // 세게 — 늦게 따라오는 두 번째 고리.
    if (v == 3 && !hat) {
      final t2 = ((ms - 70) / (life - 70)).clamp(0.0, 1.0);
      if (ms > 70) {
        c.drawCircle(
          r.at,
          rad * 0.62 + 10 * Curves.easeOutCubic.transform(t2),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = _alpha(Colors.white, 0.4 * (1 - t2)),
        );
      }
    }
    // 하이햇 — 짧게 튀는 불꽃 선.
    if (hat) {
      final sp = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.6 + 0.4 * v
        ..color = _alpha(hot, 0.75 * fade);
      for (final ang in const [-2.4, -1.57, -0.74]) {
        final d = Offset(math.cos(ang), math.sin(ang));
        c.drawLine(r.at + d * (rad * 0.75), r.at + d * (rad * (1.05 + 0.15 * v)), sp);
      }
    }
    // 3) 코어 번쩍임 — 맞는 순간 아주 짧게 밝다(세기가 셀수록 크고 세다).
    final ct = (ms / (kick ? 150 : 110)).clamp(0.0, 1.0);
    if (ct < 1) {
      final cr = (7 + 5.0 * v) * (1 - 0.4 * ct);
      c.drawCircle(
        r.at,
        cr,
        Paint()
          ..shader = RadialGradient(
            colors: [_alpha(Colors.white, (1 - ct) * (0.35 + 0.2 * v)), _alpha(hot, 0)],
          ).createShader(Rect.fromCircle(center: r.at, radius: cr)),
      );
    }
    if (r.lane == 'chord') _chordCue(c, r, t, e, fade);
  }

  /// 코드 탭 — 방향(왼 긴장 · 오른 해결)을 쐐기가 날아가며, 색(위 화려 · 아래 담백)을 반짝임·선으로.
  void _chordCue(Canvas c, _Ripple r, double t, double e, double fade) {
    if (r.dir != 0) {
      final tone = r.dir < 0 ? _DoodlePlayViewState._kCool : _DoodlePlayViewState._kWarm;
      for (var i = 0; i < 3; i++) {
        final lag = i * 0.12;
        if (t < lag) continue;
        final tt = ((t - lag) / (1 - lag)).clamp(0.0, 1.0);
        final dx = r.dir * (30 + 78 * Curves.easeOutCubic.transform(tt));
        _chevron(
          c,
          Offset(r.at.dx + dx, r.at.dy),
          9.0 + 2 * i,
          r.dir,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = 4
            ..color = _alpha(tone, (1 - tt) * (0.95 - 0.18 * i)),
        );
      }
    }
    if (r.color == 1) {
      final sp = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.2
        ..color = _alpha(Colors.white, 0.9 * fade);
      _sparkle(c, Offset(r.at.dx - 20, r.at.dy - 26 - 46 * e), 7, sp);
      _sparkle(c, Offset(r.at.dx + 18, r.at.dy - 20 - 34 * e), 5, sp);
    } else {
      c.drawLine(
        Offset(r.at.dx - 16, r.at.dy + 24 + 8 * e),
        Offset(r.at.dx + 16, r.at.dy + 24 + 8 * e),
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 3
          ..color = _alpha(Colors.white, 0.55 * fade),
      );
    }
  }

  // ── 닿아 있는 손가락 ──
  void _finger(Canvas c, Size size, _Finger f, DateTime now, Color base) {
    final cur = Offset(f.curX, f.curY);
    // 닿음 확인용 빛무리 — "손가락이 인식됐다"를 눈으로.
    c.drawCircle(
      cur,
      34,
      Paint()
        ..shader = RadialGradient(
          colors: [_alpha(base, 0.22), _alpha(base, 0)],
        ).createShader(Rect.fromCircle(center: cur, radius: 34)),
    );
    if (f.swell) _swell(c, size, f, base);

    final origin = Offset(f.downX, f.downY);
    // 롤 충전 링 — 꾹 누르는 동안 차오르고, 다 차면 물결이 터진다.
    final charge = s._chargeOf(f, now);
    if (charge != null) {
      final opens = s._stageDef.drumLane == 'hat' &&
          hatHoldOpensSticky(
            downFrac: f.downFrac,
            frac: f.frac,
            slop: s._area.height <= 0 ? 0 : kBandSlopPx / s._area.height,
          );
      final tone = opens ? Color.lerp(base, Colors.white, 0.55)! : base;
      final ring = Rect.fromCircle(center: origin, radius: 38);
      c.drawCircle(
        origin,
        38,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..color = _alpha(Colors.white, 0.14),
      );
      c.drawArc(
        ring,
        -math.pi / 2,
        2 * math.pi * charge,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 4 + 3 * charge
          ..color = _alpha(tone, 0.95),
      );
      final tipAng = -math.pi / 2 + 2 * math.pi * charge;
      c.drawCircle(
        origin + Offset(math.cos(tipAng), math.sin(tipAng)) * 38,
        3 + 2 * charge,
        Paint()..color = _alpha(Colors.white, 0.9),
      );
      // 하이햇은 꾹 누르는 동안 **지금 손 밑이 무슨 모드인지**(16비트·8비트·OPEN)를 바로 적는다 —
      // 롤이 돌기 전(충전 중)에 이미 어느 쪽인지 보여야 손을 옮길 수 있다.
      if (s._stageDef.drumLane == 'hat' && charge > 0.15) {
        _hatModeLabel(c, origin, s._hatBandOf(f), 0.5 + 0.5 * charge);
      }
    }
    // 롤이 도는 동안 — 격자(박)마다 손가락 밑이 깜빡이고, 밀어서 세지는 눈금이 뜬다.
    if (f.rolled) {
      final at = f.flashAt;
      if (at != null) {
        final diff = now.difference(at).inMilliseconds;
        if (diff >= 0 && diff < 90) {
          final k = 1 - diff / 90;
          c.drawCircle(origin, 30 + 8 * (1 - k), Paint()..color = _alpha(base, 0.5 * k));
          c.drawCircle(
            origin,
            34 + 10 * (1 - k),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = _alpha(Colors.white, 0.5 * k),
          );
        }
      }
      _crescendo(c, size, f, base);
      if (s._stageDef.drumLane == 'hat') {
        _hatModeLabel(c, origin, f.hatBand ?? s._hatBandOf(f), 0.9);
      }
    }
  }

  /// 하이햇 모드 글자 — 손가락 밑에 「16비트」·「8비트」·「OPEN」.
  void _hatModeLabel(Canvas c, Offset origin, int band, double a) {
    final text = switch (band) {
      kHatBand16 => '16비트',
      kHatBand8 => '8비트',
      _ => 'OPEN',
    };
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: _alpha(Colors.white, a),
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(origin.dx - tp.width / 2, origin.dy + 44));
  }

  /// 롤 크레셴도 눈금 — 손가락에서 오른쪽으로 폭의 1/4·2/4 자리에 점 둘. 지나간 만큼 켜진다.
  void _crescendo(Canvas c, Size size, _Finger f, Color base) {
    final q = size.width / 4;
    if (q <= 0 || f.downX + q > size.width - 8) return; // 오른쪽 끝이라 밀 자리가 없다
    final y = f.downY + 64 > size.height - 16 ? f.downY - 64 : f.downY + 64;
    final x1 = math.min(f.downX + 2 * q, size.width - 8);
    c.drawLine(
      Offset(f.downX, y),
      Offset(x1, y),
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3
        ..color = _alpha(Colors.white, 0.22),
    );
    for (var i = 1; i <= 2; i++) {
      final x = f.downX + i * q;
      if (x > size.width - 8) break;
      final on = f.rollBump >= i;
      c.drawCircle(
        Offset(x, y),
        on ? 7 : 5,
        Paint()..color = on ? _alpha(base, 0.95) : _alpha(Colors.white, 0.35),
      );
    }
    final cx = f.curX.clamp(f.downX, x1).toDouble();
    c.drawCircle(Offset(cx, y), 4, Paint()..color = _alpha(Colors.white, 0.85));
  }

  /// 스웰 — 그은 만큼 아래에서 베일이 차오르고, 손가락 자리에서 지금 자리까지 빛줄기가 선다.
  void _swell(Canvas c, Size size, _Finger f, Color base) {
    final travel = size.height * kSwellTravel;
    if (travel <= 0) return;
    final up = ((f.downY - f.curY - kSwellDeadPx) / travel).clamp(0.0, 1.0);
    final vh = size.height * 0.5 * up;
    if (vh > 1) {
      final rect = Rect.fromLTWH(0, size.height - vh, size.width, vh);
      c.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_alpha(base, 0), _alpha(base, 0.24)],
          ).createShader(rect),
      );
    }
    final from = Offset(f.downX, f.downY), to = Offset(f.curX, f.curY);
    c.drawLine(
      from,
      to,
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 3 + 5 * up
        ..color = _alpha(base, 0.30 + 0.5 * up),
    );
    // 「위로 그으세요」 쐐기 — 아직 안 그었을 때 더 또렷이 떠 있다.
    _chevronV(
      c,
      Offset(f.curX, f.curY - 46),
      9,
      1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 4
        ..color = _alpha(Colors.white, 0.75 - 0.5 * up),
    );
  }
}

/// 코드 단계의 바닥 그림 — 좌우 세 띠(긴장·그대로·해결)와 위아래 두 구역(화려·담백), 그리고
/// **맥박 치는 쐐기**로 「이 방향으로 치면 뭔가 달라진다」를 보여 준다. 탭한 순간엔 그 구역이 번쩍한다.
class _ChordZonePainter extends CustomPainter {
  final _DoodlePlayViewState s;
  _ChordZonePainter(this.s, Listenable repaint) : super(repaint: repaint);

  @override
  bool shouldRepaint(covariant _ChordZonePainter old) => true;

  @override
  void paint(Canvas canvas, Size size) {
    final now = DateTime.now();
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    final third = w / 3;
    final splitY = kChordColorSplit * h;
    final landed = s._curDir();
    var flash = 0.0;
    final fa = s._flashAt;
    if (fa != null) {
      final ms = now.difference(fa).inMilliseconds;
      if (ms >= 0 && ms < _DoodlePlayViewState._kZoneFlashMs) {
        flash = 1 - ms / _DoodlePlayViewState._kZoneFlashMs;
      }
    }
    final holding = s._fingers.values.where((f) => !f.swiped).toList();
    final topOn = holding.any((f) => f.color == 1), botOn = holding.any((f) => f.color == 0);

    // 위·아래 두 구역 — 누른 쪽이 밝고, 탭 순간엔 번쩍한다.
    final topA = (topOn ? 0.05 : 0.0) + (s._flashColor == 1 ? 0.10 * flash : 0);
    final botA = (botOn ? 0.05 : 0.0) + (s._flashColor == 0 ? 0.10 * flash : 0);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, splitY), Paint()..color = _alpha(Colors.white, topA));
    canvas.drawRect(
      Rect.fromLTWH(0, splitY, w, h - splitY),
      Paint()..color = _alpha(Colors.white, botA),
    );

    // 좌·우 띠 — 바깥 가장자리가 진하고 안쪽으로 옅어진다. 착지 방향 쪽은 더 진하다.
    void band(Rect r, Color tone, bool leftSide, bool on, bool flashing) {
      final edgeA = (on ? 0.32 : 0.15) + (flashing ? 0.30 * flash : 0);
      canvas.drawRect(
        r,
        Paint()
          ..shader = LinearGradient(
            begin: leftSide ? Alignment.centerLeft : Alignment.centerRight,
            end: leftSide ? Alignment.centerRight : Alignment.centerLeft,
            colors: [_alpha(tone, edgeA), _alpha(tone, 0.02)],
          ).createShader(r),
      );
    }

    band(Rect.fromLTWH(0, 0, third, h), _DoodlePlayViewState._kCool, true, landed < 0,
        s._flashDir < 0);
    band(Rect.fromLTWH(w - third, 0, third, h), _DoodlePlayViewState._kWarm, false, landed > 0,
        s._flashDir > 0);
    if (s._flashDir == 0 && flash > 0) {
      canvas.drawRect(
        Rect.fromLTWH(third, 0, third, h),
        Paint()..color = _alpha(Colors.white, 0.06 * flash),
      );
    }

    // 경계선 — 위(화려)/아래(담백).
    canvas.drawLine(
      Offset(0, splitY),
      Offset(w, splitY),
      Paint()
        ..strokeWidth = 2
        ..color = _alpha(Colors.white, 0.22),
    );

    // 맥박 치는 쐐기 — 바깥으로 흘러가며 「이쪽으로」를 가리킨다. 안 친 사이에는 옅게, 착지한 쪽은 진하게.
    final phase = (now.millisecondsSinceEpoch % 1200) / 1200.0;
    void chevrons(bool leftSide, Color tone, bool strong) {
      final sign = leftSide ? -1 : 1;
      for (var i = 0; i < 3; i++) {
        final p = (phase + i / 3) % 1.0;
        final x0 = leftSide ? third * 0.95 : w - third * 0.95;
        final x1 = leftSide ? third * 0.5 : w - third * 0.5;
        final x = x0 + (x1 - x0) * p;
        final a = math.sin(math.pi * p) * (strong ? 0.85 : 0.38);
        _chevron(
          canvas,
          Offset(x, h * 0.5),
          10,
          sign,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = 4
            ..color = _alpha(tone, a),
        );
      }
    }

    chevrons(true, _DoodlePlayViewState._kCool, landed < 0);
    chevrons(false, _DoodlePlayViewState._kWarm, landed > 0);

    // 위·아래 화살 — 경계선 바로 위는 위(화려, 반짝), 아래는 아래(담백).
    final pulse = 0.5 + 0.5 * math.sin(now.millisecondsSinceEpoch / 300);
    final vp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 4;
    // 가운데 패드의 글자를 안 가리게 양옆에 한 쌍씩.
    for (final dx in const [-72.0, 72.0]) {
      _chevronV(canvas, Offset(w / 2 + dx, splitY - 30 - 4 * pulse), 10, 1,
          vp..color = _alpha(Colors.white, topOn ? 0.8 : 0.22 + 0.16 * pulse));
      _chevronV(canvas, Offset(w / 2 + dx, splitY + 30 + 4 * pulse), 10, -1,
          vp..color = _alpha(Colors.white, botOn ? 0.8 : 0.22 + 0.16 * pulse));
    }
  }
}
