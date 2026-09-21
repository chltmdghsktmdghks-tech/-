// **멜로디가 그 아래 코드와 맞는가** 를 재는 도구 (수동 실행).
//   flutter test test/clash_meter.dart
//
// 여태 화성 검사는 코드↔코드, 코드↔베이스만 봤다(`harmony_clash_test`).
// 정작 제일 크게 들리는 줄 — **멜로디** — 은 아무도 안 봤다.
// 멜로디가 코드톤 바로 옆 반음에 오래 머무르면 「탁하다·틀렸다」로 들린다.
//
// 도수 공간이라 조와 무관하게 **반음 단위로 정확히** 계산된다.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/theory.dart';

/// 코드 하나가 내는 음들 — **조의 으뜸음 기준 반음**(0~11).
List<int> chordPcs(int idx, Object? ty, String mode) {
  final sc = kScale[mode]!;
  final off = [
    idx,
    idx + 2,
    idx + 4,
  ].map((x) => sc[x % 7] + 12 * (x ~/ 7)).toList();
  final qual = (off[2] - off[0]) == 6
      ? 'dim'
      : ((off[1] - off[0]) == 3 ? 'min' : 'maj');
  final ivs =
      kChordTypeIntervals[ty is String ? ty : qual] ??
      kChordTypeIntervals[qual]!;
  return [for (final iv in ivs) ((off[0] + iv) % 12 + 12) % 12];
}

/// 도수 → 으뜸음 기준 반음(옥타브 포함).
int degSemi(int deg, String mode) {
  final sc = kScale[mode]!;
  final d = deg.clamp(0, 14);
  return sc[d % 7] + 12 * (d ~/ 7);
}

/// 패턴을 씬 길이(loopBars)만큼 늘려 [step → 노트] 로 편다.
List<List<Object?>> spread(NotePatternDef def, int loopBars) {
  final out = <List<Object?>>[];
  final srcSteps = (def.src > 0 ? def.src : def.bars) * kStepsPerBar;
  final own = def.bars * kStepsPerBar;
  final reps = def.src > 0 ? (def.bars ~/ def.src).clamp(1, 64) : 1;
  final tiled = <List<Object?>>[];
  for (var r = 0; r < reps; r++) {
    for (final n in def.notes) {
      final c = List<Object?>.from(n);
      c[1] = (c[1] as int) + r * srcSteps;
      tiled.add(c);
    }
  }
  final loopSteps = loopBars * kStepsPerBar;
  final cycles = own > 0 ? (loopSteps / own).ceil() : 1;
  for (var c = 0; c < cycles; c++) {
    for (final n in tiled) {
      final s = (n[1] as int) + c * own;
      if (s >= loopSteps) continue;
      final cp = List<Object?>.from(n);
      cp[1] = s;
      out.add(cp);
    }
  }
  out.sort((a, b) => (a[1] as int).compareTo(b[1] as int));
  return out;
}

void main() {
  test('멜로디↔코드', () {
    // ignore: avoid_print
    void pr(String s) => print(s);

    pr('장르        씬          음   반음충돌  긴음충돌  코드톤  끝음해결');
    var totNotes = 0, totClash = 0, totLong = 0, totEnd = 0, totEndOk = 0;
    final worst = <String>[];

    for (final g in kGenres) {
      final proj = Project.initial()..setGenre(g.key);
      final mode = g.mode;
      for (final sc in proj.scenes) {
        // 씬 길이 = 제일 긴 패턴 (sequencer.build 와 같은 규칙)
        var loopBars = 0;
        for (final t in proj.tracks) {
          final clip = sc.clips[t.id];
          if (clip == null) continue;
          final b = proj.barsOf(t.type, clip);
          if (b > loopBars) loopBars = b;
        }
        if (loopBars <= 0) loopBars = 4;

        // 코드 타임라인 — 첫 코드 트랙
        List<List<Object?>>? ch;
        var chName = '';
        for (final t in proj.tracks.where((t) => t.type == 'chord')) {
          final clip = sc.clips[t.id];
          if (clip == null) continue;
          final d = proj.findNote('chord', clip);
          if (d == null || d.notes.isEmpty) continue;
          ch = spread(d, loopBars);
          chName = clip;
          break;
        }
        if (ch == null) continue;

        List<int> chordAt(int step) {
          List<Object?>? best;
          for (final c in ch!) {
            if ((c[1] as int) <= step) {
              best = c;
            } else {
              break;
            }
          }
          best ??= ch.first;
          return chordPcs(
            ((best[0] as int) % 7 + 7) % 7,
            best.length > 4 ? best[4] : null,
            mode,
          );
        }

        for (final t in proj.tracks.where((t) => t.type == 'melody')) {
          final clip = sc.clips[t.id];
          if (clip == null) continue;
          final d = proj.findNote('melody', clip);
          if (d == null || d.notes.isEmpty) continue;
          final mel = spread(d, loopBars);
          var n = 0, clash = 0, longClash = 0, tone = 0;
          for (var i = 0; i < mel.length; i++) {
            final note = mel[i];
            final step = note[1] as int;
            final len = note[2] as int;
            final pc = degSemi(note[0] as int, mode) % 12;
            final pcs = chordAt(step);
            var dist = 12;
            for (final c in pcs) {
              final diff = (pc - c).abs() % 12;
              final dd = diff > 6 ? 12 - diff : diff;
              if (dd < dist) dist = dd;
            }
            n++;
            if (dist == 0) tone++;
            if (dist == 1) {
              clash++;
              // **3칸(점8분) 넘게 끄는 음만** 진짜 문제다.
              // 16분·8분으로 지나가는 반음은 어느 장르에서나 정상이다.
              if (len >= 3) longClash++;
            }
          }
          // 프레이즈 끝음 — 마디 4개마다 마지막 음
          var ends = 0, endOk = 0;
          for (var bar = 3; bar < loopBars; bar += 4) {
            List<Object?>? last;
            for (final m in mel) {
              final b = (m[1] as int) ~/ kStepsPerBar;
              if (b <= bar) last = m;
            }
            if (last == null) continue;
            ends++;
            final pc = degSemi(last[0] as int, mode) % 12;
            if (chordAt(last[1] as int).contains(pc)) endOk++;
          }
          if (n == 0) continue;
          final cp = (clash * 100 / n).round();
          final lp = (longClash * 100 / n).round();
          final tp = (tone * 100 / n).round();
          pr(
            '${g.key.padRight(11)} ${sc.name.padRight(11)} '
            '${n.toString().padLeft(3)}  ${'$cp%'.padLeft(6)}  '
            '${'$lp%'.padLeft(6)}  ${'$tp%'.padLeft(5)}  '
            '${ends == 0 ? '  -' : '$endOk/$ends'.padLeft(4)}',
          );
          totNotes += n;
          totClash += clash;
          totLong += longClash;
          totEnd += ends;
          totEndOk += endOk;
          if (longClash > 0 || (ends > 0 && endOk < ends)) {
            worst.add(
              '${g.key}/${sc.name}  $clip ↔ $chName  '
              '긴음충돌 $longClash · 끝음 $endOk/$ends',
            );
            for (final note in mel) {
              final step = note[1] as int;
              final len = note[2] as int;
              final pc = degSemi(note[0] as int, mode) % 12;
              final pcs = chordAt(step);
              var dist = 12;
              var near = -1;
              for (final c in pcs) {
                final diff = (pc - c).abs() % 12;
                final dd = diff > 6 ? 12 - diff : diff;
                if (dd < dist) {
                  dist = dd;
                  near = c;
                }
              }
              if (dist != 1 || len < 3) continue;
              worst.add(
                '      ${step ~/ 16 + 1}마디 ${step % 16}칸 len$len  '
                '도수${note[0]}($pc반음) ↔ [${pcs.join(',')}] 부딪침 $near',
              );
            }
          }
        }
      }
    }
    pr('');
    pr(
      '합계  음 $totNotes · 반음충돌 ${(totClash * 100 / totNotes).toStringAsFixed(1)}% '
      '· 긴음충돌 ${(totLong * 100 / totNotes).toStringAsFixed(1)}% '
      '· 끝음해결 $totEndOk/$totEnd',
    );
    if (worst.isNotEmpty) {
      pr('');
      pr('── 손봐야 할 것 ──');
      for (final w in worst) {
        pr('  $w');
      }
    }
  });
}
