// 두들 타격 그림을 **눈으로 보는** 도구(시험 아님). 화면에 물결·방향 화살·롤 링을 띄워 PNG 로 뽑는다.
//   flutter test test/doodle_fx_snap.dart
// 나오는 곳: /tmp/mddoodlefx/*.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/doodle_play_view.dart';

void main() {
  final key = GlobalKey();
  Future<void> shot(WidgetTester t, String name) async {
    await t.runAsync(() async {
      final b = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final img = await b.toImage();
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('/tmp/mddoodlefx').createSync(recursive: true);
      File('/tmp/mddoodlefx/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  Future<void> open(WidgetTester t, {String? tab, String? chordVoice}) async {
    t.view.physicalSize = const Size(400, 860);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final proj = Project.initial();
    if (chordVoice != null) {
      proj.tracks.firstWhere((x) => x.type == 'chord').voice = chordVoice;
    }
    await t.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: DoodlePlayView(project: proj, transport: Transport(), host: null),
      ),
    ));
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.text('이 순서로 시작'));
    await t.pump(const Duration(milliseconds: 100));
    if (tab != null) {
      await t.tap(find.text(tab).first);
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> wait(WidgetTester t, int ms) async {
    await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await t.pump(const Duration(milliseconds: 16));
  }

  testWidgets('snap chord left', (t) async {
    await open(t, tab: 'CHORD');
    await shot(t, 'chord_idle');
    final g = await t.startGesture(const Offset(50, 300));
    await t.pump();
    await wait(t, 90);
    await shot(t, 'chord_left_tap');
    await g.up();
    await wait(t, 700);
  });

  testWidgets('snap snare roll', (t) async {
    await open(t, tab: 'SNARE');
    final g = await t.startGesture(const Offset(200, 420));
    await t.pump();
    await wait(t, 120);
    await shot(t, 'snare_charge');
    await g.up();
    await wait(t, 600);
    // 세게 / 여리게 나란히
    final a = await t.startGesture(const Offset(200, 380));
    await t.pump();
    final b = await t.startGesture(const Offset(30, 700));
    await t.pump();
    await wait(t, 110);
    await shot(t, 'snare_hits');
    await a.up();
    await b.up();
    await wait(t, 600);
  });

  testWidgets('snap ripples by vel', (t) async {
    await open(t);
    final gs = [
      await t.startGesture(const Offset(320, 260)),
      await t.startGesture(const Offset(200, 420)),
      await t.startGesture(const Offset(90, 720)),
    ];
    await t.pump();
    await wait(t, 60);
    await shot(t, 'ripples_60ms');
    await wait(t, 110);
    await shot(t, 'ripples_170ms');
    for (final g in gs) {
      await g.up();
    }
    await wait(t, 600);
  });

  testWidgets('snap swell', (t) async {
    await open(t, tab: 'CHORD', chordVoice: 'pad');
    final g = await t.startGesture(const Offset(220, 780));
    await t.pump();
    await g.moveBy(const Offset(0, -150));
    await t.pump();
    await wait(t, 40);
    await shot(t, 'swell');
    await g.up();
    await wait(t, 600);
  });

  testWidgets('snap hat open charge', (t) async {
    await open(t, tab: 'HI-HAT');
    final g = await t.startGesture(const Offset(200, 700));
    await t.pump();
    await wait(t, 130);
    await shot(t, 'hat_open_charge');
    await g.up();
    await wait(t, 600);
  });
}
