// 두들플레이 연주감 · 한손 오탐 줄이기 (2026-09-30) —
//   flutter test test/doodle_feel_test.dart
//
//  A. 악기 × 세기 햅틱 분기      B. 물결·방향 그림이 뜨는가(상태로 잰다)
//  C. 표본 미리 읽기 배선         D. 첫 안내 카드(한 번 보고 끄면 다시 안 뜸)
//  E. 데드존 · 히스테리시스 · 최소 이동거리 (순수 규칙 + 화면 배선)
//
// 임계값은 전부 `doodle_gestures.dart` 의 상수라 실기기에서 바꾸면 이 시험도 같은 상수를 본다.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/audio_isolate.dart';
import 'package:music_doodle_engine/doodle_gestures.dart';
import 'package:music_doodle_engine/doodle_hints.dart';
import 'package:music_doodle_engine/drums.dart' show DRUM_KITS;
import 'package:music_doodle_engine/engine.dart';
import 'package:music_doodle_engine/project.dart';
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
  double setSidechainPump(String? genre, {double offDepth = 0}) => 0;

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

/// 햅틱 호출을 적는다 — `HapticFeedback.xxx` 는 플랫폼 채널로 나간다.
List<String> _haptics(WidgetTester tester) {
  final log = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        log.add((call.arguments as String).replaceFirst('HapticFeedbackType.', ''));
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return log;
}

Future<_Host?> _open(
  WidgetTester tester, {
  bool withHost = false,
  String? kit,
  String? chordVoice,
  String? tab,
}) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final host = withHost ? _Host() : null;
  final p = Project.initial();
  if (kit != null) p.tracks.firstWhere((t) => t.type == 'drum').kit = kit;
  if (chordVoice != null) {
    p.tracks.firstWhere((t) => t.type == 'chord').voice = chordVoice;
  }
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: DoodlePlayView(
        project: p,
        transport: Transport()..mode = 'major',
        host: host as AudioClient?,
        initialBars: 4,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.text('이 순서로 시작'));
  await tester.pump(const Duration(milliseconds: 100));
  host?.looping();
  await tester.pump(const Duration(milliseconds: 50));
  if (tab != null) {
    await tester.tap(find.text(tab).first);
    await tester.pump(const Duration(milliseconds: 100));
  }
  return host;
}

/// 치는 자리(화면에서 위아래 안내줄을 뺀 전부) — 분수 좌표를 화면 좌표로.
Offset _at(WidgetTester tester, double fx, double fy) {
  final r = tester.getRect(find.byKey(const ValueKey('doodle-fx')));
  return r.topLeft + Offset(r.width * fx, r.height * fy);
}

Future<void> _tap(WidgetTester tester, Offset at) async {
  final g = await tester.startGesture(at);
  await tester.pump();
  await g.up();
  await tester.pump();
}

dynamic _state(WidgetTester tester) => tester.state(find.byType(DoodlePlayView));

void main() {
  setUp(() {
    DoodleHints.debugReset();
    DoodleHints.memoryOnly = true; // 시험은 파일을 안 쓴다
  });

  group('A. 햅틱 — 악기 × 세기 (순수 규칙)', () {
    test('킥은 묵직: 고스트만 medium, 나머지 heavy', () {
      expect(doodleHaptic('kick', 1), DoodleHaptic.medium);
      expect(doodleHaptic('kick', 2), DoodleHaptic.heavy);
      expect(doodleHaptic('kick', 3), DoodleHaptic.heavy);
    });
    test('스네어·베이스는 중간이 기준 — 여리게 light · 보통 medium · 세게 heavy', () {
      for (final i in ['snare', 'bass']) {
        expect(doodleHaptic(i, 1), DoodleHaptic.light, reason: i);
        expect(doodleHaptic(i, 2), DoodleHaptic.medium, reason: i);
        expect(doodleHaptic(i, 3), DoodleHaptic.heavy, reason: i);
      }
    });
    test('코드는 세기가 늘 2 라 medium', () {
      expect(doodleHaptic('chord', 2), DoodleHaptic.medium);
    });
    test('하이햇은 짧고 가볍게 — 여린 것은 똑(tick), 세게 쳐도 light 를 안 넘는다', () {
      expect(doodleHaptic('hat', 1), DoodleHaptic.tick);
      expect(doodleHaptic('hat', 2), DoodleHaptic.light);
      expect(doodleHaptic('hat', 3), DoodleHaptic.light);
    });
    test('같은 세기면 킥 ≥ 스네어 ≥ 하이햇 (무게 순서), 같은 악기면 세기 따라 안 줄어든다', () {
      int w(DoodleHaptic h) => 3 - h.index; // tick 0 … heavy 3
      for (var v = 1; v <= 3; v++) {
        expect(w(doodleHaptic('kick', v)), greaterThanOrEqualTo(w(doodleHaptic('snare', v))));
        expect(w(doodleHaptic('snare', v)), greaterThanOrEqualTo(w(doodleHaptic('hat', v))));
      }
      for (final i in ['kick', 'snare', 'hat', 'bass']) {
        for (var v = 1; v < 3; v++) {
          expect(w(doodleHaptic(i, v + 1)), greaterThanOrEqualTo(w(doodleHaptic(i, v))), reason: i);
        }
      }
    });
    test('모르는 악기는 medium 이 기준', () {
      expect(doodleHaptic('???', 2), DoodleHaptic.medium);
    });
  });

  group('A. 햅틱 — 화면 배선 (친 악기·세기가 진동으로 나간다)', () {
    testWidgets('킥: 정타 오른쪽 = heavy, 아래(고스트) = medium', (tester) async {
      final log = _haptics(tester);
      await _open(tester);
      await _tap(tester, _at(tester, 0.85, 0.3));
      expect(log.last, 'heavyImpact');
      await _tap(tester, _at(tester, 0.85, 0.9));
      expect(log.last, 'mediumImpact', reason: '고스트 킥은 한 단계 여리다');
    });

    testWidgets('스네어: 한가운데 = heavy, 가장자리 = light', (tester) async {
      final log = _haptics(tester);
      await _open(tester, tab: 'SNARE');
      await _tap(tester, _at(tester, 0.5, 0.5));
      expect(log.last, 'heavyImpact');
      await _tap(tester, _at(tester, 0.02, 0.98));
      expect(log.last, 'lightImpact');
    });

    testWidgets('하이햇: 오른쪽 = light, 왼쪽(여리게) = selectionClick(똑)', (tester) async {
      final log = _haptics(tester);
      await _open(tester, tab: 'HI-HAT');
      await _tap(tester, _at(tester, 0.9, 0.3));
      expect(log.last, 'lightImpact');
      await _tap(tester, _at(tester, 0.05, 0.3));
      expect(log.last, 'selectionClick');
    });

    testWidgets('코드: 어디를 쳐도 medium', (tester) async {
      final log = _haptics(tester);
      await _open(tester, tab: 'CHORD');
      await _tap(tester, _at(tester, 0.2, 0.3));
      expect(log.last, 'mediumImpact');
    });

    testWidgets('막힌 둘째 손가락(코드는 한 손가락만)은 heavy 로 알린다 — 무반응 금지', (tester) async {
      final log = _haptics(tester);
      await _open(tester, tab: 'CHORD');
      final a = await tester.startGesture(_at(tester, 0.3, 0.3));
      await tester.pump();
      log.clear();
      final b = await tester.startGesture(_at(tester, 0.7, 0.7));
      await tester.pump();
      expect(log, ['heavyImpact']);
      await b.up();
      await a.up();
    });
  });

  group('B. 시각 타격 피드백', () {
    testWidgets('악기(레인)마다 물결이 따로 남는다 + 손을 뗀 뒤 물결이 다 사그라들면 프레임이 멈춘다', (tester) async {
      await _open(tester);
      await _tap(tester, _at(tester, 0.5, 0.3));
      expect(_state(tester).debugRippleLanes, ['kick']);
      await tester.tap(find.text('HI-HAT').first);
      await tester.pump(const Duration(milliseconds: 100));
      await _tap(tester, _at(tester, 0.5, 0.3));
      expect(_state(tester).debugRippleLanes, isNot(contains('kick')), reason: '단계가 바뀌면 물결을 비운다');
      // 실제 시계로 물결 수명(560ms)을 넘긴다 → 그림 시계가 멈춰야 한다(배터리).
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 700)));
      // 탭 전환의 잉크 번짐(위젯 시계 1초 남짓)이 끝나도록 흘린 뒤, 마지막 한 프레임은 「다 사라진
      // 모습」을 그리고 시계를 멈춘다 → 그 뒤 프레임은 더 없다.
      await tester.pump(const Duration(seconds: 2));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(_state(tester).debugLiveRipples, 0);
      expect(tester.binding.hasScheduledFrame, isFalse, reason: '놀 때는 프레임을 안 돌린다');
    });

    testWidgets('코드 탭: 방향(−1·0·+1)과 색이 구역 번쩍임으로 남는다', (tester) async {
      await _open(tester, tab: 'CHORD');
      await _tap(tester, _at(tester, 0.05, 0.2)); // 왼쪽·위
      var f = _state(tester).debugFlash as (int, int);
      expect(f, (-1, 1));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await _tap(tester, _at(tester, 0.95, 0.9)); // 오른쪽·아래
      f = _state(tester).debugFlash as (int, int);
      expect(f, (1, 0));
      expect(find.byKey(const ValueKey('doodle-chord-zones')), findsOneWidget);
      // 화살표 글자(◀ ▶)는 라벨 하나씩만 — 그림은 Text 가 아니다.
      expect(find.textContaining('◀'), findsOneWidget);
      expect(find.textContaining('▶'), findsOneWidget);
    });

    testWidgets('꾹 눌러 스웰: 손가락이 살아 있는 동안은 프레임이 돈다', (tester) async {
      await _open(tester, tab: 'CHORD', chordVoice: 'pad');
      final g = await tester.startGesture(_at(tester, 0.5, 0.9));
      await tester.pump();
      await g.moveBy(const Offset(0, -120));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.hasScheduledFrame, isTrue);
      await g.up();
    });
  });

  group('C. 표본 미리 읽기 (즉응성)', () {
    testWidgets('진입 시점에 이 곡이 쓸 악기·드럼 표본 이름을 오디오 쪽에 보낸다', (tester) async {
      final h = (await _open(tester, withHost: true, kit: 'acoustic'))!;
      final c = h.of('preloadSamples');
      expect(c, isNotEmpty);
      final voices = c.expand((x) => x.$3[#voices] as List).toSet();
      final p = (tester.widget(find.byType(DoodlePlayView)) as DoodlePlayView).project;
      expect(
        voices,
        containsAll([
          p.tracks.firstWhere((t) => t.type == 'bass').voice,
          p.tracks.firstWhere((t) => t.type == 'chord').voice,
        ]),
      );
      final pieces = c.expand((x) => x.$3[#drumPieces] as List).toSet();
      final set = DRUM_KITS['acoustic']!.sampleSet;
      expect(pieces, containsAll([('kick', set), ('snare', set), ('hatClosed', set), ('hatOpen', set)]));
    });

    testWidgets('전자음 킷은 드럼 표본을 안 읽는다(합성이 정체성)', (tester) async {
      final h = (await _open(tester, withHost: true, kit: 'k808'))!;
      final pieces = h.of('preloadSamples').expand((x) => x.$3[#drumPieces] as List);
      expect(pieces, isEmpty);
    });

    test('오디오 쪽이 미리읽기 메시지를 받는다 — 빈 것·모르는 이름·망가진 것 모두 죽지 않는다', () {
      // 규약: [30, List<String> voices, List<[piece, set]>] (`_cPreload`).
      final engine = Engine();
      final loop = LoopState();
      final saw = <String>[];
      final keep = debugPrint;
      debugPrint = (String? s, {int? wrapWidth}) => saw.add(s ?? '');
      addTearDown(() => debugPrint = keep);
      int send(List m) => handleAudioMessage(m, engine, loop, 3072, () {});
      expect(send([30, <String>[], <List<String>>[]]), 3072);
      expect(
        send([
          30,
          ['없는악기'],
          [
            ['없는조각', '없는세트'],
          ],
        ]),
        3072,
      );
      expect(send([30]), 3072, reason: '칸이 모자란 메시지는 그 한 통만 버린다');
      expect(send([30, 'x', 3]), 3072);
    });
  });

  group('D. 첫 안내 카드', () {
    testWidgets('처음엔 뜨고, ? 로 닫으면 그 악기는 다시 안 뜬다(다른 악기는 뜸)', (tester) async {
      await _open(tester);
      expect(find.byKey(const ValueKey('doodle-coach')), findsOneWidget);
      expect(find.textContaining('KICK 손짓'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('doodle-coach-toggle')));
      await tester.pump();
      expect(find.byKey(const ValueKey('doodle-coach')), findsNothing);
      expect(DoodleHints.seen('kick'), isTrue);
      // 다른 악기는 아직 처음
      await tester.tap(find.text('SNARE').first);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('doodle-coach')), findsOneWidget);
      // 킥으로 돌아와도 안 뜬다
      await tester.tap(find.text('KICK').first);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('doodle-coach')), findsNothing);
      // ? 를 다시 누르면 언제든 다시 볼 수 있다
      await tester.tap(find.byKey(const ValueKey('doodle-coach-toggle')));
      await tester.pump();
      expect(find.byKey(const ValueKey('doodle-coach')), findsOneWidget);
    });

    testWidgets('화면을 새로 열어도(앱 재진입) 기억한다', (tester) async {
      DoodleHints.markSeen('kick');
      await _open(tester);
      expect(find.byKey(const ValueKey('doodle-coach')), findsNothing);
    });

    testWidgets('카드 위를 쳐도 소리가 난다 — 카드가 치는 자리를 가로채지 않는다', (tester) async {
      final h = (await _open(tester, withHost: true))!;
      final card = tester.getRect(find.byKey(const ValueKey('doodle-coach')));
      h.calls.clear();
      await _tap(tester, card.center);
      expect(h.of('drumOn'), isNotEmpty, reason: '카드 밑이라고 무반응이면 안 된다');
      expect(find.byKey(const ValueKey('doodle-coach')), findsOneWidget, reason: '치기만 해서 닫히진 않는다');
    });

    test('안내 문구 — 악기마다 있고, 그 음색에만 있는 손짓은 있을 때만 덧붙는다', () {
      for (final k in kDoodleCoachKeys) {
        expect(doodleCoachTips(k).length, greaterThanOrEqualTo(2), reason: k);
      }
      expect(doodleCoachTips('chord').length + 2, doodleCoachTips('chord', swell: true, mute: true).length);
      expect(doodleCoachTips('kick').length + 1, doodleCoachTips('kick', boom: true).length);
      expect(doodleCoachTips('없는악기'), isEmpty);
    });

    test('기억은 파일에 남는다(재시작해도 유지) — 못 쓰는 환경은 메모리로만', () async {
      final dir = Directory.systemTemp.createTempSync('doodle_hints_');
      addTearDown(() => dir.deleteSync(recursive: true));
      DoodleHints.memoryOnly = false;
      DoodleHints.overrideDir = dir;
      await DoodleHints.load();
      expect(DoodleHints.seen('chord'), isFalse);
      DoodleHints.markSeen('chord');
      await Future<void>.delayed(const Duration(milliseconds: 100)); // 파일 쓰기가 뒤에서 돈다
      DoodleHints.debugReset(); // 앱을 껐다 켠 것과 같다
      DoodleHints.overrideDir = dir;
      await DoodleHints.load();
      expect(DoodleHints.seen('chord'), isTrue);
      expect(DoodleHints.seen('kick'), isFalse);
    });
  });

  group('E. 히스테리시스 · 데드존 (순수 규칙)', () {
    test('stickyBand — 직전이 없으면 원래 구역, 경계 slop 안에서는 직전에 머문다', () {
      const e = [1 / 3, 2 / 3];
      expect(stickyBand(0.30, e), 0);
      expect(stickyBand(0.34, e), 1);
      expect(stickyBand(0.34, e, prev: 0, slop: 0.035), 0, reason: '경계를 막 넘었을 뿐');
      expect(stickyBand(0.37, e, prev: 0, slop: 0.035), 1, reason: '충분히 넘으면 바뀐다');
      expect(stickyBand(0.32, e, prev: 1, slop: 0.035), 1, reason: '내려올 때도 같은 되돌림');
      expect(stickyBand(0.29, e, prev: 1, slop: 0.035), 0);
      expect(stickyBand(0.90, e, prev: 0, slop: 0.035), 2, reason: '두 구역 이상 건넌 건 의도한 이동');
      expect(stickyBand(0.34, e, prev: 0, slop: 0), 1, reason: 'slop 0 이면 옛 동작');
    });

    test('세기 경계에서 손이 흔들려도 안 튄다 — 16분 하이햇 연타 시나리오', () {
      final b = StickyBand(const [1 / 3, 2 / 3]);
      const w = 400.0;
      final slop = kBandSlopPx / w;
      // 1/3 경계(=133px) 근처에서 ±5px 떠는 손: 130 → 137 → 131 → 139 → 132 → 136
      final xs = [130.0, 137, 131, 139, 132, 136];
      final got = <int>[];
      var t = 0;
      for (final x in xs) {
        got.add(b.read(x / w, t, slop: slop));
        t += 125; // 120BPM 16분
      }
      expect(got, everyElement(0), reason: '경계 ±5px 흔들림은 한 구역으로 굳는다: $got');
      // 옛 방식(기억 없음)은 오락가락했다
      final old = [for (final x in xs) stickyBand(x / w, const [1 / 3, 2 / 3])];
      expect(old.toSet().length, 2, reason: '전(前) 동작 재현: $old');
      // 진짜로 옮겨 가면(경계 + slop 이상) 바뀐다
      expect(b.read(160 / w, t, slop: slop), 1);
    });

    test('기억은 kStickyMs 를 넘기면 잊는다 — 쉬었다 치면 의도한 위치로', () {
      final b = StickyBand(const [1 / 3]);
      expect(b.read(0.30, 0, slop: 0.04), 0);
      expect(b.read(0.34, kStickyMs, slop: 0.04), 0, reason: '시간 안이라 머문다');
      expect(b.read(0.34, kStickyMs * 3, slop: 0.04), 1, reason: '오래 쉬었으니 새로 판정');
      b.reset();
      expect(b.read(0.34, kStickyMs * 3 + 1, slop: 0.04), 1);
    });

    test('롤 크레셴도 단계 — 폭의 1/4 선에서 떨어도 안 튀고, 충분히 밀거나 되돌려야 바뀐다', () {
      const w = 400.0; // 1/4 = 100px
      expect(rollBumpSticky(99, w, 0, slop: kBandSlopPx), 0);
      expect(rollBumpSticky(105, w, 0, slop: kBandSlopPx), 0, reason: '막 넘음 → 유지');
      expect(rollBumpSticky(120, w, 0, slop: kBandSlopPx), 1);
      expect(rollBumpSticky(92, w, 1, slop: kBandSlopPx), 1, reason: '막 내려옴 → 유지');
      expect(rollBumpSticky(80, w, 1, slop: kBandSlopPx), 0);
      expect(rollBumpSticky(-50, w, 0, slop: kBandSlopPx), 0, reason: '왼쪽은 기본 세기 밑으로 안 간다');
      expect(rollBumpSticky(999, w, 2, slop: kBandSlopPx), 2, reason: '상한 2');
      expect(rollBumpSticky(50, 0, 0), 0);
      expect(rollVelOfBump(3, 2), 3);
      expect(rollVelOfBump(1, 2), 3);
      expect(rollVelOfBump(1, 0), 1);
    });

    test('하이햇 3구역 — 위 16비트 · 가운데 8비트 · 아래 오픈, 경계에서 흔들려도 안 튄다', () {
      const slop = 14 / 600; // 화면 높이 600px
      // 상수 관계: 위 < 가운데 < 아래, 8비트 구역이 손가락 하나 너비(≈14%)보다 넉넉히 넓다
      expect(kHat16Zone, lessThan(kOpenHatZone));
      expect(kOpenHatZone - kHat16Zone, greaterThan(0.25));
      // 자리 → 구역 (기억 없음)
      expect(hatBandSticky(0.10), kHatBand16);
      expect(hatBandSticky(0.55), kHatBand8);
      expect(hatBandSticky(0.90), kHatBandOpen);
      expect(hatRollUnit(kHatBand16), 1, reason: '16비트 = 매 16분 칸');
      expect(hatRollUnit(kHatBand8), 2, reason: '8비트 = 두 칸마다');
      // 16 ↔ 8 경계(kHat16Zone) 흔들림
      expect(hatBandSticky(kHat16Zone + 0.01, prev: kHatBand16, slop: slop), kHatBand16);
      expect(hatBandSticky(kHat16Zone + 0.06, prev: kHatBand16, slop: slop), kHatBand8);
      expect(hatBandSticky(kHat16Zone - 0.01, prev: kHatBand8, slop: slop), kHatBand8);
      expect(hatBandSticky(kHat16Zone - 0.06, prev: kHatBand8, slop: slop), kHatBand16);
      // 8 ↔ 오픈 경계 흔들림
      expect(hatBandSticky(kOpenHatZone + 0.01, prev: kHatBand8, slop: slop), kHatBand8);
      expect(hatBandSticky(kOpenHatZone + 0.06, prev: kHatBand8, slop: slop), kHatBandOpen);
      // 오픈 판정 — 처음 닿은 자리를 기억(롤하려다 살짝 내려와도 오픈 안 됨)
      expect(hatHoldOpensSticky(downFrac: 0.5, frac: kOpenHatZone + 0.01, slop: slop), isFalse);
      expect(hatHoldOpensSticky(downFrac: 0.5, frac: 0.85, slop: slop), isTrue);
      expect(hatHoldOpensSticky(downFrac: 0.85, frac: kOpenHatZone - 0.01, slop: slop), isTrue);
      expect(hatHoldOpensSticky(downFrac: 0.85, frac: 0.50, slop: slop), isFalse);
      // 위(16비트)에서 시작해 가운데를 스쳐도 오픈이 아니다
      expect(hatHoldOpensSticky(downFrac: 0.2, frac: 0.55, slop: slop), isFalse);
      // 기억 없는 옛 함수와 slop 0 은 같다
      expect(hatHoldOpensSticky(downFrac: 0.4, frac: 0.61), hatHoldOpens(0.61));
      expect(hatHoldOpensSticky(downFrac: 0.4, frac: 0.80), hatHoldOpens(0.80));
    });

    test('스웰 데드존 — 처음 kSwellDeadPx 는 그은 게 아니다, 끝(가득)은 그대로', () {
      expect(swellLevel(800, 795, 600, deadPx: kSwellDeadPx), kSwellStart, reason: '5px 흐름은 무시');
      expect(swellLevel(800, 790, 600, deadPx: kSwellDeadPx), kSwellStart);
      expect(swellLevel(800, 700, 600, deadPx: kSwellDeadPx), greaterThan(kSwellStart));
      expect(swellLevel(800, 700, 600, deadPx: kSwellDeadPx), lessThan(swellLevel(800, 700, 600)));
      expect(swellLevel(800, 300, 600, deadPx: kSwellDeadPx), 1.0);
      expect(swellLevel(800, 795, 600), greaterThan(kSwellStart), reason: '기본값(0)은 옛 동작 그대로');
    });

    test('코드 색 경계 — 엄지가 닿는 가운데 쪽으로 내려온 kChordColorSplit', () {
      expect(kChordColorSplit, greaterThan(0.5));
      expect(kChordColorSplit, lessThan(0.7), reason: '너무 내리면 「담백」 구역이 좁아진다');
      const e = [kChordColorSplit];
      expect(chordColorOfBand(stickyBand(0.52, e)), 1, reason: '옛 정중앙 아래여도 이제 「위」');
      expect(chordColorOfBand(stickyBand(0.60, e)), 0);
      expect(chordDirOfBand(0), -1);
      expect(chordDirOfBand(1), 0);
      expect(chordDirOfBand(2), 1);
    });

    test('톡/슬라이드 임계 — 엄지가 구르는 만큼은 움직인 게 아니다', () {
      expect(kTapSlopPx, greaterThan(8), reason: '옛 8px 는 엄지 살에 너무 좁았다');
      expect(kTapSlopPx, lessThanOrEqualTo(18), reason: 'Flutter 터치 슬롭(18px) 이하');
      expect(kSlideSlopPx, greaterThanOrEqualTo(kTapSlopPx));
      expect(kBandSlopPx, greaterThan(0));
    });
  });

  group('E. 화면 배선 — 오탐이 실제로 줄었는가', () {
    testWidgets('하이햇 세기 경계: 여리게(왼쪽)에서 경계를 살짝 넘겨 친 다음 탭도 여리게로 굳는다', (tester) async {
      final h = (await _open(tester, withHost: true, tab: 'HI-HAT'))!;
      final r = tester.getRect(find.byKey(const ValueKey('doodle-fx')));
      h.calls.clear();
      Offset px(double dx) => Offset(r.left + dx, r.top + r.height * 0.3);
      final b = r.width / 3; // 1/3 경계
      await _tap(tester, px(b - 20)); // 여리게 1
      await _tap(tester, px(b + 6)); // 경계를 막 넘음 → 여전히 1
      await _tap(tester, px(b - 3)); // 다시 안쪽 → 1
      await _tap(tester, px(b + 8)); // → 1
      final vels = [for (final c in h.of('drumOn')) c.$2[2]];
      expect(vels, [1, 1, 1, 1], reason: '경계 흔들림에 세기가 안 튄다');
      // 충분히 넘어가면 보통(2)
      await _tap(tester, px(b + 40));
      expect(h.of('drumOn').last.$2[2], 2);
    });

    testWidgets('기억 없는 첫 탭은 옛 판정과 같다(회귀 없음)', (tester) async {
      final h = (await _open(tester, withHost: true, tab: 'HI-HAT'))!;
      final r = tester.getRect(find.byKey(const ValueKey('doodle-fx')));
      h.calls.clear();
      await _tap(tester, Offset(r.left + r.width / 3 + 6, r.top + r.height * 0.3));
      expect(h.of('drumOn').last.$2[2], 2, reason: '첫 탭은 경계 바로 오른쪽 = 보통');
    });

    testWidgets('코드 방향 경계: 왼쪽(긴장)에 친 뒤 경계를 막 넘어도 긴장으로 굳는다', (tester) async {
      await _open(tester, tab: 'CHORD');
      final r = tester.getRect(find.byKey(const ValueKey('doodle-fx')));
      final b = r.width / 3;
      await _tap(tester, Offset(r.left + b - 15, r.top + r.height * 0.3));
      expect((_state(tester).debugFlash as (int, int)).$1, -1);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await _tap(tester, Offset(r.left + b + 7, r.top + r.height * 0.3));
      expect((_state(tester).debugFlash as (int, int)).$1, -1, reason: '경계 살짝 너머는 아직 긴장');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
      await _tap(tester, Offset(r.left + b + 45, r.top + r.height * 0.3));
      expect((_state(tester).debugFlash as (int, int)).$1, 0, reason: '충분히 옮기면 가운데(그대로)');
    });

    testWidgets('베이스: 사다리 경계에서 엄지가 조금(<slop) 굴러도 미끄러지지(덤 음) 않는다, 크게 그으면 미끄러진다',
        (tester) async {
      final h = (await _open(tester, withHost: true, tab: 'BASS'))!;
      final r = tester.getRect(find.byKey(const ValueKey('doodle-fx')));
      final rowH = r.height / 5;
      // 세 번째 칸 바로 위쪽 경계 3px 안쪽에 닿는다.
      final start = Offset(r.left + r.width * 0.5, r.top + rowH * 2 + 3);
      h.calls.clear();
      var g = await tester.startGesture(start);
      await tester.pump();
      await g.moveBy(const Offset(0, -10)); // 경계를 7px 넘음 (< kSlideSlopPx)
      await tester.pump();
      expect(h.of('holdOn'), hasLength(1), reason: '살짝 구른 건 슬라이드가 아니다');
      await g.up();
      await tester.pump();

      h.calls.clear();
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
      g = await tester.startGesture(start);
      await tester.pump();
      await g.moveBy(const Offset(0, -40)); // 확실히 넘음
      await tester.pump();
      expect(h.of('holdOn'), hasLength(2), reason: '크게 그으면 미끄러진다');
      expect(h.of('holdOn').last.$3[#glideF], isNotNull);
      await g.up();
    });

    testWidgets('기타 뮤트: 12px 정도 구른 톡은 여전히 뮤트, 30px 움직이면 뮤트 아님', (tester) async {
      final h = (await _open(tester, withHost: true, tab: 'CHORD', chordVoice: 'guitar'))!;
      double tailOfRelease() => h
          .of('holdOff')
          .where((c) => (c.$2[0] as int) >= 9200)
          .map((c) => (c.$3[#tailSec] ?? 0) as double)
          .last;
      var g = await tester.startGesture(_at(tester, 0.5, 0.3));
      await g.moveBy(const Offset(0, -12));
      await g.up(); // 프레임 없이 바로 — 90ms 안
      await tester.pump();
      expect(tailOfRelease(), kMuteTailSec);

      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      g = await tester.startGesture(_at(tester, 0.5, 0.3));
      await g.moveBy(const Offset(0, -30));
      await g.up();
      await tester.pump();
      expect(tailOfRelease(), 0, reason: '30px 는 움직인 것');
    });

    testWidgets('스웰: 톡 칠 때 엄지가 6px 위로 흘러도 볼륨이 안 튄다', (tester) async {
      final h = (await _open(tester, withHost: true, tab: 'CHORD', chordVoice: 'pad'))!;
      h.calls.clear();
      final g = await tester.startGesture(_at(tester, 0.5, 0.9));
      await tester.pump();
      await g.moveBy(const Offset(0, -6));
      await tester.pump();
      expect(h.of('setSwell').last.$2[1], kSwellStart);
      await g.moveBy(const Offset(0, -150));
      await tester.pump();
      expect(h.of('setSwell').last.$2[1] as double, greaterThan(kSwellStart));
      await g.up();
    });
  });

  group('F. 레이아웃 회귀 — 중앙 안내 글자가 세로 기둥이 되지 않는다', () {
    // 2026-09-30 회귀: 첫 안내 카드가 안 뜰 때 `SizedBox.shrink()` 가 Stack 의 「위치 없는 자식」이라
    // Stack 폭이 0 이 되어 KICK·TAP·REC·힌트가 한 글자씩 세로로 쌓였다.
    Future<void> check(WidgetTester tester, {required bool coach}) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      if (!coach) {
        for (final k in kDoodleCoachKeys) {
          DoodleHints.markSeen(k);
        }
      }
      final h = _Host();
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: DoodlePlayView(
          project: Project.initial(),
          transport: Transport(),
          host: h as AudioClient,
          initialBars: 4,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('이 순서로 시작'));
      // 대기 → 미리 세기 → REC 까지 루프를 흘린다.
      for (var i = 0; i < 40; i++) {
        h.looping(0.05 + i * 0.02);
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull, reason: 'overflow 등 예외 없음');
      if (!coach) expect(find.byKey(const ValueKey('doodle-coach')), findsNothing);
      final area = tester.getRect(find.byKey(const ValueKey('doodle-fx')));
      expect(area.width, greaterThan(300), reason: '치는 자리 폭이 살아 있다');
      // 중앙 글자 전부 — 폭이 정상이고(한 글자 폭이 아니고) 줄이 세로로 쌓이지 않는다.
      for (final s in ['TAP', 'REC', 'KICK', '고스트']) {
        for (final e in find.text(s).evaluate()) {
          final sz = (e.renderObject as RenderBox).size;
          expect(sz.width, greaterThan(sz.height * 0.8), reason: '$s 가 세로 기둥: $sz');
        }
      }
      for (final e in find.byType(Text).evaluate()) {
        final d = (e.widget as Text).data ?? '';
        final sz = (e.renderObject as RenderBox).size;
        if (d.length > 3 && sz.height > 0) {
          expect(sz.width, greaterThan(20), reason: '"$d" 폭이 너무 좁다: $sz');
        }
      }
    }

    testWidgets('안내 카드가 뜬 채', (tester) async => check(tester, coach: true));
    testWidgets('안내 카드가 없을 때(본 뒤) — 회귀 재현 조건', (tester) async => check(tester, coach: false));
  });
}
