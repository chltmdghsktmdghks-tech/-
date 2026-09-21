// 쇼 화면 — **남에게 보여 주는 화면** (5단계 16/N).
//
// 만든 곡을 틀어 놓고 폰을 세워 두는 자리다. 그래서 다른 화면과 반대로 만든다:
// 조작은 숨기고(화면을 누르면 잠깐 나온다), 글씨는 크게, 배경은 검게.
//
// ── 그림은 소리를 '분석'하지 않는다 ──
// 이 앱은 **악보를 갖고 있다**(`show_ops.dart` 참고). 언제 무슨 악기가 울리는지 이미
// 아니까, 프레임마다 "방금 울렸나"를 물어서 그만큼 키우면 된다. 분석보다 정확하고
// (분석은 늘 늦고 큰 소리에 작은 소리가 묻힌다) 악기별로 나눌 수 있다.
//
// ── 시간 기준 ──
// 곡 재생은 `setLoop` 에 곡 전체를 한 판으로 넣은 것이라, 루프 위치(0~1)에 곡 길이를
// 곱하면 지금 몇 초인지 나온다. `LoopClock` 이 0.25초마다 오는 값 사이를 이어 준다.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio_isolate.dart';
import '../project.dart';
import '../sequencer.dart';
import '../keep_awake.dart';
import '../show_ops.dart';
import 'critters.dart';
import 'play_head.dart';
import 'show_band.dart';

const _typeColor = {
  'drum': Color(0xFF7CB342),
  'bass': Color(0xFF42A5F5),
  'chord': Color(0xFFAB47BC),
  'melody': Color(0xFFFFA726),
};

/// 아래줄에 세울 드럼 — 이 넷이 리듬의 뼈대다(나머지는 이 넷 사이를 메운다).
///
/// 백비트 자리는 장르마다 스네어·클랩·림으로 갈린다 — 그래서 `show_ops` 가 셋을
/// 합쳐 둔 `'backbeat'` 를 읽는다. 하우스처럼 **클랩만 치는 곡**에서도 램프가 산다.
const _drumLanes = [
  ('kick', '킥'),
  ('backbeat', '스네어'),
  ('hat', '하이햇'),
  ('crash', '크래시'),
];

String mmss(double sec) {
  final t = sec.round();
  return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
}

class ShowView extends StatefulWidget {
  final Project project;
  final Transport transport;
  final AudioClient? host;
  const ShowView({
    super.key,
    required this.project,
    required this.transport,
    required this.host,
  });

  @override
  State<ShowView> createState() => _ShowViewState();
}

class _ShowViewState extends State<ShowView>
    with SingleTickerProviderStateMixin {
  final _clock = LoopClock();
  late final AnimationController _tick;
  late ShowScore _score;
  bool _chrome = true; // 조작 보이기
  bool _band = true; // 밴드 / 막대
  int _hideAt = 0;
  final _sw = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    // **씬 루프가 돌고 있는 채로 들어올 수 있다.**
    //
    // 그 루프는 눈금 한 칸이 **한 바퀴**(수 초)인데(`playLoop` 의 unitSec),
    // 이 화면은 한 칸을 **곡 전체**로 읽는다. 그대로 그리면 시간축이 통째로
    // 어긋나서 밴드가 소리와 전혀 안 맞게 번쩍이고 시간 표시가 폭주한다.
    // 들어올 때 곡 모드로 다시 걸어 준다 — 쇼는 어차피 **곡 전체**를 도는 화면이라
    // 처음부터 가는 것이 맞다(`_play` 의 켜는 갈래와 같은 순서를 쓴다).
    //
    // **단, 들어올 때 이미 곡 전체(`songLoop`)가 돌고 있었다면 다시 걸지 않는다.**
    // 예전엔 조건이 `transport.playing`뿐이라, 타임라인에서 곡을 틀어 놓고
    // 쇼 화면만 열어도(이미 songLoop=true) 매번 처음부터 재시작됐다.
    final h = widget.host;
    if (h != null && widget.transport.playing && !widget.transport.songLoop) {
      SceneSequencer.playSong(widget.project, widget.transport, h, loop: true);
      widget.transport.songLoop = true;
    }
    _score = ShowScore.from(widget.project, widget.transport);
    _tick = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _clock.attach(widget.host);
    // 쇼는 전체 화면 — 상태바·내비게이션 바가 있으면 '보여 주는 화면'이 아니다
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // 곡이 끝날 때까지 화면이 안 꺼져야 한다 — 이 화면은 세워 두는 자리다
    keepAwake(true);
    _bump();
  }

  @override
  void dispose() {
    _clock.dispose();
    _tick.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    keepAwake(false); // 나가면 원래대로 — 앱 전체에 켜 두면 배터리를 먹는다
    super.dispose();
  }

  /// 조작을 보여 주고 **재생 중일 때만** 잠시 뒤 숨긴다.
  ///
  /// 멈춰 있는데도 숨기면 ▶ 버튼이 사라진다 — 화면을 한 번 눌러야 다시 나오는데,
  /// 그걸 모르면 아무것도 못 한다(폰에서 실제로 그렇게 막혔다). 숨길 게 없을 땐 안 숨긴다.
  void _bump() {
    _chrome = true;
    _hideAt = _sw.elapsedMilliseconds + 4000;
  }

  void _play() {
    final h = widget.host;
    if (h == null) return;
    if (widget.transport.playing) {
      h.allOff();
      h.setSongMode(false);
      widget.transport.playing = false;
    } else {
      // 쇼는 **곡 전체**를 돈다(씬 한 판이 아니라). 끝나면 처음부터 다시.
      SceneSequencer.playSong(widget.project, widget.transport, h, loop: true);
      widget.transport.playing = true;
      widget.transport.songLoop = true;
      _score = ShowScore.from(widget.project, widget.transport);
    }
    setState(_bump);
  }

  /// 무대 앞에 세울 캐릭터. 곡 화면 눈금 줄과 **같은 것**을 쓴다.
  (String, double)? _mascot(double t, bool playing) => playing
      ? critterAt(
          widget.project.scenes,
          widget.project.song.sections,
          _score.spans,
          t,
          widget.transport.bpm,
        )
      : null;

  @override
  Widget build(BuildContext context) {
    final tracks = widget.project.tracks;
    return GestureDetector(
      onTap: () => setState(_bump),
      child: Container(
        color: Colors.black,
        child: AnimatedBuilder(
          animation: _tick,
          builder: (context, _) {
            final playing = widget.transport.playing;
            final t = _clock.pos(_score.total) * _score.total;
            if (_chrome && playing && _sw.elapsedMilliseconds > _hideAt) {
              _chrome = false;
            }
            final si = _score.sectionAt(t);
            final name = si >= 0 && si < _score.sectionNames.length
                ? _score.sectionNames[si]
                : '';

            return SafeArea(
              child: Column(
                children: [
                  _Header(
                    songName: widget.project.name,
                    section: name,
                    at: playing ? t : 0,
                    total: _score.total,
                    show: _chrome,
                    playing: widget.transport.playing,
                    onPlay: _play,
                    onBack: () => Navigator.of(context).maybePop(),
                    band: _band,
                    onBand: () => setState(() {
                      _band = !_band;
                      _bump();
                    }),
                  ),
                  _SectionBar(score: _score, at: t),
                  Expanded(
                    child: _band
                        ? LayoutBuilder(
                            // 무대 높이를 **여기서** 잰다. 아래 `Positioned` 안에서
                            // 재면 높이가 무한대로 와서(왼쪽·아래만 묶었으니)
                            // 「무대에 맞춘다」는 말만 남고 실제로는 늘 최대값이었다.
                            builder: (context, stage) => Stack(
                              children: [
                                Positioned.fill(
                                  child: CustomPaint(
                                    painter: BandPainter(
                                      members: [
                                        for (final tr in tracks)
                                          BandMember(
                                            name: tr.name,
                                            type: tr.type,
                                            voice: tr.voice,
                                            color:
                                                _typeColor[tr.type] ??
                                                Colors.teal,
                                            // 멈춰 있으면 전부 쉰다 — 멈춘 순간이 얼어붙어
                                            // 있으면 고장난 화면으로 보인다
                                            //
                                            // level = 서스테인 포함(빛) / hit = 타점만(움직임)
                                            level: playing
                                                ? _score.trackPulse(tr.id, t)
                                                : 0,
                                            hit: playing
                                                ? ShowScore.pulse(
                                                    _score.trackTimes[tr.id],
                                                    t,
                                                  )
                                                : 0,
                                            muted: !widget.project.audible(tr),
                                            // 음 높이 — 기타리스트 왼손이 넥 어디를 잡을지
                                            pitch: playing
                                                ? _score.pitchAt(tr.id, t)
                                                : 0.5,
                                          ),
                                      ],
                                      kick: playing
                                          ? _score.drumPulse('kick', t)
                                          : 0,
                                      snare: playing
                                          ? _score.drumPulse('backbeat', t)
                                          : 0,
                                      hat: playing
                                          ? _score.drumPulse('hat', t)
                                          : 0,
                                      crash: playing
                                          ? _score.drumPulse(
                                              'crash',
                                              t,
                                              decay: 0.6,
                                            )
                                          : 0,
                                      // 스틱 높이는 세기가 아니라 **다음 박까지의 진행도**로
                                      // 정한다(5단계 53/N) — 안 그러면 박 사이에 팔이 멈춘다
                                      snarePhase: playing
                                          ? _score.strokePhase('backbeat', t)
                                          : -1,
                                      hatPhase: playing
                                          ? _score.strokePhase('hat', t)
                                          : -1,
                                      playing: playing,
                                      sway:
                                          (_sw.elapsedMilliseconds % 6000) /
                                          6000,
                                      // 스타일마다 무대 조명 색이 다르다 — 곡이 바뀌면
                                      // 화면 분위기도 같이 바뀌어야 쇼가 된다
                                      lights:
                                          kStageLights[widget.project.genre] ??
                                          kStageLights['lofi']!,
                                      // 구간이 바뀌면 무대가 한 번 환해진다(0.7초)
                                      flash: playing
                                          ? _score.sectionPulse(t, 0.7)
                                          : 0,
                                      // 구간 성격에 따라 무대가 달아오른다 (계획 8) —
                                      // 드롭은 터지고, 브레이크는 죽고, 빌드업은 차오른다.
                                      // 멈춰 있으면 보통값(0.55) 으로 둔다.
                                      energy: playing
                                          ? _score.energyAt(t)
                                          : 0.55,
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                                // **무대 앞의 캐릭터** — 지금 흐르는 구간의 씬에
                                // 붙여 둔 것이 나와서 박자에 맞춰 춤춘다.
                                // 밴드는 「누가 연주하나」를 말하고, 이쪽은 「지금
                                // 어느 대목인가」를 말한다(구간이 바뀌면 얘가 바뀐다).
                                if (_mascot(t, playing) case (
                                  final v,
                                  final beat,
                                ))
                                  // **관객석**에 세운다. 무대 위(연주자 줄)에 두면
                                  // 악기 이름표를 가리고, 밴드 한 명처럼 보인다 —
                                  // 얘는 연주자가 아니라 「지금 어느 대목인가」다.
                                  Positioned(
                                    left: 10,
                                    bottom: 0,
                                    child: CritterIcon(
                                      value: v,
                                      // 가로로 누우면 무대가 얕다 — 고정 크기면
                                      // 관객석을 넘어 이름표를 덮는다.
                                      size: (stage.maxHeight * 0.13).clamp(
                                        30.0,
                                        80.0,
                                      ),
                                      beat: beat,
                                      color: Colors.white70,
                                    ),
                                  ),
                              ],
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (final tr in tracks)
                                  if (tr.type != 'drum')
                                    Expanded(
                                      child: _Player(
                                        label: tr.name,
                                        color:
                                            _typeColor[tr.type] ?? Colors.teal,
                                        level: playing
                                            ? _score.trackPulse(tr.id, t)
                                            : 0,
                                        muted: !widget.project.audible(tr),
                                      ),
                                    ),
                              ],
                            ),
                          ),
                  ),
                  if (!_band) _DrumRow(score: _score, at: playing ? t : -1),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 악기 하나 — 소리가 날 때마다 기둥이 솟는다.
class _Player extends StatelessWidget {
  final String label;
  final Color color;
  final double level;
  final bool muted;
  const _Player({
    required this.label,
    required this.color,
    required this.level,
    required this.muted,
  });

  @override
  Widget build(BuildContext context) {
    final v = muted ? 0.0 : level;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                // 최소 높이를 남긴다 — 안 울릴 때 사라지면 **몇 명이 연주 중인지**가 안 보인다
                final h = c.maxHeight * (0.12 + 0.88 * v);
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    height: h,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.25 + 0.75 * v),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: v > 0.05
                          ? [
                              BoxShadow(
                                color: color.withValues(alpha: 0.5 * v),
                                blurRadius: 24 * v,
                                spreadRadius: 2 * v,
                              ),
                            ]
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: muted ? Colors.white24 : Colors.white54,
            ),
          ),
        ],
      ),
    );
  }
}

/// 드럼 — 타격이라 기둥보다 **점멸**이 맞는다.
class _DrumRow extends StatelessWidget {
  final ShowScore score;
  final double at;
  const _DrumRow({required this.score, required this.at});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 74,
      child: Row(
        children: [
          for (final (lane, label) in _drumLanes)
            Expanded(
              child: Builder(
                builder: (context) {
                  final v = score.drumPulse(lane, at);
                  final c = _typeColor['drum']!;
                  return Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 30 + 22 * v,
                          height: 30 + 22 * v,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.withValues(alpha: 0.15 + 0.85 * v),
                            boxShadow: v > 0.05
                                ? [
                                    BoxShadow(
                                      color: c.withValues(alpha: 0.6 * v),
                                      blurRadius: 26 * v,
                                    ),
                                  ]
                                : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 9.5,
                            color: Colors.white38,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// 구간 띠 — 지금 곡의 어디쯤인지. 구간 이름이 보여야 "지금 코러스구나"가 된다.
class _SectionBar extends StatelessWidget {
  final ShowScore score;
  final double at;
  const _SectionBar({required this.score, required this.at});

  @override
  Widget build(BuildContext context) {
    final total = score.total <= 0 ? 1.0 : score.total;
    final cur = score.sectionAt(at);
    return SizedBox(
      height: 26,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            for (var i = 0; i < score.spans.length; i++)
              Expanded(
                flex: ((score.spans[i].$2 / total) * 1000).round().clamp(
                  1,
                  100000,
                ),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: i == cur
                        ? Colors.tealAccent.shade400
                        : Colors.white12,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    i < score.sectionNames.length ? score.sectionNames[i] : '',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: i == cur ? Colors.black87 : Colors.white38,
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

class _Header extends StatelessWidget {
  final String songName, section;
  final double at, total;
  final bool show, playing, band;
  final VoidCallback onPlay, onBack, onBand;
  const _Header({
    required this.songName,
    required this.section,
    required this.at,
    required this.total,
    required this.show,
    required this.playing,
    required this.onPlay,
    required this.onBack,
    required this.band,
    required this.onBand,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          // 조작은 숨는다 — 자리는 남겨 둔다(사라졌다 나타나면 글씨가 움직인다)
          AnimatedOpacity(
            opacity: show ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            child: Row(
              children: [
                IconButton(
                  onPressed: show ? onBack : null,
                  icon: const Icon(Icons.arrow_back, color: Colors.white70),
                ),
                IconButton(
                  onPressed: show ? onPlay : null,
                  icon: Icon(
                    playing ? Icons.stop_circle : Icons.play_circle,
                    size: 34,
                    color: Colors.tealAccent.shade400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.isEmpty ? songName : section,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                Text(
                  songName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ],
            ),
          ),
          // 작은 폰에서 글자를 키우면 「0:12 / 2:15」가 줄을 넘겼다.
          // 시각은 줄임표(…)로 자르면 뜻이 없어지므로 **줄여서** 보여 준다.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${mmss(at)} / ${mmss(total)}',
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white54,
                ),
              ),
            ),
          ),
          AnimatedOpacity(
            opacity: show ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            child: IconButton(
              tooltip: band ? '막대로 보기' : '밴드로 보기',
              onPressed: show ? onBand : null,
              icon: Icon(
                band ? Icons.bar_chart : Icons.groups,
                size: 22,
                color: Colors.white54,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
