// 가로(2340x1080 실기기 ≈ 851x393dp) 배치 확인 — overflow 없음, 트랙이 여러 줄 보임, 탭 글자 안 잘림.
//   flutter test test/landscape_layout_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/scene_view.dart';
import 'package:music_doodle_engine/ui/workspace_view.dart';

void main() {
  for (final size in const [Size(851, 393), Size(640, 360), Size(400, 800)]) {
    testWidgets('씬 화면 ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final p = Project.initial();
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: SceneView(project: p, transport: Transport(), host: null)),
      ));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
      if (size.width > size.height) {
        final shown = [for (final t in p.tracks) t.name]
            .where((n) => find.text(n).evaluate().isNotEmpty)
            .length;
        // ignore: avoid_print
        print('가로 ${size.width}x${size.height}: 트랙 $shown/${p.tracks.length} 보임');
        expect(shown, greaterThanOrEqualTo(2));
        // 재생 버튼과 첫 트랙이 좌우로 나란히
        final play = tester.getTopLeft(find.text('재생').first);
        final first = tester.getTopLeft(find.text(p.tracks.first.name).first);
        expect(first.dx, greaterThan(play.dx + 100));
      }
    });
  }

  testWidgets('상단 탭 라벨이 가로에서 안 잘린다', (tester) async {
    tester.view.physicalSize = const Size(851, 393);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final p = Project.initial();
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: ProjectWorkspace(
        project: p, transport: Transport(), live: LiveChannel(),
        master: MasterChannel(), host: null, store: null,
        simple: false, pro: true,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      final d = t.data ?? '';
      if (['씬', '타임라인', '라이브', '쇼'].contains(d)) {
        final box = tester.renderObject<RenderBox>(find.byWidget(t));
        final tp = TextPainter(
          text: TextSpan(text: d, style: t.style ?? const TextStyle(fontSize: 12.5)),
          textDirection: TextDirection.ltr,
        )..layout();
        // ignore: avoid_print
        print('탭 "$d" 폭 ${box.size.width} / 필요 ${tp.width}');
        expect(box.size.width, greaterThanOrEqualTo(tp.width - 0.5), reason: d);
      }
    }
  });
}
