// 두들플레이 처음 안내 (2026-09-30, D. 발견성) — 어떤 손짓이 있는지 **처음 한 번만** 살짝 알려 주고,
// 「알겠어요」를 누르면(또는 그 악기를 한 판 끝까지 치면) 다시 안 뜬다.
//
//  · 무엇을 보여 줄지(글) — 순수 데이터라 시험이 직접 잰다.
//  · 봤는지 기억하기 — 앱 지원 폴더의 작은 JSON 파일. 파일을 못 쓰는 환경(시험·웹)에서는
//    **메모리에만** 기억한다(안내가 한 번 더 뜨는 정도라 조용히 넘어가도 안전하다).
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 안내 한 줄 — 손짓 그림글자 + 설명.
class DoodleCoachTip {
  final String glyph;
  final String text;
  const DoodleCoachTip(this.glyph, this.text);
}

/// 안내를 따로 기억하는 단위 — 악기(킥·스네어·하이햇·코드·베이스) 하나에 카드 하나.
const List<String> kDoodleCoachKeys = ['kick', 'snare', 'hat', 'chord', 'bass'];

/// 이 악기의 안내 문구. [swell]·[mute]·[boom] 은 그 음색·킷에서만 있는 손짓이라 있을 때만 덧붙인다.
List<DoodleCoachTip> doodleCoachTips(
  String key, {
  bool swell = false,
  bool mute = false,
  bool boom = false,
}) {
  switch (key) {
    case 'kick':
      return [
        const DoodleCoachTip('↕', '위쪽을 치면 정타, 아래쪽은 여린 고스트 킥'),
        const DoodleCoachTip('↔', '오른쪽일수록 세게 울려요'),
        if (boom) const DoodleCoachTip('●', '길게 누르면 808 서브가 그만큼 웅— 울어요'),
      ];
    case 'snare':
      return const [
        DoodleCoachTip('◎', '한가운데가 세게, 가장자리가 여리게'),
        DoodleCoachTip('◔', '꾹 누르면 롤 — 세게 누르면 16분, 여리게는 8분'),
        DoodleCoachTip('→', '롤 도중 오른쪽으로 밀면 점점 세져요'),
      ];
    case 'hat':
      return const [
        DoodleCoachTip('↔', '오른쪽일수록 세게, 톡 치면 닫힌 하이햇'),
        DoodleCoachTip('◔', '아래에서 꾹 누르면 열린 하이햇, 위에서 꾹은 16비트 롤'),
        DoodleCoachTip('→', '롤 도중 위로 밀면 촘촘하게, 오른쪽으로 밀면 세게'),
      ];
    case 'chord':
      return [
        const DoodleCoachTip('↔', '마디의 마지막 탭이 왼쪽이면 다음 마디는 긴장, 오른쪽이면 해결'),
        const DoodleCoachTip('↕', '위쪽을 치면 화려한 코드, 아래쪽은 담백한 코드'),
        if (swell) const DoodleCoachTip('↑', '아래에서 위로 그으면 볼륨이 차올라요'),
        if (mute) const DoodleCoachTip('×', '아주 짧게 톡 떼면 줄을 덮는 뮤트'),
      ];
    case 'bass':
      return const [
        DoodleCoachTip('↕', '위로 갈수록 높은 음'),
        DoodleCoachTip('↔', '오른쪽일수록 세게'),
        DoodleCoachTip('⇅', '잡은 채 위아래로 끌면 음이 미끄러져요, 오래 잡으면 꼬리가 길어져요'),
      ];
  }
  return const [];
}

/// 어떤 안내를 이미 봤는지. 앱 전체에서 하나.
class DoodleHints {
  DoodleHints._();

  static final Set<String> _seen = {};
  static bool _loaded = false;

  /// 시험이 임시 폴더를 넣거나, 파일 없이 메모리만 쓰려고 열어 둔 구멍.
  static Directory? overrideDir;
  static bool memoryOnly = false;

  static Future<File?> _file() async {
    if (memoryOnly) return null;
    try {
      final dir = overrideDir ?? await getApplicationSupportDirectory();
      return File('${dir.path}/doodle_hints.json');
    } catch (_) {
      return null; // 플러그인이 없는 환경(시험) — 메모리만
    }
  }

  /// 파일에서 읽어 온다. 여러 번 불러도 한 번만 읽는다. 못 읽으면 조용히 빈 채로 둔다.
  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _file();
      if (f == null || !await f.exists()) return;
      final j = jsonDecode(await f.readAsString());
      if (j is List) _seen.addAll(j.whereType<String>());
    } catch (_) {}
  }

  static bool seen(String key) => _seen.contains(key);

  /// 봤다고 기록한다(메모리 즉시, 파일은 뒤에서). 이미 기록돼 있으면 아무 일도 안 한다.
  static void markSeen(String key) {
    if (!_seen.add(key)) return;
    () async {
      try {
        final f = await _file();
        if (f == null) return;
        await f.create(recursive: true);
        await f.writeAsString(jsonEncode(_seen.toList()..sort()));
      } catch (_) {}
    }();
  }

  /// 시험용 — 기억을 비우고 처음 상태로.
  static void debugReset() {
    _seen.clear();
    _loaded = false;
    overrideDir = null;
    memoryOnly = false;
  }
}
