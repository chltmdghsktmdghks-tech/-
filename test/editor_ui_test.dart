// 5단계 12/N — 편집기 **화면**을 시험이 직접 눌러 본다.
//   flutter test test/editor_ui_test.dart
//
// 계산은 `editor_check_test.dart` 가 본다. 여기서 보는 건 다른 것이다:
//  · 누른 자리와 고쳐지는 음이 **같은가**(격자 좌표 ↔ 도수·스텝 배선)
//  · 세로(400×800)·가로(800×400) 어느 쪽에서도 **화면이 넘치지 않는가**
//    — 가로 믹서를 눈으로만 보고 만들었다가 페이더가 뭉개진 적이 있다. 넘침은
//    위젯 시험이 예외로 잡아 준다(사람 눈보다 정확하다).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/editor_view.dart';

// editor_view.dart 안의 칸 크기와 같아야 한다 — 여기가 어긋나면 엉뚱한 칸을 누른다.
const _kCell = 30.0, _kHead = 62.0;

/// 격자의 시작 y 도 **줄 높이도 재 보고 쓴다.** 손으로 계산하면(58일까 86일까)
/// 한 줄씩 밀린 채로 시험이 통과해 버린다 — 실제로 한 번 그랬다.
/// 줄 높이는 이제 **화면에 따라 달라진다**(자리가 남으면 칸을 키운다) → 더더욱 재야 한다.
Offset _cell(WidgetTester tester, int rowFromTop, int step, int rows) {
  // 목록이 둘이다(마디 점프 줄 + 격자) — 격자는 **뒤쪽**이다
  final grid = find.byType(ListView).last;
  final top = tester.getTopLeft(grid).dy;
  // 격자가 뷰포트를 **다 안 채울 수 있다**(줄 높이에 상한이 있다) → 그냥 나누면
  // 실제보다 크게 나온다. `editor_view.dart` 의 `rowHeightFor` 와 같은 식을 쓴다.
  final rowH = rowHeightFor(tester.getSize(grid).height, rows);
  return Offset(
    _kHead + step * _kCell + _kCell / 2,
    top + rowFromTop * rowH + rowH / 2,
  );
}

void main() {
  testWidgets('편집기 화면', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = Project.initial();
    final mel = p.tracks.firstWhere((t) => t.type == 'melody');

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: EditorView(
            project: p,
            transport: Transport(),
            track: mel,
            host: null, // 소리 없이 화면만
          ),
        ),
      ),
    );

    final name = mel.pattern!;
    List<List<Object?>> notes() => p.findNote('melody', name)!.notes;

    check('1) 내 패턴으로 복사', p.isMine(name), '$name · 음 ${notes().length}개');

    // 판을 비우고 시작한다 — 라이브러리 음이 그 자리에 있으면 '찍기'가 아니라 '고르기'가 된다
    p.putUserPattern(
      'melody',
      name,
      note: NotePatternDef(name, 2, 2, const []),
    );

    // 맨 아래 줄(도수 0) 2번째 칸을 누른다 → 15줄이므로 위에서 14번째 줄
    await tester.tapAt(_cell(tester, 14, 1, 15));
    await tester.pump();
    final added = notes();
    check(
      '2) 빈 칸을 누르면 찍힌다',
      added.length == 1 && added[0][0] == 0 && added[0][1] == 1,
      '도수 ${added.isEmpty ? '-' : added[0][0]} · ${added.isEmpty ? '-' : added[0][1]}번 칸 · 길이 ${added.isEmpty ? '-' : added[0][2]}칸',
    );

    // 찍자마자 골라져 있어야 한다 — 아래 바가 그 음을 가리킨다
    check(
      '3) 찍으면 바로 골라진다',
      find.byIcon(Icons.straighten).evaluate().isNotEmpty &&
          find.text('2칸').evaluate().isNotEmpty,
      '아래 바에 길이 2칸이 보인다',
    );

    // 길이 +를 두 번 → 4칸
    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add).last);
    await tester.pump();
    check('4) 길이 늘리기', notes()[0][2] == 4, '${notes()[0][2]}칸');

    // 세기 '세게' — 좁은 화면에선 옆으로 밀려 있을 수 있으니 먼저 끌어온다
    await tester.ensureVisible(find.text('세게'));
    await tester.pump();
    await tester.tap(find.text('세게'));
    await tester.pump();
    check('5) 세기', notes()[0][3] == 3, '세기 ${notes()[0][3]}');

    // 글라이드
    await tester.ensureVisible(find.text('글라이드'));
    await tester.pump();
    await tester.tap(find.text('글라이드'));
    await tester.pump();
    check(
      '6) 글라이드',
      notes()[0].length > 4 && notes()[0][4] == 1,
      '5번째 칸 ${notes()[0].length > 4 ? notes()[0][4] : '없음'}',
    );

    // 한 칸 오른쪽으로
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    check('7) 옮기기', notes()[0][1] == 2, '${notes()[0][1]}번 칸');

    // 고른 음을 다시 누르면 지워진다 (4칸짜리라 막대 왼쪽 끝을 누른다)
    await tester.tapAt(_cell(tester, 14, 2, 15));
    await tester.pump();
    check('8) 다시 누르면 지워진다', notes().isEmpty, '음 ${notes().length}개');

    // ── 8-b) **고르기만 한 것은 되돌리기 기록에 안 쌓인다** ──
    //
    // `_snapshot()` 이 갈래 위에 있어서, 이미 찍힌 칸을 눌러 **고르기만 해도**
    // 판이 하나도 안 바뀐 기록이 쌓였다. 그러면 되돌리기를 눌러도 같은 판으로
    // 되돌아가 **아무 일도 안 일어난다** — 사용자에겐 고장으로 보인다.
    // 찍기 → 다른 칸 찍기 → 앞 칸 고르기 → 되돌리기 한 번, 이면 음이 하나여야 한다.
    p.putUserPattern(
      'melody',
      name,
      note: NotePatternDef(name, 2, 2, const []),
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
    await tester.tapAt(_cell(tester, 14, 1, 15)); // 찍기 A
    await tester.pump();
    await tester.tapAt(_cell(tester, 14, 5, 15)); // 찍기 B (고른 것은 B가 된다)
    await tester.pump();
    final two = notes().length;
    await tester.tapAt(_cell(tester, 14, 1, 15)); // A 를 **고르기만** 한다
    await tester.pump();
    final stillTwo = notes().length;
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    check(
      '8-b) 고르기만 한 것은 되돌리기에 안 쌓인다',
      two == 2 && stillTwo == 2 && notes().length == 1,
      '찍고 둘 $two개 → 고르기만 $stillTwo개 → 되돌리기 뒤 ${notes().length}개 (1이어야 한다)',
    );

    // ── 8-c) **다시하기가 되돌리기의 짝이다** ──
    //
    // 되돌리기만 있으면 한 칸 지나쳤을 때 그 편집이 영영 없다. 그래서 사람은
    // 마음 놓고 되돌리지 못한다 — 짝이 있어야 되돌리기가 산다.
    // 그리고 되돌린 **뒤에 새로 고치면** 다시하기는 더 못 간다(갈라진 미래다).
    {
      p.putUserPattern(
        'melody',
        name,
        note: NotePatternDef(name, 2, 2, const []),
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
      await tester.tapAt(_cell(tester, 14, 1, 15)); // 찍기
      await tester.pump();
      await tester.tapAt(_cell(tester, 14, 5, 15)); // 하나 더
      await tester.pump();
      final two = notes().length;

      await tester.tap(find.byIcon(Icons.undo));
      await tester.pump();
      final afterUndo = notes().length;
      await tester.tap(find.byIcon(Icons.redo));
      await tester.pump();
      final afterRedo = notes().length;

      // 되돌린 뒤 **새로 고치면** 다시하기는 꺼진다
      await tester.tap(find.byIcon(Icons.undo));
      await tester.pump();
      await tester.tapAt(_cell(tester, 13, 9, 15)); // 다른 줄에 새로 찍기
      await tester.pump();
      final redoGone =
          tester
              .widget<GestureDetector>(
                find.ancestor(
                  of: find.byIcon(Icons.redo),
                  matching: find.byType(GestureDetector),
                ),
              )
              .onTap ==
          null;

      check(
        '8-c) 다시하기가 되돌리기의 짝',
        two == 2 && afterUndo == 1 && afterRedo == 2 && redoGone,
        '둘 $two → 되돌리기 $afterUndo → 다시하기 $afterRedo · '
            '새로 고친 뒤 다시하기 꺼짐 $redoGone',
      );
    }

    // ── 8-d) **지우개 — 훑으면 지나간 것이 지워진다** ──
    //
    // 여태 지우는 길은 둘뿐이었다: 하나씩 두 번 누르기, 또는 판 전체 날리기.
    // 16비트 하이햇 한 줄이면 32번이다 — **하나와 전부 사이가 비어 있었다.**
    {
      p.putUserPattern(
        'melody',
        name,
        note: NotePatternDef(name, 2, 2, const []),
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
      // 한 줄에 넷 찍는다
      for (final st in [1, 3, 5, 7]) {
        await tester.tapAt(_cell(tester, 14, st, 15));
        await tester.pump();
      }
      final four = notes().length;

      // 지우개를 켜고 그 줄을 훑는다
      await tester.tap(find.byIcon(Icons.auto_fix_off));
      await tester.pump();
      final from = _cell(tester, 14, 1, 15);
      final to = _cell(tester, 14, 7, 15);
      // 격자 훑기는 **꾹 누르고** 시작한다(찍기 드래그와 같은 길이다 —
      // 안 그러면 세로 스크롤과 부딪힌다)
      final g = await tester.startGesture(from);
      await tester.pump(const Duration(milliseconds: 600));
      // 칸마다 들러야 한다 — 한 번에 건너뛰면 사이가 안 지워진다
      for (var st = 1; st <= 7; st++) {
        await g.moveTo(_cell(tester, 14, st, 15));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pump();
      final wiped = notes().length;

      // 되돌리기 **한 번**으로 다 돌아온다(끄는 동안은 한 번만 쌓는다)
      await tester.tap(find.byIcon(Icons.undo));
      await tester.pump();
      final back = notes().length;

      // 끄면 다시 찍힌다
      // ignore: avoid_print
      print(
        '    지우개 아이콘 ${find.byIcon(Icons.auto_fix_off).evaluate().length}개',
      );
      await tester.tap(find.byIcon(Icons.auto_fix_off));
      await tester.pump();
      final beforeDraw = notes().length;
      // 9번 칸까지가 400dp 화면에 보인다(62 + 9×30 + 15 = 347) — 11번은 화면 밖이라
      // 눌러도 아무 일이 안 난다. 시험이 화면 밖을 누르면 「기능이 죽었다」로 보인다.
      await tester.tapAt(_cell(tester, 14, 9, 15));
      await tester.pump();
      final drawsAgain = notes().length == beforeDraw + 1;

      check(
        '8-d) 지우개로 훑어 지운다',
        four == 4 && wiped == 0 && back == 4 && drawsAgain,
        '찍기 $four개 → 훑어 지우기 $wiped개 → 되돌리기 한 번에 $back개 · '
            '끄면 다시 찍힘 $drawsAgain',
      );
    }

    // 드럼은 길이가 없고 세기만 있다
    final drum = p.tracks.firstWhere((t) => t.type == 'drum');
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: EditorView(
            project: p,
            transport: Transport(),
            track: drum,
            host: null,
          ),
        ),
      ),
    );
    await tester.tapAt(_cell(tester, 0, 0, kDrumLanes.length)); // 킥 첫 칸
    await tester.pump();
    check(
      '9) 드럼은 세기만',
      find.byIcon(Icons.graphic_eq).evaluate().isNotEmpty &&
          find.byIcon(Icons.straighten).evaluate().isEmpty,
      '길이 칸 없음 · 세기 칸 있음',
    );
    // 트랙을 갈아 끼웠으면 **그 트랙의 내 패턴**을 고쳐야 한다(앞 트랙이 아니라)
    final dName = drum.pattern!;
    check(
      '9-b) 트랙 바꾸면 그 트랙 패턴',
      p.isMine(dName) && p.userDrum.containsKey(dName),
      '$dName',
    );
    await tester.ensureVisible(find.text('여리게'));
    await tester.pump();
    await tester.tap(find.text('여리게'));
    await tester.pump();
    final kickVels = p.findDrum(dName)!.vels?['k'];
    final kickSteps = p.findDrum(dName)!.hits['k'];
    final at0 = kickSteps?.indexOf(0) ?? -1;
    check(
      '10) 드럼 세기 바뀜',
      at0 >= 0 && kickVels != null && kickVels[at0] == 1,
      '킥 첫 칸 세기 ${at0 < 0 ? '-' : kickVels?[at0]}',
    );

    // 12~14) 마디 자 · 마디 점프 · 촘촘 보기
    //  — 4마디(64칸)를 30px 로 그리면 다섯 번 밀어야 끝까지 본다
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

    // 기본 2마디짜리 패턴이라 점프 칸이 2개
    final barsNow = p.findNote('melody', name)!.bars;
    final jump = find.byType(GestureDetector);
    check(
      '12) 마디 자',
      find.text('마디').evaluate().isNotEmpty && barsNow > 1,
      '$barsNow마디 · 점프 줄 있음 · 잡히는 것 ${jump.evaluate().length}개',
    );

    // 12-b) **줄 이름은 가로로 밀어도 남는다.** 예전엔 이름 칸까지 같이 밀려서
    //       2마디로 점프하면 어느 줄이 몇 도인지 알 수 없었다(폰에서 확인).
    final labelBefore = tester.getTopLeft(find.textContaining('1↑↑'));
    // 마디 점프 줄의 두 번째 칸 = 2마디
    await tester.tap(
      find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(GestureDetector),
          )
          .at(1),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final labelAfter = find.textContaining('1↑↑').evaluate().isEmpty
        ? null
        : tester.getTopLeft(find.textContaining('1↑↑'));
    final ruler2 = find.text('2').evaluate().isNotEmpty;
    check(
      '12-b) 줄 이름은 안 밀린다',
      labelAfter != null &&
          (labelAfter.dx - labelBefore.dx).abs() < 0.5 &&
          ruler2,
      '이름 x ${labelBefore.dx.round()} → ${labelAfter?.dx.round()} · 자에 2마디 $ruler2',
    );

    // 촘촘 보기 — 격자 전체 너비가 줄어야 한다
    double gridWidth() => tester.getSize(find.byType(ListView).last).width;
    final wide = gridWidth();
    await tester.tap(find.byIcon(Icons.zoom_out_map));
    await tester.pump();
    final tight = gridWidth();
    check('13) 촘촘 보기', tight < wide, '${wide.round()} → ${tight.round()}px');

    // 되돌리기
    await tester.tap(find.byIcon(Icons.zoom_in_map));
    await tester.pump();
    check(
      '14) 되돌리기',
      (gridWidth() - wide).abs() < 1,
      '${gridWidth().round()}px',
    );

    // 가로로 눕혀도 넘치지 않아야 한다
    tester.view.physicalSize = const Size(800, 400);
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
    final err = tester.takeException();
    check('11) 가로·세로 둘 다 안 넘침', err == null, '넘침 예외 ${err ?? '없음'}');

    // 15) 가로에서는 위쪽 바가 **한 줄** — 재생과 「촘촘 보기」가 같은 높이에 온다.
    //     두 줄로 두면 드럼 레인 10개 중 2.5개만 보인다.
    final playY = tester.getCenter(find.text('재생')).dy;
    final zoomY = tester.getCenter(find.text('촘촘 보기')).dy;
    check(
      '15) 가로는 위쪽 바 한 줄',
      (playY - zoomY).abs() < 6,
      '재생 y${playY.round()} · 촘촘 보기 y${zoomY.round()}',
    );

    // ignore: avoid_print
    print(fail == 0 ? '편집기 화면 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });

  // 5단계 28/N — **빈 판**으로 들어왔을 때. 트랙이 '없음' 이어도 편집기가 열리게
  // 되면서, 아무것도 안 찍힌 격자를 처음 보는 일이 흔해졌다.
  testWidgets('빈 판 편집기', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = Project.initial();
    final mel = p.tracks.firstWhere((t) => t.type == 'melody');
    p.setClip(mel, null); // '없음 (안 침)' 인 트랙

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

    // 1) 빈 판 안내가 뜬다
    check(
      '1) 빈 판 안내',
      find.textContaining('빈 판입니다').evaluate().isNotEmpty,
      '무엇을 하면 되는지 한 줄',
    );

    // 2) 마디 점프 칸이 **손가락 크기**다 (42×38 — 예전 30×28 은 옆 마디로 샜다)
    final chip = tester.getSize(
      find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(GestureDetector),
          )
          .first,
    );
    check(
      '2) 마디 칸 크기',
      chip.width >= 42 && chip.height >= 36,
      '${chip.width.round()}×${chip.height.round()}px',
    );

    // 2-b) 위쪽 바가 **안 잘린다** — 한 줄에 여섯 개를 넣었더니 이름도 설명도
    //      다 잘렸다(폰). 두 줄로 나누고 돋보기에는 글자를 붙였다.
    // (아이콘이 아니라 **눌리는 칸**을 잰다 — 아이콘만 재면 19px 이 나온다)
    final small = tester.getSize(
      find
          .ancestor(
            of: find.byIcon(Icons.remove),
            matching: find.byType(Container),
          )
          .first,
    );
    final fullName = find.text(mel.pattern ?? '?').evaluate().isNotEmpty;
    final zoomLabel = find.text('촘촘 보기').evaluate().isNotEmpty;
    check(
      '2-b) 위쪽 바',
      fullName && zoomLabel && small.width >= 38,
      '이름 온전 $fullName · 돋보기 글자 $zoomLabel · ±칸 ${small.width.round()}px',
    );

    // 3) 한 칸 찍으면 안내가 사라진다
    await tester.tapAt(_cell(tester, 3, 2, 15));
    await tester.pump();
    final name = mel.pattern;
    final n = name == null ? null : p.findNote('melody', name)?.notes.length;
    check(
      '3) 찍으면 안내가 사라진다',
      n == 1 && find.textContaining('빈 판입니다').evaluate().isEmpty,
      '음 $n개',
    );

    // 4) **자리가 남으면 칸을 키운다.** 드럼은 레인이 10개뿐이라 28px 로 못 박으면
    //    격자 아래가 화면의 40% 나 빈다(그림으로 뽑아 보고 잡았다).
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: EditorView(
            project: p,
            transport: Transport(),
            track: p.tracks.firstWhere((t) => t.type == 'drum'),
            host: null,
          ),
        ),
      ),
    );
    await tester.pump();
    final grid = find.byType(ListView).last;
    final rowH = rowHeightFor(tester.getSize(grid).height, kDrumLanes.length);
    check(
      '4) 자리가 남으면 칸이 커진다',
      rowH > 34,
      '한 줄 ${rowH.round()}px (최소 28 · 최대 46)',
    );

    // 5) 아무것도 안 골랐을 때 아래 바는 **한 줄만** 차지한다
    // (안내 글이 바뀌면 같이 고쳐야 한다 — 44/N 에서 제스처 안내로 바뀌었다)
    final barH = tester.getSize(find.textContaining('빈 칸을 끌면')).height;
    check('5) 빈 아래 바는 얇다', barH < 30, '안내 글 높이 ${barH.round()}px');

    // 6~9) **되돌리기** — 이 화면에는 없었다. 「지우기」가 확인도 없이 판 전체를
    //      날리는데도 되돌릴 방법이 없었다(5단계 43/N).
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
    final nm = mel.pattern!;
    int count() => p.findNote('melody', nm)?.notes.length ?? 0;

    // 음 셋을 찍는다(이미 하나 찍혀 있으니 셋을 더한다)
    final base = count();
    for (final st in [3, 6, 9]) {
      await tester.tapAt(_cell(tester, 10, st, 15));
      await tester.pump();
    }
    final many = count();
    check('6) 음을 더 찍었다', many == base + 3, '$base → $many개');

    // 「지우기」로 판을 통째로 비운다
    await tester.tap(find.byIcon(Icons.delete_sweep_outlined));
    await tester.pump();
    check('7) 지우면 비워진다', count() == 0, '음 ${count()}개');

    // 되돌리면 **그대로 돌아온다**
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    check('8) 되돌리면 살아난다', count() == many, '음 ${count()}개 (지우기 전 $many개)');

    // 한 걸음씩 계속 거슬러 올라간다
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    check('9) 한 걸음씩', count() == many - 2, '두 번 더 되돌려 음 ${count()}개');

    // 10~13) **꾹 눌러 끌기** (5단계 44/N). 손가락이 이미 음 위에 있는데
    //        눈을 아래 바로 옮겨 「길이 +」를 찾는 건 낭비다.
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
    // 판을 비우고 시작
    p.putUserPattern('melody', nm, note: NotePatternDef(nm, 2, 2, const []));
    await tester.pump();

    List<List<Object?>> ns() => p.findNote('melody', nm)!.notes;

    // 10) 빈 칸을 꾹 눌러 옆으로 끌면 **쫘르륵 깔린다**
    final from = _cell(tester, 10, 0, 15);
    var g = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 600)); // 길게 누르기
    for (var i = 1; i <= 4; i++) {
      await g.moveTo(_cell(tester, 10, i, 15));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await g.up();
    await tester.pump();
    check('10) 끌면 깔린다', ns().length == 5, '음 ${ns().length}개 (0~4번 칸)');

    // 11) 한 번 끈 것은 **한 번에** 되돌아간다
    await tester.tap(find.byIcon(Icons.undo));
    await tester.pump();
    check('11) 끈 건 한 번에 되돌아간다', ns().isEmpty, '음 ${ns().length}개');

    // 다시 하나 찍고
    await tester.tapAt(_cell(tester, 10, 2, 15));
    await tester.pump();
    final len0 = ns().first[2] as int;

    // 12) 있는 음을 꾹 눌러 **옆으로** → 길이
    g = await tester.startGesture(_cell(tester, 10, 2, 15));
    await tester.pump(const Duration(milliseconds: 600));
    await g.moveBy(const Offset(3 * 30.0, 0)); // 세 칸 오른쪽
    await tester.pump(const Duration(milliseconds: 30));
    await g.up();
    await tester.pump();
    final len1 = ns().first[2] as int;
    check('12) 옆으로 끌면 길이', len1 == len0 + 3, '$len0칸 → $len1칸');

    // 13) 있는 음을 꾹 눌러 **위로** → 음이 올라간다(높낮이)
    //
    // 세로가 여태 「세기」였는데 **높낮이**로 바뀌었다. 두드려 넣기가 생기면서
    // 「박자는 맞는데 아직 제자리가 아닌 음」이 한 판에 열 개씩 생기기 때문이다 —
    // 그걸 고치는 길이 「지우고 옆 줄에 다시 찍기」면 두드린 보람이 없다.
    // 세기는 아래 바의 여리게·보통·세게가 맡는다(거기 이미 있었다).
    final noteRowH = rowHeightFor(
      tester.getSize(find.byType(ListView).last).height,
      15,
    );
    final deg0 = ns().first[0] as int;
    final vel0 = ns().first[3] as int;
    g = await tester.startGesture(_cell(tester, 10, 2, 15));
    await tester.pump(const Duration(milliseconds: 600));
    await g.moveBy(Offset(0, -2 * noteRowH)); // 두 줄 위로
    await tester.pump(const Duration(milliseconds: 30));
    await g.up();
    await tester.pump();
    final deg1 = ns().first[0] as int;
    check('13) 위로 끌면 음이 올라간다', deg1 == deg0 + 2, '$deg0도 → $deg1도');

    // 13-b) **옮기는 것이지 새로 찍는 것이 아니다** — 길이·세기가 따라온다.
    //       (지우고 다시 찍으면 둘 다 초기값으로 돌아간다)
    check(
      '13-b) 옮겨도 길이·세기 그대로',
      ns().first[2] == len1 && ns().first[3] == vel0,
      '${ns().first[2]}칸 · 세기 ${ns().first[3]}',
    );

    // 13-c) 세로로 끌었으면 **길이는 안 건드린다**(축 잠금).
    //       안 잠그면 손이 조금 기울 때 고치려던 것과 다른 것이 바뀐다.
    g = await tester.startGesture(_cell(tester, 8, 2, 15));
    await tester.pump(const Duration(milliseconds: 600));
    await g.moveBy(Offset(9, -2 * noteRowH)); // 세로가 크다 → 세로로 잠긴다
    await tester.pump(const Duration(milliseconds: 30));
    await g.up();
    await tester.pump();
    check('13-c) 세로로 끌면 길이는 그대로', ns().first[2] == len1, '${ns().first[2]}칸');

    // 14) **촘촘 보기가 보던 자리를 지키는가.**
    //     칸 너비만 바꾸면 스크롤은 픽셀이라 그대로 남는다 → 3마디를 보고 있다가
    //     촘촘히 하면 4마디가 보인다. 찾아 놓은 자리를 다시 찾아야 했다.
    //     마디 자의 「3」 이 화면 어디에 있는지로 확인한다(스크롤 값은 private).
    //
    // **판이 3마디는 돼야 뜻이 있다.** 여태 이 판은 2마디였고, 그래서 「3」 은
    // 자에도 점프 줄에도 없었다 — 대신 **가로 스크롤 밖**에 있는 줄 이름 「3」
    // (도수 3)이 잡히고 있었다. 그 x 는 밀어도 안 변하니 무엇을 하든 통과했다.
    // (줄 이름에 음이름을 붙이면서 그 글자가 안 잡히게 되자 드러났다)
    await tester.tap(find.byIcon(Icons.add).first); // 마디 2 → 3
    await tester.pump();
    await tester.tap(find.byIcon(Icons.add).first); // 3 → 4
    await tester.pump();
    await tester.tap(find.text('3').first); // 마디 3 으로 점프
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    double? xOf(String label) {
      final f = find.text(label);
      if (f.evaluate().isEmpty) return null;
      return tester.getTopLeft(f.last).dx;
    }

    final before = xOf('3');
    await tester.tap(find.text('촘촘 보기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final after = xOf('3');
    check(
      '14) 촘촘히 해도 보던 마디가 그 자리',
      before != null && after != null && (after - before).abs() < 40,
      '마디 3 이 ${before?.round()} → ${after?.round()}px',
    );

    // ignore: avoid_print
    print(fail == 0 ? '빈 판 편집기 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
