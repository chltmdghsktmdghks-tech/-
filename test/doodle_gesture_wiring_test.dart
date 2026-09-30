// 두들 제스처 → 소리 API 배선 (2026-09-29 (16)) — 순서 화면 악기 고르기, 808 붐, 오픈 하이햇,
// 스웰, 뮤트첩, 롤 크레셴도, 사이드체인 펌핑, 코드 리듬 락.
//   flutter test test/doodle_gesture_wiring_test.dart
//
// 소리 자체(엔진)는 `doodle_sound_hooks_test.dart` 가 잰다. 여기서는 **어떤 손짓이 어떤 API 를
// 어떤 인자로 부르는가**만 가짜 호스트로 본다. 손을 누르고 있는 시간은 실제 시계(`DateTime.now`)로
// 재므로 `runAsync` 로 진짜 시간을 흘린다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/audio_isolate.dart';
import 'package:music_doodle_engine/doodle_gestures.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/tap_rec.dart';
import 'package:music_doodle_engine/ui/doodle_play_view.dart';

/// 부른 소리 API 를 적어 두는 가짜 호스트 — 안 적은 메서드는 그냥 삼킨다.
class _Host implements AudioClient {
  final calls = <(String, List<Object?>, Map<Symbol, Object?>)>[];
  final _stats = StreamController<AudioStats>.broadcast();

  @override
  int aheadFrames = 3072;
  @override
  Stream<AudioStats> get statsStream => _stats.stream;
  @override
  double setSidechainPump(String? genre, {double offDepth = 0}) {
    calls.add(('setSidechainPump', [genre], {#offDepth: offDepth}));
    return 0;
  }

  /// 루프가 돈다고 알린다 — 롤이 격자를 잡으려면 시계가 흘러야 한다.
  void looping([double pos = 0.3]) =>
      _stats.add(AudioStats(looping: true, loopPos: pos, aheadFrames: 1536));

  @override
  dynamic noSuchMethod(Invocation i) {
    calls.add((
      i.memberName.toString().replaceAll(RegExp(r'Symbol\("|"\)'), ''),
      i.positionalArguments,
      i.namedArguments,
    ));
    return null;
  }

  Iterable<(String, List<Object?>, Map<Symbol, Object?>)> of(String n) =>
      calls.where((c) => c.$1 == n);
}

Future<(_Host, dynamic)> _open(
  WidgetTester tester, {
  String? kit,
  String? chordVoice,
  String genre = 'lofi',
  bool start = true,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final host = _Host();
  final p = Project.initial()..setGenre(genre);
  if (kit != null) p.tracks.firstWhere((t) => t.type == 'drum').kit = kit;
  if (chordVoice != null) {
    p.tracks.firstWhere((t) => t.type == 'chord').voice = chordVoice;
  }
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData.dark(),
    home: DoodlePlayView(
      project: p,
      transport: Transport()..mode = 'major',
      host: host as AudioClient,
      initialBars: 4,
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  if (start) {
    await tester.tap(find.text('이 순서로 시작'));
    await tester.pump(const Duration(milliseconds: 100));
  }
  host.looping();
  await tester.pump(const Duration(milliseconds: 50));
  return (host, p);
}

Track _t(Project p, String type) => p.tracks.firstWhere((t) => t.type == type);

/// 마지막 `holdOn` **뒤에** 나간 코드 음 `holdOff` 들 — 손을 뗄 때의 것(닿을 때 앞 화음을 끄는 것은 뺀다).
List<(String, List<Object?>, Map<Symbol, Object?>)> _releases(_Host h) {
  final at = h.calls.lastIndexWhere((c) => c.$1 == 'holdOn');
  return [
    for (final c in h.calls.skip(at + 1))
      if (c.$1 == 'holdOff' && (c.$2[0] as int) >= 9200) c,
  ];
}

/// 실제 시계를 [ms] 만큼 흘리고 시계 타이머도 한 번 돌린다.
Future<void> _hold(WidgetTester tester, int ms) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await tester.pump(const Duration(milliseconds: 60));
}

void main() {
  group('순수 규칙', () {
    test('808 붐 킷 — 전자음 킷만(표본 킷은 붐이 합성 킥으로 바뀌므로 제외)', () {
      expect(doodleBoomKit('k808'), isTrue);
      expect(doodleBoomKit('k909'), isTrue);
      expect(doodleBoomKit('acoustic'), isFalse);
      expect(doodleBoomKit('rock'), isFalse);
    });

    test('오픈 하이햇 — 아래 구역만, 스웰 — 아래에서 닿아야 걸리고 위로 그을수록 큰 값', () {
      expect(hatHoldOpens(0.9), isTrue);
      expect(hatHoldOpens(0.3), isFalse);
      expect(hatHoldOpens(0.55), isFalse, reason: '가운데는 8비트 롤 구역');
      expect(swellStartsAt(0.9), isTrue);
      expect(swellStartsAt(0.4), isFalse);
      expect(swellLevel(800, 800, 600), kSwellStart);
      final mid = swellLevel(800, 700, 600), top = swellLevel(800, 400, 600);
      expect(mid, greaterThan(kSwellStart));
      expect(top, 1.0);
      expect(swellLevel(800, 900, 600), kSwellStart, reason: '내려가도 시작 밑으로는 안 간다');
    });

    test('뮤트첩 — 기타 계열이 짧게, 안 움직이고 뗐을 때만', () {
      expect(isMuteStrum(voice: 'guitar', heldMs: 40, moved: false), isTrue);
      expect(isMuteStrum(voice: 'nylon', heldMs: 40, moved: false), isTrue);
      expect(isMuteStrum(voice: 'guitar', heldMs: 300, moved: false), isFalse);
      expect(isMuteStrum(voice: 'guitar', heldMs: 40, moved: true), isFalse);
      expect(isMuteStrum(voice: 'piano', heldMs: 40, moved: false), isFalse);
    });

    test('롤 크레셴도 — 오른쪽으로 밀수록 오르고, 왼쪽·제자리는 그대로, 3 이 상한', () {
      expect(rollVel(1, 0, 400), 1);
      expect(rollVel(1, -200, 400), 1);
      expect(rollVel(1, 120, 400), 2);
      expect(rollVel(1, 250, 400), 3);
      expect(rollVel(2, 390, 400), 3);
      expect(rollVel(1, 300, 0), 1);
    });

    test('악기 목록 — 요구한 여섯·셋, 지금 값이 목록 밖이면 맨 앞에 끼운다', () {
      expect(kDoodleChordVoices, ['piano', 'pad', 'strings', 'organ', 'brass', 'guitar']);
      expect(kDoodleBassVoices, ['fingerbass', 'jbass', 'bass']);
      expect(doodleChoicesWith(kDoodleChordVoices, 'epiano').first, 'epiano');
      expect(doodleChoicesWith(kDoodleChordVoices, 'pad'), kDoodleChordVoices);
    });
  });

  group('코드 리듬 락(#9)', () {
    List<int> steps(List<TapHit> h) => [for (final x in h) x.step];

    test('첫 마디만 쳐도 나머지 마디가 그 리듬을 반복한다', () {
      final (out, from) = lockChordRhythm(
        [const TapHit(0, 0, 2), const TapHit(0, 8, 2)],
        spb: 16,
        bars: 4,
      );
      expect(steps(out), [0, 8, 16, 24, 32, 40, 48, 56]);
      expect(from[24], 8);
    });

    test('친 마디는 친 대로 — 그 뒤 빈 마디는 「마지막으로 친 마디」를 따른다', () {
      final (out, _) = lockChordRhythm(
        [const TapHit(0, 0, 2), const TapHit(0, 32, 2), const TapHit(0, 40, 2)],
        spb: 16,
        bars: 4,
      );
      // 마디0 = {0}, 마디1 = 마디0 복사 {16}, 마디2 = 친 대로 {32,40}, 마디3 = 마디2 복사 {48,56}
      expect(steps(out), [0, 16, 32, 40, 48, 56]);
    });

    test('첫 마디를 안 쳤으면 그 앞은 채우지 않는다(처음 친 마디 뒤부터)', () {
      final (out, _) = lockChordRhythm([const TapHit(0, 16, 2)], spb: 16, bars: 4);
      expect(steps(out), [16, 32, 48]);
    });

    test('하나도 안 쳤으면 아무것도 안 생긴다', () {
      expect(lockChordRhythm(const [], spb: 16, bars: 4).$1, isEmpty);
    });

    testWidgets('화면: 첫 마디만 친 코드가 4마디 전부에 적히고, 코드 도수는 마디의 진행을 따른다', (tester) async {
      final (_, _) = await _open(tester, start: false);
      final st = tester.state(find.byType(DoodlePlayView)) as dynamic;
      st.debugCommit(DoodleKind.chord, [const TapHit(0, 0, 2), const TapHit(0, 8, 2)]);
      final notes = st.debugChordNotes as List<List<Object?>>;
      expect([for (final n in notes) n[1]], [0, 8, 16, 24, 32, 40, 48, 56]);
    });
  });

  group('순서 화면 악기 고르기', () {
    testWidgets('코드 줄 칩 → 여섯 음색이 뜨고, 고르면 코드 트랙 음색이 바뀌고 소리가 난다', (tester) async {
      final (host, p) = await _open(tester, start: false);
      expect(find.byKey(const ValueKey('order-inst-3')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('order-inst-3')));
      await tester.pumpAndSettle();
      for (final v in kDoodleChordVoices) {
        expect(find.byKey(ValueKey('inst-$v')), findsOneWidget, reason: v);
      }
      await tester.tap(find.byKey(const ValueKey('inst-guitar')));
      await tester.pumpAndSettle();
      expect(_t(p, 'chord').voice, 'guitar');
      expect(host.of('noteOn'), isNotEmpty, reason: '고른 음색을 바로 들려준다');
      expect(host.of('clearSwell'), isNotEmpty, reason: '편성이 바뀌면 스웰을 걷는다');
    });

    testWidgets('베이스 줄 — 핑거/jbass/신스, 드럼 줄 — 킷은 레인마다 따로(킥만 바뀐다)', (tester) async {
      final (_, p) = await _open(tester, start: false);
      await tester.tap(find.byKey(const ValueKey('order-inst-4')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('inst-jbass')));
      await tester.pumpAndSettle();
      expect(_t(p, 'bass').voice, 'jbass');
      await tester.tapAt(const Offset(5, 5)); // 시트 닫기
      await tester.pumpAndSettle();

      final base = _t(p, 'drum').kit;
      await tester.tap(find.byKey(const ValueKey('order-inst-0'))); // 킥 줄
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('inst-k808')));
      await tester.pumpAndSettle();
      expect(_t(p, 'drum').kit, base, reason: '트랙 킷(=스네어·하이햇 기본)은 그대로');
      expect(p.scene.laneKits, {'kick': 'k808'}, reason: '킥 레인만 덮어쓴다');
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('808'), findsOneWidget, reason: '킥 줄만 새 킷 이름(스네어·하이햇은 그대로)');
    });

    testWidgets('고른 음색이 연주(_pressDown)에 쓰인다 — 코드를 기타로 바꾸면 holdOn 이 guitar', (tester) async {
      final (host, p) = await _open(tester, start: false);
      await tester.tap(find.byKey(const ValueKey('order-inst-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('inst-guitar')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('이 순서로 시작'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('CHORD').first);
      await tester.pump(const Duration(milliseconds: 100));
      host.calls.clear();
      final g = await tester.startGesture(const Offset(200, 400));
      await tester.pump();
      expect(host.of('holdOn').map((c) => c.$2[1]).toSet(), {'guitar'});
      await g.up();
      expect(_t(p, 'chord').voice, 'guitar');
    });

    testWidgets('씬에 안 남기고 나가면 원래 음색·킷으로 되돌린다', (tester) async {
      final (_, p) = await _open(tester, start: false, kit: 'acoustic', chordVoice: 'piano');
      final was = _t(p, 'bass').voice;
      await tester.tap(find.byKey(const ValueKey('order-inst-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('inst-strings')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('order-inst-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('inst-k909')));
      await tester.pumpAndSettle();
      expect(_t(p, 'chord').voice, 'strings');
      expect(p.scene.laneKits, {'kick': 'k909'});
      await tester.pumpWidget(const SizedBox()); // 화면을 닫는다 = dispose
      expect(p.scene.laneKits, isEmpty, reason: '레인 킷도 원래대로');
      expect(_t(p, 'chord').voice, 'piano');
      expect(_t(p, 'drum').kit, 'acoustic');
      expect(_t(p, 'bass').voice, was);
    });
  });

  group('808 붐 · 오픈 하이햇', () {
    testWidgets('킥(전자음 킷): 누르면 drumHoldOn, 떼면 누른 만큼 tailSec 로 drumHoldOff', (tester) async {
      final (host, _) = await _open(tester, kit: 'k808');
      final g = await tester.startGesture(const Offset(200, 300));
      await tester.pump();
      expect(host.of('drumHoldOn'), hasLength(1));
      expect(host.of('drumOn').where((c) => c.$2[1] == 'kick'), isEmpty);
      await _hold(tester, 400);
      await g.up();
      await tester.pump();
      final off = host.of('drumHoldOff').last;
      final tail = off.$3[#tailSec] as double;
      expect(tail, inInclusiveRange(0.35, 0.9), reason: '누른 시간(≈0.4s)이 그대로 꼬리');
    });

    testWidgets('킥(표본 킷): 예전처럼 drumOn 한 방(붐 없음)', (tester) async {
      final (host, _) = await _open(tester, kit: 'acoustic');
      final g = await tester.startGesture(const Offset(200, 300));
      await tester.pump();
      expect(host.of('drumHoldOn'), isEmpty);
      expect(host.of('drumOn').where((c) => c.$2[1] == 'kick'), hasLength(1));
      await g.up();
    });

    testWidgets('레인별 킷: 킥만 808 이면 킥은 붐(k808), 하이햇은 기본 킷 그대로 친다', (tester) async {
      final (host, p) = await _open(tester, kit: 'acoustic');
      p.scene.laneKits['kick'] = 'k808';
      var g = await tester.startGesture(const Offset(200, 300));
      await tester.pump();
      expect(host.of('drumHoldOn').map((c) => c.$2[1]).toSet(), {'k808'});
      await g.up();
      await tester.tap(find.text('HI-HAT').first);
      await tester.pump(const Duration(milliseconds: 100));
      host.calls.clear();
      g = await tester.startGesture(const Offset(200, 300));
      await tester.pump();
      expect(host.of('drumOn').map((c) => c.$2[0]).toSet(), {'acoustic'});
      await g.up();
    });

    testWidgets('하이햇: 톡 = 닫힌 한 방, 아래에서 꾹 = hatopen, 위에서 꾹 = 롤(오픈 아님)', (tester) async {
      final (host, _) = await _open(tester);
      await tester.tap(find.text('HI-HAT').first);
      await tester.pump(const Duration(milliseconds: 100));
      host.looping();
      host.calls.clear();

      // 톡
      var g = await tester.startGesture(const Offset(200, 780));
      await tester.pump();
      await g.up();
      await _hold(tester, 250);
      expect(host.of('drumOn').where((c) => c.$2[1] == 'hat'), hasLength(1));
      bool opened() => host
          .of('drumBatch')
          .any((c) => (c.$2[0] as List).any((h) => (h as List)[1] == 'hatopen'));
      expect(opened(), isFalse, reason: '짧게 떼면 닫힌 하이햇');

      // 아래에서 꾹
      g = await tester.startGesture(const Offset(200, 780));
      await tester.pump();
      await _hold(tester, 320);
      await _hold(tester, 100);
      expect(opened(), isTrue, reason: '아래에서 0.18초 넘게 누르면 오픈');
      await g.up();

      // 위에서 꾹 — 롤이지 오픈이 아니다
      host.calls.clear();
      g = await tester.startGesture(const Offset(200, 250));
      await tester.pump();
      await _hold(tester, 320);
      await _hold(tester, 100);
      expect(opened(), isFalse);
      expect(
        host
            .of('drumBatch')
            .expand((c) => c.$2[0] as List)
            .where((h) => (h as List)[1] == 'hat'),
        isNotEmpty,
        reason: '위에서 꾹은 16비트 롤',
      );
      await g.up();
    });

    testWidgets('하이햇 8비트 vs 16비트: 위 = 촘촘(16분), 가운데 = 성긴(8분), 격자에 정렬', (tester) async {
      final (host, _) = await _open(tester);
      await tester.tap(find.text('HI-HAT').first);
      await tester.pump(const Duration(milliseconds: 100));

      // 손가락을 [y] 에 두고 [ms] 동안 눌러 롤이 낸 닫힌 하이햇 수를 센다.
      Future<int> rollHits(double y) async {
        host.looping();
        host.calls.clear();
        final g = await tester.startGesture(Offset(200, y));
        await tester.pump();
        for (var i = 0; i < 12; i++) {
          await _hold(tester, 150);
        }
        await g.up();
        return host
            .of('drumBatch')
            .expand((c) => c.$2[0] as List)
            .where((h) => (h as List)[1] == 'hat')
            .length;
      }

      final n16 = await rollHits(150); // 위 (frac ≈ 0.17)
      final n8 = await rollHits(500); // 가운데 (frac ≈ 0.55)
      expect(n16, greaterThan(0));
      expect(n8, greaterThan(0));
      expect(n16, greaterThan(n8 * 1.5),
          reason: '16비트는 8비트의 약 2배 촘촘 (16비트 $n16 vs 8비트 $n8)');
      expect(n16, lessThan(n8 * 2.6), reason: '너무 촘촘해도 안 된다(32분 아님)');

      // 가운데 구역을 꾹 눌러도 오픈이 아니다(예전엔 0.6 아래는 무조건 오픈이었다).
      host.looping();
      host.calls.clear();
      final g = await tester.startGesture(const Offset(200, 500));
      await tester.pump();
      await _hold(tester, 320);
      await _hold(tester, 150);
      expect(
        host.of('drumBatch').any(
          (c) => (c.$2[0] as List).any((h) => (h as List)[1] == 'hatopen'),
        ),
        isFalse,
        reason: '가운데는 8비트 롤',
      );
      await g.up();
    });

    testWidgets('스네어 롤: 오른쪽으로 밀면 롤 세기가 오른다(크레셴도)', (tester) async {
      final (host, _) = await _open(tester);
      await tester.tap(find.text('SNARE').first);
      await tester.pump(const Duration(milliseconds: 100));
      host.looping();
      host.calls.clear();
      final g = await tester.startGesture(const Offset(20, 450));
      await tester.pump();
      await _hold(tester, 330);
      await _hold(tester, 150);
      await g.moveTo(const Offset(390, 450));
      await _hold(tester, 150);
      await _hold(tester, 150);
      final vels = [
        for (final c in host.of('drumBatch'))
          for (final h in c.$2[0] as List)
            if ((h as List)[1] == 'snare') h[2] as int,
      ];
      await g.up();
      expect(vels, isNotEmpty);
      expect(vels.reduce((a, b) => a > b ? a : b), greaterThan(vels.first),
          reason: '밀기 전 $vels');
    });
  });

  group('코드: 스웰 · 뮤트첩', () {
    testWidgets('패드: 아래에서 닿으면 setSwell 시작 → 위로 그을수록 오르고 → 떼면 1 로 복귀(코드 버스로 낸다)',
        (tester) async {
      final (host, _) = await _open(tester, chordVoice: 'pad');
      await tester.tap(find.text('CHORD').first);
      await tester.pump(const Duration(milliseconds: 100));
      host.calls.clear();
      final g = await tester.startGesture(const Offset(200, 780));
      await tester.pump();
      expect(host.of('setSwell').first.$2, ['chord', kSwellStart]);
      expect(host.of('holdOn').every((c) => c.$3[#part] == 1), isTrue,
          reason: '스웰은 코드 버스에 걸리므로 코드 버스(kPartChord)로 낸다');
      await g.moveBy(const Offset(0, -200));
      await tester.pump();
      final lv = host.of('setSwell').last.$2[1] as double;
      expect(lv, greaterThan(kSwellStart));
      await g.moveBy(const Offset(0, -300));
      await tester.pump();
      expect(host.of('setSwell').last.$2[1], 1.0);
      await g.up();
      await tester.pump();
      expect(host.of('setSwell').last.$2[1], 1.0);
      expect(host.of('setSwell').last.$3[#smoothSec], 0.5);
    });

    testWidgets('패드라도 위쪽에서 닿으면 스웰 없음, 피아노는 아래여도 없음', (tester) async {
      final (host, _) = await _open(tester, chordVoice: 'pad');
      await tester.tap(find.text('CHORD').first);
      await tester.pump(const Duration(milliseconds: 100));
      host.calls.clear();
      var g = await tester.startGesture(const Offset(200, 300));
      await tester.pump();
      await g.moveBy(const Offset(0, -80));
      await g.up();
      expect(host.of('setSwell'), isEmpty);
    });

    testWidgets('피아노: 아래에서 그어도 스웰 없음(라이브 버스 그대로)', (tester) async {
      final (host, _) = await _open(tester, chordVoice: 'piano');
      await tester.tap(find.text('CHORD').first);
      await tester.pump(const Duration(milliseconds: 100));
      host.calls.clear();
      final g = await tester.startGesture(const Offset(200, 780));
      await tester.pump();
      await g.moveBy(const Offset(0, -200));
      await g.up();
      expect(host.of('setSwell'), isEmpty);
      expect(host.of('holdOn').every((c) => c.$3[#part] == -2), isTrue);
    });

    testWidgets('기타: 아주 짧게 떼면 뮤트(꼬리 바로 자름), 길게 잡았다 떼면 그대로 울림', (tester) async {
      final (host, _) = await _open(tester, chordVoice: 'guitar');
      await tester.tap(find.text('CHORD').first);
      await tester.pump(const Duration(milliseconds: 100));
      host.calls.clear();
      var g = await tester.startGesture(const Offset(200, 400));
      await g.up(); // 프레임을 안 그리고 바로 뗀다 — 실제 시계로 90ms 안
      await tester.pump();
      final mute = _releases(host);
      expect(mute, isNotEmpty);
      expect(mute.every((c) => c.$3[#tailSec] == kMuteTailSec), isTrue);

      host.calls.clear();
      g = await tester.startGesture(const Offset(200, 400));
      await tester.pump();
      await _hold(tester, 300);
      await g.up();
      await tester.pump();
      final ring = _releases(host);
      expect(ring.every((c) => c.$3[#tailSec] == 0), isTrue, reason: '길게 잡으면 뮤트 아님');
    });

    testWidgets('기타라도 톡이 아닌 칸은 세기 2 그대로 (뮤트 칸만 여리게 적힌다)', (tester) async {
      final (_, _) = await _open(tester, chordVoice: 'guitar', start: false);
      final st = tester.state(find.byType(DoodlePlayView)) as dynamic;
      // 판을 못 돌리니 _staccatoAt 를 직접 못 채운다 — 대신 rows 규칙: 톡이 아닌 칸은 세기 2.
      st.debugCommit(DoodleKind.chord, [const TapHit(0, 0, 4)]);
      final notes = st.debugChordNotes as List<List<Object?>>;
      expect(notes.first[3], 2);
    });
  });

  group('사이드체인 펌핑', () {
    testWidgets('두들 진입 때 setSidechainPump(장르)를 건다 — 하우스', (tester) async {
      final (host, _) = await _open(tester, genre: 'house', start: false);
      expect(host.of('setSidechainPump').first.$2, ['house']);
    });

    testWidgets('되감기·판 갱신(setLoop) 뒤마다 다시 건다(대상 리셋 방지)', (tester) async {
      final (host, _) = await _open(tester, genre: 'house');
      // 시작(_startStages → _rewindLoop → refreshLoop) 뒤 마지막 setLoop 다음에 펌핑이 있어야 한다.
      final names = [for (final c in host.calls) c.$1];
      final lastLoop = names.lastIndexOf('setLoop');
      expect(lastLoop, isNonNegative);
      expect(names.sublist(lastLoop).contains('setSidechainPump'), isTrue,
          reason: 'setLoop 이후에 펌핑 대상을 다시 걸어야 한다');
    });
  });
}
