// Phase 6 — **표지가 그 곡의 것인가.** (개선 계획 8-1)
//   flutter test test/cover_check_test.dart
//
// 표지는 「예쁘냐」로는 시험할 수 없다. 시험할 수 있는 것은 이것들이다:
//  1. 진짜 PNG 가 나오는가(크기·머리글)
//  2. **곡마다 다른가** — 장르를 바꿨는데 같은 그림이면 넣으나 마나다
//  3. **짜임이 반영되는가** — 구간이 다르면 그림도 달라야 한다
//  4. 이상한 값에도 안 죽는가(이름 없음·구간 없음·0초)
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/show_ops.dart';
import 'package:music_doodle_engine/ui/cover.dart';

CoverInfo _of(String key, {String title = '새 곡'}) {
  final g = genreDef(key);
  final p = Project.initial()..setGenre(key);
  final tr = Transport()
    ..bpm = g.bpm
    ..mode = g.mode;
  final sc = ShowScore.from(p, tr);
  return CoverInfo(
    title: title,
    genreLabel: g.label,
    genreKey: key,
    bpm: g.bpm,
    keyLabel: 'C 단조',
    seconds: sc.total,
    sections: [
      for (var i = 0; i < sc.spans.length; i++)
        (sc.sectionNames[i], sc.spans[i].$2),
    ],
  );
}

/// 그림을 **화소로** 받는다 — 견주려면 PNG 로는 안 된다(압축 결과가 달라질 수 있다).
Future<Uint8List> _raw(CoverInfo info, {int side = 240}) async {
  final rec = ui.PictureRecorder();
  final size = Size(side.toDouble(), side.toDouble());
  CoverPainter(info).paint(Canvas(rec, Offset.zero & size), size);
  final img = await rec.endRecording().toImage(side, side);
  final b = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  img.dispose();
  return b!.buffer.asUint8List();
}

double _diff(Uint8List a, Uint8List b) {
  if (a.length != b.length) return 1;
  var d = 0;
  for (var i = 0; i < a.length; i += 4) {
    if ((a[i] - b[i]).abs() > 6 ||
        (a[i + 1] - b[i + 1]).abs() > 6 ||
        (a[i + 2] - b[i + 2]).abs() > 6) {
      d++;
    }
  }
  return d / (a.length / 4);
}

void main() {
  testWidgets('곡 표지', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    await tester.runAsync(() async {
      // ── 1) 진짜 PNG ──
      final png = await renderCoverPng(_of('lofi'), side: 512);
      final isPng =
          png.length > 8 &&
          png[0] == 0x89 &&
          png[1] == 0x50 &&
          png[2] == 0x4E &&
          png[3] == 0x47;
      // IHDR 의 폭·높이(8바이트 머리글 + 4길이 + 4타입 뒤)
      final w = (png[16] << 24) | (png[17] << 16) | (png[18] << 8) | png[19];
      final h = (png[20] << 24) | (png[21] << 16) | (png[22] << 8) | png[23];
      check(
        '1) PNG 가 나온다',
        isPng && w == 512 && h == 512,
        '${png.length ~/ 1024}KB · ${w}x$h',
      );

      // ── 2) 장르마다 다르다 ──
      final byGenre = <String, Uint8List>{};
      for (final g in kGenres) {
        byGenre[g.key] = await _raw(_of(g.key));
      }
      final same = <String>[];
      final keys = byGenre.keys.toList();
      for (var i = 0; i < keys.length; i++) {
        for (var j = i + 1; j < keys.length; j++) {
          // 화소의 3% 도 안 다르면 「같은 그림」으로 본다
          if (_diff(byGenre[keys[i]]!, byGenre[keys[j]]!) < 0.03) {
            same.add('${keys[i]}=${keys[j]}');
          }
        }
      }
      check(
        '2) 장르마다 다른 표지',
        same.isEmpty,
        same.isEmpty ? '${kGenres.length}개 서로 다름' : same.take(3).join(', '),
      );

      // ── 3) 짜임이 반영된다 ──
      //
      // 같은 장르·같은 이름인데 **구간만** 바꿔서 견준다. 그림이 그대로면
      // 짜임 띠가 아무 일도 안 하는 것이다.
      final base = _of('house');
      final flat = CoverInfo(
        title: base.title,
        genreLabel: base.genreLabel,
        genreKey: base.genreKey,
        bpm: base.bpm,
        keyLabel: base.keyLabel,
        seconds: base.seconds,
        sections: const [('벌스', 60), ('벌스', 60)],
      );
      final d = _diff(await _raw(base), await _raw(flat));
      check(
        '3) 구간이 다르면 표지도 다르다',
        d > 0.01,
        '${(d * 100).toStringAsFixed(1)}% 화소가 다름',
      );

      // ── 4) 이상한 값에도 안 죽는다 ──
      final odd = [
        (
          '이름 없음',
          const CoverInfo(
            title: '',
            genreLabel: '로파이',
            genreKey: 'lofi',
            bpm: 78,
            keyLabel: 'C 단조',
            seconds: 0,
            sections: [],
          ),
        ),
        (
          '모르는 장르',
          const CoverInfo(
            title: 'x',
            genreLabel: '?',
            genreKey: '없는장르',
            bpm: 90,
            keyLabel: 'C 단조',
            seconds: 12,
            sections: [('벌스', 12)],
          ),
        ),
        (
          '0초 구간',
          const CoverInfo(
            title: 'x',
            genreLabel: '팝',
            genreKey: 'pop',
            bpm: 104,
            keyLabel: 'C 장조',
            seconds: 5,
            sections: [('인트로', 0), ('코러스', 0)],
          ),
        ),
      ];
      final died = <String>[];
      for (final o in odd) {
        try {
          final p = await renderCoverPng(o.$2, side: 120);
          if (p.isEmpty) died.add('${o.$1}(빈 파일)');
        } catch (e) {
          died.add('${o.$1}($e)');
        }
      }
      check(
        '4) 이상한 값에도 안 죽는다',
        died.isEmpty,
        died.isEmpty ? '${odd.length}가지' : died.join(', '),
      );
    });

    // ignore: avoid_print
    print(fail == 0 ? '곡 표지 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
