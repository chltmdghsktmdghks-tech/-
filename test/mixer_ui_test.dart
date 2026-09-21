// 5단계 24/N — 믹서 보기 확인.
//   flutter test test/mixer_ui_test.dart
//
// 세로 화면에서 스트립(세로 페이더)은 100dp 씩 먹는다 — **세 개밖에 안 보인다.**
// 재즈·팝처럼 6~7트랙인 곡에서 밸런스를 맞추려면 계속 좌우로 밀어야 한다.
// 그래서 트랙이 많으면 줄 모양이 기본이어야 하고, 언제든 바꿀 수 있어야 한다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/mixer_view.dart';

void main() {
  testWidgets('믹서 보기', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = Project.initial(); // 로파이 4트랙
    Widget app() => MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: MixerView(
          project: p,
          live: LiveChannel(),
          master: MasterChannel(),
          host: null,
        ),
      ),
    );

    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 16));

    // 1) 트랙이 적으면 스트립(자세히)이 기본
    check(
      '1) 4트랙은 스트립',
      find.text('트랙 4개').evaluate().isNotEmpty &&
          find.text('자세히').evaluate().isNotEmpty,
      '보기 줄 있음',
    );

    // 2) 줄 모양으로 바꾸면 **모든 트랙이 한 화면에** 보인다
    await tester.tap(find.text('한눈에'));
    await tester.pump(const Duration(milliseconds: 16));
    final names = [for (final t in p.tracks) t.name];
    var shown = names.where((n) => find.text(n).evaluate().isNotEmpty).length;
    check('2) 줄 모양 — 전부 보임', shown == names.length, '$shown/${names.length}');

    // 3) 7트랙 곡(재즈)은 **줄 모양이 기본**이어야 한다 — 스트립이면 3개만 보인다
    p.setGenre('jazz');
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: MixerView(
            key: const ValueKey('jazz'), // 새로 만들어 기본값을 다시 정하게
            project: p,
            live: LiveChannel(),
            master: MasterChannel(),
            host: null,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final jazzNames = [for (final t in p.tracks) t.name];
    shown = jazzNames.where((n) => find.text(n).evaluate().isNotEmpty).length;
    check(
      '3) 6트랙 이상은 줄 모양이 기본',
      p.tracks.length >= 6 && shown == jazzNames.length,
      '트랙 ${p.tracks.length}개 · 보이는 것 $shown개 · ${jazzNames.join(',')}',
    );

    // 4) 마스터는 어느 보기에서도 붙박이 (줄 모양에서는 '전체 볼륨' 이라고 쓴다)
    check('4) 마스터 고정', find.text('전체 볼륨').evaluate().isNotEmpty, '전체 볼륨 줄이 보임');

    // 4-b) 스트립에도 M/S 가 있어야 한다 — 믹싱 중 제일 자주 누른다
    check(
      '4-b) 스트립에 M/S',
      find.text('M').evaluate().length >= 4 &&
          find.text('S').evaluate().length >= 4,
      'M ${find.text('M').evaluate().length}개 · S ${find.text('S').evaluate().length}개',
    );

    // 4-c) **솔로를 켜면 나머지 스트립이 흐려진다.**
    //
    // 스트립은 저마다 `AnimatedBuilder(animation: track)` 으로 자기 트랙만 듣는데,
    // 흐림 조건(`anySolo && !track.solo`)은 **남의 트랙** 값에 달려 있다.
    // 그래서 드럼 S 를 켜도 베이스 스트립이 그대로 밝았다 — 소리는 바뀌는데
    // 「왜 갑자기 안 들리지」가 화면 어디에도 안 나왔다.
    {
      tester.view.physicalSize = const Size(400, 800);
      final ps = Project.initial(); // 로파이 4트랙 · 스트립 보기
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: MixerView(
              key: const ValueKey('solo'),
              project: ps,
              live: LiveChannel(),
              master: MasterChannel(),
              host: null,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));

      /// 그 트랙 이름을 감싸고 있는 Opacity 의 값 — 흐림은 이걸로만 보인다.
      double? opacityOf(String name) {
        final f = find.ancestor(
          of: find.text(name),
          matching: find.byType(Opacity),
        );
        final e = f.evaluate();
        if (e.isEmpty) return null;
        return (e.first.widget as Opacity).opacity;
      }

      final first = ps.tracks.first.name; // 드럼
      final second = ps.tracks[1].name; // 베이스
      final beforeDim = opacityOf(second);
      await tester.tap(find.text('S').first); // 드럼 솔로
      await tester.pump(const Duration(milliseconds: 16));
      final afterDim = opacityOf(second);
      final soloStays = opacityOf(first);
      check(
        '4-c) 솔로를 켜면 나머지가 흐려진다',
        ps.tracks.first.solo &&
            beforeDim != null &&
            afterDim != null &&
            beforeDim == 1.0 &&
            afterDim < 1.0 &&
            soloStays == 1.0,
        '$second ${beforeDim?.toStringAsFixed(2)} → ${afterDim?.toStringAsFixed(2)} · '
            '$first ${soloStays?.toStringAsFixed(2)}',
      );
    }

    // 5-a) 줄에는 **볼륨 하나만** 크게 (좌우·잔향·EQ 를 같이 늘어놓으면 하나도 못 잡는다)
    tester.view.physicalSize = const Size(400, 800);
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tap(find.text('한눈에'));
    await tester.pump(const Duration(milliseconds: 16));
    check(
      '5-a) 줄에는 볼륨만',
      find.text('좌우').evaluate().isEmpty &&
          find.text('100%').evaluate().isNotEmpty,
      '좌우·잔향은 줄에 없음 · 볼륨 값은 보임',
    );

    // 손잡이가 **손가락만 해야** 한다 — 지름 22 이상(예전 값은 16)
    final thumb = tester.getSize(find.byType(Slider).first);
    check('5-b) 슬라이더가 크다', thumb.height >= 28, '높이 ${thumb.height.round()}px');

    // 5-c) 톱니를 누르면 나머지가 **큰 슬라이더**로 나온다
    await tester.tap(find.byIcon(Icons.tune).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final labels = [
      '볼륨',
      '좌우',
      '울림',
      '저음',
      '고음',
    ].where((t) => find.text(t).evaluate().isNotEmpty).length;
    check('5-c) 채널 시트', labels == 5, '큰 슬라이더 $labels/5');

    // 시트는 화면 위에 얹히므로 위젯 순서상 **뒤쪽**이다
    final big = tester.getSize(find.byType(Slider).last);
    check('5-d) 시트 슬라이더는 더 크다', big.height >= 36, '높이 ${big.height.round()}px');

    // 5-e) 「이 트랙 삭제」 — **폭을 다 쓰는 큰 버튼**이어야 한다.
    //      작은 글자 버튼을 오른쪽 구석에 붙여 놨더니 안드로이드 내비게이션 바에
    //      딱 붙어서, 폰에서 두 번 눌렀는데 안 먹었다.
    final before = p.tracks.length;
    // 지우기 전에 **무엇을 잃는지** 적어 둔다 — 되돌렸을 때 이름만 돌아오고
    // 음은 안 돌아오는 일이 흔하다(씬마다 클립이 따로 달려 있다).
    final victim = p.tracks.first;
    final gonePattern = (
      victim.id,
      p.scenes
          .map((sc) => sc.clips[victim.id])
          .firstWhere((c) => (c ?? '').isNotEmpty, orElse: () => null),
    );
    final delBtn = find.widgetWithText(OutlinedButton, '이 트랙 삭제');
    final delSize = tester.getSize(delBtn);
    check(
      '5-e) 지우기 버튼이 크다',
      delSize.width > 300 && delSize.height >= 46,
      '${delSize.width.round()}×${delSize.height.round()}px (화면 400)',
    );

    // 5-e2) **한 가지를 두 이름으로 부르지 않는다.**
    //   라이브 화면은 「울림」인데 믹서만 「잔향」이었다. 같은 손잡이에 두 이름이
    //   붙으면 초보는 다른 것인 줄 안다(빠르기/템포와 같은 병).
    //   인서트 플러그인 「리버브」는 다른 물건이라 그대로 둔다.
    check(
      '5-e2) 울림이라고 부른다',
      find.text('울림').evaluate().isNotEmpty &&
          find.textContaining('잔향').evaluate().isEmpty,
      '울림 ${find.text('울림').evaluate().length}개 · '
          '잔향 ${find.textContaining('잔향').evaluate().length}개',
    );

    // 5-f) 한 번 묻는다 — 되돌릴 수는 있지만 곡 전체에서 악기 하나가 사라지는 자리다
    // 시트는 스크롤되는 자리다 — 로우컷·하이컷(2026-09-16 추가)까지 늘어나
    // 화면 높이를 넘으면 지우기 버튼이 안 보일 수 있어 먼저 스크롤해서 본다.
    await tester.ensureVisible(delBtn);
    await tester.pumpAndSettle();
    await tester.tap(delBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final asked = find
        .textContaining('모든 씬에서 이 악기가 사라집니다')
        .evaluate()
        .isNotEmpty;
    check(
      '5-f) 지우기 전에 묻는다',
      asked && p.tracks.length == before,
      '확인 창 $asked · 아직 트랙 ${p.tracks.length}개',
    );

    // 5-g) 취소하면 안 지운다
    await tester.tap(find.text('취소'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    check('5-g) 취소하면 그대로', p.tracks.length == before, '트랙 ${p.tracks.length}개');

    // 5-h) 「지우기」를 누르면 실제로 지워지고, 채널 시트도 같이 닫힌다
    await tester.tap(delBtn);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('지우기'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // 「울림」은 마스터 줄에도 있어서 시트가 닫혔는지 못 가른다 —
    // 「이 트랙 삭제」 버튼은 채널 시트에만 있다.
    check(
      '5-h) 지우면 지워진다',
      p.tracks.length == before - 1 && find.text('이 트랙 삭제').evaluate().isEmpty,
      '트랙 $before → ${p.tracks.length}개 · 시트도 닫힘',
    );

    // 5-i) **되돌릴 수 있다.** 트랙 하나에 모든 씬의 클립이 달려 있어서,
    //      이 한 번이 곡 전체에서 그 악기를 지운다 — 곡·씬은 되돌아오는데
    //      제일 많이 잃는 트랙만 안 되고 있었다.
    final undo = find.text('되돌리기');
    check(
      '5-i) 되돌릴 길이 뜬다',
      undo.evaluate().isNotEmpty,
      '알림 ${find.byType(SnackBar).evaluate().length}개',
    );
    if (undo.evaluate().isNotEmpty) {
      await tester.tap(undo);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final back = p.tracks.length == before;
      final clipBack = p.scenes.any(
        (sc) => (sc.clips[gonePattern.$1] ?? '') == gonePattern.$2,
      );
      check(
        '5-i) 되돌리면 음까지 돌아온다',
        back && clipBack,
        '트랙 ${p.tracks.length}개 · 씬 클립 ${clipBack ? "돌아옴" : "빔"}',
      );
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // 5) 가로는 원래대로 줄 모양(보기 줄 없음)
    tester.view.physicalSize = const Size(800, 400);
    await tester.pumpWidget(app());
    await tester.pump(const Duration(milliseconds: 16));
    check(
      '5) 가로는 그대로',
      find.text('한눈에').evaluate().isEmpty,
      '가로에선 보기 줄이 필요 없다',
    );
    final err = tester.takeException();
    check('6) 가로·세로 안 넘침', err == null, '넘침 예외 ${err ?? '없음'}');

    // 7) 가로에서는 이름과 볼륨이 **같은 줄**이다. 두 줄로 두면 한 줄이 84dp 라
    //    400dp 화면에 세 줄밖에 안 들어간다(그림으로 뽑아 보고 잡았다).
    // (앞에서 스타일을 재즈로 바꾸고 트랙도 하나 지웠다 — 이름을 박아 두면 안 된다)
    final nm = tester.getCenter(find.text(p.tracks.first.name).first);
    // 값 글자는 트랙마다 달라서(재즈 프리셋) 못 박으면 엉뚱한 줄을 잡는다
    // → **첫 줄의 슬라이더**를 잰다.
    final firstSlider = tester.getCenter(find.byType(Slider).first);
    check(
      '7) 가로는 이름·볼륨 한 줄',
      (nm.dy - firstSlider.dy).abs() < 6 && firstSlider.dx > nm.dx,
      '이름 y${nm.dy.round()} · 슬라이더 y${firstSlider.dy.round()}',
    );

    // 8) 그래서 **마스터까지 다 보인다** — 스크롤해야 나오면 못 찾는다
    final master = find.text('MASTER');
    check(
      '8) 마스터까지 화면 안',
      master.evaluate().isNotEmpty && tester.getBottomRight(master).dy <= 400,
      '마스터 아래끝 y${master.evaluate().isEmpty ? '-' : tester.getBottomRight(master).dy.round()}',
    );

    // ignore: avoid_print
    print(fail == 0 ? '믹서 보기 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
