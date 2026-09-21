// **악기 추가** — 종류(코드·멜로디)가 아니라 **악기 이름**으로 고른다.
//   flutter test test/instrument_add_test.dart
//
// 여태는 「드럼·베이스·코드·멜로디」 넷 중 하나를 먼저 고르게 했다. 그건 이 앱의
// 속사정이지 사람이 아는 말이 아니다 — 기타를 넣고 싶은 사람이 「코드인가
// 멜로디인가」부터 답해야 했다.
//
// 보는 것: 버튼이 **하나**인가 · 악기 이름이 나오는가 · 고르면 그 **음색으로**
// 트랙이 생기는가 · 종류가 알아서 따라오는가 · 목록이 성한가(없는 음색을 적어
// 두면 화면에는 이름만 뜨고 소리는 딴 것이 난다).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/instruments.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/scene_view.dart';

void main() {
  testWidgets('악기 추가', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $what — $detail');
      if (!ok) fail++;
    }

    // 1) 목록이 성한가 — 여기 없는 음색을 적어 두면 이름만 뜨고 소리는 딴 것이 난다.
    {
      final bad = [
        for (final (v, l, t) in kInstrumentPicks)
          if (v.isNotEmpty && !VOICE_LABEL.containsKey(v))
            '$l($v)'
          else if (!kTrackTypes.contains(t))
            '$l→$t',
      ];
      check('1) 없는 음색·종류가 없다', bad.isEmpty, '어긋남 $bad');
      check(
        '1-b) 드럼도 있다',
        kInstrumentPicks.any((e) => e.$3 == 'drum'),
        '${kInstrumentPicks.length}종',
      );
      // 종류 넷이 다 나와야 한다 — 하나가 빠지면 그 종류는 만들 길이 없어진다.
      final types = {for (final e in kInstrumentPicks) e.$3};
      check('1-c) 종류 넷이 다 있다', types.length == kTrackTypes.length, '$types');
    }

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = Project.initial()..setGenre('lofi');
    final tr = Transport();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SceneView(project: p, transport: tr, host: null),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    // 2) 줄에 있는 것은 **버튼 하나**다 — 네 가지를 먼저 고르게 하지 않는다.
    check(
      '2) 「악기 추가」 하나',
      find.text('악기 추가').evaluate().isNotEmpty &&
          find.text('코드').evaluate().isEmpty &&
          find.text('멜로디').evaluate().isEmpty,
      '',
    );

    // 3) 누르면 **악기 이름**이 나온다
    await tester.tap(find.text('악기 추가'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final shown = [
      for (final (_, label, _) in kInstrumentPicks)
        if (find.text(label).evaluate().isNotEmpty) label,
    ];
    check('3) 악기 이름이 나온다', shown.length >= 8, '${shown.length}종 보임');
    check(
      '3-b) 기타·피아노·벨이 있다',
      ['기타', '피아노', '벨'].every((n) => find.text(n).evaluate().isNotEmpty),
      '',
    );

    // 4) 고르면 그 **음색으로** 트랙이 생기고 종류가 따라온다
    final before = p.tracks.length;
    await tester.tap(find.text('기타'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final t = p.tracks.last;
    check(
      '4) 고른 악기로 생긴다',
      p.tracks.length == before + 1 && t.voice == 'guitar',
      '${p.tracks.length}개 · 음색 ${t.voice} · 종류 ${t.type} · 이름 ${t.name}',
    );
    check('4-b) 종류가 따라온다', t.type == 'chord', t.type);
    check('4-c) 이름도 악기 이름', t.name == '기타', t.name);

    // 4-d) **모든 씬**에 판이 들어간다 — 안 그러면 딴 씬에서 그 악기만 조용하다
    check(
      '4-d) 모든 씬에 판이 있다',
      p.scenes.every((s) => s.clips[t.id] != null),
      '${p.scenes.where((s) => s.clips[t.id] != null).length}/${p.scenes.length}',
    );

    check('5) 넘침 없음', tester.takeException() == null, '');

    expect(fail, 0, reason: '$fail개 항목이 어긋났습니다');
  });
}
