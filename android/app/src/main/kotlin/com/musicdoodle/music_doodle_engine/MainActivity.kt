package com.musicdoodle.music_doodle_engine

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 쇼 화면을 위한 **화면 안 꺼짐**.
 *
 * 쇼 화면은 「곡을 틀어 놓고 폰을 세워 두는 자리」인데, 안드로이드 기본 화면 꺼짐이
 * 보통 30초라 **3분짜리 곡의 첫 소절에서 화면이 꺼졌다.** 그 화면의 존재 이유가
 * 반쯤 없어지는 것이다.
 *
 * 패키지를 더하지 않고 여기서 처리한다(§15 — 필요 이상의 dependency 금지).
 * 앱 전체에 켜 두면 배터리를 먹으므로 **쇼 화면에 있는 동안만** 켠다.
 */
class MainActivity : FlutterActivity() {
    private val channelName = "music_doodle/screen"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "keepAwake" -> {
                        val on = call.arguments as? Boolean ?: false
                        runOnUiThread {
                            if (on) {
                                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            } else {
                                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                            }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
