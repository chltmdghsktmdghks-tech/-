// **베이스 줄이 어떻게 생겼는가** 를 재는 도구 (수동 실행).
//   flutter test test/bass_meter.dart
//
// 여태 베이스는 「코드의 근음을 따라가는가」(harmony_clash_test)만 봤다.
// 그건 안 틀렸는지를 본 것이지 **좋은지**를 본 게 아니다.
// 근음만 네 번 치는 베이스는 안 틀렸지만 아무 재미가 없다.
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';

void main() {
  test('베이스 계량', () {
    // ignore: avoid_print
    void pr(String s) => print(s);
    pr('장르        씬          패턴            음/마디 근음%  움직임 여백%  킥동시% 킥엇박%');
    for (final g in kGenres) {
      final proj = Project.initial()..setGenre(g.key);
      for (final sc in proj.scenes) {
        // 그 씬의 코드(마디별 근음 도수)
        final byBar = <int, int>{};
        for (final t in proj.tracks.where((t) => t.type == 'chord')) {
          final clip = sc.clips[t.id];
          if (clip == null) continue;
          final d = proj.findNote('chord', clip);
          if (d == null || d.notes.isEmpty) continue;
          for (final n in d.notes) {
            byBar.putIfAbsent(
              (n[1] as int) ~/ 16,
              () => ((n[0] as int) % 7 + 7) % 7,
            );
          }
          break;
        }
        // 그 씬의 킥 자리
        final kick = <int>{};
        for (final t in proj.tracks.where((t) => t.type == 'drum')) {
          final clip = sc.clips[t.id];
          if (clip == null) continue;
          final d = findDrumPattern(clip);
          if (d == null) continue;
          kick.addAll(d.hits['k'] ?? const []);
          break;
        }
        for (final t in proj.tracks.where((t) => t.type == 'bass')) {
          final clip = sc.clips[t.id];
          if (clip == null) continue;
          final d = proj.findNote('bass', clip);
          if (d == null || d.notes.isEmpty) continue;
          final ns = d.notes;
          var root = 0, filled = 0, move = 0;
          for (var i = 0; i < ns.length; i++) {
            final bar = (ns[i][1] as int) ~/ 16;
            if (byBar[bar] != null &&
                ((ns[i][0] as int) % 7 + 7) % 7 == byBar[bar]) {
              root++;
            }
            filled += ns[i][2] as int;
            if (i > 0)
              move += ((ns[i][0] as int) - (ns[i - 1][0] as int)).abs();
          }
          var onKick = 0, offKick = 0;
          if (kick.isNotEmpty) {
            for (final n in ns) {
              final st = (n[1] as int) % (d.src * 16);
              if (kick.contains(st)) {
                onKick++;
              } else if (!kick.contains(st - 1) && !kick.contains(st + 1)) {
                offKick++;
              }
            }
          }
          final bars = d.bars;
          pr(
            '${g.key.padRight(11)} ${sc.name.padRight(11)} ${clip.padRight(15)} '
            '${(ns.length / bars).toStringAsFixed(1).padLeft(5)} '
            // **코드가 없는 씬에서는 「0%」가 아니라 「—」다.**
            // 하우스 아웃트로·힙합 브레이크가 그렇다 — 근음을 안 짚은 게 아니라
            // **짚을 코드가 없다.** 0% 로 찍어 놓으면 다음에 보는 사람이
            // 「베이스가 코드와 어긋난다」로 읽는다(내가 그랬다).
            '${(byBar.isEmpty ? '—' : '${(root * 100 / ns.length).round()}%').padLeft(5)} '
            '${(move / math.max(1, ns.length - 1)).toStringAsFixed(1).padLeft(5)} '
            '${'${(100 - filled * 100 / (bars * 16)).round()}%'.padLeft(5)} '
            '${kick.isEmpty ? '    -' : '${(onKick * 100 / ns.length).round()}%'.padLeft(5)} '
            '${kick.isEmpty ? '    -' : '${(offKick * 100 / ns.length).round()}%'.padLeft(5)}',
          );
        }
      }
    }
  });
}
