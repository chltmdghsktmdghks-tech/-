// 「두드려 넣기」 화면 (5단계 46/N).
//
// 무엇을 어느 칸에 남길지는 `tap_rec.dart` 가 정한다. 여기가 하는 일은 셋뿐이다:
//   · 박을 들려준다(미리 세기 한 마디 → 한 바퀴)
//   · 손가락이 닿고 떨어진 **때**를 받아 넘긴다
//   · 지금이 어느 대목인지 보여 준다
//
// ── 왜 한 바퀴만 도는가 ──
// 계속 겹쳐 담게 하면 「언제 그만두지」를 사용자가 정해야 한다. 한 바퀴로 끊으면
// 끝이 저절로 온다 — 마음에 안 들면 다시 누르면 된다. 되돌리기가 있으니 잃는 것도 없다.

import 'dart:async';

import 'package:flutter/material.dart';

import '../audio_isolate.dart';
import '../live_ops.dart';
import '../meter.dart';
import '../patterns.dart' show kStepsPerBar;
import '../prog_ops.dart';
import '../project.dart';
import '../sequencer.dart';
import '../synth.dart' show kPartLive;
import '../tap_rec.dart';
import '../theory.dart';
import 'play_head.dart';

/// 두드려 넣기를 연다. 돌려주는 것은 **두드린 것들** — 취소면 null,
/// 한 바퀴 도는 동안 아무것도 안 쳤으면 빈 목록.
Future<List<TapHit>?> tapRecordSheet(
  BuildContext context, {
  required Project project,
  required Transport transport,
  required AudioClient? host,
  required Track track,
  required int steps,
  required int bars,
  required bool isDrum,
  required bool isChord,
  required bool chromatic,
}) {
  return showModalBottomSheet<List<TapHit>>(
    context: context,
    isScrollControlled: true,
    isDismissible: false, // 녹음 중에 밖을 눌러 닫히면 친 것이 통째로 날아간다
    enableDrag: false,
    backgroundColor: const Color(0xFF121418),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => FractionallySizedBox(
      heightFactor: 0.9,
      child: _TapSheet(
        project: project,
        transport: transport,
        host: host,
        track: track,
        steps: steps,
        bars: bars,
        isDrum: isDrum,
        isChord: isChord,
        chromatic: chromatic,
      ),
    ),
  );
}

class _TapSheet extends StatefulWidget {
  final Project project;
  final Transport transport;
  final AudioClient? host;
  final Track track;
  final int steps, bars;
  final bool isDrum, isChord, chromatic;

  const _TapSheet({
    required this.project,
    required this.transport,
    required this.host,
    required this.track,
    required this.steps,
    required this.bars,
    required this.isDrum,
    required this.isChord,
    required this.chromatic,
  });

  @override
  State<_TapSheet> createState() => _TapSheetState();
}

class _TapSheetState extends State<_TapSheet> {
  final _clock = LoopClock();
  Timer? _timer;

  double _loopSec = 0;
  int _loopBars = 4;

  /// 대목이 흘러가는 규칙은 `tap_rec.dart` 가 들고 있다 — 여기서는 박만 넣는다.
  /// **벽시계를 안 쓴다**: 박은 오디오 시계에서 오고, 그게 소리의 진짜 자다.
  late TapClock _clockState;

  TapSnap _snap = TapSnap.eighth;
  bool _met = true;
  bool _backing = true;

  TapRecorder? _rec;

  TapPhase get _phase => _clockState.phase;

  /// 이번 바퀴에 이미 예약한 박 — 같은 박을 두 번 놓으면 두 번 들린다.
  final Set<int> _metSent = {};
  double _metLastNow = 0;

  /// 지금 눌려 있는 판(불을 켜 준다) · 손가락 번호 → 판 번호.
  final Set<int> _hot = {};
  final Map<int, int> _byPointer = {};

  int get _padCount => widget.isDrum ? kTapDrumPads.length : 1;
  double get _beatSec => 60.0 / widget.transport.bpm;

  /// 이 곡의 박자 — 미리 세기·한 바퀴 길이가 여기서 몇 박인지를 정한다.
  MeterDef get _meter => widget.project.meterDef;

  MusicKey get _key =>
      MusicKey(root: widget.transport.root, mode: widget.transport.mode);

  @override
  void initState() {
    super.initState();
    final h = widget.host;
    _clock.attach(h);
    // 박을 세려면 반주가 돌아야 한다 — 안 돌면 「지금 몇 초인가」가 없다.
    if (h != null && !widget.transport.playing) {
      final b = SceneSequencer.playLoop(widget.project, widget.transport, h);
      widget.transport.playing = true;
      widget.transport.songLoop = false;
      _loopSec = b.loopSec;
      _loopBars = b.loopBars;
    } else {
      final b = SceneSequencer.build(widget.project, widget.transport, reps: 1);
      _loopSec = b.loopSec;
      _loopBars = b.loopBars;
    }
    _clockState = TapClock(
      beatsPerLoop: _loopBars * _meter.clicksPerBar,
      lapBeats: widget.bars * _meter.clicksPerBar,
      countBeats: _meter.clicksPerBar,
      beatsPerBar: _meter.clicksPerBar,
    );
    h?.setSongMode(false); // 손가락에 붙어야 한다
    _timer = Timer.periodic(const Duration(milliseconds: 30), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clock.dispose();
    final h = widget.host;
    // 잡고 있던 것을 놓고, 내려 뒀던 트랙을 **반드시** 되돌린다.
    // 여기서 안 되돌리면 곡이 통째로 무음인 채로 화면을 나간다.
    h?.holdOff(-1);
    if (h != null) SceneSequencer.pushMix(widget.project, h);
    h?.setSongMode(true);
    super.dispose();
  }

  // ── 박 세기 ──

  void _tick() {
    final h = widget.host;
    if (!mounted || h == null || _loopSec <= 0) return;
    final pos = _clock.pos(_loopSec);

    _sendMet(pos, h);

    final was = _phase;
    _clockState.update(pos * _loopBars * _meter.clicksPerBar);
    if (was != TapPhase.rec && _phase == TapPhase.rec) _startRec();
    if (_phase == TapPhase.done) {
      _finish(pos);
      return;
    }
    setState(() {}); // 남은 수 · 진행 막대
  }

  void _sendMet(double pos, AudioClient h) {
    // 미리 세기는 **끄더라도 들린다** — 그게 자가 아니라 출발 신호라서다.
    if (_phase == TapPhase.rec && !_met) return;
    if (_phase != TapPhase.count && _phase != TapPhase.rec) return;
    final nowSec = pos * _loopSec;
    if (nowSec < _metLastNow) _metSent.clear(); // 판이 넘어갔다
    _metLastNow = nowSec;
    final ticks = beatsToSend(
      nowSec: nowSec,
      loopSec: _loopSec,
      beatSec: _beatSec,
      sent: _metSent,
    );
    if (ticks.isEmpty) return;
    h.batch(metroBatch(ticks));
    for (final t in ticks) {
      _metSent.add(t.beat);
    }
  }

  void _startRec() {
    final h = widget.host;
    _rec = TapRecorder(
      steps: widget.steps,
      loopBars: _loopBars,
      loopSec: _loopSec,
      snap: _snap,
      // 귀에 닿는 소리는 앞질러 만든 양만큼 늦다 — 그만큼 되돌려 박에 맞춘다
      latencySec: (h?.aheadFrames ?? 3072) / 48000.0,
      spb: widget.project.spb,
    );
  }

  void _finish(double pos) {
    final rec = _rec;
    _timer?.cancel();
    _timer = null;
    rec?.closeAll(pos); // 아직 누르고 있는 것도 거기서 끊어 담는다
    widget.host?.holdOff(-1);
    if (mounted) Navigator.of(context).pop(rec?.hits() ?? const <TapHit>[]);
  }

  // ── 반주 ──

  void _setBacking(bool on) {
    final h = widget.host;
    setState(() => _backing = on);
    if (h == null) return;
    if (on) {
      SceneSequencer.pushMix(widget.project, h);
      return;
    }
    // 트랙 버스만 내린다 — 자는 라이브 버스라 안 딸려 간다(`metroBatch` 참고).
    for (final t in widget.project.tracks) {
      h.setBus(SceneSequencer.busOf(t), vol: 0.0);
    }
  }

  // ── 두드리기 ──

  void _padDown(int pointer, int pad) {
    final rec = _rec;
    setState(() {
      _hot.add(pad);
      _byPointer[pointer] = pad;
    });
    final pos = _clock.pos(_loopSec);
    if (rec != null) rec.down(pad, pos);
    _sound(pointer, pad, rec?.stepOf(pos) ?? 0);
  }

  void _padUp(int pointer) {
    final pad = _byPointer.remove(pointer);
    if (pad == null) return;
    setState(() => _hot.remove(pad));
    widget.host?.holdOff(pointer);
    _rec?.up(pad, _clock.pos(_loopSec));
  }

  /// 두드리면 **그 자리에 담길 소리**가 난다 — 들은 것과 담기는 것이 달라선 안 된다.
  void _sound(int pointer, int pad, int step) {
    final h = widget.host;
    if (h == null) return;
    if (widget.isDrum) {
      h.drumOn(widget.track.kit, kTapDrumPads[pad].$1, 3);
      return;
    }
    final d = tapDegree(
      prog: _prog,
      progSteps: _progSteps,
      step: step,
      type: widget.track.type,
      chord: widget.isChord,
      chromatic: widget.chromatic,
      mode: widget.transport.mode,
    );
    if (widget.isChord) {
      // 코드는 **화음 전체**를 들려준다 — 한 음만 나면 코드인지 모른다.
      // 꾹 누르는 동안 잡고 있으려면 손가락 하나에 음이 셋이라, 여기만 batch 로 낸다.
      h.batch([
        for (final f in chordFreqsOf(diatonicChords(_key)[d % 7]))
          [widget.track.voice, f, 1.2, 3, true, 0.0, 0.0, kPartLive],
      ]);
      return;
    }
    h.holdOn(
      pointer,
      widget.track.voice,
      widget.chromatic
          ? semiFreq(d, widget.track.type, _key)
          : degreeFreq(d, widget.track.type, _key),
      3,
    );
  }

  List<ProgSlot> get _prog => widget.project.readSceneProg().$1;
  int get _progSteps => widget.project.readSceneProg().$2;

  // ── 그리기 ──

  @override
  Widget build(BuildContext context) {
    final tall = MediaQuery.of(context).size.height >= 520;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          children: [
            _head(),
            const SizedBox(height: 8),
            _options(),
            const SizedBox(height: 8),
            _status(tall),
            const SizedBox(height: 8),
            Expanded(child: _pads()),
          ],
        ),
      ),
    );
  }

  Widget _head() => Row(
    children: [
      const Icon(Icons.touch_app, size: 18, color: Colors.tealAccent),
      const SizedBox(width: 7),
      const Expanded(
        child: Text(
          '두드려 넣기',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('그만두기', style: TextStyle(fontSize: 13)),
      ),
    ],
  );

  Widget _options() => SizedBox(
    height: 34,
    child: ListView(
      scrollDirection: Axis.horizontal,
      children: [
        for (final s in TapSnap.values)
          _chip(
            label: s.label,
            on: _snap == s,
            // 녹음이 시작되면 못 바꾼다 — 도중에 자가 바뀌면 앞뒤가 다른 판이 된다
            onTap: _phase == TapPhase.rec ? null : () => setState(() => _snap = s),
          ),
        const SizedBox(width: 10),
        _chip(
          label: '메트로놈',
          on: _met,
          icon: Icons.timer_outlined,
          onTap: () => setState(() => _met = !_met),
        ),
        _chip(
          label: '반주',
          on: _backing,
          icon: Icons.queue_music,
          onTap: () => _setBacking(!_backing),
        ),
      ],
    ),
  );

  Widget _chip({
    required String label,
    required bool on,
    VoidCallback? onTap,
    IconData? icon,
  }) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? Colors.teal.withValues(alpha: 0.35) : Colors.white10,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: on ? Colors.tealAccent.withValues(alpha: 0.5) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: onTap == null
                    ? Colors.white24
                    : (on ? Colors.white : Colors.white54),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: onTap == null
                    ? Colors.white24
                    : (on ? Colors.white : Colors.white54),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _status(bool tall) {
    switch (_phase) {
      case TapPhase.wait:
        // 소리가 나야 박을 셀 수 있다 — 「지금 몇 초인가」가 소리에서 온다.
        // 못 켰으면 **가만히 기다리는 대신 그렇다고 말한다**(기다려도 안 온다).
        return _statusBox(
          Text(
            widget.host == null
                ? '소리를 아직 못 켰습니다 — 소리가 나야 박을 셉니다'
                : '다음 마디부터 셉니다',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              color: widget.host == null ? Colors.orangeAccent : Colors.white70,
            ),
          ),
          tall,
        );
      case TapPhase.count:
        return _statusBox(
          Text(
            '${_clockState.left}',
            style: TextStyle(
              fontSize: tall ? 44 : 28,
              height: 1.0,
              fontWeight: FontWeight.w900,
              color: Colors.tealAccent,
            ),
          ),
          tall,
        );
      case TapPhase.rec:
      case TapPhase.done:
        return _statusBox(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${_rec?.count ?? 0}개 · ${widget.bars}마디 한 바퀴',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              // **친 것이 보여야 한다.** 진행 막대만 있으면 「얼마나 남았나」는
              // 알아도 「내가 뭘 쳤나」는 모른다 — 한 바퀴가 끝나 격자를 볼 때까지
              // 깜깜하다. 두드린 자리를 눈금으로 찍어 주면 치면서 고칠 수 있다
              // (같은 칸을 다시 치면 덮어쓰니까).
              SizedBox(
                height: 14,
                width: double.infinity,
                child: CustomPaint(
                  painter: _TapStrip(
                    hits: _rec?.hits() ?? const [],
                    steps: widget.steps,
                    spb: widget.project.spb,
                    pads: _padCount,
                    at: _clockState.progress,
                  ),
                ),
              ),
            ],
          ),
          tall,
        );
    }
  }

  Widget _statusBox(Widget child, bool tall) => Container(
    height: tall ? 74 : 46,
    width: double.infinity,
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(11),
    ),
    child: child,
  );

  /// 판 전체를 **하나의 Listener** 로 받는다.
  ///
  /// 판마다 따로 달면 손가락이 판 밖으로 미끄러졌을 때 떼는 신호가 안 온다 —
  /// 그러면 그 음은 길이가 안 정해지고 소리도 안 끊긴다(라이브에서 겪은 것과 같다).
  Widget _pads() => LayoutBuilder(
    builder: (context, box) {
      final cols = _padCount == 1 ? 1 : 2;
      final rows = (_padCount / cols).ceil();
      final w = box.maxWidth / cols;
      final h = box.maxHeight / rows;
      int? padAt(Offset p) {
        if (p.dx < 0 || p.dy < 0 || p.dx >= box.maxWidth || p.dy >= box.maxHeight) {
          return null;
        }
        final i = (p.dy ~/ h) * cols + (p.dx ~/ w);
        return i >= 0 && i < _padCount ? i : null;
      }

      return Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          final pad = padAt(e.localPosition);
          if (pad != null) _padDown(e.pointer, pad);
        },
        onPointerUp: (e) => _padUp(e.pointer),
        onPointerCancel: (e) => _padUp(e.pointer),
        child: Column(
          children: [
            for (var r = 0; r < rows; r++)
              Expanded(
                child: Row(
                  children: [
                    for (var c = 0; c < cols; c++)
                      if (r * cols + c < _padCount)
                        Expanded(child: _pad(r * cols + c)),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );

  Widget _pad(int i) {
    final on = _hot.contains(i);
    final label = widget.isDrum ? kTapDrumPads[i].$2 : '두드리기';
    final sub = widget.isDrum
        ? kTapDrumPads[i].$1
        : (_phase == TapPhase.rec ? '박자만 — 높낮이는 나중에' : '');
    return Padding(
      padding: const EdgeInsets.all(3),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 70),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on
              ? Colors.tealAccent.withValues(alpha: 0.55)
              : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: on ? Colors.tealAccent : Colors.white24,
            width: on ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: widget.isDrum ? 22 : 19,
                fontWeight: FontWeight.w900,
                color: on ? Colors.black : Colors.white,
              ),
            ),
            if (sub.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: on ? Colors.black54 : Colors.white38,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 한 판을 두드리는 데 걸리는 시간(초) — 시험이 쓰는 값이다.
double tapLapSec(int bars, double bpm, {int clicksPerBar = 4}) =>
    bars * clicksPerBar * (60.0 / bpm);

/// 판 하나가 몇 칸인가 — 화면과 시험이 같은 셈을 쓰게 한다.
int tapSteps(int bars, {int spb = kStepsPerBar}) => bars * spb;


/// 두드리는 동안 보여 주는 띠 — **친 자리**와 **지금 자리**.
///
/// 마디 경계에 옅은 금을 긋는다. 금이 없으면 눈금이 어느 마디의 것인지 알 수 없어
/// 「셋째 마디를 놓쳤다」 같은 것이 안 보인다.
class _TapStrip extends CustomPainter {
  final List<TapHit> hits;
  final int steps, pads, spb;
  final double at;

  const _TapStrip({
    required this.hits,
    required this.steps,
    required this.spb,
    required this.pads,
    required this.at,
  });

  static const _padColors = [
    Color(0xFF64FFDA),
    Color(0xFFFFD54F),
    Color(0xFF80CBC4),
    Color(0xFFFF8A65),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    if (steps <= 0) return;
    final w = size.width;
    final bg = Paint()..color = Colors.white10;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)),
      bg,
    );

    // 마디 금
    final line = Paint()..color = Colors.white24..strokeWidth = 1;
    for (var b = spb; b < steps; b += spb) {
      final x = w * b / steps;
      canvas.drawLine(Offset(x, 2), Offset(x, size.height - 2), line);
    }

    // 지나온 만큼
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - 2, w * at.clamp(0.0, 1.0), 2),
      Paint()..color = Colors.tealAccent.withValues(alpha: 0.7),
    );

    // 친 자리 — 길이만큼 눕힌다(꾹 누른 것이 길게 보인다)
    for (final h in hits) {
      final x = w * h.step / steps;
      final len = (w * h.len / steps).clamp(2.0, w);
      final c = _padColors[h.pad % _padColors.length];
      final top = pads <= 1
          ? 2.0
          : 2 + (size.height - 4) * (h.pad % pads) / pads;
      final hgt = pads <= 1 ? size.height - 4 : (size.height - 4) / pads;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top, len, hgt.clamp(2.0, size.height)),
          const Radius.circular(2),
        ),
        Paint()..color = c,
      );
    }
  }

  @override
  bool shouldRepaint(_TapStrip old) =>
      old.at != at || old.hits.length != hits.length;
}
