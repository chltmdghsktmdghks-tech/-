// 5단계 16/N — 쇼 화면 확인.
//   flutter test test/show_check_test.dart
//
// 쇼 화면은 **틀려도 그럴듯해 보인다.** 아무 박자에나 튀어도 "그런 연출인가" 싶고,
// 구간 이름이 한 칸 밀려 있어도 눈치채기 어렵다. 그래서 숫자로 본다:
//  · 악보에 적힌 그 시각에 튀는가(그 악기만)
//  · 구간 이름이 그 시각의 구간과 같은가
//  · 소리를 내는 트랙은 **하나도 빠짐없이** 움직이는가(가만히 있는 악기 = 고장으로 보인다)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/ui/show_view.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/arrange.dart';
import 'package:music_doodle_engine/presets.dart';
import 'package:music_doodle_engine/show_ops.dart';
import 'package:music_doodle_engine/song.dart';
import 'package:music_doodle_engine/ui/show_band.dart';

void main() {
  // ── 화면이 저 혼자 꺼지면 안 된다 ──
  //
  // 쇼 화면은 「곡을 틀어 놓고 폰을 세워 두는 자리」인데, 안드로이드 기본 화면 꺼짐이
  // 보통 30초라 **3분짜리 곡의 첫 소절에서 화면이 꺼졌다.** 남에게 보여 주려고 만든
  // 화면이 30초 만에 검게 되면 그 화면은 없는 것과 같다.
  // 들어갈 때 켜고 **나갈 때 끄는지**까지 본다 — 앱 전체에 켜 두면 배터리를 먹는다.
  testWidgets('쇼 화면 — 화면 안 꺼짐', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final calls = <bool>[];
    const ch = MethodChannel('music_doodle/screen');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(ch, (
      c,
    ) async {
      if (c.method == 'keepAwake') calls.add(c.arguments as bool);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ch,
        null,
      ),
    );

    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final p = Project.initial();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShowView(project: p, transport: Transport(), host: null),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    check('1) 들어가면 켠다', calls.isNotEmpty && calls.first == true, '$calls');

    // 화면을 치운다 = 나간 것
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    await tester.pump(const Duration(milliseconds: 16));
    check('2) 나가면 끈다', calls.length >= 2 && calls.last == false, '$calls');

    // ignore: avoid_print
    print(fail == 0 ? '쇼 화면 안 꺼짐 통과' : '실패 $fail건');
    expect(fail, 0);
  });

  test('쇼 화면', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final p = Project.initial();
    final tr = Transport();
    final score = ShowScore.from(p, tr);

    // 1) 곡 길이가 재생 길이와 같다
    final want = SceneSequencer.songSeconds(p, tr);
    check(
      '1) 곡 길이',
      (score.total - want).abs() < 1e-6,
      '${score.total.toStringAsFixed(1)}초 · 구간 ${score.spans.length}개',
    );

    // 2) 소리 내는 트랙은 전부 움직인다 — 가만히 있는 악기는 고장처럼 보인다
    final melodic = [
      for (final t in p.tracks)
        if (t.type != 'drum') t,
    ];
    final moving = [
      for (final t in melodic)
        if ((score.trackTimes[t.id] ?? []).isNotEmpty) t,
    ];
    check(
      '2) 모든 악기가 움직인다',
      moving.length == melodic.length,
      '${moving.length}/${melodic.length} · ${[for (final t in moving) t.name].join(',')}',
    );

    // 3) 악보에 적힌 그 시각에 튄다 — 첫 타격 시각에 1, 조금 뒤엔 줄어든다
    final id0 = melodic.first.id;
    final t0 = score.trackTimes[id0]!.first;
    final end0 = score.trackEnds[id0]!.first;
    final at = score.trackPulse(id0, t0);
    final soon = score.trackPulse(id0, t0 + 0.15);
    check(
      '3) 그 시각에 튄다',
      (at - 1).abs() < 1e-9 && soon < at && soon > 0,
      '지금 ${at.toStringAsFixed(2)} · 0.15초 뒤 ${soon.toStringAsFixed(2)} '
          '(음 길이 ${(end0 - t0).toStringAsFixed(2)}초)',
    );

    // 3-b) **서스테인** — 음이 아직 눌려 있는 동안은 안 꺼진다(5단계 30/N).
    //      예전엔 0.3초 만에 0 이 됐다. 4초 끄는 패드가 깜빡이고 마는 셈이었다.
    final held = score.trackPulse(id0, end0 - 0.01);
    check(
      '3-b) 눌려 있는 동안 계속 빛난다',
      held >= ShowScore.kSustain - 1e-9,
      '끝나기 직전 ${held.toStringAsFixed(2)} (바닥 ${ShowScore.kSustain})',
    );

    // 3-c) **릴리스** — 끝나면 잦아든다. 뚝 끊으면 깜빡이는 것으로 보인다.
    final justAfter = score.trackPulse(id0, end0 + ShowScore.kRelease * 0.5);
    final wellAfter = score.trackPulse(id0, end0 + ShowScore.kRelease + 0.01);
    // 다음 음이 곧바로 이어지면 릴리스를 볼 수 없다 — 그때는 건너뛴다
    final gap = score.trackTimes[id0]!.firstWhere(
      (x) => x > t0,
      orElse: () => double.infinity,
    );
    final canSee = gap > end0 + ShowScore.kRelease + 0.02;
    check(
      '3-c) 끝나면 잦아든다',
      !canSee ||
          (justAfter > 0 && justAfter < ShowScore.kSustain && wellAfter == 0),
      canSee
          ? '끝난 뒤 ${justAfter.toStringAsFixed(2)} → ${wellAfter.toStringAsFixed(2)}'
          : '다음 음이 바로 이어져 건너뜀',
    );

    // 4) 첫 타격 **전에는** 조용하다(0 이어야 한다 — 시작하자마자 다 튀면 가짜다)
    check(
      '4) 시작 전엔 조용',
      score.trackPulse(melodic.first.id, t0 - 0.01) == 0,
      '첫 타격 ${t0.toStringAsFixed(2)}초 직전 0',
    );

    // 5) 악기별로 나뉜다 — 베이스가 울릴 때 멜로디가 같이 튀면 안 된다
    final bass = p.tracks.firstWhere((t) => t.type == 'bass');
    final mel = p.tracks.firstWhere((t) => t.type == 'melody');
    final bt = score.trackTimes[bass.id]!;
    // 멜로디가 울리지 않는 베이스 타격을 하나 찾는다
    final mt = score.trackTimes[mel.id]!;
    double? lonely;
    for (final b in bt) {
      final near = mt.any((m) => (m - b).abs() < 0.05);
      if (!near) {
        lonely = b;
        break;
      }
    }
    check(
      '5) 악기별로 나뉜다',
      lonely != null &&
          score.trackPulse(bass.id, lonely) > 0.9 &&
          score.trackPulse(mel.id, lonely) < 0.9,
      lonely == null
          ? '베이스만 울리는 지점을 못 찾음'
          : '${lonely.toStringAsFixed(2)}초 — 베이스 ${score.trackPulse(bass.id, lonely).toStringAsFixed(2)} · 멜로디 ${score.trackPulse(mel.id, lonely).toStringAsFixed(2)}',
    );

    // 6) 구간 이름이 그 시각의 구간과 같다 — 구간 한가운데를 찍어 본다
    var okSec = true;
    final names = <String>[];
    for (var i = 0; i < score.spans.length; i++) {
      final mid = score.spans[i].$1 + score.spans[i].$2 / 2;
      if (score.sectionAt(mid) != i) okSec = false;
      names.add(score.sectionNames[i]);
    }
    check(
      '6) 구간 이름',
      okSec && names.length == score.spans.length,
      names.join('→'),
    );

    // 7) 구간 경계 — 끝나는 순간은 **다음 구간**이어야 한다(한 칸 밀리기 쉬운 자리)
    final b0 = score.spans[0].$2;
    check(
      '7) 구간 경계',
      score.sectionAt(b0 - 0.001) == 0 && score.sectionAt(b0) == 1,
      '${b0.toStringAsFixed(1)}초에서 0 → 1',
    );

    // 8) 드럼도 나뉜다 — 킥과 하이햇이 따로 논다
    final kick = score.drumTimes['kick'] ?? [];
    final hat = score.drumTimes['hat'] ?? [];
    check(
      '8) 드럼 레인',
      kick.isNotEmpty && hat.isNotEmpty && kick.length != hat.length,
      '킥 ${kick.length}타 · 하이햇 ${hat.length}타',
    );

    // ignore: avoid_print
    print(fail == 0 ? '쇼 화면 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });

  testWidgets('쇼 화면 — 그리기', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final p = Project.initial()..name = '내 곡';
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          backgroundColor: Colors.black,
          body: ShowView(project: p, transport: Transport(), host: null),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    // 구간 띠에 구간 이름이 전부 있어야 한다(하나라도 빠지면 곡의 어디쯤인지 못 읽는다)
    final names = {for (final s in p.song.sections) p.scenes[s.scene].name};
    final shown = names.where((n) => find.text(n).evaluate().isNotEmpty).length;
    check('9) 구간 이름이 보인다', shown == names.length, '$shown/${names.length}');

    // 악기 이름도 — 누가 연주 중인지가 이 화면의 내용이다.
    // (기본은 밴드 화면이고 이름은 **그림 위에** 그려서 글자 찾기로는 안 잡힌다 →
    //  막대 화면으로 바꿔서 확인한다. 밴드 쪽 이름은 눈으로 본다.)
    await tester.tap(find.byIcon(Icons.bar_chart));
    await tester.pump(const Duration(milliseconds: 16));
    final melodic = [
      for (final t in p.tracks)
        if (t.type != 'drum') t.name,
    ];
    final shownT = melodic
        .where((n) => find.text(n).evaluate().isNotEmpty)
        .length;
    check(
      '10) 악기 이름이 보인다',
      shownT == melodic.length,
      '$shownT/${melodic.length} · ${melodic.join(',')}',
    );

    check(
      '11) 곡 이름과 시간',
      find.text('내 곡').evaluate().isNotEmpty &&
          find.textContaining(' / ').evaluate().isNotEmpty,
      '제목 · 0:00 / 전체',
    );

    // 가로로 눕혀도 안 넘친다 — 쇼는 눕혀 놓고 보는 화면이다
    tester.view.physicalSize = const Size(800, 400);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          backgroundColor: Colors.black,
          body: ShowView(project: p, transport: Transport(), host: null),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final err = tester.takeException();
    check('12) 가로·세로 둘 다 안 넘침', err == null, '넘침 예외 ${err ?? '없음'}');

    // ignore: avoid_print
    print(fail == 0 ? '쇼 화면 그리기 통과' : '실패 $fail건');
    expect(fail, 0);
  });

  testWidgets('쇼 화면 — 밴드', (tester) async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final p = Project.initial()..name = '내 곡';
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          backgroundColor: Colors.black,
          body: ShowView(project: p, transport: Transport(), host: null),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    // 처음은 밴드 — 사람이 서 있는 화면이 기본이다(막대는 '자세히 보기' 쪽)
    check(
      '13) 밴드가 기본',
      find.byType(CustomPaint).evaluate().isNotEmpty,
      '밴드 그림 있음',
    );

    // 막대로 바꾸면 악기 이름이 글자로 나온다
    await tester.tap(find.byIcon(Icons.bar_chart));
    await tester.pump(const Duration(milliseconds: 16));
    final melodic = [
      for (final t in p.tracks)
        if (t.type != 'drum') t.name,
    ];
    final shown = melodic
        .where((n) => find.text(n).evaluate().isNotEmpty)
        .length;
    check(
      '14) 막대로 전환',
      shown == melodic.length && find.text('킥').evaluate().isNotEmpty,
      '악기 $shown/${melodic.length} · 드럼 줄 보임',
    );

    // 다시 밴드로
    await tester.tap(find.byIcon(Icons.groups));
    await tester.pump(const Duration(milliseconds: 16));
    check(
      '15) 다시 밴드로',
      find.byIcon(Icons.bar_chart).evaluate().isNotEmpty,
      '전환 아이콘이 되돌아옴',
    );

    // 가로로 눕혀도 안 넘친다
    tester.view.physicalSize = const Size(800, 400);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          backgroundColor: Colors.black,
          body: ShowView(project: p, transport: Transport(), host: null),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    final err = tester.takeException();
    check('16) 밴드도 가로·세로 안 넘침', err == null, '넘침 예외 ${err ?? '없음'}');

    // ignore: avoid_print
    print(fail == 0 ? '쇼 화면 밴드 통과' : '실패 $fail건');
    expect(fail, 0);
  });

  // 5단계 30/N — 때림 → 서스테인 → 릴리스 세 토막을 **손으로 만든 악보**로 본다.
  // 진짜 곡에서는 음이 바로 이어져 릴리스 구간이 잘 안 나온다.
  test('서스테인·릴리스', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    // 2초에 시작해 3초 동안 눌리는 음 하나(끝 5초). 그 뒤로는 아무것도 없다.
    const s = ShowScore(
      spans: [(0, 10)],
      sectionNames: ['하나'],
      trackTimes: {
        'pad': [2.0],
      },
      trackEnds: {
        'pad': [5.0],
      },
      trackPitch: {
        'pad': [0.5],
      },
      drumTimes: {},
      total: 10,
    );
    double at(double t) => s.trackPulse('pad', t);

    check('1) 치기 전엔 0', at(1.99) == 0, '${at(1.99)}');
    check(
      '2) 치는 순간 1',
      (at(2.0) - 1).abs() < 1e-9,
      '${at(2.0).toStringAsFixed(2)}',
    );

    // 3) 3초를 끄는 동안 **한 번도 안 꺼진다** (예전엔 2.3초에 0 이 됐다)
    final dips = [
      for (var t = 2.0; t < 5.0; t += 0.05)
        if (at(t) < ShowScore.kSustain - 1e-9) t,
    ];
    check(
      '3) 누르는 3초 내내 켜져 있다',
      dips.isEmpty,
      '바닥 ${ShowScore.kSustain} 아래로 내려간 시점 ${dips.length}개',
    );

    // 4) 가운데는 서스테인 바닥에 앉아 있다(때림이 이미 잦아든 뒤)
    check(
      '4) 서스테인 바닥',
      (at(3.5) - ShowScore.kSustain).abs() < 1e-9,
      '3.5초 ${at(3.5).toStringAsFixed(2)}',
    );

    // 5) 끝나면 잦아들고, 릴리스가 지나면 0
    final half = at(5.0 + ShowScore.kRelease / 2);
    final done = at(5.0 + ShowScore.kRelease + 0.01);
    check(
      '5) 끝나면 잦아든다',
      half > 0 && half < ShowScore.kSustain && done == 0,
      '절반 ${half.toStringAsFixed(2)} → 지난 뒤 ${done.toStringAsFixed(2)}',
    );

    // ignore: avoid_print
    print(fail == 0 ? '서스테인·릴리스 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });

  // 5단계 41/N — 연주자 개성과 악기 고르기.
  // 화면 그림은 눈으로 봐야 하지만 **규칙은 숫자로 볼 수 있다**:
  // 같은 음색이면 같은 악기를 들어야 하고, 음색이 다르면 다른 악기를 든다.
  test('연주자 악기', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    BandMember m(String name, String type, String voice) => BandMember(
      name: name,
      type: type,
      voice: voice,
      color: Colors.teal,
      level: 0,
      hit: 0,
      muted: false,
    );

    // 1) **음색**이 악기를 정한다 — 트랙 종류가 아니라.
    //    폰에서 「기타」 라고 이름 짓고 나일론 기타를 골랐는데 색소폰을 불고 있었다.
    check(
      '1) 음색이 악기를 정한다',
      m('기타', 'melody', 'nylon').instrument == 'guitar',
      '멜로디 트랙 + 나일론 → 기타',
    );
    check(
      '2) 색소폰은 관악기',
      m('리드', 'melody', 'sax').instrument == 'horn',
      'sax → horn',
    );
    check(
      '3) 피아노는 건반',
      m('패드', 'chord', 'piano').instrument == 'keys',
      'piano → keys',
    );
    check(
      '4) 베이스는 기타류',
      m('베이스', 'bass', 'upright').instrument == 'guitar',
      'upright → guitar',
    );
    // 마림바·벨은 **건반 자세**다 — 소리는 '뜯고 치는' 쪽이지만 자세가 다르다
    check(
      '4-b) 마림바는 건반 자세',
      m('비브라폰', 'chord', 'marimba').instrument == 'keys',
      'marimba → keys',
    );

    // 4-c) **노래는 아무것도 안 든다.** 이게 빠져 있어서 'vocal' 이 트랙 종류
    //      ('melody')로 떨어져 팝·R&B·가스펠 보컬이 **관악기를 불고 있었다.**
    //      소리는 사람 목소리인데 무대에서는 색소폰을 불고 있었던 셈이다.
    check(
      '4-c) 노래는 마이크',
      m('보컬', 'melody', 'vocal').instrument == 'voice',
      'vocal → voice',
    );

    // 4-d) 곡에 실제로 쓰는 음색이 **하나도 빠짐없이** 표에 있어야 한다.
    //      빠지면 조용히 엉뚱한 자세로 그려진다 — 오류가 안 난다. 그게 제일 나쁘다.
    {
      final used = <String>{};
      for (final f in kObjectSongForms.values) {
        for (final t in f.tracks) {
          if (t.type != 'drum') used.add(t.voice);
        }
      }
      final orphan = [
        for (final v in used)
          if (!kBandInstrument.values.any((l) => l.contains(v))) v,
      ];
      check(
        '4-d) 곡이 쓰는 음색이 표에 다 있다',
        orphan.isEmpty,
        orphan.isEmpty ? '${used.length}종 전부' : orphan.join(', '),
      );
    }

    // 5) 음색을 모르면 **예전 규칙**(트랙 종류)으로 떨어진다
    check(
      '5) 모르는 음색은 트랙 종류로',
      m('무엇', 'chord', '???').instrument == 'keys',
      '알 수 없는 음색 → 종류로',
    );

    // 6-a) **음 높이가 손 자리를 정한다** — 음이 바뀔 때만 바뀌어야 한다.
    //      예전엔 사인파로 손을 계속 흔들었다. 그건 연주가 아니라 떨림이다.
    final pr = Project.initial();
    final ptr = Transport();
    final sc = ShowScore.from(pr, ptr);
    final bassId = pr.tracks.firstWhere((t) => t.type == 'bass').id;
    final times = sc.trackTimes[bassId]!;
    final pitches = sc.trackPitch[bassId]!;
    check(
      '6-a) 음마다 높이가 있다',
      pitches.length == times.length,
      '음 ${times.length}개 · 높이 ${pitches.length}개',
    );

    // 0~1 로 펴져 있다(제일 낮은 음 0, 제일 높은 음 1)
    final lo = pitches.reduce((a, b) => a < b ? a : b);
    final hi = pitches.reduce((a, b) => a > b ? a : b);
    check(
      '6-b) 0~1 로 펴진다',
      lo <= 1e-9 && (hi - 1).abs() < 1e-9,
      '${lo.toStringAsFixed(2)} ~ ${hi.toStringAsFixed(2)}',
    );

    // **음 사이에서는 값이 안 바뀐다** — 손이 가만히 있어야 한다
    final t0 = times.first;
    final next = times.firstWhere(
      (x) => x > t0 + 0.01,
      orElse: () => double.infinity,
    );
    final still = next.isFinite
        ? (sc.pitchAt(bassId, t0) - sc.pitchAt(bassId, (t0 + next) / 2)).abs()
        : 0.0;
    check(
      '6-c) 음 사이에는 안 움직인다',
      still < 1e-9,
      '${t0.toStringAsFixed(2)}초와 그 다음 음 사이 차이 $still',
    );

    // 7) 표에 적힌 음색이 서로 겹치지 않는다 — 겹치면 어느 악기를 들지 순서에 달린다
    final seen = <String>{};
    final dup = <String>[];
    for (final e in kBandInstrument.entries) {
      for (final v in e.value) {
        if (!seen.add(v)) dup.add(v);
      }
    }
    check(
      '7) 음색이 두 악기에 안 겹친다',
      dup.isEmpty,
      dup.isEmpty ? '${seen.length}개 전부' : dup.join(','),
    );

    // ignore: avoid_print
    print(fail == 0 ? '연주자 악기 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });

  // 5단계 35/N — 구간 전환 섬광. 인트로 → 벌스 → 코러스가 귀로만 넘어가면
  // 화면은 계속 같아 보인다. 그래서 **구간이 바뀐 그 시각에만** 1 이어야 한다.
  test('구간 전환 섬광', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final p = Project.initial();
    final tr = Transport();
    final score = ShowScore.from(p, tr);
    const dec = 0.7;

    // 두 번째 구간이 시작하는 시각
    final at = score.spans[1].$1;
    check(
      '1) 넘어가는 순간 1',
      (score.sectionPulse(at, dec) - 1).abs() < 1e-9,
      '${score.sectionPulse(at, dec).toStringAsFixed(2)} (${at.toStringAsFixed(1)}초)',
    );

    final half = score.sectionPulse(at + dec / 2, dec);
    check('2) 절반쯤에서 절반', (half - 0.5).abs() < 1e-6, half.toStringAsFixed(2));

    check('3) 지나면 0', score.sectionPulse(at + dec + 0.01, dec) == 0, '꺼짐');

    // 구간 한가운데는 조용해야 한다 — 계속 번쩍이면 눈이 아프다
    final mid = score.spans[1].$1 + score.spans[1].$2 / 2;
    check(
      '4) 구간 한가운데는 0',
      score.sectionPulse(mid, dec) == 0,
      '${mid.toStringAsFixed(1)}초',
    );

    // 구간마다 한 번씩 — 7구간이면 7번
    var lit = 0;
    for (final sp in score.spans) {
      if (score.sectionPulse(sp.$1, dec) > 0.9) lit++;
    }
    check(
      '5) 구간마다 한 번',
      lit == score.spans.length,
      '$lit/${score.spans.length}구간',
    );

    // ignore: avoid_print
    print(fail == 0 ? '구간 전환 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });

  // 5단계 29/N — 무대 조명은 스타일마다 다르다. **빠진 스타일이 있으면**
  // 그 곡만 조용히 기본 색으로 나온다 — 화면에서는 눈치채기 어렵다. 그래서 센다.
  test('무대 조명 색', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final missing = [
      for (final g in kSongGenres)
        if (!kStageLights.containsKey(g.$1)) g.$1,
    ];
    check(
      '1) 스타일마다 색이 있다',
      missing.isEmpty,
      '${kSongGenres.length}개 중 빠진 것 ${missing.isEmpty ? '없음' : missing.join(',')}',
    );

    final wrong = [
      for (final e in kStageLights.entries)
        if (e.value.length != 3) '${e.key}(${e.value.length})',
    ];
    check(
      '2) 기둥은 셋씩',
      wrong.isEmpty,
      '조명 기둥 3개 · 어긋난 것 ${wrong.isEmpty ? '없음' : wrong.join(',')}',
    );

    // 3) 스타일끼리 **실제로 달라야** 한다 — 다 같으면 넣으나 마나다
    final sets = {for (final e in kStageLights.entries) e.value.toString()};
    check(
      '3) 서로 다르다',
      sets.length == kStageLights.length,
      '${kStageLights.length}개 중 서로 다른 조합 ${sets.length}개',
    );

    // ── 4) 구간 성격에 따라 무대가 달아오르는가 (Phase 6 · 계획 8) ──
    //
    // 계획이 든 예 그대로다: Drop → 무대 에너지 증가 / Break → 줄어듦 / Build → 차오름.
    // 그림으로 봐서는 「좀 밝네」로 끝난다 — **숫자로 못 박아 둬야** 나중에 조명 값을
    // 만지다가 조용히 뒤집히는 일이 없다.
    {
      final bad = <String>[];
      var checked = 0;
      for (final g in kSongGenres) {
        final p = Project.initial()..setGenre(g.$1);
        final tr = Transport()..bpm = g.$3;
        final sc = ShowScore.from(p, tr);
        double? at(SectionRole r, {double frac = 0.5}) {
          for (var i = 0; i < sc.spans.length; i++) {
            if (roleOf(sc.sectionNames[i]) != r) continue;
            final (st, du) = sc.spans[i];
            return sc.energyAt(st + du * frac);
          }
          return null;
        }

        final drop = at(SectionRole.drop);
        final norm = at(SectionRole.normal);
        final brk = at(SectionRole.breakDown);
        if (drop != null && norm != null && drop <= norm) {
          bad.add('${g.$1} 드롭≤보통');
        }
        if (brk != null && norm != null && brk >= norm) {
          bad.add('${g.$1} 브레이크≥보통');
        }
        // 빌드업은 **구간 안에서** 올라가야 한다
        final bStart = at(SectionRole.build, frac: 0.05);
        final bEnd = at(SectionRole.build, frac: 0.95);
        if (bStart != null && bEnd != null && bEnd <= bStart) {
          bad.add('${g.$1} 빌드업이 안 차오름');
        }
        // 아웃트로는 잦아들어야 한다
        final oStart = at(SectionRole.outro, frac: 0.05);
        final oEnd = at(SectionRole.outro, frac: 0.95);
        if (oStart != null && oEnd != null && oEnd >= oStart) {
          bad.add('${g.$1} 아웃트로가 안 잦아듦');
        }
        checked++;
      }
      check(
        '4) 구간에 따라 무대가 달아오른다',
        bad.isEmpty,
        bad.isEmpty ? '$checked개 스타일' : bad.take(4).join(', '),
      );

      // 값의 범위 — 0~1 을 벗어나면 조명이 꺼지거나 하얗게 탄다
      final p = Project.initial()..setGenre('proghouse');
      final sc = ShowScore.from(p, Transport());
      var out = 0;
      for (var i = 0; i <= 200; i++) {
        final v = sc.energyAt(sc.total * i / 200);
        if (v < 0 || v > 1) out++;
      }
      check('4-b) 0~1 을 안 벗어난다', out == 0, '201지점 중 $out개');
      check(
        '4-c) 곡 밖에서도 안 죽는다',
        sc.energyAt(-5) >= 0 && sc.energyAt(sc.total + 5) >= 0,
        '',
      );
    }

    // ── 5) **백비트 램프가 모든 스타일에서 산다** ──
    //
    // 화면의 「스네어」 램프와 드러머 왼손은 `drumTimes['snare']` 만 봤다.
    // 그런데 백비트를 **클랩으로 치는 장르**가 여럿이다(하우스·재즈·가스펠 등).
    // 그 곡들에서는 램프도 손도 곡 내내 죽어 있었다 — 소리는 나는데 화면은 조용했다.
    // 이제 `show_ops` 가 스네어·클랩·림을 `'backbeat'` 하나로 묶는다.
    {
      final dead = <String>[];
      var checked = 0;
      for (final g in kSongGenres) {
        final p = Project.initial()..setGenre(g.$1);
        final sc = ShowScore.from(p, Transport());
        final bb = sc.drumTimes['backbeat'] ?? const <double>[];
        checked++;
        if (bb.isEmpty) dead.add(g.$1);
      }
      check(
        '5) 백비트 램프가 모든 스타일에서 산다',
        dead.isEmpty,
        dead.isEmpty ? '$checked개 스타일 전부 타격 있음' : '죽은 스타일 ${dead.join(', ')}',
      );

      // 5-b) 합친 목록은 **셋을 다 담고 · 시간순**이어야 한다
      final ph = Project.initial()..setGenre('house');
      final sh = ShowScore.from(ph, Transport());
      final bb = sh.drumTimes['backbeat'] ?? const <double>[];
      final parts = [
        ...?sh.drumTimes['snare'],
        ...?sh.drumTimes['clap'],
        ...?sh.drumTimes['rim'],
      ];
      var sorted = true;
      for (var i = 1; i < bb.length; i++) {
        if (bb[i] < bb[i - 1]) sorted = false;
      }
      check(
        '5-b) 스네어·클랩·림을 합치고 시간순으로 둔다',
        bb.length == parts.length && sorted && bb.isNotEmpty,
        '합친 것 ${bb.length}개 (스네어 ${sh.drumTimes['snare']?.length ?? 0} · '
            '클랩 ${sh.drumTimes['clap']?.length ?? 0} · '
            '림 ${sh.drumTimes['rim']?.length ?? 0}) · 시간순 $sorted',
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '무대 조명 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
