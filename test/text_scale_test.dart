// 글자를 키운 폰에서도 화면이 멀쩡한가.
//   flutter test test/text_scale_test.dart
//
// ── 왜 ──
// 안드로이드 「설정 → 디스플레이 → 글자 크기와 스타일」은 글자를 최대 **1.3배**까지
// 키운다(원 UI 는 접근성에서 더 간다). 눈이 나쁜 사람은 대개 이걸 켜 놓고 산다.
// 그런데 이 앱은 **한 번도 그 상태로 그려 본 적이 없었다** — 모든 시험이 1.0배다.
//
// 글자가 커지면 버튼·칩·라벨이 자기 칸을 넘고, 플러터는 「A RenderFlex overflowed」
// 예외를 던진다. 폰에서는 노랑·검정 빗금으로 나오거나 글자가 그냥 잘린다.
// **화면이 넘치는지 아닌지는 눈이 아니라 예외로 잡을 수 있다** — 그래서 시험이 된다.
//
// 세로·가로·작은폰(320dp) × 1.0 · 1.3 배로 주요 화면을 전부 그린다.
// 작은 폰을 같이 보는 까닭: 이 앱이 네이티브로 옮겨진 이유가 **보급형 폰**이다.
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

void main() {
  testWidgets('글자를 키워도 안 넘친다', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = Project.initial()..name = '나무';
    final tr = Transport();
    final live = LiveChannel();
    final master = MasterChannel();

    // **매번 새 트리로 짓는다.** 키가 같으면 플러터가 앞 화면의 요소를 그대로
    // 이어 쓴다 — 그러면 앞 화면 탓에 난 넘침이 이 화면 몫으로 찍힌다
    // (screen_snap 에서 이미 한 번 데었다).
    // 배율은 **MaterialApp 안쪽**에서 건다(`builder`). 바깥에 MediaQuery 를 씌우면
    // MaterialApp 이 화면에서 제 것을 새로 만들어 덮어써서, 배율은 안 먹고
    // 크기·여백만 0 이 된 가짜 화면을 재게 된다.
    Widget wrap(Widget body, double scale, String tag, {String? title}) =>
        MaterialApp(
          key: ValueKey(tag),
          theme: ThemeData.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: title == null
              ? body
              : Scaffold(
                  appBar: AppBar(title: Text(title)),
                  body: body,
                ),
        );

    // 화면 하나를 배율·방향 네 가지로 그려 본다.
    Future<void> sweep(
      String name,
      Widget Function() build, {
      String? title,
    }) async {
      final bad = <String>[];
      for (final scale in [1.0, 1.3]) {
        for (final size in [
          const Size(400, 800), // 기준(갤럭시 A17 은 393dp)
          const Size(800, 400), // 가로
          const Size(320, 640), // 작은 보급형 폰 — 이 앱이 겨냥하는 쪽이다
        ]) {
          final way = size.width > size.height
              ? '가로'
              : (size.width < 360 ? '작은폰' : '세로');
          tester.view.physicalSize = size;
          await tester.pumpWidget(
            wrap(build(), scale, '$name-$scale-$way', title: title),
          );
          await tester.pump(const Duration(milliseconds: 200));
          // 한 프레임에 여러 군데가 넘치면 플러터는 「Multiple exceptions (10)」
          // 한 줄로 뭉친다 — 그때는 **한 군데씩 고치고 다시 돌리는 수밖에 없다**
          // (`FlutterError.onError` 를 가로채 보니 시험이 멎어 버렸다).
          for (var i = 0; i < 20; i++) {
            final err = tester.takeException();
            if (err == null) break;
            bad.add('${scale}배 $way: ${'$err'.split('\n').first}');
          }
        }
      }
      check(
        name,
        bad.isEmpty,
        bad.isEmpty ? '1.0·1.3배 × 세로·가로·작은폰 넘침 없음' : bad.join(' / '),
      );
    }

    await sweep(
      '1) 첫 화면',
      () => HomeView(
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

    await sweep(
      '2) 씬',
      () => SceneView(project: p, transport: tr, host: null),
      title: '씬',
    );

    await sweep(
      '3) 곡',
      () => SongView(project: p, transport: tr, host: null),
      title: '곡',
    );

    await sweep(
      '4) 라이브',
      () => LiveView(project: p, transport: tr, live: live, host: null),
      title: '라이브',
    );

    await sweep(
      '5) 믹서',
      () => MixerView(project: p, live: live, master: master, host: null),
      title: '믹서',
    );

    for (final ty in ['drum', 'bass', 'chord', 'melody']) {
      final t = p.tracks.where((x) => x.type == ty).firstOrNull;
      if (t == null) continue;
      await sweep(
        '6) 편집기 $ty',
        () => EditorView(project: p, transport: tr, track: t, host: null),
        title: '편집',
      );
    }

    await sweep(
      '7) 시작하기',
      () => Scaffold(
        backgroundColor: const Color(0xFF16161A),
        body: CreateSheetBody(onPick: (_) {}),
      ),
    );

    await sweep(
      '8) 느낌',
      () => Scaffold(
        backgroundColor: const Color(0xFF16161A),
        body: FeelSheetBody(
          value: const Feel(energy: 0.78, density: 0.3, groove: 0.55),
          onChanged: (_) {},
        ),
      ),
    );

    // 쇼 화면 — 무대·가사·구간 이름이 다 글자다
    await sweep('10) 쇼', () => ShowView(project: p, transport: tr, host: null));

    // 곡 목록 — 곡 이름이 길어지는 자리
    {
      final st = Store(project: p, transport: tr, live: live, master: master)
        ..guideSeen = true;
      await sweep(
        '11) 곡 목록',
        () => SongsView(store: st, project: p, onOpened: () {}),
      );
    }

    // ── 긴 이름 ──
    // 곡·씬·트랙 이름은 **사용자가 적는다.** 「나무」로만 재 보고 넘어가면
    // 실제로 긴 이름을 적은 사람 화면에서만 깨진다. 말도 안 되게 긴 이름을 넣고
    // 같은 화면들을 다시 그린다 — 줄임표(…)로 잘리는 건 괜찮고, 넘치면 안 된다.
    {
      final lp = Project.initial()
        ..name = '아주 아주 긴 곡 이름을 적으면 어떻게 되는지 보려고 만든 이름입니다';
      for (final sc in lp.scenes) {
        sc.name = '${sc.name} — 아주 길게 적은 구간 이름';
      }
      for (final t in lp.tracks) {
        t.name = '${t.name} 아주 긴 트랙 이름';
      }
      final lt = Transport();
      await sweep(
        '12) 긴 이름 · 씬',
        () => SceneView(project: lp, transport: lt, host: null),
        title: '씬',
      );
      await sweep(
        '13) 긴 이름 · 곡',
        () => SongView(project: lp, transport: lt, host: null),
        title: '곡',
      );
      await sweep(
        '14) 긴 이름 · 믹서',
        () => MixerView(
          project: lp,
          live: LiveChannel(),
          master: MasterChannel(),
          host: null,
        ),
        title: '믹서',
      );
      await sweep(
        '15) 긴 이름 · 쇼',
        () => ShowView(project: lp, transport: lt, host: null),
      );
      await sweep(
        '16) 긴 이름 · 첫 화면',
        () => HomeView(
          project: lp,
          transport: lt,
          live: LiveChannel(),
          master: MasterChannel(),
          host: null,
          store: null,
          ready: true,
          onOpenLab: () {},
          onSongOpened: () {},
        ),
      );
    }

    // 트랙이 제일 많은 장르 — 줄이 늘면 넘칠 자리가 는다
    {
      final pp = Project.initial()..setGenre('pop');
      await sweep(
        '9) 믹서(팝 7트랙)',
        () => MixerView(
          project: pp,
          live: LiveChannel(),
          master: MasterChannel(),
          host: null,
        ),
        title: '믹서',
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '글자 크기 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
