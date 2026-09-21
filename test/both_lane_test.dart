// **한 판에 화음과 낱음을 같이** — 옛 앱의 `lanes.chord` + `lanes.rows`.
//   flutter test test/both_lane_test.dart
//
// 여태 판 하나는 트랙 종류가 정하는 한 가지만 들었다. 패드로 화음을 깔면서 그
// 위에 낱음 몇 개를 얹으려면 트랙을 하나 더 만들어야 했다.
//
// 보는 것: 덧줄이 **정말 울리는가**(데이터가 아니라 나가는 소리로) · 본줄을 고쳐도
// 덧줄이 **안 사라지는가**(짝이 하나 없는 그 병) · 저장 왕복 · 옛 파일 호환 ·
// 편집기에서 줄을 바꾸면 줄 수와 고치는 대상이 같이 바뀌는가.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/ui/editor_view.dart';

/// 그 트랙이 내는 (시각, 주파수) — 정렬해서 글자로.
List<String> _voice(Project p, Transport tr, Track t) {
  final b = SceneSequencer.build(p, tr, reps: 1);
  final part = SceneSequencer.busNames(p).indexOf(t.id);
  return [
    for (final n in b.notes)
      if (n[7] == part)
        '${(n[6] as double).toStringAsFixed(4)}:'
            '${(n[1] as double).toStringAsFixed(2)}',
  ]..sort();
}

void main() {
  testWidgets('한 판에 화음과 낱음', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $what — $detail');
      if (!ok) fail++;
    }

    final p = Project.initial()..setGenre('lofi');
    final tr = Transport();
    final chord = p.tracks.firstWhere((t) => t.type == 'chord');
    final name = p.makeEditable(chord);

    final before = _voice(p, tr, chord);
    check('0) 화음이 울린다', before.isNotEmpty, '${before.length}음');

    // 1) 덧줄(낱음)을 얹으면 **소리가 늘어난다**
    {
      final d = p.userNote[name]!;
      p.userNote[name] = NotePatternDef(
        d.name,
        d.bars,
        d.src,
        d.notes,
        also: [
          [7, 0, 2, 3],
          [9, 4, 2, 3],
        ],
      );
      final after = _voice(p, tr, chord);
      check(
        '1) 덧줄이 울린다',
        after.length == before.length + 2,
        '${before.length}음 → ${after.length}음',
      );
      // 1-b) 화음은 **그대로**여야 한다 — 덧줄이 본줄을 밀어내면 안 된다
      final kept = before.every(after.contains);
      check('1-b) 화음은 그대로', kept, '');
    }

    // 2) 본줄을 고쳐도 덧줄이 **안 사라진다** — 짝이 하나 없으면 조용히 없어진다
    {
      final d = p.userNote[name]!;
      p.userNote[name] = NotePatternDef(d.name, d.bars, d.src, [
        ...d.notes,
        [4, 8, 4, 2],
      ], also: d.also);
      check('2) 덧줄이 남는다', p.userNote[name]!.also.length == 2, '');
    }

    // 3) 저장 왕복 — `toJson` 에만 적고 `fromJson` 에서 빠뜨리면 조용히 사라진다
    {
      final q = Project.initial()
        ..loadJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
      check(
        '3) 저장 왕복',
        q.userNote[name]?.also.length == 2,
        '${q.userNote[name]?.also.length ?? -1}음',
      );
      final qt = q.tracks.firstWhere((t) => t.type == 'chord');
      check(
        '3-b) 소리도 같다',
        _voice(q, tr, qt).join('|') == _voice(p, tr, chord).join('|'),
        '',
      );
    }

    // 3-c) **옛 파일**에는 이 칸이 없다 — 빈 목록으로 읽혀야 한다
    {
      final j = jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>;
      for (final v in (j['userNote'] as Map).values) {
        (v as Map).remove('also');
      }
      final q = Project.initial()..loadJson(j);
      check('3-c) 옛 파일은 빈 덧줄', q.userNote[name]!.also.isEmpty, '');
    }

    // 4) 가락 판에 **화음**을 얹는 반대쪽도 된다
    {
      final mel = p.tracks.firstWhere((t) => t.type == 'melody');
      final mname = p.makeEditable(mel);
      final was = _voice(p, tr, mel);
      final d = p.userNote[mname]!;
      p.userNote[mname] = NotePatternDef(
        d.name,
        d.bars,
        d.src,
        d.notes,
        also: [
          [0, 0, 8, 2],
        ],
      );
      final now = _voice(p, tr, mel);
      check(
        '4) 가락 판에 화음도 얹힌다',
        now.length > was.length,
        '${was.length} → ${now.length}',
      );
    }

    // ── 5) 편집기에서 줄을 바꿔 본다 ──
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: EditorView(project: p, transport: tr, track: chord, host: null),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    check('5) 줄 손잡이가 있다', find.text('화음').evaluate().isNotEmpty, '');
    // 화음 판이니 줄 이름은 코드 이름이다(1도~7도가 아니다)
    await tester.tap(find.text('화음'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    check('5-b) 누르면 낱음 줄로 바뀐다', find.text('낱음').evaluate().isNotEmpty, '');
    check('5-c) 넘침 없음', tester.takeException() == null, '');

    expect(fail, 0, reason: '$fail개 항목이 어긋났습니다');
  });
}
