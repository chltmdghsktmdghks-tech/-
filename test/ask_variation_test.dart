// 질문해서 만들기 — 같은 답이어도 pick 에 따라 결과가 갈리는가 (2026-09-29 (9)).
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/ask_song.dart';
import 'package:music_doodle_engine/instruments.dart';

Map<String, String> _a() => {
  'mood': 'calm', 'scene': 'cafe', 'speed': 'mid', 'power': 'mid2',
  'lead': 'warm', 'low': 'bounce', 'drum': 'normal', 'space': 'room2',
  'len': 'm', 'edge': 'clean',
};

void main() {
  test('pick 0 은 예전 그대로(1등·첫 악기·빠르기 그대로)', () {
    final r = askRecipe(_a());
    expect(r.leadVoice, 'sax');
    expect(r.lowVoice, 'fingerbass');
  });

  test('pick 을 바꾸면 조·빠르기·악기·뼈대 중 뭔가는 달라진다', () {
    final sigs = <String>{};
    for (var k = 0; k < 200; k += 7) {
      final r = askRecipe(_a(), pick: k);
      sigs.add('${r.genre}|${r.root}|${r.bpm.round()}|${r.leadVoice}|${r.lowVoice}');
    }
    expect(sigs.length, greaterThan(6));
  });

  test('바뀐 값은 늘 유효하다 — 악기 이름·빠르기 범위', () {
    for (final lead in ['voice', 'bell', 'warm', 'synth']) {
      for (final low in ['deep', 'bounce', 'soft']) {
        for (var k = 0; k < 400; k += 3) {
          final r = askRecipe(_a()..['lead'] = lead..['low'] = low, pick: k);
          expect(VOICE_LABEL.containsKey(r.leadVoice), isTrue, reason: '${r.leadVoice}');
          expect(VOICE_LABEL.containsKey(r.lowVoice), isTrue, reason: '${r.lowVoice}');
          expect(r.bpm, inInclusiveRange(60, 180));
        }
      }
    }
  });

  test('답이 갈라놓은 방향은 흔들려도 유지 — 빠르게 vs 느리게', () {
    for (var k = 0; k < 60; k += 5) {
      final fast = askRecipe(_a()..['speed'] = 'fast', pick: k).bpm;
      final still = askRecipe(_a()..['speed'] = 'still', pick: k).bpm;
      expect(fast, greaterThan(still));
    }
  });
}
