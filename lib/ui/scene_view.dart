// 씬 화면 — **믹서에 있는 그 트랙들을 실제로 연주하는 곳.**
//
// 웹 씬 뷰는 트랙×씬 **격자**에 클립을 놓고 씬을 발사(launch)한다. 폰 세로에서 격자는
// 칸이 40dp 도 안 나와서, **씬은 칩으로 골라 타고 "지금 씬"만 트랙 목록으로 펴는** 모양
// 으로 폈다(같은 개념, 다른 배치). 씬을 탭하면 클립 한 벌 + 템포 + 드럼 키트가 통째로
// 바뀐다 — 재생 중이면 다음 판부터.
//
// 여기서 고른 **음색·키트·패턴이 곧 소리다** — 5단계 2/N 전에는 화면 글씨였다.
// 세로/가로 모두 같은 '한 줄 = 한 트랙' 배치를 쓴다(가로 믹서에서 쓴 것과 같은 얼개).

import 'dart:async';

import 'package:flutter/material.dart';

import '../audio_isolate.dart';
import '../drums.dart';
import '../instruments.dart';
import '../pattern_names.dart';
import '../presets.dart';
import '../arrange_rec.dart';
import '../project.dart';
import '../sequencer.dart';
import 'editor_view.dart';
import 'critters.dart';
import 'prog_sheet.dart';
import 'doodle_play_view.dart';
import 'play_head.dart';
import 'text_scale.dart';

const _typeColor = {
  'drum': Color(0xFF7CB342),
  'bass': Color(0xFF42A5F5),
  'chord': Color(0xFFAB47BC),
  'melody': Color(0xFFFFA726),
};

class SceneView extends StatefulWidget {
  final Project project;
  final Transport transport;
  final AudioClient? host;

  /// **간단히 보기**인가 (Phase 2). 켜면 조 고르기·음 편집기 같은
  /// 한 단계 깊은 것들을 감춘다 — 기능은 그대로 있고 버튼만 안 보인다.
  final bool simple;

  /// 들어오자마자 **소리부터 낸다** (Phase 2 · 계획 4-2).
  /// 장르를 고르고 들어온 길에서 켠다 — 고른 뒤에 재생 버튼을 또 찾게 하면
  /// "골랐는데 아무 일도 안 일어났다"가 된다.
  final bool autoPlay;

  /// 프로 모드(설정) — 편집기가 반음 줄 손잡이를 열지 정한다.
  final bool pro;
  const SceneView({
    super.key,
    required this.project,
    required this.transport,
    required this.host,
    this.simple = false,
    this.pro = false,
    this.autoPlay = false,
  });

  @override
  State<SceneView> createState() => _SceneViewState();
}

class _SceneViewState extends State<SceneView> {
  String _info = '';

  int _bars = 4;
  double _loopSec = 0;

  /// 템포·조 슬라이더는 드래그하는 내내 값이 바뀐다. 그때마다 씬을 새로 만들어 보내면
  /// 초당 60번 만드는 셈이라 낭비다 — 잠깐 멈추면 그때 한 번만 보낸다.
  Timer? _debounce;

  // ── 연주해서 곡 만들기 ──
  //
  // 여태 곡을 만드는 길은 하나였다: 곡 화면에서 「＋구간 붙이기」로 하나씩 놓기.
  // 그건 **적는 일**이지 만드는 일이 아니다. 씬을 틀어 놓고 인트로 → 벌스 →
  // 코러스로 넘겨 보는 것이 훨씬 자연스럽고, 그때 이미 사람은 곡을 만들고 있다.
  // 그 손짓을 그냥 받아 적는다.
  ArrangeRecorder? _arr;

  /// 언제 시작했나 — 씬을 넘긴 시각을 재는 자.
  /// 엔진 시계가 아니라 벽시계를 쓴다. 재는 것이 **사람이 언제 눌렀나**라서다
  /// (엔진 시계는 판 안의 위치라 판을 넘으면 0 으로 돌아간다).
  final Stopwatch _arrClock = Stopwatch();

  @override
  void initState() {
    super.initState();
    widget.transport.addListener(_onTransport);
    // 들어오자마자 소리부터 낸다 (계획 4-2). 첫 프레임 뒤에 켠다 —
    // build 중에 재생을 걸면 `setState` 가 씹힌다(이 프로젝트에서 겪은 함정이다).
    if (widget.autoPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.host != null) _play();
      });
    }
  }

  @override
  void dispose() {
    widget.transport.removeListener(_onTransport);
    _debounce?.cancel();
    super.dispose();
  }

  void _onTransport() {
    if (!widget.transport.playing) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), _refresh);
  }

  void _play() {
    final host = widget.host;
    if (host == null) return;
    final b = SceneSequencer.playLoop(widget.project, widget.transport, host);
    widget.transport.playing = true;
    widget.transport.songLoop = false; // 씬 한 판 루프다 — 곡 재생이 아니다
    _show(b);
  }

  /// 씬 전환 — 클립 한 벌을 통째로 갈아 끼운다. 템포·드럼 키트까지 같이 바뀐다
  /// (로파이 78 → 하우스 124 를 템포 없이 바꾸면 그 장르로 안 들린다).
  /// 재생 중이면 **다음 판부터** 새 씬이 나온다.
  ///
  /// 스타일·조·느낌 고르기는 이제 여기 없다 — 작업 화면 위쪽 톱니바퀴의
  /// 「프로젝트 설정」(`project_settings_sheet.dart`)으로 옮겼다.

  void _launch(int i) {
    widget.project.launchScene(i);
    final s = widget.project.scenes[i];
    if (s.bpm != null) widget.transport.bpm = s.bpm!;
    // 받아 적는 중이면 이 손짓이 곧 곡의 한 구간이 된다
    _arr?.mark(i, _arrClock.elapsedMilliseconds / 1000);
    _refresh();
  }

  /// 받아 적기 켜고 끄기. 끌 때 구간표를 통째로 갈아 끼운다.
  void _toggleArrange() {
    final rec = _arr;
    if (rec == null) {
      // 안 틀고 넘기면 「몇 판 머물렀나」가 안 잡힌다 — 반주부터 켠다
      if (!widget.transport.playing) _play();
      _arrClock
        ..reset()
        ..start();
      final r = ArrangeRecorder()
        ..mark(widget.project.currentScene, 0); // 지금 씬부터 시작이다
      setState(() => _arr = r);
      return;
    }
    _arrClock.stop();
    final made = sectionsFrom(
      rec,
      _arrClock.elapsedMilliseconds / 1000,
      loopSecOf: (i) =>
          SceneSequencer.sceneLoopSec(widget.project, widget.transport, i),
    );
    setState(() => _arr = null);
    if (made.isEmpty) {
      _say('씬을 넘긴 기록이 없습니다');
      return;
    }
    // **되돌릴 거리를 들고 갈아 끼운다** — 곡 구성은 한 번에 제일 많이 잃는 자리다.
    final before = [...widget.project.song.sections];
    widget.project.song.restore(made);
    final sec = SceneSequencer.songSeconds(widget.project, widget.transport);
    _say(
      '${made.length}구간 · ${sec.round()}초짜리 곡이 됐습니다 — 「곡으로 잇기」에서 보세요',
      undo: () => widget.project.song.restore(before),
    );
  }

  void _say(String msg, {VoidCallback? undo}) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 12.5)),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: undo == null ? 3 : 7),
        action: undo == null
            ? null
            : SnackBarAction(label: '되돌리기', onPressed: undo),
      ),
    );
  }

  /// 돌고 있는 중에 무언가 바뀌었을 때 — **다음 판부터** 반영된다(박자는 안 끊긴다).
  ///
  /// **곡 재생(`songLoop`) 중이면 얘기가 다르다.** 곡 재생의 "한 판"은 구간을
  /// 전부 이어붙인 몇 분짜리다 — `refreshLoop` 로 갈아 끼워도 그 몇 분이 다
  /// 지나야 반영돼서, 씬을 눌러도 아무 일도 안 일어나는 것처럼 보였다(실기기
  /// 확인: "안 넘어가고 반복되던데"). 그때는 다음 판을 기다리지 않고 그 자리에서
  /// 새 씬 루프로 바로 갈아탄다.
  void _refresh() {
    final host = widget.host;
    if (host == null || !widget.transport.playing) return;
    if (widget.transport.songLoop) {
      _play();
      return;
    }
    _show(SceneSequencer.refreshLoop(widget.project, widget.transport, host));
  }

  void _show(SceneBuild b) {
    if (!mounted) return;
    setState(() {
      _bars = b.loopBars;
      _loopSec = b.loopSec;
      // 변형을 켜면 루프가 **여러 바퀴**를 한 판으로 돈다(계획 6-1) —
      // 음·타격 수는 그 전체 값이므로 한 바퀴 값으로 나눠서 보여 준다.
      // 안 그러면 「4마디에 타격 245개」처럼 읽힌다(실제로는 네 바퀴 몫이다).
      final turns = b.loopSec > 0
          ? (b.totalSec / b.loopSec).round().clamp(1, 64)
          : 1;
      _info =
          '한 판 ${b.loopBars}마디 · ${b.loopSec.toStringAsFixed(1)}초 · '
          '음 ${b.notes.length ~/ turns}개 · 타격 ${b.drums.length ~/ turns}개 · '
          '${turns > 1 ? '$turns바퀴마다 변화 · ' : ''}무한 반복';
    });
  }

  void _stop() {
    widget.host?.allOff();
    widget.host?.setSongMode(false);
    _debounce?.cancel();
    widget.transport.playing = false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Transport(
          transport: widget.transport,
          info: _info,
          onPlay: _play,
          onStop: _stop,
        ),
        _SceneBar(
          project: widget.project,
          transport: widget.transport,
          host: widget.host,
          loopSec: _loopSec,
          bpm: widget.transport.bpm,
          onLaunch: _launch,
          onChanged: _refresh,
          recording: _arr != null,
          recCount: _arr?.count ?? 0,
          onRecord: _toggleArrange,
        ),
        // 재생 위치 — **자기 위젯**이다. 지표가 250ms 마다 오는데 이걸 화면 전체
        // setState 로 받으면 초당 4번씩 트랙 줄까지 다 다시 그린다(4단계에서 EQ 가
        // 느렸던 것과 같은 병).
        _PlayHead(host: widget.host, bars: _bars, loopSec: _loopSec),
        Expanded(
          child: AnimatedBuilder(
            animation: widget.project,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              children: [
                // 트랙은 있는데 **패턴이 하나도 없으면 재생해도 무음**이다.
                // 초보에게는 '고장' 으로 보인다 — 그 자리에서 알려 준다.
                if (widget.project.tracks.isNotEmpty &&
                    widget.project.tracks.every((t) => t.pattern == null))
                  const _SilentHint(),
                for (final t in widget.project.tracks)
                  _TrackRow(
                    key: ValueKey(t.id),
                    track: t,
                    project: widget.project,
                    transport: widget.transport,
                    host: widget.host,
                    simple: widget.simple,
                    pro: widget.pro,
                    onChanged: _refresh,
                  ),
                _AddRow(
                  onAdd: (type, voice) =>
                      widget.project.addTrack(type, voice: voice),
                ),
                // 「두드려서 채우기」 — **이 씬의 바닥(드럼·베이스·화음)을
                // 손으로 쳐서 깐다.** 홈 화면의 "두드려서 만들기"가 첫 씬을
                // 만드는 입구라면, 이쪽은 **씬마다** 쓰는 입구다(사용자 결정,
                // 2026-09-21: "씬마다 두들플레이로 만드는 거야").
                const SizedBox(height: 8),
                _DoodleFillButton(
                  project: widget.project,
                  transport: widget.transport,
                  host: widget.host,
                  onDone: _refresh,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 「두드려서 채우기」 — 이 씬을 두들플레이로 채운다.
class _DoodleFillButton extends StatelessWidget {
  final Project project;
  final Transport transport;
  final AudioClient? host;
  final VoidCallback onDone;
  const _DoodleFillButton({
    required this.project,
    required this.transport,
    required this.host,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () async {
        await openDoodlePlay(
          context,
          project: project,
          transport: transport,
          host: host,
        );
        onDone();
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        side: BorderSide(color: Colors.tealAccent.withValues(alpha: 0.5)),
      ),
      icon: const Text('👆', style: TextStyle(fontSize: 15)),
      label: const Text(
        '두드려서 채우기 — 이 씬의 드럼·베이스·코드',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// 씬 전체가 '없음' 일 때 뜨는 한 줄. 무엇을 눌러야 소리가 나는지까지 적는다.
class _SilentHint extends StatelessWidget {
  const _SilentHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.volume_off, size: 18, color: Colors.amber.shade200),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '이 씬은 아직 아무 소리도 안 납니다.\n'
              '아래 「패턴」을 눌러 하나 고르면 소리가 나요.',
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Colors.amber.shade100,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════ 위쪽 — 재생·템포·조 ══════════════════

class _Transport extends StatelessWidget {
  final Transport transport;
  final String info;
  final VoidCallback onPlay, onStop;

  const _Transport({
    required this.transport,
    required this.info,
    required this.onPlay,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    // 가로로 누우면 높이가 귀하다 — 세 줄을 한 줄로 붙인다.
    // 안 그러면 위쪽 설정이 화면의 3/4 를 먹고 트랙이 두 줄밖에 안 보인다
    // (그림으로 뽑아 보고 잡았다). **만들기 화면의 주인공은 트랙이다.**
    return AnimatedBuilder(
      animation: transport,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white12)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 108,
                    height: 44,
                    child: FilledButton.icon(
                      onPressed: transport.playing ? onStop : onPlay,
                      icon: Icon(
                        transport.playing ? Icons.stop : Icons.play_arrow,
                        size: 20,
                      ),
                      label: Text(
                        transport.playing ? '정지' : '재생',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: transport.playing
                            ? Colors.red.shade700
                            : Colors.teal.shade600,
                        foregroundColor:
                            Colors.white, // 안 잡으면 테마 기본색(보라)이라 안 읽힌다
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    // 빠르기는 이제 톱니바퀴의 「프로젝트 설정」에서 만진다 —
                    // 여기서는 지금 값만 본다(건드릴 손잡이는 없다).
                    child: Row(
                      children: [
                        const Text(
                          '빠르기',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white38,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${transport.bpm.round()} BPM',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // 스타일·조·느낌은 이제 이 화면에 없다(작업 화면 위쪽 톱니바퀴의
              // 「프로젝트 설정」으로 옮겼다) — 재생·빠르기만 남아 그 아래
              // 안내 한 줄만 있으면 된다.
              if (!transport.playing)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    '▶ 를 누르면 멈출 때까지 반복합니다',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, color: Colors.white24),
                  ),
                ),
              if (info.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      info,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: Colors.white38,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ══════════════════ 씬 고르기 ══════════════════

/// 씬 칩 줄 — 탭하면 그 씬으로 갈아탄다(재생 중이면 다음 판부터), 길게 누르면 손질.
///
/// 웹처럼 트랙×씬 **격자**로 그리면 폰 세로에서 칸이 40dp 도 안 나온다. 그래서
/// "지금 씬" 하나만 아래 트랙 목록으로 펴 놓고, 씬은 칩으로 골라 타는 모양으로 폈다.
class _SceneBar extends StatelessWidget {
  final Project project;
  final Transport transport;

  /// 씬 칩에 붙은 캐릭터를 **박자에 맞춰** 움직이게 할 재료.
  final AudioClient? host;
  final double loopSec;
  final double bpm;
  final ValueChanged<int> onLaunch;

  /// 씬 **목록을 건드린 뒤** 돌고 있는 루프를 다시 보내는 통로.
  ///
  /// 지금 씬을 지우면 `removeScene` 이 트랙 패턴을 남은 씬 것으로 바꾸는데,
  /// 엔진에는 아무 말도 안 갔다 — **화면만 바뀌고 스피커에서는 지운 씬이 계속
  /// 돌았다.** 씬을 고르는 `onLaunch` 는 `_refresh` 를 부르는데 지우는 쪽만 빠져
  /// 있었다(짝이 하나 없는 그 모양이다).
  final VoidCallback onChanged;

  /// **연주해서 곡 만들기** — 씬을 넘긴 순서가 그대로 구간표가 된다.
  final bool recording;
  final int recCount;
  final VoidCallback onRecord;
  const _SceneBar({
    required this.project,
    required this.transport,
    required this.host,
    required this.loopSec,
    required this.bpm,
    required this.onLaunch,
    required this.onChanged,
    required this.recording,
    required this.recCount,
    required this.onRecord,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: project,
      builder: (context, _) => Container(
        // 52 − 위아래 5 = 칩 높이 42. 예전엔 46 − 5 = 36 이었다.
        height: scaled(context, 52),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white12)),
        ),
        child: Row(
          children: [
            // **연주해서 곡 만들기.** 켜고 씬을 넘기면 그 순서가 구간표가 된다.
            // 씬 줄 바로 옆이라야 뜻이 통한다 — 여기서 하는 일이 곧 그것이다.
            GestureDetector(
              onTap: onRecord,
              child: Container(
                height: 34, // 손가락 바닥선
                padding: const EdgeInsets.symmetric(horizontal: 10),
                margin: const EdgeInsets.only(right: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: recording
                      ? Colors.red.shade600
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      recording ? Icons.stop : Icons.fiber_manual_record,
                      size: 13,
                      color: recording ? Colors.white : Colors.red.shade300,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      recording ? '곡으로 ($recCount)' : '연주 녹음',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: recording ? Colors.white : Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < project.scenes.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 5),
                      child: GestureDetector(
                        onTap: () => onLaunch(i),
                        onLongPress: () => _edit(context, i),
                        child: Container(
                          alignment: Alignment.center,
                          padding: EdgeInsets.only(
                            left: 12,
                            right: i == project.currentScene ? 7 : 12,
                          ),
                          decoration: BoxDecoration(
                            color: i == project.currentScene
                                ? Colors.indigo.shade400
                                : Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          // 이름 바꾸기·복제·삭제가 **길게 누르기에만** 있었다.
                          // 곡 목록에서 이미 겪은 것과 같은 문제다 —
                          // 「있는 줄도 모르니 씬 이름이 전부 "씬 2" 로 남는다」.
                          // 지금 씬에만 ⋮ 를 붙인다: 하나만 나오니 안 어지럽고,
                          // **어느 씬에 대한 메뉴인지**도 그 자리에서 보인다.
                          // 길게 누르기는 그대로 둔다(이미 익힌 사람이 있다).
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // **지금 씬만 춤춘다.** 다 움직이면 어느 것이
                              // 소리 나는지 오히려 안 보이고, 씬 수만큼 시계가
                              // 돈다(멈춘 것은 그릴 값이 안 바뀐다).
                              if ((project.scenes[i].critter ?? '').isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(right: 5),
                                  child: i == project.currentScene
                                      ? CritterBeat(
                                          host: host,
                                          loopSec: loopSec,
                                          bpm: bpm,
                                          value: project.scenes[i].critter!,
                                          size: 26,
                                          color: Colors.white,
                                        )
                                      : CritterIcon(
                                          value: project.scenes[i].critter!,
                                          size: 26,
                                          color: Colors.white54,
                                        ),
                                ),
                              Text(
                                project.scenes[i].name,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: i == project.currentScene
                                      ? FontWeight.w800
                                      : FontWeight.w400,
                                  color: i == project.currentScene
                                      ? Colors.white
                                      : Colors.white60,
                                ),
                              ),
                              if (i == project.currentScene)
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _edit(context, i),
                                  // **18×15 였다.** 보이는 점 셋은 그대로 두고
                                  // 눌리는 자리만 칩 높이만큼 넓힌다 — 이만한 것을
                                  // 두 번 세 번 눌러야 하면 있으나 마나다.
                                  child: const SizedBox(
                                    width: 34,
                                    height: double.infinity,
                                    child: Icon(
                                      Icons.more_vert,
                                      size: 15,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  GestureDetector(
                    onTap: project.addScene,
                    child: Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Text(
                        '＋',
                        style: TextStyle(fontSize: 14, color: Colors.white54),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _edit(BuildContext context, int i) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        // 줄이 다섯이 됐다. 작은 폰에서 글자를 키우면 서랍이 정해진 높이
        // (화면의 9/16)를 넘는다 — 넘치면 노란 줄무늬만 뜨고 아래 줄은 못 누른다.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit, size: 20),
                title: Text(
                  '"${project.scenes[i].name}" 이름 바꾸기',
                  style: const TextStyle(fontSize: 14),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _rename(context, i);
                },
              ),
              ListTile(
                leading: SizedBox(
                  width: 20,
                  height: 26,
                  child: (project.scenes[i].critter ?? '').isEmpty
                      ? const Icon(Icons.face_retouching_off, size: 20)
                      : CritterIcon(
                          value: project.scenes[i].critter!,
                          size: 26,
                          color: Colors.white70,
                        ),
                ),
                title: Text(
                  '캐릭터 — ${critterName(project.scenes[i].critter)}',
                  style: const TextStyle(fontSize: 14),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  showCritterSheet(
                    context,
                    value: project.scenes[i].critter,
                    onPick: (v) => project.setSceneCritter(i, v),
                  );
                },
              ),
              // **지금 씬에만** 낸다 — 코드 진행은 지금 실려 있는 패턴을 고치는
              // 일이라, 딴 씬을 길게 눌러 열었을 때 내면 엉뚱한 씬을 고친다.
              if (i == project.currentScene)
                ListTile(
                  leading: const Icon(Icons.piano, size: 20),
                  title: Text(
                    '코드 진행 — ${project.readSceneProg().$1.length}자리',
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: const Text(
                    '코드를 바꾸면 베이스·멜로디도 같이 옮겨집니다',
                    style: TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    showProgSheet(
                      context,
                      project: project,
                      transport: transport,
                      host: host,
                      onChanged: onChanged,
                    );
                  },
                ),
              ListTile(
                leading: const Icon(Icons.copy, size: 20),
                title: const Text('복제', style: TextStyle(fontSize: 14)),
                onTap: () {
                  project.duplicateScene(i);
                  Navigator.pop(ctx);
                },
              ),
              if (project.scenes.length > 1)
                ListTile(
                  leading: Icon(
                    Icons.delete_outline,
                    size: 20,
                    color: Colors.red.shade300,
                  ),
                  title: Text(
                    '삭제',
                    style: TextStyle(fontSize: 14, color: Colors.red.shade300),
                  ),
                  // 씬 하나에 트랙 전부의 패턴이 들어 있고, **그 씬을 쓰던 곡 구간까지
                  // 같이 지워진다.** 확인 창 대신 되돌리기를 준다 —
                  // 곡 목록의 삭제와 같은 방식으로 맞춘다(둘이 다르면 그게 더 헷갈린다).
                  onTap: () {
                    final messenger = ScaffoldMessenger.of(context);
                    final name = project.scenes[i].name;
                    final gone = project.removeScene(i);
                    Navigator.pop(ctx);
                    if (gone == null) return;
                    onChanged(); // 다음 판부터 남은 씬 소리로 — 안 부르면 지운 씬이 계속 돈다
                    final lost =
                        gone.sections.length - project.song.sections.length;
                    messenger.clearSnackBars();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          lost > 0
                              ? '「$name」 을 지웠습니다 · 곡에서 $lost군데도 같이 빠졌어요'
                              : '「$name」 을 지웠습니다',
                        ),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 6),
                        action: SnackBarAction(
                          label: '되돌리기',
                          onPressed: () {
                            project.undoRemoveScene(gone);
                            onChanged();
                          },
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context, int i) async {
    final ctl = TextEditingController(text: project.scenes[i].name);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1E),
        title: const Text('씬 이름', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          onSubmitted: (s) => Navigator.pop(ctx, s),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (v != null && v.trim().isNotEmpty) project.renameScene(i, v.trim());
  }
}

// ══════════════════ 재생 위치 ══════════════════

/// 지금 몇 마디 몇 박인지 — 오디오가 알려 주는 **들리는 지점** 기준.
/// 이어 그리기는 [LoopPosBuilder] 가 한다(곡 화면도 같은 걸 쓴다).
class _PlayHead extends StatelessWidget {
  final AudioClient? host;
  final int bars;
  final double loopSec;
  const _PlayHead({
    required this.host,
    required this.bars,
    required this.loopSec,
  });

  @override
  Widget build(BuildContext context) {
    final n = bars < 1 ? 1 : bars;
    return SizedBox(
      // 글자를 키우면 「한 판 4마디」가 두 줄이 되어 34 안에서 잘렸다
      height: scaled(context, 34),
      child: LoopPosBuilder(
        host: host,
        loopSec: loopSec,
        builder: (context, pos, looping) {
          final bar = (pos * n).floor().clamp(0, n - 1);
          final beat = ((pos * n * 4).floor() % 4) + 1;
          return Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
            child: Row(
              children: [
                SizedBox(
                  width: scaled(context, 78),
                  child: Text(
                    looping ? '${bar + 1}마디 $beat박' : '한 판 $n마디',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: looping ? Colors.teal.shade200 : Colors.white24,
                    ),
                  ),
                ),
                for (var i = 0; i < n; i++)
                  Expanded(
                    child: Container(
                      height: 18,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: looping && i == bar
                            ? Colors.teal.shade400
                            : Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      // 멈춰 있을 때 빈 칸 넷만 있으면 이게 뭔지 알 수 없다 →
                      // **마디 번호**를 넣는다. 돌기 시작하면 번호 대신 채워지는 막대가 된다.
                      child: !(looping && i == bar)
                          ? Center(
                              child: Text(
                                '${i + 1}',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white.withValues(alpha: 0.28),
                                ),
                              ),
                            )
                          : FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: ((pos * n) - bar).clamp(0.0, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.teal.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ══════════════════ 트랙 한 줄 ══════════════════

class _TrackRow extends StatelessWidget {
  final Track track;
  final Project project;
  final Transport transport;
  final AudioClient? host;
  final VoidCallback onChanged;

  /// 간단히 보기면 **음 편집기 버튼을 감춘다**. 음을 하나씩 찍는 건 한 단계 깊은
  /// 일이다 — 음색과 패턴을 고르는 것만으로도 곡이 된다(Phase 2).
  final bool simple;

  /// 프로 모드 — 편집기로 그대로 넘긴다.
  final bool pro;
  const _TrackRow({
    super.key,
    required this.track,
    required this.project,
    required this.transport,
    required this.host,
    required this.simple,
    required this.pro,
    required this.onChanged,
  });

  String _voiceLabel() => track.type == 'drum'
      ? (DRUM_KITS[track.kit]?.label ?? track.kit)
      : (VOICE_LABEL[track.voice] ?? track.voice);

  /// 음 편집기를 연다 — 연필 아이콘과 패턴 시트의 "직접 그리기" 둘 다 여기로 온다.
  Future<void> _openEditor(BuildContext context) => Navigator.of(context)
      .push(
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: Text('${track.name} 편집')),
            body: SafeArea(
              top: false,
              child: EditorView(
                project: project,
                transport: transport,
                track: track,
                host: host,
                pro: pro,
              ),
            ),
          ),
        ),
      )
      .then((_) => onChanged());

  /// 「쉬기」 — 지금 실린 패턴이 빠진다. **무엇이 빠지는지 이름을 대고 묻는다.**
  /// 예전엔 확인도 없이 바로 빠졌다. 되돌릴 수는 있지만(패턴을 다시 고르면 된다)
  /// 무엇이 실려 있었는지 **기억하고 있어야** 한다 — 그게 사실상 되돌리기 없음이다.
  void _confirmRest(BuildContext ctx) {
    final cur = track.pattern;
    if (cur == null) return; // 이미 쉬는 중이면 물어볼 게 없다
    showDialog<void>(
      context: ctx,
      builder: (d) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D22),
        title: Text(
          '「${track.name}」 을 쉬게 할까요?',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: Text(
          '지금 실린 「${patternShort(cur)}」 이 빠집니다.\n'
          '「패턴」을 눌러 언제든 다시 고를 수 있어요.',
          style: const TextStyle(fontSize: 13, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('취소', style: TextStyle(fontSize: 14)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(d);
              project.setClip(track, null);
              onChanged();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.teal.shade600,
              foregroundColor: Colors.white,
            ),
            child: const Text(
              '쉬기',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: track,
      builder: (context, _) {
        final c = _typeColor[track.type] ?? Colors.grey;
        final off = track.pattern == null || !project.audible(track);
        return Opacity(
          opacity: off ? 0.5 : 1,
          child: Container(
            // 글자를 키운 폰에서는 칸도 같이 커진다
            height: scaled(context, 64),
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: c.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: scaled(context, 62),
                  color: c.withValues(alpha: 0.9),
                ),
                // 이름 — 탭하면 바꾼다
                SizedBox(
                  // 92 로 줄였다 — 예전 104 에서는 음색 칸이 좁아 「신스 ⋯」 로
                  // 잘렸다(그림으로 뽑아 보고 잡았다). 트랙 이름은 두 글자~네 글자다.
                  width: 92,
                  child: InkWell(
                    onTap: () => _rename(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Row(
                            children: [
                              Icon(
                                kTrackTypeIcon[track.type] ?? Icons.music_note,
                                size: 10,
                                color: Colors.white30,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                kTrackTypeLabel[track.type] ?? track.type,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white30,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // 음색(또는 키트)
                Expanded(
                  flex: 4,
                  child: _Field(
                    label: track.type == 'drum' ? '키트' : '음색',
                    value: _voiceLabel(),
                    color: c,
                    onTap: () => _pickVoice(context),
                  ),
                ),
                // 패턴
                Expanded(
                  flex: 5,
                  child: _Field(
                    label: '패턴',
                    // 이름은 키라서 못 바꾼다 — **보여 줄 때만** 한국어로 옮긴다
                    // **「비어 있음」을 앞에 둔다** — 뒤에 붙이면 이름이 길 때 잘려서
                    // 정작 알아야 할 말이 안 보인다.
                    value: track.pattern == null
                        ? '없음 (안 침)'
                        : (project.isSilent(track)
                              ? '비어 있음 · ${patternShort(track.pattern!)}'
                              : patternShort(track.pattern!)),
                    color: c,
                    // 이름은 붙어 있는데 **안이 빈** 판. 그냥 두면 "왜 안 들리지"가 된다.
                    warn: track.pattern != null && project.isSilent(track),
                    onTap: () => _pickPattern(context),
                  ),
                ),
                // 패턴이 '없음' 이어도 **눌리게 둔다** — 빈 판에서 직접 그리는 것도
                // 하나의 만드는 방법이다. (예전엔 `onPressed: null` 이라 눌러도 아무
                // 일이 안 났다. 화면상 거의 같아 보여서 고장으로 보인다.)
                // 편집기가 들어가는 순간 `makeEditable` 로 빈 2마디를 만들어 준다.
                //
                // 간단히 보기에서는 **감춘다** — 음을 하나씩 찍는 건 한 단계 깊은
                // 일이다. 음색과 패턴을 고르는 것만으로도 곡이 된다(Phase 2).
                if (!simple)
                  IconButton(
                    onPressed: () => _openEditor(context),
                    tooltip: track.pattern == null ? '빈 판에 직접 음 찍기' : '음 찍기',
                    iconSize: 18,
                    color: Colors.white54,
                    icon: const Icon(Icons.edit_note),
                  ),
                IconButton(
                  // 확인 없이 바로 빠졌다 — 무엇이 빠졌는지도 안 알려 줬다.
                  // 되돌릴 수는 있지만(패턴을 다시 고르면 된다) **무엇이 실려
                  // 있었는지 기억해야** 한다. 그래서 이름을 대고 묻는다.
                  onPressed: () => _confirmRest(context),
                  tooltip: '이 트랙 쉬기',
                  iconSize: 18,
                  color: track.pattern == null ? c : Colors.white24,
                  icon: const Icon(Icons.do_not_disturb_on_outlined),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _rename(BuildContext context) async {
    final ctl = TextEditingController(text: track.name);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1E),
        title: const Text('트랙 이름', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          onSubmitted: (s) => Navigator.pop(ctx, s),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (v != null && v.trim().isNotEmpty) track.rename(v.trim());
  }

  Future<void> _pickVoice(BuildContext context) async {
    final drum = track.type == 'drum';
    final items = drum ? DRUM_KIT_ORDER : ALL_VOICES;
    final label = drum
        ? (String k) => DRUM_KITS[k]?.label ?? k
        : (String v) => VOICE_LABEL[v] ?? v;
    final cur = drum ? track.kit : track.voice;
    final picked = await pickFromSheet(
      context,
      title: drum ? '드럼 키트' : '악기',
      subtitle: '고르면 다음 ▶ 재생부터 이 소리로 칩니다.',
      items: items,
      label: label,
      current: cur,
      color: _typeColor[track.type] ?? Colors.teal,
      groups: drum ? null : kVoiceFamily,
    );
    if (picked == null) return;
    if (drum) {
      project.setKit(track, picked); // 키트는 씬에도 남는다(씬마다 키트가 다르다)
    } else {
      track.voice = picked;
    }
    onChanged(); // 돌고 있으면 다음 판부터 이 소리로
  }

  Future<void> _pickPattern(BuildContext context) async {
    final names = SceneSequencer.patternNamesFor(project, track.type);
    // 4/4 가 아니면 **왜 목록이 줄었는지** 한 줄 적어 준다 — 안 그러면
    // 「아까 그 판이 왜 없어졌지」가 된다(5단계 47/N).
    final m = project.meterDef;
    final meterHint = m.isFour
        ? null
        : '${m.feel.split(' — ').first} 곡이라 그 박자의 판만 보여요.';
    final picked = await pickPatternSheet(
      context,
      title: '${kTrackTypeLabel[track.type] ?? track.type} 패턴',
      names: names,
      current: track.pattern,
      color: _typeColor[track.type] ?? Colors.teal,
      genre: project.genre,
      isMine: project.isMine,
      meterHint: meterHint,
    );
    if (picked == kDrawPatternSentinel) {
      if (!context.mounted) return;
      await _openEditor(context);
    } else if (picked != null) {
      project.setClip(track, picked); // 트랙과 **지금 씬** 양쪽에 쓴다
      onChanged();
    }
  }
}

class _Field extends StatelessWidget {
  final String label, value;
  final Color color;
  final VoidCallback onTap;

  /// 켜면 칸이 노랗게 테두리 진다 — **여기 뭔가 잘못됐다**는 표시.
  final bool warn;
  const _Field({
    required this.label,
    required this.value,
    required this.color,
    required this.onTap,
    this.warn = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: warn ? const Color(0x22FFC107) : Colors.white10,
            borderRadius: BorderRadius.circular(7),
            border: warn
                ? Border.all(color: const Color(0xFFFFC107), width: 1.2)
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 라벨을 늘리면 **두 줄이 되어 칸이 넘친다**(시험에서 10px 넘침).
              // 라벨은 그대로 두고 색만 바꾼다 — 알림은 값 줄 앞머리에 붙인다.
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  color: warn ? const Color(0xFFFFC107) : Colors.white38,
                ),
              ),
              // **두 줄까지 쓴다.** 한 줄로 못 박았더니 「먼지낀 건반 코…」 「업라이트 …」
              // 처럼 정작 알아야 할 뒷부분이 잘렸다(폰에서 확인).
              // 칸을 넓히는 건 한계가 있다 — 줄이 하나뿐인 화면이 아니다.
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddRow extends StatelessWidget {
  final void Function(String type, String? voice) onAdd;
  const _AddRow({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // 56 − 위아래 여백 6 = 버튼 높이 44. 손가락 끝이 대략 8~10mm 다.
      height: scaled(context, 56),
      child: OutlinedButton.icon(
        onPressed: () => _pick(context),
        icon: const Icon(Icons.add, size: 18),
        label: const Text(
          '악기 추가',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white70,
          side: const BorderSide(color: Colors.white24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
    );
  }

  /// 악기를 고르면 **종류가 따라온다.**
  ///
  /// 여태는 「드럼·베이스·코드·멜로디」 넷 중 하나를 먼저 고르게 했다. 그건 이 앱의
  /// 속사정이지 사람이 아는 말이 아니다 — 기타를 넣고 싶은 사람이 「코드인가
  /// 멜로디인가」부터 답해야 했다. 여기서는 악기 이름만 보여 준다.
  void _pick(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '악기 추가',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              const Text(
                '고르면 그 악기에 맞는 판이 같이 들어옵니다.',
                style: TextStyle(fontSize: 11.5, color: Colors.white54),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                // 가로로 누운 폰에서도 서랍이 화면을 안 넘게 한다.
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.55,
                ),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final (voice, label, type) in kInstrumentPicks)
                        GestureDetector(
                          onTap: () {
                            Navigator.pop(ctx);
                            onAdd(type, voice.isEmpty ? null : voice);
                          },
                          child: Container(
                            width: 86,
                            height: 56, // 손가락 바닥선
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: (_typeColor[type] ?? Colors.teal)
                                  .withValues(alpha: 0.20),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: (_typeColor[type] ?? Colors.teal)
                                    .withValues(alpha: 0.55),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  kTrackTypeLabel[type] ?? type,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    color: Colors.white38,
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
            ],
          ),
        ),
      ),
    );
  }
}

/// [pickPatternSheet] 이 이 값을 돌려주면 "직접 그리기" 를 골랐다는 뜻 —
/// 패턴을 싣는 대신 음 편집기를 열어야 한다.
const kDrawPatternSentinel = '__draw__';

Future<String?> pickPatternSheet(
  BuildContext context, {
  required String title,
  required List<String> names,
  required String? current,
  required Color color,
  required String genre,
  required bool Function(String?) isMine,
  // 5단계 47/N — 왈츠·흔들발라드가 생기면서 이 목록이 **박자로도 걸러진다**
  // (`SceneSequencer.patternNamesFor`). 아무 말도 안 하면 「아까 그 판이 왜
  // 없어졌지」가 된다 — null 이면(4/4) 여태처럼 아무 말도 안 붙인다.
  String? meterHint,
  // 씬 화면에서만 켠다. 타임라인 레인은 "이 마디에 어느 이름난 판을 놓을까"를
  // 고르는 자리라 여기서 바로 그리기로 새면 방금 고른 자리에 놓아야 할 이름이
  // 안 붙는다 — 그 화면은 이 버튼을 뺀다.
  bool allowDraw = true,
}) {
  final mine = [
    for (final n in names)
      if (isMine(n)) n,
  ];
  final styled = [
    for (final n in names)
      if (!isMine(n) && patternIsStyle(n, genre)) n,
  ];
  final basic = [
    for (final n in names)
      if (!isMine(n) && patternIsBasic(n)) n,
  ];
  final others = [
    for (final n in names)
      if (!isMine(n) && !patternIsStyle(n, genre) && !patternIsBasic(n)) n,
  ];
  final styleLabel = songGenreOf(genre).$2;

  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF1A1A1E),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) {
        var all = false;
        return StatefulBuilder(
          builder: (ctx, setInner) => SafeArea(
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
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        // 전부 펼치기 — 다른 스타일 패턴을 섞고 싶을 때만
                        GestureDetector(
                          onTap: () => setInner(() => all = !all),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: all ? color : Colors.white10,
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Text(
                              all ? '이 스타일만' : '전부 보기',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: all ? Colors.black : Colors.white60,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      all
                          ? '스타일별로 묶어 뒀습니다.'
                          : '$styleLabel 스타일 패턴입니다 — 이 곡에 맞는 것들.',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.white38,
                      ),
                    ),
                    if (meterHint != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        meterHint,
                        style: TextStyle(fontSize: 11, color: color),
                      ),
                    ],
                    if (allowDraw) ...[
                      const SizedBox(height: 10),
                      // "음악 낙서장" 이라는 이름값 — 미리 만든 패턴만 늘어놓고
                      // 끝내지 않는다. 「간단히」 모드에서도 여기서 바로 빈 판에
                      // 직접 그리러 갈 수 있어야 한다(연필 아이콘은 그 모드에서
                      // 숨어 있다 — 이 버튼이 그 유일한 문).
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx, kDrawPatternSentinel),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: color.withValues(alpha: 0.6),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.edit_note, size: 18, color: color),
                              const SizedBox(width: 6),
                              Text(
                                '직접 그리기',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: color,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (mine.isNotEmpty)
                              _PatGroup(
                                title: '내가 고친 판',
                                items: mine,
                                current: current,
                                color: color,
                              ),
                            _PatGroup(
                              title: styleLabel,
                              items: styled,
                              current: current,
                              color: color,
                            ),
                            if (all) ...[
                              _PatGroup(
                                title: '기본',
                                items: basic,
                                current: current,
                                color: color,
                              ),
                              _PatGroup(
                                title: '다른 스타일',
                                items: others,
                                current: current,
                                color: color,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// 묶음 하나 — 제목 + 칩들. 비어 있으면 아예 안 그린다.
class _PatGroup extends StatelessWidget {
  final String title;
  final List<String> items;
  final String? current;
  final Color color;
  const _PatGroup({
    required this.title,
    required this.items,
    required this.current,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: Colors.white38,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final it in items)
                GestureDetector(
                  onTap: () => Navigator.pop(context, it),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: it == current ? color : Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      patternLabel(it),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: it == current
                            ? FontWeight.w800
                            : FontWeight.w400,
                        color: it == current ? Colors.black : Colors.white70,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 목록에서 하나 고르는 시트 — 악기·키트가 같은 모양을 쓴다.
/// [groups] 를 주면 **서랍(계열)별로 나눠** 보여 준다(`instruments.dart` 의
/// `kVoiceFamily` — "건반"·"뜯고 치는"·"관악기"… ). 24~33개를 한 줄에 늘어놓으면
/// 원하는 걸 찾으려고 계속 밀어야 한다 — 사람은 "기타 비슷한 거"를 찾지
/// 'nylon' 을 찾지 않는다. 안 주면(드럼 키트 등 계열이 없는 목록) 여태처럼 한
/// 줄로 쭉 편다.
Future<String?> pickFromSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required List<String> items,
  required String Function(String) label,
  required String? current,
  required Color color,
  Map<String, List<String>>? groups,
}) {
  Widget chip(BuildContext ctx, String it) => GestureDetector(
    onTap: () => Navigator.pop(ctx, it),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: it == current ? color : Colors.white10,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label(it),
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: it == current ? FontWeight.w800 : FontWeight.w400,
          color: it == current ? Colors.black : Colors.white70,
        ),
      ),
    ),
  );

  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF1A1A1E),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        // 가로 화면에서 시트가 화면을 다 먹지 않게 — 절반 넘으면 안쪽이 스크롤된다
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.72,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11.5, color: Colors.white38),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: groups == null
                      ? Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final it in items) chip(ctx, it),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final e in groups.entries)
                              if (e.value.any(items.contains)) ...[
                                Padding(
                                  padding: const EdgeInsets.only(
                                    top: 10,
                                    bottom: 6,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        kVoiceFamilyIcon[e.key] ??
                                            Icons.piano,
                                        size: 13,
                                        color: Colors.white54,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        e.key,
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: [
                                    for (final it in e.value)
                                      if (items.contains(it)) chip(ctx, it),
                                  ],
                                ),
                              ],
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
