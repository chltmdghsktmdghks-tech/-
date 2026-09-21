// **곡 파일 가져오기** — 「파일로 꺼내기」의 짝.
//   flutter test test/import_check_test.dart
//
// 꺼내기만 있으면 백업이 반쪽이다. 그런데 가져오기는 **잃는 쪽으로 틀리기 쉬운**
// 기능이라 지킬 것이 셋이다:
//  1) 절대 덮어쓰지 않는다 — 「가져왔더니 내 곡이 없어졌다」보다 나쁜 결과는 없다
//  2) 곡 파일이 아니면 아무것도 안 만든다 — 고르는 창에서는 사진도 고를 수 있다
//  3) 가져온 곡이 **원본 그대로**여야 한다 — 이름만 같고 내용이 다르면 백업이 아니다
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/store.dart';

Store _store(Directory dir, Project p) => Store(
  project: p,
  transport: Transport(),
  live: LiveChannel(),
  master: MasterChannel(),
  overrideDir: dir,
);

void main() {
  test('곡 파일 가져오기', () async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $what — $detail');
      if (!ok) fail++;
    }

    // ── 내보낼 곡 하나를 만든다 ──
    final dirA = await Directory.systemTemp.createTemp('mdimpA');
    final pa = Project.initial();
    final sa = _store(dirA, pa);
    await sa.start();
    pa.setGenre('citypop');
    pa.name = '보낼 곡';
    pa.tracks.first.vol = 0.37;
    pa.setSceneCritter(0, '@hero');
    await sa.saveNow();
    final raw = await sa.exportJson(sa.currentId!);
    check(
      '0) 꺼내진다',
      raw != null && raw.contains('보낼 곡'),
      '${raw?.length ?? 0}자',
    );

    // ── 다른 폰(다른 폴더)에서 가져온다 ──
    final dirB = await Directory.systemTemp.createTemp('mdimpB');
    final pb = Project.initial();
    final sb = _store(dirB, pb);
    await sb.start();
    pb.setGenre('lofi');
    pb.name = '원래 있던 곡';
    pb.tracks.first.vol = 0.91;
    await sb.saveNow();
    final beforeId = sb.currentId!;
    final beforeCount = sb.songs.length;

    // 1) 곡 파일이 아니면 아무것도 안 만든다
    {
      final bad = [
        '',
        '그냥 글자',
        '{"a":1}',
        '[1,2,3]',
        '{"scenes":"씬이 목록이 아니다","tracks":[]}',
      ];
      var ok = true;
      var detail = '';
      for (final b in bad) {
        final m = await sb.importJson(b);
        if (m != null || sb.songs.length != beforeCount) {
          ok = false;
          detail = '「$b」 에서 곡이 생겼다';
          break;
        }
      }
      check('1) 곡 파일이 아니면 안 만든다', ok, ok ? '${bad.length}가지 모두' : detail);
    }

    // 2) 가져오면 곡이 늘고 **원래 곡은 그대로 있다**
    final meta = await sb.importJson(raw!);
    check(
      '2) 곡이 하나 늘었다',
      meta != null && sb.songs.length == beforeCount + 1,
      '${sb.songs.length}개',
    );
    check(
      '2-b) 원래 곡이 그대로 있다',
      sb.songs.any((s) => s.id == beforeId),
      '원래 곡 ${sb.songs.where((s) => s.id == beforeId).length}개',
    );
    check(
      '2-c) 원래 곡을 덮어쓰지 않았다',
      meta != null && meta.id != beforeId,
      '새 id ${meta?.id} · 옛 id $beforeId',
    );

    // 3) 가져온 곡이 **열려 있고 내용이 원본 그대로**다
    check('3) 가져온 곡이 열려 있다', sb.currentId == meta!.id, '${sb.current?.name}');
    check(
      '3-b) 내용이 원본 그대로',
      pb.genre == 'citypop' &&
          (pb.tracks.first.vol - 0.37).abs() < 1e-9 &&
          pb.scenes[0].critter == '@hero',
      '${pb.genre} · 볼륨 ${pb.tracks.first.vol} · 캐릭터 ${pb.scenes[0].critter}',
    );

    // 3-c) 목록에 **길이**가 적혔는가 — 안 적히면 목록에서 그 곡만 길이가 빈다
    check('3-c) 길이가 적혔다', meta.sec > 0, '${meta.sec.toStringAsFixed(1)}초');

    // 4) 같은 것을 **또** 가져오면 이름이 겹치지 않게 번호가 붙는다
    {
      final again = await sb.importJson(raw);
      check(
        '4) 이름이 겹치면 번호를 붙인다',
        again != null && again.name != meta.name,
        '${meta.name} → ${again?.name}',
      );
      check(
        '4-b) 곡이 또 하나 늘었다',
        sb.songs.length == beforeCount + 2,
        '${sb.songs.length}개',
      );
    }

    // 5) 껐다 켜도 남는가 — 목록(index)에 안 적혔으면 다음에 앱을 켤 때 사라진다
    {
      final pc = Project.initial();
      final sc = _store(dirB, pc);
      await sc.start();
      check(
        '5) 껐다 켜도 남는다',
        sc.songs.length == beforeCount + 2 &&
            sc.songs.any((s) => s.name == meta.name),
        '${sc.songs.length}개 · ${[for (final s in sc.songs) s.name]}',
      );
    }

    // 6) 가져오기 **직전에 만지던 것**이 안 날아간다 — 열기 전에 저장해야 한다.
    {
      pb.name = '고치던 중';
      final editing = sb.currentId!;
      await sb.importJson(raw); // 저장 없이 바로 가져온다
      final pd = Project.initial();
      final sd = _store(dirB, pd);
      await sd.start();
      await sd.open(editing);
      check('6) 고치던 것이 안 날아간다', pd.name == '고치던 중', pd.name);
    }

    expect(fail, 0, reason: '$fail개 항목이 어긋났습니다');
  });
}
