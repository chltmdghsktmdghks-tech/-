// 두들 빈 시작 (2026-09-29 (12) 1단계) — 장르를 얕게만 입힌다: 씬 1개·패턴 0개.
//   flutter test test/doodle_blank_start_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';

void main() {
  for (final g in ['lofi', 'rock', 'trap', 'waltz', 'jazz']) {
    test('$g: setGenreBare 는 씬·송폼·편성을 안 깐다', () {
      final p = Project.blank();
      p.setGenreBare(g);
      expect(p.genre, g);
      expect(p.scenes.length, 1, reason: '두들은 한 씬만');
      expect(p.scenes.first.clips.values.where((v) => v != null), isEmpty,
          reason: '다른 악기 패턴이 채워지면 안 된다');
      expect(p.tracks.map((t) => t.type).toList(), ['drum', 'bass', 'chord', 'melody']);
      expect(p.scenes.first.bpm, isNotNull, reason: '장르 빠르기는 씬에 얹힌다');
      expect(p.scenes.first.kit, isNotNull);
    });
  }

  test('setGenre(옛 길)는 여러 씬을 깐다 — 두들이 이걸 안 쓰는 이유', () {
    final p = Project.blank()..setGenre('lofi');
    expect(p.scenes.length, greaterThan(1));
  });

  test('박자를 장르가 정한다(왈츠 3/4)', () {
    final p = Project.blank()..setGenreBare('waltz');
    expect(p.meter, '3/4');
    expect(p.spb, 12);
  });
}
