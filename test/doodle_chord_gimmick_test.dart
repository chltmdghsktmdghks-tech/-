// 두들플레이 코드 기믹 (2026-09-29 (12) 2단계) — 순수 로직 + 화면 연결.
//   flutter test test/doodle_chord_gimmick_test.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/doodle_chords.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/theory.dart';
import 'package:music_doodle_engine/ui/doodle_play_view.dart';

void main() {
  const cMajor = MusicKey(root: 0, mode: 'major');
  const aMinor = MusicKey(root: 9, mode: 'minor');

  group('기본 진행은 매번 다르고 그 조의 다이아토닉이다', () {
    test('마디 수만큼 깔리고 도수는 0~6', () {
      for (final bars in [2, 4, 8]) {
        for (final mode in ['major', 'minor']) {
          final p = doodleBasePlan(mode: mode, bars: bars);
          expect(p.length, bars);
          expect(p.every((c) => c.degree >= 0 && c.degree <= 6 && c.type == null), isTrue);
        }
      }
    });
    test('씨앗을 바꾸면 진행이 달라진다(매번 다르게)', () {
      final seen = <String>{};
      for (var i = 0; i < 40; i++) {
        seen.add(doodleBasePlan(mode: 'major', bars: 4, rng: math.Random(i)).join());
      }
      expect(seen.length, greaterThan(2));
    });
    test('장르 없으면 세컨더리 도미넌트·7화음 같은 것 없이 단순 다이어토닉', () {
      for (var i = 0; i < 50; i++) {
        final p = doodleBasePlan(mode: 'minor', bars: 8, rng: math.Random(i));
        expect(p.every((c) => c.type == null), isTrue);
      }
    });
  });

  group('좌우 = 진행 방향 (긴장/해결) — 기능화성 표', () {
    test('해결: V→I / vi, 후보는 표 안에서만, 지금 코드와 다르다', () {
      const v = DoodleChordPick(4);
      final got = <int>{};
      for (var i = 0; i < 40; i++) {
        final n = doodleStepChord(v, 1, mode: 'major', salt: i);
        got.add(n.degree);
        expect(n, isNot(v));
        expect(n.type, isNull);
      }
      expect(got, {0, 5}, reason: 'V 의 해결 = I / vi');
    });
    test('도미넌트 7 은 5도 아래로 풀린다: V7→I, III7→vi, VI7→ii, II7→V', () {
      const cases = {4: 0, 2: 5, 5: 1, 1: 4};
      cases.forEach((from, to) {
        for (var i = 0; i < 6; i++) {
          final n = doodleStepChord(DoodleChordPick(from, 'dom7'), 1,
              mode: 'major', genre: 'jazz', salt: i);
          expect(n, DoodleChordPick(to), reason: '${from}7 → $to');
        }
      });
    });
    test('긴장: I → V7 / ii (장르 없으면 세컨더리 도미넌트 III7 은 안 쓰고 V7 은 남는다)', () {
      final got = <DoodleChordPick>{};
      for (var i = 0; i < 60; i++) {
        got.add(doodleStepChord(const DoodleChordPick(0), -1, mode: 'major', salt: i));
      }
      expect(got, {const DoodleChordPick(4, 'dom7'), const DoodleChordPick(1)});
    });
    test('긴장은 V7 쪽으로 끌어당긴다 — IV·ii 의 긴장 후보에 V7 이 있다', () {
      for (final d in [1, 3]) {
        final got = {
          for (var i = 0; i < 30; i++)
            doodleStepChord(DoodleChordPick(d), -1, mode: 'major', salt: i),
        };
        expect(got.contains(const DoodleChordPick(4, 'dom7')), isTrue, reason: '도수 $d');
      }
    });
    test('재즈 계열 장르는 긴장에 세컨더리 도미넌트(III7)가 섞인다', () {
      var saw = false;
      for (var i = 0; i < 80; i++) {
        if (doodleStepChord(const DoodleChordPick(0), -1,
                mode: 'major', genre: 'jazz', salt: i) ==
            const DoodleChordPick(2, 'dom7')) {
          saw = true;
        }
      }
      expect(saw, isTrue);
    });
    test('같은 입력·같은 salt 는 늘 같은 답(미리보기 = 확정의 전제)', () {
      for (var d = 0; d < 7; d++) {
        for (final dir in [-1, 1]) {
          expect(
            doodleStepChord(DoodleChordPick(d), dir, mode: 'minor', salt: 7),
            doodleStepChord(DoodleChordPick(d), dir, mode: 'minor', salt: 7),
          );
        }
      }
    });
    test('가운데(0)는 안 바꾼다', () {
      const c = DoodleChordPick(3);
      expect(doodleStepChord(c, 0, mode: 'major'), c);
    });
    test('장·단조 모든 도수·양방향·모든 salt 에서 도수 0~6, 후보가 항상 있다', () {
      for (var d = 0; d < 7; d++) {
        for (final dir in [-1, 1]) {
          for (final mode in ['major', 'minor']) {
            for (var i = 0; i < 12; i++) {
              final n = doodleStepChord(DoodleChordPick(d), dir, mode: mode, salt: i);
              expect(n.degree, inInclusiveRange(0, 6));
            }
          }
        }
      }
    });
    test('X 구역: 왼쪽 1/3 긴장, 오른쪽 1/3 해결', () {
      expect(doodleDirOfX(0.1), -1);
      expect(doodleDirOfX(0.5), 0);
      expect(doodleDirOfX(0.9), 1);
    });
  });

  group('랜덤 진행이 그럴듯하다', () {
    test('장·단조·장르·마디 수 전부에서 이웃 마디가 같은 코드로 붙지 않고 끝이 도미넌트/토닉 계열', () {
      for (final mode in ['major', 'minor']) {
        for (final bars in [4, 8]) {
          for (var i = 0; i < 60; i++) {
            final p = doodleBasePlan(mode: mode, bars: bars, genre: 'jazz', rng: math.Random(i));
            for (var b = 1; b < p.length; b++) {
              expect(p[b], isNot(p[b - 1]), reason: '$mode $bars #$i bar $b');
            }
            expect(p.first.degree == 0 || p.first.degree == 5 || p.first.degree == 1 || p.first.degree == 2, isTrue);
          }
        }
      }
    });
  });

  group('상하 = 두 구역 (위 화려 / 아래 담백)', () {
    test('한가운데 한 줄로 갈린다', () {
      expect(doodleColorOfY(0.0), 1);
      expect(doodleColorOfY(0.49), 1);
      expect(doodleColorOfY(0.5), 0);
      expect(doodleColorOfY(1.0), 0);
    });
    test('뿌리는 색이 바뀌어도 그대로 — 다른 코드 고르기가 아니다', () {
      for (var d = 0; d < 7; d++) {
        for (final key in [cMajor, aMinor]) {
          final roots = {
            for (final c in [0, 1])
              doodleChordSpec(key, DoodleChordPick(d), c).root,
          };
          expect(roots.length, 1, reason: '도수 $d 의 뿌리가 색에 따라 달라짐');
        }
      }
    });
    test('C장조 I: 담백 C, 화려 CM7. V7 자리는 담백 G7, 화려 G9', () {
      String n(DoodleChordPick p, int c) => doodleChordName(doodleChordSpec(cMajor, p, c));
      expect(n(const DoodleChordPick(0), 0), 'C');
      expect(n(const DoodleChordPick(0), 1), 'CM7');
      expect(n(const DoodleChordPick(4, 'dom7'), 0), 'G7');
      expect(n(const DoodleChordPick(4, 'dom7'), 1), 'G9');
    });
  });

  group('코드끼리 부드럽게 (voiceLead)', () {
    int move(List<int> a, List<int> b) {
      final n = a.length < b.length ? a.length : b.length;
      var t = 0;
      for (var i = 0; i < n; i++) {
        t += (a[i] - b[i]).abs();
      }
      return t;
    }

    test('C→G→Am→F 를 이으면 전부 G3~ 위쪽(베이스 아래로 안 내려감)이고, 뿌리 자리 그대로 치는 것보다 덜 움직인다', () {
      const key = cMajor;
      final plan = [0, 4, 5, 3].map((d) => DoodleChordPick(d)).toList();
      List<int>? prev = doodleVoiceSeed(key, plan);
      var led = 0, root = 0;
      List<int>? prevRoot;
      for (final c in [...plan, ...plan]) {
        final mid = chordMidiOf(doodleChordSpec(key, c, 0));
        final v = voiceLead(mid, prev);
        expect(v.first, greaterThanOrEqualTo(kVoiceLow - 3), reason: '베이스 음역 침범');
        led += move(prev!, v);
        prev = v;
        final r = invertChord(mid, 0);
        if (prevRoot != null) root += move(prevRoot, r);
        prevRoot = r;
      }
      expect(led, lessThan(root), reason: '공통음·최소 이동이 뿌리 자리 고정보다 부드러워야 한다');
    });
    test('같은 코드를 여러 번 치면 늘 같은 자리(연주 = 재생)', () {
      final mid = chordMidiOf(doodleChordSpec(cMajor, const DoodleChordPick(3), 1));
      final a = voiceLead(mid, [55, 59, 62]);
      expect(voiceLead(mid, a), a);
    });
    test('두들이 적는 코드 줄은 전위 칸이 비어 재생이 voiceLead 로 잇는다', () {
      // `_decorate` 는 [도수, 칸, 길이, 세기, 종류, null] — 일곱째(전위) 칸이 없다.
      final def = NotePatternDef('t', 2, 2, [
        [0, 0, 8, 2, null, null],
        [4, 16, 8, 2, 'dom7', null],
      ], spb: 16);
      final hits = buildChordPattern(def, cMajor);
      expect(hits.length, 2);
      // 둘째 코드(G7)가 뿌리 자리(G4 근처 72~)가 아니라 앞 코드에 붙어 낮게 앉는다.
      expect(hits[1].freqs.first, lessThan(midiFreq(66) + 1));
    });
  });

  group('마디 착지 탭이 다음 마디를 바꾼다 (DoodleChordPlan)', () {
    DoodleChordPlan mk() => DoodleChordPlan(
      const [DoodleChordPick(0), DoodleChordPick(4), DoodleChordPick(5), DoodleChordPick(3)],
      mode: 'major',
      rng: math.Random(1),
    );
    test('친 게 없거나 가운데면 깔린 진행 그대로', () {
      final c = mk();
      c.recordTap(0, dir: 0, color: 0);
      expect([for (var b = 0; b < 4; b++) c.pickAt(b)], c.base);
    });
    test('마디 0 의 마지막 탭이 오른쪽이면 마디 1 만 해결 쪽으로 바뀐다', () {
      final c = mk();
      c.recordTap(0, dir: 1, color: 0);
      final b1 = c.pickAt(1);
      expect(b1, isNot(c.base[1]));
      expect([0, 5, 3].contains(b1.degree), isTrue, reason: 'I 의 해결 후보(vi/IV)');
      expect(c.pickAt(0), c.base[0], reason: '앞 마디는 안 바뀐다');
    });
    test('처음 탭이 왼쪽이어도 마지막(착지) 탭이 이긴다', () {
      final c = mk();
      c.recordTap(0, dir: -1, color: 2);
      c.recordTap(0, dir: 0, color: -1); // 착지 탭: 가운데, 차분
      expect(c.pickAt(1), c.base[1], reason: '착지가 가운데면 안 바뀐다');
      expect(c.colorOf(0), -1, reason: '그 마디 기록 색은 착지 탭 기준');
    });
    test('바뀐 마디가 그 뒤 마디의 출발점이 된다', () {
      final c = mk();
      c.recordTap(0, dir: -1, color: 0);
      c.recordTap(1, dir: 1, color: 0);
      final b1 = c.pickAt(1);
      final b2 = c.pickAt(2);
      expect(b2, isNot(b1));
    });
    test('reset 은 깔린 진행과 손짓 기록을 되돌린다', () {
      final c = mk();
      c.recordTap(0, dir: 1, color: 2);
      c.pickAt(3);
      c.reset();
      expect(c.plan, c.base);
      expect(c.colorOf(0), 0);
    });
  });

  group('화면 연결', () {
    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: DoodlePlayView(
          project: Project.initial(),
          transport: Transport(),
          host: null,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('이 순서로 시작'));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.text('CHORD').first);
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('두 번째 손가락은 무시된다 — 가장 먼저 닿은 하나만', (tester) async {
      await open(tester);
      final g1 = await tester.startGesture(const Offset(60, 200));
      await tester.pump();
      final g2 = await tester.startGesture(const Offset(340, 700));
      await tester.pump();
      // 패드에는 하나의 코드 이름만 — 두 번째가 받아들여졌다면 색·방향이 덮어써졌을 것이다.
      expect(find.text('HOLD'), findsNothing);
      await g2.up();
      await g1.up();
      await tester.pump();
    });

    testWidgets('왼쪽을 치면 ◀ 방향 힌트, 오른쪽을 치면 ▶', (tester) async {
      await open(tester);
      final l = await tester.startGesture(const Offset(30, 450));
      await tester.pump();
      expect(find.textContaining('◀'), findsOneWidget);
      await l.up();
      await tester.pump(const Duration(milliseconds: 1500));
      final r = await tester.startGesture(const Offset(370, 450));
      await tester.pump();
      expect(find.textContaining('▶'), findsOneWidget);
      await r.up();
    });

    testWidgets('다음 코드가 늘 미리 보이고, 친 자리에 「착지」 고리와 방향 안내가 뜬다', (tester) async {
      await open(tester);
      expect(find.textContaining('다음 →'), findsOneWidget);
      expect(find.text('착지'), findsNothing);
      expect(find.textContaining('마지막에 친 쪽이 다음 코드를 정해요'), findsOneWidget);
      final g = await tester.startGesture(const Offset(40, 300));
      await tester.pump();
      expect(find.text('착지'), findsOneWidget);
      expect(find.textContaining('긴장 쪽으로 이어져요'), findsOneWidget);
      await g.up();
      await tester.pump();
      final g2 = await tester.startGesture(const Offset(360, 600));
      await tester.pump();
      expect(find.text('착지'), findsOneWidget, reason: '착지 고리는 하나 — 마지막 탭으로 옮겨 간다');
      expect(find.textContaining('해결 쪽으로 이어져요'), findsOneWidget);
      await g2.up();
    });

    testWidgets('세로는 위·아래 두 구역만 — 라벨 둘, 가운데 선', (tester) async {
      await open(tester);
      expect(find.textContaining('위 · 화려하게'), findsOneWidget);
      expect(find.textContaining('아래 · 담백하게'), findsOneWidget);
      expect(find.text('화려'), findsNothing, reason: '3구역 옛 라벨은 없어졌다');
      expect(find.text('차분'), findsNothing);
    });
  });
}
