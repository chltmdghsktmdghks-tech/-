// **코러스가 벌스보다 올라가는가**를 재는 도구 (수동 실행).
//   flutter test test/lift_meter.dart
//
// 곡이 「코러스에 왔다」고 느껴지는 이유의 절반은 **음이 올라가는 것**이다.
// 소리가 커지는 것만으로는 안 된다 — 같은 자리에서 크기만 커지면 그냥 시끄럽다.
// 여기서는 구간마다 주선율의 **평균 도수와 꼭대기**를 재서, 코러스가 벌스보다
// 실제로 올라가는지 본다. 귀가 아니라 숫자로 볼 수 있는 몇 안 되는 음악적 성질이다.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/project.dart';

/// 한 씬의 **선율 쪽 전부** — 트랙 하나만 보면 틀린다.
/// 트랩의 훅은 벨을 올리는 대신 **플럭 한 층을 얹어서** 커진다.
/// 그래서 도수뿐 아니라 **층 수와 음 개수**도 같이 센다.
class _Mel {
  final List<int> deg;
  final int layers;
  const _Mel(this.deg, this.layers);

  double get avg {
    if (deg.isEmpty) return 0;
    var s = 0;
    for (final x in deg) {
      s += x;
    }
    return s / deg.length;
  }

  int get hi => deg.isEmpty ? 0 : deg.reduce((a, b) => a > b ? a : b);
  int get n => deg.length;
  bool get empty => deg.isEmpty;
}

_Mel _melOf(Project p, Scene s) {
  final out = <int>[];
  var layers = 0;
  for (final t in p.tracks.where((x) => x.type == 'melody')) {
    final name = s.clips[t.id];
    if (name == null) continue;
    final nd = p.findNote(t.type, name);
    if (nd == null || nd.notes.isEmpty) continue;
    layers++;
    for (final e in nd.notes) {
      out.add(e[0] as int);
    }
  }
  return _Mel(out, layers);
}

void main() {
  test('코러스가 올라가는가', () {
    // ignore: avoid_print
    void pr(String s) => print(s);

    const chorusNames = {'코러스', '훅', '드롭'};
    const verseNames = {'벌스'};

    pr('스타일       벌스 (평균/꼭대기/음수/층)   코러스 (평균/꼭대기/음수/층)   차이');
    final weak = <String>[];
    for (final g in kGenres) {
      final p = Project.initial()..setGenre(g.key);
      _Mel? v, c;
      for (final s in p.scenes) {
        final m = _melOf(p, s);
        if (m.empty) continue;
        if (v == null && verseNames.contains(s.name)) v = m;
        if (c == null && chorusNames.contains(s.name)) c = m;
      }
      if (v == null || c == null) {
        pr(
          '${g.key.padRight(12)} — 벌스/코러스 짝이 없다 '
          '(${[for (final s in p.scenes) s.name].join('·')})',
        );
        continue;
      }
      final dAvg = c.avg - v.avg;
      final dHi = c.hi - v.hi;
      final dN = c.n - v.n;
      final dL = c.layers - v.layers;
      // **셋 중 하나라도** 커지면 코러스가 코러스다: 높아지거나 · 빽빽해지거나 · 층이 늘거나
      final lifts = dAvg >= 0.5 || dHi > 0 || dN > v.n * 0.15 || dL > 0;
      if (!lifts) weak.add(g.key);
      final col1 = '${v.avg.toStringAsFixed(1)}/${v.hi}/${v.n}/${v.layers}'
          .padRight(28);
      final col2 = '${c.avg.toStringAsFixed(1)}/${c.hi}/${c.n}/${c.layers}'
          .padRight(30);
      pr(
        '${g.key.padRight(12)} $col1$col2'
        '${dAvg >= 0 ? '+' : ''}${dAvg.toStringAsFixed(1)} · '
        '${dHi >= 0 ? '+' : ''}$dHi · ${dN >= 0 ? '+' : ''}$dN음 · '
        '${dL >= 0 ? '+' : ''}$dL층'
        '${lifts ? '' : '  ← 커지지 않는다'}',
      );
    }
    pr('');
    pr(weak.isEmpty ? '코러스가 다 커진다' : '안 커지는 스타일: ${weak.join(', ')}');
  });
}
