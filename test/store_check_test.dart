// 5단계 10/N — 곡 여러 개(저장소) 확인.
//   flutter test test/store_check_test.dart
//
// `path_provider` 는 폰에서만 되지만, `Store` 에 폴더를 넣을 수 있게 열어 뒀으므로
// **임시 폴더로 진짜 파일을 쓰고 읽으며** 시험한다(가짜가 아니라 실물 경로다).
//
// 확인하는 것:
//  1) 처음 켜면 곡 하나가 생기고 그게 열려 있는가
//  2) 새 곡을 만들면 목록이 늘고, 서로 **내용이 섞이지 않는가**
//  3) 곡을 오가도 각자 내용이 남는가 (제일 중요 — 여기가 깨지면 만든 걸 잃는다)
//  4) 복제 · 이름 바꾸기 · 삭제(마지막 하나는 못 지움)
//  5) 옛 `project.json`(곡 하나 시절) 이 첫 곡으로 옮겨지는가
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genre_mix.dart';
import 'package:music_doodle_engine/presets.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/store.dart';
import 'package:music_doodle_engine/synth.dart' show Human;

Store _store(Directory dir, Project p) => Store(
  project: p,
  transport: Transport(),
  live: LiveChannel(),
  master: MasterChannel(),
  overrideDir: dir,
);

void main() {
  test('곡 여러 개', () async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final dir = await Directory.systemTemp.createTemp('mdstore');
    final p = Project.initial();
    final st = _store(dir, p);

    // 1) 처음 켜기
    await st.start();
    check(
      '1) 첫 실행',
      st.songs.length == 1 && st.currentId == st.songs.first.id,
      '곡 ${st.songs.length}개 · 열린 곡 ${st.current?.name}',
    );

    // 2) 새 곡 — 앞 곡과 섞이지 않아야 한다
    p.setGenre('house');
    p.tracks.first.vol = 0.33;
    await st.saveNow();
    final firstId = st.currentId!;
    await st.newSong(name: '두 번째');
    check(
      '2) 새 곡',
      st.songs.length == 2 &&
          p.genre == 'lofi' && // 새 곡은 기본값
          // 앞 곡에서 0.33 으로 내려 둔 게 안 따라와야 한다.
          // **1.0 이 아니라 「로파이가 정한 값」** 이 맞다 — 스타일마다 믹스가 다르다.
          (p.tracks.first.vol - kGenreMix['lofi']!.parts['drum']!.vol).abs() <
              1e-9,
      '곡 ${st.songs.length}개 · 새 곡 스타일 ${p.genre} · 드럼 볼륨 ${p.tracks.first.vol}',
    );

    // 3) 다시 첫 곡으로 — 아까 만진 게 남아 있어야 한다
    await st.open(firstId);
    check(
      '3) 곡을 오가도 내용 유지',
      p.genre == 'house' && (p.tracks.first.vol - 0.33).abs() < 1e-9,
      '스타일 ${p.genre} · 드럼 볼륨 ${p.tracks.first.vol}',
    );

    // 4) 복제 · 이름 바꾸기 · 삭제
    await st.duplicate(firstId);
    final dup = st.songs[1];
    await st.rename(dup.id, '복제본');
    final beforeDel = st.songs.length;
    await st.remove(dup.id);
    // 마지막 하나는 못 지운다
    while (st.songs.length > 1) {
      await st.remove(st.songs.last.id);
    }
    await st.remove(st.songs.first.id);
    check(
      '4) 복제·이름·삭제',
      beforeDel == 3 && st.songs.length == 1,
      '복제 후 $beforeDel개 → 지우고 ${st.songs.length}개(마지막 하나는 남음)',
    );

    // 4-b) **지운 곡을 되돌린다.** 여태는 「⋮ → 삭제」가 확인도 없이 곡을
    // 날렸다 — 바로 위 칸이 「복제」다. 만든 걸 잃는 것보다 나쁜 건 없다.
    // 되돌리면 **있던 자리에 · 내용 그대로 · 열려 있었으면 다시 열린 채로**
    // 와야 한다. 셋 중 하나라도 빠지면 되돌린 게 아니다.
    {
      final dirU = await Directory.systemTemp.createTemp('mdstoreU');
      final pu = Project.initial();
      final stu = _store(dirU, pu);
      await stu.start();
      await stu.newSong(name: '둘');
      await stu.newSong(name: '셋');
      // 가운데 것을 고르고, 알아볼 수 있게 스타일을 바꿔 둔다
      final mid = stu.songs.firstWhere((x) => x.name == '둘');
      await stu.open(mid.id);
      pu.setGenre('jazz');
      await stu.saveNow();
      final at = stu.songs.indexOf(mid);
      final n0 = stu.songs.length;

      final f = File('${dirU.path}/songs/${mid.id}.json');
      final hadFile = await f.exists(); // 경로가 맞는지부터 — 아니면 아래가 공염불
      final gone = await stu.remove(mid.id);
      final afterDel = stu.songs.length;
      final fileGone = hadFile && !await f.exists();

      await stu.undoRemove(gone!);
      final fileBack = await f.exists();
      final back = stu.songs.indexWhere((x) => x.id == mid.id);
      check(
        '4-b) 지운 곡을 되돌린다',
        gone.wasCurrent &&
            afterDel == n0 - 1 &&
            fileGone &&
            fileBack &&
            back == at &&
            stu.songs[back].name == '둘' &&
            stu.currentId == mid.id &&
            pu.genre == 'jazz',
        '자리 $at→$back · 이름 ${stu.songs[back].name} · 스타일 ${pu.genre} · '
            '열린 곡 ${stu.currentId == mid.id ? '그것' : '다른 것'}',
      );

      // 두 번 눌러도 하나만 돌아온다 (스낵바가 남아 있을 수 있다)
      await stu.undoRemove(gone);
      check(
        '4-c) 되돌리기를 두 번 눌러도 하나',
        stu.songs.length == n0,
        '${stu.songs.length}개',
      );
      await dirU.delete(recursive: true);
    }

    // 4-c2) **열려 있는 곡을 지워도 옆 곡이 안 덮인다.**
    //
    // `remove` 가 `currentId` 를 다음 곡으로 먼저 바꾼 다음 `open` 을 불렀다.
    // `open` 은 기본으로 지금 곡을 먼저 저장하는데, 그 저장이 **새 id** 를 읽고
    // **메모리에 남아 있는 지운 곡**을 그 파일에 썼다. 곡이 둘일 때 열린 쪽을
    // 지우면 남은 한 곡이 지운 곡의 내용·이름·장르로 바뀌었다 —
    // 되돌리기를 눌러도 살아나는 건 지운 곡뿐이라 **옆 곡은 영영 사라졌다.**
    //
    // 4-b 는 이걸 못 잡는다. 지운 곡만 보고 **살아남은 곡을 안 봤다.**
    {
      final dirX = await Directory.systemTemp.createTemp('mdstoreX');
      final px = Project.initial();
      final stx = _store(dirX, px);
      await stx.start();

      // 남을 곡 — 알아볼 수 있게 스타일을 박아 둔다
      final keep = stx.songs.first;
      await stx.open(keep.id);
      await stx.rename(keep.id, '지키는곡');
      px.setGenre('lofi');
      await stx.saveNow();

      // 지울 곡 — 다른 스타일로
      await stx.newSong(name: '지울곡');
      final drop = stx.songs.firstWhere((x) => x.name == '지울곡');
      await stx.open(drop.id);
      px.setGenre('trap');
      await stx.saveNow();

      final gone2 = await stx.remove(drop.id);
      final left = stx.songs.length == 1 ? stx.songs.first : null;
      final keepFile = File('${dirX.path}/songs/${keep.id}.json');
      Map<String, dynamic>? onDisk;
      if (await keepFile.exists()) {
        onDisk =
            jsonDecode(await keepFile.readAsString()) as Map<String, dynamic>;
      }
      check(
        '4-c2) 열린 곡을 지워도 남은 곡이 안 덮인다',
        gone2 != null &&
            left != null &&
            left.id == keep.id &&
            left.name == '지키는곡' &&
            left.genre == 'lofi' &&
            onDisk != null &&
            onDisk['genre'] == 'lofi' &&
            px.genre == 'lofi',
        '남은 곡 ${left?.name}/${left?.genre} · 파일 ${onDisk?['genre']} · '
            '화면 ${px.genre}',
      );
      await dirX.delete(recursive: true);
    }

    // 4-c3) **새 곡·초기화가 빠르기·조까지 그 스타일로 맞추는가.**
    //
    // `Project.reset()` 은 스타일만 갈아입힌다. 빠르기·조는 `Transport` 가 들고
    // 있어서, 안 맞추면 **앞 곡의 조가 새 곡에 그대로 남는다** — 팝(장조)에서
    // 새 곡을 만들면 로파이가 장조로 시작하고 그대로 저장된다. 소리는 나므로
    // 오류로는 안 잡힌다. 여태는 「곡 재생」이 누를 때마다 덮어 주고 있어서
    // 안 보였다(그 덮어쓰기가 사용자가 맞춰 둔 값까지 날리던 진짜 버그다).
    {
      final dirT = await Directory.systemTemp.createTemp('mdstoreT');
      final pt = Project.initial();
      final stt = _store(dirT, pt);
      await stt.start();
      // 장조 곡을 하나 만들어 둔다
      pt.setGenre('pop');
      stt.transport
        ..bpm = 106
        ..mode = 'major';
      await stt.saveNow();
      final popOk = stt.transport.mode == 'major';

      await stt.newSong(name: '새것');
      final gd = songGenreOf(pt.genre); // reset 은 lofi 로 간다
      final newOk =
          stt.transport.mode == gd.$5 &&
          (stt.transport.bpm - gd.$3).abs() < 0.01;

      // 초기화도 같은 자리다
      pt.setGenre('pop');
      stt.transport
        ..bpm = 106
        ..mode = 'major';
      await stt.resetCurrent();
      final resetOk =
          stt.transport.mode == gd.$5 &&
          (stt.transport.bpm - gd.$3).abs() < 0.01;

      check(
        '4-c3) 새 곡·초기화가 빠르기·조도 그 스타일로',
        popOk && newOk && resetOk,
        '새 곡 ${stt.project.genre}/${stt.transport.mode}/'
            '${stt.transport.bpm.round()}BPM (기대 ${gd.$5}/${gd.$3.round()})',
      );
      await dirT.delete(recursive: true);
    }

    // 4-c4) **라이브 이펙트가 곡마다 따로 남는가.**
    //
    // 마스터 인서트는 곡마다 남는데 라이브만 꽂을 자리가 아예 없었다 —
    // 엔진(`live` 붙박이 버스)은 처음부터 인서트를 들고 있었고 없던 건 화면뿐이다.
    // 저장은 **넣는 것**과 **비우는 것**이 짝이어야 한다: 앞 곡에 꽂아 둔 것이
    // 안 꽂은 곡에 남으면 마스터가 겪었던 그 병이 그대로 재현된다.
    {
      final dirF = await Directory.systemTemp.createTemp('mdstoreF');
      final pf = Project.initial();
      final stf = _store(dirF, pf);
      await stf.start();

      // 곡 A — 딜레이를 꽂는다
      final aId = stf.currentId!;
      stf.live
        ..addFx('delay')
        ..setFxParam(0, 'wet', 0.42);
      await stf.saveNow();

      // 곡 B — 아무것도 안 꽂는다
      await stf.newSong(name: '안 꽂은 곡');
      final emptied = stf.live.chain.isEmpty;
      await stf.saveNow();

      // 다시 A 로 — 꽂아 둔 것이 값까지 그대로 돌아온다
      await stf.open(aId);
      final back = stf.live.chain;
      final restored =
          back.length == 1 &&
          back.first.type == 'delay' &&
          ((back.first.p['wet'] ?? 0) - 0.42).abs() < 1e-9;

      // 다시 B 로 — 남아 있으면 안 된다
      final bId = stf.songs.firstWhere((x) => x.name == '안 꽂은 곡').id;
      await stf.open(bId);
      final cleared = stf.live.chain.isEmpty;

      check(
        '4-c4) 라이브 이펙트가 곡마다 따로 남는다',
        emptied && restored && cleared,
        '새 곡 비움 $emptied · 되돌아옴 $restored · 안 꽂은 곡 비움 $cleared',
      );
      await dirF.delete(recursive: true);
    }

    // 4-c5) **앱 설정(화면 방향·소리 품질·보는 방식)이 껐다 켜도 남는가.**
    //
    // 설정이 「이번 한 번」이면 그건 설정이 아니다. 곡이 아니라 앱에 딸린 값이라
    // `index.json` 에 같이 적는다. 모르는 값이 들어와도 안 죽어야 한다 —
    // 파일 하나가 앱을 못 열게 만드는 자리를 이 저장소에서 이미 겪었다.
    {
      final dirS = await Directory.systemTemp.createTemp('mdstoreS');
      final ps = Project.initial();
      final sts = _store(dirS, ps);
      await sts.start();
      final defaults =
          sts.orient == 'auto' && sts.highQuality && sts.songMode == 'list';

      await sts.setOrient('landscape');
      await sts.setHighQuality(false);
      await sts.setSongMode('timeline');
      await sts.setHuman(0);

      // 껐다 켠 것처럼 새 Store 로 다시 읽는다
      final st2 = _store(dirS, Project.initial());
      await st2.start();
      final kept =
          st2.orient == 'landscape' &&
          !st2.highQuality &&
          st2.songMode == 'timeline' &&
          st2.human == 0 &&
          // **켤 때 엔진에 바로 걸려야 한다** — 값만 남고 안 걸리면 설정이 아니다
          Human.t == 0;

      // 모르는 값은 기본으로 떨어진다
      await sts.setOrient('거꾸로');
      final safe = sts.orient == 'auto';

      check(
        '4-c5) 앱 설정이 껐다 켜도 남는다',
        defaults && kept && safe,
        '기본 $defaults · 왕복 ${st2.orient}/${st2.highQuality}/${st2.songMode}/'
            '흔들림${st2.human}(엔진 ${Human.t}) · 모르는 값 → ${sts.orient}',
      );
      Human.setLevel(0); // 다음 시험을 위해 되돌린다
      await dirS.delete(recursive: true);
    }

    // 4-c6) **곡을 파일로 꺼낼 수 있는가 — 그리고 그게 지금 것인가.**
    //
    // 곡은 앱 전용 폴더에만 있다. 앱을 지우거나 폰을 바꾸면 전곡이 사라진다.
    // 꺼낸 내용이 **마지막 저장 이후에 만진 것을 빼먹으면** 그건 백업이 아니다 —
    // 지금 열려 있는 곡은 꺼내기 전에 저장해야 한다.
    {
      final dirX = await Directory.systemTemp.createTemp('mdstoreX2');
      final px = Project.initial();
      final stx = _store(dirX, px);
      await stx.start();
      final id = stx.currentId!;

      // **저장하지 않고** 스타일만 바꾼다(자동 저장 0.8초는 안 지났다)
      px.setGenre('trap');
      final raw = await stx.exportJson(id);
      final j = raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
      final fresh = j != null && j['genre'] == 'trap';

      // 그 내용으로 새 저장소를 채우면 그대로 열린다(진짜 백업인지)
      final ok2 = j != null && (j['tracks'] as List?)?.isNotEmpty == true;

      // 모르는 id 는 null — 안 죽는다
      final none = await stx.exportJson('없는id');

      check(
        '4-c6) 곡을 파일로 꺼낸다 (지금 것으로)',
        fresh && ok2 && none == null,
        '스타일 ${j?['genre']} · 트랙 ${(j?['tracks'] as List?)?.length ?? 0}개 · '
            '모르는 id → ${none == null ? 'null' : '값 있음'}',
      );
      await dirX.delete(recursive: true);
    }

    // 4-d) **라이브 음색의 「내가 골랐나」가 왕복에서 살아남는가.**
    //
    // 여기가 조용히 죽어 있었다. 불러오기가 `live.voice = ...` 를 썼는데
    // 그 setter 는 「사용자가 골랐다」는 뜻이라 `voiceAuto` 를 꺼 버린다.
    // 자동 저장이 있으니 **모든 곡이** 한 번은 저장됐다 열린다 →
    // 장르별 라이브 기본 음색(계획 7)이 전부 죽어 있었다. 오류는 안 난다.
    {
      final dirL = await Directory.systemTemp.createTemp('mdlive');
      final pl = Project.initial();
      final liveL = LiveChannel();
      final stl = Store(
        project: pl,
        transport: Transport(),
        live: liveL,
        master: MasterChannel(),
        overrideDir: dirL,
      );
      await stl.start();
      await stl.saveNow();
      final idL = stl.currentId!;

      await stl.newSong(name: '딴 곡');
      await stl.open(idL);
      check(
        '4-d) 고른 적 없으면 왕복해도 장르가 정한다',
        liveL.voiceAuto,
        'voiceAuto=${liveL.voiceAuto} · 음색 ${liveL.voice}',
      );

      // 반대쪽도 지킨다 — 고르고 나면 왕복해도 **내 것**이어야 한다
      liveL.voice = 'sax';
      await stl.saveNow();
      await stl.newSong(name: '또 딴 곡');
      await stl.open(idL);
      check(
        '4-e) 고른 뒤엔 왕복해도 내 것',
        !liveL.voiceAuto && liveL.voice == 'sax',
        'voiceAuto=${liveL.voiceAuto} · 음색 ${liveL.voice}',
      );

      stl.detach();
      await dirL.delete(recursive: true);
    }

    // 4-f) **저장이 안 되면 조용히 넘어가지 않는다.**
    //
    // 여태 `saveNow` 는 실패를 삼키고 로그만 찍었다. 저장 공간이 꽉 찼거나 권한이
    // 사라지면 그때부터 아무것도 안 남는데, 사용자는 **앱을 껐다 켠 뒤에야** 안다.
    // 그때는 이미 늦었다 — 만든 걸 잃는 것보다 나쁜 건 없다.
    // 여기서는 쓸 자리에 **폴더를 놔서** 쓰기를 못 하게 만들고 세는지 본다.
    {
      final dirF = await Directory.systemTemp.createTemp('mdfail');
      final pf = Project.initial();
      final stf = Store(
        project: pf,
        transport: Transport(),
        live: LiveChannel(),
        master: MasterChannel(),
        overrideDir: dirF,
      );
      await stf.start();
      await stf.saveNow();
      final before = stf.saveFails;

      // 여기서는 **일부러** 실패시키므로 「저장 실패」 로그가 찍힌다 —
      // 전체 시험 출력이 안 읽히게 잠깐 막는다.
      final keepPrint = debugPrint;
      debugPrint = (String? _, {int? wrapWidth}) {};
      addTearDown(() => debugPrint = keepPrint);

      // index.json 자리에 폴더를 놓는다 → 그 뒤로 쓰기가 다 실패한다
      final idx = File('${dirF.path}/index.json');
      if (await idx.exists()) await idx.delete();
      await Directory('${dirF.path}/index.json').create();

      var told = 0;
      void onChange() => told++;
      stf.addListener(onChange);
      await stf.saveNow();
      check(
        '4-f) 저장이 안 되면 센다',
        before == 0 && stf.saveFails > 0 && told > 0,
        '실패 ${stf.saveFails}번 · 화면에 알림 $told번 · ${stf.lastSaveError?.split(',').first}',
      );

      // 다시 쓸 수 있게 되면 **스스로 0 으로 돌아간다** (안 그러면 경고가 안 사라진다)
      await Directory('${dirF.path}/index.json').delete();
      await stf.saveNow();
      check(
        '4-g) 고쳐지면 스스로 돌아온다',
        stf.saveFails == 0 && stf.lastSaveError == null,
        '실패 ${stf.saveFails}번',
      );

      // ── 4-h) 저장이 실패해도 **앞서 저장한 곡은 온전하다** ──
      //
      // 예전엔 파일에 곧장 썼다 — `writeAsString` 은 **먼저 비우고** 채운다.
      // 그 사이에 앱이 죽으면(안드로이드는 메모리가 모자라면 뒤 앱을 그냥 죽인다)
      // 반만 쓰인 JSON 이 남고, 그 곡은 못 읽는다. 이 앱은 만지는 족족 저장하니
      // 「쓰는 중」인 시간이 길다.
      //
      // 이제 옆에 다 쓰고 `rename` 으로 갈아 끼운다. 임시 파일 자리에 폴더를 놓으면
      // **새로 쓰는 것만** 실패하고 있던 파일은 손도 안 탄다 — 그걸 확인한다.
      {
        final songF = File('${dirF.path}/songs/${stf.currentId}.json');
        final good = await songF.readAsString();
        await Directory('${songF.path}.tmp').create(recursive: true);
        pf.name = '이 이름은 저장에 실패한다';
        await stf.saveNow();
        final after = await songF.readAsString();
        var readable = false;
        try {
          readable = jsonDecode(after) is Map;
        } catch (_) {
          readable = false;
        }
        check(
          '4-h) 저장이 실패해도 옛 곡 파일은 온전하다',
          after == good && readable && stf.saveFails > 0,
          '${after.length}자 · 읽힌다 $readable · 실패 ${stf.saveFails}번',
        );
        await Directory('${songF.path}.tmp').delete();
      }

      // 4-i) 임시 파일을 안 남긴다 — 성공했든 실패했든
      await stf.saveNow();
      final leftovers = Directory(
        '${dirF.path}/songs',
      ).listSync().where((e) => e.path.endsWith('.tmp')).toList();
      check(
        '4-i) 임시 파일을 안 남긴다',
        leftovers.isEmpty && stf.saveFails == 0,
        '남은 것 ${leftovers.length}개',
      );

      stf.removeListener(onChange);
      stf.detach();
      await dirF.delete(recursive: true);
    }

    // 5-b) 이름 칸이 없던 옛 파일도 이름이 남아야 한다 (자동 저장에 덮이지 않게)
    final dir3 = await Directory.systemTemp.createTemp('mdstore3');
    final noName = Project.initial().toJson()..remove('name');
    await File('${dir3.path}/project.json').writeAsString(jsonEncode(noName));
    final p3 = Project.initial();
    final st3 = _store(dir3, p3);
    await st3.start();
    await st3.saveNow(); // 첫 자동 저장이 이름을 덮지 않는가
    check(
      '5-b) 이름 없던 옛 파일',
      st3.songs.first.name == '내 곡' && p3.name == '내 곡',
      '${st3.songs.first.name}',
    );
    await dir3.delete(recursive: true);

    // 5) 옛 파일 마이그레이션
    final dir2 = await Directory.systemTemp.createTemp('mdstore2');
    final old = Project.initial();
    old.setGenre('rock');
    old.name = '옛날 곡';
    await File(
      '${dir2.path}/project.json',
    ).writeAsString(jsonEncode(old.toJson()));
    final p2 = Project.initial();
    final st2 = _store(dir2, p2);
    await st2.start();
    final bak = File('${dir2.path}/project.json.bak');
    check(
      '5) 옛 저장 파일 옮기기',
      st2.songs.length == 1 &&
          st2.songs.first.name == '옛날 곡' &&
          p2.genre == 'rock' &&
          await bak.exists(),
      '${st2.songs.first.name} · ${p2.genre} · 원본은 .bak 으로 보관됨',
    );

    // 6) **조성·템포가 없는 옛 파일은 그 곡의 스타일 기본값으로 열린다.**
    //
    // 예전엔 「지금 열려 있던 곡의 값」을 물려받았다. 그러면 장조 곡(팝·가스펠)을
    // 단조 곡을 보다가 열면 **코드가 전부 딴 것**이 된다 — 소리는 나므로
    // 오류로는 안 잡힌다. 가스펠(84BPM·장조)로 확인한다.
    {
      final dir3 = await Directory.systemTemp.createTemp('mdstore3');
      // ① 가스펠로 한 곡 저장한다
      final pa = Project.initial()..setGenre('gospel');
      pa.name = '옛 가스펠';
      final sa = Store(
        project: pa,
        transport: Transport()
          ..mode = 'major'
          ..bpm = 84,
        live: LiveChannel(),
        master: MasterChannel(),
        overrideDir: dir3,
      );
      await sa.start();
      await sa.saveNow();
      // ② 그 파일에서 조성·템포 칸을 지운다(옛 버전이 안 적던 칸)
      final songDir = Directory('${dir3.path}/songs');
      final f3 = songDir.listSync().whereType<File>().first;
      final raw = jsonDecode(await f3.readAsString()) as Map<String, dynamic>;
      raw.remove('mode');
      raw.remove('bpm');
      await f3.writeAsString(jsonEncode(raw));
      // ③ **단조 곡을 보다가** 그 파일을 연다
      final pb = Project.initial();
      final tb = Transport()
        ..mode = 'minor'
        ..bpm = 140;
      final sb = Store(
        project: pb,
        transport: tb,
        live: LiveChannel(),
        master: MasterChannel(),
        overrideDir: dir3,
      );
      await sb.start();
      check(
        '6) 조성 없는 옛 파일은 그 스타일의 조성으로',
        pb.genre == 'gospel' && tb.mode == 'major' && tb.bpm == 84,
        '${pb.genre} · ${tb.mode} · ${tb.bpm.round()}BPM',
      );
      await dir3.delete(recursive: true);
    }

    await dir.delete(recursive: true);
    await dir2.delete(recursive: true);

    // ignore: avoid_print
    print(fail == 0 ? '곡 여러 개 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
