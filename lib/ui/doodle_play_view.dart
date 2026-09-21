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
// 새로 만든 것은 **한 화면 = 한 악기**로 진행을 순서대로 강제하는 이 위젯 자체와
// 장르별 순서 표(`kDoodleStages`)뿐이다.
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
import 'package:flutter/services.dart';

import '../audio_isolate.dart';
import '../edit_ops.dart' show DrumOps;
import '../genres.dart' show genreDef;
import '../live_ops.dart' show LivePads, beatsToSend, metroBatch;
import '../meter.dart';
import '../patterns.dart' show NotePatternDef;
import '../prog_ops.dart' show ProgSlot, kMaxDegree;
import '../project.dart';
import '../sequencer.dart';
import '../synth.dart' show kPartLive;
import '../tap_rec.dart';
import '../theory.dart'
    show
        ChordSpec,
        MusicKey,
        buildChordText,
        chordFreqsOf,
        degreeFreq,
        diatonicChords,
        kChordTypeIntervals,
        parseChordText,
        scaleOf;
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
Future<void> openDoodlePlay(
  BuildContext context, {
  required Project project,
  required Transport transport,
  required AudioClient? host,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => DoodlePlayView(
        project: project,
        transport: transport,
        host: host,
      ),
    ),
  );
}

class DoodlePlayView extends StatefulWidget {
  final Project project;
  final Transport transport;
  final AudioClient? host;
  const DoodlePlayView({
    super.key,
    required this.project,
    required this.transport,
    required this.host,
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

  /// 지금 머무는 좌우 구역(0~3). 넘어가면 미끄러뜨리기다.
  int zone;

  /// 지금 소리 나고 있는 주파수 — 미끄러뜨릴 때 **출발점**이 된다.
  double freq = 0;

  /// 이 손가락이 마지막으로 음을 연 칸. 미끄러진 뒤에도 앞 칸을 안다.
  int step;

  /// 드럼에서 꾹 눌러 롤이 도는 중인가. null 이면 아직 한 방뿐.
  /// 값은 **다음 연타를 낼 시각**이다.
  DateTime? rollNext;

  _Finger({
    required this.pad,
    required this.downX,
    required this.downY,
    required this.downAt,
    required this.vel,
    required this.zone,
    required this.step,
  });
}

class _DoodlePlayViewState extends State<DoodlePlayView> {
  final _clock = LoopClock();
  Timer? _timer;

  late final Track _drumTrack;
  late final String _drumPatternName;
  late DrumOps _ops;

  late final Track _bassTrack;
  late final String _bassPatternName;
  List<List<Object?>> _bassNotes = [];

  late final Track _chordTrack;
  late final String _chordPatternName;
  List<List<Object?>> _chordNotes = [];

  double _loopSec = 0;
  int _loopBars = 0;

  int _stage = 0;
  TapClock? _clockState;
  TapRecorder? _rec;

  bool _reviewing = false;
  bool _allDone = false;
  List<TapHit> _pending = const [];

  final Set<int> _metSent = {};
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

  /// 음 높이 옮기기 — 위로 쓸면 +1(한 옥타브 위), 아래로 쓸면 −1.
  /// 드럼은 음 높이가 없어서 안 쓴다.
  int _octShift = 0;

  /// 방금 친 순간(화면 이펙트용) — null 이면 안 친 상태.
  DateTime? _hitAt;

  /// HOLD 로 잡고 있는 손가락 번호의 **시작값**. 손가락마다 +1 해서 쓴다
  /// (라이브 화면과 겹치지 않게 큰 수로 둔다).
  static const int _kHoldId = 9001;

  /// 코드 단계에서 잡고 있는 화음 음들의 번호 시작값 — 손가락 번호와 겹치면
  /// 안 되므로 따로 뗀 자리에 둔다.
  static const int _kChordId = 9200;

  /// 한 화음에 낼 수 있는 음 수 — 9화음(5음)까지.
  static const int _kMaxChordTones = 5;

  /// 세로로 이만큼(논리픽셀) 넘게 움직이면 음이 아니라 쓸기로 본다.
  static const double _kSwipeSlop = 28;

  /// **쓸기는 닿은 뒤 이 시간 안에 일어난 것만** 본다.
  ///
  /// 예전엔 시간 제한이 없어서, 베이스를 1~2초 길게 잡고 있는 동안 손가락이
  /// 천천히 36px 흘러내리기만 해도 쓸기로 읽혀 `holdOff` + `_rec.cancel` 이
  /// 돌았다 — **그 음이 소리도 기록도 없이 사라지고 옥타브까지 바뀐다.**
  /// 리듬을 타는 중에 손이 미끄러지는 건 예외가 아니라 기본값이다.
  /// 문턱을 36→28 로 낮추는 대신 시간창과 방향비를 걸었다(문턱만 올리면
  /// 이번엔 옥타브 바꾸기가 안 된다).
  static const int _kSwipeWindowMs = 160;

  /// 세로가 가로보다 이만큼 커야 쓸기 — 비스듬한 손짓은 미끄러뜨리기로 본다.
  static const double _kSwipeRatio = 1.6;

  /// 이 시간 안에 떼면 **톡**(스타카토). 시간 축이라 다른 손짓과 안 겹친다.
  static const int _kStaccatoMs = 90;

  /// 「톡」으로 치려면 이만큼 안에서 끝나야 한다.
  static const double _kStaccatoSlop = 8;

  /// 드럼에서 이만큼 붙이고 있으면 **롤**이 돈다.
  static const int _kRollAfterMs = 220;

  /// 롤을 앞질러 예약하는 창 — 길면 뗐는데 계속 쳐서 "화면이 안 먹는다"가 된다.
  static const double _kRollAheadSec = 0.12;

  /// 코드 두께 — 첫 손가락 뒤 이 시간 안에 닿은 손가락까지 **한 화음**으로 센다.
  static const int _kChordGroupMs = 120;

  /// 한 번에 받을 손가락 수 — `TapRecorder` 의 판이 넷이라 거기에 맞춘다.
  static const int _kMaxFingers = 4;

  /// 탭 이펙트 한 번이 사그라드는 시간.
  static const Duration _kHitFx = Duration(milliseconds: 320);

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

  /// 그 칸의 **화음 종류**(칸 → 'min7' 같은 코드 글). null 이면 3화음 그대로.
  final Map<int, String> _chordTypeOf = {};

  /// **꾹 눌러 롤**로 들어온 드럼 칸들 — 사람이 친 게 아니라 기계가 낸
  /// 정확한 시각이라 `TapRecorder`(사람 반응 지연을 되돌리는 계산)를 안 거친다.
  final Set<int> _rollSteps = {};

  /// 화면에 들어올 때 씬에 **이미 있던** 코드 진행. 이 화면은 코드 판을
  /// 비우고 시작하므로(그래야 안 친 악기가 안 울린다), 비우기 전에 챙겨 뒀다가
  /// 코드 단계를 건너뛰었을 때 베이스가 이걸 따라 걷게 한다.
  List<ProgSlot> _priorProg = const [];
  int _priorProgSteps = 0;

  /// 코드 두께 — 지금 모으고 있는 화음의 첫 손가락 시각·칸·손가락 수.
  DateTime? _chordFirstAt;
  int _chordFirstStep = -1;
  int _chordFingers = 0;

  /// 이 화면이 **내려가지 못하게 막는** 버퍼 바닥(프레임) — 48kHz에서 64ms.
  /// 씬 루프를 틀어 놓고 도는 화면이라 급식이 마르면 안 된다(위 `initState`).
  static const int _kDoodleAheadFloor = 3072;

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
  DoodleStage get _stageDef => kDoodleStages[_stage];

  @override
  void initState() {
    super.initState();
    final p = widget.project;
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
    _bars = _pickBars(SceneSequencer.sceneLoopBars(p, p.currentScene));
    final ts = DateTime.now().millisecondsSinceEpoch;
    _drumTrack = p.tracks.firstWhere(
      (t) => t.type == 'drum',
      orElse: () => p.tracks.first,
    );
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
    _chordPatternName = 'doodle_chord_$ts';
    p.putUserPattern(
      'chord',
      _chordPatternName,
      note: NotePatternDef(_chordPatternName, _bars, _bars, const [], spb: p.spb),
    );
    p.setClip(_chordTrack, _chordPatternName);

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

    final h = widget.host;
    _clock.attach(h);
    if (h != null) {
      final b = SceneSequencer.playLoop(p, widget.transport, h);
      widget.transport.playing = true;
      widget.transport.songLoop = false;
      _loopSec = b.loopSec;
      _loopBars = b.loopBars;
      h.setSongMode(false); // 손가락에 붙어야 한다
      // ── 버퍼를 **내리지 않고 바닥만 올린다** (2026-09-21) ──
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
      if (prevAhead < _kDoodleAheadFloor) h.setAhead(_kDoodleAheadFloor);
      _buffered = h.aheadFrames;
      // 예약 시각 보정은 **실측 버퍼**로 한다(목표치와 다를 수 있다).
      _statsSub = h.statsStream.listen((s) {
        if (s.aheadFrames > 0) _buffered = s.aheadFrames;
      });
    }
    _armStage();
    _timer = Timer.periodic(const Duration(milliseconds: 30), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _statsSub?.cancel();
    _clock.dispose();
    final h = widget.host;
    h?.holdOff(-1);
    // 재워 뒀던 트랙을 **먼저** 깨운다 — `pushMix` 가 그 상태를 읽어 간다.
    for (final t in widget.project.tracks) {
      final was = _priorMute[t.id];
      if (was != null && t.mute != was) t.mute = was;
    }
    if (h != null) SceneSequencer.pushMix(widget.project, h);
    final prev = _prevAhead;
    if (h != null && prev != null && prev != h.aheadFrames) h.setAhead(prev);
    h?.setSongMode(true);
    super.dispose();
  }

  void _armStage() {
    _clockState = TapClock(
      beatsPerLoop: _loopBars * _meter.clicksPerBar,
      lapBeats: _bars * _meter.clicksPerBar,
      countBeats: _meter.clicksPerBar,
      beatsPerBar: _meter.clicksPerBar,
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
    _chordTypeOf.clear();
    _rollSteps.clear();
    _chordFirstAt = null;
    _chordFirstStep = -1;
    _chordFingers = 0;
    _hitAt = null;
    _octShift = 0;
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
    // 자(메트로놈)가 보낸 기록도 비운다 — 안 비우면 앞 단계에서 이미 보낸
    // 박 번호가 남아 새 단계의 미리 세기 첫 박이 막힐 수 있다.
    _metSent.clear();
    _metLastNow = 0;
  }

  // ── 박 세기 ── (두드려 넣기 화면과 같은 계산, `tap_sheet.dart` 참고)

  void _tick() {
    final h = widget.host;
    if (!mounted || h == null || _loopSec <= 0 || _reviewing || _allDone) {
      return;
    }
    final pos = _clock.pos(_loopSec);
    _sendMet(pos, h);
    final cs = _clockState!;
    final was = cs.phase;
    cs.update(pos * _loopBars * _meter.clicksPerBar);
    if (was != TapPhase.rec && cs.phase == TapPhase.rec) _startRec();
    _maybeHaptic(cs);
    _tickRoll();
    if (cs.phase == TapPhase.done) {
      _finishLap(pos);
      return;
    }
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
    if (_metLastNow - nowSec > _loopSec / 2) _metSent.clear();
    if (nowSec > _metLastNow) _metLastNow = nowSec;
    final ticks = beatsToSend(
      nowSec: nowSec,
      loopSec: _loopSec,
      beatSec: _beatSec,
      sent: _metSent,
      lead: 0.5,
    );
    if (ticks.isEmpty) return;
    h.batch(metroBatch(ticks, beatsPerBar: _meter.clicksPerBar));
    for (final t in ticks) {
      _metSent.add(t.beat);
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
    widget.host?.holdOff(-1);
    setState(() {
      _pending = _rec?.hits() ?? const [];
      _reviewing = true;
    });
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
    return (_priorProg, _priorProgSteps);
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

  /// 손짓으로 정해진 것들을 **음 줄에 한꺼번에 얹는다.**
  ///
  /// `tapToNotes` 는 박자만 담는 함수라 세기를 늘 2로 적고 높이도 그 칸의
  /// 기본음으로만 적는다. 여기서 칸 번호로 맞춰 갈아 끼운다.
  /// 행 모양은 `[도수, 칸, 길이, 세기, 글라이드·코드종류, 층]`.
  ///
  /// **베이스와 코드가 다섯째 칸을 서로 다르게 읽는다** — 낱음 줄은
  /// `n[4]==1` 을 "앞 음에서 미끄러짐"으로(`buildRowsPattern`), 코드 줄은
  /// `n[4] is String` 을 "코드 종류"로(`buildChordPattern`) 읽는다. 그래서
  /// [chord] 로 갈라 둔다.
  ///
  /// 코드 줄에는 **좌우로 고른 음을 절대 더하지 않는다.** 코드 줄의 첫 칸은
  /// 도수가 아니라 **코드 번호**(`% chords.length` 로 읽힌다)라, 거기 3·5·7도를
  /// 더하면 친 것과 전혀 다른 코드가 적힌다 — 들린 Am 이 다른 코드로 저장됐다.
  List<List<Object?>> _decorate(
    List<List<Object?>> rows, {
    required bool chord,
  }) {
    return [
      for (final r in rows)
        () {
          final step = r[1] as int;
          final len = _staccatoAt.contains(step) ? 1 : r[2];
          final vel = _velOf[step] ?? r[3];
          if (chord) {
            final ty = _chordTypeOf[step];
            // 층(`n[5]`)은 `tapToNotes(oct:)` 가 이미 적어 뒀다 — 살려 둔다.
            final oct = r.length > 5 ? r[5] : null;
            if (ty == null && oct == null) return <Object?>[r[0], step, len, vel];
            if (oct == null) return <Object?>[r[0], step, len, vel, ty];
            return <Object?>[r[0], step, len, vel, ty, oct];
          }
          // 낱음 줄(베이스) — **소리 낼 때 쓴 바로 그 함수**로 도수를 구한다.
          // `tapToNotes` 가 적어 둔 `r[0]` 은 좌우·옥타브를 모르는 기본음이다.
          // 여기서 따로 더하면 clamp 순서가 달라져 소리와 갈린다(전에 그랬다).
          final deg = _writeDegree(step, _toneOf[step] ?? 0);
          final glide = _glideAt.contains(step) ? 1 : null;
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
  int _velFromCenter(Offset at, Size area) {
    final m = area.width < area.height ? area.width : area.height;
    if (m <= 0) return 2;
    final dx = at.dx - area.width / 2, dy = at.dy - area.height / 2;
    final r = math.sqrt(dx * dx + dy * dy) / m;
    if (r < _kHardR) return 3; // 한가운데 — 악센트
    if (r < _kSoftR) return 2; // 그 바깥 — 보통
    return 1; // 가장자리 — 고스트
  }

  /// 한가운데(세게) 구역의 반지름 — min(폭,높이) 대비.
  /// 화면에 그려지는 190px 동그라미와 같은 크기로 맞춘다.
  static const double _kHardR = 0.24;

  /// 여기서부터 바깥은 여리게.
  static const double _kSoftR = 0.44;

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

  /// 구역 경계에서 이만큼 더 나가야 넘어간 것으로 본다.
  static const double _kZoneSlop = 8;

  /// 손가락이 닿았다 — **누른 동안 계속 나는 소리**로 낸다(HOLD).
  /// 드럼만 예외로 톡 치는 한 방이다(타악은 잡고 있을 것이 없다).
  void _pressDown(PointerDownEvent e, Size area) {
    final pointer = e.pointer;
    final at = e.localPosition;
    // **어느 대목이든 소리는 바로 낸다.** 예전엔 녹음(rec) 중이 아니면 여기서
    // 그냥 돌아가서, 대기·미리 세기 동안(길면 6초) 눌러도 소리도 화면도
    // 아무 반응이 없었다 — 사용자에겐 "눌러도 안 되는 화면"으로 보인다.
    // 담는 것만 녹음 중에 하고, 들려주는 것은 늘 한다.
    if (_fingers.containsKey(pointer) || _fingers.length >= _kMaxFingers) return;
    final cs = _clockState;
    final recording = cs != null && cs.phase == TapPhase.rec;
    final pos = _clock.pos(_loopSec);
    final rec = _rec;
    // 손가락마다 판(pad)을 따로 준다 — 같은 판을 쓰면 두 번째 손가락이
    // 첫 번째가 누르고 있던 것을 닫아 버린다.
    final used = {for (final f in _fingers.values) f.pad};
    var pad = 0;
    while (used.contains(pad) && pad < _kMaxFingers - 1) {
      pad++;
    }
    final now = DateTime.now();
    // 베이스는 **세로가 이미 음 높이**라 세기를 자리로 못 읽는다. 자동으로
    // 둔다 — 베이스 라인은 세기보다 음과 길이가 훨씬 크게 들린다.
    final vel = _hasTone ? 2 : _velFromCenter(at, area);
    final zone = _hasTone ? _rowFromY(at.dy, area.height) : 0;
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
    );
    _fingers[pointer] = f;
    if (recording) {
      rec?.down(pad, pos);
      _velOf[step] = vel;
      if (tone != 0) _toneOf[step] = tone;
    }
    switch (_stageDef.kind) {
      case DoodleKind.drum:
        widget.host?.drumOn(_drumTrack.kit, _stageDef.drumLane!, vel);
        // 타악은 길이가 없다 — 그 자리에 한 칸.
        if (recording) rec?.up(pad, pos);
        // 붙이고 있으면 **롤**이 돈다. 여기서는 시각만 잡아 두고, 실제 연타는
        // `_tickRoll` 이 앞질러 예약한다(30ms 화면 시계로 내면 덜컹거린다).
        f.rollNext = now.add(const Duration(milliseconds: _kRollAfterMs));
      case DoodleKind.bass:
        f.freq = _bassFreq(step, tone);
        widget.host?.holdOn(_kHoldId + pad, _bassTrack.voice, f.freq, vel);
      case DoodleKind.chord:
        _chordDown(step, vel, recording: recording, now: now);
    }
    setState(() => _hitAt = now);
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
    return (base + tone + 7 * (_octShift > 0 ? 1 : 0)).clamp(0, kMaxDegree);
  }

  /// 코드 한 방 — **두께**(같이 닿은 손가락 수)가 3화음/7화음/9화음을 정한다.
  void _chordDown(
    int step,
    int vel, {
    required bool recording,
    required DateTime now,
  }) {
    // 같은 칸에서 짧은 시간 안에 닿은 손가락들을 **한 화음**으로 센다.
    // 벌린 거리를 안 재는 이유: 손 크기·화면 크기마다 달라서 문턱을 못 잡는다.
    // 개수는 틀릴 수가 없다.
    final first = _chordFirstAt;
    if (first == null ||
        _chordFirstStep != step ||
        now.difference(first).inMilliseconds > _kChordGroupMs) {
      _chordFirstAt = now;
      _chordFirstStep = step;
      _chordFingers = 1;
    } else {
      _chordFingers++;
    }
    final thick = _chordFingers.clamp(1, 3);
    final key = MusicKey(root: widget.transport.root, mode: widget.transport.mode);
    final degree = _degreeAt(step, type: 'chord', chord: true);
    final text = _thickText(key, degree, thick);
    final spec = _specOf(key, degree, text);
    final oct = LivePads.octMul(_octShift);
    // **잡고 있는 소리로 낸다.** 예전엔 `batch` 로 8초짜리 한 방을 냈는데,
    // `batch` 는 번호가 없어서 `holdOff` 로 못 끊는다 — 떼도 8초를 울렸고,
    // 두께가 바뀌면 앞 화음 위에 새 화음이 겹쳐 지저분해진다.
    for (var i = 0; i < _kMaxChordTones; i++) {
      widget.host?.holdOff(_kChordId + i);
    }
    final freqs = chordFreqsOf(spec);
    for (var i = 0; i < freqs.length && i < _kMaxChordTones; i++) {
      widget.host?.holdOn(
        _kChordId + i,
        _chordTrack.voice,
        freqs[i] * oct,
        vel,
        part: kPartLive,
      );
    }
    if (recording) {
      if (text != null) {
        _chordTypeOf[step] = text;
      } else {
        _chordTypeOf.remove(step);
      }
    }
  }

  /// 두께 → 그 도수의 **다이아토닉** 코드 글. 1이면 null(3화음 그대로).
  ///
  /// 스케일에서 뽑으므로 장·단조 어느 쪽이든 그 조에 있는 음만 쓴다 —
  /// "무엇을 눌러도 틀린 음이 안 난다"가 두께를 늘려도 안 깨진다.
  String? _thickText(MusicKey key, int degree, int thick) {
    if (thick <= 1) return null;
    final sc = scaleOf(key.mode);
    int off(int x) => sc[x % 7] + 12 * (x ~/ 7);
    final r = degree % 7;
    final iv = [0, off(r + 2) - off(r), off(r + 4) - off(r), off(r + 6) - off(r)];
    String? type;
    for (final e in kChordTypeIntervals.entries) {
      final v = e.value;
      if (v.length == 4 &&
          v[0] == iv[0] &&
          v[1] == iv[1] &&
          v[2] == iv[2] &&
          v[3] == iv[3]) {
        type = e.key;
        break;
      }
    }
    if (type == null) return null; // 표에 없는 화음이면 3화음으로 둔다
    if (thick <= 2) return buildChordText(type, const [], null);
    // 9도는 표가 **뿌리에서 14반음 고정**이다. 그 조에서 실제 9도가 14가
    // 아니면(단조의 어떤 자리) 얹는 순간 조 밖 음이 되므로 7화음에서 멈춘다.
    final ninth = off(r + 8) - off(r);
    if (ninth != 14) return buildChordText(type, const [], null);
    return buildChordText(type, const ['t9'], null);
  }

  /// 코드 글이 있으면 그 종류로, 없으면 그 도수의 기본 3화음으로.
  ChordSpec _specOf(MusicKey key, int degree, String? text) {
    final base = diatonicChords(key)[degree % 7];
    if (text == null) return base;
    final c = parseChordText(text);
    return ChordSpec(
      root: base.root,
      type: c.type.isEmpty ? base.type : c.type,
      tensions: c.tensions,
    );
  }

  /// 손가락이 움직였다.
  ///
  /// **베이스**는 세로가 사다리(음 높이)라, 칸을 넘으면 그 음으로
  /// **미끄러진다**. 옥타브 쓸기는 없다 — 사다리가 그 자리를 가져갔고,
  /// 한 축에 두 뜻을 얹으면 사람이 구분해서 움직일 수 없다.
  ///
  /// **코드**는 사다리가 없으므로 예전대로 위아래 쓸기 = 옥타브다.
  void _pressMove(int pointer, Offset at, Size area) {
    final f = _fingers[pointer];
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

    // ── 코드: 위아래 쓸기 = 옥타브 ──
    // 쓸기는 **닿은 직후 한 동작만** 본다. 시간 제한이 없던 때에는, 긴 음을
    // 1~2초 잡고 있는 동안 손가락이 천천히 흘러내리기만 해도 쓸기로 읽혀
    // `holdOff` + `cancel` 이 돌았다 — 그 음이 **소리도 기록도 없이** 사라졌다.
    final sinceMs = DateTime.now().difference(f.downAt).inMilliseconds;
    if (sinceMs <= _kSwipeWindowMs &&
        dy.abs() >= _kSwipeSlop &&
        dy.abs() > dx.abs() * _kSwipeRatio) {
      f.swiped = true;
      widget.host?.holdOff(_kHoldId + f.pad);
      _rec?.cancel(f.pad);
      HapticFeedback.selectionClick();
      setState(() {
        // 위로 쓸면 위 옥타브(화면 좌표는 위가 작은 값이라 부호가 뒤집힌다).
        _octShift = (_octShift + (dy < 0 ? 1 : -1)).clamp(-1, 1);
      });
    }
  }

  /// 미끄러뜨려 다음 음으로 — 소리는 앞 주파수에서 이어 붙이고(`glideF`),
  /// 판에는 다섯째 칸에 1 을 적는다. 재생 쪽(`buildRowsPattern` 의 `n[4]==1`)이
  /// 같은 방식으로 앞 음에서 미끄러뜨리므로 **친 소리와 재생이 일치한다.**
  void _slideTo(_Finger f, int zone) {
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
    widget.host?.holdOff(_kHoldId + f.pad);
    if (_stageDef.kind == DoodleKind.chord && _fingers.isEmpty) {
      for (var i = 0; i < _kMaxChordTones; i++) {
        widget.host?.holdOff(_kChordId + i);
      }
    }
    if (!f.swiped && recording) {
      _rec?.up(f.pad, pos);
      // **톡** 치면 짧게 — 시간 축이라 어느 손짓과도 안 겹친다.
      // `lenOf` 의 바닥값이 격자 한 단위(8분이면 2칸)라, 이게 없으면 아무리
      // 톡 쳐도 전부 8분이 되어 스타카토 베이스를 아예 못 만든다.
      final heldMs = DateTime.now().difference(f.downAt).inMilliseconds;
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
  void _tickRoll() {
    final h = widget.host;
    if (h == null || _stageDef.kind != DoodleKind.drum) return;
    if (_fingers.isEmpty || _loopSec <= 0) return;
    final sixteenth = _stepSec;
    if (sixteenth <= 0) return;
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
      // 아직 롤이 시작될 때가 아니다(220ms 전에 떼면 그냥 한 방이다).
      if (next.isAfter(now.add(Duration(milliseconds: (_kRollAheadSec * 1000).round())))) {
        continue;
      }
      // 롤은 **격자에 맞춰** 돈다 — 기계가 내는 소리라 정확할 수 있고,
      // 격자에서 벗어나면 되레 어긋난 것으로 들린다.
      var guard = 0;
      while (next!.difference(now).inMicroseconds / 1e6 <= _kRollAheadSec &&
          guard++ < 8) {
        final ahead = next.difference(now).inMicroseconds / 1e6;
        // 지금부터 다음 16분 격자까지 남은 시간.
        final k = ((tInLoop + (ahead > 0 ? ahead : 0)) / sixteenth).ceil();
        final gridT = k * sixteenth;
        // `tInLoop` 은 **들리는** 자리인데 이 delay 는 **렌더 시계**에 얹힌다
        // (`_sendMet` 과 같은 함정). 빼 주지 않으면 롤이 버퍼 한 통만큼 늦게
        // 들리는데 판에는 격자에 정확히 찍혀서, 연주 중 귀와 「사용하기」 뒤
        // 재생이 서로 다르다. 칸 번호(`st`)는 그대로 둔다 — 그쪽이 맞다.
        var delay = gridT - tInLoop - _buffered / 48000.0;
        // 이미 지나간 격자는 **건너뛴다.** 0 으로 밀면 앞으로 튀어 박이 겹친다.
        if (delay < 0) {
          next = now.add(
            Duration(microseconds: ((gridT - tInLoop + sixteenth) * 1e6).round()),
          );
          continue;
        }
        if (delay > _kRollAheadSec) break;
        // 첫 한 방보다 살짝 여리게 — 진짜 롤이 그렇다.
        final rv = f.vel > 1 ? f.vel - 1 : 1;
        hits.add([_drumTrack.kit, lane, rv, 180.0, delay]);
        if (recording) {
          // 한 16분 = 한 칸이라 격자 번호가 곧 칸 번호다. 기계가 낸 시각이라
          // `TapRecorder`(사람 반응 지연을 되돌리는 계산)를 안 거친다.
          final st = ((k % steps) + steps) % steps;
          _rollSteps.add(st);
          _velOf[st] = rv;
        }
        next = now.add(
          Duration(microseconds: ((delay + sixteenth) * 1e6).round()),
        );
      }
      f.rollNext = next;
    }
    if (hits.isNotEmpty) h.drumBatch(hits);
  }

  void _retake() => setState(_armStage);

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
        final (prog, progSteps) = _prog();
        _bassNotes = _decorate(tapToNotes(
          const [], // 다시 녹음이면 이전 것을 지우고 새로 얹는다 — 한 판뿐이다
          _pending,
          prog: prog,
          progSteps: progSteps,
          steps: _bars * widget.project.spb,
          type: 'bass',
          chord: false,
          chromatic: false,
          mode: widget.transport.mode,
        ), chord: false);
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
        _chordNotes = _decorate(tapToNotes(
          const [],
          _pending,
          prog: prog,
          progSteps: progSteps,
          steps: _bars * widget.project.spb,
          type: 'chord',
          chord: true,
          chromatic: false,
          mode: widget.transport.mode,
          oct: _octShift,
        ), chord: true);
        widget.project.putUserPattern(
          'chord',
          _chordPatternName,
          note: NotePatternDef(_chordPatternName, _bars, _bars, _chordNotes,
              spb: widget.project.spb),
        );
    }
  }

  void _keep() {
    final h = widget.host;
    _commit();
    if (h != null) SceneSequencer.refreshLoop(widget.project, widget.transport, h);
    if (_stage + 1 >= kDoodleStages.length) {
      setState(() => _allDone = true);
    } else {
      setState(() {
        _stage++;
        _armStage();
      });
    }
  }

  void _openEditor() {
    // 방금 친 것부터 판에 적고 연다 — 안 적으면 빈 격자가 뜬다.
    _commit();
    final h = widget.host;
    if (h != null) SceneSequencer.refreshLoop(widget.project, widget.transport, h);
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
      canPop: _allDone,
      child: Scaffold(
        backgroundColor: const Color(0xFF101114),
        body: SafeArea(
          child: _allDone ? _doneBody() : (_reviewing ? _reviewBody() : _playBody()),
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: '그만하고 나가기',
            onPressed: () => Navigator.of(context).maybePop(),
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
                    color: Colors.white38,
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
          const SizedBox(width: 48), // 왼쪽 닫기 버튼과 균형
        ],
      ),
    );
  }

  /// 진행 표시 — ✓(끝) · ●(지금) · ○(아직). 지시서 8번: "메뉴가 아니라 진행
  /// 상황 표시" — 눌러서 건너뛸 수 없다.
  Widget _progress() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < kDoodleStages.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                children: [
                  Icon(
                    i < _stage
                        ? Icons.check_circle
                        : i == _stage
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: i <= _stage ? Colors.tealAccent : Colors.white24,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    kDoodleStages[i].label,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: i == _stage ? FontWeight.w800 : FontWeight.w500,
                      color: i <= _stage ? Colors.white70 : Colors.white24,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// 단계마다 다른 색 — 씬 화면의 트랙 색과 같은 계열로 맞춘다(드럼 초록·
  /// 베이스 파랑·코드 보라·가락 주황). 같은 악기를 두 화면에서 다른 색으로
  /// 보여 주면 같은 것인 줄 모른다.
  Color _stageColor() => switch (_stageDef.kind) {
    DoodleKind.drum => Colors.lightGreenAccent,
    DoodleKind.bass => Colors.lightBlueAccent,
    DoodleKind.chord => Colors.purpleAccent,
  };

  /// 친 순간 퍼지는 물결. 시계가 이미 30ms마다 `setState` 를 부르므로
  /// (`_tick`) 따로 애니메이션 장치를 두지 않는다 — 친 시각과 지금의 차로
  /// 그때그때 크기·진하기를 셈한다.
  List<Widget> _hitRipples(double d) {
    final at = _hitAt;
    if (at == null) return const [];
    final ms = DateTime.now().difference(at).inMilliseconds;
    if (ms > _kHitFx.inMilliseconds) return const [];
    final t = ms / _kHitFx.inMilliseconds; // 0 → 1
    return [
      Container(
        width: d + 40 * t,
        height: d + 40 * t,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: _stageColor().withValues(alpha: 0.55 * (1 - t)),
            width: 3,
          ),
        ),
      ),
    ];
  }

  /// 지금 음 높이가 몇 옥타브 옮겨져 있나 — 0이면 아무것도 안 띄운다
  /// (기본 상태에까지 이름표를 달면 화면만 시끄럽다).
  Widget _octBadge() {
    if (!_hasPitch || _octShift == 0) return const SizedBox(height: 26);
    // `Container` 에 `alignment` 를 주면 부모 폭을 다 먹는다 — `Center` 로
    // 감싸야 글자만큼만 차지하는 이름표가 된다(실기기에서 줄 전체로 늘어난
    // 것을 보고 잡았다).
    return Center(
      child: Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _stageColor().withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: _stageColor().withValues(alpha: 0.6)),
        ),
        child: Text(
          _octShift > 0 ? '한 옥타브 위' : '한 옥타브 아래',
          style: TextStyle(
            color: _stageColor(),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
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
    return Column(
      children: [
        _header(),
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
              return Listener(
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
                    if (_hasTone) _toneLadder() else _velTarget(area),
                    // 패드는 **「세게」 구역 그 자체**이고 화면 한가운데에 있다.
                    // 보이는 동그라미와 실제 과녁이 어긋나면 "가운데가 세게"가
                    // 그냥 거짓말이 된다(실기기에서 두 원이 따로 놀던 것을 보고
                    // 고쳤다). 베이스는 사다리가 악기라 패드를 안 그린다 —
                    // 없는 과녁을 그리면 거기를 치게 된다.
                    if (!_hasTone) _padCircle(area, phase, recording),
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
                          const SizedBox(height: 6),
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
                          _octBadge(),
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          _hintText(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white30,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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

  /// 이 단계에서 **실제로 듣는 손짓만** 적는다. 안 쓰는 것까지 적어 두면
  /// 해 봤는데 아무 일도 안 일어나서 "고장 난 화면"으로 보인다.
  String _hintText() => switch (_stageDef.kind) {
    DoodleKind.drum =>
      '아무 데나 쳐도 됩니다 · 한가운데가 세게, 가장자리가 여리게\n'
          '꾹 누르면 잘게 굴러갑니다 · 두 손가락으로 번갈아 쳐도 됩니다',
    DoodleKind.bass =>
      '위로 갈수록 높은 음 · 톡 치면 짧게, 잡으면 길게\n'
          '잡은 채 위아래로 끌면 미끄러집니다',
    DoodleKind.chord =>
      '아무 데나 쳐도 됩니다 · 한가운데가 세게\n'
          '손가락 두 개면 7화음, 세 개면 9화음 · 위아래로 쓸면 한 옥타브',
  };

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

  /// 치는 패드 = **「세게」 구역 그 자체**(`_kHardR`). 화면 한가운데.
  Widget _padCircle(Size area, TapPhase phase, bool recording) {
    final m = area.width < area.height ? area.width : area.height;
    final d = m * _kHardR * 2;
    return IgnorePointer(
      child: SizedBox(
        width: d,
        height: d,
        child: Stack(
          alignment: Alignment.center,
          children: [
            ..._hitRipples(d),
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _pressed
                    ? _stageColor().withValues(alpha: 0.30)
                    : recording
                    ? Colors.redAccent.withValues(alpha: 0.18)
                    : Colors.white10,
                border: Border.all(
                  color: _pressed
                      ? _stageColor()
                      : recording
                      ? Colors.redAccent
                      : Colors.white24,
                  width: 3,
                ),
              ),
              child: Center(
                child: Text(
                  phase == TapPhase.wait || phase == TapPhase.count
                      ? '곧 시작'
                      : _pressed
                      ? 'HOLD'
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
    return Column(
      children: [
        for (var i = _kLadderRows - 1; i >= 0; i--)
          Expanded(
            child: Container(
              width: double.infinity,
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 14),
              decoration: BoxDecoration(
                color: _stageColor().withValues(
                  alpha: live.contains(i) ? 0.20 : (i.isEven ? 0.045 : 0.020),
                ),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withValues(
                      alpha: i == _kLadderRows - 1 ? 0 : 0.05,
                    ),
                  ),
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
                _stage + 1 >= kDoodleStages.length ? '사용하기 · 완성' : '사용하기',
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
