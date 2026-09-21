// 5단계 15/N — 곡 목록에 보이는 길이 확인.
//   flutter test test/song_len_test.dart
//
// 목록에 적힌 길이는 **거짓말하기 쉬운 숫자**다. 2:40 이라 적어 놓고 3:19 가 재생되면
// 사용자는 목록을 안 믿게 되고, 그 뒤로는 곡을 다 열어 봐야 한다.
// 그래서 셈으로 낸 길이(`songSeconds`)가 **실제로 만들어지는 곡 길이**와 같은지 본다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/presets.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/store.dart';

void main() {
  test('곡 길이', () async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    // 1) 셈으로 낸 길이 = 실제로 만들어진 곡 길이 (스타일 6종에서)
    final p = Project.initial();
    final tr = Transport();
    var worst = 0.0;
    final rows = <String>[];
    for (final g in ['lofi', 'house', 'rock', 'trap', 'jazz', 'ambient']) {
      p.setGenre(g);
      tr.bpm = songGenreOfBpm(g);
      final quick = SceneSequencer.songSeconds(p, tr);
      final real = SceneSequencer.buildSong(p, tr).loopSec;
      final diff = (quick - real).abs();
      if (diff > worst) worst = diff;
      rows.add('$g ${quick.toStringAsFixed(1)}s');
    }
    check('1) 셈 = 실제', worst < 1e-6, '${rows.join(' · ')} (최대 차이 $worst초)');

    // 2) 뮤트한 트랙은 판 길이에 안 들어간다 — `build` 와 같은 규칙이어야 한다
    p.setGenre('lofi');
    for (final t in p.tracks) {
      t.mute = t.type != 'drum'; // 드럼만 남긴다
    }
    final q2 = SceneSequencer.songSeconds(p, tr);
    final r2 = SceneSequencer.buildSong(p, tr).loopSec;
    check(
      '2) 뮤트해도 같은 규칙',
      (q2 - r2).abs() < 1e-6,
      '${q2.toStringAsFixed(1)}s vs ${r2.toStringAsFixed(1)}s',
    );
    for (final t in p.tracks) {
      t.mute = false;
    }

    // 3) 저장하면 목록에 길이가 적힌다 — 목록은 곡 파일을 안 열고도 길이를 알아야 한다
    final dir = await Directory.systemTemp.createTemp('mdlen');
    final st = Store(
      project: p,
      transport: tr,
      live: LiveChannel(),
      master: MasterChannel(),
      overrideDir: dir,
    );
    await st.start();
    await st.saveNow();
    final meta = st.songs.firstWhere((s) => s.id == st.currentId);
    final want = SceneSequencer.songSeconds(p, tr);
    check(
      '3) 목록에 길이 저장',
      (meta.sec - want).abs() < 1e-6 && meta.sec > 0,
      '${meta.sec.toStringAsFixed(1)}초',
    );

    // 4) 앱을 껐다 켜도 남아 있다
    final p2 = Project.initial();
    final st2 = Store(
      project: p2,
      transport: Transport(),
      live: LiveChannel(),
      master: MasterChannel(),
      overrideDir: dir,
    );
    await st2.start();
    check(
      '4) 다시 켜도 남음',
      (st2.songs.first.sec - meta.sec).abs() < 1e-6,
      '${st2.songs.first.sec.toStringAsFixed(1)}초',
    );

    // 5) 길이 칸이 없던 옛 목록도 켤 때 한 번 채워진다
    //    (안 채우면 예전부터 쓰던 사람은 길이가 영영 안 보인다)
    final idx = File('${dir.path}/index.json');
    final raw = jsonDecode(await idx.readAsString()) as Map<String, dynamic>;
    for (final s in (raw['songs'] as List)) {
      (s as Map).remove('sec'); // 옛 형식으로 되돌린다
    }
    await idx.writeAsString(jsonEncode(raw));

    final p3 = Project.initial();
    final st3 = Store(
      project: p3,
      transport: Transport(),
      live: LiveChannel(),
      master: MasterChannel(),
      overrideDir: dir,
    );
    await st3.start();
    check(
      '5) 옛 목록 채우기',
      st3.songs.first.sec > 0,
      '${st3.songs.first.sec.toStringAsFixed(1)}초',
    );

    await dir.delete(recursive: true);

    // ── 6) **구간부터 재생** — 앞 구간을 건너뛰고 그만큼 짧아진다 ──
    //
    // 3분짜리 곡의 뒷부분을 고치는데 매번 처음부터 다 들어야 했다.
    // `buildSong(from:)` 은 앞 구간을 통째로 건너뛰고 시각을 0 으로 다시 잡는다.
    {
      final p6 = Project.initial();
      final tr6 = Transport();
      final spans = SceneSequencer.songSpans(p6, tr6);
      final whole = SceneSequencer.buildSong(p6, tr6);
      final from2 = SceneSequencer.buildSong(p6, tr6, from: 2);
      // 건너뛴 두 구간의 길이만큼 짧아야 한다
      final skipped = spans[0].$2 + spans[1].$2;
      final want = whole.totalSec - skipped;
      // 첫 구간이 아니게 되면 앞 구간 필의 크래시(afterFill)가 안 얹힌다 —
      // 길이는 그대로고 드럼 몇 개만 다르다. 길이만 본다.
      final lenOk = (from2.totalSec - want).abs() < 0.05;
      // 맨 끝 구간부터면 마지막 하나만 남는다
      final last = SceneSequencer.buildSong(
        p6,
        tr6,
        from: p6.song.sections.length - 1,
      );
      final lastOk = (last.totalSec - spans.last.$2).abs() < 0.05;
      // 범위를 넘겨도 안 죽는다(빈 곡)
      final over = SceneSequencer.buildSong(p6, tr6, from: 999);
      check(
        '6) 구간부터 재생',
        lenOk && lastOk && over.totalSec == 0 && from2.notes.isNotEmpty,
        '전체 ${whole.totalSec.toStringAsFixed(1)}초 · '
            '3번째부터 ${from2.totalSec.toStringAsFixed(1)}초(기대 ${want.toStringAsFixed(1)}) · '
            '끝 구간만 ${last.totalSec.toStringAsFixed(1)}초 · 범위 밖 ${over.totalSec}초',
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '곡 길이 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}

/// 스타일의 기본 템포.
double songGenreOfBpm(String key) => songGenreOf(key).$3;
