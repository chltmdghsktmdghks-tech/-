// Phase 1 — **저장했다 다시 열면 그대로인가.** (개선 계획 3-5)
//   flutter test test/save_roundtrip_test.dart
//
// `store_check_test` 는 곡을 여러 개 오갈 때 섞이지 않는지를 본다.
// 여기서는 **한 곡 안의 모든 값**이 왕복에서 살아남는지를 항목별로 본다 —
// 프로젝트가 커질수록 새 필드를 `toJson` 에만 적고 `fromJson` 에서 빠뜨리는 실수가
// 생기는데, 그러면 사용자가 만진 것이 **아무 소리 없이** 사라진다.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/feel.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';

void main() {
  test('저장 왕복', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $what — $detail');
      if (!ok) fail++;
    }

    // ── 만질 수 있는 것은 다 만져 둔다 ──
    final p = Project.initial()
      ..setGenre('citypop')
      ..name = '왕복 시험곡';
    final t0 = p.tracks.first; // 드럼
    final t1 = p.tracks[1];
    t0.vol = 0.42;
    t0.pan = -0.3;
    t0.rev = 0.27;
    t0.eq.lo = 2.5;
    t0.eq.mid = -1.5;
    t0.eq.hi = 3.0;
    t0.mute = true;
    t1.vol = 1.15;
    t1.solo = true;
    t1.voice = 'moogbass';

    // 인서트(플러그인) — 값까지 확인한다
    p.setFeel(
      const Feel(energy: 0.8, density: 0.25, groove: 0.7, fill: 0.9, vary: 0.3),
    );

    t1.addFx('amp');
    t1.setFxParam(0, 'mode', 2);
    t1.setFxParam(0, 'gain', 0.73);
    t1.addFx('delay');
    t1.setFxOn(1, false);

    // 내가 고친 패턴 — 드럼 타격과 세기
    final mine = p.makeEditable(t0);
    final d0 = p.userDrum[mine]!;
    p.userDrum[mine] = DrumPatternDef(
      d0.name,
      d0.bars,
      d0.src,
      {
        ...d0.hits,
        'kick': [0, 6, 12],
      },
      {
        'kick': [3, 1, 2],
      },
    );

    // 음정 패턴 — 음 하나하나
    final mel = p.tracks.firstWhere((t) => t.type == 'melody');
    final mineMel = p.makeEditable(mel);
    p.userNote[mineMel]!.notes
      ..clear()
      ..addAll([
        [4, 0, 6, 3],
        [5, 8, 2, 2],
        [7, 12, 4, 1],
      ]);

    // 곡 구성
    p.song.sections.clear();
    p.song.add(1);
    p.song.sections.last.reps = 3;
    p.song.add(0);
    p.song.sections.last.reps = 2;

    // ── 왕복 ──
    final raw = jsonEncode(p.toJson());
    final back = Project.initial()
      ..loadJson(jsonDecode(raw) as Map<String, dynamic>);

    check(
      '0) 버전 필드',
      (jsonDecode(raw) as Map)['v'] == 1,
      "v=${(jsonDecode(raw) as Map)['v']}",
    );
    check(
      '1) 이름·스타일',
      back.name == p.name && back.genre == p.genre,
      '${back.name} · ${back.genre}',
    );
    check(
      '2) 트랙 수',
      back.tracks.length == p.tracks.length,
      '${back.tracks.length}/${p.tracks.length}',
    );

    final b0 = back.tracks.first, b1 = back.tracks[1];
    check(
      '3) 믹서 값',
      (b0.vol - 0.42).abs() < 1e-9 &&
          (b0.pan + 0.3).abs() < 1e-9 &&
          (b0.rev - 0.27).abs() < 1e-9 &&
          (b0.eq.lo - 2.5).abs() < 1e-9 &&
          (b0.eq.mid + 1.5).abs() < 1e-9 &&
          (b0.eq.hi - 3.0).abs() < 1e-9,
      '볼륨 ${b0.vol} · 팬 ${b0.pan} · 잔향 ${b0.rev} · EQ ${b0.eq.lo}/${b0.eq.mid}/${b0.eq.hi}',
    );
    check('4) 뮤트·솔로', b0.mute && b1.solo, '뮤트 ${b0.mute} · 솔로 ${b1.solo}');
    check('5) 음색', b1.voice == 'moogbass', b1.voice);

    check(
      '6) 인서트 — 종류·순서·켜짐',
      b1.chain.length == 2 &&
          b1.chain[0].type == 'amp' &&
          b1.chain[1].type == 'delay' &&
          b1.chain[1].on == false,
      '${[for (final f in b1.chain) '${f.type}${f.on ? '' : '(꺼짐)'}'].join(' → ')}',
    );
    check(
      '7) 인서트 — 손잡이 값',
      b1.chain[0].p['mode'] == 2 &&
          (b1.chain[0].p['gain']! - 0.73).abs() < 1e-9,
      '성향 ${b1.chain[0].p['mode']} · 게인 ${b1.chain[0].p['gain']}',
    );

    final bd = back.userDrum[mine];
    check(
      '8) 내가 찍은 드럼 — 자리와 세기',
      bd != null &&
          bd.hits['kick']?.join(',') == '0,6,12' &&
          bd.vels?['kick']?.join(',') == '3,1,2',
      bd == null ? '패턴이 사라짐' : '자리 ${bd.hits['kick']} · 세기 ${bd.vels?['kick']}',
    );

    final bn = back.userNote[mineMel];
    check(
      '9) 내가 찍은 음 — 높이·자리·길이·세기',
      bn != null &&
          bn.notes.length == 3 &&
          bn.notes[0].join(',') == '4,0,6,3' &&
          bn.notes[2].join(',') == '7,12,4,1',
      bn == null ? '패턴이 사라짐' : '${bn.notes.length}음 · 첫 음 ${bn.notes[0]}',
    );

    // 9-b) **어느 트랙 타입에서 만들었는지**도 왕복에서 살아남아야 한다.
    // 이게 없으면(=타입을 잊으면) 이 멜로디 패턴이 베이스·코드 고르기에도
    // 다시 뜬다 — 저장은 됐는데 지킴은 풀린, 조용한 회귀다.
    check(
      '9-b) 내가 만든 패턴의 타입도 왕복에서 산다',
      back.userNoteType[mineMel] == 'melody',
      '${back.userNoteType[mineMel]} (바라는 값 melody)',
    );

    check(
      '10) 곡 구성',
      back.song.sections.length == 2 &&
          back.song.sections[0].scene == 1 &&
          back.song.sections[0].reps == 3 &&
          back.song.sections[1].scene == 0 &&
          back.song.sections[1].reps == 2,
      back.song.sections.map((s) => '${s.scene}번×${s.reps}판').join(' → '),
    );

    // 10-b) 느낌 손잡이 다섯 (계획 4-4 · 6-1 · 6-2)
    //  이게 없으면 사용자가 맞춰 둔 분위기가 **아무 소리 없이** 초기값으로 돌아온다.
    check(
      '10-b) 느낌 손잡이',
      back.feel.energy == 0.8 &&
          back.feel.density == 0.25 &&
          back.feel.groove == 0.7 &&
          back.feel.fill == 0.9 &&
          back.feel.vary == 0.3,
      '기운 ${back.feel.energy} · 빽빽 ${back.feel.density} · 그루브 ${back.feel.groove} · '
          '매듭 ${back.feel.fill} · 변화 ${back.feel.vary}',
    );

    // 11) **두 번 왕복해도 같은가** — 한 번은 우연히 맞을 수 있다
    final raw2 = jsonEncode(back.toJson());
    check(
      '11) 두 번째 왕복도 같다',
      raw2 == raw,
      raw2 == raw
          ? '${raw.length}자 완전 일치'
          : '길이 ${raw.length} vs ${raw2.length}',
    );

    // 12) **모르는 필드가 있어도** 죽지 않는다(앞으로 필드가 늘어날 것이다)
    final future = jsonDecode(raw) as Map<String, dynamic>;
    future['someNewThing'] = {'a': 1};
    future['v'] = 99;
    var survived = true;
    try {
      Project.initial().loadJson(future);
    } catch (e) {
      survived = false;
    }
    check('12) 모르는 필드·새 버전에도 안 죽는다', survived, survived ? 'v99 도 읽힘' : '예외 발생');

    // ignore: avoid_print
    print(fail == 0 ? '저장 왕복 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
