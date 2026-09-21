// 5단계 21/N — 곡(구간 늘어놓기) 화면 UI 확인.
//   flutter test test/song_ui_test.dart
//
// 이 화면은 구간이 7~10개가 되면 금세 길어진다. 그래서 보는 것:
//  · 순서를 **끌어서** 바꿀 수 있는가(↑↓ 를 여러 번 누르지 않아도 되는가)
//  · 순서가 바뀌면 **곡 데이터도** 바뀌는가(화면만 바뀌면 아무 소용 없다)
//  · 판 수를 한 번에 고를 수 있는가(−/+ 만 있으면 8판까지 일곱 번)
//  · ＋구간 붙이기가 **스크롤 없이** 닿는가
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/arrange_rec.dart';
import 'package:music_doodle_engine/pattern_names.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/song_view.dart';

void main() {
  testWidgets('곡 화면', (tester) async {
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
    final tr = Transport();
    final song = p.song;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SongView(project: p, transport: tr, host: null),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    // 구간 **객체**로 비교한다 — 씬 번호는 겹쳐서(벌스가 두 번) 순서가 바뀐 걸 못 본다
    final objBefore = [...song.sections];
    final before = [for (final s in song.sections) s.scene];
    check('1) 구간이 있다', before.length >= 3, '${before.length}개 · $before');

    // 2) 끌어서 순서 바꾸기 — 첫 줄 손잡이를 잡고 아래로
    final handles = find.byIcon(Icons.drag_indicator);
    check(
      '2) 손잡이가 있다',
      handles.evaluate().length == before.length,
      '${handles.evaluate().length}개',
    );

    final start = tester.getCenter(handles.at(0));
    final drag = await tester.startGesture(start);
    await tester.pump(const Duration(milliseconds: 120));
    for (var i = 0; i < 10; i++) {
      await drag.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await drag.up();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final after = [for (final s in song.sections) s.scene];
    final movedTo = song.sections.indexOf(objBefore[0]);
    final rest = [for (final o in objBefore.skip(1)) song.sections.indexOf(o)];
    final restKeptOrder = [
      for (var i = 1; i < rest.length; i++) rest[i] > rest[i - 1],
    ].every((x) => x);
    check(
      '3) 끌면 곡이 바뀐다',
      movedTo > 0 && restKeptOrder && song.sections.length == objBefore.length,
      '$before → $after (첫 구간이 $movedTo번째로, 나머지는 순서 유지)',
    );

    // 4) 판 수를 한 번에 — 숫자를 누르면 1·2·4·8·16
    // (**첫 줄의 지금 판 수**를 눌러야 한다. '1판' 으로 박아 두면 순서가 바뀐 뒤
    //  엉뚱한 줄을 누른다 — 처음에 그렇게 틀렸다)
    final head = song.sections[0];
    await tester.tap(find.text('${head.reps}판').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    final menu = [
      '1판',
      '2판',
      '4판',
      '8판',
      '16판',
    ].where((t) => find.text(t).evaluate().isNotEmpty).length;
    check('4) 판 수 빠른 선택', menu == 5, '$menu/5');

    await tester.tap(find.text('8판').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    check('5) 고르면 반영', head.reps == 8, '${head.reps}판');

    // 6) ＋구간 붙이기는 스크롤 없이 닿는다(아래 고정)
    check('6) 붙이기 줄 고정', find.text('＋구간 붙이기').evaluate().isNotEmpty, '화면에 보임');

    // 6-b) 위쪽 바 — 네 가지를 한 줄에 넣었더니 가운데 설명이 두 줄로 깨졌다(폰).
    //      두 줄로 나눴다: 재생 버튼이 화면 폭의 절반은 넘고, 설명은 한 줄로 끝난다.
    final playW = tester
        .getSize(find.widgetWithText(FilledButton, '곡 재생'))
        .width;
    final hint = tester.widget<Text>(find.textContaining('구간을 늘어놓고'));
    check(
      '6-b) 위쪽 바 두 줄',
      playW > 200 && hint.maxLines == 1,
      '재생 버튼 ${playW.round()}px(화면 400) · 설명 ${hint.maxLines}줄',
    );

    // 7) 가로·세로 안 넘침
    tester.view.physicalSize = const Size(800, 400);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SongView(project: p, transport: tr, host: null),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final err = tester.takeException();
    check('7) 가로·세로 안 넘침', err == null, '넘침 예외 ${err ?? '없음'}');

    // ── 8) **보는 방식 둘이 같은 자료를 본다** ──
    //
    // 구간 목록과 타임라인은 화면이 둘이지 자료는 하나다(`Arrangement.sections`).
    // 타임라인은 그 목록에서 마디 자리를 셈으로 뽑아 그릴 뿐이라, 어느 쪽에서
    // 고쳐도 다른 쪽에 그대로 있다. **두 벌을 들고 맞추는 길이 아니다** —
    // 그랬으면 반드시 한쪽만 고치는 날이 온다.
    {
      // 7) 가 가로(800x400)로 눕혀 놓고 끝난다 — 세로로 되돌리고 시작한다
      tester.view.physicalSize = const Size(400, 800);
      final p2 = Project.initial();
      final tr2 = Transport();
      var mode = 'list';
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: StatefulBuilder(
            builder: (ctx, setSt) => Scaffold(
              body: SongView(
                project: p2,
                transport: tr2,
                host: null,
                mode: mode,
                onMode: (m) => setSt(() => mode = m),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      final n0 = p2.song.sections.length;
      final reps0 = [for (final x in p2.song.sections) x.reps];

      // 타임라인으로 간다
      await tester.tap(find.text('타임라인'));
      await tester.pump(const Duration(milliseconds: 16));
      final onTimeline =
          mode == 'timeline' &&
          find.byType(ReorderableListView).evaluate().isEmpty;

      // 자료는 그대로여야 한다 — 옮겨 담는 코드가 없으니 변할 수가 없다
      final same =
          p2.song.sections.length == n0 &&
          [for (final x in p2.song.sections) x.reps].join() == reps0.join();

      // 타임라인에서 첫 구간을 골라 판 수를 올린다.
      // 씬 이름은 아래 「＋구간 붙이기」 칩에도 있어서 블록만 집는 표시를 쓴다 —
      // '2판 · 0:08' 은 블록에만 있다.
      await tester.tap(find.textContaining('판 · ').first);
      await tester.pump(const Duration(milliseconds: 16));
      final barShown = find.byIcon(Icons.content_copy).evaluate().isNotEmpty;
      await tester.tap(find.byIcon(Icons.add).last);
      await tester.pump(const Duration(milliseconds: 16));
      final bumped = p2.song.sections.first.reps == reps0.first + 1;

      // 목록으로 돌아오면 그 값이 그대로 보인다
      await tester.tap(find.text('구간 목록'));
      await tester.pump(const Duration(milliseconds: 16));
      final backOk =
          mode == 'list' &&
          find.byType(ReorderableListView).evaluate().isNotEmpty &&
          find.text('${p2.song.sections.first.reps}판').evaluate().isNotEmpty;

      check(
        '8) 목록 ↔ 타임라인이 같은 자료',
        onTimeline && same && barShown && bumped && backOk,
        '전환 $onTimeline · 자료 그대로 $same · 손잡이 $barShown · '
            '판수 ${reps0.first}→${p2.song.sections.first.reps} · 돌아오기 $backOk',
      );

      // 8-b) 타임라인에서 「한 벌 더」 → **바로 뒤에** 같은 씬이 생긴다
      //
      // 두 번째 블록을 쓴다 — 첫 블록은 위에서 이미 골라 뒀고, 같은 것을 다시
      // 누르면 고르기가 풀린다(그게 맞는 동작이다).
      final before = p2.song.sections.length;
      final secondScene = p2.song.sections[1].scene;
      await tester.tap(find.text('타임라인'));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tap(find.textContaining('판 · ').at(1));
      await tester.pump(const Duration(milliseconds: 16));
      // 손잡이 줄은 **옆으로 흐른다**(작은 폰에서 아홉을 다 못 놓는다) —
      // 화면 밖에 있으면 눌러도 아무 일이 없다. 먼저 끌어온다.
      await tester.ensureVisible(find.byIcon(Icons.content_copy));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.content_copy));
      await tester.pump(const Duration(milliseconds: 16));
      check(
        '8-b) 바로 뒤에 한 벌 더',
        p2.song.sections.length == before + 1 &&
            p2.song.sections[2].scene == secondScene,
        '$before개 → ${p2.song.sections.length}개 · '
            '셋째 자리 씬 ${p2.song.sections[2].scene}(둘째 구간 $secondScene)',
      );
    }

    // ── 9) **곡 길이를 목표에 맞춘다** ──
    //
    // 구간을 하나씩 더하고 빼서 3분을 맞추는 것은 셈이지 음악이 아니다.
    // 마디가 아니라 **초**로 잰다 — 78BPM 로파이와 128BPM 하우스는 같은 마디
    // 수라도 길이가 배로 다르다.
    {
      tester.view.physicalSize = const Size(400, 800);
      final p3 = Project.initial();
      final tr3 = Transport();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SongView(project: p3, transport: tr3, host: null),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      final before = SceneSequencer.songSeconds(p3, tr3);

      await tester.tap(find.textContaining('길게'));
      await tester.pump(const Duration(milliseconds: 16));
      final long = SceneSequencer.songSeconds(p3, tr3);

      await tester.tap(find.textContaining('짧게'));
      await tester.pump(const Duration(milliseconds: 16));
      final short = SceneSequencer.songSeconds(p3, tr3);

      check(
        '9) 길이를 맞춘다',
        (long - kSongTargets['길게']!).abs() < 30 &&
            (short - kSongTargets['짧게']!).abs() < 30 &&
            short < long,
        '${before.round()}초 → 길게 ${long.round()}초 · 짧게 ${short.round()}초',
      );
      check(
        '9-b) 되돌릴 수 있다',
        find.text('되돌리기').evaluate().isNotEmpty,
        '스낵바에 되돌리기',
      );
    }

    // ── 10) **구간마다 어떤 가락인지 보인다** ──
    //
    // 색 띠(`_TypeStrip`)는 「무엇이 들어 있나」만 말한다 — 벌스가 둘이면 둘 다
    // 「드럼·베이스·코드·멜로디」다. 음을 점으로 찍어 두면 **어떤 곡인지**가 보인다.
    // 그림 자체는 못 재니 **재료가 제대로 뽑히는가**를 본다.
    {
      final p4 = Project.initial();
      var found = 0, empty = 0;
      for (var i = 0; i < p4.scenes.length; i++) {
        final r = sectionRoll(p4, i);
        if (r == null) {
          empty++;
          continue;
        }
        found++;
        // 칸 수가 0 이면 그리다 0 으로 나눈다
        if (r.$2 <= 0) empty++;
        // 음이 판 밖으로 나가면 막대가 칸 밖으로 삐져나온다
        for (final n in r.$1) {
          final st = (n[1] as num).toInt();
          if (st < 0 || st >= r.$2) empty++;
        }
      }
      // 없는 씬·범위 밖은 null 이어야 한다(안 죽는다)
      final safe = sectionRoll(p4, -1) == null && sectionRoll(p4, 999) == null;
      check(
        '10) 구간 미리보기 재료가 성하다',
        found > 0 && empty == 0 && safe,
        '씬 ${p4.scenes.length}개 중 $found개에 가락 있음 · 어긋남 $empty개 · '
            '범위 밖 안전 $safe',
      );
    }

    // 12) **이 씬 고치기** — 타임라인에서 구간을 고르면 바로 그 씬으로 갈 수 있다.
    //     여태는 뒤로 → 만들기 → 씬 고르기 세 걸음이었다.
    {
      final p5 = Project.initial()..setGenre('lofi');
      final tr5 = Transport();
      var asked = -1;
      tester.view.physicalSize = const Size(400, 800);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SongView(
              project: p5,
              transport: tr5,
              host: null,
              mode: 'timeline',
              onEditScene: (i) => asked = i,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      // 두 번째 블록을 고른다 — 첫 블록이면 「0번」이라 0 과 −1 을 못 가른다.
      await tester.tap(find.textContaining('판 · ').at(1));
      await tester.pump(const Duration(milliseconds: 16));
      final btn = find.byIcon(Icons.edit_note);
      check('12) 고친 손잡이가 있다', btn.evaluate().isNotEmpty, '');
      if (btn.evaluate().isNotEmpty) {
        await tester.tap(btn.first);
        await tester.pump(const Duration(milliseconds: 16));
      }
      check(
        '12-b) 그 구간의 씬을 부른다',
        asked == p5.song.sections[1].scene,
        '부른 씬 $asked · 그 구간 씬 ${p5.song.sections[1].scene}',
      );
      check('12-c) 넘침 없음', tester.takeException() == null, '');

      // 12-d) **구간 손잡이 줄은 고른 뒤에만 나온다** — 작은 폰 넘침 검사가
      //       그걸 못 본다(안 고르면 줄이 없으니까). 여기서 골라 둔 채로 재 본다.
      tester.view.physicalSize = const Size(320, 640);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      check('12-d) 320dp 에서도 안 넘친다', tester.takeException() == null, '');
      tester.view.physicalSize = const Size(400, 800);
    }

    // 11) **타임라인에 악기 줄이 있다** — 씬 줄 하나로는 「악기별로 넣기」가 안 된다.
    {
      final p3 = Project.initial()..setGenre('lofi');
      final tr3 = Transport();
      tester.view.physicalSize = const Size(400, 800);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SongView(
              project: p3,
              transport: tr3,
              host: null,
              mode: 'timeline',
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));

      final laneNames = [
        for (final t in p3.tracks) t.name,
      ].where((n) => find.text(n).evaluate().isNotEmpty).length;
      check(
        '11) 악기 줄이 다 있다',
        laneNames == p3.tracks.length,
        '$laneNames/${p3.tracks.length}줄',
      );
      check('11-b) 마디 눈금이 있다', find.text('마디').evaluate().isNotEmpty, '');

      // 11-c) 빈 칸을 누르면 패턴 고르기가 열리고, 고르면 **클립이 놓인다**
      final drum = p3.tracks.firstWhere((t) => t.type == 'drum');
      await tester.tapAt(
        tester.getTopLeft(find.text(drum.name)) + const Offset(120, 8),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final sheetOpen = find.textContaining('패턴').evaluate().isNotEmpty;
      check('11-c) 칸을 누르면 패턴 서랍', sheetOpen, '');
      if (sheetOpen) {
        // 칩에 적히는 것은 **보여 주는 이름**(`patternLabel`)이지 저장 이름이 아니다.
        // 서랍 안에 실제로 그려진 칩 중 하나를 고른다.
        final byLabel = {
          for (final n in SceneSequencer.patternNamesFor(p3, 'drum'))
            patternLabel(n): n,
        };
        final shown = [
          for (final w in tester.widgetList<Text>(find.byType(Text)))
            if (byLabel.containsKey(w.data)) w.data!,
        ];
        final pick = shown.isEmpty ? '' : shown.first;
        if (pick.isNotEmpty) {
          await tester.tap(find.text(pick).first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
        }
        check(
          '11-d) 고르면 클립이 놓인다',
          p3.song.lanes.length == 1 && p3.song.lanes.single.trackId == drum.id,
          '${p3.song.lanes.length}개 · '
              '${p3.song.lanes.isEmpty ? '' : p3.song.lanes.single.toJson()}',
        );
      }
      check('11-e) 넘침 없음', tester.takeException() == null, '');

      // 11-h) **복사해서 붙이기.** 하나 만들어 두고 여러 자리에 붙이는 것이
      //       트랙 줄을 쓰는 제일 흔한 손짓이다(옛 앱의 `tlClip9` 자리).
      if (p3.song.lanes.isNotEmpty) {
        final put = p3.song.lanes.single;
        // 줄에 적히는 것은 **보여 주는 이름**이다(고를 때 본 그 이름).
        await tester.tap(find.text(patternLabel(put.pattern)).first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        final copyRow = find.textContaining('복사 —');
        check('11-h) 클립 메뉴에 복사', copyRow.evaluate().isNotEmpty, '');
        if (copyRow.evaluate().isNotEmpty) {
          await tester.tap(copyRow.first);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
          // 빈 칸을 꾹 누르면 붙는다 — 패턴 서랍이 열리면 안 된다
          await tester.longPressAt(
            tester.getTopLeft(find.text(drum.name)) + const Offset(240, 8),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 700));
          check(
            '11-i) 꾹 누르면 붙는다',
            p3.song.lanes.length == 2 &&
                p3.song.lanes.every((c) => c.pattern == put.pattern),
            '${p3.song.lanes.length}개 · '
                '${[for (final c in p3.song.lanes) '${c.section}-${c.bar}']}',
          );
        }
      }

      // 11-f) **재생선 자리 셈** — 초와 마디는 씬마다 빠르기가 달라 딱 비례하지
      //       않는다. 곡 절반쯤에서 마디도 절반쯤이어야 한다(같은 빠르기 곡).
      {
        final spans = SceneSequencer.songSpans(p3, tr3);
        final total = spans.isEmpty ? 0.0 : spans.last.$1 + spans.last.$2;
        final head = timelineHeadX(p3, spans, total * 0.5);
        // 곡 **끝 자리**는 마지막 마디 다음이다 — `total` 초는 어느 구간에도
        // 안 들어가므로(끝은 열린 구간이다) 마디 수로 잰다.
        var totalBars = 0;
        for (final sec in p3.song.sections) {
          totalBars += SceneSequencer.sceneLoopBars(p3, sec.scene) * sec.reps;
        }
        final end = totalBars * kTimelineBarW;
        check(
          '11-f) 재생선이 곡을 따라간다',
          head > 0 && head < end && (head / end - 0.5).abs() < 0.12,
          '절반 ${head.round()}px / 끝 ${end.round()}px',
        );
        check(
          '11-g) 곡 밖은 안 그린다',
          timelineHeadX(p3, spans, -1) < 0 &&
              timelineHeadX(p3, spans, total + 10) < 0,
          '',
        );
      }
    }

    // ignore: avoid_print
    print(fail == 0 ? '곡 화면 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
