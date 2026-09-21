// 가로모드·세로모드 전체 화면 확인 — 화면 크기를 폰 세로/가로 비율로 각각
// 바꿔 주요 화면을 띄워 보고, 자리가 없어서 나는 렌더 오버플로 예외
// (`FlutterError` a.k.a "노란/검은 줄무늬")가 있는지 잡는다.
//   flutter test test/orientation_check_test.dart
//
// 실기기로 하나하나 돌려 보는 것도 했지만, 화면이 많아서(씬·타임라인·
// 라이브·쇼·노트 편집기·믹서·첫 화면) 전부 손으로 돌려 보긴 오래 걸리고
// 빠뜨리기 쉽다 — 그래서 여기 자동 확인을 추가해 매번 같이 돈다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/editor_view.dart';
import 'package:music_doodle_engine/ui/home_view.dart';
import 'package:music_doodle_engine/ui/mixer_view.dart';
import 'package:music_doodle_engine/ui/project_settings_sheet.dart';
import 'package:music_doodle_engine/ui/workspace_view.dart';

// 실기기(RFKL505TRAZ, 1080×2340) 가로세로 비율을 논리 픽셀로 축소한 크기.
const _portrait = Size(411, 890);
const _landscape = Size(890, 411);
// 가장 낮은 축에 속하는 실기기 가로 높이(예: 갤럭시 계열 좁은 가로) — 시트가
// 화면 높이의 85% 로 눌리는 자리라 여기서 잘리면 실기기에서도 잘린다.
const _shortLandscape = Size(740, 340);

void main() {
  Future<int> sweep(
    WidgetTester tester,
    String label,
    Size size,
    Widget Function() build,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: ThemeData.dark(), home: build()),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));

    final err = tester.takeException();
    // ignore: avoid_print
    print(
      '${err == null ? '  OK' : '실패'} $label — ${err ?? size}',
    );
    return err == null ? 0 : 1;
  }

  testWidgets('작업 화면 4탭 — 가로·세로', (tester) async {
    var fail = 0;
    final p = Project.initial();
    final tr = Transport();

    Widget ws({String mode = 'scene'}) => ProjectWorkspace(
      project: p,
      transport: tr,
      live: LiveChannel(),
      master: MasterChannel(),
      host: null,
      store: null,
      simple: false,
      pro: true,
      initialMode: mode,
    );

    for (final mode in ['scene', 'timeline', 'live', 'show']) {
      for (final entry in {'세로': _portrait, '가로': _landscape}.entries) {
        fail += await sweep(
          tester,
          '작업 화면 · $mode · ${entry.key}',
          entry.value,
          () => ws(mode: mode),
        );
      }
    }

    expect(fail, 0);
  });

  testWidgets('노트 편집기 — 가로·세로', (tester) async {
    var fail = 0;
    final p = Project.initial();
    final tr = Transport();
    final track = p.tracks.firstWhere((t) => t.type == 'melody');

    Widget editor() => Scaffold(
      appBar: AppBar(title: Text('${track.name} 편집')),
      body: SafeArea(
        top: false,
        child: EditorView(project: p, transport: tr, track: track, host: null, pro: true),
      ),
    );

    for (final entry in {'세로': _portrait, '가로': _landscape}.entries) {
      fail += await sweep(tester, '노트 편집기 · ${entry.key}', entry.value, editor);
    }

    expect(fail, 0);
  });

  testWidgets('첫 화면 — 가로·세로', (tester) async {
    var fail = 0;
    final p = Project.initial()..name = '첫 곡';

    Widget home() => HomeView(
      project: p,
      transport: Transport(),
      live: LiveChannel(),
      master: MasterChannel(),
      host: null,
      store: null,
      ready: true,
      onOpenLab: () {},
      onSongOpened: () {},
    );

    for (final entry in {'세로': _portrait, '가로': _landscape}.entries) {
      fail += await sweep(tester, '첫 화면 · ${entry.key}', entry.value, home);
    }

    expect(fail, 0);
  });

  testWidgets('믹서·프로젝트 설정 시트 — 낮은 가로 화면', (tester) async {
    var fail = 0;
    final p = Project.initial();
    final tr = Transport();
    final master = MasterChannel();
    final track = p.tracks.first;

    tester.view.physicalSize = _shortLandscape;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(key: key, body: const SizedBox()),
      ),
    );
    await tester.pump();

    showChannelSheet(
      key.currentContext!,
      track: track,
      color: Colors.teal,
      onChanged: () {},
      onSolo: () {},
      host: null,
    );
    await tester.pumpAndSettle();
    var err = tester.takeException();
    // ignore: avoid_print
    print('${err == null ? '  OK' : '실패'} 믹서 채널 시트 · 낮은 가로 — $err');
    if (err != null) fail++;

    Navigator.of(key.currentContext!).pop();
    await tester.pumpAndSettle();

    showProjectSettingsSheet(
      key.currentContext!,
      project: p,
      transport: tr,
      master: master,
      onChanged: () {},
    );
    await tester.pumpAndSettle();
    err = tester.takeException();
    // ignore: avoid_print
    print('${err == null ? '  OK' : '실패'} 프로젝트 설정 시트 · 낮은 가로 — $err');
    if (err != null) fail++;

    expect(fail, 0);
  });
}
