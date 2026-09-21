// 5단계 14/N — 라이브 녹음 확인.
//   flutter test test/live_rec_test.dart
//
// 녹음은 **틀렸는지 알기 어려운** 기능이다. 한 칸씩 밀려 담겨도 다시 들으면
// "내가 그렇게 쳤나 보다" 싶고, 판 경계에서 흘린 음은 아예 없었던 일이 된다.
// 그래서 숫자로 본다: 어디에 담기는가 · 늦음을 되돌리는가 · 판을 넘으면 감기는가 ·
// **담은 게 실제로 소리가 나는가**(트랙에 실어 시퀀서까지 돌려 본다).
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/live_ops.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';

void main() {
  test('라이브 녹음', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    // 4마디(64칸) · 8초짜리 판 = 한 칸 0.125초
    const steps = 64;
    const loopSec = 8.0;

    // 1) 박에 맞춰 담긴다 — 조금 이르거나 늦게 쳐도 가장 가까운 칸으로
    final r1 = LiveRecorder(steps: steps, loopSec: loopSec);
    r1.hit(0, 0.0); // 딱 맞게
    r1.hit(1, 4.2 / steps / 1.0 * 1); // 4번 칸보다 살짝 뒤
    r1.hit(2, 7.6 / steps); // 8번 칸에 가깝다
    final n1 = r1.notes();
    check(
      '1) 박에 맞춤',
      n1.length == 3 && n1[0][1] == 0 && n1[1][1] == 4 && n1[2][1] == 8,
      '칸 ${[for (final n in n1) n[1]].join(' ')} (4.2→4, 7.6→8)',
    );

    // 2) 늦게 잡히는 것을 되돌린다 — 귀에 닿는 소리는 앞질러 만든 양만큼 늦다.
    //    되돌리지 않으면 **판 전체가 한 칸씩 밀린 채로** 담긴다.
    const lat = 0.064; // 64ms = 반 칸보다 조금 크다(한 칸 0.125초)
    final late = LiveRecorder(steps: steps, loopSec: loopSec, latencySec: lat);
    final raw = LiveRecorder(steps: steps, loopSec: loopSec);
    final feltOnBeat = (16 * 0.125 + lat) / loopSec; // 16번 칸이라고 느끼며 친 시각
    late.hit(0, feltOnBeat);
    raw.hit(0, feltOnBeat);
    check(
      '2) 늦음 되돌리기',
      late.notes().first[1] == 16 && raw.notes().first[1] == 17,
      '되돌림 ${late.notes().first[1]}번 칸 · 안 되돌리면 ${raw.notes().first[1]}번 칸',
    );

    // 3) 같은 자리를 다시 치면 덮어쓴다(겹쳐 녹음) — 안 그러면 판이 돌 때마다 음이 쌓인다
    final r3 = LiveRecorder(steps: steps, loopSec: loopSec);
    for (var i = 0; i < 5; i++) {
      r3.hit(3, 12 / steps);
    }
    check('3) 겹쳐 녹음', r3.count == 1, '5번 쳤는데 ${r3.count}음');

    // 4) 판을 넘어가면 감긴다 — 아르페지오 꼬리가 판 끝을 넘을 때 사라지면 안 된다
    final r4 = LiveRecorder(steps: steps, loopSec: loopSec);
    r4.hit(5, 1.02); // 판 길이의 102% 지점
    check(
      '4) 판 넘어가면 감김',
      r4.notes().first[1] == 1,
      '1.02 → ${r4.notes().first[1]}번 칸',
    );

    // 5) 담은 게 **소리가 난다** — 트랙에 실어 시퀀서까지 돌려 본다
    final p = Project.initial();
    final t = p.ensureLiveTrack('bell');
    final rec = LiveRecorder(steps: steps, loopSec: loopSec);
    for (var i = 0; i < 8; i++) {
      rec.hit(i % 7, (i * 8) / steps);
    }
    const name = '라이브 코러스';
    p.putUserPattern(
      'melody',
      name,
      note: NotePatternDef(name, 4, 4, rec.notes()),
    );
    p.setClip(t, name);
    final b = SceneSequencer.build(p, Transport(), reps: 1);
    final part = b.busNames.indexOf(t.id);
    final mine = [
      for (final n in b.notes)
        if (n[7] == part) n,
    ];
    check(
      '5) 담은 게 소리가 난다',
      mine.length == 8 && mine.every((n) => n[0] == 'bell'),
      '${mine.length}음 · 음색 ${mine.isEmpty ? '-' : mine.first[0]}',
    );

    // 6) 라이브 트랙은 **다른 씬을 안 건드린다** — 인트로에서 친 게 코러스에도 나오면 사고
    final others = [
      for (var i = 0; i < p.scenes.length; i++)
        if (i != p.currentScene) p.scenes[i].clips[t.id],
    ];
    check(
      '6) 다른 씬은 조용',
      others.every((c) => c == null) &&
          p.scenes[p.currentScene].clips[t.id] == name,
      '지금 씬 $name · 나머지 ${others.length}개 전부 비어 있음',
    );

    // 7) 다시 녹음해도 트랙은 하나 — 칠 때마다 트랙이 늘면 열 번 치고 트랙이 열 개다
    final before = p.tracks.length;
    final t2 = p.ensureLiveTrack('sax');
    check(
      '7) 트랙은 하나',
      identical(t, t2) && p.tracks.length == before,
      '트랙 ${p.tracks.length}개 · 음색 ${t2.voice}(새로 고른 것)',
    );

    // 8) 저장·불러오기 왕복 — 앱을 껐다 켜도 남아 있어야 한다
    final back = Project.initial()..loadJson(p.toJson());
    final liveTrack = back.tracks
        .where((x) => x.name == kLiveTrackName)
        .toList();
    final kept = back.findNote('melody', name);
    check(
      '8) 저장 왕복',
      liveTrack.length == 1 && kept != null && kept.notes.length == 8,
      '트랙 ${liveTrack.length}개 · 음 ${kept?.notes.length}개',
    );

    // ignore: avoid_print
    print(fail == 0 ? '라이브 녹음 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
