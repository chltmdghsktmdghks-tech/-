// 샘플곡 심기 확인 — `Store(seedSamples: true)` 가 처음 켤 때 딱 한 번
// 진짜 파일을 써내는지, 다음 시작에서는 다시 안 심는지.
//   flutter test test/sample_seed_check_test.dart
//
// 위젯을 안 띄우니 `test()` 를 쓴다 — `testWidgets()` 는 가짜 시계 위에서
// 돈다(`tester.runAsync` 로 감싼 안에서만 진짜 비동기 I/O 가 진행된다).
// 여기 `Directory.systemTemp.createTemp` 를 그 밖에서 부르면 시계가 절대
// 안 흘러 테스트가 걸린다(먼저 그렇게 짰다가 10분 타임아웃으로 잡혔다).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/store.dart';

void main() {
  test('샘플곡 심기', () async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final dir = await Directory.systemTemp.createTemp('mdseed');
    addTearDown(() => dir.delete(recursive: true));

    // 1) 빈 저장소에서 처음 켠다 — 샘플곡 6개 + 테스트 곡 1개.
    final st1 = Store(
      project: Project.initial(),
      transport: Transport(),
      live: LiveChannel(),
      master: MasterChannel(),
      overrideDir: dir,
      seedSamples: true,
    );
    await st1.start();
    check('1) 곡 7개(샘플 6 + 테스트 1)', st1.songs.length == 7, '${st1.songs.length}개');
    final samples = st1.songs.where((s) => s.sample).toList();
    check('2) 샘플곡 6개', samples.length == 6, '${samples.length}개');
    final nonSamples = st1.songs.where((s) => !s.sample).toList();
    check(
      '3) 테스트 곡 1개, 이름 「테스트」',
      nonSamples.length == 1 && nonSamples.first.name == '테스트',
      '${nonSamples.map((s) => s.name).toList()}',
    );
    check(
      '4) 지금 열린 곡이 테스트 곡',
      st1.currentId == nonSamples.first.id,
      '${st1.currentId} vs ${nonSamples.first.id}',
    );

    // 2-b) 샘플곡을 열었다 저장해도 이름이 안 바뀐다 — `Project.initial()`
    // 기본값('새 곡')이 곡 파일 안에 그대로 남아 있으면, 열어서 한 번만
    // 저장돼도(`saveNow` 가 `meta.name = project.name` 으로 되돌린다) 목록
    // 이름이 "새 곡"으로 덮어써진다(실기기에서 직접 열어 보고서야 잡았다).
    final lofiSample = samples.firstWhere((s) => s.name == '로파이 샘플');
    await st1.open(lofiSample.id);
    check(
      '2-b) 연 곡의 프로젝트 이름표도 맞다',
      st1.project.name == '로파이 샘플',
      st1.project.name,
    );
    await st1.saveNow();
    final after = st1.songs.firstWhere((s) => s.id == lofiSample.id);
    check(
      '2-c) 열었다 저장해도 목록 이름이 그대로',
      after.name == '로파이 샘플',
      after.name,
    );

    // 2) 다시 켠다(같은 폴더) — 또 심으면 13개가 된다. 그러면 안 된다.
    final st2 = Store(
      project: Project.initial(),
      transport: Transport(),
      live: LiveChannel(),
      master: MasterChannel(),
      overrideDir: dir,
      seedSamples: true,
    );
    await st2.start();
    check('5) 다시 켜도 그대로 7개(또 안 심는다)', st2.songs.length == 7, '${st2.songs.length}개');

    // 3) seedSamples: false(시험 기본값과 같은 조건)면 아예 안 심는다 —
    //    빈 폴더에서 시작하면 예전처럼 기본 곡 1개.
    final dir2 = await Directory.systemTemp.createTemp('mdseed2');
    addTearDown(() => dir2.delete(recursive: true));
    final st3 = Store(
      project: Project.initial(),
      transport: Transport(),
      live: LiveChannel(),
      master: MasterChannel(),
      overrideDir: dir2,
    );
    await st3.start();
    check(
      '6) seedSamples 꺼져 있으면(시험 기본값) 곡 1개뿐',
      st3.songs.length == 1 && !st3.songs.first.sample,
      '${st3.songs.length}개',
    );

    // ignore: avoid_print
    print(fail == 0 ? '샘플곡 심기 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
