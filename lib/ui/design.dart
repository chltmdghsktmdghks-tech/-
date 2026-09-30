// 디자인 토큰 — 색·타이포·간격을 한 곳에 모은다.
//
// ── 왜 만드나 ──
// 화면마다 같은 배경·트랙색·글자 크기를 각자 새로 적어 왔다(예: song_view.dart,
// scene_view.dart, mixer_view.dart, show_view.dart 가 각각 드럼/베이스/코드/멜로디
// 색을 따로 정의). 값 자체는 대체로 맞았지만(이미 여러 화면이 같은 hex를 쓰고
// 있었다), 이름이 없어서 어긋난 곳(home_view.dart 가 iOS 계열 색을 썼던 것)을
// 알아채기 어려웠다.
//
// 이 파일은 **지금 화면들이 실제로 쓰고 있는 값**을 모아 이름을 붙인 것이다 —
// 새 색·새 크기를 지어내지 않았다. 지금 당장은 정의만 하고, 기존 화면들을
// 강제로 이 파일에 갈아끼우지 않는다(그건 다음 배치에서 화면별로 한 커밋씩).
//
// ── 쓰는 법 ──
// `import '.../ui/design.dart';` 후 `DS.bg`, `DS.trackDrum`, `DS.spaceM` 처럼 쓴다.
import 'package:flutter/material.dart';

/// Design System — 이 앱의 색·타이포·간격 토큰.
abstract final class DS {
  // ── 색: 바탕 ──
  static const bg = Color(0xFF101114);
  static const surface = Color(0xFF16181C);
  static const surfaceRaised = Color(0xFF1A1D22);
  static const border = Colors.white12;

  // ── 색: 글자 ──
  static const text = Color(0xFFF4F4F7);
  static const textDim = Colors.white54;
  static const textFaint = Colors.white38;

  // ── 색: 강조 ──
  static const accent = Colors.tealAccent;

  // ── 색: 트랙/악기 (드럼·베이스·코드·멜로디) ──
  // song_view.dart · scene_view.dart · mixer_view.dart · show_view.dart 가 이미
  // 쓰고 있는 Material 계열 값 — 더 많은 화면이 쓰는 쪽을 정본으로 삼았다.
  static const trackDrum = Color(0xFF7CB342);
  static const trackBass = Color(0xFF42A5F5);
  static const trackChord = Color(0xFFAB47BC);
  static const trackMelody = Color(0xFFFFA726);

  // ── 색: 상태 ──
  static const good = Color(0xFF30D158);
  static const warn = Color(0xFFFFC107);
  static const critical = Color(0xFFFF375F);

  // ── 타이포: 역할별 스케일 ──
  static const title = TextStyle(
    fontSize: 22,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
  );
  static const section = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  );
  static const body = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0,
  );
  static const label = TextStyle(
    fontSize: 12.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.2,
  );
  static const caption = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );
  static const number = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  // ── 간격 단위 ──
  static const space4 = 4.0;
  static const space8 = 8.0;
  static const space12 = 12.0;
  static const space16 = 16.0;
  static const space24 = 24.0;
}

/// 가로로 누운 화면인가 — 폭이 높이보다 크면 그렇다(2026-09-30, 가로 적응 2순위).
///
/// 세로 배치는 그대로 두고 **가로일 때만** 분기하려고 화면마다 같은 잣대를 쓴다.
/// 높이가 귀한 폰 가로(≈393dp)와 넉넉한 태블릿 가로를 가르려면 [isShortLandscape].
bool isLandscape(BuildContext context) {
  final s = MediaQuery.sizeOf(context);
  return s.width > s.height;
}

/// 가로인데 높이도 모자란 화면(폰 가로, 높이 520dp 미만).
bool isShortLandscape(BuildContext context) {
  final s = MediaQuery.sizeOf(context);
  return s.width > s.height && s.height < 520;
}
