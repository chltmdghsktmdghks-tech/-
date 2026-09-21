// 자동 화성이 **얼마나 맞히는지** 재는 도구 (수동 실행).
//   flutter test test/harmony_meter.dart
//
// 짝은 **실제 씬에서 같이 울리는 것**으로 잡는다. 처음엔 패턴 이름 앞부분으로 묶었는데
// 그러면 벌스 멜로디에 코러스 코드가 붙는다 — 「사람이 쓴 코드가 63% 밖에 안 맞는다」는
// 이상한 값이 나와서 알았다. 기준이 틀리면 그 뒤 숫자는 전부 뜻이 없다.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genre_mix.dart';
import 'package:music_doodle_engine/harmony.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/theory.dart';

class _Pair {
  final String label;
  final List<List<Object?>> mel, chord;
  final int bars;
  _Pair(this.label, this.mel, this.chord, this.bars);
}

List<_Pair> _pairs() {
  final out = <_Pair>[];
  for (final g in kGenreDuck.keys) {
    final p = Project.initial()..setGenre(g);
    for (var i = 0; i < p.scenes.length; i++) {
      final sc = p.scenes[i];
      for (final mt in p.tracks.where((t) => t.type == 'melody')) {
        final mClip = sc.clips[mt.id];
        if (mClip == null) continue;
        for (final ct in p.tracks.where((t) => t.type == 'chord')) {
          final cClip = sc.clips[ct.id];
          if (cClip == null) continue;
          final m = p.findNote('melody', mClip), c = p.findNote('chord', cClip);
          if (m == null || c == null || m.notes.isEmpty || c.notes.isEmpty) {
            continue;
          }
          out.add(_Pair('$g/${sc.name}', m.notes, c.notes, m.bars));
          break; // 코드 트랙 하나면 충분하다
        }
      }
    }
  }
  return out;
}

void main() {
  test('자동 화성 계량', () {
    // ignore: avoid_print
    void p(String s) => print(s);
    const key = MusicKey(root: 0, mode: 'minor');
    final pairs = _pairs();

    double agree(List<ChordPick> picks, List<List<Object?>> human) {
      var same = 0, n = 0;
      for (final pk in picks) {
        var h = -1, at = -1;
        for (final row in human) {
          final st = (row[1] as num).toInt();
          if (st <= pk.step && st > at) {
            at = st;
            h = ((row[0] as num).toInt() % 7 + 7) % 7;
          }
        }
        if (h < 0) continue;
        n++;
        if (h == pk.index) same++;
      }
      return n == 0 ? 0 : same / n;
    }

    var humanFit = 0.0;
    for (final e in pairs) {
      humanFit += harmonyFit(e.mel, e.chord, bars: e.bars);
    }
    p(
      '짝 ${pairs.length}개 · **사람이 쓴 코드와 멜로디가 맞는 정도 '
      '${(humanFit / pairs.length * 100).round()}%** (이게 기준선이다)',
    );
    p('');
    p('흐름   자동이 맞는 정도   사람과 같은 코드');
    for (final w in [0.0, 1.0, 2.0, 3.0, 5.0, 8.0]) {
      var f = 0.0, sm = 0.0;
      for (final e in pairs) {
        final picks = suggestChords(e.mel, bars: e.bars, key: key, flow: w);
        f += harmonyFit(e.mel, chordRowsOf(picks), bars: e.bars);
        sm += agree(picks, e.chord);
      }
      final col = '${(f / pairs.length * 100).round()}%'.padRight(22);
      p(
        '${w.toStringAsFixed(0).padLeft(4)}   $col'
        '${(sm / pairs.length * 100).round()}%',
      );
    }
  });
}
