// 라이브 — **내 곡 위에 얹어 친다** (5단계 13/N).
//
// 씬 루프를 돌려 놓고 그 위에서 패드를 두드린다. 두 가지가 이 화면의 전부다:
//
// 1) **틀린 음이 안 나온다.** 패드는 반음 건반이 아니라 **지금 조의 음계**다
//    (`degreeFreq` — 곡을 만들 때 쓰는 바로 그 함수). 아무 데나 눌러도 곡에 맞는다.
//    피아노 건반을 주면 초보는 반드시 옆 반음을 짚고, 한 번 어긋난 소리를 들으면
//    그 뒤로 안 누른다. 그게 이 앱에서 제일 흔한 이탈 지점이다.
// 2) **곡과 따로 논다.** 치는 소리는 전부 라이브 버스(`kPartLive`)로 나간다 —
//    믹서의 라이브 페이더·잔향이 이 소리만 잡는다. 곡 트랙은 안 건드린다.
//
// 씬 칩을 누르면 **돌면서 씬이 바뀐다**(다음 판부터). 인트로 → 코러스로 넘기며 치는 게
// 라이브다. 재생을 멈췄다 켜지 않는다.
//
// ── 반응 속도 ──
// `setSongMode(false)` 로 앞질러 만드는 양을 사용자가 정한 값(기본 64ms)으로 되돌린다.
// 곡 재생은 128ms 로 넉넉히 잡지만(안 밀리는 게 중요), 손가락에 붙어야 하는 화면에서는
// 그만큼이 그대로 늦음으로 느껴진다. 루프는 엔진 시계 기준으로 `guard = ahead + 0.25초`
// 앞서 채우므로 64ms 로 줄여도 판이 비지 않는다.

import 'dart:async';

import 'package:flutter/material.dart';

import '../audio_isolate.dart';
import '../engine.dart' show noteNameIn;
import '../instruments.dart';
import '../live_ops.dart';
import '../genres.dart';
import '../project.dart';
import '../patterns.dart';
import '../sequencer.dart';
import '../theory.dart';
import 'play_head.dart';

/// 음 길이 — 라벨 · 초 · **녹음에 남길 칸 수**(16분음표 몇 칸).
/// 들은 길이와 남는 길이가 다르면 녹음하고 나서 "내가 친 게 아닌데" 가 된다.
///
/// **이제 이건 「바닥」이다.** 꾹 누르면 누르고 있는 동안 나고 그만큼 적힌다 —
/// 톡 쳤을 때 얼마나 울릴지, 그리고 적힐 최소 길이가 얼마인지를 이 값이 정한다.
const List<(String, double, int)> _kLens = [
  ('짧게', 0.35, 1),
  ('보통', 0.9, 2),
  ('길게', 2.2, 4),
];

class LiveView extends StatefulWidget {
  final Project project;
  final Transport transport;
  final LiveChannel live;
  final AudioClient? host;

  /// 초보 모드(`Store.beginner`) — 반음 건반에서 지금 조에 안 맞는 건반을
  /// 흐리게 하고 눌러도 소리가 안 나게 한다. 기본 켜짐.
  final bool beginner;
  const LiveView({
    super.key,
    required this.project,
    required this.transport,
    required this.live,
    required this.host,
    this.beginner = true,
  });

  @override
  State<LiveView> createState() => _LiveViewState();
}

class _LiveViewState extends State<LiveView> {
  LiveMode _mode = LiveMode.single;
  int _len = 1; // _kLens 인덱스

  // ── 메트로놈 ──
  //
  // 드럼이 없는 씬(패드·코드만)에서 녹음하면 **기댈 박이 아예 없다.** 반주는
  // 흐르는데 어디가 1박인지 안 들리니 박에 맞춰 칠 수가 없다.
  //
  // 화면 타이머로 「지금」 울리면 박이 ±16ms 로 흔들린다 — 그건 자가 아니라 소음이다.
  // **앞질러 예약하고** 시각은 엔진이 지킨다(`beatsToSend` 가 무엇을 언제 놓을지 정한다).
  bool _met = false;
  Timer? _metTimer;

  /// 이번 바퀴에 이미 예약한 박 — 같은 박을 두 번 놓으면 두 번 들린다.
  final Set<int> _metSent = {};
  double _metLastNow = 0;

  void _toggleMet() {
    setState(() => _met = !_met);
    if (!_met) {
      _metTimer?.cancel();
      _metTimer = null;
      _metSent.clear();
      return;
    }
    // 박을 세려면 반주가 돌아야 한다 — 안 돌면 「지금 몇 초인가」가 없다
    if (!widget.transport.playing) _togglePlay();
    _metSent.clear();
    _metLastNow = 0;
    _metTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      _metStep();
    });
  }

  void _metStep() {
    final h = host;
    if (!_met || h == null || !widget.transport.playing || _loopSec <= 0) {
      return;
    }
    final nowSec = _clock.pos(_loopSec) * _loopSec;
    // 판이 넘어갔다 — 기록을 비운다(박 번호가 0 부터 다시 센다)
    if (nowSec < _metLastNow) {
      _metSent.clear();
    }
    _metLastNow = nowSec;
    final beatSec = 60.0 / widget.transport.bpm;
    final ticks = beatsToSend(
      nowSec: nowSec,
      loopSec: _loopSec,
      beatSec: beatSec,
      sent: _metSent,
    );
    if (ticks.isEmpty) return;
    // 자는 **라이브 버스**로 낸다 — 드럼 버스에 실으면 믹서에서 드럼을 줄일 때
    // 박까지 같이 작아진다(`metroBatch` 주석 참고).
    h.batch(metroBatch(ticks));
    for (final t in ticks) {
      _metSent.add(t.beat);
    }
  }

  /// **최근에 쓴 악기 넷.** 연주 중에 악기를 바꾸려면 모달 서랍을 열었다 닫아야
  /// 했다 — 그 사이 연주가 끊긴다. 자주 오가는 둘·셋은 한 번 탭으로 닿아야 한다.
  ///
  /// 곡에 저장하지 않는다. 「방금 뭘 썼나」는 이 화면에 있는 동안의 일이다.
  final List<String> _favs = [];

  void _useVoice(String v) {
    widget.live.voice = v;
    _favs
      ..remove(v)
      ..insert(0, v);
    while (_favs.length > 4) {
      _favs.removeLast();
    }
    setState(() {});
  }

  int _oct = 0; // -1 ~ +2

  /// **반음 건반** — 다이아토닉 패드(도수 7개) 대신 실제 피아노처럼 12음
  /// 전부를 보여 준다. 기본은 꺼짐(다이아토닉) — 도수 패드가 주는 「틀린
  /// 음이 안 나온다」 약속은 그대로 두고, 원하는 사람만 반음으로 넘어간다.
  bool _chromatic = false;

  /// 반음 건반으로(또는 반대로) 넘긴다. **녹음 중에는 안 바꾼다** — 한 판
  /// 안에서 도수와 반음이 섞이면 패턴 하나에 두 가지 뜻이 같이 담긴다.
  void _toggleChromatic() {
    if (_rec != null) {
      _say('녹음을 마치고 바꿔 주세요');
      return;
    }
    setState(() => _chromatic = !_chromatic);
  }

  /// 이 화면이 열릴 때 **그 장르의 라이브 기본값**을 얹는다 (계획 7).
  ///
  /// 여태 어떤 장르든 피아노 · 한 음 · 보통 길이였다 — 트랩을 만들다 라이브를 열면
  /// 피아노가 나왔다. 음색은 사용자가 고른 적 있으면 안 건드리고(`suggestVoice`),
  /// 주법·길이는 이 화면 안에서만 사는 값이라 열 때마다 새로 잡는다.
  void _applyGenreDefaults() {
    final g = genreDef(widget.project.genre);
    widget.live.suggestVoice(g.liveVoice);
    _mode = switch (g.liveMode) {
      'chord' => LiveMode.chord,
      'arp' => LiveMode.arp,
      _ => LiveMode.single,
    };
    _len = g.liveLen.clamp(0, _kLens.length - 1);
  }

  final Set<int> _hot = {}; // 지금 눌린 패드(불 들어오는 표시)

  // ── 녹음 ──
  final _clock = LoopClock(); // 손가락이 닿는 그 순간 몇 박인지
  LiveRecorder? _rec;
  double _loopSec = 0;
  int _loopBars = 4;

  AudioClient? get host => widget.host;
  MusicKey get key =>
      MusicKey(root: widget.transport.root, mode: widget.transport.mode);

  @override
  void initState() {
    super.initState();
    _applyGenreDefaults();
    // 라이브 버스 값을 엔진에 맞춰 둔다 — 믹서에 보이는 값과 실제가 어긋나면 안 된다
    host?.setBus('live', vol: widget.live.vol, rev: widget.live.rev);
    _clock.attach(host);
    // 아직 안 틀었어도 판 길이는 알 수 있다(녹음 버튼을 먼저 누를 수 있어야 한다)
    final b = SceneSequencer.build(widget.project, widget.transport, reps: 1);
    _loopSec = b.loopSec;
    _loopBars = b.loopBars;
  }

  @override
  void dispose() {
    _metTimer?.cancel();
    // 잡고 있던 것을 놓고 나간다 — 안 놓으면 화면을 나가도 소리가 계속 난다.
    host?.holdOff(-1);
    _clock.dispose();
    // 나갈 때 다시 곡 모드로 — 다음 화면(곡·씬)은 안 밀리는 쪽이 중요하다
    host?.setSongMode(true);
    super.dispose();
  }

  // ── 소리 ──

  /// 무엇을 낼지는 `live_ops.dart` 가 정한다(시험이 그걸 직접 검사한다).
  /// 여기서는 보내고, 불 켜 주는 일만 한다.
  // ── 꾹 눌러 소리 유지 · 끌어서 음 잇기 ──
  //
  // 여태는 어떻게 만지든 「짧게/보통/길게」 중 미리 고른 길이로만 났다 —
  // **라이브인데 표현이 없었다.** 이제 누르고 있는 동안 나고, 손가락을 옆 패드로
  // 끌면 그 음으로 이어진다.
  //
  // 「짧게/보통/길게」는 이제 **적히는 길이**와 톡 쳤을 때의 길이를 정한다.

  /// 지금 손가락이 누르고 있는 것 — 포인터 번호 → 도수.
  final Map<int, int> _down = {};

  /// 누른 순간(초, 클록 기준). 뗄 때 **실제로 잡고 있던 길이**를 적는 데 쓴다.
  final Map<int, double> _downAt = {};

  /// 이 손가락이 **지금 물고 있는 소리의 개수** — 화음이면 3, 단음이면 1.
  /// `holdOff` 로 놓을 때 `_voiceId(pointer, 0..개수-1)` 전부를 놓아야 한다
  /// (엔진은 부른 자리(id)로만 물고 있어서, 하나라도 안 놓으면 그 소리는
  /// 손을 떼도 안 멈추고 `maxSec`(12초)까지 저 혼자 운다 — 사용자 지적,
  /// 2026-09-16: "짧게 누르면 짧게 나와야지". 실제 원인은 여기 있었다 —
  /// 예전엔 `holdOff(pointer)` 하나만 불러서, 화음이거나 포인터 번호가
  /// `_voiceId(pointer,0)`(=`pointer*8`)과 다른 경우(포인터 0이 아닌 모든
  /// 손가락) **한 번도 제대로 놓인 적이 없었다.**
  final Map<int, int> _downVoiceCount = {};

  /// 그 손가락이 물고 있던 소리를 **전부** 놓는다.
  void _releaseHeld(int pointer) {
    final n = _downVoiceCount.remove(pointer) ?? 1;
    for (var i = 0; i < n; i++) {
      host?.holdOff(_voiceId(pointer, i));
    }
  }

  /// 반음 건반에서 **초보 모드가 죽여 둔 건반**인가 — 죽은 건반은 누른 셈을
  /// 안 친다(소리도, 녹음도, 불도 안 켠다). 다이아토닉 패드는 늘 조에 맞으니
  /// 여기서 늘 거짓이다.
  bool _muted(int value) =>
      _chromatic && widget.beginner && !ChromaticPad.inScale(value, key);

  void _padDown(int pointer, int degree) {
    if (_muted(degree)) return;
    _down[pointer] = degree;
    _downAt[pointer] = _clock.pos(_loopSec);
    _hold(pointer, degree);
    setState(() => _hot.add(degree));
  }

  /// 손가락이 옆 패드로 넘어갔다 — **앞 음을 놓고 새 음을 잡는다.**
  void _padSlide(int pointer, int degree) {
    final was = _down[pointer];
    if (was == degree) return;
    if (was == null) return; // 이 손가락으로 시작한 게 아니다
    if (_muted(degree)) return; // 죽은 건반으로는 안 넘어간다 — 앞 음을 계속 잡는다
    // **지나간 음도 담는다.** 끌면 그 음들이 실제로 들렸으니 담기는 것도 같아야
    // 한다 — 뗄 때 한 번만 담으면 마지막 음만 남아서 「내가 친 게 아닌데」가 된다.
    final from = _downAt[pointer];
    if (from != null) _record(was, heldFrom: from);
    _down[pointer] = degree;
    _downAt[pointer] = _clock.pos(_loopSec);
    // 엔진이 같은 번호의 앞 음을 알아서 놓지만, 그냥 놓고 새로 켜면 딱 끊겨
    // 붙는다 — 옆 칸으로 **미끄러지듯** 넘어가라고(사용자 요청, 2026-09-15)
    // 앞 음 높이를 `glideF`로 같이 보낸다. 엔진은 이미 그 값으로 포르타멘토를
    // 만들 줄 안다(`synth.dart` — 멜로디 레가토에 이미 쓰던 길).
    _hold(pointer, degree, fromDegree: was);
    setState(() {
      _hot.remove(was);
      _hot.add(degree);
    });
  }

  void _padUp(int pointer) {
    final degree = _down.remove(pointer);
    final at = _downAt.remove(pointer);
    _releaseHeld(pointer);
    if (degree == null) return;
    // **뗄 때 적는다** — 얼마나 잡고 있었는지는 떼 봐야 안다.
    if (at != null) _record(degree, heldFrom: at);
    setState(() => _hot.remove(degree));
  }

  /// 그 도수(또는 반음 건반이면 반음)를 잡는다. 화음·아르페지오는 음이
  /// 여럿이라 **번호를 나눠 쓴다**(한 손가락이 여러 소리를 물 수 있게 —
  /// 엔진은 번호 하나에 하나만 문다). 반음 건반은 늘 단음이다(§ChromaticPad).
  void _hold(int pointer, int degree, {int? fromDegree}) {
    final h = host;
    if (h == null) return;
    h.setSongMode(false); // 손가락에 붙어야 한다
    List<List<dynamic>> eventsOf(int d) => _chromatic
        ? ChromaticPad.events(
            semi: d,
            key: key,
            oct: _oct,
            voice: widget.live.voice,
            dur: _kLens[_len].$2,
          )
        : LivePads.events(
            d,
            mode: _mode,
            key: key,
            oct: _oct,
            voice: widget.live.voice,
            dur: _kLens[_len].$2,
          );
    final ev = eventsOf(degree);
    // 아르페지오는 시간차로 흩뿌리는 것이라 **잡아 두면 아르페지오가 아니다** —
    // 그쪽은 예전 길(batch)을 그대로 쓴다. 반음 건반은 늘 단음이라 여기 안 온다.
    if (!_chromatic && _mode == LiveMode.arp) {
      h.batch(ev);
      return;
    }
    // 이 손가락이 지금부터 몇 개를 무는지 적어 둔다 — 뗄 때(`_releaseHeld`)
    // 전부 놓아야 한다(화음이면 3개).
    _downVoiceCount[pointer] = ev.length;
    // 슬라이드로 넘어온 것이면 **직전 음 높이**를 같은 자리(i번째 음)에서
    // 찾아 글라이드 시작점으로 준다 — 화음처럼 음이 여럿이어도 자리끼리
    // 잇는다. 새로 누른 것(fromDegree 없음)은 그냥 0(글라이드 없음).
    final fromEv = fromDegree == null ? null : eventsOf(fromDegree);
    for (var i = 0; i < ev.length; i++) {
      final e = ev[i];
      final glideF = (fromEv != null && i < fromEv.length)
          ? fromEv[i][1] as double
          : 0.0;
      h.holdOn(
        _voiceId(pointer, i),
        e[0] as String,
        e[1] as double,
        e[3] as int,
        soft: e[4] as bool,
        glideF: glideF,
        part: e[7] as int,
      );
    }
  }

  /// 한 손가락이 여러 음을 물 때 쓰는 번호. 포인터 번호가 커도 안 겹치게 벌려 둔다.
  static int _voiceId(int pointer, int i) => pointer * 8 + i;

  /// 악기 서랍에서 한 번 눌렀을 때 — **그 악기로 한 음**을 들려준다.
  ///
  /// 지금 조·옥타브 그대로라 「이 소리로 치면 이렇다」가 그대로 들린다.
  /// 녹음 중이어도 **적지 않는다** — 고르는 중에 난 소리는 연주가 아니다.
  void _previewVoice(String voice) {
    final h = host;
    if (h == null) return;
    h.setSongMode(false);
    h.batch(
      LivePads.events(
        0, // 으뜸음 — 어느 악기든 같은 음으로 견주게 한다
        mode: LiveMode.single,
        key: key,
        oct: _oct,
        voice: voice,
        dur: 0.9,
      ),
    );
  }

  /// 친 걸 적어 둔다 — **들린 것과 같은 음들**을 남긴다.
  /// 화음이면 3음, 아르페지오면 친 시간차 그대로 4음(칸에 맞춰 떨어진다).
  /// [heldFrom] 이 있으면 **그때부터 지금까지**를 길이로 적는다 —
  /// 들린 것과 담긴 것이 다르면 안 된다. 톡 친 것은 고른 길이가 바닥이 된다.
  void _record(int degree, {double? heldFrom}) {
    final rec = _rec;
    if (rec == null) return;
    final pos = heldFrom ?? _clock.pos(_loopSec);
    var len = _kLens[_len].$3;
    if (heldFrom != null && _loopSec > 0) {
      var frac = _clock.pos(_loopSec) - heldFrom;
      if (frac < 0) frac += 1; // 판을 넘어갔다
      final spb = widget.project.spb;
      final steps = (frac * _loopBars * spb).round();
      if (steps > len) len = steps.clamp(1, _loopBars * spb);
    }
    // 반음 건반은 늘 단음이다 — 코드·아르페지오는 다이아토닉 패드에서만.
    // (`_chromatic` 이 아니라 `_recChromatic` 을 본다 — 녹음 도중 전환해도
    // 이번 판은 시작할 때 쓰던 건반으로 끝까지 적힌다.)
    if (_recChromatic) {
      rec.hit(_recSemi(degree), pos, lenSteps: len);
      setState(() {});
      return;
    }
    switch (_mode) {
      case LiveMode.single:
        rec.hit(_recDeg(degree), pos, lenSteps: len);
      case LiveMode.chord:
        // 3화음 = 음계로 도수 d, d+2, d+4 (`diatonicChords` 와 같은 자리)
        for (final k in [0, 2, 4]) {
          rec.hit(_recDeg(degree + k), pos, lenSteps: len * 2);
        }
      case LiveMode.arp:
        const seq = [0, 2, 4, 7];
        for (var i = 0; i < seq.length; i++) {
          final at = _loopSec > 0 ? pos + (i * 0.11) / _loopSec : pos;
          rec.hit(_recDeg(degree + seq[i]), at, lenSteps: len);
        }
    }
    setState(() {});
  }

  /// 옥타브 버튼을 올려 둔 채로 쳤으면 그만큼 올려서 적는다.
  /// 패턴이 담을 수 있는 도수는 0~14 뿐이라 넘치면 **한 옥타브 내려서** 담는다
  /// (그대로 자르면 눌린 음과 다른 음이 남는다 — 계이름은 지키는 쪽을 골랐다).
  int _recDeg(int degree) {
    var d = degree + 7 * _oct;
    while (d > 14) {
      d -= 7;
    }
    while (d < 0) {
      d += 7;
    }
    return d;
  }

  /// `_recDeg` 의 반음 판(0~24, `kProRows` 와 같은 범위) — 넘치면 한 옥타브
  /// 접어서 담는다.
  int _recSemi(int semi) {
    var s = semi + 12 * _oct;
    while (s > 24) {
      s -= 12;
    }
    while (s < 0) {
      s += 12;
    }
    return s;
  }

  // ── 녹음 ──

  /// 이번 녹음이 반음 건반이었나 — **녹음 도중에 전환해도 안 섞이게**
  /// `_toggleRec` 이 시작할 때 잠가 둔다(`_keep` 이 이 값을 쓴다).
  bool _recChromatic = false;

  void _toggleRec() {
    final rec = _rec;
    if (rec == null) {
      // 안 틀고 녹음하면 박자 기준이 없다 — 반주부터 켠다
      if (!widget.transport.playing) _togglePlay();
      final b = SceneSequencer.build(widget.project, widget.transport, reps: 1);
      _loopSec = b.loopSec;
      _loopBars = b.loopBars;
      _recChromatic = _chromatic;
      setState(() {
        _rec = LiveRecorder(
          steps: _loopBars * widget.project.spb,
          loopSec: _loopSec,
          // 귀에 닿는 소리는 앞질러 만든 양만큼 늦다 — 그만큼 되돌려 박에 맞춘다
          latencySec: (host?.aheadFrames ?? 3072) / 48000.0,
        );
      });
      return;
    }
    final notes = rec.notes();
    setState(() => _rec = null);
    if (notes.isEmpty) {
      _say('아무것도 안 쳤습니다');
      return;
    }
    _keep(notes);
  }

  /// 친 걸 **바로 트랙으로 만든다** — 어디에 담을지 묻지 않는다.
  /// 담기는 곳은 지금 씬의 「라이브」 트랙이고, 이름은 씬을 따라간다
  /// (같은 씬에서 다시 치면 덮어쓴다 — 마음에 들 때까지 다시 치는 게 자연스럽다).
  void _keep(List<List<Object?>> notes) {
    final p = widget.project;
    final t = p.ensureLiveTrack(widget.live.voice);
    final name = '라이브 ${p.scene.name}';
    p.putUserPattern(
      'melody',
      name,
      note: NotePatternDef(
        name,
        _loopBars,
        _loopBars,
        notes,
        chromatic: _recChromatic,
      ),
    );
    p.setClip(t, name);
    final h = host;
    if (h != null) {
      h.configureBuses(SceneSequencer.busNames(p));
      SceneSequencer.pushMix(p, h);
      if (widget.transport.playing) {
        if (widget.transport.songLoop) {
          // 곡 재생 중이면 refreshLoop 로는 몇 분 뒤에나 반영된다 — 방금
          // 담은 걸 바로 들으려고 씬 루프로 갈아탄다(씬 전환과 같은 이유).
          SceneSequencer.playLoop(widget.project, widget.transport, h);
          widget.transport.songLoop = false;
          h.setSongMode(false);
        } else {
          SceneSequencer.refreshLoop(p, widget.transport, h);
        }
      }
    }
    _say('${notes.length}음을 「라이브」 트랙에 담았습니다 — 다음 판부터 같이 납니다');
  }

  void _say(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 12.5)),
        duration: const Duration(milliseconds: 1800),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── 루프 ──

  void _togglePlay() {
    final h = host;
    if (h == null) return;
    if (widget.transport.playing) {
      h.allOff();
      h.setSongMode(false);
      widget.transport.playing = false;
    } else {
      SceneSequencer.playLoop(widget.project, widget.transport, h);
      widget.transport.playing = true;
      widget.transport.songLoop = false; // 씬 한 판 루프다 — 곡 재생이 아니다
      h.setSongMode(false); // 루프는 돌리되 반응은 라이브 쪽에 맞춘다
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final playing = widget.transport.playing;

    // **가로로 눕히면 반대가 된다** — 폭은 남고 높이가 모자란다.
    // 세로에서 두 줄로 나눈 것들을 가로에서는 다시 한 줄로 붙인다.
    // 안 그러면 패드가 화면의 3분의 1로 쪼그라든다(그림으로 뽑아 보고 잡았다).
    final wide = MediaQuery.of(context).size.height < 520;
    final rec = _rec;

    // **친 것을 말없이 버리지 않는다.**
    //
    // 「담기 N」이 떠 있는데 뒤로가기(← 나 안드로이드 뒤로)를 누르면 여태는 화면과
    // 함께 `LiveRecorder` 가 통째로 사라졌다 — 안내도, 확인도, 스낵바도 없었다.
    // 몇 마디를 쳐 놓고 씬을 확인하러 잠깐 나갔다 오면 그게 없다.
    //
    // `dispose()` 에서 담으면 안 된다. `_keep` 이 `putUserPattern`/`ensureLiveTrack`
    // 으로 `notifyListeners` 를 부르는데, dispose 는 트리가 잠긴 상태에서 돌아
    // 「widget tree was locked」로 터진다. pop 을 붙잡는 자리는 평범한 콜백이라
    // setState 도 스낵바도 합법이다.
    return PopScope(
      canPop: rec == null || rec.count == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _toggleRec(); // 담는 길은 하나만 둔다 — 스낵바까지 제자리에서 뜬다
        if (mounted) Navigator.of(context).pop();
      },
      child: Column(
        children: [
          _TopBar(
            playing: playing,
            onPlay: _togglePlay,
            recording: _rec != null,
            recCount: _rec?.count ?? 0,
            onRec: _toggleRec,
          ),
          _ControlRow(
            voice: widget.live.voice,
            met: _met,
            onMet: _toggleMet,
            favs: _favs.where((v) => v != widget.live.voice).toList(),
            onFav: _useVoice,
            onVoice: () async {
              final picked = await pickVoiceSheet(
                context,
                widget.live.voice,
                // 소리 장치가 없으면 미리듣기를 안 준다 — 그러면 예전처럼
                // 한 번에 고른다(시험도 이 길로 돈다).
                onPreview: host == null ? null : _previewVoice,
              );
              if (picked == null) return;
              _useVoice(picked);
            },
            mode: _mode,
            onMode: (m) => setState(() => _mode = m),
            oct: _oct,
            onOct: (d) => setState(() => _oct = (_oct + d).clamp(-1, 2)),
            wide: wide,
            chromatic: _chromatic,
            onChromatic: _toggleChromatic,
          ),
          _LiveKnobs(
            wide: wide,
            live: widget.live,
            onChanged: () {
              host?.setBus('live', vol: widget.live.vol, rev: widget.live.rev);
              setState(() {});
            },
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              // ── 꾹 눌러 소리 유지 · 끌어서 음 잇기 ──
              //
              // **패드마다 Listener 를 달면 안 된다.** 손가락이 그 패드를 벗어나는
              // 순간 그 위젯은 move 를 더 못 받는다(포인터는 처음 잡은 위젯에 묶인다).
              // 그래서 격자 전체에 하나만 달고 **자리로 어느 패드인지 셈한다.**
              child: _chromatic
                  ? LayoutBuilder(
                      builder: (context, c) {
                        int? pcAt(Offset p) {
                          if (p.dx < 0 || p.dx >= c.maxWidth) return null;
                          if (p.dy < 0 || p.dy >= c.maxHeight) return null;
                          return _PianoKeyboard.pitchClassAt(
                            p,
                            c.maxWidth,
                            c.maxHeight,
                          );
                        }

                        // 화면이 보여 주는 건 **피아노의 음이름(C·D#…)** 이지만
                        // 잡는 건 **으뜸음에서 몇 반음**(semi) — 조가 바뀌어도
                        // 저장한 것이 저절로 따라간다(도수와 같은 약속).
                        int? semiAt(Offset p) {
                          final pc = pcAt(p);
                          if (pc == null) return null;
                          return (pc - key.root % 12 + 12) % 12;
                        }

                        return Listener(
                          onPointerDown: (e) {
                            final s = semiAt(e.localPosition);
                            if (s != null) _padDown(e.pointer, s);
                          },
                          onPointerMove: (e) {
                            final s = semiAt(e.localPosition);
                            if (s != null) _padSlide(e.pointer, s);
                          },
                          onPointerUp: (e) => _padUp(e.pointer),
                          onPointerCancel: (e) => _padUp(e.pointer),
                          child: _PianoKeyboard(
                            hot: _hot,
                            keyOf: key,
                            oct: _oct,
                            muted: (semi) => _muted(semi),
                          ),
                        );
                      },
                    )
                  : LayoutBuilder(
                      builder: (context, c) {
                        // 두 줄 · 사이 6 — 아래 Column 과 같은 값이어야 한다
                        final rowH = (c.maxHeight - 6) / 2;
                        final colW = c.maxWidth / 7;
                        int? padAt(Offset p) {
                          if (p.dx < 0 || p.dx >= c.maxWidth) return null;
                          if (p.dy < 0 || p.dy >= c.maxHeight) return null;
                          final col = (p.dx / colW).floor().clamp(0, 6);
                          // 위가 높은 옥타브(7~13), 아래가 낮은 쪽(0~6)
                          final top = p.dy < rowH;
                          if (!top && p.dy < rowH + 6) return null; // 줄 사이 틈
                          return (top ? 7 : 0) + col;
                        }

                        return Listener(
                          onPointerDown: (e) {
                            final d = padAt(e.localPosition);
                            if (d != null) _padDown(e.pointer, d);
                          },
                          onPointerMove: (e) {
                            final d = padAt(e.localPosition);
                            if (d != null) _padSlide(e.pointer, d);
                          },
                          onPointerUp: (e) => _padUp(e.pointer),
                          onPointerCancel: (e) => _padUp(e.pointer),
                          child: Column(
                            children: [
                              // 위가 높은 옥타브 — 악보와 같은 방향, 지금 손이
                              // 있는 자리라 또렷하게 둔다.
                              Expanded(
                                child: _PadRow(
                                  from: 7,
                                  hot: _hot,
                                  keyOf: key,
                                  oct: _oct,
                                ),
                              ),
                              const SizedBox(height: 6),
                              // 아래 옥타브는 살짝 죽여서 "지금 칠 자리"와
                              // "한 옥타브 아래"가 한눈에 갈리게 한다(사용자
                              // 요청, 2026-09-15: "배치를 잘 하자").
                              Expanded(
                                child: _PadRow(
                                  from: 0,
                                  dim: true,
                                  hot: _hot,
                                  keyOf: key,
                                  oct: _oct,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 악기 고르기 — **계열별로 묶어서** 보여 준다.
/// 사람은 "기타 비슷한 거"를 찾지 'nylon' 을 찾지 않는다.
///
/// **한 번 누르면 들려주고, 같은 것을 다시 눌러야 바뀐다.**
/// 서른 개 가까운 악기를 소리 한 번 못 듣고 이름만 보고 골라야 했다 —
/// 고르고, 패드를 쳐 보고, 아니면 다시 열고. 한 번에 끝나던 일이 세 번이었다.
/// ([onPreview] 가 없으면 예전처럼 한 번에 고른다 — 소리 장치가 없을 때다)
Future<String?> pickVoiceSheet(
  BuildContext context,
  String current, {
  void Function(String voice)? onPreview,
}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF1A1A1E),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _VoiceSheetBody(current: current, onPreview: onPreview),
  );
}

/// 시트 몸통 — **겨눠 둔 악기**를 들고 있어야 해서 State 가 필요하다.
class _VoiceSheetBody extends StatefulWidget {
  final String current;
  final void Function(String voice)? onPreview;
  const _VoiceSheetBody({required this.current, required this.onPreview});

  @override
  State<_VoiceSheetBody> createState() => _VoiceSheetBodyState();
}

class _VoiceSheetBodyState extends State<_VoiceSheetBody> {
  /// 한 번 눌러 **들어 본** 악기. 같은 것을 다시 누르면 그때 바뀐다.
  String? armed;

  @override
  Widget build(BuildContext ctx) {
    final current = widget.current;
    final onPreview = widget.onPreview;
    void setSt(VoidCallback f) => setState(f);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.72,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '악기',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(
                onPreview == null
                    ? '고르면 다음에 누르는 패드부터 이 소리로 납니다.'
                    : '한 번 누르면 들려줍니다 · 같은 걸 다시 누르면 바뀝니다.',
                style: const TextStyle(fontSize: 11.5, color: Colors.white38),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in kVoiceFamily.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    kVoiceFamilyIcon[e.key] ?? Icons.piano,
                                    size: 13,
                                    color: Colors.white38,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    e.key,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white38,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final v in e.value)
                                    GestureDetector(
                                      onTap: () {
                                        // 소리를 못 내면 예전처럼 한 번에 고른다
                                        if (onPreview == null) {
                                          Navigator.pop(ctx, v);
                                          return;
                                        }
                                        // 겨눠 둔 것을 다시 누르면 그때 바뀐다
                                        if (armed == v) {
                                          Navigator.pop(ctx, v);
                                          return;
                                        }
                                        onPreview(v);
                                        setSt(() => armed = v);
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 11,
                                          vertical: 9,
                                        ),
                                        decoration: BoxDecoration(
                                          color: armed == v
                                              ? Colors.amber.shade400
                                              : (v == current
                                                    ? Colors.tealAccent.shade400
                                                    : Colors.white10),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          armed == v
                                              ? '${VOICE_LABEL[v] ?? v} · 다시 탭'
                                              : (VOICE_LABEL[v] ?? v),
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight:
                                                (v == current || armed == v)
                                                ? FontWeight.w800
                                                : FontWeight.w400,
                                            color: (v == current || armed == v)
                                                ? Colors.black
                                                : Colors.white70,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 패드 한 줄 = 도수 7개.
class _PadRow extends StatelessWidget {
  final int from;
  final Set<int> hot;
  final MusicKey keyOf;
  final int oct;

  /// 아래 옥타브 줄 — 살짝 죽여서 "지금 칠 자리"와 구분한다.
  final bool dim;

  /// 누르는 것은 **격자 전체가 받는다**(손가락이 패드를 넘나들어야 하므로).
  /// 여기는 그리기만 한다.
  const _PadRow({
    required this.from,
    required this.hot,
    required this.keyOf,
    required this.oct,
    this.dim = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _Pad(
                degree: from + i,
                name: _noteNameOf(from + i, keyOf, oct),
                hot: hot.contains(from + i),
                dim: dim,
              ),
            ),
          ),
      ],
    );
  }
}

/// 도수 → 계이름 + 옥타브(C4·D#5…). 무슨 음을 누르는지 보이면 **배우게 된다** —
/// 이 앱은 연주 장난감이면서 동시에 처음 배우는 사람의 첫 악기다.
///
/// 옥타브 숫자를 빼면 **두 줄이 글자까지 똑같아진다**(1 C / 1 C) — 폰에서 보고 알았다.
/// 위아래 줄이 뭐가 다른지 화면만 봐선 알 수 없으면 윗줄은 안 쓰게 된다.
String _noteNameOf(int degree, MusicKey key, int oct) =>
    noteNameIn(LivePads.midiOf(degree, key, oct), key.root, key.mode);

/// 도수 패드 하나 — **진짜 건반처럼**(사용자 요청, 2026-09-15: "라이브 모드는
/// 진짜 건반처럼 하고 배치를 잘 하자"). 다이아토닉 7음은 검은 건반이 없는
/// "흰 건반 한 옥타브"와 정확히 같은 개수라, 실제 흰 건반 모양(아이보리색,
/// 아래만 둥근 모서리)을 그대로 쓰고 으뜸음만 짙게 칠해 표시한다.
/// 누르면 실제로 눌리는 것처럼 살짝 내려앉고 그림자가 줄어든다.
class _Pad extends StatelessWidget {
  final int degree;
  final String name;
  final bool hot;
  final bool dim;
  const _Pad({
    required this.degree,
    required this.name,
    required this.hot,
    this.dim = false,
  });

  static const _ivory = Color(0xFFEDEFEA);
  static const _ink = Color(0xFF23251F);

  @override
  Widget build(BuildContext context) {
    final isRoot = degree % 7 == 0; // 으뜸음은 색이 다르다(길을 잃지 않게)
    // **`Opacity` 위젯으로 죽이지 않는다** — 위젯 트리를 감싸면 위젯 테스트의
    // 좌표 찾기(getCenter)가 어긋나는 경우가 있었다(직접 실패로 확인). 대신
    // 색 하나하나에 알파를 섞어서 같은 눈으로 보이는 "죽임"을 만든다.
    final dimmed = dim && !hot;
    final a = dimmed ? 0.55 : 1.0;
    final base = isRoot
        ? Colors.teal.shade700.withValues(alpha: a)
        : _ivory.withValues(alpha: a);
    final fg = isRoot ? Colors.white : _ink;
    // **`transform` 은 안 쓴다** — 위젯 테스트에서 손가락을 옆 칸으로 끄는
    // 도중 눌린 칸의 자리가 옮겨진 것처럼 위젯 테스트의 좌표 찾기가
    // 어긋나는 경우가 있었다(직접 실패로 확인). 눌림은 색·그림자만으로 낸다.
    return AnimatedContainer(
      duration: const Duration(milliseconds: 70),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: hot ? Colors.tealAccent.shade400 : base,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(11),
          top: Radius.circular(3),
        ),
        border: Border.all(
          color: hot
              ? Colors.white
              : (isRoot ? Colors.black26 : Colors.black12).withValues(
                  alpha: a,
                ),
          width: hot ? 1.8 : 1,
        ),
        boxShadow: hot
            ? const [
                BoxShadow(color: Colors.black38, blurRadius: 2, offset: Offset(0, 1)),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: (isRoot ? 0.35 : 0.25) * a,
                  ),
                  blurRadius: 5,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      // 글자는 **가운데**에 둔다 — 아래쪽에 붙이면(건반 느낌은 살지만)
      // 실제 렌더 위치가 칸 가장자리에 너무 가까워져서, 화면 높이가 빠듯한
      // 자리(예: AppBar 가 있는 화면)에서 손짓 계산 경계 밖으로 밀려나는
      // 것을 위젯 테스트로 확인했다(직접 실패로 확인, 2026-09-15).
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${degree % 7 + 1}',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
              color: hot ? Colors.black87 : fg.withValues(alpha: a),
            ),
          ),
          Text(
            name,
            style: TextStyle(
              fontSize: 9.5,
              color: hot
                  ? Colors.black54
                  : fg.withValues(alpha: 0.62 * a),
            ),
          ),
        ],
      ),
    );
  }
}

/// 반음 건반 — **실제 피아노처럼** 흰 건반 7 + 검은 건반 5(한 옥타브).
///
/// 자리는 **음이름**(C·C#·D…)으로 고정한다 — 조가 바뀌어도 피아노 모양은
/// 그대로다(실제 피아노가 그렇듯). 지금 조의 으뜸음이 어느 건반인지만
/// 색으로 옮겨 다닌다. 더 높이·낮게는 기존 「옥타브 ▼/▲」를 그대로 쓴다.
class _PianoKeyboard extends StatelessWidget {
  /// 흰 건반 7개의 피치 클래스(C=0).
  static const List<int> whitePc = [0, 2, 4, 5, 7, 9, 11];

  /// 검은 건반 5개 — (몇 번째 흰 건반 뒤인가, 피치 클래스).
  static const List<(int, int)> blackPc = [
    (0, 1), // C#
    (1, 3), // D#
    (3, 6), // F#
    (4, 8), // G#
    (5, 10), // A#
  ];

  static const _names = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];

  final Set<int> hot; // 지금 눌린 반음(semi, 으뜸음 기준)
  final MusicKey keyOf;
  final int oct;
  final bool Function(int semi) muted;
  const _PianoKeyboard({
    required this.hot,
    required this.keyOf,
    required this.oct,
    required this.muted,
  });

  /// 화면 자리 → 피치 클래스(C=0…B=11). 검은 건반이 흰 건반 위에 겹치므로
  /// 검은 건반부터 맞혀 본다(손가락이 위쪽에 먼저 닿는 것과 같다).
  static int pitchClassAt(Offset p, double w, double h) {
    final colW = w / 7;
    final blackH = h * 0.62;
    if (p.dy < blackH) {
      final blackW = colW * 0.62;
      for (final (afterWhite, pc) in blackPc) {
        final cx = (afterWhite + 1) * colW;
        if (p.dx >= cx - blackW / 2 && p.dx <= cx + blackW / 2) return pc;
      }
    }
    final col = (p.dx / colW).floor().clamp(0, 6);
    return whitePc[col];
  }

  int _semiOf(int pc) => (pc - keyOf.root % 12 + 12) % 12;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final colW = c.maxWidth / 7;
        final blackH = c.maxHeight * 0.62;
        final blackW = colW * 0.62;
        return SizedBox(
          width: c.maxWidth,
          height: c.maxHeight,
          child: Stack(
            children: [
              Positioned.fill(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final pc in whitePc)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1.5),
                          child: _Key(
                            white: true,
                            label: _names[pc],
                            isRoot: _semiOf(pc) == 0,
                            hot: hot.contains(_semiOf(pc)),
                            dead: muted(_semiOf(pc)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              for (final (afterWhite, pc) in blackPc)
                Positioned(
                  left: (afterWhite + 1) * colW - blackW / 2,
                  top: 0,
                  width: blackW,
                  height: blackH,
                  child: _Key(
                    white: false,
                    label: _names[pc],
                    isRoot: _semiOf(pc) == 0,
                    hot: hot.contains(_semiOf(pc)),
                    dead: muted(_semiOf(pc)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 건반 하나(흰/검) — 색만 다르고 그리는 규칙은 같다.
class _Key extends StatelessWidget {
  final bool white;
  final String label;
  final bool isRoot;
  final bool hot;

  /// **초보 모드가 죽인 건반** — 지금 조에 안 맞아 흐리고, 눌러도 안 탄다.
  final bool dead;
  const _Key({
    required this.white,
    required this.label,
    required this.isRoot,
    required this.hot,
    required this.dead,
  });

  @override
  Widget build(BuildContext context) {
    final base = white ? Colors.white : const Color(0xFF1C1E22);
    final rootColor = white ? Colors.teal.shade200 : Colors.teal.shade700;
    var color = isRoot ? rootColor : base;
    if (hot) color = Colors.tealAccent.shade400;
    if (dead) color = base.withValues(alpha: 0.28);
    final textColor = white ? Colors.black87 : Colors.white70;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 90),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.vertical(
          bottom: const Radius.circular(8),
          top: white ? Radius.zero : const Radius.circular(4),
        ),
        border: Border.all(
          color: hot ? Colors.white : Colors.black26,
          width: hot ? 2 : 1,
        ),
        boxShadow: white
            ? const []
            : const [
                BoxShadow(color: Colors.black54, blurRadius: 3, offset: Offset(0, 2)),
              ],
      ),
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isRoot ? FontWeight.w900 : FontWeight.w600,
          color: dead ? textColor.withValues(alpha: 0.35) : textColor,
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final bool playing, recording;
  final int recCount;
  final VoidCallback onPlay, onRec;
  const _TopBar({
    required this.playing,
    required this.onPlay,
    required this.recording,
    required this.recCount,
    required this.onRec,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: FilledButton.icon(
                onPressed: onPlay,
                icon: Icon(playing ? Icons.stop : Icons.play_arrow, size: 18),
                label: Text(
                  playing ? '정지' : '반주',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: playing
                      ? Colors.red.shade700
                      : Colors.teal.shade600,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SizedBox(
              height: 40,
              child: FilledButton.icon(
                onPressed: onRec,
                icon: Icon(
                  recording ? Icons.stop_circle : Icons.fiber_manual_record,
                  size: 18,
                ),
                label: Text(
                  recording ? '담기 $recCount' : '녹음',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: recording
                      ? Colors.red.shade600
                      : Colors.white12,
                  foregroundColor: recording
                      ? Colors.white
                      : Colors.red.shade300,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ControlRow extends StatelessWidget {
  final String voice;
  final VoidCallback onVoice;

  /// 최근에 쓴 악기(지금 것 빼고) — 한 번 탭으로 되돌아간다.
  final List<String> favs;
  final ValueChanged<String> onFav;

  /// 메트로놈 — 드럼 없는 씬에서 녹음할 때 기댈 박.
  final bool met;
  final VoidCallback onMet;
  final LiveMode mode;
  final ValueChanged<LiveMode> onMode;
  final int oct;
  final ValueChanged<int> onOct;
  final bool wide;

  /// 반음 건반(다이아토닉 패드 대신 12음 전부) 켜짐 여부.
  final bool chromatic;
  final VoidCallback onChromatic;
  const _ControlRow({
    required this.wide,
    required this.voice,
    required this.onVoice,
    required this.favs,
    required this.onFav,
    required this.met,
    required this.onMet,
    required this.mode,
    required this.onMode,
    required this.oct,
    required this.onOct,
    required this.chromatic,
    required this.onChromatic,
  });

  @override
  Widget build(BuildContext context) {
    // 여섯 가지를 한 줄에 늘어놨더니 **옥타브가 화면 밖으로 밀려났다**(폰에서 확인:
    // 처음 보이는 건 「피아노▾ 단음 화음 아르페지오 짧게 보통 …」 까지고
    // 「길게」도 잘려 있다). 옥타브는 라이브에서 없으면 안 되는 값인데
    // 있는 줄도 모른다. 두 줄로 갈랐다.
    final voiceChip = _Chip(
      label: '${VOICE_LABEL[voice] ?? voice} ▾',
      on: true,
      onTap: onVoice,
    );
    // **최근에 쓴 악기 넷** — 연주 중에 모달을 열었다 닫으면 그 사이 연주가 끊긴다.
    // 자주 오가는 둘·셋은 한 번 탭으로 닿아야 한다.
    final favChips = [
      for (final v in favs) ...[
        const SizedBox(width: 6),
        _Chip(label: VOICE_LABEL[v] ?? v, on: false, onTap: () => onFav(v)),
      ],
    ];
    final metChip = _Chip(label: '메트', on: met, onTap: onMet);
    // 반음 건반 — 켜면 도수 패드(단음·화음·아르페지오) 대신 실제 피아노가
    // 나온다. 화음·아르페지오는 도수를 전제로 해서 반음에는 없다(§live_ops
    // ChromaticPad) — 그래서 켜져 있을 때는 모드 칩을 안 보여 준다.
    final chromChip = _Chip(label: '반음', on: chromatic, onTap: onChromatic);
    final modeChips = [
      _Chip(
        label: '단음',
        on: mode == LiveMode.single,
        onTap: () => onMode(LiveMode.single),
      ),
      _Chip(
        label: '화음',
        on: mode == LiveMode.chord,
        onTap: () => onMode(LiveMode.chord),
      ),
      _Chip(
        label: '아르페지오',
        on: mode == LiveMode.arp,
        onTap: () => onMode(LiveMode.arp),
      ),
    ];
    final octChips = [
      _Chip(label: '▼', on: false, onTap: () => onOct(-1)),
      Container(
        height: 40,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          oct == 0 ? '옥타브 기본' : '옥타브 ${oct > 0 ? '+$oct' : '$oct'}',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: oct == 0 ? Colors.white54 : Colors.tealAccent.shade200,
          ),
        ),
      ),
      _Chip(label: '▲', on: false, onTap: () => onOct(1)),
    ];

    // 가로: 폭이 남으니 **한 줄**(800dp 에 641dp 어치라 다 들어간다)
    if (wide) {
      return SizedBox(
        height: 52, // 52 − 위아래 6 = 칩 40. 예전엔 44 − 6 = 32 였다
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          children: [
            voiceChip,
            ...favChips,
            const SizedBox(width: 10),
            chromChip,
            const SizedBox(width: 6),
            if (!chromatic) ...modeChips,
            const SizedBox(width: 14),
            ...octChips,
            const SizedBox(width: 10),
            metChip,
          ],
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 52, // 칩이 40 이 되게
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            children: [
              // 음색은 **한 칸으로 접는다** — 24개를 한 줄에 늘어놓으면 원하는 악기를
              // 찾으려고 계속 밀어야 하고, 그 줄이 패드 자리를 먹는다.
              _Chip(
                label: '${VOICE_LABEL[voice] ?? voice} ▾',
                on: true,
                onTap: onVoice,
              ),
              ...favChips,
              const SizedBox(width: 10),
              chromChip,
              if (!chromatic) ...[const SizedBox(width: 6), ...modeChips],
            ],
          ),
        ),
        SizedBox(
          height: 46, // 칩이 40 이 되게
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
            children: [
              // 옥타브 — 「−/+」만 있으면 무엇의 −인지 모른다. 지금 값을 가운데 둔다.
              _Chip(label: '▼', on: false, onTap: () => onOct(-1)),
              Container(
                height: 40,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  oct == 0 ? '옥타브 기본' : '옥타브 ${oct > 0 ? '+$oct' : '$oct'}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: oct == 0
                        ? Colors.white54
                        : Colors.tealAccent.shade200,
                  ),
                ),
              ),
              _Chip(label: '▲', on: false, onTap: () => onOct(1)),
              const SizedBox(width: 14),
              metChip,
            ],
          ),
        ),
      ],
    );
  }
}

/// 라이브 볼륨·잔향 — 믹서까지 안 가고 여기서 바로 잡는다(치면서 조절하는 값들이다).
class _LiveKnobs extends StatelessWidget {
  final LiveChannel live;
  final VoidCallback onChanged;

  /// 가로로 누웠나 — 그때는 두 줄이 아니라 **한 줄에 둘**이다(높이가 아깝다).
  final bool wide;
  const _LiveKnobs({
    required this.live,
    required this.onChanged,
    required this.wide,
  });

  @override
  Widget build(BuildContext context) {
    // 예전엔 아이콘 둘(🔊 · ⬤)에 슬라이더 둘을 한 줄에 반씩 나눠 담았다.
    // 무엇을 만지는 값인지 알 수 없고(`blur_on` 아이콘이 잔향으로 읽힐 리 없다),
    // 슬라이더가 100px 남짓이라 원하는 값에 세우지도 못한다 — 믹서에서 이미
    // 같은 값을 치렀다. **한 줄에 하나씩, 이름과 값을 붙여서.**
    final vol = _LiveSlider(
      label: '볼륨',
      display: '${(live.vol / 1.0 * 100).round()}%',
      value: live.vol,
      max: 1.4,
      onChanged: (v) {
        live.vol = v;
        onChanged();
      },
    );
    final rev = _LiveSlider(
      label: '울림',
      display: '${(live.rev * 100).round()}%',
      value: live.rev,
      max: 1.0,
      onChanged: (v) {
        live.rev = v;
        onChanged();
      },
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: wide
          // 가로: 폭이 남으니 한 줄에 둘(하나에 350dp 씩 — 넉넉하다)
          ? Row(
              children: [
                Expanded(child: vol),
                const SizedBox(width: 16),
                Expanded(child: rev),
              ],
            )
          : Column(children: [vol, rev]),
    );
  }
}

/// 라이브 화면용 한 줄 슬라이더 — 이름 · 슬라이더 · 값.
/// 믹서 시트만큼 크게 하면 패드 자리를 먹으니 높이 36 으로 줄였다(손잡이 반지름 10).
class _LiveSlider extends StatelessWidget {
  final String label, display;
  final double value, max;
  final ValueChanged<double> onChanged;
  const _LiveSlider({
    required this.label,
    required this.display,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          SizedBox(
            width: 38,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.white70,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                activeTrackColor: Colors.tealAccent.shade400,
                thumbColor: Colors.tealAccent.shade400,
                inactiveTrackColor: Colors.white24,
              ),
              child: Slider(
                max: max,
                value: value.clamp(0, max),
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 46,
            child: Text(
              display,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: Colors.tealAccent.shade200,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40, // 32 는 손가락에 비해 작다 — 라이브는 연주 중에 누른다
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? Colors.tealAccent.shade400 : Colors.white12,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: on ? Colors.black87 : Colors.white70,
          ),
        ),
      ),
    );
  }
}
