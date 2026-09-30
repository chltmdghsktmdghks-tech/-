// 가로 적응 2순위 — 홈·곡(타임라인)·라이브 (2026-09-30).
//   flutter test test/landscape_layout2_test.dart
//
// 볼 것: (1) 가로 크기 셋에서 overflow 가 없다 (2) 넓은 화면을 실제로 쓴다
// (홈은 두 입구가 좌우로, 곡은 타임라인이 더 높이·넓게, 라이브는 패드가 커진다)
// (3) 세로(400x800)는 예전 배치 그대로다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/store.dart';
import 'package:music_doodle_engine/ui/home_view.dart';
import 'package:music_doodle_engine/ui/live_view.dart';
import 'package:music_doodle_engine/ui/song_view.dart';

const _sizes = [Size(851, 393), Size(640, 360), Size(2340, 1080)];

void _setSize(WidgetTester t, Size s) {
  t.view.physicalSize = s;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

void main() {
  // ───────────── 홈 ─────────────
  for (final size in [..._sizes, const Size(400, 800)]) {
    testWidgets('홈 ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      _setSize(tester, size);
      late Directory dir;
      late Store store;
      await tester.runAsync(() async {
        dir = await Directory.systemTemp.createTemp('mdland');
        store = Store(
          project: Project.initial(),
          transport: Transport(),
          live: LiveChannel(),
          master: MasterChannel(),
          overrideDir: dir,
          seedSamples: true,
        );
        await store.start();
      });
      addTearDown(() => dir.delete(recursive: true));
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: HomeView(
          project: store.project,
          transport: store.transport,
          live: store.live,
          master: store.master,
          host: null,
          store: store,
          ready: true,
          onOpenLab: () {},
          onSongOpened: () {},
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(tester.takeException(), isNull);

      final a = tester.getTopLeft(find.textContaining('질문에 답해서').first);
      final b = tester.getTopLeft(find.text('두드려서 만들기').first);
      // ignore: avoid_print
      print('홈 ${size.width.toInt()}x${size.height.toInt()}: 입구 A$a B$b');
      if (size.width > size.height) {
        // 가로: 두 입구가 같은 높이에서 좌우로
        expect((a.dy - b.dy).abs(), lessThan(2));
        expect(b.dx, greaterThan(a.dx + 150));
      } else {
        // 세로: 예전처럼 위아래
        expect(b.dy, greaterThan(a.dy + 40));
      }
    });
  }

  // ───────────── 곡(구간 목록·타임라인) ─────────────
  for (final mode in ['timeline', 'list']) {
    for (final size in [..._sizes, const Size(400, 800)]) {
      testWidgets('곡 $mode ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        _setSize(tester, size);
        final p = Project.initial();
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SongView(
              project: p,
              transport: Transport(),
              host: null,
              mode: mode,
              onMode: (_) {},
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);

        if (mode == 'timeline') {
          // 트랙 이름(드럼 등)이 몇 줄 보이는가 — 가로에서 세로 스크롤 없이 많이 보여야 한다
          final shown = [for (final t in p.tracks) t.name]
              .where((n) => find.text(n).evaluate().isNotEmpty)
              .length;
          // ignore: avoid_print
          print('곡 타임라인 ${size.width.toInt()}x${size.height.toInt()}: '
              '트랙 $shown/${p.tracks.length}');
          if (size.width > size.height && size.height < 520) {
            expect(shown, greaterThanOrEqualTo(3));
            // ＋구간 붙이기가 위 줄로 올라가 있다 (아래 고정이 아니다)
            final add = tester.getTopLeft(find.text('＋구간 붙이기').first);
            expect(add.dy, lessThan(size.height / 2));
          }
        }
      });
    }
  }

  // ───────────── 라이브 ─────────────
  for (final chromatic in [false, true]) {
    for (final size in [..._sizes, const Size(400, 800)]) {
      testWidgets(
          '라이브 ${chromatic ? '반음 ' : ''}${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        _setSize(tester, size);
        final p = Project.initial();
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: LiveView(
              project: p,
              transport: Transport(),
              live: LiveChannel(),
              host: null,
            ),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 50));
        if (chromatic) {
          await tester.tap(find.text('반음'));
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(tester.takeException(), isNull);

        if (!chromatic) {
          // 패드 한 칸("1")의 높이·폭
          final pad = find.text('1').first;
          final box = tester.getSize(find.ancestor(
            of: pad,
            matching: find.byType(AnimatedContainer),
          ).first);
          // ignore: avoid_print
          print('라이브 ${size.width.toInt()}x${size.height.toInt()}: '
              '패드 ${box.width.toStringAsFixed(0)}x${box.height.toStringAsFixed(0)}');
          if (size.width > size.height && size.height < 520) {
            // 예전 가로는 높이 ≈90 이었다
            expect(box.height, greaterThan(120));
          }
        }
        // 재생·녹음 버튼과 슬라이더가 화면 안에 있다
        final play = tester.getRect(find.text('반주').first);
        expect(play.bottom, lessThanOrEqualTo(size.height));
        expect(find.text('볼륨'), findsOneWidget);
      });
    }
  }
}
