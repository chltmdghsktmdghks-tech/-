// Phase 2 — **첫 흐름: 고르면 바로 소리.** (개선 계획 4-1·4-2)
//   flutter test test/create_flow_test.dart
//
// 계획이 요구하는 것은 한 줄이다:
//   `앱 실행 → 장르 선택 → 기본 음악이 즉시 재생 → 사용자가 바로 조작`
//
// 그래서 "시트가 뜬다"까지만 보지 않는다. **고른 뒤에 실제로 무엇이 바뀌었는지**를 본다:
// 장르 · 템포 · 조 · 편성 · 그리고 **재생이 켜졌는가.**
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/presets.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/create_sheet.dart';
import 'package:music_doodle_engine/ui/scene_view.dart';

void main() {
  testWidgets('만들기 시작', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $what — $detail');
      if (!ok) fail++;
    }

    const portrait = Size(400, 800), landscape = Size(800, 400);
    for (final (label, size) in [('세로', portrait), ('가로', landscape)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;

      // ── 시트가 무엇을 보여 주는가 ──
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          // **매번 새 트리로.** 같은 키면 플러터가 앞 화면의 GridView 를 재사용해서
          // 밀어 둔 스크롤 위치가 그대로 남는다 — 맨 위 카드를 못 누른다.
          key: UniqueKey(),
          theme: ThemeData.dark(),
          home: Scaffold(body: CreateSheetBody(onPick: (k) => picked = k)),
        ),
      );
      await tester.pump();

      // 장르가 다 있어야 한다 — 하나라도 빠지면 그 장르는 영영 못 고른다.
      // 목록은 접혀 있으므로 **훑으면서 모은다**. 한 번에 크게 밀면 위쪽이
      // 화면 밖으로 나가서 "없다"고 나온다(처음에 그렇게 헛짚었다).
      final seen = <String>{};
      for (var step = 0; step < 8; step++) {
        for (final g in kSongGenres) {
          if (find.text(g.$2).evaluate().isNotEmpty) seen.add(g.$2);
        }
        if (seen.length == kSongGenres.length) break;
        // **미는 것은 바깥 목록이다.** 팩(계획 7-2)으로 묶으면서 안에 격자가
        // 여러 개 생겼고, 5단계 47/N 이후로는 박자 칩 줄도 가로 `ListView` 라
        // 타입만으로 잡으면 「어느 것이냐」로 시험이 멈춘다 — 키로 짚는다.
        await tester.drag(
          find.byKey(const Key('genreList')),
          const Offset(0, -180),
        );
        await tester.pump();
      }
      final stillMissing = [
        for (final g in kSongGenres)
          if (!seen.contains(g.$2)) g.$2,
      ];
      check(
        '$label · 장르 ${kSongGenres.length}종이 다 있다',
        stillMissing.isEmpty,
        stillMissing.isEmpty ? '전부 닿는다' : '못 찾음: ${stillMissing.join(', ')}',
      );

      // **용어를 안 쓴다** — 계획 4-1 이 못 박은 것.
      // 처음 상태(맨 위)에서 본다 — 밀어 내린 뒤가 아니라.
      await tester.pumpWidget(
        MaterialApp(
          // **매번 새 트리로.** 같은 키면 플러터가 앞 화면의 GridView 를 재사용해서
          // 밀어 둔 스크롤 위치가 그대로 남는다 — 맨 위 카드를 못 누른다.
          key: UniqueKey(),
          theme: ThemeData.dark(),
          home: Scaffold(body: CreateSheetBody(onPick: (k) => picked = k)),
        ),
      );
      await tester.pump();
      const jargon = ['믹서', 'FX', '씬', '트랙', '패턴', '스케일', '코드'];
      final shown = [
        for (final w in jargon)
          if (find.textContaining(w).evaluate().isNotEmpty) w,
      ];
      check(
        '$label · 첫 화면에 전문 용어가 없다',
        shown.isEmpty,
        shown.isEmpty ? '장르 이름과 느낌뿐' : '나옴: ${shown.join(', ')}',
      );

      // ── 고르면 무엇이 바뀌는가 ──
      await tester.pumpWidget(
        MaterialApp(
          // **매번 새 트리로.** 같은 키면 플러터가 앞 화면의 GridView 를 재사용해서
          // 밀어 둔 스크롤 위치가 그대로 남는다 — 맨 위 카드를 못 누른다.
          key: UniqueKey(),
          theme: ThemeData.dark(),
          home: Scaffold(body: CreateSheetBody(onPick: (k) => picked = k)),
        ),
      );
      await tester.pump();
      // 팩으로 묶으면서 하우스가 세 번째 묶음(「춤」)으로 내려갔다 — 화면 밖이고,
      // 목록이 게을러서(lazy) **아직 만들어지지도 않았다**. 나올 때까지 민다.
      // `.first` 는 5단계 47/N 부터 박자 칩 줄(가로 스크롤)을 먼저 잡는다 —
      // 장르 목록(`genreList`) 안의 것으로 짚는다.
      await tester.scrollUntilVisible(
        find.text('하우스'),
        120,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('genreList')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump();
      await tester.tap(find.text('하우스'));
      await tester.pump();
      check('$label · 고르면 값이 넘어온다', picked == 'house', '${picked}');

      // 그 값으로 실제 프로젝트가 바뀌는가
      final p = Project.initial();
      final tr = Transport();
      final before = '${p.genre}/${tr.bpm}';
      p.setGenre(picked!);
      final g = songGenreOf(picked!);
      tr.bpm = g.$3;
      tr.mode = g.$5;
      check(
        '$label · 장르·템포·조가 같이 바뀐다',
        p.genre == 'house' && tr.bpm == 124 && tr.mode == 'minor',
        '$before → ${p.genre}/${tr.bpm.round()}/${tr.mode}',
      );
      check(
        '$label · 편성이 채워진다',
        p.tracks.isNotEmpty && p.tracks.every((t) => !p.isSilent(t)),
        '${p.tracks.length}트랙 · 전부 소리남',
      );

      // ── 들어가면 바로 재생되는가 ──
      // host 가 없으면(시험 환경) 재생을 못 켠다. **켜려고 시도했는지**가 아니라
      // autoPlay 를 켠 화면이 멀쩡히 서는지를 본다 — 실제 소리는 폰에서 확인한다.
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: SceneView(
              project: p,
              transport: tr,
              host: null,
              autoPlay: true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      check(
        '$label · 자동 재생 화면이 선다',
        tester.takeException() == null,
        '넘침·예외 없음',
      );

      // **스타일 칩은 이제 씬 화면에 없다**(2026-09) — 작업 화면 위쪽
      // 톱니바퀴의 「프로젝트 설정」(`project_settings_sheet.dart`)으로
      // 옮겼다. 자주 안 만지는 값을 화면에 늘 띄워 두지 않으려는 것이다.
      // 여기서는 장르·템포·조·편성이 실제로 바뀌었는지(위 확인들)로 충분하다.
    }

    tester.view.resetPhysicalSize();
    // ignore: avoid_print
    print(fail == 0 ? '만들기 시작 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
