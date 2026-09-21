// 화면을 **그림 파일로 뽑는다** (손으로 돌리는 도구, `_test.dart` 아님).
//   flutter test test/screen_snap.dart
//
// 폰이 없을 때 화면을 눈으로 볼 방법이 없어서 만들었다.
// 나오는 곳: /tmp/mdscreen/*.png
//
// ── 한글 폰트 ──
// 시험 환경에는 폰트가 하나도 없다. 그냥 뽑으면 글자가 전부 **□□** 로 나온다
// (밴드 그림을 뽑을 때 처음 겪었다). 맥에 있는 애플 고딕을 실어서 쓴다.
// 폰에 들어가는 앱과는 상관없다 — 여기서만 쓴다.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/feel.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/presets.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/store.dart';
import 'package:music_doodle_engine/ui/create_sheet.dart';
import 'package:music_doodle_engine/ui/feel_sheet.dart';
import 'package:music_doodle_engine/ui/home_view.dart';
import 'package:music_doodle_engine/ui/editor_view.dart';
import 'package:music_doodle_engine/ui/live_view.dart';
import 'package:music_doodle_engine/ui/mixer_view.dart';
import 'package:music_doodle_engine/ui/scene_view.dart';
import 'package:music_doodle_engine/ui/song_view.dart';

const _out = '/tmp/mdscreen';

Future<void> _loadKorean() async {
  const path = '/System/Library/Fonts/Supplemental/AppleGothic.ttf';
  final f = File(path);
  if (!f.existsSync()) return;
  final bytes = f.readAsBytesSync();
  final loader =
      FontLoader('Roboto') // 기본 폰트 이름으로 실어야 전부 이걸 쓴다
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

final _snapKey = GlobalKey();

Future<void> _shot(WidgetTester tester, String name) async {
  // 화면을 그대로 이미지로 뽑으려면 **RepaintBoundary** 가 필요하다
  // (레이어에는 toImage 가 없다).
  final b =
      _snapKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final img = await b.toImage(pixelRatio: 2.0);
  final png = await img.toByteData(format: ui.ImageByteFormat.png);
  final dir = Directory(_out);
  if (!dir.existsSync()) dir.createSync(recursive: true);
  File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  // ignore: avoid_print
  print('  $_out/$name.png');
}

void main() {
  testWidgets('화면 그림 뽑기', (tester) async {
    await tester.runAsync(_loadKorean);

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0; // 뽑을 때 2배로 키운다(_shot)
    addTearDown(tester.view.reset);

    final p = Project.initial()..name = '나무';
    final tr = Transport();
    // 가로도 같이 뽑는다. 시험은 '안 넘쳤다'까지만 보는데, **안 넘쳐도 못 쓸 수 있다**
    // (칸이 납작해지거나 정작 만들 것이 화면 밖으로 밀려나거나).
    var landscape = false;
    void turn(bool on) {
      landscape = on;
      tester.view.physicalSize = on
          ? const Size(800, 400)
          : const Size(400, 800);
    }

    Future<void> show(String name, Widget body, {String? title}) async {
      final suffix = landscape ? '_가로' : '';
      await tester.pumpWidget(
        RepaintBoundary(
          key: _snapKey,
          child: MaterialApp(
            // **매번 새 트리로 짓는다.** 키가 같으면 플러터가 앞 화면의 Navigator 를
            // 그대로 재사용해서, 앞에서 열어 둔 대화상자가 다음 그림에 그대로 남는다
            // (가로 그림에 믹서 시트가 덮여 나와서 알았다).
            key: ValueKey('$name$suffix'),
            theme: ThemeData.dark(),
            home: title == null
                ? body
                : Scaffold(
                    appBar: AppBar(title: Text(title)),
                    body: body,
                  ),
          ),
        ),
      );
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      await tester.runAsync(() => _shot(tester, '$name$suffix'));
    }

    // ignore: avoid_print
    print('나온 그림:');

    await show(
      '1_첫화면',
      HomeView(
        project: p,
        transport: tr,
        live: LiveChannel(),
        master: MasterChannel(),
        host: null,
        store: null,
        ready: true,
        onOpenLab: () {},
        onSongOpened: () {},
      ),
    );

    await show(
      '2_만들기',
      SceneView(project: p, transport: tr, host: null),
      title: '씬 (한 판 만들기)',
    );

    // 트랙이 많은 장르 — 로파이는 4줄뿐이라 **화면이 넘칠 일이 없다.**
    // 팝은 7줄, 가스펠·디스코는 5줄이다. 줄이 늘면 밀리거나 잘리는지 눈으로 본다.
    // 트랙이 많은 장르의 **믹서** — 폰에서 몇 줄이나 보이는지, 더 있다는 표시가
    // 나오는지 눈으로 본다(예전엔 「트랙 4개」인데 셋만 보였다).
    {
      final mp = Project.initial()..setGenre('pop');
      await show(
        '5b_믹서_pop',
        MixerView(
          project: mp,
          live: LiveChannel(),
          master: MasterChannel(),
          host: null,
        ),
        title: '믹서 — 팝(7트랙)',
      );
    }
    for (final g in ['pop', 'gospel']) {
      final gp = Project.initial()..setGenre(g);
      // **템포·조성도 그 장르 것으로 맞춘다.** 안 맞추면 그림이 거짓말을 한다 —
      // 가스펠(장조)을 「C 단조」로 찍어 놓고 그걸 보고 판단하게 된다.
      final gt = Transport()
        ..bpm = songGenreOf(g).$3
        ..mode = songGenreOf(g).$5;
      await show(
        '2b_만들기_$g',
        SceneView(project: gp, transport: gt, host: null),
        title: '씬 — ${genreDef(g).label}',
      );
    }

    // ── 간단히 보기 (Phase 2) ──
    // **감춘 뒤에도 화면이 멀쩡한지**는 눈으로 봐야 안다. 버튼 하나를 빼면
    // 남은 것들이 밀리거나 가운데가 비거나 한다 — 시험의 '안 넘쳤다'로는 안 잡힌다.
    // 세로·가로 둘 다 뽑는다.
    final simpleStore =
        Store(
            project: p,
            transport: tr,
            live: LiveChannel(),
            master: MasterChannel(),
          )
          ..simpleMode = true
          // 안내 창이 뜨면 첫 화면이 안 보인다(그리고 안내를 봤다고 적으려다
          // path_provider 를 찾는다 — 시험 환경엔 없다)
          ..guideSeen = true;
    await show(
      '11_첫화면_간단히',
      HomeView(
        project: p,
        transport: tr,
        live: LiveChannel(),
        master: MasterChannel(),
        host: null,
        store: simpleStore,
        ready: true,
        onOpenLab: () {},
        onSongOpened: () {},
      ),
    );
    await show(
      '12_만들기_간단히',
      SceneView(project: p, transport: tr, host: null, simple: true),
      title: '씬 (한 판 만들기)',
    );

    // ── 만들기 시작 (Phase 2 · 계획 4-1) ──
    // 첫 실행에서 제일 먼저 보는 화면이다. **여기서 막히면 아무 소리도 안 난다.**
    await show(
      '13_시작하기',
      Scaffold(
        backgroundColor: const Color(0xFF16161A),
        body: CreateSheetBody(onPick: (_) {}),
      ),
    );

    // ── 느낌 손잡이 (Phase 2 · 계획 4-4) ──
    // 값이 **말로** 보여야 한다(0.73 은 아무 뜻도 없다). 눈으로 확인한다.
    await show(
      '14_느낌',
      Scaffold(
        backgroundColor: const Color(0xFF16161A),
        body: FeelSheetBody(
          value: const Feel(energy: 0.78, density: 0.3, groove: 0.55),
          onChanged: (_) {},
        ),
      ),
    );
    await show(
      '3_곡으로잇기',
      SongView(project: p, transport: tr, host: null),
      title: '곡 (구간 늘어놓기)',
    );

    await show(
      '4_라이브',
      LiveView(project: p, transport: tr, live: LiveChannel(), host: null),
      title: '라이브',
    );

    await show(
      '5_믹서',
      MixerView(
        project: p,
        live: LiveChannel(),
        master: MasterChannel(),
        host: null,
      ),
      title: '믹서',
    );

    // 편집기 — 드럼(레인 10개)과 멜로디(도수 15줄)를 둘 다 본다
    await show(
      '6_편집기_드럼',
      EditorView(
        project: p,
        transport: tr,
        track: p.tracks.firstWhere((t) => t.type == 'drum'),
        host: null,
      ),
      title: '드럼 편집',
    );
    await show(
      '7_편집기_멜로디',
      EditorView(
        project: p,
        transport: tr,
        track: p.tracks.firstWhere((t) => t.type == 'melody'),
        host: null,
      ),
      title: '리드 편집',
    );
    // **위층 코드 줄** — 재즈 비브라폰처럼 한 옥타브 위에서 치는 줄은 이름 옆에
    // 그 사실이 적힌다. 이름이 길어지는 자리라 눈으로 확인한다.
    {
      final jp = Project.initial()..setGenre('jazz');
      final jt = jp.tracks.firstWhere(
        (t) => t.name.contains('비브'),
        orElse: () => jp.tracks.firstWhere((t) => t.type == 'chord'),
      );
      jt.pattern =
          jp.scenes
              .map((s) => s.clips[jt.id])
              .firstWhere((c) => c != null, orElse: () => jt.pattern) ??
          jt.pattern;
      await show(
        '7c_편집기_위층',
        EditorView(project: jp, transport: tr, track: jt, host: null),
        title: '위층 코드 편집',
      );
    }
    // 코드 편집 — 여기에만 「멜로디에 맞추기」가 있다 (계획 6-4)
    await show(
      '7b_편집기_코드',
      EditorView(
        project: p,
        transport: tr,
        track: p.tracks.firstWhere((t) => t.type == 'chord'),
        host: null,
      ),
      title: '코드 편집',
    );

    // ── 인서트(로직식 플러그인) ── 시트를 열어 가며 뽑는다
    await tester.pumpWidget(
      RepaintBoundary(
        key: _snapKey,
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            appBar: AppBar(title: const Text('믹서')),
            body: MixerView(
              project: p,
              live: LiveChannel(),
              master: MasterChannel(),
              host: null,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('한눈에'));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tap(find.byIcon(Icons.tune).first);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    // 채널 시트 — 아래로 밀어 인서트 자리를 보이게
    await tester.drag(find.text('울림').last, const Offset(0, -260));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.runAsync(() => _shot(tester, '8_인서트_랙'));

    await tester.tap(find.text('인서트 꽂기'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.runAsync(() => _shot(tester, '9_인서트_고르기'));

    await tester.tap(find.text('기타 앰프'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.runAsync(() => _shot(tester, '10_플러그인_창'));
    // 창 닫고 랙으로 — 꽂힌 뒤 모습
    await tester.tapAt(const Offset(200, 40));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    await tester.runAsync(() => _shot(tester, '11_꽂힌_뒤'));

    // ── 가로 ──
    turn(true);
    await show(
      '1_첫화면',
      HomeView(
        project: p,
        transport: tr,
        live: LiveChannel(),
        master: MasterChannel(),
        host: null,
        store: null,
        ready: true,
        onOpenLab: () {},
        onSongOpened: () {},
      ),
    );
    await show(
      '2_만들기',
      SceneView(project: p, transport: tr, host: null),
      title: '씬 (한 판 만들기)',
    );
    // 간단히 보기도 **가로에서 한 번 더** — 세로에서 멀쩡해도 가로에서 무너질 수 있다
    // (가로는 높이가 귀해서 위쪽 바가 한 줄로 접힌다. 거기서 칩을 빼면 배치가 바뀐다).
    await show(
      '11_첫화면_간단히',
      HomeView(
        project: p,
        transport: tr,
        live: LiveChannel(),
        master: MasterChannel(),
        host: null,
        store: simpleStore,
        ready: true,
        onOpenLab: () {},
        onSongOpened: () {},
      ),
    );
    await show(
      '12_만들기_간단히',
      SceneView(project: p, transport: tr, host: null, simple: true),
      title: '씬 (한 판 만들기)',
    );

    // ── 만들기 시작 (Phase 2 · 계획 4-1) ──
    // 첫 실행에서 제일 먼저 보는 화면이다. **여기서 막히면 아무 소리도 안 난다.**
    await show(
      '13_시작하기',
      Scaffold(
        backgroundColor: const Color(0xFF16161A),
        body: CreateSheetBody(onPick: (_) {}),
      ),
    );

    // ── 느낌 손잡이 (Phase 2 · 계획 4-4) ──
    // 값이 **말로** 보여야 한다(0.73 은 아무 뜻도 없다). 눈으로 확인한다.
    await show(
      '14_느낌',
      Scaffold(
        backgroundColor: const Color(0xFF16161A),
        body: FeelSheetBody(
          value: const Feel(energy: 0.78, density: 0.3, groove: 0.55),
          onChanged: (_) {},
        ),
      ),
    );
    await show(
      '4_라이브',
      LiveView(project: p, transport: tr, live: LiveChannel(), host: null),
      title: '라이브',
    );
    await show(
      '5_믹서',
      MixerView(
        project: p,
        live: LiveChannel(),
        master: MasterChannel(),
        host: null,
      ),
      title: '믹서',
    );
    for (final g in ['pop']) {
      final gp = Project.initial()..setGenre(g);
      final gt = Transport()
        ..bpm = songGenreOf(g).$3
        ..mode = songGenreOf(g).$5;
      await show(
        '2b_만들기_$g',
        SceneView(project: gp, transport: gt, host: null),
        title: '씬 — ${genreDef(g).label}',
      );
    }

    await show(
      '6_편집기_드럼',
      EditorView(
        project: p,
        transport: tr,
        track: p.tracks.firstWhere((t) => t.type == 'drum'),
        host: null,
      ),
      title: '드럼 편집',
    );
    // 코드 편집은 위쪽 줄에 **일곱 번째**를 얹는다 — 가로에서 한 줄로 접히므로
    // 여기가 제일 잘리기 쉬운 자리다. 눈으로 본다.
    {
      final jp = Project.initial()..setGenre('jazz');
      final jt = jp.tracks.firstWhere(
        (t) => t.name.contains('비브'),
        orElse: () => jp.tracks.firstWhere((t) => t.type == 'chord'),
      );
      jt.pattern =
          jp.scenes
              .map((s) => s.clips[jt.id])
              .firstWhere((c) => c != null, orElse: () => jt.pattern) ??
          jt.pattern;
      await show(
        '7c_편집기_위층',
        EditorView(project: jp, transport: tr, track: jt, host: null),
        title: '위층 코드 편집',
      );
    }
    await show(
      '7b_편집기_코드',
      EditorView(
        project: p,
        transport: tr,
        track: p.tracks.firstWhere((t) => t.type == 'chord'),
        host: null,
      ),
      title: '코드 편집',
    );
    turn(false);
  });
}
