// 가로 상단 압축 실측 (2026-09-30) — 홈 상단 바 / 탭 바 높이와 본 내용이 시작하는 y.
//   flutter test test/landscape_top_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/store.dart';
import 'package:music_doodle_engine/ui/home_view.dart';
import 'package:music_doodle_engine/ui/workspace_view.dart';

/// 탭 바(뒤로가기 아이콘을 품은 가장 위 줄) 아래에서 처음 그려지는 글자/아이콘의 y.
double _firstBelow(WidgetTester t, double barBottom) {
  double best = 1e9;
  for (final e in find.byType(Text).evaluate()) {
    final r = t.getRect(find.byElementPredicate((x) => x == e));
    if (r.top >= barBottom - 0.5 && r.top < best && r.height > 0) best = r.top;
  }
  return best;
}

void main() {
  const land = [Size(851, 393), Size(640, 360)];
  for (final size in land) {
    for (final mode in ['scene', 'timeline', 'live']) {
      testWidgets('상단 ${size.width.toInt()}x${size.height.toInt()} $mode', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);
        final p = Project.initial();
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData.dark(),
          home: ProjectWorkspace(
            project: p, transport: Transport(), live: LiveChannel(),
            master: MasterChannel(), host: null, store: null,
            simple: false, pro: true, initialMode: mode,
          ),
        ));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
        final back = find.byIcon(Icons.arrow_back);
        final bar = tester.getRect(find.ancestor(of: back, matching: find.byType(Container)).first);
        // ignore: avoid_print
        print('TOP ${size.width.toInt()}x${size.height.toInt()} $mode: 탭바 높이 ${bar.height} '
            '/ 본 내용 첫 글자 y ${_firstBelow(tester, bar.bottom)}');
        expect(bar.height, lessThanOrEqualTo(48));
        // 누를 것은 44 이상
        for (final ic in [Icons.arrow_back, Icons.settings_outlined, Icons.help_outline]) {
          final r = tester.getRect(find.ancestor(of: find.byIcon(ic), matching: find.byType(IconButton)).first);
          expect(r.height, greaterThanOrEqualTo(44), reason: '$ic');
          expect(r.width, greaterThanOrEqualTo(44), reason: '$ic');
        }
      });
    }
  }

  for (final size in [...land, const Size(400, 800)]) {
    testWidgets('홈 상단 ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      late Directory dir;
      late Store store;
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('mdtop');
        store = Store(
          project: Project.initial(), transport: Transport(), live: LiveChannel(),
          master: MasterChannel(), overrideDir: dir, seedSamples: true,
        );
        await store.start();
      });
      addTearDown(() => dir.delete(recursive: true));
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: HomeView(
          project: store.project, transport: store.transport, live: store.live,
          master: store.master, host: null, store: store, ready: true,
          onOpenLab: () {}, onSongOpened: () {},
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(tester.takeException(), isNull);
      final title = tester.getRect(find.text('음악 낙서장'));
      final a = tester.getRect(find.textContaining('질문에 답해서').first);
      // ignore: avoid_print
      print('TOP 홈 ${size.width.toInt()}x${size.height.toInt()}: 제목 y ${title.top}~${title.bottom} '
          '/ 첫 카드 글자 y ${a.top}');
      if (size.width > size.height) {
        for (final ic in [Icons.settings_outlined, Icons.help_outline]) {
          final r = tester.getRect(find.ancestor(of: find.byIcon(ic), matching: find.byType(IconButton)).first);
          expect(r.height, greaterThanOrEqualTo(44), reason: '$ic');
        }
      }
    });
  }
}
