// **곡을 여러 개 놓고 막 쓰다 보면** 생기는 저장 고장을 찾는다 (씨앗 고정).
//   flutter test test/store_rough_test.dart
//
// `rough_use_test` 는 프로젝트 하나 안에서만 논다. 실제로는 곡을 만들고 · 복제하고 ·
// 지우고 · 되돌리고 · 오가면서 그 사이사이에 **자동 저장**이 돈다.
// 파일과 목록이 어긋나는 순간 「곡이 안 열린다」가 되는데, 그건 앱을 껐다 켠
// 다음에야 드러난다 — 그때는 이미 늦었다.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/store.dart';

void main() {
  test('곡 여러 개로 막 써 보기', () async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final genres = [for (final g in kGenres) g.key];
    final bad = <String>[];
    var steps = 0;

    for (var seed = 1; seed <= 20; seed++) {
      final rnd = math.Random(seed);
      final dir = await Directory.systemTemp.createTemp('mdrough');
      final p = Project.initial();
      final tr = Transport();
      final live = LiveChannel();
      final master = MasterChannel();
      var st = Store(
        project: p,
        transport: tr,
        live: live,
        master: master,
        overrideDir: dir,
      );
      await st.start();
      st.attach();
      final log = <String>[];
      RemovedSong? lastGone;

      // **내용이 살아남는가** — 이름만 맞고 속이 바뀌면 그게 더 나쁘다.
      // 곡마다 「스타일·템포·첫 트랙 볼륨」을 적어 두고, 다시 열 때 대조한다.
      final want = <String, (String, double, double)>{};
      void remember() {
        final id = st.currentId;
        if (id != null) want[id] = (p.genre, tr.bpm, p.tracks.first.vol);
      }

      String? mismatch() {
        final id = st.currentId;
        if (id == null) return null;
        final w = want[id];
        if (w == null) return null;
        if (p.genre != w.$1) return '스타일이 바뀌었다(${w.$1} → ${p.genre})';
        if ((tr.bpm - w.$2).abs() > 0.01) {
          return '템포가 바뀌었다(${w.$2} → ${tr.bpm})';
        }
        if ((p.tracks.first.vol - w.$3).abs() > 1e-6) {
          return '첫 트랙 볼륨이 바뀌었다(${w.$3} → ${p.tracks.first.vol})';
        }
        return null;
      }

      remember();

      Future<String?> trouble() async {
        // ① 목록에 있는 곡은 파일이 있어야 한다
        for (final s in st.songs) {
          if (!await File('${dir.path}/songs/${s.id}.json').exists()) {
            return '목록에 있는데 파일이 없다(${s.name})';
          }
        }
        // ② 열려 있는 곡은 목록에 있어야 한다
        if (st.currentId != null &&
            !st.songs.any((s) => s.id == st.currentId)) {
          return '열린 곡이 목록에 없다';
        }
        // ③ 목록이 비면 안 된다
        if (st.songs.isEmpty) return '목록이 비었다';
        // ④ 저장이 실패하고 있으면 안 된다
        if (st.saveFails > 0)
          return '저장 실패 ${st.saveFails}번(${st.lastSaveError})';
        // ⑤ 지금 곡은 소리를 만들 수 있어야 한다
        try {
          SceneSequencer.buildSong(p, tr);
        } catch (e) {
          return '소리를 못 만든다: $e';
        }
        return null;
      }

      for (var i = 0; i < 100; i++) {
        // 이 동작이 **여는 곡을 바꾸는가.**
        //
        // 바꾸는 동작이면 새로 온 곡의 값이 적어 둔 참값과 **맞아야 한다** —
        // 대조를 먼저 하고 그다음 참값을 갱신한다. 고치는 동작(스타일·볼륨·저장)
        // 이면 반대로 새 값이 곧 참값이다.
        //
        // 이 순서가 뒤집혀 있었다. 걸음 끝에서 `remember()` 를 **먼저** 불렀기
        // 때문에, 삭제가 옆 곡 파일을 덮어써도 그 오염된 값이 그대로 참값으로
        // 등록됐다. 100걸음을 걸어도 영원히 못 잡는 자였다.
        var switched = false;
        switch (rnd.nextInt(9)) {
          case 0:
            log.add('새 곡');
            await st.newSong(name: '곡$i');
            switched = true;
          case 1:
            if (st.songs.length > 1) {
              final s = st.songs[rnd.nextInt(st.songs.length)];
              log.add('열기 ${s.name}');
              remember(); // 떠나기 전 지금 곡을 적어 둔다
              await st.open(s.id);
              switched = true;
              final m = mismatch();
              if (m != null) {
                bad.add(
                  '씨앗 $seed · ${i + 1}번째\n     한 일: ${log.join(' → ')}\n'
                  '     탈: 다시 열었더니 $m',
                );
              }
            }
          case 2:
            final s = st.songs[rnd.nextInt(st.songs.length)];
            log.add('복제 ${s.name}');
            await st.duplicate(s.id);
            switched = true;
          case 3:
            final s = st.songs[rnd.nextInt(st.songs.length)];
            log.add('이름 ${s.name}');
            await st.rename(s.id, '바뀐$i');
          case 4:
            if (st.songs.length > 1) {
              final s = st.songs[rnd.nextInt(st.songs.length)];
              log.add('삭제 ${s.name}');
              lastGone = await st.remove(s.id);
              switched = true;
            }
          case 5:
            if (lastGone != null) {
              log.add('삭제 되돌리기');
              await st.undoRemove(lastGone);
              lastGone = null;
              switched = true;
            }
          case 6:
            final g = genres[rnd.nextInt(genres.length)];
            log.add('스타일 $g');
            p.setGenre(g);
            final gd = genreDef(g);
            tr
              ..bpm = gd.bpm
              ..mode = gd.mode;
          case 7:
            log.add('저장');
            await st.saveNow();
          case 8:
            final t = p.tracks[rnd.nextInt(p.tracks.length)];
            log.add('만지기 ${t.name}');
            t.vol = rnd.nextDouble();
            if (p.scenes.length > 1) {
              p.launchScene(rnd.nextInt(p.scenes.length));
            }
        }
        steps++;
        var t = await trouble();
        if (switched) {
          t ??= mismatch(); // 바꿔 온 곡이 두고 간 그대로인가
          remember(); // 처음 보는 곡이면 이제부터 이것이 참값이다
        } else {
          remember(); // 방금 만진 것이 지금 곡의 참값이다
          t ??= mismatch();
        }
        if (bad.isNotEmpty) break;
        if (t != null) {
          bad.add(
            '씨앗 $seed · ${i + 1}번째\n     한 일: ${log.join(' → ')}\n     탈: $t',
          );
          break;
        }
      }

      // **앱을 껐다 켠 것처럼** 다시 읽어 본다 — 여기서 드러나는 고장이 제일 나쁘다
      if (bad.isEmpty) {
        await st.saveNow();
        final names = [for (final s in st.songs) s.name];
        final cur = st.currentId;
        st.detach();
        final p2 = Project.initial();
        final st2 = Store(
          project: p2,
          transport: Transport(),
          live: LiveChannel(),
          master: MasterChannel(),
          overrideDir: dir,
        );
        await st2.start();
        final names2 = [for (final s in st2.songs) s.name];
        if (names.join(',') != names2.join(',')) {
          bad.add(
            '씨앗 $seed · 껐다 켜니 목록이 다르다\n'
            '     전: ${names.join(',')}\n     후: ${names2.join(',')}',
          );
        } else if (st2.currentId != cur) {
          bad.add('씨앗 $seed · 껐다 켜니 다른 곡이 열린다');
        } else {
          // 목록의 모든 곡이 실제로 열리는가
          for (final s in st2.songs) {
            try {
              await st2.open(s.id);
              SceneSequencer.buildSong(p2, Transport());
            } catch (e) {
              bad.add('씨앗 $seed · 「${s.name}」 이 안 열린다: $e');
              break;
            }
          }
          // 남은 파일이 목록과 맞는가 (고아 파일 = 지운 곡이 안 지워진 것)
          final files = Directory('${dir.path}/songs')
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith('.json'))
              .length;
          if (files != st2.songs.length) {
            bad.add('씨앗 $seed · 파일 $files개 ≠ 목록 ${st2.songs.length}개');
          }
        }
        st2.detach();
      }
      await dir.delete(recursive: true);
      if (bad.isNotEmpty) break;
    }

    check(
      '곡을 막 다뤄도 안 어긋난다',
      bad.isEmpty,
      bad.isEmpty ? '20벌 × 100가지 = $steps걸음 + 껐다 켜기' : '\n  ${bad.first}',
    );

    // ignore: avoid_print
    print(fail == 0 ? '곡 저장 막 써 보기 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
