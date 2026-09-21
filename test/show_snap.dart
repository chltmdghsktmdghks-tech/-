// 쇼 화면 밴드를 **그림 파일로 뽑는다** (손으로 돌리는 도구, `_test.dart` 아님).
//   flutter test test/show_snap.dart
//
// 폰이 없을 때 그림을 눈으로 확인할 방법이 없어서 만들었다.
// `CustomPainter` 를 화면 없이 캔버스에 그려 PNG 로 떨어뜨린다.
// 나오는 곳: /tmp/mdshow/*.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/ui/show_band.dart';

Future<void> _snap(String name, BandPainter p, Size size) async {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec, Offset.zero & size);
  p.paint(canvas, size);
  final img = await rec.endRecording().toImage(
    size.width.round(),
    size.height.round(),
  );
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  final dir = Directory('/tmp/mdshow');
  if (!dir.existsSync()) dir.createSync(recursive: true);
  final f = File('${dir.path}/$name.png');
  f.writeAsBytesSync(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('  ${f.path}');
}

BandMember _m(
  String name,
  String type,
  Color c,
  double lv,
  double hit, {
  String voice = '',
}) => BandMember(
  name: name,
  type: type,
  voice: voice,
  color: c,
  level: lv,
  hit: hit,
  muted: false,
);

void main() {
  testWidgets('쇼 화면 그림 뽑기', (tester) async {
    const size = Size(400, 720);
    final four = [
      _m('드럼', 'drum', const Color(0xFF7CB342), 0, 0),
      _m('신스 베이스', 'bass', const Color(0xFF42A5F5), 0.9, 0.9),
      _m('패드', 'chord', const Color(0xFFAB47BC), 0.45, 0.0), // 서스테인 중
      _m('리드', 'melody', const Color(0xFFFFA726), 0.2, 0.2),
    ];
    final six = [
      ...four,
      _m('색소폰', 'melody', const Color(0xFFFFA726), 0.6, 0.6),
      _m('기타', 'bass', const Color(0xFF42A5F5), 0.3, 0.3),
      _m('피아노', 'chord', const Color(0xFFAB47BC), 0.45, 0.0),
    ];
    // **같은 악기 다섯**. 여기서 다섯이 똑같이 보이면 개성 코드가 안 먹은 것이다.
    final same = [
      _m('드럼', 'drum', const Color(0xFF7CB342), 0, 0),
      for (final n in ['기타 1', '기타 2', '기타 3', '기타 4', '기타 5'])
        _m(n, 'bass', const Color(0xFF42A5F5), 0.7, 0.7),
    ];

    await tester.runAsync(() async {
      // ignore: avoid_print
      print('나온 그림:');
      await _snap(
        '1_lofi_4트랙',
        BandPainter(
          members: four,
          kick: 0.8,
          snare: 0.1,
          hat: 0.3,
          crash: 0.0,
          playing: true,
          sway: 0.3,
          lights: kStageLights['lofi']!,
        ),
        size,
      );
      await _snap(
        '2_house_7트랙',
        BandPainter(
          members: six,
          kick: 0.2,
          snare: 0.9,
          hat: 0.6,
          crash: 0.0,
          playing: true,
          sway: 0.7,
          lights: kStageLights['house']!,
        ),
        size,
      );
      await _snap(
        '3_구간전환_섬광',
        BandPainter(
          members: four,
          kick: 1.0,
          snare: 0.0,
          hat: 0.0,
          crash: 0.9,
          playing: true,
          sway: 0.1,
          lights: kStageLights['rock']!,
          flash: 1.0,
        ),
        size,
      );
      // 구간 성격에 따라 무대가 달아오르는가 (계획 8) — **셋을 나란히 놓고 본다.**
      // 하나씩 보면 「좀 밝네」로 끝나고 차이가 있는지 없는지 알 수 없다.
      for (final e in [('브레이크', 0.15), ('보통', 0.55), ('드롭', 1.0)]) {
        await _snap(
          '4_무대에너지_${e.$1}',
          BandPainter(
            members: four,
            kick: 0.8,
            snare: 0.1,
            hat: 0.3,
            crash: 0.0,
            playing: true,
            sway: 0.3,
            lights: kStageLights['proghouse']!,
            energy: e.$2,
          ),
          size,
        );
      }
      await _snap(
        '5_같은악기_다섯',
        BandPainter(
          members: same,
          kick: 0.5,
          snare: 0.2,
          hat: 0.4,
          crash: 0.0,
          playing: true,
          sway: 0.45,
          lights: kStageLights['citypop']!,
        ),
        size,
      );
      // 크게 — 그림 하나하나가 제대로 그려졌는지 보려면 확대해서 봐야 한다
      for (final t in [
        ('bass', '기타', 'guitar'),
        ('chord', '건반', 'piano'),
        ('melody', '색소폰', 'sax'),
      ]) {
        await _snap(
          '6_크게_${t.$2}',
          BandPainter(
            members: [
              _m('드럼', 'drum', const Color(0xFF7CB342), 0.6, 0.6),
              _m(
                '${t.$2} 하나',
                t.$1,
                const Color(0xFF42A5F5),
                0.9,
                0.9,
                voice: t.$3,
              ),
              _m(
                '${t.$2} 둘',
                t.$1,
                const Color(0xFFFFA726),
                0.9,
                0.4,
                voice: t.$3,
              ),
            ],
            kick: 0.7,
            snare: 0.3,
            hat: 0.5,
            crash: 0.0,
            playing: true,
            sway: 0.2,
            lights: kStageLights['pop']!,
          ),
          size,
        );
      }
      // 노래하는 사람 — 'vocal' 은 악기를 안 든다. 마이크만 잡는다.
      // (이게 없어서 팝·R&B·가스펠 보컬이 **관악기를 불고 있었다.**)
      for (final h in [0.0, 0.9]) {
        await _snap(
          '9_보컬_${(h * 100).round()}',
          BandPainter(
            members: [
              _m('드럼', 'drum', const Color(0xFF7CB342), 0.4, 0.4),
              _m(
                '보컬',
                'melody',
                const Color(0xFFFFA726),
                h,
                0.9,
                voice: 'vocal',
              ),
              _m(
                '색소폰',
                'melody',
                const Color(0xFF42A5F5),
                h,
                0.9,
                voice: 'sax',
              ),
              _m(
                '건반',
                'chord',
                const Color(0xFFBA68C8),
                0.5,
                0.6,
                voice: 'piano',
              ),
            ],
            kick: 0.6,
            snare: 0.3,
            hat: 0.5,
            crash: 0.0,
            playing: true,
            sway: 0.2,
            lights: kStageLights['gospel']!,
          ),
          const Size(560, 640),
        );
      }
      // 드럼만 크게 — **킥·스네어·하이햇 생김새를 눈으로 따지려고** 만든 장면
      // (5단계 50/N). 편성이 둘뿐이면 scale 이 커져서 쇠붙이까지 보인다.
      // 스틱 높이는 **다음 박까지의 진행도**가 정한다(5단계 53/N).
      // 0=친 순간 · 0.45=리바운드 꼭대기 · 1=다시 내려와 치기 직전 · −1=쉼.
      // 네 장을 나란히 놓고 봐야 '치고 있는' 것으로 보이는지 판단이 된다.
      for (final ph in [0.0, 0.45, 0.9, -1.0]) {
        await _snap(
          '8_드럼_스틱_${ph < 0 ? '쉼' : (ph * 100).round()}',
          BandPainter(
            members: [
              _m('드럼', 'drum', const Color(0xFF7CB342), 0, 0),
              _m('베이스', 'bass', const Color(0xFF42A5F5), 0.3, 0.0),
            ],
            kick: ph == 0 ? 1.0 : 0.0,
            snare: ph == 0 ? 1.0 : 0.0,
            hat: ph == 0 ? 1.0 : 0.3,
            crash: 0.0,
            playing: true,
            sway: 0.2,
            snarePhase: ph,
            hatPhase: ph < 0 ? -1.0 : (ph + 0.3) % 1.0,
            lights: kStageLights['rock']!,
          ),
          const Size(420, 640),
        );
      }
      // 가로 — 쇼는 눕혀 놓고 보는 화면이다. 세로만 보고 넘기면 안 된다.
      await _snap(
        '7_가로',
        BandPainter(
          members: six,
          kick: 0.8,
          snare: 0.2,
          hat: 0.5,
          crash: 0.0,
          playing: true,
          sway: 0.35,
          lights: kStageLights['rock']!,
        ),
        const Size(800, 400),
      );
      await _snap(
        '4_멈춤',
        BandPainter(
          members: [
            for (final m in four)
              BandMember(
                name: m.name,
                type: m.type,
                voice: m.voice,
                color: m.color,
                level: 0,
                hit: 0,
                muted: false,
              ),
          ],
          kick: 0,
          snare: 0,
          hat: 0,
          crash: 0,
          playing: false,
          sway: 0.5,
          lights: kStageLights['jazz']!,
        ),
        size,
      );
    });
  });
}
