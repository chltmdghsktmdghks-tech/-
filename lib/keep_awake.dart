// 화면이 저 혼자 꺼지지 않게 — **쇼 화면에 있는 동안만.**
//
// 쇼 화면은 「곡을 틀어 놓고 폰을 세워 두는 자리」인데, 안드로이드 기본 화면 꺼짐이
// 보통 30초라 **3분짜리 곡의 첫 소절에서 화면이 꺼졌다.** 남에게 보여 주려고 만든
// 화면이 30초 만에 검게 되면 그 화면은 없는 것과 같다.
//
// **패키지를 더하지 않았다** (§15 — 필요 이상의 dependency 금지).
// `MainActivity.kt` 가 창 플래그 하나를 세우는 게 전부라 채널 하나면 된다.
import 'package:flutter/services.dart';

const _ch = MethodChannel('music_doodle/screen');

/// 화면을 안 꺼지게 할지. **실패해도 조용히 넘어간다** —
/// 시험(플랫폼 없음)과 다른 OS 에서 이것 때문에 화면이 안 뜨면 안 된다.
Future<void> keepAwake(bool on) async {
  try {
    await _ch.invokeMethod<void>('keepAwake', on);
  } catch (_) {
    // 안 되면 그만 — 화면은 그대로 돈다
  }
}
