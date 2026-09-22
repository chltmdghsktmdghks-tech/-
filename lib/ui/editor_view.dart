// 편집기 — **패턴 안의 음을 직접 찍는 곳.** 웹에서 가장 큰 화면의 첫 덩어리.
//
// ── 라이브러리 패턴은 못 고친다 ──
// `patterns.dart` 의 표는 `const` 상수다(그래야 앱 어디서 틀어도 같은 소리가 난다).
// 그래서 편집기에 들어오는 순간 **내 패턴으로 복사**한다(`Project.makeEditable`).
// 원본은 그대로 남는다 — 다른 씬이 그걸 쓰고 있을 수 있다.
//
// ── 격자 ──
// 가로 = 스텝(16분음표, 한 마디 16칸), 세로 = 드럼이면 **레인 10개**, 코드면 **도수 7개**,
// 나머지는 **도수 15개**(2옥타브+1 — `theory.dart degreeFreq` 가 자르는 범위와 같다).
// 아래가 낮은 음이다(악보와 같은 방향). 코드 트랙만 7줄인 이유: 코드는 도수를 7로 나눈
// 나머지만 쓴다(`buildChordPattern`). 15줄로 그리면 **8번째 줄이 1번째와 똑같은 소리**가
// 나서, 왜 다른 줄인데 같은 소리냐는 질문만 남는다.
//
// ── 음 하나를 고른다 (5단계 12/N) ──
// 예전엔 칸을 누르면 켜고/끄는 게 전부였다. 그래서 **길이·세기·글라이드를 못 만졌다**
// — 라이브러리 패턴은 그 셋으로 표정을 만드는데(같은 음도 짧게/여리게/미끄러져 들어오면
// 완전히 다르게 들린다), 편집기로 찍은 음은 전부 "2칸·보통·직진" 이라 밋밋했다.
// 지금은:
//   빈 칸 누르기      → 음을 찍고 **그 음이 골라진다**
//   음 누르기         → 고른다(아래 바가 그 음을 가리킨다)
//   고른 음 다시 누르기 → 지운다
// 길이는 **눈에 보인다** — 4칸짜리는 4칸을 차지하는 막대로 그린다(예전엔 전부 한 칸이라
// 길이가 있는 줄도 몰랐다). 세기는 막대 밝기로, 글라이드는 막대 왼쪽 표시로 보여준다.
//
// ── 재생하면서 고친다 ──
// 편집기 안에서도 ▶를 누를 수 있고, 한 칸 찍을 때마다 **다음 판부터** 소리에 반영된다
// (`refreshLoop`). 눈으로 찍고 귀로 바로 확인하는 게 이 화면의 전부다.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../audio_isolate.dart';
import '../edit_ops.dart';
import '../engine.dart' show noteNameIn;
import '../harmony.dart';
import '../meter.dart';
import '../pattern_names.dart';
import '../patterns.dart';
import '../project.dart';
import '../sequencer.dart';
import '../synth.dart' show kPartLive;
import '../tap_rec.dart';
import '../theory.dart';
import 'play_head.dart';
import 'prog_sheet.dart' show chordNameOf;
import 'tap_sheet.dart';

/// 레인 → 한글 이름. 격자 왼쪽에 붙인다.
const _laneLabel = {
  'kick': '킥',
  'snare': '스네어',
  'hat': '하이햇',
  'tom': '탐',
  'crash': '크래시',
  'rim': '림',
  'clap': '클랩',
  'shaker': '쉐이커',
  'cowbell': '카우벨',
  'ride': '라이드',
};

const _kCell = 30.0; // 한 스텝 칸 너비
// 한 줄 **최소** 높이. 28 이었는데 32 로 올렸다 — 줄 이름이 눌러서 소리를 듣는
// 자리가 되면서 **누를 것**이 됐고, 28 은 손가락 바닥선(세로 32) 아래다.
// 격자 칸도 같은 높이라 같이 커진다 — 원래도 여기가 제일 자주 빗나가는 자리였다.
// (줄은 ListView 안에 있어서, 자리가 모자라면 좁아지는 대신 스크롤이 생긴다)
const _kRow = 32.0;
const _kRowMax = 46.0; // 한 줄 최대 높이 — 자리가 남으면 여기까지 키운다

/// 줄 몇 개를 [h] 안에 놓을 때 한 줄 높이.
///
/// 예전엔 28 로 못 박아 뒀다. 그런데 드럼은 레인이 10개뿐이라 **격자 아래로
/// 화면의 40%가 텅 비었다**(그림으로 뽑아 보고 잡았다). 자리가 남으면 칸을 키운다 —
/// 큰 칸이 곧 누르기 쉬운 칸이다.
double rowHeightFor(double h, int rows) =>
    rows <= 0 ? _kRow : (h / rows).clamp(_kRow, _kRowMax).toDouble();
const _kHead = 62.0; // 왼쪽 이름칸 너비 — **가로 스크롤 밖**에 있다(밀어도 남는다)
const _kRulerH = 19.0; // 마디 자 높이
const _kHeadH = 14.0; // 재생 위치 줄 높이

/// 고른 음 하나. 드럼이면 [lane] 이 차 있고, 아니면 [degree] 가 줄 번호다.
class _Sel {
  final String? lane;
  final int degree;
  final int step;
  const _Sel({this.lane, required this.degree, required this.step});

  _Sel movedTo(int s) => _Sel(lane: lane, degree: degree, step: s);
}

/// 도수 → 사람이 읽는 이름. 0~6 은 1~7, 그 위는 화살표로 옥타브를 표시한다.
String _degLabel(int d) {
  final oct = d ~/ 7;
  return '${d % 7 + 1}${oct == 0 ? '' : (oct == 1 ? '↑' : '↑↑')}';
}

/// 그 줄이 실제로 **무슨 음인가** — `3↑` 옆에 `Eb5`.
///
/// 도수만 보면 무엇을 찍고 있는지 알 수 없다. 라이브 화면은 이미 음이름을 보여
/// 준다 — 같은 앱에서 한쪽만 알려 주면 사람은 **그쪽에서만 배운다.**
///
/// `bass` 는 실제 재생 음역(C1 기준)이라 여기서도 그 자리로 적는다 —
/// 화면에 C4 라고 써 놓고 C1 이 나면 그건 거짓말이다(`degreeFreq` 와 같은 식).
String noteNameFor(int degree, String type, MusicKey key) {
  final sc = scaleOf(key.mode);
  final d = degree.clamp(0, 14);
  final semi = sc[d % 7] + 12 * (d ~/ 7) + key.root;
  final midi = (type == 'bass' ? kBassBase : 60) + semi;
  return noteNameIn(midi, key.root, key.mode);
}

/// 음 막대에 적는 **코드 이름** — `Fm7`, 텐션·밑음이 붙으면 `Fm7(9)/Ab`.
///
/// 저장 글자(`min7+t9/4`)는 이 앱의 속사정이다. 막대에 필요한 것은 **읽는 이름**이다.
String chordBarLabel(int degree, String text, MusicKey? key) {
  if (key == null) return text;
  final c = parseChordText(text);
  final base = chordNameOf(
    degree % 7,
    key,
    type: c.type.isEmpty ? null : c.type,
  );
  final t = c.tensions.isEmpty
      ? ''
      : '(${[for (final x in c.tensions) kTensionLabel[x] ?? x].join(',')})';
  final b = c.bassDegree == null
      ? ''
      : '/${chordNameOf(c.bassDegree!, key, type: 'maj')}';
  return '$base$t$b';
}

/// 반음 줄의 음이름 — 0 = 그 조의 으뜸음.
String semiNameFor(int semi, String type, MusicKey key) {
  final s = semi.clamp(0, kProRows - 1);
  final midi = (type == 'bass' ? kBassBase : 60) + key.root + s;
  return noteNameIn(midi, key.root, key.mode);
}

/// 편집기에서 고를 수 있는 **코드 종류**.
///
/// `theory.dart` 는 스물넷을 알지만 **다 내놓지 않는다** — 「기능이 있다는 이유만으로
/// UI 에 다 노출하지 않는다」. 이 여섯이면 팝·재즈·로파이가 다 나오고, 이름도
/// 악보에서 보던 그대로다(dim7·m7b5 같은 것은 라이브러리 패턴이 쓰지만 직접 찍는
/// 사람이 찾을 이름이 아니다).
///
/// 첫 항목은 **되돌리기**다 — 잘못 골랐을 때 나가는 길이 없으면 안 된다.
const List<(String?, String)> kChordChoices = [
  (null, '기본'),
  ('min7', 'm7'),
  ('maj7', 'M7'),
  ('dom7', '7'),
  ('sus4', 'sus4'),
  ('sus2', 'sus2'),
  ('dim', 'dim'),
];

/// 스텝 → '2마디 3박' (16분 하나 어긋나면 뒤에 +1~3 을 붙인다)
///
/// [m] 이 그 판의 박자다 — /8 박자는 8분음표를 센다(6/8 에서 「6박」까지 나온다).
String _posLabel(int step, MeterDef m) {
  final bar = step ~/ m.stepsPerBar + 1;
  final inBar = step % m.stepsPerBar;
  final beat = meterBeatAt(m, step);
  final sub = inBar % m.clickSteps;
  return '$bar마디 $beat박${sub == 0 ? '' : '+$sub'}';
}

/// 씬 루프 안의 위치([pos], 0~1)를 **이 격자 안의 칸**으로 되접는다.
///
/// `pos` 의 기준자는 **씬 루프 한 바퀴**([loopBars]마디 — 그 씬에서 들리는 트랙 중
/// 제일 긴 패턴에 맞춘다)인데, 격자는 **지금 고치는 패턴**([steps]칸)이다.
/// 2마디짜리를 고치는데 씬에 4마디 패드가 있으면 루프는 4마디다 — 그대로 곱하면
/// 막대가 소리의 **절반 속도**로 기어가고, 격자를 한 바퀴 도는 동안 소리는 두 바퀴 돈다.
///
/// 되접어야 「지금 어느 칸이 울리고 있나」가 맞는다. 화면에서 떼어 놔야 시험할 수 있다.
double headStep(
  double pos, {
  required int steps,
  required int loopBars,
  int spb = kStepsPerBar,
}) {
  if (loopBars <= 0 || steps <= 0) return pos * steps;
  return (pos * loopBars * spb) % steps;
}

/// 재생 막대([x], 격자 안 절대 좌표)가 보이는 폭 밖으로 나갔을 때
/// **어디로 밀어야 하는지**. 이미 보이면 null(= 가만둔다).
///
/// 화면에서 떼어 놔야 시험할 수 있어 여기에 둔다. 규칙은 셋뿐이다:
///  · 보이는 폭의 5~92% 안에 있으면 안 건드린다 — 끝에 닿기 직전까지 놔둬야
///    매 프레임 밀어 대지 않는다.
///  · 밀 때는 **왼쪽 15%** 자리에 놓는다. 0% 에 놓으면 다음 순간 또 나간다.
///  · 밀 거리가 1px 도 안 되면 안 민다.
double? followTarget({
  required double x,
  required double offset,
  required double viewport,
  required double maxScroll,
}) {
  if (viewport <= 0 || maxScroll <= 0) return null;
  if (x >= offset + viewport * 0.05 && x <= offset + viewport * 0.92) {
    return null; // 이미 보인다
  }
  final want = (x - viewport * 0.15).clamp(0.0, maxScroll);
  return (want - offset).abs() < 1 ? null : want;
}

class EditorView extends StatefulWidget {
  final Project project;
  final Transport transport;
  final Track track;
  final AudioClient? host;

  /// **프로 모드**(설정) — 켜져 있으면 줄 손잡이를 꾹 눌러 반음 줄로 바꿀 수 있다.
  final bool pro;

  const EditorView({
    super.key,
    required this.project,
    required this.transport,
    required this.track,
    required this.host,
    this.pro = false,
  });

  @override
  State<EditorView> createState() => _EditorViewState();
}

class _EditorViewState extends State<EditorView> {
  late String _name;
  double _loopSec = 0;

  /// 씬 루프 한 바퀴가 몇 마디인가 — 재생 막대를 격자 칸으로 되접을 때 쓴다.
  /// 이걸 안 들고 있어서 `pos` 를 **이 패턴의 길이**로 곱했다([headStep] 참고).
  int _loopBars = 0;
  _Sel? _sel;

  /// 한 칸 너비. 4마디(64칸)를 30px 로 그리면 **다섯 번 밀어야 끝까지 본다** →
  /// 촘촘 보기(18px)를 뒀다. 더 줄이면 손가락으로 못 찍는다(칸이 손끝보다 작아진다).
  double _cell = _kCell;
  final _hs = ScrollController();

  // ── 재생 위치 따라가기 ──
  //
  // 4마디 판은 64칸 × 30px = **1920px** 인데 화면에 보이는 건 280px 남짓이다.
  // 그래서 재생을 눌러도 **재생 막대가 시간의 85% 를 화면 밖에** 있었다.
  // 지금 어디를 치고 있는지 안 보이는 편집기는 반쪽이다.
  //
  // 다만 **고치는 중에는 안 따라간다.** 음을 찍고 있는데 화면이 저 혼자 넘어가면
  // 다음 손가락이 엉뚱한 칸에 떨어진다. 손을 대면(찍기·끌기·마디 버튼·손으로 밀기)
  // 5초 동안 가만히 있는다 — 손을 떼고 듣기 시작하면 다시 따라간다.
  int _holdUntilMs = 0;
  bool _autoScrolling = false;
  void _holdFollow() =>
      _holdUntilMs = DateTime.now().millisecondsSinceEpoch + 5000;

  /// 촘촘 보기 — 칸 너비를 바꾸면서 **보던 자리를 지킨다.**
  ///
  /// 예전엔 `_cell` 만 바꿨다. 스크롤 위치는 픽셀이라 그대로 남는데 한 칸의
  /// 너비가 달라지므로, 3마디를 보고 있다가 촘촘히 하면 **4마디가 보인다.**
  /// 찾아 놓은 자리를 다시 찾아야 했다.
  void _zoom() {
    final next = _cell < _kCell ? _kCell : 18.0;
    final atStep = _hs.hasClients ? _hs.offset / _cell : 0.0;
    setState(() => _cell = next);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hs.hasClients) return;
      _holdFollow(); // 손으로 옮긴 것이니 잠시 안 따라간다
      _hs.jumpTo((atStep * next).clamp(0.0, _hs.position.maxScrollExtent));
    });
  }

  /// 재생 막대가 보이는 폭을 벗어나면 **왼쪽 15% 자리로** 끌어온다.
  void _followPlayhead(double pos) {
    if (!mounted || !_hs.hasClients || _autoScrolling) return;
    if (DateTime.now().millisecondsSinceEpoch < _holdUntilMs) return;
    final p = _hs.position;
    final want = followTarget(
      x: headStep(pos, steps: steps, loopBars: _loopBars) * _cell,
      offset: _hs.offset,
      viewport: p.viewportDimension,
      maxScroll: p.maxScrollExtent,
    );
    if (want == null) return;
    _autoScrolling = true;
    _hs
        .animateTo(
          want,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        )
        .whenComplete(() => _autoScrolling = false);
  }

  /// 되돌리기 — 고치기 **직전**의 판을 쌓아 둔다.
  ///
  /// 이 화면에는 되돌리기가 없었다. 「지우기」는 확인도 없이 판 전체를 날리고,
  /// 실수로 음을 지우면 어디에 뭐가 있었는지 기억으로 복원해야 했다.
  /// 판 하나는 커야 음 100개 남짓이라 **20벌을 들고 있어도 부담이 없다.**
  final List<Object> _undo = [];

  /// **다시하기.** 되돌리기를 한 칸 더 눌렀을 때 되찾는 자리다.
  /// 여태는 되돌리기만 있어서, 한 칸 지나치면 그 편집은 영영 없었다 —
  /// 「되돌리기」가 있으면 사람은 **마음 놓고 되돌린다.** 짝이 있어야 그게 산다.
  ///
  /// 판을 새로 고치면 비운다(그 자리에서 갈라진 미래는 더 못 따라간다).
  final List<Object> _redo = [];
  static const _kUndoMax = 20;

  /// 지금 판을 **깊은 복사**로 뜬다 — 되돌리기·다시하기가 같은 자를 쓴다.
  Object? _snap() {
    final p = widget.project;
    if (isDrum) {
      final d = p.findDrum(_name);
      if (d == null) return null;
      return DrumPatternDef(
        d.name,
        d.bars,
        d.src,
        {for (final e in d.hits.entries) e.key: List<int>.from(e.value)},
        d.vels == null
            ? null
            : {for (final e in d.vels!.entries) e.key: List<int>.from(e.value)},
      );
    }
    final n = p.findNote(t.type, _name);
    if (n == null) return null;
    return NotePatternDef(
      n.name,
      n.bars,
      n.src,
      [for (final x in n.notes) List<Object?>.from(x)],
      also: [for (final x in n.also) List<Object?>.from(x)],
      chromatic: n.chromatic,
    );
  }

  /// 뜬 판을 실제로 얹는다.
  void _apply(Object v) {
    if (v is DrumPatternDef) {
      widget.project.putUserPattern('drum', _name, drum: v);
    } else if (v is NotePatternDef) {
      widget.project.putUserPattern(t.type, _name, note: v);
    }
  }

  // ── 꾹 눌러 끌기 (5단계 44/N) ──
  //
  // 버튼으로만 고치면 화면 아래 바를 계속 봐야 한다. 손가락이 이미 그 음 위에 있는데
  // 눈을 아래로 옮겨 「길이 +」를 찾는 건 낭비다. 그래서 **음 위에서 바로** 고친다:
  //   · 있는 음을 꾹 눌러 **좌우** → 길이
  //   · 있는 음을 꾹 눌러 **위아래** → **높낮이**(줄 사이로 옮긴다)
  //   · 빈 칸을 꾹 눌러 **좌우** → 음이 쫘르륵 깔린다
  //
  // 세로가 여태 「세기」였는데 **높낮이로 바꿨다.** 두드려 넣기가 생기면서
  // 「박자는 맞는데 음이 아직 제자리가 아닌 음」이 한 판에 열 개씩 생기기 때문이다 —
  // 그걸 고치는 길이 「지우고 옆 줄에 다시 찍기」 두 번이면 두드린 보람이 없다.
  // 세기는 아래 바의 여리게·보통·세게로 간다(거기 이미 있었다).
  //
  // 왜 '꾹 눌러' 인가: 격자는 **가로로 스크롤**된다. 그냥 끌면 화면이 밀린다.
  // 길게 누르면 스크롤과 안 싸운다(누르고 있는 동안은 스크롤이 안 잡는다).
  _Drag? _drag;

  /// **지우개.** 켜면 격자를 훑어 지나간 음이 계속 지워진다.
  ///
  /// 여태 지우는 길은 둘뿐이었다 — 하나씩 두 번 누르기, 아니면 판 전체 날리기.
  /// 16비트 하이햇 한 줄을 지우려면 32번이다. **하나와 전부 사이가 비어 있었다.**
  bool _erase = false;

  /// 끌기 방향이 정해지는 거리(px). 이만큼 움직이기 전에는 아무 일도 안 한다 —
  /// 손을 대는 순간의 1~2px 떨림으로 방향이 정해지면 늘 엉뚱한 쪽이 잡힌다.
  static const _kAxisLock = 8.0;

  /// 세로 스크롤이 둘이다 — 왼쪽 이름 칸과 오른쪽 격자. 손가락은 격자만 만지고,
  /// 이름 칸은 그대로 따라온다(하나의 컨트롤러를 둘에 붙일 수는 없다).
  final _vsLabel = ScrollController();
  final _vsGrid = ScrollController();

  Track get t => widget.track;
  bool get isDrum => t.type == 'drum';

  /// **덧줄을 고치는 중인가.**
  ///
  /// 판 하나가 화음과 낱음을 **둘 다** 들 수 있다(`NotePatternDef.also`) —
  /// 패드로 화음을 깔면서 그 위에 낱음 몇 개를 얹는 것이 한 판 안에서 된다.
  /// 줄 수도 다루는 것도 다르니 **한 번에 한 줄씩** 고친다(옛 앱도 그랬다).
  bool _alt = false;

  /// 지금 고치는 것이 화음인가. 덧줄에서는 **뒤집힌다** —
  /// 화음 판의 덧줄은 낱음이고, 가락 판의 덧줄은 화음이다.
  bool get isChord => (t.type == 'chord') != _alt;

  /// **반음 줄(프로 모드)** 인가 — 지금 보고 있는 줄 기준.
  ///
  /// 화음 줄과 덧줄에는 해당이 없다(화음은 도수로 고르고, 덧줄은 늘 도수 줄이다).
  bool get _chro =>
      !isDrum &&
      !isChord &&
      !_alt &&
      (widget.project.findNote(t.type, _name)?.chromatic ?? false);

  /// 화음은 도수를 7로 나눈 나머지만 쓴다 → 7줄. 낱음(멜로디/베이스)은 15줄.
  /// 반음 줄은 25줄(2옥타브+1).
  int get rows =>
      isDrum ? kDrumLanes.length : (isChord ? 7 : (_chro ? kProRows : 15));

  @override
  void initState() {
    super.initState();
    // 들어오자마자 내 패턴으로 만든다(라이브러리 원본은 안 건드린다)
    _name = widget.project.makeEditable(t);
    _vsGrid.addListener(_syncLabels);
    _push();
  }

  /// 격자를 세로로 밀면 왼쪽 이름 칸도 같은 만큼 민다.
  void _syncLabels() {
    if (!_vsLabel.hasClients) return;
    if ((_vsLabel.offset - _vsGrid.offset).abs() < 0.5) return;
    _vsLabel.jumpTo(
      _vsGrid.offset.clamp(
        _vsLabel.position.minScrollExtent,
        _vsLabel.position.maxScrollExtent,
      ),
    );
  }

  @override
  void dispose() {
    _hs.dispose();
    _vsGrid.removeListener(_syncLabels);
    _vsGrid.dispose();
    _vsLabel.dispose();
    super.dispose();
  }

  /// 같은 편집기 화면에 **다른 트랙이 실릴 수 있다**(Flutter 는 같은 자리의 같은 종류
  /// 위젯을 재사용한다 — `initState` 가 다시 안 불린다). 그때 이름을 안 바꾸면
  /// 드럼을 열어 놓고 **앞 트랙의 패턴을 고치게 된다.** 위젯 시험이 이걸 잡았다.
  @override
  void didUpdateWidget(covariant EditorView old) {
    super.didUpdateWidget(old);
    if (old.track != widget.track) {
      _sel = null;
      // **줄도 본줄로 돌린다.** 안 그러면 화음 판의 낱음 줄을 보다가 트랙을
      // 바꿨을 때 딴 악기의 덧줄이 열린다 — 뭘 고치고 있는지 알 수 없다.
      _alt = false;
      _name = widget.project.makeEditable(widget.track);
      _push();
    }
  }

  int get bars => isDrum
      ? (widget.project.findDrum(_name)?.bars ?? 2)
      : (widget.project.findNote(t.type, _name)?.bars ?? 2);

  /// 이 곡의 박자 — **곡 하나는 박자 하나다**([Project.meter] 참고).
  MeterDef get meter => widget.project.meterDef;

  /// 이 박자의 한 마디가 몇 칸인가.
  int get spb => meter.stepsPerBar;

  int get steps => bars * spb;

  // ── 지금 찍혀 있는 것 읽기 ──

  /// 드럼: 레인별 스텝·세기(자리가 맞는 두 목록). 계산은 `edit_ops.dart` 가 한다.
  DrumOps get _drum => DrumOps.read(widget.project.findDrum(_name));

  /// 멜로디/베이스/코드: [도수, 스텝, 길이, 세기, (글라이드|코드타입)]
  /// 덧줄을 고치는 중이면 **덧줄**을 돌려준다.
  List<List<Object?>> get _notes {
    final d = widget.project.findNote(t.type, _name);
    if (d == null) return const [];
    return _alt ? d.also : d.notes;
  }

  /// 반대쪽 줄에 몇 음이 있나 — 손잡이에 적어서 **거기 뭔가 있다**를 알린다.
  int get _otherCount {
    final d = widget.project.findNote(t.type, _name);
    if (d == null) return 0;
    return _alt ? d.notes.length : d.also.length;
  }

  /// 아무것도 안 찍힌 판인가 — 안내 한 줄을 띄울지 정한다.
  bool get _isEmpty =>
      isDrum ? _drum.steps.values.every((s) => s.isEmpty) : _notes.isEmpty;

  List<Object?>? _noteAt(int degree, int step) {
    final i = _notes.indexWhere((n) => n[0] == degree && n[1] == step);
    return i < 0 ? null : _notes[i];
  }

  /// 그 칸을 **덮고 있는** 음. 음은 `[도수, 시작칸, 길이, …]` 라 한 칸이 아니라
  /// 여러 칸에 걸쳐 있다.
  ///
  /// 여태 손끝 판정이 [_noteAt] (= **시작 칸이 정확히 같은 것**)만 봤다.
  /// 그래서 4칸짜리 음의 3번째 칸을 누르면 **빈 칸으로 읽혀 그 위에 새 음을
  /// 하나 더 깔았다**(사용자 신고, 2026-09-22: "긴 블럭의 중간 부분을 길게
  /// 누르면 그 블럭을 잡아야지 왜 새로 생성되니"). 눈에는 한 덩어리로 보이는데
  /// 만질 수 있는 곳은 왼쪽 끝 한 칸뿐이었던 셈이다.
  ///
  /// 잡은 뒤에 쓰는 값은 **그 음의 시작 칸**이어야 한다 — 길이 고치기
  /// (`NoteOps.setLen`)도 줄 옮기기도 시작 칸으로 음을 찾는다.
  List<Object?>? _noteCovering(int degree, int step) {
    for (final n in _notes) {
      if (n[0] != degree) continue;
      final s = n[1] as int;
      final len = n[2] as int;
      if (step >= s && step < s + len) return n;
    }
    return null;
  }

  /// 고치기 직전에 부른다 — **지금 판을 복사해서** 쌓는다.
  /// 얕은 복사면 안 된다(같은 목록을 가리키면 되돌려도 그대로다).
  void _snapshot() {
    // 끄는 중에는 안 쌓는다 — 한 번 끈 건 **한 번에** 되돌아가야 한다
    if (_drag != null) return;
    // 되돌린 뒤에 **새로 고치면** 그 앞의 「다시하기」는 더 못 간다.
    // (안 비우면 엉뚱한 판이 되돌아온다 — 편집기에서 제일 헷갈리는 종류다)
    _redo.clear();
    final p = widget.project;
    if (isDrum) {
      final d = p.findDrum(_name);
      if (d == null) return;
      _undo.add(
        DrumPatternDef(
          d.name,
          d.bars,
          d.src,
          {for (final e in d.hits.entries) e.key: List<int>.from(e.value)},
          d.vels == null
              ? null
              : {
                  for (final e in d.vels!.entries)
                    e.key: List<int>.from(e.value),
                },
        ),
      );
    } else {
      final n = p.findNote(t.type, _name);
      if (n == null) return;
      _undo.add(
        NotePatternDef(
          n.name,
          n.bars,
          n.src,
          [for (final x in n.notes) List<Object?>.from(x)],
          also: [for (final x in n.also) List<Object?>.from(x)],
          chromatic: n.chromatic,
        ),
      );
    }
    if (_undo.length > _kUndoMax) _undo.removeAt(0);
  }

  /// 한 걸음 되돌린다. **되돌리기 전 판을 다시하기 통에 담는다.**
  void _undoOnce() {
    if (_undo.isEmpty) return;
    final now = _snap();
    final prev = _undo.removeLast();
    _sel = null;
    if (now != null) {
      _redo.add(now);
      if (_redo.length > _kUndoMax) _redo.removeAt(0);
    }
    _apply(prev);
    _push();
  }

  /// 한 걸음 다시한다 — 되돌리기의 짝.
  void _redoOnce() {
    if (_redo.isEmpty) return;
    final now = _snap();
    final next = _redo.removeLast();
    _sel = null;
    if (now != null) {
      _undo.add(now);
      if (_undo.length > _kUndoMax) _undo.removeAt(0);
    }
    _apply(next);
    _push();
  }

  // ── 고치기: 드럼 ──

  void _writeDrum(DrumOps d, {int? nb}) {
    widget.project.putUserPattern(
      'drum',
      _name,
      drum: d.toDef(_name, nb ?? bars),
    );
    _push();
  }

  /// **줄 이름을 누르면 그 줄 소리가 난다.**
  ///
  /// 15줄 중 어디에 찍을지, 드럼 10레인이 각각 무슨 소리인지 — 여태 **찍어 봐야만**
  /// 알 수 있었다. 찍고 듣고 지우는 세 번이 「들어 보기」 한 번이 된다.
  /// (라이브 화면은 이미 이렇게 한다. 편집기만 안 하고 있었다)
  void _preview(int rowFromTop) {
    final h = widget.host;
    if (h == null) return;
    h.setSongMode(false); // 손가락에 붙어야 한다
    if (isDrum) {
      final lane = kDrumLanes[rowFromTop];
      h.drumOn(t.kit, lane, 3);
      return;
    }
    final degree = rows - 1 - rowFromTop;
    final key = MusicKey(
      root: widget.transport.root,
      mode: widget.transport.mode,
    );
    if (isChord) {
      // 코드 줄은 **그 도수의 코드 전체**를 들려준다 — 한 음만 나면 코드인지 모른다
      h.batch([
        for (final f in chordFreqsOf(diatonicChords(key)[degree % 7]))
          [t.voice, f, 0.9, 3, true, 0.0, 0.0, kPartLive],
      ]);
      return;
    }
    h.batch([
      [
        t.voice,
        _chro ? semiFreq(degree, t.type, key) : degreeFreq(degree, t.type, key),
        0.7,
        3,
        false,
        0.0,
        0.0,
        kPartLive,
      ],
    ]);
  }

  void _tapDrum(String lane, int step) {
    _holdFollow(); // 고치는 중엔 화면이 저 혼자 넘어가면 안 된다
    if (_erase) {
      if (_drum.indexOf(lane, step) < 0) return;
      _snapshot();
      _eraseAt(lane, 0, step);
      return;
    }
    final d = _drum;
    // **고르기만 한 것은 되돌릴 거리가 아니다.** `_snapshot()` 이 이 위에 있어서,
    // 이미 찍힌 칸을 눌러 고르기만 해도 판이 하나도 안 바뀐 기록이 쌓였다.
    // 그러면 되돌리기를 눌러도 **같은 판으로 되돌아가** 아무 일도 안 일어난다.
    // 되돌리기가 몇 번씩 헛도는 것은 「고장 났나」로 보인다. 고치는 갈래에서만 쌓는다.
    if (d.indexOf(lane, step) >= 0) {
      final sel = _sel;
      if (sel != null && sel.lane == lane && sel.step == step) {
        _snapshot();
        d.remove(lane, step); // 고른 걸 다시 누르면 지운다
        _sel = null;
        _writeDrum(d);
      } else {
        setState(() => _sel = _Sel(lane: lane, degree: 0, step: step));
      }
      return;
    }
    _snapshot();
    d.add(lane, step);
    _sel = _Sel(lane: lane, degree: 0, step: step);
    _writeDrum(d);
  }

  void _setDrumVel(String lane, int step, int vel) {
    _snapshot();
    _writeDrum(_drum..setVel(lane, step, vel));
  }

  void _moveDrum(String lane, int step, int by) {
    final d = _drum;
    if (!d.move(lane, step, by, steps)) return;
    _snapshot();
    _sel = _sel?.movedTo(step + by);
    _writeDrum(d);
  }

  void _deleteDrum(String lane, int step) {
    _snapshot();
    final d = _drum..remove(lane, step);
    _sel = null;
    _writeDrum(d);
  }

  // ── 고치기: 멜로디/베이스/코드 ──

  void _say(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(msg, style: const TextStyle(fontSize: 12.5)),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(milliseconds: 2200),
        ),
      );
  }

  // ── 두드려 넣기 (5단계 46/N) ──
  //
  // 어려운 박자는 손으로 못 찍는다. 머릿속 리듬을 격자의 몇 번째 칸으로 옮겨 적으려면
  // 그 리듬을 **이미 셀 줄 알아야** 하는데, 셀 줄 알면 애초에 어렵지 않다.
  // 그래서 순서를 바꾼다 — **박자는 두드려 넣고, 높낮이는 나중에 끌어 올린다.**
  // 한 번에 하나씩만 하면 되는 일이 된다.
  //
  // 담기는 곳은 **지금 보고 있는 줄**이다(덧줄을 보고 있으면 덧줄에). 무엇을 고치는
  // 중인지 화면이 이미 말하고 있으니, 여기서 또 고르게 하면 묻는 것만 늘어난다.
  Future<void> _tapRecord() async {
    var clear = false;
    if (!_isEmpty) {
      // **말없이 지우지 않는다.** 되돌리기가 있어도, 방금 만든 것이 사라지는 순간의
      // 놀람은 되돌려지지 않는다.
      final pick = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF16181C),
          title: const Text(
            '이 판에 이미 음이 있습니다',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
          ),
          content: const Text(
            '두드린 것을 어떻게 담을까요?',
            style: TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'add'),
              child: const Text('위에 더하기'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'clear'),
              child: const Text('지우고 시작'),
            ),
          ],
        ),
      );
      if (pick == null || !mounted) return;
      clear = pick == 'clear';
    }
    _holdFollow();
    final hits = await tapRecordSheet(
      context,
      project: widget.project,
      transport: widget.transport,
      host: widget.host,
      track: t,
      steps: steps,
      bars: bars,
      isDrum: isDrum,
      isChord: isChord,
      chromatic: _chro,
    );
    if (!mounted) return;
    setState(() {}); // 시트가 반주를 틀었을 수 있다 — 재생/정지 단추를 맞춘다
    if (hits == null) return;
    if (hits.isEmpty) {
      _say('아무것도 안 두드렸습니다');
      return;
    }
    _snapshot();
    _applyTaps(hits, clear: clear);
    _say('${hits.length}개를 넣었습니다 — 음을 꾹 눌러 위아래로 끌면 높낮이가 바뀝니다');
  }

  /// 두드린 것을 판에 적는다. 높낮이는 **그 자리에 흐르는 코드의 뿌리음**이다
  /// (`tapDegree`) — 찍자마자 어울려 들려야 고치는 일이 「고르는 일」이 된다.
  void _applyTaps(List<TapHit> hits, {required bool clear}) {
    if (isDrum) {
      final d = clear ? DrumOps.read(null) : _drum;
      for (final h in hits) {
        d.add(kTapDrumPads[h.pad].$1, h.step);
      }
      _sel = null;
      _writeDrum(d);
      return;
    }
    final (prog, progSteps) = widget.project.readSceneProg();
    _sel = null;
    _writeNotes(
      tapToNotes(
        _notes,
        hits,
        prog: prog,
        progSteps: progSteps,
        steps: steps,
        type: t.type,
        chord: isChord,
        chromatic: _chro,
        mode: widget.transport.mode,
        oct: isChord ? NoteOps.chordOct(_notes) : 0,
        clear: clear,
      ),
    );
  }

  /// 프로 모드가 꺼져 있을 때 — **어디서 켜는지** 알려 준다.
  void _proHint() {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            '설정 ▸ 프로 모드를 켜면 여기서 반음(검은 건반)까지 찍을 수 있어요',
            style: TextStyle(fontSize: 12.5),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// **도수 줄 ↔ 반음 줄.** 찍어 둔 것을 좌표계째 옮긴다.
  ///
  /// 그냥 깃발만 바꾸면 도수 7(한 옥타브 위)이 반음 7(5도)이 되어 **가락이 딴
  /// 가락이 된다.** 되돌리기에도 쌓아 둔다 — 되돌아올 길이 있어야 마음 놓고 켠다.
  void _toggleChromatic() {
    final cur = widget.project.findNote(t.type, _name);
    if (cur == null) return;
    _snapshot();
    final mode = widget.transport.mode;
    final to = !cur.chromatic;
    final moved = to
        ? NoteOps.toChromatic(cur.notes, mode)
        : NoteOps.toDegrees(cur.notes, mode);
    widget.project.putUserPattern(
      t.type,
      _name,
      note: NotePatternDef(
        _name,
        cur.bars,
        cur.src,
        moved,
        also: cur.also,
        chromatic: to,
      ),
    );
    setState(() => _sel = null);
    _push();
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            to ? '반음 줄로 바꿨습니다 — 검은 건반까지 찍힙니다' : '도수 줄로 돌아왔습니다 — 조에 맞는 음만 찍힙니다',
            style: const TextStyle(fontSize: 12.5),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// 지금 고치는 줄을 쓴다. **반대쪽 줄은 그대로 들고 간다** — 안 그러면 낱음을
  /// 얹어 둔 판에서 화음을 한 번 고치는 순간 얹어 둔 것이 조용히 사라진다
  /// (짝이 하나 없는 그 모양이다).
  void _writeNotes(List<List<Object?>> list, {int? nb}) {
    final cur = widget.project.findNote(t.type, _name);
    final b = nb ?? bars;
    widget.project.putUserPattern(
      t.type,
      _name,
      // **바꿀 것만 적는다**(`copyWith`) — 반대쪽 줄과 반음 줄 깃발을 손으로
      // 옮기다 보면 언젠가 한 번 빠뜨린다. 그러면 얹어 둔 것이 조용히 사라진다.
      note:
          cur?.copyWith(
            bars: b,
            src: b,
            notes: _alt ? cur.notes : list,
            also: _alt ? list : cur.also,
          ) ??
          NotePatternDef(
            _name,
            b,
            b,
            _alt ? const [] : list,
            also: _alt ? list : const [],
          ),
    );
    _push();
  }

  void _tapNote(int degree, int step) {
    _holdFollow(); // 고치는 중엔 화면이 저 혼자 넘어가면 안 된다
    // **덮고 있는 음**을 본다 — 긴 음의 가운데를 눌러도 그 음이 잡혀야 한다
    // (`_noteCovering` 주석). 잡은 뒤에 쓰는 칸은 그 음의 **시작 칸**이다.
    final found = _noteCovering(degree, step);
    final hit = found == null ? step : found[1] as int;
    if (_erase) {
      if (found == null) return;
      _snapshot();
      _eraseAt(null, degree, hit);
      return;
    }
    final sel = _sel;
    // 고르기만 한 것은 되돌릴 거리가 아니다 — `_tapDrum` 과 같은 이유다.
    if (found != null) {
      if (sel != null &&
          sel.lane == null &&
          sel.degree == degree &&
          sel.step == hit) {
        _snapshot();
        _sel = null; // 고른 걸 다시 누르면 지운다
        _writeNotes(NoteOps.remove(_notes, degree, hit));
      } else {
        setState(() => _sel = _Sel(degree: degree, step: hit));
      }
      return;
    }
    _snapshot();
    // 같은 스텝의 다른 도수는 그대로 둔다 — 화음도 찍을 수 있어야 한다.
    _sel = _Sel(degree: degree, step: step);
    _writeNotes(
      NoteOps.add(_notes, degree, step, isChord: isChord, steps: steps),
    );
  }

  /// 판 안의 음 길이를 **통째로** 한 칸씩 — 스타카토 ↔ 레가토.
  /// 드럼은 길이가 없다(칠 뿐이다) → 그쪽에는 안 나온다.
  void _stretchAll(int dir) {
    if (isDrum) return;
    _snapshot();
    _writeNotes(NoteOps.stretchAll(_notes, dir, steps: steps));
  }

  void _setLen(int len) {
    final s = _sel;
    if (s == null) return;
    _snapshot();
    _writeNotes(NoteOps.setLen(_notes, s.degree, s.step, len, steps: steps));
  }

  void _setVel(int vel) {
    final s = _sel;
    if (s == null) return;
    _snapshot();
    _writeNotes(NoteOps.setVel(_notes, s.degree, s.step, vel));
  }

  /// 코드 종류 — 3화음 → 7th · sus4 · dim …
  ///
  /// `theory.dart` 는 처음부터 스물네 가지를 알고 있었고 라이브러리 패턴도
  /// 쓰고 있었는데, **편집기에서 고를 길이 없었다** — 직접 찍는 코드는 무엇을
  /// 찍어도 기본 3화음뿐이라 코드 트랙의 색이 하나로 고정돼 있었다.
  void _setChordType(String? type) {
    final s = _sel;
    if (s == null) return;
    _snapshot();
    _writeNotes(
      NoteOps.setChordType(_notes, s.degree, s.step, type, isChord: isChord),
    );
  }

  /// 글라이드 — 앞 음 높이에서 미끄러져 들어온다(코드 트랙은 해당 없음).
  void _toggleGlide() {
    final s = _sel;
    if (s == null) return;
    _snapshot();
    _writeNotes(
      NoteOps.toggleGlide(_notes, s.degree, s.step, isChord: isChord),
    );
  }

  void _moveNote(int by) {
    final s = _sel;
    if (s == null) return;
    final next = NoteOps.move(_notes, s.degree, s.step, by, steps: steps);
    if (next.every((n) => !(n[0] == s.degree && n[1] == s.step + by))) return;
    _snapshot();
    _sel = s.movedTo(s.step + by);
    _writeNotes(next);
  }

  void _deleteNote() {
    final s = _sel;
    if (s == null) return;
    _snapshot();
    _sel = null;
    _writeNotes(NoteOps.remove(_notes, s.degree, s.step));
  }

  // ── 마디 수 · 비우기 ──

  /// 마디 수 바꾸기 — 늘리면 뒤가 비고, 줄이면 범위 밖 음은 버린다.
  void _setBars(int b) {
    final nb = b.clamp(1, 8);
    if (nb == bars) return;
    _snapshot();
    final limit = nb * spb;
    _sel = null;
    if (isDrum) {
      _writeDrum(_drum..trimTo(limit), nb: nb);
    } else {
      _writeNotes(NoteOps.trimTo(_notes, limit), nb: nb);
    }
  }

  // ── 어울리는 코드 고르기 (계획 6-4) ──

  /// 지금 씬에서 **같이 울리는** 멜로디. 없으면 null(버튼이 흐려진다).
  List<List<Object?>>? _sceneMelody() {
    final p = widget.project;
    for (final tr in p.tracks) {
      if (tr.type != 'melody' || !p.audible(tr)) continue;
      final clip = p.scene.clips[tr.id];
      if (clip == null) continue;
      final def = p.findNote('melody', clip);
      // **반음 줄 판은 못 읽는다** — 같은 숫자라도 뜻이 다르다(도수 7 = 옥타브,
      // 반음 7 = 5도). 그대로 넘기면 엉뚱한 코드를 골라 준다.
      // 도수로 옮겨서 넘긴다 — 조에 없는 음은 제일 가까운 음으로 붙는다.
      if (def == null || def.notes.isEmpty) continue;
      return def.chromatic
          ? NoteOps.toDegrees(def.notes, widget.transport.mode)
          : def.notes;
    }
    return null;
  }

  /// 멜로디를 보고 코드 판을 새로 채운다. **되돌리기가 받쳐 준다** —
  /// 판 전체를 갈아엎는 일이라 마음에 안 들면 되돌릴 수 있어야 한다.
  void _fitToMelody() {
    final mel = _sceneMelody();
    if (mel == null) return;
    _snapshot();
    _sel = null;
    final picks = suggestChords(
      mel,
      bars: bars,
      key: MusicKey(root: widget.transport.root, mode: widget.transport.mode),
      spb: spb,
    );
    // 이 줄이 앉아 있던 **층**은 지키고 코드만 갈아 끼운다 —
    // 위층을 맡던 줄(비브라폰·스트링)이 한 옥타브 떨어지면 패드와 다시 겹친다.
    final oct = NoteOps.chordOct(_notes);
    final rows = chordRowsOf(picks);
    if (oct != 0) {
      for (final r in rows) {
        while (r.length < 5) {
          r.add(null);
        }
        if (r.length < 6) {
          r.add(oct);
        } else {
          r[5] = oct;
        }
      }
    }
    _writeNotes(rows);
  }

  void _clear() {
    _snapshot(); // 판 전체를 날린다 — 되돌릴 수 있어야 한다
    _sel = null;
    if (isDrum) {
      widget.project.putUserPattern(
        'drum',
        _name,
        drum: DrumPatternDef(_name, bars, bars, const {}),
      );
      _push();
    } else {
      _writeNotes(const []);
    }
  }

  // ── 꾹 눌러 끌기 ──

  /// 화면 좌표 → (줄, 칸). 격자 밖이면 null.
  (int, int)? _cellAt(Offset at, double rowH) {
    final step = (at.dx / _cell).floor();
    final rowFromTop =
        ((at.dy + (_vsGrid.hasClients ? _vsGrid.offset : 0)) / rowH).floor();
    if (step < 0 || step >= steps || rowFromTop < 0 || rowFromTop >= rows) {
      return null;
    }
    return (rowFromTop, step);
  }

  void _dragStart(Offset at, double rowH) {
    _holdFollow();
    final cell = _cellAt(at, rowH);
    if (cell == null) return;
    final (rowFromTop, step) = cell;
    final degree = rows - 1 - rowFromTop;
    final lane = isDrum ? kDrumLanes[rowFromTop] : null;

    // 드럼은 한 칸짜리 타격이라 덮는 범위가 없다. 음 줄만 **덮고 있는 음**을 본다.
    final found = isDrum ? null : _noteCovering(degree, step);
    final has = isDrum ? _drum.indexOf(lane!, step) >= 0 : found != null;

    _snapshot(); // 끄는 동안은 한 번만 쌓는다 — 한 번에 되돌아가야 한다
    if (_erase) {
      // 지우개는 **있든 없든 훑는다** — 길이·세기 고치기로 새지 않는다
      _drag = _Drag(
        paint: true,
        at: at,
        lane: lane,
        degree: degree,
        step: step,
        len0: 1,
      );
      _eraseAt(lane, degree, step);
      return;
    }
    if (has) {
      // **손끝에 잡히는 느낌** — 꾹 눌러 잡은 순간을 손으로도 알려 준다.
      // 이 뒤로 끌면(옆=길이·위아래=높낮이) 무엇을 잡았는지 눈으로 안 봐도 안다.
      HapticFeedback.selectionClick();
      // **잡는 값은 그 음의 시작 칸**이다 — 가운데를 잡았어도 길이 고치기·줄
      // 옮기기는 시작 칸으로 음을 찾는다. 누른 칸을 그대로 쓰면 엉뚱한 자리를
      // 고치거나 아무 일도 안 일어난다.
      final startStep = isDrum ? step : found![1] as int;
      _drag = _Drag(
        paint: false,
        at: at,
        lane: lane,
        degree: degree,
        step: startStep,
        len0: isDrum ? 1 : (found![2] as int),
      );
      setState(() => _sel = _Sel(lane: lane, degree: degree, step: startStep));
    } else {
      // 빈 칸 — 여기서부터 **깔기** 시작
      _drag = _Drag(
        paint: true,
        at: at,
        lane: lane,
        degree: degree,
        step: step,
        len0: 1,
      );
      _paintAt(lane, degree, step);
    }
  }

  void _dragMove(Offset at, double rowH) {
    final d = _drag;
    if (d == null) return;

    if (d.paint) {
      // 같은 줄에서 지나간 칸마다 하나씩 — 줄을 벗어나면 그 줄에 찍는다
      final cell = _cellAt(at, rowH);
      if (cell == null) return;
      final (rowFromTop, step) = cell;
      final degree = rows - 1 - rowFromTop;
      final lane = isDrum ? kDrumLanes[rowFromTop] : null;
      if (_erase) {
        _eraseAt(lane, degree, step);
      } else {
        _paintAt(lane, degree, step);
      }
      return;
    }

    // 있는 음 고치기 — **가로는 길이, 세로는 높낮이**
    final dx = at.dx - d.at.dx;
    final dy = at.dy - d.at.dy;

    // 처음 움직인 쪽으로 잠근다(둘 다 조금이면 아직 아무 쪽도 아니다)
    if (d.axis == 0) {
      if (dx.abs() < _kAxisLock && dy.abs() < _kAxisLock) return;
      d.axis = dx.abs() >= dy.abs() ? 1 : 2;
      // 어느 쪽으로 잠겼는지(길이냐 높낮이냐) 손끝으로 확인시켜 준다.
      HapticFeedback.lightImpact();
    }
    if (d.axis == 2) {
      // 화면 y 는 아래가 + — 위로 끌면 위 줄로 간다
      _moveRow(d, (-dy / rowH).round());
      return;
    }

    // 드럼에는 길이가 없다 — 가로로 끌 것이 없으니 여기서 끝난다
    if (isDrum) return;
    final now = _noteAt(d.curDegree ?? d.degree, d.step);
    if (now == null) return;
    final len = (d.len0 + (dx / _cell).round()).clamp(1, kMaxNoteLen);
    if (len != (now[2] as int)) {
      _writeNotes(
        NoteOps.setLen(
          _notes,
          d.curDegree ?? d.degree,
          d.step,
          len,
          steps: steps,
        ),
      );
    }
  }

  /// 잡은 음을 **줄 사이로 옮긴다.** [by] 는 시작한 자리에서 몇 줄 **위**인가.
  ///
  /// 옮기는 것이지 새로 찍는 것이 아니라 길이·세기·글라이드가 따라온다 —
  /// 「지우고 옆 줄에 다시 찍기」로는 그게 전부 초기값으로 돌아간다.
  /// 가려는 자리에 이미 음이 있으면 **가만있는다**(덮어쓰면 남의 음이 사라진다).
  void _moveRow(_Drag d, int by) {
    if (isDrum) {
      final from = kDrumLanes.indexOf(d.lane ?? '');
      if (from < 0) return;
      // 드럼은 위가 0번(킥)이다 — 위로 끌면 번호가 줄어든다
      final toLane = kDrumLanes[(from - by).clamp(0, kDrumLanes.length - 1)];
      final now = d.curLane ?? d.lane!;
      if (toLane == now) return;
      final ops = _drum;
      if (ops.indexOf(now, d.step) < 0) return;
      if (ops.indexOf(toLane, d.step) >= 0) return;
      final vel = ops.velAt(now, d.step);
      ops.remove(now, d.step);
      ops.add(toLane, d.step);
      ops.setVel(toLane, d.step, vel);
      d.curLane = toLane;
      _sel = _Sel(lane: toLane, degree: 0, step: d.step);
      HapticFeedback.selectionClick(); // 한 줄 옮길 때마다 딸깍 — 몇 칸 갔는지 손으로 센다
      _writeDrum(ops);
      _preview(kDrumLanes.indexOf(toLane));
      return;
    }
    final to = (d.degree + by).clamp(0, rows - 1);
    final now = d.curDegree ?? d.degree;
    if (to == now) return;
    final at = _notes.indexWhere((n) => n[0] == now && n[1] == d.step);
    if (at < 0) return;
    if (_notes.any((n) => n[0] == to && n[1] == d.step)) return;
    final list = [for (final n in _notes) List<Object?>.from(n)];
    list[at][0] = to;
    d.curDegree = to;
    _sel = _Sel(degree: to, step: d.step);
    HapticFeedback.selectionClick(); // 한 줄 옮길 때마다 딸깍 — 몇 칸 갔는지 손으로 센다
    _writeNotes(list);
    _preview(rows - 1 - to); // 옮긴 자리를 **들려준다** — 눈으로만 보면 어디로 갔는지 모른다
  }

  /// 깔기 — 이미 있으면 그냥 둔다(끌면서 지웠다 그렸다 하면 안 된다).
  /// 지우개로 지나간 칸 — **있으면 지운다.** 없으면 아무 일도 안 한다.
  void _eraseAt(String? lane, int degree, int step) {
    if (isDrum) {
      final d = _drum;
      if (d.indexOf(lane!, step) < 0) return;
      d.remove(lane, step);
      _sel = null;
      _writeDrum(d);
      return;
    }
    // 긴 음은 **어느 칸을 훑어도** 지워져야 한다 — 시작 칸만 보면 지우개로
    // 가운데를 문질러도 안 지워지고 "고장난 지우개"가 된다.
    final hit = _noteCovering(degree, step);
    if (hit == null) return;
    _sel = null;
    _writeNotes(NoteOps.remove(_notes, degree, hit[1] as int));
  }

  void _paintAt(String? lane, int degree, int step) {
    if (isDrum) {
      final d = _drum;
      if (d.indexOf(lane!, step) >= 0) return;
      d.add(lane, step);
      _sel = _Sel(lane: lane, degree: 0, step: step);
      _writeDrum(d);
      return;
    }
    // **여기는 일부러 시작 칸만 본다.** 「끌면 쫘르륵 깔린다」가 지나간 칸마다
    // 하나씩 찍는 동작이라(`editor_ui_test.dart` 10번), 덮인 칸을 건너뛰게 하면
    // 기본 길이가 2칸이므로 한 칸 걸러 하나만 찍힌다 — 끌어 깐 줄이 성겨진다.
    // 잡기·지우기와 달리 여기만 규칙이 다른 이유다.
    if (_noteAt(degree, step) != null) return;
    _sel = _Sel(degree: degree, step: step);
    _writeNotes(
      NoteOps.add(_notes, degree, step, isChord: isChord, steps: steps),
    );
  }

  /// 고친 걸 소리에 반영한다 — 재생 중이면 다음 판부터.
  void _push() {
    final host = widget.host;
    if (host == null) {
      setState(() {});
      return;
    }
    SceneBuild b;
    if (!widget.transport.playing) {
      b = SceneSequencer.build(widget.project, widget.transport, reps: 1);
    } else if (widget.transport.songLoop) {
      // 곡 재생 중이면 refreshLoop 로는 몇 분 뒤에나 반영된다 — 방금 고친
      // 걸 바로 들으려고 씬 루프로 갈아탄다(라이브 녹음 때와 같은 이유).
      b = SceneSequencer.playLoop(widget.project, widget.transport, host);
      widget.transport.songLoop = false;
      host.setSongMode(false);
    } else {
      b = SceneSequencer.refreshLoop(widget.project, widget.transport, host);
    }
    setState(() {
      _loopSec = b.loopSec;
      _loopBars = b.loopBars;
    });
  }

  void _play() {
    final host = widget.host;
    if (host == null) return;
    final b = SceneSequencer.playLoop(widget.project, widget.transport, host);
    widget.transport.playing = true;
    widget.transport.songLoop = false; // 씬 한 판 루프다 — 곡 재생이 아니다
    setState(() {
      _loopSec = b.loopSec;
      _loopBars = b.loopBars;
    });
  }

  void _stop() {
    widget.host?.allOff();
    widget.host?.setSongMode(false);
    widget.transport.playing = false;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final drum = isDrum ? _drum : null;
    final notes = isDrum ? null : _notes;
    final sel = _sel;

    return Column(
      children: [
        _Bar(
          // 가로로 누우면 높이가 귀하다 — 두 줄을 한 줄로 붙인다.
          // 안 그러면 드럼 레인 10개 중 2.5개만 보인다(그림으로 뽑아 보고 잡았다).
          wide: MediaQuery.of(context).size.height < 520,
          name: patternLabel(_name),
          bars: bars,
          playing: widget.transport.playing,
          onPlay: _play,
          onStop: _stop,
          onBars: _setBars,
          onClear: _clear,
          onUndo: _undo.isEmpty ? null : _undoOnce,
          onRedo: _redo.isEmpty ? null : _redoOnce,
          onStretch: isDrum ? null : _stretchAll,
          erasing: _erase,
          onErase: () => setState(() => _erase = !_erase),
          // 코드 판에서만 보인다 — 「기능이 있다는 이유만으로 다 노출하지 않는다」
          showFit: isChord,
          onFit: isChord && _sceneMelody() != null ? _fitToMelody : null,
          onTapRec: _tapRecord,
          tight: _cell < _kCell,
          onZoom: _zoom,
        ),
        // 마디 점프 — 4마디를 끝까지 밀지 않아도 된다.
        // 촘촘 보기와 짝이다: 촘촘히 줄이면 두 마디가 한눈에, 점프로 나머지를 본다.
        // 칸 크기는 손끝 기준이다. 30×28 은 실기기에서 4.5mm 남짓 — 누르면 옆 마디로
        // 간다. 42×38(약 6.5×5.8mm)로 키웠다.
        if (bars > 1)
          SizedBox(
            height: 46,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              children: [
                const Padding(
                  padding: EdgeInsets.only(right: 8, top: 10),
                  child: Text(
                    '마디',
                    style: TextStyle(fontSize: 12, color: Colors.white54),
                  ),
                ),
                for (var b = 0; b < bars; b++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () {
                        _holdFollow(); // 손으로 옮겼으니 잠시 안 따라간다
                        _hs.animateTo(
                          (b * spb * _cell).clamp(
                            0.0,
                            _hs.position.maxScrollExtent,
                          ),
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOut,
                        );
                      },
                      child: Container(
                        width: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${b + 1}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                // 위층을 맡는 코드 줄이면 그 사실을 적는다 — 같은 격자인데 소리가
                // 한 옥타브 위에서 나면 왜 다른지 알 길이 없다. **보여만 준다**
                // (고치는 손잡이는 안 만든다 — 「기능이 있다고 다 노출하지 않는다」).
                //
                // 처음엔 패턴 이름 옆에 붙였는데 **가로·세로 둘 다 잘렸다**(그림으로
                // 확인). 그 줄은 이미 꽉 차 있다. 여기는 마디 버튼 뒤가 비어 있다.
                if (isChord && NoteOps.chordOct(_notes) > 0)
                  const Padding(
                    padding: EdgeInsets.only(left: 6, top: 10),
                    child: Text(
                      '한 옥타브 위에서 소리 남',
                      style: TextStyle(fontSize: 12, color: Color(0xFF7FD8C0)),
                    ),
                  ),
              ],
            ),
          ),
        // 빈 판이면 무엇을 해야 하는지 한 줄 — '없음' 트랙에서 바로 들어올 수 있게
        // 되면서 **아무것도 안 찍힌 격자**를 처음 보는 일이 흔해졌다.
        if (_isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
            child: Row(
              children: [
                Icon(
                  Icons.touch_app,
                  size: 15,
                  color: Colors.tealAccent.shade200,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isDrum
                        ? '빈 판입니다 — 칸을 누르면 그 자리에서 칩니다.'
                        : '빈 판입니다 — 칸을 누르면 음이 찍힙니다. 위로 갈수록 높은 음.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Colors.tealAccent.shade100,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // 왼쪽 이름 칸(킥·스네어 / 1도·5도)은 **가로로 밀어도 남아 있어야 한다.**
        // 예전엔 이름 칸까지 같이 밀려서, 2마디로 점프하면 어느 줄이 킥인지
        // 알 수 없었다(폰에서 확인). 그래서 이름 칸을 가로 스크롤 **밖으로** 뺐다.
        // 세로 스크롤은 둘이 짝을 맞춰 움직인다(`_linkRows`).
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              // 자 + 재생선을 뺀 나머지를 줄 수로 나눈다
              final rowH = rowHeightFor(
                box.maxHeight - _kRulerH - _kHeadH,
                rows,
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _kHead,
                    child: Column(
                      children: [
                        // 자 + 재생선만큼 내리는 **빈 자리**였다.
                        // **줄 바꾸기**를 여기 넣는다: 판 하나가 화음과 낱음을 둘 다
                        // 드는데(`NotePatternDef.also`), 위쪽 바에 손잡이를 하나
                        // 더 얹으면 세로 폰에서 줄이 하나 늘어 **격자가 그만큼
                        // 줄어든다**(가로에서는 41px 넘쳤다). 여기는 원래 비어
                        // 있고, 「지금 어느 줄을 보고 있나」가 붙을 자리이기도 하다.
                        SizedBox(
                          height: _kRulerH + _kHeadH,
                          child: isDrum
                              ? null
                              : GestureDetector(
                                  onTap: () => setState(() {
                                    _alt = !_alt;
                                    _sel = null; // 줄이 바뀌면 고른 자리는 뜻이 없다
                                  }),
                                  // **꾹 = 반음 줄**(프로 모드에서만).
                                  // 설정에서 켠 사람에게만 열린다 — 도수 줄의
                                  // 제약이 「아무거나 눌러도 어울린다」를 만든다.
                                  //
                                  // 꺼져 있어도 **손잡이는 단다.** null 로 두면
                                  // 꾹 누른 것이 탭으로 흘러가 줄이 바뀐다
                                  // (꾹 눌렀는데 딴 일이 일어난다 — 시험이 잡았다).
                                  // 대신 어디서 켜는지 알려 준다.
                                  onLongPress: isChord || _alt
                                      ? null
                                      : (widget.pro
                                            ? _toggleChromatic
                                            : _proHint),
                                  child: Container(
                                    margin: const EdgeInsets.fromLTRB(
                                      3,
                                      3,
                                      3,
                                      3,
                                    ),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: _alt
                                          ? Colors.amber.shade600
                                          : Colors.white.withValues(
                                              alpha: 0.10,
                                            ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: FittedBox(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.layers,
                                            size: 12,
                                            color: _alt
                                                ? Colors.black87
                                                : Colors.white54,
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            _alt
                                                ? (t.type == 'chord'
                                                      ? '낱음'
                                                      : '화음')
                                                : (t.type == 'chord'
                                                      ? '화음'
                                                      : '가락'),
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800,
                                              color: _alt
                                                  ? Colors.black87
                                                  : Colors.white70,
                                            ),
                                          ),
                                          // 반대쪽에 음이 있으면 개수를 적는다 —
                                          // 모르면 「소리가 하나 더 나는데
                                          // 어디서 나지」가 된다.
                                          if (_otherCount > 0) ...[
                                            const SizedBox(width: 3),
                                            Text(
                                              '·$_otherCount',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: _alt
                                                    ? Colors.black54
                                                    : Colors.white38,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                        Expanded(
                          child: ListView.builder(
                            controller: _vsLabel,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: rows,
                            itemExtent: rowH,
                            itemBuilder: (context, i) {
                              final degree = rows - 1 - i;
                              final lane = isDrum ? kDrumLanes[i] : null;
                              final key = MusicKey(
                                root: widget.transport.root,
                                mode: widget.transport.mode,
                              );
                              return _RowLabel(
                                height: rowH,
                                // **코드 줄은 코드 이름으로 적는다.** 「4도」는
                                // 악보를 아는 사람의 말이다 — 무엇을 찍고 있는지
                                // 알 수 없으면 귀로 하나씩 눌러 볼 수밖에 없다.
                                text: isDrum
                                    ? (_laneLabel[lane] ?? lane!)
                                    : (isChord
                                          ? chordNameOf(degree % 7, key)
                                          : (_chro
                                                ? semiNameFor(
                                                    degree,
                                                    t.type,
                                                    key,
                                                  )
                                                : _degLabel(degree))),
                                // 코드 줄 아래에는 **느낌**을 적는다(활짝·쓸쓸함…).
                                // 악보를 몰라도 고를 수 있어야 한다.
                                sub: isDrum
                                    ? null
                                    : (isChord
                                          ? '${degree % 7 + 1}도 · '
                                                '${degMood(degree % 7, key.mode)}'
                                          : (_chro
                                                ? null
                                                : noteNameFor(
                                                    degree,
                                                    t.type,
                                                    key,
                                                  ))),
                                // 밝은 줄 = 눈을 붙일 자리. 도수 줄은 옥타브마다,
                                // 반음 줄은 **12반음마다**(으뜸음) 밝다.
                                bright: isDrum
                                    ? i < 3
                                    : (_chro
                                          ? degree % 12 == 0
                                          : degree % 7 == 0),
                                onTap: () => _preview(i),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 격자와 재생 위치는 **같은 스크롤 안에** 있어야 한다 —
                  // 따로 두면 옆으로 밀었을 때 세로줄이 엉뚱한 칸을 가리킨다.
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      // 손으로 민 것만 잡는다 — 우리가 `animateTo` 로 옮긴 것은
                      // `dragDetails` 가 없어서 구분된다(안 그러면 스스로를 막는다).
                      onNotification: (n) {
                        if ((n is ScrollStartNotification &&
                                n.dragDetails != null) ||
                            (n is ScrollUpdateNotification &&
                                n.dragDetails != null)) {
                          _holdFollow();
                        }
                        return false;
                      },
                      child: SingleChildScrollView(
                        controller: _hs,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: steps * _cell,
                          child: Column(
                            children: [
                              // 마디 자 — **지금 몇 마디를 보고 있는지**가 안 보이면 길을 잃는다
                              SizedBox(
                                height: _kRulerH,
                                child: Row(
                                  children: [
                                    for (var b = 0; b < bars; b++)
                                      SizedBox(
                                        width: spb * _cell,
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 2,
                                              height: 13,
                                              color: Colors.white30,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '${b + 1}',
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                color: Colors.white54,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                height: _kHeadH,
                                child: LoopPosBuilder(
                                  host: widget.host,
                                  loopSec: _loopSec,
                                  builder: (context, pos, looping) {
                                    if (looping) {
                                      // build 안에서 스크롤을 못 건드린다 — 프레임 뒤로 미룬다
                                      WidgetsBinding.instance
                                          .addPostFrameCallback(
                                            (_) => _followPlayhead(pos),
                                          );
                                    }
                                    return !looping
                                        ? const SizedBox()
                                        : Stack(
                                            children: [
                                              Positioned(
                                                left:
                                                    headStep(
                                                      pos,
                                                      steps: steps,
                                                      loopBars: _loopBars,
                                                      spb: spb,
                                                    ) *
                                                    _cell,
                                                child: Container(
                                                  width: 2.5,
                                                  height: _kHeadH,
                                                  color: Colors
                                                      .tealAccent
                                                      .shade200,
                                                ),
                                              ),
                                            ],
                                          );
                                  },
                                ),
                              ),
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  // **길게 누른 뒤** 끈다 — 그냥 끌면 격자가 가로로 스크롤된다
                                  onLongPressStart: (e) =>
                                      _dragStart(e.localPosition, rowH),
                                  onLongPressMoveUpdate: (e) =>
                                      _dragMove(e.localPosition, rowH),
                                  onLongPressEnd: (_) =>
                                      setState(() => _drag = null),
                                  onLongPressCancel: () =>
                                      setState(() => _drag = null),
                                  child: ListView.builder(
                                    controller: _vsGrid,
                                    itemCount: rows,
                                    itemExtent: rowH,
                                    itemBuilder: (context, i) {
                                      // 도수는 아래가 낮은 음 — 위에서부터 그리므로 뒤집는다
                                      final degree = rows - 1 - i;
                                      final lane = isDrum
                                          ? kDrumLanes[i]
                                          : null;
                                      return _GridRow(
                                        height: rowH,
                                        cell: _cell,
                                        steps: steps,
                                        meter: meter,
                                        musicKey: MusicKey(
                                          root: widget.transport.root,
                                          mode: widget.transport.mode,
                                        ),
                                        drumSteps: isDrum
                                            ? drum!.steps[lane]!
                                            : null,
                                        drumVels: isDrum
                                            ? drum!.vels[lane]!
                                            : null,
                                        notes: isDrum
                                            ? null
                                            : [
                                                for (final n in notes!)
                                                  if (n[0] == degree) n,
                                              ],
                                        isChord: isChord,
                                        selStep: isDrum
                                            ? (sel?.lane == lane
                                                  ? sel?.step
                                                  : null)
                                            : (sel != null &&
                                                      sel.lane == null &&
                                                      sel.degree == degree
                                                  ? sel.step
                                                  : null),
                                        onTap: (s) => isDrum
                                            ? _tapDrum(lane!, s)
                                            : _tapNote(degree, s),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        _SelBar(
          sel: sel,
          isDrum: isDrum,
          isChord: isChord,
          meter: meter,
          laneLabel: sel?.lane == null
              ? ''
              : (_laneLabel[sel!.lane] ?? sel.lane!),
          note: sel == null || isDrum ? null : _noteAt(sel.degree, sel.step),
          drumVel: sel?.lane == null || drum == null
              ? 2
              : (drum.velAt(sel!.lane!, sel.step) == 0
                    ? 2
                    : drum.velAt(sel.lane!, sel.step)),
          onLen: _setLen,
          onVel: (v) =>
              isDrum ? _setDrumVel(sel!.lane!, sel.step, v) : _setVel(v),
          onGlide: _toggleGlide,
          onChordType: _setChordType,
          musicKey: MusicKey(
            root: widget.transport.root,
            mode: widget.transport.mode,
          ),
          onMove: (by) =>
              isDrum ? _moveDrum(sel!.lane!, sel.step, by) : _moveNote(by),
          onDelete: () =>
              isDrum ? _deleteDrum(sel!.lane!, sel.step) : _deleteNote(),
        ),
      ],
    );
  }
}

/// 꾹 눌러 끄는 동안의 상태.
class _Drag {
  /// true 면 **깔기**(빈 칸에서 시작), false 면 있는 음 **고치기**.
  final bool paint;
  final Offset at; // 누르기 시작한 자리
  final String? lane; // 드럼이면 레인 — **시작할 때**의 것
  final int degree, step; // 도수도 **시작할 때**의 것
  final int len0; // 시작할 때의 길이

  /// **어느 쪽으로 끌고 있나** — 0 아직 모름, 1 가로(길이), 2 세로(높낮이).
  ///
  /// 처음 움직인 쪽으로 잠근다. 안 잠그면 길이를 늘리다가 손이 조금 기울 때
  /// 음이 딴 줄로 튄다 — **고치려던 것과 다른 것이 바뀌는** 제일 나쁜 종류다.
  int axis = 0;

  /// 세로로 옮긴 결과 **지금 어디에 있나.** 다음 계산의 기준은 늘 시작 자리라,
  /// 이건 「거기 이미 뭐가 있나」를 볼 때와 옮길 음을 찾을 때만 쓴다.
  int? curDegree;
  String? curLane;

  _Drag({
    required this.paint,
    required this.at,
    required this.lane,
    required this.degree,
    required this.step,
    required this.len0,
  });
}

/// 왼쪽에 **고정으로 남는** 줄 이름(킥·스네어 / 1도·5도).
class _RowLabel extends StatelessWidget {
  final String text;

  /// 도수 아래 작게 붙는 **실제 음이름**(C4·Eb5…). 없으면 안 그린다.
  ///
  /// 도수만 보면 무엇을 찍고 있는지 알 수 없다. 라이브 화면은 이미 음이름을
  /// 보여 준다 — 같은 앱에서 한쪽만 알려 주면 사람은 **그쪽에서만 배운다.**
  final String? sub;
  final bool bright;
  final double height;

  /// 누르면 그 줄 소리를 들려준다 — 찍기 전에 귀로 찾는 길.
  final VoidCallback? onTap;
  const _RowLabel({
    required this.text,
    required this.bright,
    required this.height,
    this.sub,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.only(right: 6),
          // **한 줄로 붙인다.** 위아래로 쌓으면 글자를 키운 폰(1.3배)에서 줄
          // 높이(32)를 넘긴다 — 줄 높이는 격자가 정하는 값이라 못 늘린다.
          // `FittedBox` 로 자리가 모자라면 통째로 줄어들게 한다(잘리지 않는다).
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: text,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: bright ? FontWeight.w700 : FontWeight.w400,
                        color: bright ? Colors.white70 : Colors.white38,
                      ),
                    ),
                    if (sub != null)
                      TextSpan(
                        text: ' $sub',
                        style: const TextStyle(
                          fontSize: 8.5,
                          color: Colors.white24,
                        ),
                      ),
                  ],
                ),
                maxLines: 1,
                textAlign: TextAlign.right,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 격자 한 줄. 드럼은 칸 자체를 칠하고, 나머지는 **길이만큼 뻗은 막대**를 얹는다.
/// 줄 이름은 여기 없다 — 가로로 밀어도 남아야 해서 [_RowLabel] 로 뺐다.
class _GridRow extends StatelessWidget {
  final double height;
  final double cell;
  final int steps;
  final MeterDef meter;
  final List<int>? drumSteps, drumVels;
  final List<List<Object?>>? notes;
  final bool isChord;

  /// 막대에 **코드 이름**을 적으려면 조를 알아야 한다. 화음 줄에서만 온다.
  final MusicKey? musicKey;
  final int? selStep;
  final ValueChanged<int> onTap;

  const _GridRow({
    required this.musicKey,
    required this.height,
    required this.cell,
    required this.steps,
    required this.meter,
    required this.drumSteps,
    required this.drumVels,
    required this.notes,
    required this.isChord,
    required this.selStep,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Row(
            // 칸이 **줄 높이를 꽉 채우게** — 줄 높이가 화면에 따라 달라진다
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var s = 0; s < steps; s++)
                _Cell(
                  cell: cell,
                  step: s,
                  meter: meter,
                  vel: drumSteps == null
                      ? 0
                      : () {
                          final at = drumSteps!.indexOf(s);
                          return at < 0 ? 0 : drumVels![at];
                        }(),
                  selected: selStep == s,
                  onTap: () => onTap(s),
                ),
            ],
          ),
          // 음 막대 — 칸 위에 얹으므로 **막대를 누르면 그 음이 잡힌다**
          if (notes != null)
            for (final n in notes!)
              Positioned(
                left: (n[1] as int) * cell + 1,
                // **위아래를 안 띄운다.** 막대는 누르는 것이라 줄 높이를 다 써야
                // 손가락 바닥선(32)을 지킨다. 보이는 모양은 그대로다 —
                // 1px 여백은 [_NoteBar] 안쪽 margin 으로 옮겼다(누르는 자리는 남는다).
                top: 0,
                bottom: 0,
                width:
                    ((n[2] as int).clamp(1, steps - (n[1] as int)) * cell - 2)
                        .toDouble(),
                child: _NoteBar(
                  vel: n[3] as int,
                  glide: !isChord && n.length > 4 && n[4] == 1,
                  // **저장 글자가 아니라 코드 이름**을 적는다. `min7` 은 이 앱의
                  // 속사정이고, 막대에 필요한 것은 「Fm7」 이다.
                  // (텐션·밑음이 붙어 있으면 그것도 같이 — `Fm7(9)/Ab`)
                  chordType: isChord && n.length > 4 && n[4] is String
                      ? chordBarLabel(n[0] as int, n[4] as String, musicKey)
                      : null,
                  selected: selStep == n[1],
                  onTap: () => onTap(n[1] as int),
                ),
              ),
        ],
      ),
    );
  }
}

/// 음 막대 — 밝기가 세기다(여리게/보통/세게).
class _NoteBar extends StatelessWidget {
  final int vel;
  final bool glide, selected;
  final String? chordType;
  final VoidCallback onTap;
  const _NoteBar({
    required this.vel,
    required this.glide,
    required this.chordType,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final a = vel <= 1 ? 0.42 : (vel == 2 ? 0.72 : 1.0);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        decoration: BoxDecoration(
          color: Colors.tealAccent.shade400.withValues(alpha: a),
          borderRadius: BorderRadius.circular(4),
          border: selected
              ? Border.all(color: Colors.amberAccent, width: 2)
              : null,
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Stack(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (glide)
                  const Icon(
                    Icons.show_chart,
                    size: 12,
                    color: Colors.black87,
                  ),
                if (chordType != null)
                  Text(
                    chordType!,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: const TextStyle(
                      fontSize: 8.5,
                      color: Colors.black87,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            // **잡을 자리를 눈으로도 보여 준다.** 여태는 "꾹 눌러 옆=길이"를
            // 글자 힌트로만 알렸다 — 안 읽으면 아무도 모른다. 고른 음의
            // 오른쪽 끝에 손잡이 두 줄을 그려서, 어디를 밀면 길이가
            // 늘어나는지 한눈에 보이게 한다(타임라인 구간의 손잡이와 같은
            // 생김새 — `song_view.dart` 의 `_ResizeGrip`).
            if (selected)
              Positioned(
                right: 1,
                top: 0,
                bottom: 0,
                child: Center(
                  child: SizedBox(
                    width: 6,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          width: 1.4,
                          height: 12,
                          color: Colors.black45,
                        ),
                        Container(
                          width: 1.4,
                          height: 12,
                          color: Colors.black45,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final double cell;
  final int step;
  final MeterDef meter;
  final int vel; // 0 이면 빈 칸(드럼이 아니면 언제나 0)
  final bool selected;
  final VoidCallback onTap;
  const _Cell({
    required this.cell,
    required this.step,
    required this.meter,
    required this.vel,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 박마다 조금 밝게, 마디마다 더 밝게 — 안 그러면 어디가 어딘지 모른다
    // (박 길이는 박자마다 다르다 — 6/8 은 2칸, 그 밖은 4칸: meter.clickSteps)
    final beat = step % meter.clickSteps == 0;
    final bar = step % meter.stepsPerBar == 0;
    final on = vel > 0;
    final a = vel <= 1 ? 0.42 : (vel == 2 ? 0.72 : 1.0);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        // 여백까지 합쳐 딱 `_kCell` 이어야 한다 — 여기가 32px 이면 칸은 32px 씩
        // 가는데 재생줄·음막대는 30px 씩 가서 **뒤로 갈수록 어긋난다**(끝 칸은
        // 아예 화면 밖으로 밀려 눌리지도 않았다. 위젯 시험이 넘침으로 잡아냈다).
        width: cell - 2,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: on
              ? Colors.tealAccent.shade400.withValues(alpha: a)
              : Colors.white.withValues(
                  alpha: bar ? 0.12 : (beat ? 0.07 : 0.035),
                ),
          borderRadius: BorderRadius.circular(4),
          border: selected
              ? Border.all(color: Colors.amberAccent, width: 2)
              : (bar ? Border.all(color: Colors.white24, width: 0.8) : null),
        ),
      ),
    );
  }
}

/// 고른 음을 손보는 바 — 아무것도 안 골랐을 땐 안내만 보여준다(자리는 늘 잡아 둔다.
/// 나타났다 사라지면 격자가 위아래로 튄다).
class _SelBar extends StatelessWidget {
  final _Sel? sel;
  final bool isDrum, isChord;
  final MeterDef meter;
  final String laneLabel;
  final List<Object?>? note;
  final int drumVel;
  final ValueChanged<int> onLen, onVel, onMove;
  final VoidCallback onGlide, onDelete;

  /// 코드 종류 고르기 — 코드 판에서만 쓴다.
  final ValueChanged<String?> onChordType;

  /// 코드 **이름**을 지으려면 조를 알아야 한다(같은 4도라도 조마다 이름이 다르다).
  final MusicKey musicKey;

  const _SelBar({
    required this.sel,
    required this.isDrum,
    required this.isChord,
    required this.meter,
    required this.laneLabel,
    required this.note,
    required this.drumVel,
    required this.onLen,
    required this.onVel,
    required this.onMove,
    required this.onGlide,
    required this.onChordType,
    required this.musicKey,
    required this.onDelete,
  });

  /// 이 엔진이 아는 코드 **전부** + 텐션 + 슬래시 베이스.
  ///
  /// 옛 앱(뮤직 두들)의 프로 코드 빌더 자리다. 엔진은 처음부터 스물넷을 알고
  /// 텐션·슬래시까지 낼 수 있었는데, 고를 자리가 여섯뿐이라 직접 찍는 코드는
  /// 늘 밋밋했다.
  ///
  /// 셋을 **한 서랍에서** 고르고, 맨 위에 지금 무슨 코드가 되는지 적는다 —
  /// `Am7(9)/C` 를 보면 무엇을 만들고 있는지 그 자리에서 안다.
  void _moreChords(BuildContext context) {
    final d = (sel?.degree ?? 0) % 7;
    var type = note == null ? null : NoteOps.chordTypeOf(note!);
    var tens = note == null
        ? <String>[]
        : List<String>.from(NoteOps.chordTensionsOf(note!));
    var bass = note == null ? null : NoteOps.chordBassOf(note!);

    String rootOf(int deg) => chordNameOf(deg, musicKey, type: 'maj');
    String fullName() {
      final base = chordNameOf(d, musicKey, type: type);
      final t = tens.isEmpty
          ? ''
          : '(${[for (final x in tens) kTensionLabel[x] ?? x].join(',')})';
      return '$base$t${bass == null ? '' : '/${rootOf(bass!)}'}';
    }

    void apply() => onChordType(buildChordText(type, tens, bass));

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          Widget chip(String label, bool on, VoidCallback tap) =>
              GestureDetector(
                onTap: () {
                  tap();
                  apply();
                  setSheet(() {});
                },
                child: Container(
                  height: 44, // 손가락 바닥선
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on ? Colors.amber.shade600 : Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: on ? Colors.black : Colors.white70,
                    ),
                  ),
                ),
              );

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // **지금 무슨 코드가 되는가** — 고를 때마다 여기가 바뀐다.
                  Text(
                    fullName(),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    '${d + 1}도 · ${degMood(d, musicKey.mode)} — 뿌리음은 그대로 두고 '
                    '색깔만 바꿉니다.',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.white54,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.of(ctx).size.height * 0.55,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (title, types) in kChordGroups) ...[
                            _SheetHead(title),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final ty in types)
                                  chip(
                                    chordNameOf(d, musicKey, type: ty),
                                    type == ty,
                                    () => type = ty,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                          ],
                          // 텐션 — 색깔 음. 붙였다 뗐다 하는 것이라 **눌러서 켠다**.
                          _SheetHead('덧음 (텐션)'),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final t in kTensionLabel.entries)
                                chip(t.value, tens.contains(t.key), () {
                                  if (!tens.remove(t.key)) tens.add(t.key);
                                }),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // 슬래시 베이스 — 밑에 깔 음. 도수로 고른다(조를 따라간다).
                          _SheetHead('밑음 (슬래시 베이스)'),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              chip('없음', bass == null, () => bass = null),
                              for (var b = 0; b < 7; b++)
                                chip(rootOf(b), bass == b, () => bass = b),
                            ],
                          ),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = sel;
    // 아무것도 안 골랐을 때는 안내 **한 줄**뿐이다 — 86dp 를 차지할 이유가 없다.
    // 가로 화면에서 그 86dp 가 격자 두 줄이다(그림으로 뽑아 보고 잡았다).
    final empty = s == null || (!isDrum && note == null);
    return Container(
      height: empty ? 42 : 86,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      decoration: const BoxDecoration(
        color: Color(0xFF16181C),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: empty
          // 드럼에는 길이도 글라이드도 없다 — 없는 걸 안내하면 찾다가 지친다.
          ? Center(
              // 꾹 눌러 끄는 제스처는 **알려 주지 않으면 아무도 못 찾는다.**
              // 아무것도 안 골랐을 때 이 자리가 비어 있으니 여기에 적는다.
              child: Text(
                isDrum
                    ? '꾹 눌러 위아래 = 다른 악기로 · 빈 칸을 끌면 쫘르륵'
                    : '꾹 눌러 옆 = 길이 · 위아래 = 높낮이 · 빈 칸을 끌면 쫘르륵',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: Colors.white38),
              ),
            )
          : Column(
              children: [
                SizedBox(
                  height: 30,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.center_focus_strong,
                        size: 15,
                        color: Colors.amberAccent,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          isDrum
                              ? '$laneLabel · ${_posLabel(s.step, meter)}'
                              : '${isChord ? '${s.degree + 1}도 코드' : '${_degLabel(s.degree)}음'}'
                                    ' · ${_posLabel(s.step, meter)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      _Small(icon: Icons.chevron_left, onTap: () => onMove(-1)),
                      const SizedBox(width: 4),
                      _Small(icon: Icons.chevron_right, onTap: () => onMove(1)),
                      const SizedBox(width: 8),
                      _Small(
                        icon: Icons.delete_outline,
                        onTap: onDelete,
                        danger: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // 글자 대신 그림표를 쓴다 — 360dp 폰에서 '길이'·'세기' 두 글자씩만
                        // 더 붙어도 **글라이드가 화면 밖으로 밀린다**(제일 중요한 게 안 보인다)
                        if (!isDrum) ...[
                          const _Cap(Icons.straighten),
                          _Small(
                            icon: Icons.remove,
                            onTap: () => onLen((note![2] as int) - 1),
                          ),
                          SizedBox(
                            width: 34,
                            child: Text(
                              '${note![2]}칸',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          _Small(
                            icon: Icons.add,
                            onTap: () => onLen((note![2] as int) + 1),
                          ),
                          const SizedBox(width: 8),
                        ],
                        const _Cap(Icons.graphic_eq),
                        for (var v = 1; v <= 3; v++)
                          _Chip(
                            label: const ['여리게', '보통', '세게'][v - 1],
                            on: (isDrum ? drumVel : note![3] as int) == v,
                            onTap: () => onVel(v),
                          ),
                        if (!isDrum && !isChord) ...[
                          const SizedBox(width: 8),
                          _Chip(
                            label: '글라이드',
                            icon: Icons.show_chart,
                            on: note!.length > 4 && note![4] == 1,
                            onTap: onGlide,
                          ),
                        ],
                        // 코드 종류 — **엔진은 처음부터 알고 있었다.**
                        // 고를 자리가 없어서 직접 찍는 코드는 늘 3화음뿐이었다.
                        if (isChord) ...[
                          const SizedBox(width: 10),
                          // 자주 쓰는 여섯은 **바로 손에 닿는 자리**에 둔다.
                          // 이름은 `m7` 이 아니라 **그 조에서 무슨 코드가 되는지**로
                          // 적는다 — 「min7 로 바꾸시겠어요」는 아무 뜻이 없다.
                          for (final (key, _) in kChordChoices)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: _Chip(
                                label: key == null
                                    ? chordNameOf(s.degree % 7, musicKey)
                                    : chordNameOf(
                                        s.degree % 7,
                                        musicKey,
                                        type: key,
                                      ),
                                on: NoteOps.chordTypeOf(note!) == key,
                                // **덧음·밑음은 그대로 들고 간다.** 종류만 바꾸는
                                // 칩이 텐션까지 지우면, 서랍에서 공들여 붙인 것이
                                // 칩 한 번에 날아간다(짝이 하나 없는 그 모양).
                                onTap: () => onChordType(
                                  buildChordText(
                                    key,
                                    NoteOps.chordTensionsOf(note!),
                                    NoteOps.chordBassOf(note!),
                                  ),
                                ),
                              ),
                            ),
                          // 나머지 열여덟은 서랍에 둔다 — 스물넷을 한 줄에 늘어놓으면
                          // 옆으로 한참 밀어야 하고, 그래서 아무도 안 쓴다.
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _Chip(
                              label: '더…',
                              icon: Icons.expand_more,
                              on: false,
                              onTap: () => _moreChords(context),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Cap extends StatelessWidget {
  final IconData icon;
  const _Cap(this.icon);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 4),
    child: Icon(icon, size: 15, color: Colors.white54),
  );
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool on;
  final VoidCallback onTap;
  const _Chip({
    required this.label,
    this.icon,
    required this.on,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 32,
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? Colors.tealAccent.shade400 : Colors.white12,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: on ? Colors.black87 : Colors.white60),
              const SizedBox(width: 3),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: on ? Colors.black87 : Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final String name;
  final int bars;
  final bool playing, tight;
  final bool wide;
  final VoidCallback onPlay, onStop, onClear, onZoom;

  /// 되돌릴 게 없으면 null — 버튼이 흐려진다.
  final VoidCallback? onUndo;

  /// 다시하기 — 되돌리기의 짝. 없으면(=되돌린 적 없으면) null.
  final VoidCallback? onRedo;

  /// 판 전체 음 길이 ±1칸. 드럼 판에서는 null(길이라는 게 없다).
  final ValueChanged<int>? onStretch;

  /// 지우개가 켜져 있는가 · 켜고 끄기.
  final bool erasing;
  final VoidCallback onErase;

  /// **코드 판일 때만** 온다. 씬에 멜로디가 없으면 null(흐려진다).
  final VoidCallback? onFit;
  final bool showFit;

  /// 두드려 넣기 — 박자를 손으로 두드려 담는다.
  final VoidCallback onTapRec;

  final ValueChanged<int> onBars;
  const _Bar({
    required this.wide,
    required this.onUndo,
    required this.onRedo,
    required this.onStretch,
    required this.erasing,
    required this.onErase,
    required this.onFit,
    required this.showFit,
    required this.onTapRec,
    required this.name,
    required this.bars,
    required this.playing,
    required this.onPlay,
    required this.onStop,
    required this.onBars,
    required this.onClear,
    required this.tight,
    required this.onZoom,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      // 여섯 가지를 한 줄에 욱여넣으니 **이름도 설명도 다 잘렸다**(폰에서 확인:
      // 「신스 베이스 내 …」 · 「빈 칸=찍기 · 음=고…」). 두 줄로 나눴다 —
      // 위: 재생 · 이름 · 지우기, 아래: 마디 수 · 보기 방식.
      child: Builder(
        builder: (context) {
          final playBtn = SizedBox(
            width: 100,
            height: 42,
            child: FilledButton.icon(
              onPressed: playing ? onStop : onPlay,
              icon: Icon(playing ? Icons.stop : Icons.play_arrow, size: 19),
              label: Text(
                playing ? '정지' : '재생',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              style: FilledButton.styleFrom(
                padding: EdgeInsets.zero,
                backgroundColor: playing
                    ? Colors.red.shade700
                    : Colors.teal.shade600,
                foregroundColor: Colors.white,
              ),
            ),
          );
          final title = Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          );
          final clearBtn = _Small(
            icon: Icons.delete_sweep_outlined,
            onTap: onClear,
          );
          // 지우개 — **하나와 전부 사이**를 메운다. 16비트 하이햇 한 줄을
          // 지우려면 여태 32번 눌렀고, 싫으면 판 전체를 날리는 수밖에 없었다.
          final eraseBtn = _Small(
            icon: Icons.auto_fix_off,
            onTap: onErase,
            on: erasing,
          );
          // 되돌리기 — 이 화면에는 없었다. 「지우기」가 판 전체를 날리는데도.
          final undoBtn = _Small(icon: Icons.undo, onTap: onUndo);
          // **되돌리기만 있으면 마음 놓고 못 되돌린다.** 한 칸 지나치면 그 편집이
          // 영영 없어지니까. 짝이 있어야 되돌리기가 산다.
          final redoBtn = _Small(icon: Icons.redo, onTap: onRedo);
          // 「멜로디에 맞추기」 — 코드 판에서만 나온다 (계획 6-4).
          // 아이콘만 두면 무슨 버튼인지 못 맞힌다(돋보기에서 겪었다) → 글자를 붙인다.
          //
          // **가로 화면만 예외다.** 코드 판 + 글자 1.3배 + 가로에서는 이 한 줄이
          // 22px 넘쳤다(넘침 시험이 잡았다). 거기서는 이미 되돌리기·지우개·비우기가
          // 다 그림표라, 이것도 그림표로 두고 길게 눌러 이름을 본다.
          final fitBtn = !showFit
              ? const SizedBox.shrink()
              : wide
              ? Tooltip(
                  message: '멜로디에 맞추기',
                  child: _Small(icon: Icons.auto_awesome, onTap: onFit),
                )
              : GestureDetector(
                  onTap: onFit,
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: onFit == null
                          ? Colors.white10
                          : Colors.deepPurple.shade400.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.auto_awesome,
                          size: 15,
                          color: onFit == null ? Colors.white24 : Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          wide ? '맞추기' : '멜로디에 맞추기',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: onFit == null
                                ? Colors.white24
                                : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
          // 판 전체 음 길이 — **한 번에** 스타카토 ↔ 레가토.
          // 음을 하나씩 골라 늘리면 20음짜리는 20번이다.
          final stretchGroup = onStretch == null
              ? const SizedBox.shrink()
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 가로에서는 글자를 뺀다 — 한 줄에 다 놓으려면 자리가 없다
                    // (아이콘 둘이 붙어 있어 무엇인지는 눌러 보면 바로 안다).
                    if (!wide) ...[
                      const Text(
                        '음 길이',
                        style: TextStyle(fontSize: 12, color: Colors.white54),
                      ),
                      const SizedBox(width: 6),
                    ],
                    _Small(
                      icon: Icons.unfold_less,
                      onTap: () => onStretch!(-1),
                    ),
                    const SizedBox(width: 4),
                    _Small(icon: Icons.unfold_more, onTap: () => onStretch!(1)),
                  ],
                );
          // 두드려 넣기 — **이 화면에서 제일 새로운 길**이라 글자를 붙인다.
          // 아이콘만 두면 아무도 못 찾는다(돋보기·맞추기에서 이미 겪었다).
          // 가로 화면에서는 한 줄에 자리가 없어 그림표만 남긴다.
          final tapBtn = wide
              ? Tooltip(
                  message: '두드려 넣기',
                  child: _Small(icon: Icons.touch_app, onTap: onTapRec),
                )
              : GestureDetector(
                  onTap: onTapRec,
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.30),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: Colors.tealAccent.withValues(alpha: 0.45),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.touch_app, size: 16),
                        SizedBox(width: 6),
                        Text(
                          '두드려 넣기',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
          final barsGroup = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!wide) ...[
                const Text(
                  '마디',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
                const SizedBox(width: 8),
              ],
              _Small(
                icon: Icons.remove,
                onTap: bars > 1 ? () => onBars(bars - 1) : null,
              ),
              SizedBox(
                width: 52,
                child: Text(
                  '$bars마디',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _Small(
                icon: Icons.add,
                onTap: bars < 8 ? () => onBars(bars + 1) : null,
              ),
            ],
          );
          final zoomBtn = Row(
            children: [
              // 돋보기 아이콘만으로는 뭘 하는 건지 못 맞힌다 — 글자를 붙였다.
              GestureDetector(
                onTap: onZoom,
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: tight
                        ? Colors.teal.withValues(alpha: 0.30)
                        : Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        tight ? Icons.zoom_in_map : Icons.zoom_out_map,
                        size: 17,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        tight ? '넓게 보기' : '촘촘 보기',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );

          // 가로: 한 줄에 전부(800dp 에 460dp + 이름 — 넉넉하다)
          if (wide) {
            return Row(
              children: [
                playBtn,
                const SizedBox(width: 10),
                title,
                const SizedBox(width: 10),
                barsGroup,
                const SizedBox(width: 10),
                stretchGroup,
                const SizedBox(width: 10),
                if (showFit) ...[fitBtn, const SizedBox(width: 10)],
                tapBtn,
                const SizedBox(width: 6),
                zoomBtn,
                const SizedBox(width: 6),
                undoBtn,
                const SizedBox(width: 6),
                redoBtn,
                const SizedBox(width: 6),
                eraseBtn,
                const SizedBox(width: 6),
                clearBtn,
              ],
            );
          }
          return Column(
            children: [
              Row(
                children: [
                  playBtn,
                  const SizedBox(width: 10),
                  title,
                  const SizedBox(width: 6),
                  undoBtn,
                  const SizedBox(width: 6),
                  redoBtn,
                  const SizedBox(width: 6),
                  eraseBtn,
                  const SizedBox(width: 6),
                  clearBtn,
                ],
              ),
              const SizedBox(height: 8),
              Row(children: [barsGroup, const Spacer(), zoomBtn]),
              const SizedBox(height: 8),
              // 두드려 넣기와 음 길이를 한 줄에 — 둘 다 「판 전체를 손보는」 일이다.
              // 줄을 따로 두면 320dp 폰에서 격자가 그만큼 잘린다.
              Row(
                children: [
                  tapBtn,
                  const Spacer(),
                  if (onStretch != null) stretchGroup,
                ],
              ),
              if (showFit) ...[
                const SizedBox(height: 8),
                Row(children: [fitBtn]),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 서랍 안 묶음 제목 — 한 곳에서만 쓰지만 세 번 나온다.
class _SheetHead extends StatelessWidget {
  final String text;
  const _SheetHead(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        color: Colors.white38,
      ),
    ),
  );
}

class _Small extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool danger;

  /// 켜고 끄는 버튼인 경우 — 켜져 있으면 **한눈에 보여야 한다**.
  /// (지우개가 켜진 줄 모르고 찍으려다 지우면 그게 제일 나쁘다)
  final bool on;
  const _Small({
    required this.icon,
    this.onTap,
    this.danger = false,
    this.on = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      // 32px 는 실기기에서 5mm 남짓 — 마디를 줄이려다 늘리기 일쑤였다. 38px 로.
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null
              ? Colors.white10
              : on
              ? Colors.amber.shade600
              : (danger ? Colors.red.shade900 : Colors.white24),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 19,
          color: onTap == null
              ? Colors.white24
              : on
              ? Colors.black
              : (danger ? Colors.red.shade100 : Colors.white70),
        ),
      ),
    );
  }
}
