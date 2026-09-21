// 캐릭터(이모티콘) 서랍 — 씬에 붙여 두면 **박자에 맞춰 움직인다**.
//
// 옛 웹 앱(뮤직 두들)에서 가져왔다. 거기서는 SVG 조각 몇 개 + 「16포즈 표」로
// 그렸는데, 여기서는 두 가지를 바꿨다.
//
//  1) **그림은 코드로 그린다** — 밴드(`show_band.dart`)와 같은 이유다.
//     이미지 파일이면 저작권이 섞이고, 앱이 무거워지고, 무엇보다 소리에 맞춰
//     매 프레임 자세가 바뀌는 걸 못 한다.
//  2) **자세를 표가 아니라 박으로 뽑는다** — 옛 앱은 8분음표 16칸짜리 표를 돌렸다.
//     그러면 한 판이 2마디냐 4마디냐에 따라 춤이 달라진다. 여기서는 「지금 몇 박째」
//     하나만 받아서 계산한다 — 판 길이가 몇이든 **박에 맞는다**.
//
// 움직임은 셋만 지킨다(사람이 박자로 읽는 것이 이 셋이다):
//  · `_bump` 박마다 한 번 통통 — 무릎 굽히기
//  · `_bar`  한 마디에 한 번 — 팔·꼬리처럼 크게 흔드는 것
//  · `_bar2` 두 마디에 한 번 — 몸 기울기처럼 아주 느린 것

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../audio_isolate.dart';
import '../project.dart';
import 'play_head.dart';

/// 캐릭터를 그리는 판의 크기. 옛 앱의 viewBox 를 그대로 쓴다 —
/// 좌표를 옮겨 적을 때 실수가 안 나온다.
const double kCritW = 40;
const double kCritH = 52;

// ── 박에서 뽑는 값 ──
/// 박마다 한 번 통통(0~1). 원본의 `|sin(t*4)|`.
double _bump(double b) => math.sin(b * math.pi).abs();

/// 한 마디(4박)에 한 번 왕복(-1~1). 원본의 `sin(t*2)`.
double _bar(double b) => math.sin(b * math.pi / 2);

/// 한 마디에 한 번이되 **네 분의 일 박 앞선** 것. 원본의 `sin(t*2+π/2)`.
double _barC(double b) => math.cos(b * math.pi / 2);

/// 두 마디에 한 번(-1~1). 원본의 `sin(t)`.
double _bar2(double b) => math.sin(b * math.pi / 4);

// ── 그리기 거들이 ──
void _turn(Canvas c, double x, double y, double deg, VoidCallback body) {
  if (deg == 0) {
    body();
    return;
  }
  c.save();
  c.translate(x, y);
  c.rotate(deg * math.pi / 180);
  c.translate(-x, -y);
  body();
  c.restore();
}

void _shift(Canvas c, double dx, double dy, VoidCallback body) {
  if (dx == 0 && dy == 0) {
    body();
    return;
  }
  c.save();
  c.translate(dx, dy);
  body();
  c.restore();
}

void _zoom(
  Canvas c,
  double x,
  double y,
  double sx,
  double sy,
  VoidCallback body,
) {
  c.save();
  c.translate(x, y);
  // 0 배는 뒤집을 수 없는 행렬이 된다 — 아주 얇게라도 남긴다.
  c.scale(sx.abs() < 0.02 ? (sx < 0 ? -0.02 : 0.02) : sx, sy);
  c.translate(-x, -y);
  body();
  c.restore();
}

Paint _f(Color c) => Paint()
  ..color = c
  ..isAntiAlias = true;

Paint _s(Color c, [double w = 3.2]) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true;

void _ln(Canvas c, double x1, double y1, double x2, double y2, Paint p) =>
    c.drawLine(Offset(x1, y1), Offset(x2, y2), p);

void _circ(Canvas c, double x, double y, double r, Paint p) =>
    c.drawCircle(Offset(x, y), r, p);

void _oval(Canvas c, double x, double y, double rx, double ry, Paint p) =>
    c.drawOval(
      Rect.fromCenter(center: Offset(x, y), width: rx * 2, height: ry * 2),
      p,
    );

void _rrect(
  Canvas c,
  double x,
  double y,
  double w,
  double h,
  double r,
  Paint p,
) => c.drawRRect(
  RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)),
  p,
);

Path _tri(double x1, double y1, double x2, double y2, double x3, double y3) =>
    Path()
      ..moveTo(x1, y1)
      ..lineTo(x2, y2)
      ..lineTo(x3, y3)
      ..close();

/// 캐릭터 한 종류.
class CritterDef {
  /// 저장에 쓰는 값. `@` 로 시작한다 — 그냥 이모지와 구별하는 표다.
  final String id;
  final String name;

  /// [beat] 는 지금 몇 박째(연속). 0 이면 멈춘 자세.
  /// [tint] 는 **제 색이 없는** 캐릭터(선으로 그린 것)가 쓸 색.
  final void Function(Canvas c, double beat, Color tint) draw;
  const CritterDef(this.id, this.name, this.draw);
}

// ── 색이 있는 캐릭터들이 쓰는 색 ──
const _slimeBody = Color(0xFF6AC05A);
const _slimeInk = Color(0xFF112233);
const _eyeWhite = Color(0xFFF0E9F5);
const _eyeRim = Color(0xFF3A2B4A);
const _iris = Color(0xFFB06EE0);
const _pupil = Color(0xFF160C22);
const _stem = Color(0xFFF2E6CF);
const _cap = Color(0xFFE07A4A);
const _capInk = Color(0xFF5A3B2B);
const _gemBlue = Color(0xFF5DB9FF);
const _skin = Color(0xFFF0D9B8);
const _tunic = Color(0xFF5DB97A);
const _boot = Color(0xFF3A5A4A);
const _hair = Color(0xFFF4F4F7);
const _faceInk = Color(0xFF2A2233);

final List<CritterDef> kCritterList = [
  CritterDef('@dancer', '댄서', (c, b, t) {
    final f = _f(t), s = _s(t);
    _shift(c, 0, -2.5 * _bump(b), () {
      _turn(c, 20, 31, 9 * _bar2(b), () {
        _circ(c, 20, 9, 5.5, f);
        _ln(c, 20, 15, 20, 31, s);
        _turn(c, 20, 18, -45 + 50 * _bar(b), () => _ln(c, 20, 18, 11, 26, s));
        _turn(c, 20, 18, 45 - 50 * _bar(b), () => _ln(c, 20, 18, 29, 26, s));
        _turn(c, 20, 31, 20 * _barC(b), () => _ln(c, 20, 31, 14, 46, s));
        _turn(c, 20, 31, -20 * _barC(b), () => _ln(c, 20, 31, 26, 46, s));
      });
    });
  }),
  // 로봇만 **뚝뚝 끊어서** 움직인다 — 8분음표마다 자세가 딱 바뀐다.
  // 부드럽게 하면 로봇이 아니다.
  CritterDef('@robot', '로봇', (c, b, t) {
    final f = _f(t), s = _s(t);
    final e = (b * 2).floor(); // 8분음표 몇 번째
    final up = e % 4 < 2;
    final hop = e % 2 == 1 ? -2.0 : 0.0;
    final d = up ? -1.0 : 1.0;
    _shift(c, 0, hop, () {
      _turn(c, 20, 13, 8 * d, () => _rrect(c, 13, 2, 14, 11, 2, f));
      _rrect(c, 14, 16, 12, 15, 2, f);
      _turn(c, 13, 18, up ? -80 : 10, () => _ln(c, 13, 18, 5, 24, s));
      _turn(c, 27, 18, up ? 10 : 80, () => _ln(c, 27, 18, 35, 24, s));
      _turn(c, 16, 31, -8 * d, () => _ln(c, 16, 31, 16, 46, s));
      _turn(c, 24, 31, 8 * d, () => _ln(c, 24, 31, 24, 46, s));
    });
  }),
  CritterDef('@cat', '고양이', (c, b, t) {
    final f = _f(t), s = _s(t);
    _shift(c, 0, -3 * _bump(b), () {
      _oval(c, 19, 37, 10, 8, f);
      _turn(c, 20, 22, 12 * _bar(b), () {
        _circ(c, 20, 20, 7, f);
        c.drawPath(_tri(14, 16, 12, 8, 19, 13), f);
        c.drawPath(_tri(26, 16, 28, 8, 21, 13), f);
      });
      _turn(c, 29, 38, 28 * _bar(b), () {
        c.drawPath(
          Path()
            ..moveTo(29, 38)
            ..quadraticBezierTo(37, 34, 35, 25),
          s,
        );
      });
    });
  }),
  CritterDef('@bird', '병아리', (c, b, t) {
    final f = _f(t), s = _s(t);
    final w = 40 * _bump(b);
    _shift(c, 0, -2 * _bump(b), () {
      _circ(c, 20, 31, 10, f);
      _shift(c, 0, 3 * _bar(b), () {
        _circ(c, 22, 14, 6, f);
        c.drawPath(_tri(28, 13, 34, 15, 28, 17), f);
      });
      _turn(c, 12, 29, w, () => _ln(c, 12, 29, 4, 24, s));
      _turn(c, 28, 29, -w, () => _ln(c, 28, 29, 36, 24, s));
      _ln(c, 16, 41, 16, 47, s);
      _ln(c, 24, 41, 24, 47, s);
    });
  }),
  CritterDef('@alien', '문어', (c, b, t) {
    final f = _f(t), s = _s(t);
    double leg(int k) => 18 * math.sin(b * math.pi / 2 + k * 1.1);
    _shift(c, 0, -2 * _bar(b).abs(), () {
      _turn(c, 20, 30, 6 * _bar2(b), () {
        c.drawPath(
          Path()
            ..moveTo(8, 28)
            ..arcToPoint(
              const Offset(32, 28),
              radius: const Radius.circular(12),
            )
            ..lineTo(32, 31)
            ..lineTo(8, 31)
            ..close(),
          f,
        );
        _turn(c, 11, 31, leg(0), () => _ln(c, 11, 31, 9, 45, s));
        _turn(c, 17, 31, leg(1), () => _ln(c, 17, 31, 16, 47, s));
        _turn(c, 23, 31, leg(2), () => _ln(c, 23, 31, 24, 47, s));
        _turn(c, 29, 31, leg(3), () => _ln(c, 29, 31, 31, 45, s));
      });
    });
  }),
  CritterDef('@note', '음표', (c, b, t) {
    final f = _f(t), s = _s(t);
    _shift(c, 0, -4 * _bump(b), () {
      _turn(c, 20, 30, 16 * _bar(b), () {
        _oval(c, 15, 38, 6.5, 5, f);
        _ln(c, 21, 37, 21, 10, s);
        c.drawPath(
          Path()
            ..moveTo(21, 10)
            ..quadraticBezierTo(31, 14, 27, 23),
          s,
        );
      });
    });
  }),
  CritterDef('@slime', '슬라임', (c, b, _) {
    final sx = 1 + 0.13 * _bar(b);
    _shift(c, 0, -3 * _bar(b).abs(), () {
      // 몸만 눌렸다 펴진다. 눈·입은 같이 늘어나면 흉해서 따로 그린다.
      _zoom(c, 20, 46, sx, 2 - sx, () {
        c.drawPath(
          Path()
            ..moveTo(6, 46)
            ..quadraticBezierTo(3, 23, 20, 23)
            ..quadraticBezierTo(37, 23, 34, 46)
            ..close(),
          _f(_slimeBody),
        );
      });
      _circ(c, 14, 37, 2.4, _f(_slimeInk));
      _circ(c, 26, 37, 2.4, _f(_slimeInk));
      c.drawPath(
        Path()
          ..moveTo(15, 43)
          ..quadraticBezierTo(20, 46, 25, 43),
        _s(_slimeInk, 1.6),
      );
    });
  }),
  CritterDef('@eyeball', '눈알', (c, b, _) {
    _shift(c, 0, -3 * _bar(b).abs(), () {
      _circ(c, 20, 28, 14, _f(_eyeWhite));
      _circ(c, 20, 28, 14, _s(_eyeRim, 1.5));
      _shift(c, 3.2 * _bar(b), 1.5 * math.sin(b * math.pi), () {
        _circ(c, 20, 28, 7, _f(_iris));
        _circ(c, 20, 28, 3.4, _f(_pupil));
        _circ(c, 17.6, 25.6, 1.5, _f(Colors.white));
      });
    });
  }),
  CritterDef('@mushroom', '버섯', (c, b, _) {
    _shift(c, 0, -4 * _bar(b).abs(), () {
      _turn(c, 20, 48, 6 * _bar2(b), () {
        _rrect(c, 14, 33, 12, 15, 3, _f(_stem));
        _circ(c, 17, 41, 1.4, _f(_capInk));
        _circ(c, 23, 41, 1.4, _f(_capInk));
        c.drawPath(
          Path()
            ..moveTo(6, 31)
            ..quadraticBezierTo(6, 13, 20, 13)
            ..quadraticBezierTo(34, 13, 34, 31)
            ..close(),
          _f(_cap),
        );
        final spot = _f(Colors.white.withValues(alpha: 0.8));
        _circ(c, 14, 23, 2.6, spot);
        _circ(c, 26, 22, 2, spot);
      });
    });
  }),
  CritterDef('@gem', '원소보석', (c, b, _) {
    _shift(c, 0, -3 * _bar(b).abs(), () {
      // 옆으로 눌렀다 펴면서 **도는 것처럼** 보인다(진짜 3D 가 아니다).
      _zoom(c, 20, 29, math.cos(b * math.pi / 4), 1, () {
        final body = Path()
          ..moveTo(20, 15)
          ..lineTo(32, 26)
          ..lineTo(26, 43)
          ..lineTo(14, 43)
          ..lineTo(8, 26)
          ..close();
        c.drawPath(body, _f(_gemBlue));
        c.drawPath(body, _s(Colors.white.withValues(alpha: 0.67), 1));
        final cut = _s(Colors.white.withValues(alpha: 0.4), 1);
        _ln(c, 20, 15, 14, 43, cut);
        _ln(c, 20, 15, 26, 43, cut);
        _ln(c, 8, 26, 32, 26, cut);
      });
    });
  }),
  CritterDef('@hero', '모험가', (c, b, _) {
    final arm = 26 * _bar(b);
    _shift(c, 0, -4 * _bar(b).abs(), () {
      _rrect(c, 14, 30, 12, 16, 3, _f(_tunic));
      _rrect(c, 15, 44, 4, 6, 2, _f(_boot));
      _rrect(c, 21, 44, 4, 6, 2, _f(_boot));
      _circ(c, 20, 20, 10, _f(_skin));
      c.drawPath(
        Path()
          ..moveTo(9, 19)
          ..quadraticBezierTo(9, 6, 20, 6)
          ..quadraticBezierTo(31, 6, 31, 19)
          ..quadraticBezierTo(31, 13, 20, 13)
          ..quadraticBezierTo(9, 13, 9, 19)
          ..close(),
        _f(_hair),
      );
      _circ(c, 16.5, 20, 1.5, _f(_faceInk));
      _circ(c, 23.5, 20, 1.5, _f(_faceInk));
      c.drawPath(
        Path()
          ..moveTo(17, 24)
          ..quadraticBezierTo(20, 26, 23, 24),
        _s(_faceInk, 1.2),
      );
      final a = _s(_skin, 3.5);
      _turn(c, 14, 33, arm, () => _ln(c, 14, 33, 7, 38, a));
      _turn(c, 26, 33, -arm, () => _ln(c, 26, 33, 33, 38, a));
    });
  }),
];

final Map<String, CritterDef> kCritters = {
  for (final d in kCritterList) d.id: d,
};

/// 그림 캐릭터 말고 **그냥 글자로 붙이는** 것들. 옛 앱과 같은 줄이다.
const List<String> kCritterEmojis = [
  '🔥',
  '⚡',
  '😎',
  '🥁',
  '🎸',
  '🎹',
  '🌙',
  '⭐',
  '💜',
  '🐱',
  '👾',
  '🍄',
  '🌊',
  '🚀',
  '🍕',
  '🫠',
];

/// 저장된 값에 붙일 이름 — 메뉴에 「지금 무엇이 붙어 있나」를 보여 줄 때 쓴다.
String critterName(String? v) {
  if (v == null || v.isEmpty) return '없음';
  return kCritters[v]?.name ?? v;
}

class _CritterPainter extends CustomPainter {
  final String id;
  final double beat;
  final Color tint;
  const _CritterPainter(this.id, this.beat, this.tint);

  @override
  void paint(Canvas canvas, Size size) {
    final def = kCritters[id];
    if (def == null) return;
    final k = math.min(size.width / kCritW, size.height / kCritH);
    canvas.save();
    canvas.translate(
      (size.width - kCritW * k) / 2,
      (size.height - kCritH * k) / 2,
    );
    canvas.scale(k);
    // **판 밖은 자른다.** 크게 흔드는 곳(고양이 꼬리·문어 다리)은 40×52 를
    // 잠깐 넘어간다 — 옛 앱에서는 브라우저가 SVG 를 잘라 줘서 안 보였던 것이고,
    // 여기서는 안 자르면 옆 칩 위에 그려진다.
    canvas.clipRect(const Rect.fromLTWH(0, 0, kCritW, kCritH));
    def.draw(canvas, beat, tint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CritterPainter old) =>
      old.beat != beat || old.id != id || old.tint != tint;
}

/// 캐릭터 하나를 **주어진 자세로** 그린다. 시계는 밖에서 준다.
class CritterIcon extends StatelessWidget {
  final String value;
  final double size; // 세로 길이
  final double beat;
  final Color color;
  const CritterIcon({
    super.key,
    required this.value,
    required this.size,
    this.beat = 0,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    if (kCritters.containsKey(value)) {
      return SizedBox(
        width: size * kCritW / kCritH,
        height: size,
        child: CustomPaint(painter: _CritterPainter(value, beat, color)),
      );
    }
    // 이모지는 자세가 없다. 통통 튀는 것만 준다 — 그것만으로도 박이 보인다.
    return SizedBox(
      width: size * 0.86,
      height: size,
      child: Center(
        child: Transform.translate(
          offset: Offset(0, -_bump(beat) * size * 0.12),
          child: Text(
            value,
            style: TextStyle(fontSize: size * 0.66),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// 캐릭터 + **엔진 시계**. 돌고 있을 때만 다시 그린다.
///
/// [LoopPosBuilder] 를 안 쓰고 시계를 직접 든다. 그쪽은 멈춰 있어도 초당 60번
/// 다시 그리는데, 캐릭터는 씬 줄에 여러 개가 붙는다 — 멈춘 화면에서까지
/// 다시 그릴 이유가 없다.
class CritterBeat extends StatefulWidget {
  final AudioClient? host;
  final double loopSec;
  final double bpm;
  final String value;
  final double size;
  final Color color;
  const CritterBeat({
    super.key,
    required this.host,
    required this.loopSec,
    required this.bpm,
    required this.value,
    required this.size,
    this.color = Colors.white,
  });

  @override
  State<CritterBeat> createState() => _CritterBeatState();
}

class _CritterBeatState extends State<CritterBeat>
    with SingleTickerProviderStateMixin {
  final _clock = LoopClock();
  late final AnimationController _tick;

  @override
  void initState() {
    super.initState();
    _tick = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _clock.attach(
      widget.host,
      onLooping: (on) {
        if (!mounted) return;
        if (on) {
          _tick.repeat();
        } else {
          _tick.stop();
        }
        setState(() {});
      },
    );
  }

  @override
  void didUpdateWidget(CritterBeat old) {
    super.didUpdateWidget(old);
    if (old.host != widget.host) {
      _clock.attach(
        widget.host,
        onLooping: (on) {
          if (!mounted) return;
          if (on) {
            _tick.repeat();
          } else {
            _tick.stop();
          }
          setState(() {});
        },
      );
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _tick.dispose();
    super.dispose();
  }

  double get _beat {
    if (!_clock.looping) return 0;
    final sec = widget.loopSec;
    if (sec <= 0 || widget.bpm <= 0) return 0;
    return _clock.pos(sec) * sec * widget.bpm / 60;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _tick,
      builder: (context, _) => CritterIcon(
        value: widget.value,
        size: widget.size,
        beat: _beat,
        color: widget.color,
      ),
    );
  }
}

/// 캐릭터 고르는 서랍.
///
/// 「없음」을 **맨 앞**에 둔다 — 붙이는 것보다 떼는 것이 찾기 어려우면 안 된다.
/// 고르면 바로 닫는다(확인 버튼이 없다): 잘못 골라도 다시 열어 바꾸면 그만이라
/// 한 번 더 누르게 할 값이 없다.
Future<void> showCritterSheet(
  BuildContext context, {
  required String? value,
  required ValueChanged<String?> onPick,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1A1A1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '캐릭터',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            const Text(
              '씬에 하나 붙여 두면 재생할 때 박자에 맞춰 움직입니다.',
              style: TextStyle(fontSize: 11.5, color: Colors.white54),
            ),
            const SizedBox(height: 10),
            // 세로가 짧은 폰(가로 모드)에서도 서랍이 화면을 안 넘게 한다.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.5,
              ),
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _CritterCell(
                      label: '없음',
                      picked: value == null || value.isEmpty,
                      onTap: () {
                        Navigator.pop(ctx);
                        onPick(null);
                      },
                    ),
                    for (final d in kCritterList)
                      _CritterCell(
                        label: d.name,
                        value: d.id,
                        picked: value == d.id,
                        onTap: () {
                          Navigator.pop(ctx);
                          onPick(d.id);
                        },
                      ),
                    for (final e in kCritterEmojis)
                      _CritterCell(
                        value: e,
                        picked: value == e,
                        onTap: () {
                          Navigator.pop(ctx);
                          onPick(e);
                        },
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

class _CritterCell extends StatelessWidget {
  final String? value;
  final String? label;
  final bool picked;
  final VoidCallback onTap;
  const _CritterCell({
    this.value,
    this.label,
    required this.picked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 74, // 손가락 바닥선을 넉넉히 넘긴다
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: picked ? Colors.indigo.shade400 : Colors.white10,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: picked ? Colors.white70 : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (value == null)
              const Icon(Icons.block, size: 22, color: Colors.white38)
            else
              CritterIcon(value: value!, size: 34),
            if (label != null) ...[
              const SizedBox(height: 3),
              Text(
                label!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  color: picked ? Colors.white : Colors.white54,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// **지금 흐르는 구간**의 캐릭터와 그 구간 안에서 몇 박째인가. 없으면 null.
///
/// 곡 화면의 눈금 줄과 쇼 화면의 무대가 **같은 것을 물어본다** — 두 군데에 따로
/// 적으면 언젠가 말없이 어긋난다(이 프로젝트에서 제일 자주 나온 병이다).
///
/// [spans] 는 구간마다 (시작 초, 길이 초). [sections] 와 자리가 맞아야 한다.
/// [bpm] 은 씬에 빠르기가 안 적혀 있을 때 쓸 곡 빠르기.
(String, double)? critterAt(
  List<Scene> scenes,
  List<Section> sections,
  List<(double, double)> spans,
  double now,
  double bpm,
) {
  for (var i = 0; i < spans.length && i < sections.length; i++) {
    if (now < spans[i].$1 || now >= spans[i].$1 + spans[i].$2) continue;
    final sc = sections[i].scene;
    if (sc < 0 || sc >= scenes.length) return null;
    final v = scenes[sc].critter;
    if (v == null || v.isEmpty) return null;
    // 씬마다 빠르기가 다를 수 있다 — 그 씬 것을 쓴다.
    final b = scenes[sc].bpm ?? bpm;
    return (v, (now - spans[i].$1) * b / 60);
  }
  return null;
}
