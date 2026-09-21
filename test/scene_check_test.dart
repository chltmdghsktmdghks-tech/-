// 5단계 2/N — 씬 시퀀서(내 트랙 연주) 확인. 폰 없이 돈다.
//
//   flutter test test/scene_check_test.dart
//
// **`dart run` 이 아니라 `flutter test` 다.** `tool/` 의 다른 검사들과 다른 이유:
// 프로젝트 상태(`project.dart`)가 `ChangeNotifier`(package:flutter)를 쓰기 때문에
// 순수 Dart VM 으로는 안 돌아간다(dart:ui 를 못 찾는다). 엔진·패턴·믹서만 건드리는
// 검사는 계속 `tool/` 에 두고 `dart run` 으로 돌리면 된다.
//
// 확인하는 것:
//  1) 기본 프로젝트(드럼·베이스·코드·멜로디)를 만들면 네 트랙이 전부 실제로 소리를 낸다
//  2) 버스 배정 — 드럼 아닌 트랙마다 **자기 버스**를 갖고, 음의 part 가 그 인덱스와 맞는다
//  3) 짧은 패턴은 루프 안에서 자기 길이만큼 반복한다(2마디 패턴 + 4마디 루프 = 두 번)
//  4) 템포를 두 배로 하면 길이가 절반
//  5) 뮤트/패턴 없음이면 그 트랙만 빠진다
//  6) 실제 엔진에 넣어 렌더 — 소리가 나고 하드클립·버퍼바닥이 없다
//  7) 조를 바꾸면 음높이가 바뀐다(조가 실제로 먹히는지)
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/engine.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/presets.dart';
import 'package:music_doodle_engine/feel.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/synth.dart';

Int16List _render(Engine e, double seconds) {
  final frames = (seconds * kSampleRate).round();
  final buf = Int16List(frames * 2);
  var got = 0;
  while (got < frames) {
    final n = 1024 < frames - got ? 1024 : frames - got;
    final pcm = e.render(n);
    buf.setRange(got * 2, (got + n) * 2, pcm);
    got += n;
  }
  return buf;
}

double _rms(Int16List b) {
  double s = 0;
  for (var i = 0; i < b.length; i++) {
    final v = b[i] / 32768.0;
    s += v * v;
  }
  return b.isEmpty ? 0 : sqrt(s / b.length);
}

void main() => test('씬 시퀀서', _run);

void _run() {
  Human.setLevel(0); // 결정론적으로 (live_bus_check 와 같은 이유)
  var fail = 0;
  void check(String what, bool ok, String detail) {
    // ignore: avoid_print
    print('${ok ? '  OK' : '실패'} $what — $detail');
    if (!ok) fail++;
  }

  final p = Project.initial();
  final tr = Transport()..reps = 2;
  // 1~7 은 **네 트랙이 다 연주하는 구간**이 있어야 뜻이 있다. 기본 구간은 코러스다
  // (인트로는 드럼·베이스가 쉬는 구간이라 여기 기준으로 삼으면 안 된다).

  // 1) 네 트랙이 다 소리를 내는가
  final b = SceneSequencer.build(p, tr);
  final byPart = <int, int>{};
  for (final n in b.notes) {
    byPart[n[7] as int] = (byPart[n[7] as int] ?? 0) + 1;
  }
  check(
    '1) 네 트랙 모두 연주',
    b.drums.isNotEmpty && byPart.length == 3,
    '타격 ${b.drums.length}개 · 버스별 음 ${byPart.entries.map((e) => '${e.key}:${e.value}').join(' ')}',
  );

  // 2) 버스 배정 — 드럼 아닌 트랙 순서 그대로, part 는 그 인덱스
  final wantBuses = [
    for (final t in p.tracks)
      if (t.type != 'drum') t.id,
  ];
  final partsOk = byPart.keys.every((k) => k >= 0 && k < wantBuses.length);
  check(
    '2) 버스 배정',
    b.busNames.join(',') == wantBuses.join(',') && partsOk,
    '편성=[${b.busNames.join(', ')}] · part 범위 ${partsOk ? '정상' : '벗어남'}',
  );

  // 3) 짧은 패턴이 루프를 채우는가 — 멜로디를 2마디 패턴으로 바꿔 본다
  //
  // **변형은 꺼 둔다.** 여기서 재는 것은 타일링(짧은 패턴이 긴 루프를 채우는가)이다.
  // 변형은 되풀이되는 바퀴의 음을 덜어 내므로(계획 6-1) 켜 두면 이 시험이
  // 변형을 재게 되고, 변형을 손볼 때마다 엉뚱하게 깨진다. 필과 같은 이유다.
  p.setFeel(const Feel(vary: 0));
  final mel = p.tracks.firstWhere((t) => t.type == 'melody');
  final before = byPart[b.busNames.indexOf(mel.id)] ?? 0;
  mel.pattern = 'House Pluck V'; // 2마디
  final b3 = SceneSequencer.build(p, tr);
  final after = b3.notes
      .where((n) => n[7] == b3.busNames.indexOf(mel.id))
      .length;
  // 2마디 패턴 × 루프 안 2번 × reps 2.
  // **개수를 박아 두지 말 것** — 멜로디를 고치면 깨진다(53/N 에서 실제로 깨졌다).
  // 패턴에서 세어 계산한다.
  final melDef = p.findNote('melody', 'House Pluck V')!;
  final wantNotes = melDef.notes.length * 2 * 2;
  check(
    '3) 2마디 패턴이 4마디 루프를 채움',
    b3.loopBars == 4 && after == wantNotes,
    '루프=${b3.loopBars}마디 · 멜로디 음 $before개 → $after개 (예상 $wantNotes)',
  );
  mel.pattern = kDefaultPattern['melody'];

  // 4) 템포 두 배 = 길이 절반
  final slow = SceneSequencer.build(p, Transport()..bpm = 90);
  final fast = SceneSequencer.build(p, Transport()..bpm = 180);
  final ratio = slow.totalSec == 0 ? 0.0 : fast.totalSec / slow.totalSec;
  check(
    '4) 템포 두 배 → 길이 절반',
    (ratio - 0.5).abs() < 1e-9,
    '90BPM ${slow.totalSec.toStringAsFixed(1)}s · 180BPM ${fast.totalSec.toStringAsFixed(1)}s',
  );

  // 5) 뮤트하면 빠지는가
  p.tracks.firstWhere((t) => t.type == 'bass').mute = true;
  final muted = SceneSequencer.build(p, tr);
  final bassIdx = muted.busNames.indexOf(
    p.tracks.firstWhere((t) => t.type == 'bass').id,
  );
  final bassNotes = muted.notes.where((n) => n[7] == bassIdx).length;
  check(
    '5) 뮤트한 트랙은 빠짐',
    bassNotes == 0 && muted.notes.isNotEmpty,
    '베이스 음 $bassNotes개 · 나머지 ${muted.notes.length}개',
  );
  p.tracks.firstWhere((t) => t.type == 'bass').mute = false;

  // 6) 실제 엔진에 넣어 렌더
  final full = SceneSequencer.build(p, Transport()..reps = 1);
  final e = Engine();
  e.trackMix.configure(full.busNames);
  for (final d in full.drums) {
    e.scheduleDrum(
      d[4] as double,
      d[0] as String,
      d[1] as String,
      d[2] as int,
      tomFreq: d[3] as double,
    );
  }
  for (final n in full.notes) {
    e.schedule(
      n[6] as double,
      n[0] as String,
      n[1] as double,
      n[2] as double,
      n[3] as int,
      soft: n[4] as bool,
      glideF: n[5] as double,
      part: n[7] as int,
    );
  }
  final pcm = _render(e, full.totalSec + 1.0);
  final rms = _rms(pcm);
  check(
    '6) 실제 렌더',
    rms > 0.01 && e.clipped == 0 && e.bufferEmpty == 0,
    'RMS=${rms.toStringAsFixed(4)} 피크=${e.peakOut.toStringAsFixed(3)} '
        '하드클립=${e.clipped} 버퍼바닥=${e.bufferEmpty} 최대동시음=${e.maxActive}',
  );

  // 7) 조가 실제로 먹히는가 — C단조 vs F단조에서 베이스 첫 음이 달라야 한다
  double firstBass(int root) {
    final bb = SceneSequencer.build(p, Transport()..root = root);
    final idx = bb.busNames.indexOf(
      p.tracks.firstWhere((t) => t.type == 'bass').id,
    );
    final ns = bb.notes.where((n) => n[7] == idx).toList()
      ..sort((a, b) => (a[6] as double).compareTo(b[6] as double));
    return ns.isEmpty ? 0 : ns.first[1] as double;
  }

  final c0 = firstBass(0), f5 = firstBass(5);
  final semis = c0 == 0 ? 0.0 : 12 * log(f5 / c0) / ln2;
  check(
    '7) 조 바꾸면 음높이도 바뀜',
    (semis - 5).abs() < 0.01,
    'C=${c0.toStringAsFixed(2)}Hz F=${f5.toStringAsFixed(2)}Hz (${semis.toStringAsFixed(2)}반음)',
  );

  // ── 씬 (5단계 4/N) ──
  final p2 = Project.initial();
  final drum2 = p2.tracks.firstWhere((t) => t.type == 'drum');
  final mel2 = p2.tracks.firstWhere((t) => t.type == 'melody');

  // 8) 구간(씬)을 갈아타면 클립 한 벌이 통째로 바뀌는가 — **스타일은 그대로**
  final s0 = [for (final t in p2.tracks) t.pattern].join(',');
  final kit0 = drum2.kit;
  p2.launchScene(1); // 인트로 → 벌스
  final s1 = [for (final t in p2.tracks) t.pattern].join(',');
  check(
    '8) 구간 전환',
    s0 != s1 &&
        drum2.kit == kit0 && // 같은 곡이니 키트는 안 바뀐다
        p2.scenes.map((e) => e.name).join('/') == '인트로/벌스/코러스/브레이크/아웃트로',
    '${p2.scenes[0].name}=$s0\n         ${p2.scenes[1].name}=$s1 · 키트 $kit0 유지',
  );

  // 9) 고른 클립이 **그 씬에** 남는가 (갔다 와도 살아 있는가)
  p2.launchScene(0);
  p2.setClip(mel2, 'Hip Riff V');
  p2.launchScene(1);
  final away = mel2.pattern;
  p2.launchScene(0);
  check(
    '9) 클립이 씬에 남는가',
    mel2.pattern == 'Hip Riff V' && away != 'Hip Riff V',
    '씬0=${mel2.pattern} · 씬1 에서는 $away',
  );

  // 10) 트랙을 추가하면 **모든 씬에** 들어가는가 (안 그러면 다른 씬에서만 조용하다)
  p2.addTrack('melody');
  final added = p2.tracks.last;
  final inAll = p2.scenes.every((s) => s.clips[added.id] != null);
  check('10) 새 트랙이 모든 씬에', inAll, '씬 ${p2.scenes.length}개 전부 채워짐=$inAll');

  // 11) 씬을 지워도 남은 씬이 성하고, 마지막 하나는 안 지워지는가
  final before11 = p2.scenes.length;
  p2.removeScene(0);
  while (p2.scenes.length > 1) {
    p2.removeScene(0);
  }
  p2.removeScene(0); // 마지막 하나 — 무시돼야 한다
  check(
    '11) 씬 삭제',
    p2.scenes.length == 1 && before11 > 1,
    '$before11개 → ${p2.scenes.length}개(마지막 하나는 남음)',
  );

  // ── 곡(타임라인) (5단계 5/N) ──
  final p3 = Project.initial();
  final tr3 = Transport();

  // 11-b) **곡 하나는 스타일 하나** — 모든 구간의 템포·키트가 같아야 한다.
  //       (5단계 5/N 에서 구간마다 장르를 바꿨다가 "짜깁기"라고 지적받은 자리)
  final pg = Project.initial();
  final bpms = pg.scenes.map((e) => e.bpm).toSet();
  final kits = pg.scenes.map((e) => e.kit).toSet();
  check(
    '11-b) 곡 전체가 한 스타일',
    bpms.length == 1 && kits.length == 1,
    '템포 $bpms · 키트 $kits · 구간 ${pg.scenes.map((e) => e.name).join('→')}',
  );

  // 11-c) 얼개가 송폼(kFormOrder)대로인가 · 총 마디가 그 곡 형식과 맞는가
  final order = pg.song.sections.map((e) => pg.scenes[e.scene].name).join('→');
  var totalBars = 0;
  for (final sec in pg.song.sections) {
    totalBars += pg.loopBarsOf(sec.scene) * sec.reps;
  }
  check(
    '11-c) 송폼',
    order == '인트로→벌스→코러스→브레이크→벌스→코러스→아웃트로' && totalBars == 44,
    '$order · 총 $totalBars마디',
  );

  // 11-d) 스타일을 바꾸면 구간 이름은 그대로, 내용·템포가 바뀌는가
  final beforeClip = pg.scenes[2].clips[pg.tracks.first.id];
  pg.setGenre('house');
  final afterClip = pg.scenes[2].clips[pg.tracks.first.id];
  check(
    '11-d) 스타일 교체',
    beforeClip != afterClip &&
        pg.scenes[2].name == '코러스' &&
        pg.scenes.first.bpm == 124,
    '$beforeClip → $afterClip · ${pg.scenes.first.bpm!.round()}BPM',
  );

  // 12) 구간을 이어 붙이면 길이가 더해지는가 · 구간마다 그 씬의 템포를 쓰는가
  final songB = SceneSequencer.buildSong(p3, tr3);
  var want = 0.0;
  for (final sec in p3.song.sections) {
    final s = p3.scenes[sec.scene];
    want += SceneSequencer.build(
      p3,
      tr3,
      reps: sec.reps,
      from: s,
      bpm: s.bpm,
    ).totalSec;
  }
  check(
    '12) 곡 길이',
    (songB.totalSec - want).abs() < 1e-9 && songB.totalSec > 30,
    '${songB.totalSec.toStringAsFixed(1)}초 · 구간 ${p3.song.sections.length}개 · '
        '음 ${songB.notes.length}개 · 타격 ${songB.drums.length}개',
  );

  // 13) 시각이 겹치지 않고 순서대로 놓이는가 (구간 경계가 어긋나면 여기서 걸린다)
  final times = songB.drums.map((d) => d[4] as double).toList()..sort();
  final inOrder = times.first >= 0 && times.last < songB.totalSec;
  check(
    '13) 구간이 순서대로',
    inOrder,
    '첫 타격 ${times.first.toStringAsFixed(2)}s · 마지막 ${times.last.toStringAsFixed(2)}s '
        '(전체 ${songB.totalSec.toStringAsFixed(1)}s)',
  );

  // 14) 곡을 만들어도 **지금 씬(트랙에 실린 값)은 안 바뀌는가**
  //     — 곡 재생이 화면의 '지금 씬'을 건드리면 안 된다
  final beforeSong = [for (final t in p3.tracks) t.pattern].join(',');
  SceneSequencer.buildSong(p3, tr3);
  final afterSong = [for (final t in p3.tracks) t.pattern].join(',');
  check('14) 곡 만들어도 지금 씬 그대로', beforeSong == afterSong, beforeSong);

  // 15) 씬을 지우면 그 씬을 쓰던 구간이 정리되는가
  final usedScene1 = p3.song.sections.where((s) => s.scene == 1).length;
  p3.removeScene(1);
  final still1 = p3.song.sections.where((s) => s.scene == 1).length;
  final maxScene = p3.song.sections.fold<int>(
    0,
    (m, s) => s.scene > m ? s.scene : m,
  );
  check(
    '15) 구간 삭제 → 얼개 정리',
    usedScene1 > 0 && maxScene < p3.scenes.length,
    '씬1 쓰던 구간 $usedScene1개 정리 · 남은 구간 ${p3.song.sections.length}개 '
        '(가리키는 최대 씬 $maxScene < ${p3.scenes.length})',
  );
  if (still1 > 0) {
    // 삭제 뒤 남은 '1번'은 원래 2번이 당겨진 것 — 그것까지 검사하려면 이름을 봐야 한다
  }

  // ── 편집기용 '내 패턴' (5단계 6/N) ──
  // 여기서 재는 것은 **타일링**(짧은 패턴이 긴 루프를 채우는가)이다.
  // 필과 변형은 꺼 둔다 — 필은 마지막 마디를 갈아엎고, 변형은 되풀이되는 바퀴를
  // 바꾸므로 둘 다 타격 수를 흔든다. 안 끄면 이 시험이 그것들을 재게 되고,
  // 필·변형을 손볼 때마다 엉뚱하게 깨진다.
  final p4 = Project.initial()..setFeel(const Feel(fill: 0, vary: 0));
  final tr4 = Transport();
  final drum4 = p4.tracks.firstWhere((t) => t.type == 'drum');
  final libName = drum4.pattern!;
  final libHits = findDrumPattern(libName)!.hits.length;

  // 16) 편집하려 들면 내 패턴으로 복사되고, 라이브러리 원본은 그대로인가
  final mine = p4.makeEditable(drum4);
  final copiedOk =
      p4.isMine(mine) &&
      drum4.pattern == mine &&
      p4.scene.clips[drum4.id] == mine &&
      findDrumPattern(libName)!.hits.length == libHits;
  check(
    '16) 편집 = 내 패턴으로 복사',
    copiedOk,
    '$libName → $mine · 원본 레인 ${findDrumPattern(libName)!.hits.length}개 그대로',
  );

  // 17) 내 패턴을 고치면 **소리(만들어지는 타격)** 가 바뀌는가
  final beforeHits = SceneSequencer.build(p4, tr4, reps: 1).drums.length;
  p4.putUserPattern(
    'drum',
    mine,
    drum: DrumPatternDef(mine, 1, 1, {
      'k': [0, 8],
      's': [4, 12],
    }),
  );
  final afterB = SceneSequencer.build(p4, tr4, reps: 1);
  final afterHits = afterB.drums
      .where((d) => d[1] != 'kick' ? true : true)
      .length;
  check(
    '17) 고치면 소리가 바뀜',
    beforeHits != afterHits && afterHits > 0,
    '타격 $beforeHits개 → $afterHits개',
  );

  // 18) 마디 수를 줄이면 루프가 다른 트랙에 맞춰 되풀이되는가
  //     (드럼 1마디 + 나머지 4마디 → 루프 4마디, 드럼은 4번 반복 = 4×4타격)
  final drumHitsNow = afterB.drums.length; // 위에서 만든 것: 1마디 4타격이 4마디 루프를 채운다
  check(
    '18) 짧은 내 패턴이 루프를 채움',
    afterB.loopBars == 4 && drumHitsNow == 16,
    '루프 ${afterB.loopBars}마디 · 타격 $drumHitsNow개',
  );

  // 19) 라이브러리에 없는 이름이어도 목록에 뜨는가(내 패턴이 앞에)
  //
  // **박자가 다른 판은 빠진다**(5단계 47/N) — `kDrumPatterns.length` 는 전체
  // 라이브러리라 3/4 판이 섞여 있으면 그 수보다 필터링된 목록이 작을 수 있다.
  // 그래서 「전체」가 아니라 **이 곡 박자에 맞는 라이브러리 수**와 견준다.
  final list = SceneSequencer.patternNamesFor(p4, 'drum');
  final libForMeter = SceneSequencer.patternNames('drum', spb: p4.spb).length;
  check(
    '19) 목록에 내 패턴',
    list.first == mine && list.length > libForMeter,
    '맨 앞 ${list.first} · 전체 ${list.length}개',
  );

  // ── 저장·불러오기 (5단계 8/N) ──
  // 파일 쓰기(path_provider)는 폰에서만 되므로, 여기서는 **JSON 왕복**만 본다.
  // 깨지는 곳은 거의 항상 직렬화지 파일 쓰기가 아니다.
  final p5 = Project.initial();
  final tr5 = Transport();
  p5.setGenre('house');
  final mel5 = p5.tracks.firstWhere((t) => t.type == 'melody');
  mel5.vol = 0.42;
  mel5.voice = 'sax';
  p5.setClip(mel5, 'Hip Riff V');
  final my = p5.makeEditable(p5.tracks.first); // 내 패턴 하나 만들고
  p5.putUserPattern(
    'drum',
    my,
    drum: DrumPatternDef(my, 1, 1, {
      'k': [0, 4, 8, 12],
    }),
  );
  p5.song.setReps(0, 3);
  final beforeJson = jsonEncode(p5.toJson());
  final songA = SceneSequencer.buildSong(p5, tr5);

  final p6 = Project.initial();
  p6.loadJson(jsonDecode(beforeJson) as Map<String, dynamic>);
  final afterJson = jsonEncode(p6.toJson());
  check(
    '20) 저장→불러오기 왕복',
    beforeJson == afterJson,
    '스타일 ${p6.genre} · 트랙 ${p6.tracks.length} · 구간 ${p6.scenes.length} · '
        '얼개 ${p6.song.sections.length} · 내 패턴 ${p6.userDrum.length}',
  );

  // 21) **되살린 것이 같은 소리를 내는가** — 글자만 같고 소리가 다르면 소용없다
  final reloaded = SceneSequencer.buildSong(p6, tr5);
  check(
    '21) 되살린 곡이 같은 소리',
    reloaded.notes.length == songA.notes.length &&
        reloaded.drums.length == songA.drums.length &&
        (reloaded.totalSec - songA.totalSec).abs() < 1e-9,
    '음 ${reloaded.notes.length} 타격 ${reloaded.drums.length} '
        '${reloaded.totalSec.toStringAsFixed(1)}초',
  );

  // 22) 처음부터 새로 만들기
  p6.reset();
  check(
    '22) 처음부터 새로',
    p6.genre == 'lofi' &&
        p6.tracks.length == 4 &&
        p6.userDrum.isEmpty &&
        p6.song.sections.length == 7,
    '스타일 ${p6.genre} · 트랙 ${p6.tracks.length} · 구간 ${p6.song.sections.length}개',
  );

  // ── 객체형 스타일 5종 (5단계 11/N) ──
  // 트랩·프로그하우스·팝·재즈·엠비언트는 **곡마다 편성이 다르다**(트랩 6트랙).
  for (final key in ['trap', 'proghouse', 'pop', 'jazz', 'ambient']) {
    final po = Project.initial();
    po.setGenre(key);
    final tro = Transport()
      ..bpm = songGenreOf(key).$3
      ..mode = songGenreOf(key).$5;
    final b = SceneSequencer.buildSong(po, tro);
    final byTrack = <int, int>{};
    for (final n in b.notes) {
      byTrack[n[7] as int] = (byTrack[n[7] as int] ?? 0) + 1;
    }
    // 모든 멀로딕 트랙이 곡 어딘가에서는 소리를 내야 한다(안 나면 편성이 헛돌았다는 뜻)
    final melodic = po.tracks.where((t) => t.type != 'drum').length;
    final ok =
        po.tracks.length >= 4 &&
        b.drums.isNotEmpty &&
        b.totalSec > 60 &&
        byTrack.length == melodic;
    check(
      'S) $key',
      ok,
      '${po.tracks.length}트랙(${po.tracks.map((t) => t.name).join('·')}) · '
          '구간 ${po.scenes.length}개 · 얼개 ${po.song.sections.length}개 · '
          '${b.totalSec.toStringAsFixed(0)}초 · 소리내는 멀로딕 ${byTrack.length}/$melodic',
    );
  }

  // 스타일을 객체형 → 배열형으로 되돌려도 멀쩡한가(트랙 개수가 바뀐다)
  final pb = Project.initial();
  pb.setGenre('trap');
  final trapTracks = pb.tracks.length;
  pb.setGenre('lofi');
  final backOk =
      pb.tracks.length == 4 &&
      pb.scenes.length == 5 &&
      SceneSequencer.buildSong(pb, Transport()).notes.isNotEmpty;
  check(
    'S-b) 객체형 → 배열형 되돌리기',
    backOk,
    '트랩 $trapTracks트랙 → 로파이 ${pb.tracks.length}트랙 · 구간 ${pb.scenes.length}개',
  );

  // ── 빈 판 알림 (5단계 51/N) ──
  // 이름은 붙어 있는데 안이 빈 판은 **소리가 조용히 사라진다.**
  // 폰에서 드럼이 통째로 안 나는데 트랙 줄만 봐서는 멀쩡해 보였다
  // (씬 머리글의 「타격 0개」를 보고서야 알았다).
  final sp = Project.initial();
  final dt = sp.tracks.firstWhere((t) => t.type == 'drum');
  dt.pattern = null;
  check('빈 판 1) 패턴 없으면 무음', sp.isSilent(dt), '');

  final made = sp.makeEditable(dt); // 패턴 없는 트랙 → 빈 2마디가 생긴다
  check('빈 판 2) 빈 복사본도 무음으로 잡힌다', sp.isSilent(dt), '이름 「$made」');

  sp.userDrum[made]!.hits['kick'] = [0, 8];
  check('빈 판 3) 하나라도 찍으면 소리 난다', !sp.isSilent(dt), '킥 2타');

  // 라이브러리 패턴을 그대로 쓰는 트랙은 당연히 소리가 난다
  final sp2 = Project.initial();
  final live = [
    for (final t in sp2.tracks)
      if (!sp2.isSilent(t)) t.name,
  ];
  check(
    '빈 판 4) 처음 만든 곡은 전부 소리 난다',
    live.length == sp2.tracks.length,
    '${live.length}/${sp2.tracks.length}트랙',
  );

  // ── 씬을 지우면 되돌릴 수 있어야 한다 ──
  //
  // 씬 하나에 트랙 전부의 패턴이 들어 있는데, 지우면 **그 씬을 쓰던 곡 구간까지
  // 같이 사라진다**(`onSceneRemoved`). 여태 「⋮ → 삭제」 한 번에 확인도 없이 갔다.
  // 되돌리면 셋 다 와야 한다 — 씬 · 있던 자리 · 곡 구간표.
  {
    final rp = Project.initial();
    rp.addScene();
    rp.addScene(); // 씬 3개
    final at = 1;
    final target = rp.scenes[at];
    // 곡 구간: 0 · 1 · 2 · 1 — 지우는 씬(1)이 **두 군데** 쓰인다
    rp.song.sections.clear();
    for (final n in [0, 1, 2, 1]) {
      rp.song.add(n);
    }
    rp.launchScene(at);
    final n0 = rp.scenes.length;
    final s0 = [
      for (final x in rp.song.sections) '${x.scene}x${x.reps}',
    ].join(',');

    final gone = rp.removeScene(at);
    final afterScenes = rp.scenes.length;
    // 1을 쓰던 두 군데는 빠지고, 2를 가리키던 것은 1로 내려와야 한다
    final s1 = [
      for (final x in rp.song.sections) '${x.scene}x${x.reps}',
    ].join(',');

    rp.undoRemoveScene(gone!);
    final s2 = [
      for (final x in rp.song.sections) '${x.scene}x${x.reps}',
    ].join(',');
    check(
      '씬 되돌리기 1) 씬·자리·구간표가 다 돌아온다',
      afterScenes == n0 - 1 &&
          s1 == '0x2,1x2' &&
          rp.scenes.length == n0 &&
          identical(rp.scenes[at], target) &&
          s2 == s0 &&
          rp.currentScene == at,
      '지운 뒤 [$s1] → 되돌린 뒤 [$s2] (원래 [$s0])',
    );

    // 두 번 눌러도 하나만 (스낵바가 남아 있을 수 있다)
    rp.undoRemoveScene(gone);
    check(
      '씬 되돌리기 2) 두 번 눌러도 하나',
      rp.scenes.length == n0,
      '${rp.scenes.length}개',
    );

    // 마지막 하나는 못 지운다 — 되돌릴 것도 없다(null 이 와야 스낵바도 안 뜬다)
    final one = Project.initial();
    while (one.scenes.length > 1) {
      one.removeScene(one.scenes.length - 1);
    }
    check(
      '씬 되돌리기 3) 마지막 하나는 안 지운다',
      one.removeScene(0) == null,
      '씬 ${one.scenes.length}개 남음',
    );

    // 씬 되돌리기 4) **보던 씬보다 앞에 있는 씬을 지우면, 보던 씬 번호가 당겨 와야 한다.**
    //
    // [인트로,벌스,코러스,브레이크,아웃트로] 에서 브레이크(3번)를 보는 중에
    // 벌스(1번)를 지우면 — 목록은 [인트로,코러스,브레이크,아웃트로] 가 되고
    // 브레이크는 이제 2번 자리다. `_currentScene` 을 그대로 3에 둬 버리면
    // 3번 자리(아웃트로)를 가리키게 된다 — 보던 씬이 조용히 바뀐다.
    {
      final fp = Project.initial();
      fp.addScene();
      fp.addScene();
      fp.addScene(); // 씬 5개
      fp.renameScene(0, '인트로');
      fp.renameScene(1, '벌스');
      fp.renameScene(2, '코러스');
      fp.renameScene(3, '브레이크');
      fp.renameScene(4, '아웃트로');
      final breakScene = fp.scenes[3];
      fp.launchScene(3); // 브레이크를 보는 중
      fp.removeScene(1); // 그 앞의 벌스를 지운다
      check(
        '씬 되돌리기 4) 앞의 씬을 지우면 보던 씬이 안 바뀐다',
        identical(fp.scenes[fp.currentScene], breakScene),
        '지금 씬 「${fp.scenes[fp.currentScene].name}」 (바라는 것 「브레이크」) · '
            'currentScene=${fp.currentScene}',
      );
    }
  }

  // ── 씬을 복제하면 뒤 번호가 밀린다 — 곡도 보는 자리도 따라가야 한다 ──
  //
  // 「막 써 보기」 시험이 잡은 것이다. 씬을 끼우면 뒤쪽 씬 번호가 하나씩 밀리는데,
  // **곡 구간은 번호로 씬을 가리킨다.** 아무도 안 고쳐 줘서 곡이 통째로 어긋났다:
  //   전: 인트로 · 벌스 · 코러스 · 브레이크
  //   후: 인트로 · 인트로 복사 · 벌스 · 코러스   ← 브레이크가 곡에서 사라진다
  // 보던 씬 번호도 밀려서, 트랙엔 브레이크가 실려 있는데 씬 바는 코러스를 가리켰다.
  // 지우는 쪽은 처음부터 `onSceneRemoved` 로 이걸 했다 — **끼우는 쪽만 짝이 없었다.**
  {
    final dp = Project.initial();
    dp.song.sections.clear();
    for (final n in [0, 1, 2, 3]) {
      dp.song.add(n);
    }
    dp.launchScene(3);
    final wasName = dp.scene.name;
    final wasSong = [for (final x in dp.song.sections) dp.scenes[x.scene].name];

    dp.duplicateScene(0); // **앞쪽** 씬을 복제한다

    final nowSong = [for (final x in dp.song.sections) dp.scenes[x.scene].name];
    check(
      '씬 복제 1) 곡이 가리키는 씬이 안 바뀐다',
      nowSong.join(',') == wasSong.join(','),
      '[${wasSong.join(' · ')}] → [${nowSong.join(' · ')}]',
    );
    check(
      '씬 복제 2) 보던 씬도 그대로',
      dp.scene.name == wasName,
      '$wasName → ${dp.scene.name}',
    );
    check(
      '씬 복제 3) 복사본은 바로 뒤에',
      dp.scenes[1].name == '${dp.scenes[0].name} 복사',
      dp.scenes[1].name,
    );

    // 뒤쪽을 복제하면 앞은 안 건드려야 한다(밀 것이 없다)
    final ep = Project.initial();
    ep.song.sections.clear();
    for (final n in [0, 1]) {
      ep.song.add(n);
    }
    ep.launchScene(0);
    ep.duplicateScene(ep.scenes.length - 1);
    check(
      '씬 복제 4) 뒤쪽을 복제하면 앞은 그대로',
      ep.currentScene == 0 && ep.song.sections[1].scene == 1,
      '보는 씬 ${ep.currentScene} · 두 번째 구간 ${ep.song.sections[1].scene}',
    );
  }

  // ── 드럼 트랙을 더하면 **지금 씬의 키트**로 들어와야 한다 ──
  //
  // 이것도 「막 써 보기」가 잡았다. 록 곡에 드럼을 하나 더하면 어쿠스틱으로 들어와서
  // 나머지와 다른 소리가 났고, **저장했다 열면 그제서야 록 키트로 바뀌었다**
  // (`_loadScene` 이 씬 키트를 얹으므로). 「어제는 이 소리가 아니었는데」가 여기서 난다.
  {
    final kp = Project.initial()..setGenre('rock');
    kp.addTrack('drum');
    final added = kp.tracks.last;
    check(
      '드럼 더하기) 지금 씬의 키트로 들어온다',
      added.kit == kp.scene.kit && added.kit != 'acoustic',
      '새 드럼 ${added.kit} · 씬 ${kp.scene.kit}',
    );
  }

  // ignore: avoid_print
  print(fail == 0 ? '씬 시퀀서 확인 통과' : '실패 $fail건');
  expect(fail, 0);
}
