// 편집기 화면 — **긴 음의 가운데를 꾹 누르면 그 음이 잡히는가.**
//   flutter test test/editor_longnote_ui_test.dart
//
// 사용자 신고(2026-09-22): "미디 편집할때 긴 블럭의 중간부분을 길게누르면
// 그 블럭을 잡아야지 왜 새로 생성되니".
//
// `editor_hit_test.dart` 는 **판정 규칙**만 잰다. 여기서는 규칙이 실제 화면에
// 배선됐는지를 본다 — 규칙만 맞고 배선이 빠지면 시험은 통과하는데 손은
// 그대로 헛돈다. (실기기 확인은 격자가 스크롤돼 행 좌표가 어긋나서
// 결론이 안 났다 — 그래서 위젯으로 고정해 잰다)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/editor_view.dart';

// editor_view.dart 안의 칸 크기와 같아야 한다.
const _kCell = 30.0, _kHead = 62.0;

Offset _cell(WidgetTester tester, int rowFromTop, int step, int rows) {
  final grid = find.byType(ListView).last;
  final top = tester.getTopLeft(grid).dy;
  final rowH = rowHeightFor(tester.getSize(grid).height, rows);
  return Offset(
    _kHead + step * _kCell + _kCell / 2,
    top + rowFromTop * rowH + rowH / 2,
  );
}

void main() {
  testWidgets('긴 음의 가운데를 꾹 눌러도 새로 안 생긴다', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = Project.initial()..setGenre('lofi');
    final mel = p.tracks.firstWhere((t) => t.type == 'melody');
    final nm = mel.pattern!;

    // 도수 10(위에서 4번째 줄)에 **6칸짜리** 음 하나만 둔 판.
    const rows = 15;
    const deg = 10;
    const rowFromTop = rows - 1 - deg; // 4
    p.putUserPattern(
      'melody',
      nm,
      note: NotePatternDef(nm, 2, 2, const [
        [deg, 2, 6, 2],
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: EditorView(
            project: p,
            transport: Transport(),
            track: mel,
            host: null,
          ),
        ),
      ),
    );
    await tester.pump();

    List<List<Object?>> ns() => p.findNote('melody', nm)!.notes;
    expect(ns().length, 1, reason: '시작은 음 하나');
    expect(ns().first[2], 6, reason: '6칸짜리');

    // ── 가운데(5번 칸 — 음은 2~7번 칸을 덮는다)를 꾹 누른다 ──
    final mid = _cell(tester, rowFromTop, 5, rows);
    final g = await tester.startGesture(mid);
    await tester.pump(const Duration(milliseconds: 600)); // 길게 누르기
    await g.up();
    await tester.pump();

    // ignore: avoid_print
    print('가운데 꾹 누른 뒤 — 음 ${ns().length}개 ${ns()}');
    expect(ns().length, 1,
        reason: '가운데를 잡았을 뿐인데 음이 늘었다 = 새로 생겼다는 뜻');
    expect(ns().first[1], 2, reason: '원래 음의 시작 칸이 그대로여야 한다');
    expect(ns().first[2], 6, reason: '길이도 그대로');
  });

  testWidgets('가운데를 잡고 위로 끌면 그 음이 통째로 올라간다', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = Project.initial()..setGenre('lofi');
    final mel = p.tracks.firstWhere((t) => t.type == 'melody');
    final nm = mel.pattern!;
    const rows = 15;
    const deg = 10;
    const rowFromTop = rows - 1 - deg;
    p.putUserPattern(
      'melody',
      nm,
      note: NotePatternDef(nm, 2, 2, const [
        [deg, 2, 6, 2],
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: EditorView(
            project: p,
            transport: Transport(),
            track: mel,
            host: null,
          ),
        ),
      ),
    );
    await tester.pump();
    List<List<Object?>> ns() => p.findNote('melody', nm)!.notes;

    final grid = find.byType(ListView).last;
    final rowH = rowHeightFor(tester.getSize(grid).height, rows);
    final mid = _cell(tester, rowFromTop, 5, rows);

    final g = await tester.startGesture(mid);
    await tester.pump(const Duration(milliseconds: 600));
    await g.moveTo(mid + Offset(0, -rowH)); // 한 줄 위로
    await tester.pump(const Duration(milliseconds: 30));
    await g.up();
    await tester.pump();

    // ignore: avoid_print
    print('가운데 잡고 한 줄 위로 — 음 ${ns().length}개 ${ns()}');
    expect(ns().length, 1, reason: '옮긴 것이지 새로 찍은 것이 아니다');
    expect(ns().first[0], deg + 1, reason: '한 줄 위로 올라가야 한다');
    expect(ns().first[2], 6, reason: '길이는 따라와야 한다');
  });

  testWidgets('긴 음의 가운데를 탭하면 그 음이 골라진다 — 새로 안 생긴다', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = Project.initial()..setGenre('lofi');
    final mel = p.tracks.firstWhere((t) => t.type == 'melody');
    final nm = mel.pattern!;
    const rows = 15;
    const deg = 10;
    const rowFromTop = rows - 1 - deg;
    p.putUserPattern(
      'melody',
      nm,
      note: NotePatternDef(nm, 2, 2, const [
        [deg, 2, 6, 2],
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: EditorView(
            project: p,
            transport: Transport(),
            track: mel,
            host: null,
          ),
        ),
      ),
    );
    await tester.pump();
    List<List<Object?>> ns() => p.findNote('melody', nm)!.notes;

    await tester.tapAt(_cell(tester, rowFromTop, 5, rows));
    await tester.pump();
    // ignore: avoid_print
    print('가운데 탭 — 음 ${ns().length}개 ${ns()}');
    expect(ns().length, 1, reason: '탭으로 새 음이 생기면 안 된다');

    // 골라진 것을 **다시** 탭하면 지워진다(원래 규칙). 가운데를 눌러도 같아야 한다.
    await tester.tapAt(_cell(tester, rowFromTop, 5, rows));
    await tester.pump();
    // ignore: avoid_print
    print('가운데 두 번째 탭 — 음 ${ns().length}개');
    expect(ns().length, 0, reason: '고른 걸 다시 누르면 지워진다');
  });

  testWidgets('겹친 줄에서 **보이는 막대**가 잡힌다 — 왼쪽 것이 아니라', (tester) async {
    // 「끌면 쫘르륵 깔린다」는 칸마다 기본 길이 2칸으로 찍으므로 이웃끼리
    // **1칸씩 겹친다**(의도된 동작 — `editor_ui_test.dart` 10번).
    // 그리는 쪽(`_GridRow` 의 Stack)은 목록 **뒤쪽 음을 위에** 그린다.
    // 그러니 손끝 판정도 뒤쪽을 잡아야 눈과 손이 같은 것을 가리킨다.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = Project.initial()..setGenre('lofi');
    final mel = p.tracks.firstWhere((t) => t.type == 'melody');
    final nm = mel.pattern!;
    const rows = 15;
    const deg = 10;
    const rowFromTop = rows - 1 - deg;
    // 2~3칸 음과 3~4칸 음 — **3번 칸이 겹친다.** 위에 보이는 건 뒤쪽(3번 시작).
    p.putUserPattern(
      'melody',
      nm,
      note: NotePatternDef(nm, 2, 2, const [
        [deg, 2, 2, 2],
        [deg, 3, 2, 2],
      ]),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: EditorView(
            project: p,
            transport: Transport(),
            track: mel,
            host: null,
          ),
        ),
      ),
    );
    await tester.pump();
    List<List<Object?>> ns() => p.findNote('melody', nm)!.notes;

    // 겹친 3번 칸을 두 번 탭 = 고르고 지우기.
    await tester.tapAt(_cell(tester, rowFromTop, 3, rows));
    await tester.pump();
    await tester.tapAt(_cell(tester, rowFromTop, 3, rows));
    await tester.pump();

    // ignore: avoid_print
    print('겹친 칸 두 번 탭 — 남은 음 ${ns()}');
    expect(ns().length, 1, reason: '하나만 지워져야 한다');
    expect(ns().first[1], 2,
        reason: '위에 보이던 3번 음이 지워지고 **2번 음이 남아야** 한다 '
            '— 3번이 남았다면 눈에 안 보이던 왼쪽 음을 지운 것이다');
  });

  testWidgets('칸 경계를 눌러도 찍힌다 — 여백 1px 이 과녁에서 빠지면 안 된다', (tester) async {
    // `_Cell` 의 `Container` 에는 1px 여백이 있다. `GestureDetector` 가
    // 기본값(`deferToChild`)이면 그 띠는 손끝을 **안 받는다** — 30px 칸에서
    // 양옆 1px 씩이라 경계 가까이를 누르면 아무 일도 안 일어난다.
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = Project.initial()..setGenre('lofi');
    final mel = p.tracks.firstWhere((t) => t.type == 'melody');
    final nm = mel.pattern!;
    const rows = 15;
    const deg = 10;
    const rowFromTop = rows - 1 - deg;
    p.putUserPattern('melody', nm, note: NotePatternDef(nm, 2, 2, const []));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: EditorView(
            project: p,
            transport: Transport(),
            track: mel,
            host: null,
          ),
        ),
      ),
    );
    await tester.pump();
    List<List<Object?>> ns() => p.findNote('melody', nm)!.notes;

    // 4번 칸의 **왼쪽 끝에서 0.5px** — 여백 띠 위다.
    final c = _cell(tester, rowFromTop, 4, rows);
    await tester.tapAt(Offset(c.dx - _kCell / 2 + 0.5, c.dy));
    await tester.pump();
    // ignore: avoid_print
    print('칸 왼쪽 끝 탭 — 음 ${ns().length}개 ${ns()}');
    expect(ns().length, 1, reason: '칸 경계가 과녁에서 빠져 있다');
  });
}
