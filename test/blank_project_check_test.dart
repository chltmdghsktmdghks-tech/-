// 빈 캔버스(`Project.blank`) — 사용자 결정(2026-09): 장르 송폼을 프로젝트
// 시작의 필수 첫 단계에서 빼고 나중에 고르는 프리셋으로 남긴다.
//   flutter test test/blank_project_check_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';

void main() {
  test('빈 캔버스로 시작한다', () {
    var fail = 0;
    void check(String name, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $name — $detail');
      if (!ok) fail++;
    }

    final p = Project.blank();

    check('1) 트랙 4개(드럼/베이스/코드/멜로디)', p.tracks.length == 4, '${p.tracks.length}개');
    check(
      '2) 씬은 하나뿐, 전부 쉼(패턴 없음)',
      p.scenes.length == 1 && p.scenes.first.clips.values.every((v) => v == null),
      '씬 ${p.scenes.length}개 · clips ${p.scenes.first.clips}',
    );
    check(
      '3) 구간도 하나 — 그 씬을 가리킨다',
      p.song.sections.length == 1 && p.song.sections.first.scene == 0,
      '구간 ${p.song.sections.length}개',
    );
    check(
      '4) 장르가 안 정해져 있다(빈 문자열) — 화면이 "빈 프로젝트"로 알아채는 신호',
      p.genre.isEmpty,
      "genre='${p.genre}'",
    );
    check('5) currentScene 은 안전하게 0 이다', p.currentScene == 0, '${p.currentScene}');
    // `p.scene` 게터가 `scenes[currentScene.clamp(...)]` 로 접근한다 —
    // 씬이 하나라도 있어야 이게 안 죽는다(0개였으면 clamp(0,-1) 에서 죽는다).
    check('6) p.scene 게터가 안 죽는다', p.scene.name == '씬 1', p.scene.name);

    // ignore: avoid_print
    print(fail == 0 ? '빈 캔버스 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
