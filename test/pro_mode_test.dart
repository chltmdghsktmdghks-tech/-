// **프로 모드 — 반음 줄.** (옛 앱의 PRO 모드 자리)
//   flutter test test/pro_mode_test.dart
//
// 도수 줄은 조에 맞는 음만 낸다. 블루 노트도, 지나가는 반음도 못 찍는다.
// 그 제약이 「아무거나 눌러도 어울린다」를 만들어 주므로 **기본은 꺼짐**이고,
// 켠 사람에게만 손잡이가 열린다.
//
// 제일 위험한 자리는 **좌표계가 둘**이라는 것이다 — 도수 7은 한 옥타브 위지만
// 반음 7은 5도다. 깃발만 바꾸면 찍어 둔 가락이 소리 없이 딴 가락이 된다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/edit_ops.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/theory.dart';
import 'package:music_doodle_engine/ui/editor_view.dart';

void main() {
  testWidgets('프로 모드 — 반음 줄', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $what — $detail');
      if (!ok) fail++;
    }

    const key = MusicKey(root: 0, mode: 'minor');

    // 1) 반음 줄의 자 — 0 = 으뜸음, 12 = 한 옥타브 위
    {
      final t0 = semiFreq(0, 'melody', key);
      final t12 = semiFreq(12, 'melody', key);
      check(
        '1) 12반음이 한 옥타브',
        (t12 / t0 - 2.0).abs() < 1e-9,
        '${t0.toStringAsFixed(2)} → ${t12.toStringAsFixed(2)}Hz',
      );
      // 도수 0 과 반음 0 은 **같은 음**이어야 한다(둘 다 으뜸음)
      check(
        '1-b) 으뜸음은 같다',
        (semiFreq(0, 'melody', key) - degreeFreq(0, 'melody', key)).abs() <
            1e-9,
        '',
      );
      // 조를 따라간다 — 절대 음이 아니다
      const f = MusicKey(root: 5, mode: 'minor');
      check(
        '1-c) 조를 따라간다',
        semiFreq(0, 'melody', f) > semiFreq(0, 'melody', key),
        'C ${semiFreq(0, 'melody', key).toStringAsFixed(1)} · '
            'F ${semiFreq(0, 'melody', f).toStringAsFixed(1)}Hz',
      );
      // 조에 **없는 음**이 나오는가 — 이게 프로 모드의 전부다
      final inScale = [
        for (var d = 0; d < 15; d++) degreeFreq(d, 'melody', key),
      ];
      final blue = semiFreq(3 + 3, 'melody', key); // 단조의 6반음 = 트라이톤
      check(
        '1-d) 조에 없는 음이 나온다',
        !inScale.any((f) => (f - blue).abs() < 0.01),
        '${blue.toStringAsFixed(2)}Hz',
      );
    }

    // 2) 좌표계 옮기기 — 도수 → 반음 → 도수가 **제자리**여야 한다
    {
      final deg = <List<Object?>>[
        [0, 0, 2, 2],
        [4, 4, 2, 2],
        [7, 8, 2, 2],
        [14, 12, 2, 2],
      ];
      final chro = NoteOps.toChromatic(deg, 'minor');
      final back = NoteOps.toDegrees(chro, 'minor');
      check(
        '2) 옮겼다 되돌리면 제자리',
        [for (final n in back) n[0]].join(',') ==
            [for (final n in deg) n[0]].join(','),
        '${[for (final n in deg) n[0]]} → ${[for (final n in chro) n[0]]} → '
            '${[for (final n in back) n[0]]}',
      );
      // 2-b) 옮겨도 **소리 높이는 같아야** 한다 — 그게 옮기는 이유다
      var same = true;
      for (var i = 0; i < deg.length; i++) {
        final a = degreeFreq(deg[i][0] as int, 'melody', key);
        final b = semiFreq(chro[i][0] as int, 'melody', key);
        if ((a - b).abs() > 0.01) same = false;
      }
      check('2-b) 옮겨도 음 높이가 같다', same, '');
      // 2-c) 길이·세기는 안 건드린다
      check(
        '2-c) 나머지 칸은 그대로',
        chro[1][1] == 4 && chro[1][2] == 2 && chro[1][3] == 2,
        '${chro[1]}',
      );
    }

    // 3) 반음 판이 **정말 그 소리로** 나간다
    {
      final p = Project.initial()..setGenre('lofi');
      final tr = Transport()
        ..root = 0
        ..mode = 'minor';
      final mel = p.tracks.firstWhere((t) => t.type == 'melody');
      final name = p.makeEditable(mel);
      final d = p.userNote[name]!;
      // 6반음(트라이톤) — 도수 줄에는 자리가 없는 음
      p.userNote[name] = NotePatternDef(name, d.bars, d.src, [
        [6, 0, 2, 2],
      ], chromatic: true);
      final b = SceneSequencer.build(p, tr, reps: 1);
      final part = SceneSequencer.busNames(p).indexOf(mel.id);
      final got = [
        for (final n in b.notes)
          if (n[7] == part) n[1] as double,
      ];
      check(
        '3) 반음 판이 그 소리로 나간다',
        got.length == 1 &&
            (got.first - semiFreq(6, 'melody', key)).abs() < 0.01,
        '${got.length}음 · ${got.isEmpty ? '' : got.first.toStringAsFixed(2)}Hz '
            '(바라던 것 ${semiFreq(6, 'melody', key).toStringAsFixed(2)})',
      );

      // 3-b) 저장 왕복에 깃발이 살아남는가 — 안 남으면 다음에 열 때 **딴 가락**이 된다
      final q = Project.initial()
        ..loadJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
      check('3-b) 깃발이 저장된다', q.userNote[name]?.chromatic == true, '');
      // 3-c) 옛 파일에는 이 칸이 없다 → 도수 줄
      final j = jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>;
      for (final v in (j['userNote'] as Map).values) {
        (v as Map).remove('chro');
      }
      final r = Project.initial()..loadJson(j);
      check('3-c) 옛 파일은 도수 줄', r.userNote[name]?.chromatic == false, '');
    }

    // ── 4) 편집기: 꺼져 있으면 손잡이가 안 열린다 ──
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p2 = Project.initial()..setGenre('lofi');
    final tr2 = Transport();
    final mel2 = p2.tracks.firstWhere((t) => t.type == 'melody');

    Future<void> open({required bool pro}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: EditorView(
              project: p2,
              transport: tr2,
              track: mel2,
              host: null,
              pro: pro,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }

    await open(pro: false);
    await tester.longPress(find.text('가락'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final name2 = p2.tracks.firstWhere((t) => t.type == 'melody').pattern!;
    check(
      '4) 꺼져 있으면 안 바뀐다',
      p2.userNote[name2]?.chromatic != true,
      '${p2.userNote[name2]?.chromatic}',
    );
    // 4-b) 꾹 누른 것이 **탭으로 흘러가면 안 된다** — 줄이 바뀌면 「꾹 눌렀는데
    //      딴 일이 일어났다」가 된다. 대신 어디서 켜는지 알려 준다.
    check(
      '4-b) 줄이 안 바뀐다',
      find.text('가락').evaluate().isNotEmpty,
      find.text('화음').evaluate().isNotEmpty ? '화음으로 바뀌었다' : '그대로',
    );
    check(
      '4-c) 어디서 켜는지 알려 준다',
      find.textContaining('프로 모드를 켜면').evaluate().isNotEmpty,
      '',
    );

    // 5) 켜면 꾹 눌러 반음 줄로 — 줄 수도 바뀐다
    await open(pro: true);
    await tester.longPress(find.text('가락'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    check('5) 켜면 반음 줄로 바뀐다', p2.userNote[name2]?.chromatic == true, '');
    check('5-b) 알려 준다', find.textContaining('반음 줄로').evaluate().isNotEmpty, '');
    check('5-c) 넘침 없음', tester.takeException() == null, '');

    expect(fail, 0, reason: '$fail개 항목이 어긋났습니다');
  });
}
