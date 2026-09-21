// 누를 것이 **손가락만 한가**.
//   flutter test test/tap_size_test.dart
//
// 왜: 폰에서 「두 번 눌렀는데 안 먹었다」는 대개 기능이 아니라 **크기** 문제다.
// 머티리얼은 48dp, 애플은 44pt 를 최소로 잡는다.
//
// ── 두 가지를 한다 ──
// ① **40 아래를 다 적는다** — 눈으로 훑어보는 목록이다(격자 칸처럼 일부러
//    작은 것도 있으니, 여기 적혔다고 다 흠은 아니다).
// ② **바닥선을 지킨다** — 세로 32 · 가로 28 아래는 시험이 잡는다.
//    가로 28 인 까닭은 편집기 격자 칸이 30 이라서다(16칸이 화면 폭을 나눠 갖는다).
//    한때 씬 칩의 ⋮ 가 **18×15**, 마스터 「0dB」가 64×30, 믹서 M/S 가 29×34 였다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/feel.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/store.dart';
import 'package:music_doodle_engine/ui/create_sheet.dart';
import 'package:music_doodle_engine/ui/editor_view.dart';
import 'package:music_doodle_engine/ui/feel_sheet.dart';
import 'package:music_doodle_engine/ui/home_view.dart';
import 'package:music_doodle_engine/ui/live_view.dart';
import 'package:music_doodle_engine/ui/mixer_view.dart';
import 'package:music_doodle_engine/ui/scene_view.dart';
import 'package:music_doodle_engine/ui/show_view.dart';
import 'package:music_doodle_engine/ui/song_view.dart';
import 'package:music_doodle_engine/ui/songs_view.dart';

// 이보다 작으면 시험이 잡는다.
const _minH = 32.0, _minW = 28.0;

void main() {
  testWidgets('누를 것 크기', (tester) async {
    var tooSmall = 0;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = Project.initial()..name = '나무';
    final tr = Transport();
    final live = LiveChannel();
    final master = MasterChannel();

    // 어느 종류를 재는가. 격자 칸은 `GestureDetector` 라 같이 잡히는데,
    // 그건 화면 전체를 덮는 하나라 크기가 크게 나온다(문제 없음).
    final kinds = <Type>[
      IconButton,
      TextButton,
      OutlinedButton,
      FilledButton,
      ElevatedButton,
      InkWell,
      Switch,
      Checkbox,
      GestureDetector,
    ];

    Future<void> measure(String name, Widget body, {String? title}) async {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(name),
          theme: ThemeData.dark(),
          home: title == null
              ? body
              : Scaffold(
                  appBar: AppBar(title: Text(title)),
                  body: body,
                ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));
      final small = <String>[];
      final bad = <String>[];
      // 같은 자리에 같은 크기로 겹쳐 있는 것은 **한 위젯**이다
      // (FilledButton 안에 InkWell 안에 GestureDetector). 한 번만 센다.
      final seen = <String>{};
      for (final k in kinds) {
        final found = find.byType(k);
        for (var i = 0; i < found.evaluate().length; i++) {
          final el = found.evaluate().elementAt(i);
          final ro = el.renderObject;
          if (ro is! RenderBox || !ro.hasSize) continue;
          final s = ro.size;
          if (s.width <= 0 || s.height <= 0) continue;
          // 40 아래만 본다 — 40×40 은 흔한 절충값이라 여기까지 적으면 목록이 안 읽힌다.
          if (s.width >= 40 && s.height >= 40) continue;
          final at = ro.localToGlobal(Offset.zero);
          final spot =
              '${at.dx.round()},${at.dy.round()},'
              '${s.width.round()},${s.height.round()}';
          if (!seen.add(spot)) continue;
          // 무엇인지 알아볼 실마리 — 안에 든 글자
          String label = '';
          void visit(Element e) {
            if (label.isNotEmpty) return;
            final w = e.widget;
            if (w is Text && (w.data ?? '').isNotEmpty) {
              label = w.data!;
              return;
            }
            if (w is Icon && w.icon != null) {
              label = 'icon(${w.icon!.codePoint})';
              return;
            }
            e.visitChildren(visit);
          }

          el.visitChildren(visit);
          final line =
              '${s.width.round()}×${s.height.round()}'
              '${label.isEmpty ? '' : ' 「$label」'}';
          small.add(line);
          if (s.height < _minH || s.width < _minW) bad.add('$name — $line');
        }
      }
      // 같은 것이 여럿이면 묶어서
      final tally = <String, int>{};
      for (final x in small) {
        tally[x] = (tally[x] ?? 0) + 1;
      }
      // ignore: avoid_print
      print(
        '── $name — 작은 것 ${small.length}개'
        '${bad.isEmpty ? '' : ' · **바닥선 아래 ${bad.length}개**'}',
      );
      for (final b in bad.toSet()) {
        // ignore: avoid_print
        print('  ✗ $b');
      }
      tooSmall += bad.length;
      final rows = tally.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      for (final e in rows.take(14)) {
        // ignore: avoid_print
        print('     ${e.key}${e.value > 1 ? ' ×${e.value}' : ''}');
      }
    }

    await measure(
      '첫 화면',
      HomeView(
        project: p,
        transport: tr,
        live: live,
        master: master,
        host: null,
        store: null,
        ready: true,
        onOpenLab: () {},
        onSongOpened: () {},
      ),
    );
    await measure(
      '씬',
      SceneView(project: p, transport: tr, host: null),
      title: '씬',
    );
    await measure(
      '곡',
      SongView(project: p, transport: tr, host: null),
      title: '곡',
    );
    await measure(
      '라이브',
      LiveView(project: p, transport: tr, live: live, host: null),
      title: '라이브',
    );
    await measure(
      '믹서',
      MixerView(project: p, live: live, master: master, host: null),
      title: '믹서',
    );
    for (final ty in ['drum', 'melody', 'chord']) {
      final t = p.tracks.where((x) => x.type == ty).firstOrNull;
      if (t == null) continue;
      await measure(
        '편집기 $ty',
        EditorView(project: p, transport: tr, track: t, host: null),
        title: '편집',
      );
    }
    await measure(
      '시작하기',
      Scaffold(
        backgroundColor: const Color(0xFF16161A),
        body: CreateSheetBody(onPick: (_) {}),
      ),
    );
    await measure(
      '느낌',
      Scaffold(
        backgroundColor: const Color(0xFF16161A),
        body: FeelSheetBody(
          value: const Feel(energy: 0.78, density: 0.3, groove: 0.55),
          onChanged: (_) {},
        ),
      ),
    );
    await measure('쇼', ShowView(project: p, transport: tr, host: null));
    {
      final st = Store(project: p, transport: tr, live: live, master: master)
        ..guideSeen = true;
      await measure('곡 목록', SongsView(store: st, project: p, onOpened: () {}));
    }

    // ignore: avoid_print
    print(
      tooSmall == 0
          ? '누를 것 크기 통과 — 세로 $_minH · 가로 $_minW 아래 없음'
          : '바닥선 아래 $tooSmall개',
    );
    expect(tooSmall, 0);
  });
}
