// 두들 베이스가 순서와 상관없이 최신 코드 진행을 따른다 (2026-09-29 (14) B).
//   flutter test test/doodle_bass_follows_chord_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/tap_rec.dart';
import 'package:music_doodle_engine/ui/doodle_play_view.dart';

Future<dynamic> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final tr = Transport()..mode = 'major';
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData.dark(),
    home: DoodlePlayView(
      project: Project.blank()..setGenreBare('lofi'),
      transport: tr,
      host: null,
      initialBars: 4,
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  return tester.state(find.byType(DoodlePlayView));
}

/// 마디마다 머리 한 방씩 (칸 0·16·32·48).
List<TapHit> _hits() => [for (final s in [0, 16, 32, 48]) TapHit(0, s, 4)];

List<int> _degs(List<List<Object?>> notes) => [
  for (final n in notes) n[0] as int,
];

/// 베이스 도수 → 코드 도수(베이스는 0~6 이 뿌리, 옥타브 없음 — 톤 0).
void main() {
  testWidgets('베이스를 먼저 치고 나중에 코드를 바꾸면 베이스가 새 진행을 따른다', (tester) async {
    // 기본 진행은 매번 다르다(랜덤) — 손짓으로 바꾼 진행이 우연히 기본과 같은 판은 건너뛰고 다시 연다.
    var proved = false;
    for (var attempt = 0; attempt < 40 && !proved; attempt++) {
      await tester.pumpWidget(const SizedBox());
      final st = await _open(tester);
      st.debugCommit(DoodleKind.bass, _hits());
      final before = _degs(st.debugBassNotes);
      expect(before.length, 4);

      st.debugTapChord(0, dir: -1);
      st.debugTapChord(1, dir: 1);
      st.debugTapChord(2, dir: -1);
      st.debugCommit(DoodleKind.chord, _hits());
      final chord = _degs(st.debugChordNotes);
      final after = _degs(st.debugBassNotes);

      expect(after, chord, reason: '베이스 음높이(도수)가 확정된 코드 진행을 그대로 따라간다');
      // 리듬·세기는 그대로.
      expect([for (final n in st.debugBassNotes) n[1]], [0, 16, 32, 48]);
      expect([for (final n in st.debugBassNotes) n[3]], [2, 2, 2, 2]);
      if (chord.join() != before.join()) proved = true;
    }
    expect(proved, isTrue, reason: '코드를 바꾸면 베이스 음높이가 실제로 달라진 경우가 있어야 한다');
  });

  testWidgets('코드를 먼저 치고 베이스를 치면 처음부터 그 진행', (tester) async {
    final st = await _open(tester);
    st.debugTapChord(0, dir: 1);
    st.debugCommit(DoodleKind.chord, _hits());
    st.debugCommit(DoodleKind.bass, _hits());
    expect(_degs(st.debugBassNotes), _degs(st.debugChordNotes));
  });

  testWidgets('코드를 다시 녹음하려고 비우면 베이스는 기본 진행으로 돌아간다', (tester) async {
    final st = await _open(tester);
    st.debugCommit(DoodleKind.bass, _hits());
    final base = _degs(st.debugBassNotes); // 코드가 아직 없다 = 기본 진행
    st.debugTapChord(0, dir: 1);
    st.debugCommit(DoodleKind.chord, _hits());
    expect(_degs(st.debugBassNotes), _degs(st.debugChordNotes));
    st.debugBlank(DoodleKind.chord);
    expect(_degs(st.debugBassNotes), base, reason: '코드를 비우면 기본 진행으로 돌아간다');
  });

  testWidgets('베이스를 안 쳤으면 코드를 바꿔도 베이스는 비어 있다', (tester) async {
    final st = await _open(tester);
    st.debugCommit(DoodleKind.chord, _hits());
    expect(st.debugBassNotes, isEmpty);
  });
}
