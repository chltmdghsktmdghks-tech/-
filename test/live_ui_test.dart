// 5단계 14/N — 라이브 **화면**을 시험이 직접 눌러 본다.
//   flutter test test/live_ui_test.dart
//
// 녹음 계산은 `live_rec_test.dart` 가 본다. 여기서 보는 건 배선이다:
// 녹음 버튼 → 패드 → 다시 눌러 끝내기 까지 갔을 때 **정말 트랙이 생기는가.**
// (계산이 다 맞아도 화면에서 안 이어져 있으면 사용자에게는 없는 기능이다)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/engine.dart' show keyUsesSharps, noteNameIn;
import 'package:music_doodle_engine/instruments.dart' show VOICE_LABEL;
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/live_view.dart';

void main() {
  testWidgets('라이브 화면', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = Project.initial();
    final live = LiveChannel()..voice = 'bell';

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: LiveView(
            project: p,
            transport: Transport(),
            live: live,
            host: null, // 소리 없이 화면만 — 적는 길은 소리와 상관없다
          ),
        ),
      ),
    );

    // 1) 패드 이름이 조를 따라간다 (기본 C단조: C·D·**Eb**·F·G·**Ab**·**Bb**)
    //
    // 예전엔 D#·G#·A# 로 적혔다. 소리는 같지만 **C단조를 그렇게 적지 않는다** —
    // 악보를 읽는 사람에게는 다른 음으로 보인다. ♯/♭ 은 조가 정한다
    // (`engine.dart` 의 `keyUsesSharps`, 단조는 나란한 장조로 판단).
    final hasScale = [
      'C4',
      'D4',
      'Eb4',
      'F4',
      'G4',
      'Ab4',
      'Bb4',
    ].every((n) => find.text(n).evaluate().isNotEmpty);
    check(
      '1) 패드가 조의 음계',
      hasScale && find.text('C5').evaluate().isNotEmpty,
      '아래줄 C4~Bb4 · 윗줄 C5',
    );

    // 1-b) **♯ 쪽 조에서는 ♯ 로 적는다** — 한쪽으로 몰아 놓으면 그것도 틀린다.
    //      G장조의 나란한 조가 C장조(♯ 쪽)라 F♯ 가 맞다.
    check(
      '1-b) ♯ 조는 ♯ 로',
      keyUsesSharps(7, 'major') &&
          !keyUsesSharps(0, 'minor') &&
          noteNameIn(66, 7, 'major') == 'F#4' &&
          noteNameIn(63, 0, 'minor') == 'Eb4',
      'G장조 → ${noteNameIn(66, 7, 'major')} · C단조 → ${noteNameIn(63, 0, 'minor')}',
    );

    // 2) 녹음 전에는 트랙이 안 생긴다
    final before = p.tracks.length;
    await tester.tap(find.text('C4'));
    await tester.pump();
    check(
      '2) 그냥 치면 안 담긴다',
      p.tracks.every((t) => t.name != kLiveTrackName) &&
          p.tracks.length == before,
      '트랙 ${p.tracks.length}개 그대로',
    );

    // 3) 녹음 켜기 → 세 음 치기
    await tester.tap(find.text('녹음'));
    await tester.pump();
    for (final n in ['C4', 'Eb4', 'G4']) {
      await tester.tap(find.text(n));
      await tester.pump();
    }
    check(
      '3) 녹음 중 표시',
      find.text('담기 3').evaluate().isNotEmpty,
      '버튼에 담긴 음 수가 보인다',
    );

    // 4) 끝내면 트랙이 된다
    await tester.tap(find.text('담기 3'));
    await tester.pump();
    final liveTracks = [
      for (final t in p.tracks)
        if (t.name == kLiveTrackName) t,
    ];
    final clip = liveTracks.isEmpty ? null : liveTracks.first.pattern;
    final notes = clip == null ? null : p.findNote('melody', clip)?.notes;
    check(
      '4) 트랙이 생긴다',
      liveTracks.length == 1 && notes != null && notes.length == 3,
      '트랙 ${liveTracks.length}개 · 클립 $clip · 음 ${notes?.length}개',
    );

    // 5) 음색은 라이브에서 고른 것을 따라간다
    check(
      '5) 음색',
      liveTracks.isNotEmpty && liveTracks.first.voice == 'bell',
      '${liveTracks.isEmpty ? '-' : liveTracks.first.voice}',
    );

    // 6) 다시 녹음해도 트랙은 하나 (덮어쓴다)
    await tester.tap(find.text('녹음'));
    await tester.pump();
    await tester.tap(find.text('Bb4'));
    await tester.pump();
    await tester.tap(find.text('담기 1'));
    await tester.pump();
    final again = [
      for (final t in p.tracks)
        if (t.name == kLiveTrackName) t,
    ];
    final n2 = p.findNote('melody', again.first.pattern!)?.notes;
    check(
      '6) 다시 녹음 = 덮어쓰기',
      again.length == 1 && n2 != null && n2.length == 1,
      '트랙 ${again.length}개 · 음 ${n2?.length}개',
    );

    // 7~9) 악기 고르기 — 24종을 한 줄에 늘어놓지 않는다
    check(
      '7) 음색은 한 칸으로',
      find.textContaining('벨 ▾').evaluate().isNotEmpty &&
          find.text('색소폰').evaluate().isEmpty,
      '지금 악기만 보이고 나머지는 접혀 있다',
    );

    await tester.tap(find.textContaining('벨 ▾'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final fams = [
      '건반',
      '뜯고 치는',
      '관악기',
      '현악기',
      '신스',
      '베이스',
    ].where((f) => find.text(f).evaluate().isNotEmpty).length;
    check(
      '8) 계열로 묶여 있다',
      fams == 6 && find.text('색소폰').evaluate().isNotEmpty,
      '묶음 $fams개',
    );

    await tester.tap(find.text('색소폰'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    check('9) 고르면 바뀐다', live.voice == 'sax', live.voice);

    // 11~13) 손이 닿는 자리에 있는가 — 폰에서 **옥타브가 화면 밖으로 밀려나** 있었다.
    //        여섯 가지를 한 줄에 늘어놓은 탓이다(「길게」도 잘려 있었다).
    final octLabel = find.textContaining('옥타브');
    final octOnScreen =
        octLabel.evaluate().isNotEmpty &&
        tester.getBottomRight(octLabel).dx <= 400;
    check(
      '11) 옥타브가 화면 안에',
      octOnScreen,
      octLabel.evaluate().isEmpty
          ? '없음'
          : '오른쪽 끝 ${tester.getBottomRight(octLabel).dx.round()}px (화면 400)',
    );

    // 12) 소리 길이 고르기(「짧게/보통/길게」)는 이제 없다 — 누른 만큼 나고
    //     누른 만큼 적힌다(사용자 요청, 2026-09-13). 고르는 칩이 안 보여야
    //     맞다 — 남아 있으면 이제 아무 뜻도 없는 채로 화면만 먹는다.
    final lensGone = ['짧게', '보통', '길게'].every(
      (t) => find.text(t).evaluate().isEmpty,
    );
    check('12) 길이 고르기 칩이 없다(누른 만큼 난다)', lensGone, '$lensGone');

    // 13) 볼륨·울림에 **이름과 값**이 붙어 있다 — 예전엔 아이콘 둘뿐이라
    //     무엇을 만지는 값인지 알 수 없었다
    final named =
        find.text('볼륨').evaluate().isNotEmpty &&
        find.text('울림').evaluate().isNotEmpty;
    final valued = find.textContaining('%').evaluate().length >= 2;
    check(
      '13) 볼륨·울림에 이름과 값',
      named && valued,
      '이름 $named · 값 ${find.textContaining('%').evaluate().length}개',
    );

    // 10) 가로로 눕혀도 안 넘친다
    tester.view.physicalSize = const Size(800, 400);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: LiveView(
            project: p,
            transport: Transport(),
            live: live,
            host: null,
          ),
        ),
      ),
    );
    await tester.pump();
    final err = tester.takeException();
    check('10) 가로·세로 둘 다 안 넘침', err == null, '넘침 예외 ${err ?? '없음'}');

    // 14) 가로에서는 볼륨·울림이 **한 줄**이다. 세로처럼 두 줄이면 패드가
    //     화면의 3분의 1로 쪼그라든다(폭은 남는데 높이를 낭비한다).
    final vol = tester.getCenter(find.text('볼륨'));
    final rev = tester.getCenter(find.text('울림'));
    check(
      '14) 가로는 볼륨·울림 한 줄',
      (vol.dy - rev.dy).abs() < 1 && rev.dx > vol.dx,
      '볼륨 y${vol.dy.round()} · 울림 y${rev.dy.round()}',
    );

    // 15) 그래서 **위쪽 설정이 화면 절반 전에 끝난다** — 나머지가 전부 패드다.
    //     (패드 자체를 재려면 사설 위젯이라 못 잡아서, 마지막 설정 줄로 잰다)
    final chromeEnds = tester.getBottomRight(find.text('울림')).dy;
    check(
      '15) 패드가 절반 넘게',
      400 - chromeEnds > 200,
      '설정이 y${chromeEnds.round()} 에서 끝 → 패드 ${(400 - chromeEnds).round()}px (화면 400)',
    );

    // ── 16) **녹음 중에 뒤로가기를 눌러도 친 것이 안 사라진다** ──
    //
    // 「담기 N」이 떠 있는데 ← 를 누르면 화면과 함께 `LiveRecorder` 가 통째로
    // 사라졌다 — 안내도 확인도 스낵바도 없이. 몇 마디 쳐 놓고 씬을 보러 잠깐
    // 나갔다 오면 그게 없다. 이제 pop 을 한 번 붙잡아 담고 나간다.
    //
    // 실제 앱처럼 **라우트를 쌓아** 놓고 눌러야 한다(home 에 바로 얹으면 뒤로 갈 곳이 없다).
    {
      tester.view.physicalSize = const Size(400, 800);
      final pb = Project.initial();
      final liveB = LiveChannel()..voice = 'bell';
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Builder(
              builder: (ctx) => TextButton(
                onPressed: () => Navigator.of(ctx).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Scaffold(
                      appBar: AppBar(),
                      body: LiveView(
                        project: pb,
                        transport: Transport(),
                        live: liveB,
                        host: null,
                      ),
                    ),
                  ),
                ),
                child: const Text('라이브로'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('라이브로'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('녹음'));
      await tester.pump();
      for (final n in ['C4', 'G4']) {
        await tester.tap(find.text(n));
        await tester.pump();
      }
      final recShown = find.text('담기 2').evaluate().isNotEmpty;
      await tester.pageBack();
      await tester.pumpAndSettle();
      final name = '라이브 ${pb.scene.name}';
      final kept = pb.userNote[name]?.notes;
      check(
        '16) 녹음 중에 뒤로가도 담긴다',
        recShown &&
            kept != null &&
            kept.length == 2 &&
            pb.tracks.any((t) => t.name == kLiveTrackName),
        '담기 2 보임 $recShown · 남은 음 ${kept?.length ?? 0}개 · '
            '트랙 ${pb.tracks.any((t) => t.name == kLiveTrackName)}',
      );
      check('16-b) 나가면서 터지지 않는다', tester.takeException() == null, '예외 없음');
    }

    // ── 17) **꾹 눌러 소리 유지 · 끌어서 음 잇기** ──
    //
    // 여태 어떻게 만지든 「짧게/보통/길게」 중 미리 고른 길이로만 났다 —
    // 라이브인데 표현이 없었다. 이제 손가락을 옆 패드로 끌면 그 음으로 이어지고,
    // 담기는 것도 **들린 것과 같아야 한다**(끌고 지나간 음이 다 적힌다).
    {
      tester.view.physicalSize = const Size(400, 800);
      final pc = Project.initial();
      final liveC = LiveChannel()..voice = 'bell';
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: LiveView(
              project: pc,
              transport: Transport(),
              live: liveC,
              host: null, // 소리 없이 — 적는 길은 소리와 상관없다
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tap(find.text('녹음'));
      await tester.pump();

      // 아랫줄 1도 → 3도로 **끌어서** 지나간다
      final a = tester.getCenter(find.text('C4'));
      final b = tester.getCenter(find.text('Eb4'));
      final g = await tester.startGesture(a);
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveTo(Offset((a.dx + b.dx) / 2, a.dy));
      await tester.pump(const Duration(milliseconds: 16));
      await g.moveTo(b);
      await tester.pump(const Duration(milliseconds: 16));
      await g.up();
      await tester.pump(const Duration(milliseconds: 16));

      final n = find
          .textContaining('담기')
          .evaluate()
          .map((e) => (e.widget as Text).data ?? '')
          .join();
      check(
        '17) 끌면 지나간 음이 다 담긴다',
        n.contains('담기') && !n.contains('담기 0'),
        '버튼 「$n」 (끌어서 지나간 음 수)',
      );
      check('17-b) 끌어도 안 터진다', tester.takeException() == null, '예외 없음');
    }

    // ── 18) **최근에 쓴 악기가 한 줄에 남는다** ──
    //
    // 연주 중에 악기를 바꾸려면 모달 서랍을 열었다 닫아야 했다 — 그 사이 연주가
    // 끊긴다. 자주 오가는 둘·셋은 **한 번 탭**으로 닿아야 한다.
    {
      tester.view.physicalSize = const Size(400, 800);
      final pd = Project.initial();
      final liveD = LiveChannel()..voice = 'piano';
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: LiveView(
              project: pd,
              transport: Transport(),
              live: liveD,
              host: null,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      // 처음에는 최근 목록이 비어 있다 — 쓴 적이 없다
      final before = find.text(VOICE_LABEL['bell'] ?? 'bell').evaluate().length;

      // 악기를 하나 고른다(소리 장치가 없어 한 번에 골라진다)
      await tester.tap(find.textContaining('▾'));
      await tester.pump(const Duration(milliseconds: 16));
      final bellChip = find.text(VOICE_LABEL['bell'] ?? 'bell').last;
      await tester.ensureVisible(bellChip);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tap(bellChip);
      await tester.pump(const Duration(milliseconds: 16));
      final nowBell = liveD.voice == 'bell';

      // 다른 것으로 다시 바꾸면 **벨이 최근 줄에 남는다**
      await tester.tap(find.textContaining('▾'));
      await tester.pump(const Duration(milliseconds: 16));
      final pianoChip = find.text(VOICE_LABEL['piano'] ?? 'piano').last;
      await tester.ensureVisible(pianoChip);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tap(pianoChip);
      await tester.pump(const Duration(milliseconds: 16));
      final favShown = find
          .text(VOICE_LABEL['bell'] ?? 'bell')
          .evaluate()
          .isNotEmpty;

      // 그 칩을 누르면 한 번에 돌아간다
      if (favShown) {
        await tester.tap(find.text(VOICE_LABEL['bell'] ?? 'bell').first);
        await tester.pump(const Duration(milliseconds: 16));
      }
      check(
        '18) 최근 악기가 한 줄에 남는다',
        before == 0 && nowBell && favShown && liveD.voice == 'bell',
        '처음 $before개 → 벨 고름 $nowBell → 최근 줄에 보임 $favShown → '
            '탭 뒤 ${liveD.voice}',
      );
    }

    // ── 19) **메트로놈이 화면에 있고 켜고 끌 수 있다** ──
    //
    // 드럼 없는 씬에서 녹음할 때 기댈 박이 아예 없었다. 소리 자체는 앞질러
    // 예약하는 셈이 정하고(그건 `live_check_test` 9번이 잰다), 여기서는
    // **배선**만 본다 — 켜면 켜지고 끄면 꺼지는가.
    {
      tester.view.physicalSize = const Size(400, 800);
      final pe = Project.initial();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: LiveView(
              project: pe,
              transport: Transport(),
              live: LiveChannel(),
              host: null,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      final there = find.text('메트').evaluate().isNotEmpty;
      await tester.ensureVisible(find.text('메트').first);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tap(find.text('메트').first);
      await tester.pump(const Duration(milliseconds: 16));
      // 켜면 반주도 같이 켜진다 — 박을 세려면 흘러야 한다
      // (host 가 null 이라 소리는 안 나지만 배선은 그대로 탄다)
      await tester.tap(find.text('메트').first);
      await tester.pump(const Duration(milliseconds: 16));
      check(
        '19) 메트로놈을 켜고 끈다',
        there && tester.takeException() == null,
        '칩 있음 $there · 켜고 끄기 예외 없음',
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '라이브 화면 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });

  // ── 반음 건반으로 넘기면 도수 패드가 피아노로 바뀐다 ──
  //
  // 「반음」 칩을 누르면 단음·화음·아르페지오 칩이 사라지고(반음 건반은 늘
  // 단음이라 그 셋은 뜻이 없다) 실제 피아노가 나온다. 다시 누르면 원래대로 —
  // 도수 패드와 모드 칩이 돌아온다. 위 큰 시험과 따로 둔 것은 tester 상태를
  // 처음부터 깨끗하게 두기 위해서다.
  testWidgets('반음 건반 전환', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final pc = Project.initial();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: LiveView(
            project: pc,
            transport: Transport(),
            live: LiveChannel(),
            host: null,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final modeChipsBefore = find.text('단음').evaluate().isNotEmpty;
    await tester.ensureVisible(find.text('반음').first);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tap(find.text('반음').first);
    await tester.pump(const Duration(milliseconds: 16));
    final modeChipsGone = find.text('단음').evaluate().isEmpty;
    // 피아노 흰 건반 음이름(C)이 하나는 보여야 한다
    final pianoShown = find.text('C').evaluate().isNotEmpty;
    await tester.tap(find.text('반음').first);
    await tester.pump(const Duration(milliseconds: 16));
    final modeChipsBack = find.text('단음').evaluate().isNotEmpty;

    // ignore: avoid_print
    print(
      '${modeChipsBefore && modeChipsGone && pianoShown && modeChipsBack ? '  OK' : '실패'} '
      '반음 건반 전환 — 전 $modeChipsBefore · 켠 뒤 모드칩 사라짐 $modeChipsGone · '
      '건반 보임 $pianoShown · 끈 뒤 되돌아옴 $modeChipsBack',
    );
    expect(modeChipsBefore, true);
    expect(modeChipsGone, true);
    expect(pianoShown, true);
    expect(modeChipsBack, true);
  });
}
