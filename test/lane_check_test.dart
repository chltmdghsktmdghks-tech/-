// **타임라인 트랙 줄** — 씬 위에 악기별로 클립을 얹는다. (옛 앱 `P.tl.clips`)
//   flutter test test/lane_check_test.dart
//
// 규칙은 옛 앱과 같다: 그 마디에 트랙 클립이 놓여 있으면 **그것이 씬을 이긴다.**
// 여기서 보는 것은 넷이다:
//  1) 안 놓으면 소리가 **한 톨도** 안 바뀐다 — 새 길이 옛 곡을 건드리면 안 된다
//  2) 놓으면 그 마디만 바뀐다 — 앞뒤 마디와 다른 트랙은 그대로
//  3) 구간을 끼우거나 옮기면 **클립이 따라간다** — 절대 마디로 잡았으면 어긋난다
//  4) 저장 왕복에 살아남는다
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/ui/song_view.dart';

/// 그 트랙이 [fromBar]~[untilBar] 사이에 내는 (시각, 주파수) 목록.
List<String> _notesIn(
  Project p,
  Transport tr,
  String type,
  int fromBar,
  int untilBar,
) {
  final b = SceneSequencer.buildSong(p, tr);
  final buses = SceneSequencer.busNames(p);
  final t = p.tracks.firstWhere((x) => x.type == type);
  final part = buses.indexOf(t.id);
  final barSec = 60.0 / tr.bpm * 4;
  final out = <String>[];
  for (final n in b.notes) {
    if (n[7] != part) continue;
    final at = n[6] as double;
    final bar = at / barSec;
    if (bar < fromBar - 1e-6 || bar >= untilBar - 1e-6) continue;
    out.add('${at.toStringAsFixed(4)}:${(n[1] as double).toStringAsFixed(2)}');
  }
  out.sort();
  return out;
}

String _all(Project p, Transport tr) {
  final b = SceneSequencer.buildSong(p, tr);
  final n = [
    for (final x in b.notes)
      '${(x[6] as double).toStringAsFixed(4)}|${x[0]}|'
          '${(x[1] as double).toStringAsFixed(3)}|${x[7]}',
  ]..sort();
  final d = [
    for (final x in b.drums)
      '${(x[4] as double).toStringAsFixed(4)}|${x[1]}|${x[2]}',
  ]..sort();
  return '${n.join(',')}//${d.join(',')}';
}

void main() {
  test('타임라인 트랙 줄', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $what — $detail');
      if (!ok) fail++;
    }

    final p = Project.initial()..setGenre('lofi');
    final tr = Transport();
    for (final s in p.scenes) {
      s.bpm = null; // 마디↔초 셈을 단순하게 — 곡 빠르기 하나로 본다
    }

    // 1) 안 놓으면 **한 톨도** 안 바뀐다
    final plain = _all(p, tr);
    check('1) 놓기 전', plain.isNotEmpty, '음 ${plain.split(',').length}개');

    // 멜로디 트랙에 다른 패턴을 하나 놓는다
    final mel = p.tracks.firstWhere((t) => t.type == 'melody');
    final cur = p.song.sections.isEmpty ? null : p.scenes[0].clips[mel.id];
    final other = kMelodyPatterns
        .where((d) => d.name != cur)
        .firstWhere((d) => d.bars <= 2);

    // 구간 0 의 **둘째 마디**에 놓는다 — 첫 마디가 그대로여야 「그 마디만」이 보인다
    p.song.putLane(0, 1, mel.id, other.name);

    final after = _all(p, tr);
    check('2) 놓으면 소리가 바뀐다', after != plain, '');

    // 2-b) **그 마디만** — 첫 마디는 그대로여야 한다
    {
      final before0 = _notesIn(p, tr, 'melody', 0, 1);
      p.song.lanes.clear();
      final plain0 = _notesIn(p, tr, 'melody', 0, 1);
      p.song.putLane(0, 1, mel.id, other.name);
      check(
        '2-b) 앞마디는 그대로',
        before0.join('|') == plain0.join('|'),
        '${plain0.length}음',
      );
    }

    // 2-c) 놓은 마디의 멜로디는 **씬 것이 아니다**
    {
      final withLane = _notesIn(p, tr, 'melody', 1, 2);
      p.song.lanes.clear();
      final withoutLane = _notesIn(p, tr, 'melody', 1, 2);
      p.song.putLane(0, 1, mel.id, other.name);
      check(
        '2-c) 놓은 마디는 클립 것',
        withLane.join('|') != withoutLane.join('|'),
        '씬 ${withoutLane.length}음 → 클립 ${withLane.length}음',
      );
    }

    // 2-d) **다른 트랙**은 안 건드린다
    {
      // 곡 **전체**를 본다 — 앞 네 마디만 재면 그 구간에 베이스가 없는 판에서
      // 「0음이 그대로였다」로 통과한다(재는 시늉만 하는 검사가 된다).
      final bassWith = _notesIn(p, tr, 'bass', 0, 9999);
      p.song.lanes.clear();
      final bassWithout = _notesIn(p, tr, 'bass', 0, 9999);
      p.song.putLane(0, 1, mel.id, other.name);
      check(
        '2-d) 다른 트랙은 그대로',
        bassWithout.isNotEmpty && bassWith.join('|') == bassWithout.join('|'),
        '${bassWithout.length}음',
      );
    }

    // 3) 구간을 앞에 끼우면 **클립이 따라간다**
    {
      p.song.insert(0, 0, reps: 1);
      check(
        '3) 구간을 끼우면 따라간다',
        p.song.lanes.single.section == 1,
        '구간 ${p.song.lanes.single.section}',
      );
      p.song.removeAt(0);
      check(
        '3-b) 도로 빼면 제자리',
        p.song.lanes.single.section == 0,
        '구간 ${p.song.lanes.single.section}',
      );
    }

    // 3-c) 구간을 **옮기면** 같이 간다
    {
      p.song.move(0, 2);
      check(
        '3-c) 옮기면 같이 간다',
        p.song.lanes.single.section == 2,
        '구간 ${p.song.lanes.single.section}',
      );
      p.song.move(2, 0);
    }

    // 3-d) 그 구간을 지우면 클립도 없어진다 — 남으면 엉뚱한 구간에 붙는다
    {
      final copy = p.song.lanes.single.copy();
      p.song.removeAt(0);
      check(
        '3-d) 구간을 지우면 클립도 간다',
        p.song.lanes.isEmpty,
        '${p.song.lanes.length}개',
      );
      p.song.insert(0, copy.section, reps: 2);
      p.song.putLane(0, copy.bar, copy.trackId, copy.pattern);
    }

    // 3-e) 「한 벌 더」는 클립까지 베낀다 — 안 그러면 두 번째가 딴 소리다
    {
      p.song.duplicateAt(0);
      final at1 = p.song.lanesIn(1, mel.id);
      check('3-e) 한 벌 더는 클립도 베낀다', at1.length == 1, '${at1.length}개');
      p.song.removeAt(1);
    }

    // 4) 저장 왕복
    {
      final q = Project.initial()
        ..loadJson(jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);
      final c = q.song.lanes;
      check(
        '4) 저장 왕복',
        c.length == 1 &&
            c.single.section == 0 &&
            c.single.bar == 1 &&
            c.single.pattern == other.name,
        '${c.length}개 · ${c.isEmpty ? '' : c.single.toJson()}',
      );
      check('4-b) 소리도 같다', _all(q, tr) == _all(p, tr), '');
    }

    // 4-c) **옛 파일**에는 이 칸이 아예 없다 — 빈 목록으로 읽혀야 한다
    {
      final j = jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>;
      j.remove('lanes');
      final q = Project.initial()..loadJson(j);
      check('4-c) 옛 파일은 빈 목록', q.song.lanes.isEmpty, '${q.song.lanes.length}개');
    }

    // 4-d) 없는 구간을 가리키는 클립은 **불러올 때 버린다**
    {
      final j = jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>;
      (j['lanes'] as List).add({
        'section': 99,
        'bar': 0,
        'track': mel.id,
        'pattern': other.name,
      });
      final q = Project.initial()..loadJson(j);
      check(
        '4-d) 없는 구간 클립은 버린다',
        q.song.lanes.length == 1,
        '${q.song.lanes.length}개',
      );
    }

    // 5) 같은 자리에 또 놓으면 **갈아 끼운다**(겹치지 않는다)
    {
      final third = kMelodyPatterns
          .where((d) => d.name != other.name && d.bars <= 2)
          .first;
      p.song.putLane(0, 1, mel.id, third.name);
      check(
        '5) 같은 자리는 갈아 끼운다',
        p.song.lanes.length == 1 && p.song.lanes.single.pattern == third.name,
        '${p.song.lanes.length}개 · ${p.song.lanes.single.pattern}',
      );
    }

    // 6) **구간 밖에 놓인 클립은 소리를 안 낸다.** 판 수를 줄이면 클립이 구간보다
    //    뒤로 밀려나는데, 그때도 울리면 곡이 그만큼 길어지거나 딴 구간에 섞인다.
    {
      p.song.lanes.clear();
      final plainNow = _all(p, tr);
      final secBars =
          SceneSequencer.sceneLoopBars(p, p.song.sections[0].scene) *
          p.song.sections[0].reps;
      p.song.putLane(0, secBars + 2, mel.id, other.name);
      check(
        '6) 구간 밖 클립은 조용하다',
        _all(p, tr) == plainNow,
        '구간 $secBars마디 · 놓은 자리 ${secBars + 2}마디',
      );
      // 6-b) 그래도 **자료는 남는다** — 판 수를 도로 늘리면 다시 울려야 한다.
      //      (「울린다」를 제 자신과 견주면 늘 통과한다 — 클립을 뺀 소리와 견준다)
      p.song.setReps(0, p.song.sections[0].reps + 2);
      final withLane = _all(p, tr);
      final keep = p.song.lanes.single.copy();
      p.song.lanes.clear();
      final withoutLane = _all(p, tr);
      p.song.putLane(keep.section, keep.bar, keep.trackId, keep.pattern);
      check(
        '6-b) 판을 늘리면 되살아난다',
        p.song.lanes.length == 1 && withLane != withoutLane,
        '클립 ${p.song.lanes.length}개 · 소리 다름 ${withLane != withoutLane}',
      );
    }

    // 7) **구간 띠가 트랙 줄까지 센다.** 씬에서는 쉬는 악기라도 그 구간에만
    //    넣어 뒀으면 소리가 난다 — 안 세면 「드럼뿐」이라 적어 놓고 기타가 나온다.
    {
      final q = Project.initial()..setGenre('lofi');
      final mel2 = q.tracks.firstWhere((t) => t.type == 'melody');
      // 그 씬에서 멜로디를 쉬게 한다
      for (final sc in q.scenes) {
        sc.clips[mel2.id] = null;
      }
      q.launchScene(0);
      final without = sectionTypes(q, q.song.sections[0].scene, section: 0);
      q.song.putLane(0, 0, mel2.id, other.name);
      final with_ = sectionTypes(q, q.song.sections[0].scene, section: 0);
      check(
        '7) 구간 띠가 트랙 줄을 센다',
        !without.contains('melody') && with_.contains('melody'),
        '$without → $with_',
      );
    }

    // 8) **트랙을 지우면 그 줄의 클립도 같이 나간다.** 남으면 없는 악기를
    //    가리키는 클립이 되는데, 화면에는 그 줄이 아예 없으니 지울 길도 없다.
    //    (「막 써 보기」가 잡은 것 — 씨앗 2, 29번째 걸음)
    {
      final q = Project.initial()..setGenre('lofi');
      final t = q.tracks.firstWhere((x) => x.type == 'melody');
      final n = SceneSequencer.patternNamesFor(q, 'melody').first;
      q.song.putLane(0, 0, t.id, n);
      final gone = q.removeTrack(t);
      check('8) 트랙과 같이 나간다', q.song.lanes.isEmpty, '${q.song.lanes.length}개');
      // 8-b) 되돌리면 같이 돌아온다 — 트랙만 돌아오면 반쪽이다
      if (gone != null) {
        q.undoRemoveTrack(gone);
        check(
          '8-b) 되돌리면 같이 돌아온다',
          q.song.lanes.length == 1 && q.song.lanes.single.trackId == t.id,
          '${q.song.lanes.length}개',
        );
      }
    }

    // 9) **스타일을 바꾸면 비운다.** 트랙도 씬도 구간도 통째로 새것이라
    //    옛 클립은 없는 트랙·없는 구간을 가리키게 된다.
    {
      final q = Project.initial()..setGenre('lofi');
      final t = q.tracks.firstWhere((x) => x.type == 'melody');
      final n = SceneSequencer.patternNamesFor(q, 'melody').first;
      q.song.putLane(0, 0, t.id, n);
      q.setGenre('house');
      check('9) 스타일을 바꾸면 비운다', q.song.lanes.isEmpty, '${q.song.lanes.length}개');
    }

    expect(fail, 0, reason: '$fail개 항목이 어긋났습니다');
  });
}
