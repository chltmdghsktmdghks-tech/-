// 곡 표지 — **내보낸 곡에 얼굴을 붙인다.** (Phase 6 · 개선 계획 8-1)
//
// 계획 8-1: 「WAV Export 뿐만 아니라 **Music + Artwork + Track information +
// Visualizer** 구조로 확장할 수 있도록 설계하십시오. 최종적으로는 짧은 Music Video
// 형태로 공유할 수 있는 기반을 준비합니다.」
//
// ── 왜 그림이 먼저인가 ──
// 지금은 WAV 파일 하나만 나간다. 받은 사람 화면에는 **회색 네모에 파일 이름**뿐이다.
// 무슨 곡인지, 누가 뭘 만든 건지 아무것도 안 보인다. 영상까지 가려면 프레임을 찍어
// 인코딩해야 하고 그건 dependency 가 늘어난다(§15) — 표지 한 장은 `dart:ui` 만으로
// 되고, 영상으로 갈 때 **그 프레임의 바탕**이 그대로 이것이다.
//
// ── 아무 그림이나 그리지 않는다 ──
// 이 표지는 **그 곡의 것**이어야 한다. 그래서 세 가지를 그 곡에서 가져온다:
//   · 색 — 그 스타일의 무대 조명(`kStageLights`)
//   · 짜임 — 구간을 길이 비율대로 늘어놓은 띠(인트로가 짧고 훅이 길다)
//   · 글 — 곡 이름 · 스타일 · 템포 · 조 · 길이
// 장르만 바꿔도 표지가 달라지고, 구간을 늘리면 띠가 달라진다.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../arrange.dart';
import 'show_band.dart' show kStageLights;

/// 표지에 들어갈 값들 — 그리는 쪽은 프로젝트를 몰라도 된다(시험이 쉬워진다).
class CoverInfo {
  final String title;
  final String genreLabel;
  final String genreKey;
  final double bpm;
  final String keyLabel;
  final double seconds;

  /// 구간 (이름, 길이 초). 띠를 이 비율로 나눈다.
  final List<(String, double)> sections;

  const CoverInfo({
    required this.title,
    required this.genreLabel,
    required this.genreKey,
    required this.bpm,
    required this.keyLabel,
    required this.seconds,
    required this.sections,
  });
}

/// 구간 성격 → 띠의 밝기. 쇼 화면의 무대 에너지와 **같은 규칙**이다(계획 8) —
/// 두 곳이 다른 말을 하면 같은 곡이 아닌 것처럼 보인다.
double _weight(String name) {
  switch (roleOf(name)) {
    case SectionRole.drop:
      return 1.0;
    case SectionRole.build:
      return 0.62;
    case SectionRole.breakDown:
      return 0.22;
    case SectionRole.intro:
      return 0.32;
    case SectionRole.outro:
      return 0.30;
    case SectionRole.normal:
      return 0.55;
  }
}

class CoverPainter extends CustomPainter {
  final CoverInfo info;

  /// 글꼴 이름. **비워 두면 기기 기본 글꼴**(안드로이드는 한글이 알아서 나온다).
  ///
  /// 있는 이유: `CustomPainter` 는 위젯 트리 밖에서 그려서 화면의 기본 글꼴을
  /// 물려받지 않는다 — 시험 환경에서는 한글이 전부 두부(□)로 나와 **글자가 넘치는지
  /// 줄이 깨지는지 볼 수가 없다.** 그림 도구가 한글 글꼴을 실어 이름을 넘겨주면
  /// 그제야 보인다.
  final String? fontFamily;
  const CoverPainter(this.info, {this.fontFamily});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final lights = kStageLights[info.genreKey] ?? kStageLights['lofi']!;
    final a = lights[0], b = lights.length > 1 ? lights[1] : lights[0];
    final c = lights.length > 2 ? lights[2] : a;

    // 바탕 — 거의 검정에서 스타일 색으로. 검정에서 시작해야 글씨가 산다.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0B0B10),
            Color.lerp(const Color(0xFF0B0B10), b, 0.28)!,
            Color.lerp(const Color(0xFF0B0B10), c, 0.16)!,
          ],
        ).createShader(Offset.zero & size),
    );

    // 빛무리 둘 — 무대 조명이 표지로 옮겨 온 것
    for (final g in <(double, double, Color, double)>[
      (0.24, 0.28, a, 0.55),
      (0.78, 0.66, c, 0.40),
    ]) {
      final at = Offset(w * g.$1, h * g.$2);
      canvas.drawCircle(
        at,
        w * 0.40,
        Paint()
          ..shader = RadialGradient(
            colors: [
              g.$3.withValues(alpha: g.$4),
              g.$3.withValues(alpha: 0),
            ],
          ).createShader(Rect.fromCircle(center: at, radius: w * 0.40))
          ..blendMode = BlendMode.plus,
      );
    }

    // ── 짜임 띠 ── 이 곡이 어떻게 생겼는지가 한눈에 보이는 자리
    final total = info.sections.fold<double>(0, (s, e) => s + e.$2);
    if (total > 0 && info.sections.isNotEmpty) {
      final barY = h * 0.575, barH = h * 0.075;
      var x = w * 0.09;
      final barW = w * 0.82;
      for (final s in info.sections) {
        final segW = barW * (s.$2 / total);
        if (segW <= 0.5) continue;
        final k = _weight(s.$1);
        // 구간마다 높이도 다르다 — 색만으로는 흑백으로 뽑으면 다 같아진다
        final hh = barH * (0.42 + 0.58 * k);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              x + 1,
              barY + (barH - hh),
              math.max(1.0, segW - 2),
              hh,
            ),
            Radius.circular(barH * 0.16),
          ),
          Paint()
            ..color = Color.lerp(
              a,
              c,
              (x - w * 0.09) / barW,
            )!.withValues(alpha: 0.30 + 0.62 * k),
        );
        x += segW;
      }
    }

    // ── 글 ──
    //
    // **자리를 못 박지 않고 흘려 쓴다.** 처음엔 줄마다 y 를 적어 뒀는데, 곡 이름이
    // 길어 두 줄이 되면 다음 줄과 붙었다(그림으로 뽑아 보고 잡았다).
    // 그린 높이를 돌려받아 다음 줄이 그 아래에서 시작한다.
    double text(
      String s,
      double y,
      double px,
      Color col, {
      FontWeight weight = FontWeight.w900,
      double maxW = 0.84,
    }) {
      final tp = TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            color: col,
            fontSize: px,
            fontWeight: weight,
            height: 1.12,
            fontFamily: fontFamily,
            letterSpacing: -px * 0.02,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: w * maxW);
      tp.paint(canvas, Offset(w * 0.09, y));
      return tp.height;
    }

    var y = h * 0.085;
    y +=
        text('음악 낙서장', y, w * 0.030, Colors.white38, weight: FontWeight.w700) +
        h * 0.018;
    y += text(info.title, y, w * 0.088, Colors.white) + h * 0.045;
    y += text(info.genreLabel, y, w * 0.052, a) + h * 0.010;

    final mm = (info.seconds ~/ 60), ss = (info.seconds % 60).round();
    text(
      '${info.bpm.round()} BPM · ${info.keyLabel} · $mm:${ss.toString().padLeft(2, '0')}',
      y,
      w * 0.034,
      Colors.white60,
      weight: FontWeight.w700,
    );

    // 구간 이름은 **처음 셋만** — 다 적으면 글씨가 깨알이 된다
    if (info.sections.isNotEmpty) {
      final names = info.sections.take(3).map((e) => e.$1).join(' · ');
      text(
        info.sections.length > 3
            ? '$names · … ${info.sections.length}구간'
            : names,
        h * 0.685,
        w * 0.030,
        Colors.white38,
        weight: FontWeight.w700,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CoverPainter old) =>
      old.info != info || old.fontFamily != fontFamily;
}

/// 표지를 PNG 바이트로. **`dart:ui` 만 쓴다** — 새 dependency 없이 된다(§15).
Future<Uint8List> renderCoverPng(
  CoverInfo info, {
  int side = 1080,
  String? fontFamily,
}) async {
  final rec = ui.PictureRecorder();
  final size = Size(side.toDouble(), side.toDouble());
  CoverPainter(
    info,
    fontFamily: fontFamily,
  ).paint(Canvas(rec, Offset.zero & size), size);
  final img = await rec.endRecording().toImage(side, side);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return bytes!.buffer.asUint8List();
}
