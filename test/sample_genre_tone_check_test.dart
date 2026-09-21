// 샘플곡에도 장르 인서트·믹스가 걸리는지 확인 — 사용자 요청(2026-09-13):
// "더 풍부하고 완성도 있게 플러그인 사용하고 마스터링도 잘 해놔".
//   flutter test test/sample_genre_tone_check_test.dart
//
// 샘플곡은 `Project.setGenre` 를 안 쓰고 `genre` 필드만 바로 넣는다(씬
// 프리셋 대신 타임라인 레인을 손수 짜므로) — 그래서 그때까지는
// `Project.applyGenreTone()` 을 부르지 않으면 장르별 인서트(`genre_fx.dart`)
// ·믹스(`kGenreMix`)가 하나도 안 걸리고 전부 기본값(볼륨 1.0·인서트 없음)
// 으로 났다. `song_samples.dart` 의 각 샘플에 `applyGenreTone()` 호출을
// 추가했다 — 여기서 실제로 걸렸는지 본다.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genre_fx.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/song_samples.dart';

void main() {
  test('샘플곡 — 장르 인서트가 실제로 걸린다', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final defs = buildSampleSongs();
    for (final def in defs) {
      final p = Project.initial();
      def.customize(p);

      for (final t in p.tracks) {
        final want = genreFxFor(p.genre, t.type);
        if (want.isEmpty) continue; // 이 장르·슬롯엔 원래 안 건다(재즈처럼)
        check(
          '${def.name} · ${t.type} — 인서트 ${want.length}개 걸림',
          t.chain.length == want.length &&
              t.chain.every((f) => want.any((w) => w.type == f.type)),
          '실제 ${t.chain.map((f) => f.type).toList()} · 기대 ${want.map((w) => w.type).toList()}',
        );
      }
    }

    expect(fail, 0);
  });
}
