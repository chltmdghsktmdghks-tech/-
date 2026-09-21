// **망가진 저장 파일이 앱을 죽이지 못하게 한다.**
//   flutter test test/bad_file_test.dart
//
// 저장 파일은 앱 밖에 있다 — 옛 버전이 쓴 것, 새 버전이 쓴 것, 반쯤 쓰다 만 것,
// 손으로 고친 것이 다 들어온다. 그중 하나라도 **터지면 앱이 안 뜬다**:
// 마지막에 열던 곡을 자동으로 열기 때문이다. 소리가 조금 다른 것과
// 아무것도 못 하는 것은 급이 다르다.
//
// 실제로 조(mode)가 그랬다 — 모르는 값 하나면 `kScale[mode]!` 에서 터졌다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/store.dart';
import 'package:music_doodle_engine/theory.dart';

void main() {
  test('망가진 저장 파일', () async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    /// 터지지 않으면 통과. 값이 이상해도 **소리는 나야** 한다.
    void survives(String what, void Function() f) {
      try {
        f();
        check(what, true, '안 터짐');
      } catch (e) {
        check(what, false, '$e');
      }
    }

    Map<String, dynamic> base() => Project.initial().toJson();

    survives('1) 모르는 스타일', () {
      Project.initial().loadJson(base()..['genre'] = 'polka');
    });
    survives('1-b) 모르는 스타일로 바꾸기', () => Project.initial().setGenre('polka'));

    // 여기가 실제로 터지던 자리다
    survives('2) 모르는 조', () {
      SceneSequencer.build(Project.initial(), Transport()..mode = 'lydian');
    });
    check(
      '2-b) 모르는 조는 단조로 본다',
      scaleOf('lydian').join(',') == kScale['minor']!.join(','),
      '되돌아갈 곳',
    );

    survives('3) 모르는 인서트', () {
      final j = base();
      (j['tracks'] as List)[0]['fx'] = [
        {'type': 'flanger', 'on': true, 'p': <String, dynamic>{}},
      ];
      SceneSequencer.build(Project.initial()..loadJson(j), Transport());
    });

    survives('4) 모르는 음색', () {
      final j = base();
      (j['tracks'] as List)[3]['voice'] = 'theremin';
      SceneSequencer.build(Project.initial()..loadJson(j), Transport());
    });

    survives('5) 모르는 드럼 키트', () {
      final j = base();
      (j['tracks'] as List)[0]['kit'] = 'gamelan';
      SceneSequencer.build(Project.initial()..loadJson(j), Transport());
    });

    survives('6) 곡이 없는 씬을 가리킴', () {
      final j = base();
      (j['song'] as List).add({'scene': 99, 'reps': 2});
      SceneSequencer.buildSong(Project.initial()..loadJson(j), Transport());
    });

    // 7) **파일을 통째로 망가뜨려 놓고 진짜로 열어 본다.**
    //    위는 메모리 안에서만 본 것이고, 여기는 Store 가 읽는 길을 그대로 탄다.
    {
      final dir = await Directory.systemTemp.createTemp('mdbad');
      final p = Project.initial();
      final tr = Transport();
      final st = Store(
        project: p,
        transport: tr,
        live: LiveChannel(),
        master: MasterChannel(),
        overrideDir: dir,
      );
      await st.start();
      await st.saveNow();
      final id = st.currentId!;
      st.detach();

      final f = File('${dir.path}/songs/$id.json');
      // **글자로 고친다.** `jsonEncode` 는 NaN 을 거부하므로 코드로는 못 만드는데,
      // 파일이 반쯤 쓰이다 말거나 손으로 고쳐지면 무엇이든 들어올 수 있다.
      final j = Map<String, dynamic>.from(
        jsonDecode(await f.readAsString()) as Map,
      );
      j.remove('mode');
      j.remove('bpm');
      j.remove('root');
      final raw = jsonEncode(j);
      await f.writeAsString(
        '${raw.substring(0, raw.length - 1)},'
        '"mode":"lydian","bpm":0,"root":999}',
      );

      final p2 = Project.initial();
      final tr2 = Transport();
      final st2 = Store(
        project: p2,
        transport: tr2,
        live: LiveChannel(),
        master: MasterChannel(),
        overrideDir: dir,
      );
      await st2.start();
      await st2.open(id);
      var ok = false;
      try {
        SceneSequencer.build(p2, tr2);
        ok = true;
      } catch (_) {}
      check(
        '7) 망가진 파일을 열어도 소리가 난다',
        ok &&
            kScale.containsKey(tr2.mode) &&
            tr2.bpm >= 20 &&
            tr2.bpm <= 300 && // 0BPM 이면 곡이 영원히 안 끝난다
            tr2.root >= 0 &&
            tr2.root < 12,
        '조 ${tr2.mode} · ${tr2.bpm.round()}BPM · 루트 ${tr2.root}',
      );
      st2.detach();
      await dir.delete(recursive: true);
    }

    // ignore: avoid_print
    print(fail == 0 ? '망가진 파일 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
