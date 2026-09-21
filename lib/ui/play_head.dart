// 재생 위치를 부드럽게 흘려 주는 공용 조각.
//
// 오디오 아이솔레이트는 **0.25초마다** 위치를 보낸다. 그대로 그리면 초당 4번 툭툭
// 끊겨 보인다. 받은 값과 받은 시각을 적어 두고 **그 사이를 화면 주사율로 이어서**
// 계산한다 — 0.25초마다 다시 맞춰지니 어긋나 쌓이지도 않는다.
//
// 이걸 쓰는 위젯만 다시 그려진다(씬 화면의 마디 표시, 곡 화면의 구간 표시).
// 화면 전체를 setState 로 받으면 초당 4번씩 트랙 줄까지 다 다시 그린다 — 4단계에서
// 20밴드 EQ 가 느렸던 것과 같은 병이다.

import 'dart:async';

import 'package:flutter/material.dart';

import '../audio_isolate.dart';

typedef LoopPosWidgetBuilder =
    Widget Function(BuildContext context, double pos, bool looping);

/// 재생 위치를 **아무 때나 물어볼 수 있게** 들고 있는 것. 위젯이 아니다.
///
/// 그리기만 할 거면 아래 [LoopPosBuilder] 로 충분하지만, 라이브 녹음은 손가락이
/// 닿는 **그 순간** 몇 박인지를 알아야 한다 — 그건 build 안이 아니라 콜백 안이다.
/// 이어 맞추는 계산(0.25초마다 오는 값 + 그 사이 보간)은 한 군데만 있어야 한다.
class LoopClock {
  final _sw = Stopwatch()..start();
  StreamSubscription<AudioStats>? _sub;
  double _pos = 0;
  int _atMs = 0;
  bool looping = false;

  void attach(AudioClient? host, {void Function(bool looping)? onLooping}) {
    _sub?.cancel();
    _sub = host?.statsStream.listen((s) {
      _pos = s.loopPos;
      _atMs = _sw.elapsedMilliseconds;
      if (looping != s.looping) {
        looping = s.looping;
        onLooping?.call(s.looping);
      }
    });
  }

  /// 지금 한 판 안의 위치(0~1). [loopSec] 를 알아야 사이를 이어 그릴 수 있다.
  double pos(double loopSec) {
    if (!looping || loopSec <= 0) return _pos;
    return (_pos + (_sw.elapsedMilliseconds - _atMs) / 1000 / loopSec) % 1.0;
  }

  void dispose() {
    _sub?.cancel();
    _sw.stop();
  }
}

class LoopPosBuilder extends StatefulWidget {
  final AudioClient? host;

  /// 한 판(또는 곡 한 바퀴) 길이(초). 0이면 이어 그리기를 안 한다.
  final double loopSec;
  final LoopPosWidgetBuilder builder;

  const LoopPosBuilder({
    super.key,
    required this.host,
    required this.loopSec,
    required this.builder,
  });

  @override
  State<LoopPosBuilder> createState() => _LoopPosBuilderState();
}

class _LoopPosBuilderState extends State<LoopPosBuilder>
    with SingleTickerProviderStateMixin {
  final _clock = LoopClock();
  late final AnimationController _tick;

  @override
  void initState() {
    super.initState();
    _tick = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _clock.attach(
      widget.host,
      onLooping: (_) {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _clock.dispose();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _tick,
      builder: (context, _) =>
          widget.builder(context, _clock.pos(widget.loopSec), _clock.looping),
    );
  }
}
