// 캐릭터를 **눈으로 보는** 자리. 시험이 아니라 그림을 뽑는 도구다.
//   flutter test test/critter_snap.dart
// 나오는 곳: /tmp/mdcritter/critters.png  (11종 × 8자세)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/ui/critters.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('캐릭터 그림 뽑기', () async {
    const poses = [0.0, 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75];
    const cell = 56.0;
    const label = 62.0;
    final w = label + cell * poses.length;
    final h = cell * kCritterList.length;

    final rec = ui.PictureRecorder();
    final c = Canvas(rec, Rect.fromLTWH(0, 0, w, h));
    c.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()..color = const Color(0xFF141418),
    );

    for (var r = 0; r < kCritterList.length; r++) {
      final d = kCritterList[r];
      final tp = TextPainter(
        text: TextSpan(
          text: d.name,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: label - 6);
      tp.paint(c, Offset(4, r * cell + cell / 2 - 7));

      for (var i = 0; i < poses.length; i++) {
        c.save();
        c.translate(label + i * cell + (cell - kCritW * 1.0) / 2, r * cell + 2);
        c.clipRect(const Rect.fromLTWH(0, 0, kCritW, kCritH));
        d.draw(c, poses[i], Colors.white);
        c.restore();
      }
    }

    final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory('/tmp/mdcritter').createSync(recursive: true);
    File(
      '/tmp/mdcritter/critters.png',
    ).writeAsBytesSync(png!.buffer.asUint8List());
    // ignore: avoid_print
    print('  /tmp/mdcritter/critters.png  (${w.toInt()}×${h.toInt()})');
  });
}
