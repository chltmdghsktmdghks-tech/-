// Phase 5 — **팩이 정말 따로 떨어지는가.** (개선 계획 7-2)
//   flutter test test/pack_check_test.dart
//
// 팩을 만드는 뜻은 하나다: **하나를 들어내도 나머지가 멀쩡할 것.**
// 그게 안 되면 「팩」이라는 이름만 붙인 목록이다.
//
// 지키는 것:
//  1. 모든 장르가 **정확히 한** 팩에 속한다(빠진 것도, 두 번 든 것도 없다)
//  2. 팩끼리 패턴을 **안 나눠 쓴다** — 나눠 쓰면 하나를 빼는 순간 다른 곡이 깨진다
//  3. 팩을 하나씩 빼 봐도 남은 곡이 **다 울린다**
//  4. 팩 id 와 이름이 비어 있지 않다
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/packs.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/song.dart';

/// 그 장르의 곡이 실제로 부르는 패턴 이름들.
Set<String> _patternsOf(GenreDef g) {
  final s = <String>{g.drumPat, g.bassPat, g.chordPat, g.melodyPat};
  final arr = kSongForms[g.key];
  if (arr != null) {
    for (final sec in arr) {
      for (final n in [sec.drum, sec.bass, sec.chord, sec.melody]) {
        if (n != null) s.add(n);
      }
    }
  }
  final obj = kObjectSongForms[g.key];
  if (obj != null) {
    for (final sec in obj.sections) {
      s.addAll(sec.parts.values);
    }
  }
  return s;
}

void main() {
  test('콘텐츠 팩', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    // ── 1) 장르가 정확히 한 팩에 ──
    {
      final counts = <String, int>{for (final g in kGenres) g.key: 0};
      final unknown = <String>[];
      for (final p in kPacks) {
        for (final k in p.genres) {
          if (!counts.containsKey(k)) {
            unknown.add('${p.id}/$k');
          } else {
            counts[k] = counts[k]! + 1;
          }
        }
      }
      final orphan = [
        for (final e in counts.entries)
          if (e.value == 0) e.key,
      ];
      final dup = [
        for (final e in counts.entries)
          if (e.value > 1) e.key,
      ];
      check(
        '1) 빠진 장르가 없다',
        orphan.isEmpty,
        orphan.isEmpty
            ? '${kGenres.length}개 전부'
            : '어느 팩에도 없음: ${orphan.join(', ')}',
      );
      check(
        '1-b) 두 팩에 든 장르가 없다',
        dup.isEmpty,
        dup.isEmpty ? '' : dup.join(', '),
      );
      check(
        '1-c) 없는 장르를 가리키지 않는다',
        unknown.isEmpty,
        unknown.isEmpty ? '' : unknown.join(', '),
      );
      check(
        '1-d) packOf 가 다 찾는다',
        kGenres.every((g) => packOf(g.key) != null),
        '',
      );
    }

    // ── 2) 팩끼리 패턴을 안 나눠 쓴다 ──
    {
      final byPack = <String, Set<String>>{};
      for (final p in kPacks) {
        final s = <String>{};
        for (final k in p.genres) {
          s.addAll(_patternsOf(genreDef(k)));
        }
        byPack[p.id] = s;
      }
      final clash = <String>[];
      final ids = byPack.keys.toList();
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          final both = byPack[ids[i]]!.intersection(byPack[ids[j]]!);
          if (both.isNotEmpty) {
            clash.add('${ids[i]}↔${ids[j]}: ${both.take(3).join(', ')}');
          }
        }
      }
      check(
        '2) 팩끼리 패턴을 안 나눠 쓴다',
        clash.isEmpty,
        clash.isEmpty
            ? '${byPack.values.fold(0, (a, b) => a + b.length)}개 패턴 · 겹침 0'
            : clash.join(' · '),
      );
    }

    // ── 3) 하나를 빼도 나머지가 울린다 ──
    //
    // 진짜로 빼 볼 수는 없으니(상수 목록이다) **나머지 장르의 곡을 전부 만들어 본다.**
    // 뺀 팩의 패턴을 남은 곡이 부르고 있었다면 그 곡이 조용해지거나 짧아진다.
    {
      final broken = <String>[];
      for (final drop in kPacks) {
        final rest = [
          for (final g in kGenres)
            if (!drop.genres.contains(g.key)) g,
        ];
        final gone = <String>{};
        for (final k in drop.genres) {
          gone.addAll(_patternsOf(genreDef(k)));
        }
        for (final g in rest) {
          final mine = _patternsOf(g);
          final leaning = mine.intersection(gone);
          if (leaning.isNotEmpty) {
            broken.add('${drop.id} 빼면 ${g.key}: ${leaning.take(2).join(', ')}');
            continue;
          }
          // 실제로 울리는지도 본다
          final p = Project.initial()..setGenre(g.key);
          final tr = Transport()
            ..bpm = g.bpm
            ..mode = g.mode;
          final b = SceneSequencer.buildSong(p, tr);
          if (b.notes.isEmpty && b.drums.isEmpty) {
            broken.add('${drop.id} 빼면 ${g.key} 무음');
          }
        }
      }
      check(
        '3) 팩 하나를 빼도 나머지가 멀쩡하다',
        broken.isEmpty,
        broken.isEmpty
            ? '${kPacks.length}개 팩 × 남은 장르 전부'
            : broken.take(3).join(' · '),
      );
    }

    // ── 4) 이름이 비어 있지 않다 ──
    {
      final bad = [
        for (final p in kPacks)
          if (p.id.isEmpty ||
              p.label.isEmpty ||
              p.blurb.isEmpty ||
              p.genres.isEmpty)
            p.id,
      ];
      check(
        '4) 팩마다 이름과 내용이 있다',
        bad.isEmpty,
        bad.isEmpty
            ? kPacks.map((p) => '${p.label}(${p.genres.length})').join(' · ')
            : bad.join(', '),
      );
      final ids = [for (final p in kPacks) p.id];
      check('4-b) id 가 안 겹친다', ids.toSet().length == ids.length, ids.join(','));
    }

    // ignore: avoid_print
    print(fail == 0 ? '콘텐츠 팩 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
