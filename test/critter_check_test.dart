// **씬 캐릭터가 성한가.** (옛 뮤직 두들에서 가져온 이모티콘 서랍)
//   flutter test test/critter_check_test.dart
//
// 캐릭터는 「예쁜가」를 잴 수 없다 — 그건 눈이 본다. 여기서 보는 것은 넷이다:
//  1) **두 목록이 맞나** — `kDefaultCritters`(project.dart)에 없는 id 를 적으면
//     화면에는 아무것도 안 그려지고 **오류도 안 난다**. 이 프로젝트에서 제일 자주
//     나온 병이라 시험으로 묶어 둔다.
//  2) **정말 그려지나** — 좌표를 잘못 옮겨 적으면 빈 그림이 된다.
//  3) **정말 움직이나** — 자세 계산이 어디서 끊기면 박이 지나도 그림이 그대로다.
//     그건 「캐릭터가 있다」가 아니라 「스티커가 붙어 있다」다.
//  4) **씬마다 다른 것이 붙나** — 다 같으면 붙이는 뜻이 없다.
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/critters.dart';

/// 캐릭터 하나를 40×52 로 그려서 **픽셀**을 돌려준다.
Future<List<int>> _px(CritterDef d, double beat) async {
  final rec = ui.PictureRecorder();
  const box = Rect.fromLTWH(0, 0, kCritW, kCritH);
  final c = Canvas(rec, box)..clipRect(box);
  d.draw(c, beat, const Color(0xFFFFFFFF));
  final img = await rec.endRecording().toImage(kCritW.toInt(), kCritH.toInt());
  final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  img.dispose();
  return bd!.buffer.asUint8List().toList();
}

/// 칠해진 픽셀 수(투명하지 않은 것).
int _ink(List<int> px) {
  var n = 0;
  for (var i = 3; i < px.length; i += 4) {
    if (px[i] > 8) n++;
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('씬 캐릭터', () async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $what — $detail');
      if (!ok) fail++;
    }

    // 1) 두 목록이 맞나 — 없는 id 를 기본값으로 쓰면 씬에 아무것도 안 붙는다.
    {
      final missing = kDefaultCritters
          .where((id) => !kCritters.containsKey(id))
          .toList();
      check('1) 기본 목록이 다 있는 캐릭터', missing.isEmpty, '없는 것: $missing');
      check(
        '1-b) 만든 캐릭터를 다 쓴다',
        kDefaultCritters.toSet().length == kCritterList.length,
        '기본 ${kDefaultCritters.toSet().length}종 · 만든 것 ${kCritterList.length}종',
      );
    }

    // 2) 정말 그려지나 — 판의 1% 는 칠해야 하고, 판을 꽉 채우면(90%↑) 그것도 잘못이다.
    {
      final total = (kCritW * kCritH).toInt();
      var worst = '';
      var ok = true;
      for (final d in kCritterList) {
        final n = _ink(await _px(d, 0));
        if (n < total * 0.04 || n > total * 0.9) {
          ok = false;
          worst = '${d.name} $n/$total';
        }
      }
      check('2) 빈 그림이 아니다', ok, ok ? '${kCritterList.length}종 모두' : worst);
    }

    // 3) 정말 움직이나 — 네 자세 중 **셋 이상**이 서로 달라야 한다.
    //    (박마다 통통 뛰는 것만 있는 캐릭터는 0.5박과 1.5박이 같은 자세다)
    {
      var worst = '';
      var ok = true;
      for (final d in kCritterList) {
        final seen = <String>{};
        for (final b in [0.0, 0.5, 1.0, 1.5]) {
          seen.add(base64Encode(await _px(d, b)));
        }
        if (seen.length < 3) {
          ok = false;
          worst = '${d.name} 자세 ${seen.length}가지';
        }
      }
      check('3) 박이 지나면 자세가 바뀐다', ok, ok ? '11종 모두 3가지 이상' : worst);
    }

    // 3-b) 이모지는 그림이 없다 — 서랍에 넣은 값이 캐릭터 id 와 겹치면 안 된다.
    {
      final clash = kCritterEmojis.where(kCritters.containsKey).toList();
      check('3-b) 이모지와 캐릭터가 안 겹친다', clash.isEmpty, '겹침: $clash');
    }

    // 4) 씬마다 다른 것이 붙나 — 장르가 씬을 깔면 순서대로 돌려 붙인다.
    {
      final p = Project.initial()..setGenre('citypop');
      final ids = [for (final s in p.scenes) s.critter];
      check(
        '4) 장르 씬에 캐릭터가 붙는다',
        ids.every((v) => v != null && kCritters.containsKey(v)),
        '$ids',
      );
      check(
        '4-b) 씬마다 다르다',
        ids.toSet().length == ids.length,
        '${ids.length}개 중 ${ids.toSet().length}가지',
      );
    }

    // 5) 씬을 더하면 **아직 안 쓴** 것이 붙는다 — 지금 씬을 그대로 베끼면
    //    캐릭터까지 같아져서 구별하라고 붙인 것이 구별을 못 하게 된다.
    {
      final p = Project.initial()..setGenre('citypop');
      final before = {for (final s in p.scenes) s.critter};
      p.addScene();
      final added = p.scenes.last.critter;
      check(
        '5) 새 씬은 안 쓰던 캐릭터',
        added != null && !before.contains(added),
        '새 씬 $added · 쓰던 것 ${before.length}개',
      );
    }

    // 5-b) 복제는 **그대로 베낀다** — 복사본이니 같은 것이 맞다.
    {
      final p = Project.initial()..setGenre('citypop');
      p.duplicateScene(0);
      check(
        '5-b) 복제는 같은 캐릭터',
        p.scenes[1].critter == p.scenes[0].critter,
        '${p.scenes[0].critter} → ${p.scenes[1].critter}',
      );
    }

    // 6) 저장했다 열면 그대로 — `toJson` 에만 적고 `fromJson` 에서 빠뜨리는 실수.
    {
      final p = Project.initial()..setGenre('citypop');
      p.setSceneCritter(0, '@hero');
      p.setSceneCritter(1, '🔥');
      final q = Project.initial()
        ..loadJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
      check(
        '6) 저장 왕복에 살아남는다',
        q.scenes[0].critter == '@hero' && q.scenes[1].critter == '🔥',
        '${q.scenes[0].critter} · ${q.scenes[1].critter}',
      );
    }

    // 6-b) **뗀 캐릭터는 안 되살아난다** — 씬이 하나뿐인 곡에서도.
    //
    //      여태 「하나도 없으면 옛 파일」로 갈랐다. 그러면 씬 하나짜리 곡에서
    //      그 하나를 떼는 순간 **늘 옛 파일로 보인다** — 저장했다 열 때마다
    //      뗀 것이 되살아났다. 값이 아니라 **칸의 유무**로 가른다.
    //      (막 써 보기가 왕복에서 잡았다. 손으로는 짚어 볼 생각을 못 했던 자리다)
    {
      final p = Project.initial()..setGenre('house');
      while (p.scenes.length > 1) {
        p.removeScene(p.scenes.length - 1);
      }
      p.setSceneCritter(0, null);
      final q = Project.initial()
        ..loadJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
      check(
        '6-1) 뗀 캐릭터는 안 돌아온다 (씬 하나)',
        q.scenes[0].critter == null,
        '${q.scenes[0].critter}',
      );
    }

    // 6-c) 여러 씬에서 **전부** 떼도 마찬가지다
    {
      final p = Project.initial()..setGenre('house');
      for (var i = 0; i < p.scenes.length; i++) {
        p.setSceneCritter(i, null);
      }
      final q = Project.initial()
        ..loadJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
      check(
        '6-2) 전부 떼도 안 돌아온다',
        q.scenes.every((s) => s.critter == null),
        '${q.scenes.map((s) => s.critter).toList()}',
      );
    }

    // 6-e) **캐릭터가 생기기 전에 저장한 곡**에도 채워 준다 — 안 그러면 기존 곡만
    //      계속 비어 있다. 단, 하나라도 있는 파일은 손대지 않는다(뗀 것을 되살리면
    //      「지웠는데 살아났다」가 된다).
    {
      final p = Project.initial()..setGenre('citypop');
      final j = jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>;
      for (final s in (j['scenes'] as List)) {
        (s as Map).remove('critter'); // 옛 파일 흉내
      }
      final old = Project.initial()..loadJson(j);
      check(
        '6-e) 옛 파일에 채워 준다',
        old.scenes.every((s) => s.critter != null),
        '${[for (final s in old.scenes) s.critter]}',
      );

      final j2 = jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>;
      for (final s in (j2['scenes'] as List)) {
        (s as Map)['critter'] = null; // 하나만 남기고 다 뗀 파일
      }
      (j2['scenes'] as List).first['critter'] = '@cat';
      final kept = Project.initial()..loadJson(j2);
      check(
        '6-f) 뗀 것은 되살리지 않는다',
        kept.scenes.first.critter == '@cat' &&
            kept.scenes.skip(1).every((s) => s.critter == null),
        '${[for (final s in kept.scenes) s.critter]}',
      );
    }

    // 6-b) 떼는 길이 있나 — 빈 문자열은 「없음」과 같이 다뤄야 한다
    //      (안 그러면 화면에 아무것도 없는 칸이 자리만 차지한다).
    {
      final p = Project.initial()..setGenre('citypop');
      p.setSceneCritter(0, '');
      check(
        '6-b) 빈 값은 없음',
        p.scenes[0].critter == null,
        '${p.scenes[0].critter}',
      );
      p.setSceneCritter(99, '@cat'); // 없는 씬 — 죽지 않아야 한다
      check('6-c) 없는 씬은 그냥 넘긴다', true, '터지지 않음');
    }

    // 9) **지금 흐르는 구간의 캐릭터** — 곡 화면 눈금 줄과 쇼 화면 무대가 같이 쓴다.
    {
      final p = Project.initial()..setGenre('citypop');
      final secs = <Section>[Section(0, reps: 1), Section(1, reps: 1)];
      final spans = <(double, double)>[(0.0, 8.0), (8.0, 8.0)];
      for (final s in p.scenes) {
        s.bpm = null; // 곡 빠르기를 쓰게 둔다
      }
      final a = critterAt(p.scenes, secs, spans, 0.0, 120);
      final b = critterAt(p.scenes, secs, spans, 9.0, 120);
      check(
        '9) 구간마다 다른 캐릭터',
        a != null && b != null && a.$1 != b.$1,
        '${a?.$1} → ${b?.$1}',
      );
      // 120BPM 이면 한 박이 0.5초 — 9초는 그 구간 시작(8초)에서 1초, 곧 2박.
      check('9-b) 박이 맞는다', b != null && (b.$2 - 2.0).abs() < 1e-9, '${b?.$2}박');
      check(
        '9-c) 구간 밖은 없다',
        critterAt(p.scenes, secs, spans, 99.0, 120) == null,
        '',
      );
      // 씬에 빠르기가 적혀 있으면 **그것**을 쓴다 — 씬마다 빠르기가 다른 곡이 있다.
      p.scenes[1].bpm = 60;
      final c = critterAt(p.scenes, secs, spans, 9.0, 120);
      check(
        '9-d) 씬 빠르기를 쓴다',
        c != null && (c.$2 - 1.0).abs() < 1e-9,
        '${c?.$2}박',
      );
      // 캐릭터를 뗀 씬은 아무것도 안 나온다
      p.scenes[1].critter = null;
      check(
        '9-e) 뗀 씬은 안 나온다',
        critterAt(p.scenes, secs, spans, 9.0, 120) == null,
        '',
      );
      // 없는 씬을 가리키는 구간에도 안 죽는다
      check(
        '9-f) 없는 씬은 그냥 넘긴다',
        critterAt(p.scenes, [Section(99, reps: 1)], [(0.0, 8.0)], 1.0, 120) ==
            null,
        '',
      );
    }

    // 7) 이름표 — 메뉴에 「지금 무엇이 붙어 있나」를 보여 준다.
    {
      check(
        '7) 이름표',
        critterName(null) == '없음' &&
            critterName('@cat') == '고양이' &&
            critterName('🔥') == '🔥',
        '${critterName(null)} · ${critterName('@cat')} · ${critterName('🔥')}',
      );
    }

    expect(fail, 0, reason: '$fail개 항목이 어긋났습니다');
  });
}
