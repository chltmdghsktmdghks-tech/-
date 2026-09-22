// 씬 한 판을 **몇 마디로** 할 것인가.
//   flutter test test/scene_bars_test.dart
//
// 씬 길이는 따로 저장된 값이 아니라 **그 씬에서 들리는 제일 긴 패턴**이다
// (`SceneSequencer.sceneLoopBars`). 그래서 "씬을 4마디로" 는 곧 "이 씬이 쓰는
// 판들을 다 4마디로" 다 — 한 트랙만 바꾸면 제일 긴 것이 그대로 남아
// **아무 일도 안 일어난 것처럼 보인다.** 조용히 안 바뀌는 종류라 숫자로 잰다.

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';

void main() {
  int loopBars(Project p) =>
      SceneSequencer.sceneLoopBars(p, p.currentScene);

  test('늘리면 씬이 길어진다', () {
    final p = Project.initial()..setGenre('lofi');
    final before = loopBars(p);
    // ignore: avoid_print
    print('처음 $before마디');
    final changed = p.setSceneBars(8);
    // ignore: avoid_print
    print('8마디로 → 바꾼 트랙 $changed개 · 이제 ${loopBars(p)}마디');
    expect(changed, greaterThan(0), reason: '바꾼 트랙이 없으면 뜻이 없다');
    expect(loopBars(p), 8);
  });

  test('줄이면 씬이 짧아진다 — 제일 긴 판까지 같이 줄어야 한다', () {
    final p = Project.initial()..setGenre('lofi');
    p.setSceneBars(8);
    expect(loopBars(p), 8);
    p.setSceneBars(2);
    // ignore: avoid_print
    print('2마디로 → ${loopBars(p)}마디');
    expect(loopBars(p), 2, reason: '한 트랙이라도 길게 남으면 씬은 안 줄어든다');
  });

  test('1~8 밖은 잘린다', () {
    final p = Project.initial()..setGenre('lofi');
    p.setSceneBars(99);
    expect(loopBars(p), 8);
    p.setSceneBars(0);
    expect(loopBars(p), 1);
  });

  test('줄였다 늘려도 판이 깨지지 않는다', () {
    final p = Project.initial()..setGenre('lofi');
    p.setSceneBars(1);
    p.setSceneBars(4);
    expect(loopBars(p), 4);
    // 들리는 트랙이 여전히 소리를 낼 판을 갖고 있어야 한다.
    var withClip = 0;
    for (final t in p.tracks) {
      final c = p.scene.clips[t.id];
      if (c != null && p.audible(t)) withClip++;
    }
    // ignore: avoid_print
    print('줄였다 늘린 뒤 — 판을 가진 들리는 트랙 $withClip개');
    expect(withClip, greaterThan(0), reason: '판이 통째로 날아가면 안 된다');
  });

  test('같은 마디를 다시 넣으면 아무것도 안 바꾼다', () {
    final p = Project.initial()..setGenre('lofi');
    final n = loopBars(p);
    expect(p.setSceneBars(n), 0, reason: '헛일을 하면 되돌리기·자동저장만 시끄럽다');
  });

  test('음소거된 트랙은 안 건드린다 — 씬 길이에 안 들어가니까', () {
    final p = Project.initial()..setGenre('lofi');
    // 가락을 재운다.
    final mel = p.tracks.firstWhere((t) => t.type == 'melody');
    mel.mute = true;
    final before = p.barsOf(mel.type, p.scene.clips[mel.id]);
    p.setSceneBars(1);
    final after = p.barsOf(mel.type, p.scene.clips[mel.id]);
    // ignore: avoid_print
    print('재운 가락 — $before마디 → $after마디');
    expect(after, before, reason: '안 들리는 트랙까지 자르면 켰을 때 잘려 있다');
  });
}
