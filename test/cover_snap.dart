// 곡 표지를 눈으로 본다 (수동 실행). — /tmp/mdcover
//   flutter test test/cover_snap.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/show_ops.dart';
import 'package:music_doodle_engine/ui/cover.dart';

/// 시험 환경에는 한글 폰트가 없다 — 안 실으면 글씨가 전부 두부(□)로 나온다.
/// 기본 폰트 이름('Roboto')으로 실어야 표지의 모든 글씨가 이걸 쓴다.
Future<void> _loadKorean() async {
  const path = '/System/Library/Fonts/Supplemental/AppleGothic.ttf';
  final f = File(path);
  if (!f.existsSync()) return;
  final bytes = f.readAsBytesSync();
  final loader = FontLoader('Roboto')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

Future<void> _snap(String name, CoverInfo info) async {
  const side = 1080;
  final rec = ui.PictureRecorder();
  const size = Size(1080, 1080);
  CoverPainter(
    info,
    fontFamily: 'Roboto',
  ).paint(Canvas(rec, Offset.zero & size), size);
  final img = await rec.endRecording().toImage(side, side);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  final dir = Directory('/tmp/mdcover');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('  ${dir.path}/$name.png');
}

void main() {
  testWidgets('표지 그림', (tester) async {
    await _loadKorean();
    await tester.runAsync(() async {
      // ignore: avoid_print
      print('나온 그림:');
      for (final key in ['lofi', 'drill', 'jazz', 'rnb']) {
        final g = genreDef(key);
        final p = Project.initial()
          ..setGenre(key)
          ..name = '새 곡';
        final tr = Transport()
          ..bpm = g.bpm
          ..mode = g.mode;
        final sc = ShowScore.from(p, tr);
        await _snap(
          key,
          CoverInfo(
            title: '새 곡',
            genreLabel: g.label,
            genreKey: key,
            bpm: g.bpm,
            keyLabel: 'C ${g.mode == 'major' ? '장조' : '단조'}',
            seconds: sc.total,
            sections: [
              for (var i = 0; i < sc.spans.length; i++)
                (sc.sectionNames[i], sc.spans[i].$2),
            ],
          ),
        );
      }
      // 이름이 아주 길 때 — 잘리는지
      await _snap(
        '긴이름',
        CoverInfo(
          title: '아주 아주 길고 긴 곡 이름을 붙이면 어떻게 되는지 보는 곡',
          genreLabel: '프로그하우스',
          genreKey: 'proghouse',
          bpm: 128,
          keyLabel: 'C 단조',
          seconds: 210,
          sections: const [('인트로', 20), ('그루브', 30), ('빌드업', 20), ('드롭', 40)],
        ),
      );
    });
  });
}
