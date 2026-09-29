// 재현 테스트 — 망가진 곡을 열려다 실패하면 **지금 열려 있던 곡 파일이 오염된다**
// (감사 2026-09-29). 아직 안 고쳐진 버그라 이 시험은 **실패하는 게 정상**이다.
//   flutter test test/open_bad_song_keeps_current_test.dart
//
// `Store.open`(store.dart ~620)은 `project.loadJson(j)` 가 중간에 터져도 catch 에서
// 로그만 찍고 돌아온다. 그런데 `loadJson` 은 이름·장르·트랙을 **먼저 갈아 끼우고**
// 나중에 `scenes` 를 읽는다 — 그래서 `scenes` 가 없는 파일이면 이미 B 의 이름·트랙이
// 메모리에 얹힌 채인데 `currentId` 는 그대로 A 다. 다음 자동 저장(`touch`→`saveNow`)이
// **A 의 파일에 B 의 반쪽 상태를 덮어쓴다.** `bad_file_test` 는 열어서 소리가 나는지만
// 보고, 열기 실패 뒤의 저장은 안 본다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/store.dart';

void main() {
  test('열기에 실패해도 A 곡 파일은 A 곡 그대로', () async {
    final dir = await Directory.systemTemp.createTemp('mdopenbad');
    final p = Project.initial();
    final st = Store(
      project: p,
      transport: Transport(),
      live: LiveChannel(),
      master: MasterChannel(),
      overrideDir: dir,
    );
    await st.start();
    p.name = 'A곡';
    await st.saveNow();
    final idA = st.currentId!;
    await st.newSong(name: 'B곡');
    final idB = st.currentId!;
    await st.saveNow();

    // B 파일을 반쯤 망가뜨린다 — 이름·트랙은 있는데 씬이 없다.
    final fb = File('${dir.path}/songs/$idB.json');
    final jb = Map<String, dynamic>.from(jsonDecode(await fb.readAsString()) as Map)
      ..remove('scenes');
    await fb.writeAsString(jsonEncode(jb));

    // 저장하며 열면 방금 망가뜨린 B 파일을 멀쩡한 내용으로 되살려 버린다.
    await st.open(idA, saveCurrent: false);
    expect(p.name, 'A곡');
    await st.open(idB); // 실패해야 정상 — 그리고 A 는 무사해야 한다
    await st.saveNow(); // 자동 저장이 곧 부르는 것

    final fa = File('${dir.path}/songs/$idA.json');
    final ja = jsonDecode(await fa.readAsString()) as Map;
    st.detach();
    expect(ja['name'], 'A곡', reason: 'A 파일이 B 의 반쪽 상태로 덮였다: name=${ja['name']}');
  });
}
