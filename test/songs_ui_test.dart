// 5단계 27/N — 곡 목록 확인.
//   flutter test test/songs_ui_test.dart
//
// 곡이 서너 개만 넘어도 "이름이 뭐였더라 / 어느 게 긴 거였더라"가 시작된다.
// 그리고 **이름 바꾸기가 ⋮ 안에 있으면 있는 줄도 모른다** — 곡 이름이 전부
// '새 곡 2' 로 남는 이유가 그거다. 그 둘을 본다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/store.dart';
import 'package:music_doodle_engine/ui/songs_view.dart';

void main() {
  testWidgets('곡 목록', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 파일을 실제로 쓰고 읽는다 → **`runAsync` 안에서** 해야 한다.
    // 위젯 시험은 가짜 시계 위에서 도는데, 진짜 파일 I/O 는 그 시계로는 안 끝난다
    // (그냥 부르면 시험이 통째로 멈춘다 — 여기서 겪었다).
    late Directory dir;
    final p = Project.initial();
    late Store store;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('mdsongs');
      store = Store(
        project: p,
        transport: Transport(),
        live: LiveChannel(),
        master: MasterChannel(),
        overrideDir: dir,
      );
      await store.start();
      // 곡 셋 — 이름·길이·시각이 서로 다르게.
      // 첫 곡의 기본 이름('새 곡')은 **머리말의 「새 곡」 버튼과 글자가 같아서**
      // 화면에서 곡 이름을 찾을 때 둘이 겹친다 → 다른 이름으로 바꿔 둔다.
      await store.saveNow();
      await store.rename(store.songs.first.id, '마바사');
      await store.newSong(name: '가나다');
      p.setGenre('trap'); // 더 긴 곡
      await store.saveNow();
      await store.newSong(name: '하하하');
      await store.saveNow();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SongsView(store: store, project: p, onOpened: () {}),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    check(
      '1) 곡 셋',
      store.songs.length == 3,
      '${[for (final s in store.songs) s.name].join(',')}',
    );

    // 2) 정렬 칩이 있다
    final chips = [
      '최근',
      '이름',
      '길이',
    ].where((t) => find.text(t).evaluate().isNotEmpty).length;
    check('2) 정렬 칩', chips == 3, '$chips/3');

    /// 화면에 그려진 순서대로 곡 이름을 읽는다
    List<String> shown() {
      final names = [for (final s in store.songs) s.name];
      final found = <(double, String)>[];
      for (final n in names) {
        final f = find.text(n);
        if (f.evaluate().isEmpty) continue;
        found.add((tester.getTopLeft(f).dy, n));
      }
      found.sort((a, b) => a.$1.compareTo(b.$1));
      return [for (final e in found) e.$2];
    }

    // 3) 이름순
    await tester.tap(find.text('이름'));
    await tester.pump(const Duration(milliseconds: 16));
    final byName = shown();
    final sortedNames = [...byName]..sort();
    check(
      '3) 이름순',
      byName.join(',') == sortedNames.join(','),
      byName.join(' → '),
    );

    // 4) 길이순 — 긴 곡이 위로
    await tester.tap(find.text('길이'));
    await tester.pump(const Duration(milliseconds: 16));
    final byLen = shown();
    final secOf = {for (final s in store.songs) s.name: s.sec};
    var lenOk = true;
    for (var i = 1; i < byLen.length; i++) {
      if ((secOf[byLen[i - 1]] ?? 0) < (secOf[byLen[i]] ?? 0)) lenOk = false;
    }
    check(
      '4) 길이순',
      lenOk,
      [for (final n in byLen) '$n(${(secOf[n] ?? 0).round()}s)'].join(' → '),
    );

    // 5) 이름 바꾸기가 **밖에** 있다 (⋮ 를 안 열어도 보인다)
    check(
      '5) 이름 바꾸기 버튼',
      find.byIcon(Icons.drive_file_rename_outline).evaluate().length == 3,
      '줄마다 하나씩',
    );

    // 6) 눌러서 실제로 바뀐다
    await tester.tap(find.byIcon(Icons.drive_file_rename_outline).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), '새 이름');
    await tester.tap(find.text('확인'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump();
    check(
      '6) 이름이 바뀐다',
      store.songs.any((s) => s.name == '새 이름'),
      '${[for (final s in store.songs) s.name].join(',')}',
    );

    // 7) **삭제는 되돌릴 수 있어야 한다.** 「⋮」의 「복제」 바로 아래가 「삭제」인데
    // 여태는 확인도 없이 곡이 사라졌다. 지우고 나서 「되돌리기」가 뜨고,
    // 그걸 누르면 **곡이 실제로 돌아오는지** 까지 본다(스낵바만 뜨는 건 소용없다).
    final victim = store.songs.last.name;
    final before = store.songs.length;
    await tester.tap(find.byIcon(Icons.more_vert).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // 탭을 **runAsync 안에서** 한다 — 누른 뒤 이어지는 것이 진짜 파일 I/O 라
    // 가짜 시계 위에서는 영영 안 끝난다(여기서 겪었다: 눌러도 3개 그대로였다).
    await tester.runAsync(() async {
      await tester.tap(find.text('삭제'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final deleted = store.songs.length == before - 1;
    final hasUndo = find.text('되돌리기').evaluate().isNotEmpty;
    check(
      '7) 지우면 되돌리기가 뜬다',
      deleted && hasUndo,
      '${store.songs.length}개 · 되돌리기 ${hasUndo ? '있음' : '없음'}',
    );

    if (hasUndo) {
      await tester.runAsync(() async {
        await tester.tap(find.text('되돌리기'));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
    }
    check(
      '7-b) 누르면 곡이 돌아온다',
      store.songs.length == before && store.songs.any((x) => x.name == victim),
      '${store.songs.length}개 · ${[for (final x in store.songs) x.name].join(',')}',
    );

    // 9) **줄 순서가 안 움직인다.** 곡을 열면 앞 곡이 저장되면서 시각이 갱신되는데,
    //    「최근」 정렬이 그때마다 다시 늘어서면 누르려던 곡이 딴 자리로 간다 —
    //    두어 번 오가면 **엉뚱한 곡을 연다**(폰에서 겪은 그 일이다).
    {
      List<String> shown() => [
        for (final w in tester.widgetList<ListTile>(find.byType(ListTile)))
          ((w.title as Text).data ?? ''),
      ];
      final before = shown();
      // 맨 아래 곡을 연다 → 열리는 순간 그 곡이 '최근'이 된다
      final target = before.last;
      await tester.runAsync(() async {
        await tester.tap(find.text(target));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final after = shown();
      check(
        '9) 곡을 열어도 줄 순서가 그대로',
        after.join(',') == before.join(','),
        '${before.join(',')} → ${after.join(',')}',
      );
      // **재는 시늉이 아닌지** 같이 본다 — 얼리지 않았다면 정말 순서가
      // 바뀌었어야 한다. 안 바뀌는 판이면 이 검사는 늘 통과한다(무의미).
      final live = [...store.songs]
        ..sort((a, b) => b.updated.compareTo(a.updated));
      check(
        '9-b) 얼리지 않았다면 바뀌었을 것',
        [for (final x in live) x.name].join(',') != before.join(','),
        '지금 최근순 ${[for (final x in live) x.name].join(',')}',
      );
    }

    // 8) 「파일에서 가져오기」가 **늘 보인다** — 꺼내기만 있으면 백업이 반쪽이다.
    //    ⋮ 안에 넣지 않았다(꺼내기와 달리 이건 곡 하나에 대한 일이 아니다).
    check('8) 가져오기 줄이 보인다', find.text('파일에서 가져오기').evaluate().isNotEmpty, '');
    check('8-b) 넘침 없음', tester.takeException() == null, '');

    // 8-c) 좁은 폰에서도 — 위 줄(정렬 칩 + 「새 곡」)과 자리를 다투면 안 된다.
    tester.view.physicalSize = const Size(320, 640);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    check(
      '8-c) 320dp 에서도 보인다',
      find.text('파일에서 가져오기').evaluate().isNotEmpty &&
          tester.takeException() == null,
      '',
    );

    store.detach();
    await tester.runAsync(() => dir.delete(recursive: true));

    // ignore: avoid_print
    print(fail == 0 ? '곡 목록 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
