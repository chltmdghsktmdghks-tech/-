// Phase 5 — **장르가 인서트를 꽂아 주되, 내 것은 안 건드리는가.** (개선 계획 7)
//   flutter test test/genre_fx_test.dart
//
// 이 기능의 위험은 하나다: **공들여 꽂아 둔 인서트가 스타일을 바꾸는 순간 조용히
// 날아가는 것.** 오류도 안 나고 되돌릴 수도 없다. 그래서 그것부터 지킨다.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/fx.dart';
import 'package:music_doodle_engine/genre_fx.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/project.dart';

void main() {
  test('장르 인서트', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    // ── 1) 표가 제정신인가 ──
    {
      final bad = <String>[];
      for (final e in kGenreFx.entries) {
        if (!isKnownGenre(e.key)) bad.add('없는 장르 ${e.key}');
        for (final slot in e.value.entries) {
          for (final f in slot.value) {
            final def = kFxCatalog[f.type];
            if (def == null) {
              bad.add('${e.key}/${slot.key} 없는 인서트 ${f.type}');
              continue;
            }
            for (final k in f.params.keys) {
              final pd = def.params.where((p) => p.key == k);
              if (pd.isEmpty) {
                bad.add('${e.key}/${slot.key}/${f.type} 없는 손잡이 $k');
                continue;
              }
              final v = f.params[k]!;
              if (v < pd.first.min || v > pd.first.max) {
                bad.add('${e.key}/${slot.key}/${f.type}/$k=$v 범위 밖');
              }
            }
          }
        }
      }
      check(
        '1) 인서트·손잡이가 다 있다',
        bad.isEmpty,
        bad.isEmpty ? '${kGenreFx.length}개 장르' : bad.take(4).join(', '),
      );
    }

    // ── 2) 실제로 꽂힌다 ──
    {
      final got = <String, int>{};
      for (final g in kGenres) {
        final p = Project.initial()..setGenre(g.key);
        got[g.key] = p.tracks.fold(0, (n, t) => n + t.chain.length);
      }
      final want = {
        for (final g in kGenres)
          g.key: (kGenreFx[g.key] ?? const {}).values.fold<int>(
            0,
            (n, l) => n + l.length,
          ),
      };
      final miss = [
        for (final g in kGenres)
          if (got[g.key] != want[g.key])
            '${g.key} ${got[g.key]}/${want[g.key]}',
      ];
      check(
        '2) 표대로 꽂힌다',
        miss.isEmpty,
        miss.isEmpty
            ? got.entries.map((e) => '${e.key}:${e.value}').join(' ')
            : miss.join(', '),
      );
      check('2-b) 재즈는 비어 있다', got['jazz'] == 0, '마이크 앞에서 친 소리에는 안 건다');
    }

    // ── 3) **내가 꽂은 것은 안 날아간다** ── 이게 이 시험의 이유다
    {
      final p = Project.initial()..setGenre('lofi');
      final mel = p.tracks.firstWhere((t) => t.type == 'melody');
      mel.addFx('reverb');
      mel.setFxParam(0, 'mix', 0.9);
      final before = mel.chain.map((f) => f.type).join(',');

      p.setGenre('rock'); // 록은 멜로디에 앰프를 꽂는 장르다
      final after = p.tracks
          .firstWhere((t) => t.id == mel.id)
          .chain
          .map((f) => f.type)
          .join(',');
      check('3) 내가 꽂은 것은 스타일을 바꿔도 그대로', after == before, '$before → $after');
      check(
        '3-b) 값도 그대로',
        p.tracks.firstWhere((t) => t.id == mel.id).chain.first.p['mix'] == 0.9,
        '',
      );

      // 안 만진 트랙은 새 장르 것으로 갈린다
      final bass = p.tracks.firstWhere((t) => t.type == 'bass');
      check(
        '3-c) 안 만진 트랙은 갈린다',
        bass.chain.length == 1 && bass.chain.first.type == 'bassamp',
        bass.chain.map((f) => f.type).join(','),
      );
    }

    // ── 4) 장르가 꽂은 것은 다음 장르 것으로 갈린다(쌓이지 않는다) ──
    {
      final p = Project.initial()..setGenre('rock');
      p.setGenre('lofi');
      p.setGenre('house');
      final piles = [
        for (final t in p.tracks)
          if (t.chain.length > 2) '${t.name}(${t.chain.length})',
      ];
      check(
        '4) 갈아탈수록 쌓이지 않는다',
        piles.isEmpty,
        piles.isEmpty
            ? p.tracks.map((t) => '${t.type}:${t.chain.length}').join(' ')
            : piles.join(', '),
      );
    }

    // ── 5) 저장 왕복 ──
    {
      final p = Project.initial()..setGenre('rock');
      final mel = p.tracks.firstWhere((t) => t.type == 'melody');
      final autoBefore = mel.fxAuto;
      final back = Project.initial()..loadJson(p.toJson());
      final m2 = back.tracks.firstWhere((t) => t.id == mel.id);
      check(
        '5) fxAuto 가 왕복에서 살아남는다',
        autoBefore == true && m2.fxAuto == true,
        '$autoBefore → ${m2.fxAuto}',
      );
      check(
        '5-b) 인서트도 그대로',
        m2.chain.map((f) => f.type).join(',') ==
            mel.chain.map((f) => f.type).join(','),
        m2.chain.map((f) => f.type).join(','),
      );
      check(
        '5-c) 옛 파일은 내 것으로 본다',
        Track.fromJson({
              'id': 'tX',
              'name': 'x',
              'type': 'melody',
              'voice': 'lead',
              'pan': 0.0,
              'rev': 0.0,
              'fx': [],
              'pattern': null,
            }).fxAuto ==
            false,
        'fxAuto 칸이 없으면 false',
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '장르 인서트 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
