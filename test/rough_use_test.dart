// **막 쓰다 보면 생기는 고장**을 찾는다 (씨앗 고정 · 재현 가능).
//   flutter test test/rough_use_test.dart
//
// 화면 시험은 한 화면 안의 한 가지 흐름을 본다. 사람은 그렇게 안 쓴다 —
// 스타일을 구경하다가 씬을 지우고, 트랙을 더하고, 판을 고치고, 되돌리고,
// 저장했다 다시 연다. **그 사이사이에 어긋나는 것**이 오래 남는 고장이 된다.
//
// 무작위지만 씨앗이 고정이라 실패하면 **같은 순서로 다시 난다**. 무엇을 했는지도
// 다 적어 두고 실패할 때만 찍는다.
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/edit_ops.dart';
import 'package:music_doodle_engine/tap_rec.dart';
import 'package:music_doodle_engine/engine.dart';
import 'package:music_doodle_engine/feel.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/theory.dart';

/// 씬을 실제로 **렌더해 본다** — 값이 아니라 **소리**가 성한지 본다.
/// 목록이 멀쩡해도 조합에 따라 NaN 이 나거나 통째로 뭉개질 수 있다.
String? _soundTrouble(Project p, Transport tr) {
  final b = SceneSequencer.build(p, tr);
  final e = Engine()..trackMix.configure(b.busNames);
  for (final d in b.drums) {
    e.scheduleDrum(
      (d[4] as num).toDouble(),
      d[0] as String,
      d[1] as String,
      d[2] as int,
      tomFreq: (d[3] as num).toDouble(),
    );
  }
  for (final n in b.notes) {
    e.schedule(
      (n[6] as num).toDouble(),
      n[0] as String,
      (n[1] as num).toDouble(),
      (n[2] as num).toDouble(),
      n[3] as int,
      soft: n[4] as bool,
      glideF: (n[5] as num).toDouble(),
      part: n[7] as int,
    );
  }
  // **첫 소리가 나는 데까지는 재야 한다.** 그냥 앞 6초만 재면, 30초 판에서
  // 첫 타격이 14초에 오는 성긴 씬을 「무음」으로 잘못 잡는다(여기서 겪었다).
  final firstAt =
      [
            for (final n in b.notes) (n[6] as num).toDouble(),
            for (final d in b.drums) (d[4] as num).toDouble(),
          ].fold<double>(0, math.max) <
          0
      ? 0.0
      : [
          for (final n in b.notes) (n[6] as num).toDouble(),
          for (final d in b.drums) (d[4] as num).toDouble(),
        ].fold<double>(1e9, math.min);
  final want = (firstAt >= 1e9 ? 4.0 : firstAt + 4.0);
  final total = (math.min(b.totalSec, want) * kSampleRate).round();
  var done = 0, clipped = 0;
  var peak = 0.0;
  while (done < total) {
    final n = math.min(1024, total - done);
    final pcm = e.render(n);
    for (var i = 0; i < n * 2; i++) {
      final v = pcm[i] / 32768.0;
      if (v.isNaN || v.isInfinite) return '소리에 NaN·무한대';
      final a = v.abs();
      if (a > peak) peak = a;
      if (a >= 0.9999) clipped++;
    }
    done += n;
  }
  if (clipped > 0) return '하드클립 $clipped샘플';
  // 판이 실려 있는데 아무 소리도 안 나면 그것도 탈이다
  final anyClip = p.tracks.any((t) => t.pattern != null && p.audible(t));
  if (anyClip && (b.notes.isNotEmpty || b.drums.isNotEmpty) && peak < 1e-4) {
    final first = [
      for (final n in b.notes) (n[6] as num).toDouble(),
      for (final d in b.drums) (d[4] as num).toDouble(),
    ].fold<double>(1e9, math.min);
    return '실린 판이 있는데 무음 — peak $peak · 판길이 ${b.totalSec}s · '
        '잰 구간 ${total / kSampleRate}s · 음 ${b.notes.length}개 드럼 ${b.drums.length}개 · '
        '첫 소리 ${first}s';
  }
  return null;
}

void main() {
  test('막 써 보기', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final genres = [for (final g in kGenres) g.key];
    final bad = <String>[];
    var steps = 0, rendered = 0;

    for (var seed = 1; seed <= 40; seed++) {
      final rnd = math.Random(seed);
      final p = Project.initial();
      final tr = Transport();
      final log = <String>[];

      String? trouble() {
        // ① 씬이 가리키는 트랙 id 가 실제로 있는가
        final ids = {for (final t in p.tracks) t.id};
        for (final s in p.scenes) {
          for (final k in s.clips.keys) {
            if (!ids.contains(k)) return '없는 트랙 id($k)를 가리키는 씬';
          }
        }
        // ② 곡 구간이 있는 씬을 가리키는가
        for (final sec in p.song.sections) {
          if (sec.scene < 0 || sec.scene >= p.scenes.length) {
            return '없는 씬(${sec.scene})을 가리키는 구간';
          }
        }
        // ③ 보고 있는 씬이 범위 안인가
        if (p.currentScene < 0 || p.currentScene >= p.scenes.length) {
          return '보는 씬이 범위 밖(${p.currentScene}/${p.scenes.length})';
        }
        // ④ 조가 아는 것인가
        if (!kScale.containsKey(tr.mode)) return '모르는 조(${tr.mode})';
        // ⑤ 소리가 나는가 — 씬도 곡도
        try {
          SceneSequencer.build(p, tr);
          SceneSequencer.buildSong(p, tr);
        } catch (e) {
          return '소리를 못 만든다: $e';
        }
        // ⑥ 씬이 실어 둔 판 이름이 **실제로 있는 판**인가.
        //    없는 이름이면 그 트랙은 조용히 안 난다 — 오류가 안 나는 종류다.
        for (final s in p.scenes) {
          for (final e in s.clips.entries) {
            final n = e.value;
            if (n == null) continue;
            final t = p.tracks.firstWhere(
              (x) => x.id == e.key,
              orElse: () => p.tracks.first,
            );
            if (!SceneSequencer.patternNamesFor(p, t.type).contains(n)) {
              return '없는 판을 실었다(${t.type} · $n)';
            }
          }
        }
        // ⑧ 타임라인 클립이 **있는 구간·있는 트랙·있는 판**을 가리키는가.
        //    구간을 끼우거나 지울 때 번호를 안 따라가면 딴 구간에서 소리가 난다.
        for (final c in p.song.lanes) {
          if (c.section < 0 || c.section >= p.song.sections.length) {
            return '없는 구간(${c.section})을 가리키는 클립';
          }
          if (c.bar < 0) return '마디가 음수인 클립(${c.bar})';
          final t = p.tracks.where((x) => x.id == c.trackId);
          if (t.isEmpty) return '없는 트랙(${c.trackId})을 가리키는 클립';
          if (!SceneSequencer.patternNamesFor(
            p,
            t.first.type,
          ).contains(c.pattern)) {
            return '없는 판을 가리키는 클립(${t.first.type} · ${c.pattern})';
          }
        }

        // ⑨ 음이 **제 좌표계 범위 안**인가. 도수 줄은 0~14, 반음 줄은 0~24,
        //    화음 줄은 0~6 이다. 넘으면 재생이 clamp 로 뭉개거나 딴 음이 난다.
        for (final e in p.userNote.entries) {
          final ty = p.userNoteType[e.key];
          final top = ty == 'chord' ? 6 : (e.value.chromatic ? 24 : 14);
          for (final n in e.value.notes) {
            final d = n[0] as int;
            if (d < 0 || d > top) {
              return '음이 줄 밖(${e.key} · $d, 위 $top)';
            }
          }
          // 덧줄은 본줄과 **반대**다 — 화음 판의 덧줄은 낱음(0~14).
          final altTop = ty == 'chord' ? 14 : 6;
          for (final n in e.value.also) {
            final d = n[0] as int;
            if (d < 0 || d > altTop) {
              return '덧줄 음이 줄 밖(${e.key} · $d, 위 $altTop)';
            }
          }
        }

        // ⑦ 저장했다 되살리면 **글자 하나까지** 같은가
        try {
          final j1 = p.toJson();
          final back = Project.initial()..loadJson(j1);
          final j2 = back.toJson();
          if (jsonEncode(j1) != jsonEncode(j2)) {
            final diff = <String>[];
            for (final k in j1.keys) {
              if (jsonEncode(j1[k]) != jsonEncode(j2[k])) {
                diff.add(
                  '$k\n       전: ${jsonEncode(j1[k])}\n       후: ${jsonEncode(j2[k])}',
                );
              }
            }
            return '왕복에서 달라진다 — ${diff.join(' / ')}';
          }
        } catch (e) {
          return '왕복에서 터진다: $e';
        }
        return null;
      }

      for (var i = 0; i < 100; i++) {
        final act = rnd.nextInt(24);
        switch (act) {
          case 0:
            final g = genres[rnd.nextInt(genres.length)];
            log.add('스타일 $g');
            p.setGenre(g);
            final gd = genreDef(g);
            tr
              ..bpm = gd.bpm
              ..mode = gd.mode;
          case 1:
            log.add('씬 추가');
            p.addScene();
          case 2:
            if (p.scenes.length > 1) {
              final at = rnd.nextInt(p.scenes.length);
              log.add('씬 삭제 $at');
              final gone = p.removeScene(at);
              if (gone != null && rnd.nextBool()) {
                log.add('  되돌리기');
                p.undoRemoveScene(gone);
              }
            }
          case 3:
            final at = rnd.nextInt(p.scenes.length);
            log.add('씬 복제 $at');
            p.duplicateScene(at);
          case 4:
            const types = ['drum', 'bass', 'chord', 'melody'];
            final t = types[rnd.nextInt(4)];
            log.add('트랙 추가 $t');
            p.addTrack(t);
          case 5:
            if (p.tracks.length > 1) {
              final t = p.tracks[rnd.nextInt(p.tracks.length)];
              log.add('트랙 삭제 ${t.name}');
              p.removeTrack(t);
            }
          case 6:
            final t = p.tracks[rnd.nextInt(p.tracks.length)];
            log.add('내 판 만들기 ${t.name}');
            p.makeEditable(t);
          case 7:
            final t = p.tracks[rnd.nextInt(p.tracks.length)];
            final names = SceneSequencer.patternNamesFor(p, t.type);
            if (names.isNotEmpty) {
              final n = rnd.nextBool()
                  ? names[rnd.nextInt(names.length)]
                  : null;
              log.add('패턴 ${t.name} → $n');
              p.setClip(t, n);
            }
          case 8:
            log.add('구간 추가');
            p.song.add(rnd.nextInt(p.scenes.length));
          case 9:
            if (p.song.sections.isNotEmpty) {
              final at = rnd.nextInt(p.song.sections.length);
              log.add('구간 삭제 $at');
              p.song.removeAt(at);
            }
          case 10:
            final at = rnd.nextInt(p.scenes.length);
            log.add('씬 고르기 $at');
            p.launchScene(at);
          case 11:
            // 판을 실제로 고친다 — 내 판을 만들고 음을 찍거나 지운다
            final t = p.tracks[rnd.nextInt(p.tracks.length)];
            final name = p.makeEditable(t);
            if (t.type == 'drum') {
              final d = p.userDrum[name];
              if (d != null) {
                final lane = kDrumLanes[rnd.nextInt(kDrumLanes.length)];
                final step = rnd.nextInt(d.bars * kStepsPerBar);
                log.add('드럼 찍기 $lane@$step');
                (d.hits[lane] ??= <int>[]).add(step);
              }
            } else {
              final n = p.userNote[name];
              if (n != null) {
                final deg = rnd.nextInt(t.type == 'chord' ? 7 : 15);
                final step = rnd.nextInt(n.bars * kStepsPerBar);
                log.add('음 찍기 $deg@$step');
                // **`copyWith` 로 쓴다.** 네 칸짜리 생성자로 새로 짜면
                // 덧줄·반음 줄 깃발을 손으로 옮겨야 하고, 한 번만 빠뜨리면
                // 얹어 둔 것이 사라지거나 가락이 딴 가락이 된다.
                // (이 시험이 바로 그 실수를 저지르고 있었다 — 그걸 시험이 잡았다)
                p.putUserPattern(
                  t.type,
                  name,
                  note: n.copyWith(
                    notes: NoteOps.add(
                      n.notes,
                      deg,
                      step,
                      isChord: t.type == 'chord',
                      steps: n.bars * kStepsPerBar,
                    ),
                  ),
                );
              }
            }
          case 12:
            final f = Feel(
              energy: rnd.nextDouble(),
              density: rnd.nextDouble(),
              groove: rnd.nextDouble(),
              fill: rnd.nextDouble(),
              vary: rnd.nextDouble(),
            );
            log.add('느낌 바꾸기');
            p.setFeel(f);
          case 13:
            final t = p.tracks[rnd.nextInt(p.tracks.length)];
            log.add('믹서 만지기 ${t.name}');
            t.vol = rnd.nextDouble() * 1.4;
            t.pan = rnd.nextDouble() * 2 - 1;
            if (rnd.nextBool()) {
              t.eq.hi = rnd.nextDouble() * 12 - 6;
              t.eqChanged();
            }
          case 14:
            log.add('조·템포 바꾸기');
            tr
              ..root = rnd.nextInt(12)
              ..mode = rnd.nextBool() ? 'minor' : 'major'
              ..bpm = 60 + rnd.nextInt(120).toDouble();
          case 15:
            final t = p.tracks[rnd.nextInt(p.tracks.length)];
            log.add('음소거/솔로 ${t.name}');
            t.mute = rnd.nextBool();
            t.solo = rnd.nextBool();
          // 타임라인 트랙 줄 — **구간을 끼우고 옮기고 지우는 사이사이에** 놓인다.
          // 클립은 (구간, 구간 안 마디)로 자리를 잡으므로, 구간이 움직일 때마다
          // 번호를 따라 옮겨야 한다(`_remapLanes`). 여기가 어긋나면 딴 구간에서
          // 소리가 난다 — 오류는 안 난다.
          case 16:
            if (p.song.sections.isNotEmpty) {
              final si = rnd.nextInt(p.song.sections.length);
              final t = p.tracks[rnd.nextInt(p.tracks.length)];
              final names = SceneSequencer.patternNamesFor(p, t.type);
              if (names.isNotEmpty) {
                final n = names[rnd.nextInt(names.length)];
                final bar = rnd.nextInt(8);
                log.add('클립 놓기 $si-$bar ${t.name} $n');
                p.song.putLane(si, bar, t.id, n);
              }
            }
          case 17:
            if (p.song.lanes.isNotEmpty) {
              final c = p.song.lanes[rnd.nextInt(p.song.lanes.length)];
              log.add('클립 지우기 ${c.section}-${c.bar}');
              p.song.removeLane(c);
            }
          // **덧줄** — 한 판이 화음과 낱음을 같이 든다. 판을 고치는 다른 손짓들이
          // 덧줄을 흘리지 않는지(짝이 하나 없는 그 병) 여기서 같이 흔든다.
          case 18:
            {
              final t = p.tracks[rnd.nextInt(p.tracks.length)];
              if (t.type != 'drum') {
                final name = p.makeEditable(t);
                final d = p.userNote[name];
                if (d != null) {
                  final add = rnd.nextBool();
                  log.add('덧줄 ${t.name} ${add ? '더하기' : '비우기'}');
                  p.putUserPattern(
                    t.type,
                    name,
                    note: d.copyWith(
                      also: add
                          ? [
                              [
                                rnd.nextInt(t.type == 'chord' ? 15 : 7),
                                rnd.nextInt(d.bars * kStepsPerBar),
                                2,
                                2,
                              ],
                            ]
                          : const [],
                    ),
                  );
                }
              }
            }
          // **반음 줄** — 좌표계가 바뀐다. 켜고 끄는 사이에 음이 줄 밖으로 나가면
          // 소리가 뭉개진다(도수 7 = 옥타브, 반음 7 = 5도).
          case 19:
            {
              final t = p.tracks[rnd.nextInt(p.tracks.length)];
              if (t.type == 'bass' || t.type == 'melody') {
                final name = p.makeEditable(t);
                final d = p.userNote[name];
                if (d != null) {
                  final to = !d.chromatic;
                  log.add('반음 줄 ${t.name} ${to ? '켜기' : '끄기'}');
                  p.putUserPattern(
                    t.type,
                    name,
                    note: d.copyWith(
                      notes: to
                          ? NoteOps.toChromatic(d.notes, tr.mode)
                          : NoteOps.toDegrees(d.notes, tr.mode),
                      chromatic: to,
                    ),
                  );
                }
              }
            }
          // **코드 진행 바꾸기** — 코드 하나를 바꾸면 베이스·멜로디가 따라 옮겨진다.
          case 20:
            {
              final (slots, _) = p.readSceneProg();
              if (slots.isNotEmpty) {
                final sl = slots[rnd.nextInt(slots.length)];
                final to = rnd.nextInt(7);
                log.add('코드 ${sl.label} → ${to + 1}도');
                p.changeChord(sl, to, mode: tr.mode);
              }
            }
          case 21:
            {
              final i = rnd.nextInt(p.scenes.length);
              final v = rnd.nextBool()
                  ? kDefaultCritters[rnd.nextInt(kDefaultCritters.length)]
                  : null;
              log.add('캐릭터 $i → $v');
              p.setSceneCritter(i, v);
            }
          // **두드려 넣기** — 손으로 두드린 것을 판에 얹는다. 높이를 코드에서
          // 끌어오므로, 코드가 바뀐 뒤·반음 줄을 켠 뒤·조를 바꾼 뒤에도
          // **제 좌표계 안**에 떨어져야 한다(불변식 검사가 그걸 본다).
          case 22:
            {
              final t = p.tracks[rnd.nextInt(p.tracks.length)];
              if (t.type != 'drum') {
                final name = p.makeEditable(t);
                final d = p.userNote[name];
                if (d != null) {
                  final steps = d.bars * kStepsPerBar;
                  final hits = [
                    for (var k = 0; k < 1 + rnd.nextInt(6); k++)
                      TapHit(0, rnd.nextInt(steps), 1 + rnd.nextInt(8)),
                  ];
                  final (prog, progSteps) = p.readSceneProg();
                  final clear = rnd.nextBool();
                  log.add('두드려 넣기 ${t.name} ${hits.length}개${clear ? ' (지우고)' : ''}');
                  p.putUserPattern(
                    t.type,
                    name,
                    note: d.copyWith(
                      notes: tapToNotes(
                        d.notes,
                        hits,
                        prog: prog,
                        progSteps: progSteps,
                        steps: steps,
                        type: t.type,
                        chord: t.type == 'chord',
                        chromatic: d.chromatic,
                        mode: tr.mode,
                        oct: t.type == 'chord'
                            ? NoteOps.chordOct(d.notes)
                            : 0,
                        clear: clear,
                      ),
                    ),
                  );
                }
              }
            }
          // **높낮이 옮기기** — 찍힌 음을 위아래로 끌어 다른 줄로. 편집기의
          // `_moveRow` 가 하는 일과 같다: 줄 밖으로 나가지 않고, 남의 자리를
          // 덮어쓰지 않고, 길이·세기는 따라온다.
          case 23:
            {
              final t = p.tracks[rnd.nextInt(p.tracks.length)];
              if (t.type != 'drum') {
                final name = p.makeEditable(t);
                final d = p.userNote[name];
                if (d != null && d.notes.isNotEmpty) {
                  final rows = t.type == 'chord'
                      ? 7
                      : (d.chromatic ? kProRows : 15);
                  final at = rnd.nextInt(d.notes.length);
                  final by = rnd.nextInt(9) - 4;
                  final now = d.notes[at][0] as int;
                  final to = (now + by).clamp(0, rows - 1);
                  final step = d.notes[at][1] as int;
                  final taken = d.notes.any(
                    (n) => n[0] == to && n[1] == step,
                  );
                  if (!taken && to != now) {
                    log.add('높낮이 ${t.name} $now → $to도');
                    final list = [
                      for (final n in d.notes) List<Object?>.from(n),
                    ];
                    list[at][0] = to;
                    p.putUserPattern(
                      t.type,
                      name,
                      note: d.copyWith(notes: list),
                    );
                  }
                }
              }
            }
        }
        steps++;
        var t = trouble();
        // 소리는 비싸다 — **한 벌 끝**과 중간 한 번만 본다
        if (t == null && (i == 99)) {
          rendered++;
          try {
            t = _soundTrouble(p, tr);
          } catch (e) {
            t = '렌더에서 터진다: $e';
          }
        }
        if (t != null) {
          bad.add(
            '씨앗 $seed · ${i + 1}번째\n     한 일: ${log.join(' → ')}\n     탈: $t',
          );
          break;
        }
      }
    }

    check(
      '막 써도 안 어긋난다',
      bad.isEmpty,
      bad.isEmpty
          ? '40벌 × 100가지 = $steps걸음 · 소리까지 본 것 $rendered번'
          : '\n  ${bad.first}',
    );

    // ignore: avoid_print
    print(fail == 0 ? '막 써 보기 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
