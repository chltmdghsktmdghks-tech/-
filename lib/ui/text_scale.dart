// 글자를 키운 폰에서도 칸이 같이 커지게 한다.
//
// ── 무슨 일이 있었나 ──
// 안드로이드 「설정 → 디스플레이 → 글자 크기와 스타일」은 글자를 **1.3배**까지
// 키운다(접근성에서는 더 간다). 눈이 나쁜 사람은 대개 이걸 켜 놓고 산다.
// 그런데 글자만 커지고 **칸은 그대로**다 — 높이를 `height: 58` 처럼 숫자로 못 박은
// 칸은 그때 넘쳐서, 폰에서 노랑·검정 빗금이 그어지거나 글자가 잘린다.
//
// 이 앱은 그 상태로 한 번도 그려 본 적이 없었다(모든 시험이 1.0배였다).
// `text_scale_test.dart` 가 이제 세로·가로 × 1.0·1.3배로 전부 그려 본다.
//
// ── 어떻게 고치나 ──
// 못 박은 높이를 **글자와 같은 비율로** 늘린다. 다만 끝없이 늘리면 화면에 아무것도
// 안 들어오므로 위에서 멈춘다 — 그때부터는 글자가 줄임표(…)로 잘리는 편이 낫다.
import 'package:flutter/material.dart';

/// 이 화면의 글자 배율(1.0 = 기본).
///
/// 안드로이드 14부터는 배율이 **곧지 않다**(큰 글자일수록 덜 키운다). 그래서
/// 100 같은 큰 수가 아니라 **본문 크기(14)** 로 재야 실제 본문이 커지는 만큼 나온다.
double textScale(BuildContext context, {double max = 1.6}) {
  final s = MediaQuery.textScalerOf(context).scale(14) / 14;
  return s.isFinite && s > 1 ? (s < max ? s : max) : 1.0;
}

/// 못 박은 크기(높이든 폭이든)를 글자 배율만큼 늘린 값.
double scaled(BuildContext context, double base, {double max = 1.6}) =>
    base * textScale(context, max: max);
