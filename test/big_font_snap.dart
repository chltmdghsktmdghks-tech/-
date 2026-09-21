// 글자를 키운 폰(1.3배) 화면을 그림으로 뽑는다 — 손으로 돌리는 도구.
//   flutter test test/big_font_snap.dart   → /tmp/mdbig/*.png
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/create_sheet.dart';
import 'package:music_doodle_engine/ui/scene_view.dart';
import 'package:music_doodle_engine/ui/song_view.dart';
import 'package:music_doodle_engine/ui/mixer_view.dart';

final _k = GlobalKey();
void main() {
  testWidgets('큰 글자 그림', (tester) async {
    await tester.runAsync(() async {
      final f = File('/System/Library/Fonts/Supplemental/AppleGothic.ttf');
      if (!f.existsSync()) return;
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
      await loader.load();
    });
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final p = Project.initial()..name = '나무';
    final tr = Transport();
    Future<void> shot(String name, Widget body, {String? title}) async {
      await tester.pumpWidget(
        RepaintBoundary(
          key: _k,
          child: MaterialApp(
            key: ValueKey(name),
            theme: ThemeData.dark(),
            builder: (c, ch) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: ch!,
            ),
            home: title == null
                ? body
                : Scaffold(
                    appBar: AppBar(title: Text(title)),
                    body: body,
                  ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(() async {
        final b =
            _k.currentContext!.findRenderObject() as RenderRepaintBoundary;
        final img = await b.toImage(pixelRatio: 2.0);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        Directory('/tmp/mdbig').createSync(recursive: true);
        File(
          '/tmp/mdbig/$name.png',
        ).writeAsBytesSync(png!.buffer.asUint8List());
      });
    }

    await shot(
      '씬',
      SceneView(project: p, transport: tr, host: null),
      title: '씬',
    );
    await shot(
      '곡',
      SongView(project: p, transport: tr, host: null),
      title: '곡',
    );
    await shot(
      '시작하기',
      Scaffold(
        backgroundColor: const Color(0xFF16161A),
        body: CreateSheetBody(onPick: (_) {}),
      ),
    );
    await shot(
      '믹서',
      MixerView(
        project: p,
        live: LiveChannel(),
        master: MasterChannel(),
        host: null,
      ),
      title: '믹서',
    );
  });
}
