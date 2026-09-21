// 프로젝트 카드 미리보기 확인 — `Store.sceneActiveOf`/`timelineScenesOf`
// (곡 파일을 열지 않고 카드를 그리는 데 쓰는 값들).
//   flutter test test/card_preview_check_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/store.dart';

Store _store(Directory dir, Project p) => Store(
  project: p,
  transport: Transport(),
  live: LiveChannel(),
  master: MasterChannel(),
  overrideDir: dir,
);

void main() {
  test('카드 미리보기 값', () async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    // 1) 씬 미리보기 — 패턴이 있는 트랙 타입만 켜짐으로 나온다
    final p = Project.initial(); // 트랙 넷(드럼·베이스·코드·멜로디) 다 기본 패턴이 있다
    for (final t in p.tracks) {
      // 베이스만 꺼 둔다 — 나머지 셋은 만들 때 기본 패턴 그대로 켜져 있다
      if (t.type == 'bass') t.pattern = null;
    }
    final sa = Store.sceneActiveOf(p);
    check(
      '1) 씬 미리보기 — 패턴 없는 악기만 꺼짐(베이스)',
      sa.length == kPreviewTrackTypes.length &&
          sa[kPreviewTrackTypes.indexOf('drum')] == true &&
          sa[kPreviewTrackTypes.indexOf('bass')] == false,
      '$sa',
    );

    // 2) 타임라인 미리보기 — 구간 이름이 순서대로
    final p2 = Project.initial();
    final tl = Store.timelineScenesOf(p2);
    check(
      '2) 타임라인 미리보기 — 씬 이름 순서대로',
      tl.length == p2.scenes.length &&
          tl.every((n) => n.isNotEmpty),
      '$tl',
    );

    // 3) 저장하면 SongMeta 에 실제로 담긴다(목록 화면이 곡 파일을 안 열고도
    //    쓸 수 있는 값이 된다)
    final dir = await Directory.systemTemp.createTemp('mdpreview');
    final proj = Project.initial();
    final st = _store(dir, proj);
    await st.start();
    await st.saveNow();
    final meta = st.current!;
    check(
      '3) 저장하면 메타에 담긴다',
      meta.sceneActive != null &&
          meta.sceneActive!.length == kPreviewTrackTypes.length &&
          meta.timelineScenes != null &&
          meta.timelineScenes!.isNotEmpty,
      '악기 ${meta.sceneActive} · 구간 ${meta.timelineScenes}',
    );

    // 4) index.json 에 쓰고 다시 읽어도 값이 그대로다(JSON 왕복)
    final dir2 = await Directory.systemTemp.createTemp('mdpreview2');
    final proj2 = Project.initial();
    final st2 = _store(dir2, proj2);
    await st2.start();
    await st2.saveNow();
    final st2b = _store(dir2, Project.blank());
    await st2b.start();
    final metaB = st2b.songs.first;
    check(
      '4) 다시 읽어도 그대로',
      metaB.sceneActive != null && metaB.timelineScenes != null,
      '악기 ${metaB.sceneActive} · 구간 ${metaB.timelineScenes}',
    );

    // ignore: avoid_print
    print(fail == 0 ? '카드 미리보기 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
