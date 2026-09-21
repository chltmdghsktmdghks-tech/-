// Phase 3 — **자리바꿈이 정말 자리를 바꾸는가.** (theory.dart `voiceLead`)
//   flutter test test/voicing_check_test.dart
//
// `voiceLead` 는 코드를 한 옥타브씩 옮겨 가며 **밑음을 위로 넘기는** 자리바꿈을
// 전부 시험해 보고 앞 코드와 제일 가까운 것을 고른다. 넘긴 뒤 **다시 정렬하지
// 않으면** 옥타브보다 넓은 코드(9화음 등)에서 배열 순서가 깨지고, 그러면
//   · 「반음 붙었나」 검사가 음수 간격을 보고 없는 탁함에 벌점을 주고
//   · `v.first` 가 맨 밑음이 아니게 되어 음역 벌점도 엉뚱한 음을 본다
// 그래서 넓은 코드는 자리바꿈이 **하나도 못 살아남았다** — 라이브러리 전체에서
// 9화음 720개가 100% 근음 자리였다.
//
// 지키는 것:
//  1. 나온 자리는 항상 낮은음 → 높은음 순이다
//  2. 코드톤 집합은 그대로다 — 옥타브만 옮긴다
//  3. 넓은 코드도 근음 자리에 갇히지 않는다
//  4. 좁은 코드는 원래대로 잘 이어진다
//  5. 같은 입력 → 같은 자리 (난수를 안 쓴다)
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/theory.dart';

bool _sorted(List<int> v) {
  for (var i = 1; i < v.length; i++) {
    if (v[i] < v[i - 1]) return false;
  }
  return true;
}

/// 음이름 집합(옥타브 무시). 자리를 바꿔도 이것은 안 변해야 한다.
String _pcs(List<int> v) => ([for (final m in v) m % 12]..sort()).join(',');

/// 라이브러리 코드 패턴을 실제 재생과 같은 방식으로 자리 잡는다.
/// (`buildChordPattern` 과 같은 두 바퀴 — 끝 코드에서 첫 코드로도 이어야 한다)
(List<ChordSpec>, List<List<int>>) _voiceRun(NotePatternDef def, MusicKey key) {
  final tiled = tileNoteList(def.notes, def.src, def.bars);
  final chords = diatonicChords(key);
  final specs = <ChordSpec>[];
  final octs = <int>[];
  for (final n in tiled) {
    final idx = ((n[0] as int) % chords.length + chords.length) % chords.length;
    var spec = chords[idx];
    if (n.length > 4 && n[4] is String) {
      spec = ChordSpec(root: spec.root, type: n[4] as String);
    }
    specs.add(spec);
    octs.add(n.length > 5 && n[5] is int ? n[5] as int : 0);
  }
  List<int>? prev;
  var voiced = <List<int>>[];
  for (var pass = 0; pass < 2; pass++) {
    voiced = <List<int>>[];
    for (var si = 0; si < specs.length; si++) {
      final mid = chordMidiOf(specs[si]);
      final v = specs[si].bass != null
          ? mid
          : voiceLead(mid, prev, oct: octs[si]);
      voiced.add(v);
      prev = v;
    }
  }
  return (specs, voiced);
}

void main() {
  test('코드 자리바꿈', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('  ${ok ? 'OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final keys = [
      for (var r = 0; r < 12; r++) ...[
        MusicKey(root: r, mode: 'minor'),
        MusicKey(root: r, mode: 'major'),
      ],
    ];

    var total = 0, unsorted = 0, pcsChanged = 0;
    var wide = 0, wideRoot = 0, narrow = 0, narrowRoot = 0;
    final unsortedEx = <String>[];
    final pcsEx = <String>[];

    for (final def in kChordPatterns) {
      for (final key in keys) {
        final (specs, voiced) = _voiceRun(def, key);
        for (var i = 0; i < specs.length; i++) {
          final src = chordMidiOf(specs[i]);
          final v = voiced[i];
          total++;
          if (!_sorted(v)) {
            unsorted++;
            if (unsortedEx.length < 3) {
              unsortedEx.add('${def.name}/${specs[i].type} $v');
            }
          }
          if (_pcs(v) != _pcs(src)) {
            pcsChanged++;
            if (pcsEx.length < 3) {
              pcsEx.add('${def.name}/${specs[i].type} $src → $v');
            }
          }
          final isWide = src.last - src.first > 12;
          final atRoot = v.first % 12 == specs[i].root % 12;
          if (isWide) {
            wide++;
            if (atRoot) wideRoot++;
          } else {
            narrow++;
            if (atRoot) narrowRoot++;
          }
        }
      }
    }

    // ── 1) 낮은음부터 나온다 ──
    check(
      '1) 나온 자리가 낮은음 → 높은음 순이다',
      unsorted == 0,
      '$total개 중 어긋남 $unsorted개${unsortedEx.isEmpty ? '' : ' · ${unsortedEx.join(' / ')}'}',
    );

    // ── 2) 화성은 그대로 ──
    check(
      '2) 코드톤 집합이 안 바뀐다 (옥타브만 옮긴다)',
      pcsChanged == 0,
      '어긋남 $pcsChanged개${pcsEx.isEmpty ? '' : ' · ${pcsEx.join(' / ')}'}',
    );

    // ── 3) 넓은 코드도 자리를 바꾼다 ──
    //
    // 정렬을 안 하면 여기가 정확히 100% 가 된다. 넉넉히 90% 로 잡는다 —
    // 근음 자리가 제일 가까운 자리인 경우도 많아 0% 를 요구하면 안 된다.
    final wideRootPct = wide == 0 ? 0.0 : 100 * wideRoot / wide;
    check(
      '3) 옥타브보다 넓은 코드가 근음 자리에 갇히지 않는다',
      wide > 0 && wideRootPct < 90,
      '넓은 코드 $wide개 중 근음 자리 $wideRoot개 (${wideRootPct.round()}%)',
    );

    // ── 4) 좁은 코드는 원래대로 ──
    final narrowRootPct = narrow == 0 ? 0.0 : 100 * narrowRoot / narrow;
    check(
      '4) 좁은 코드도 골고루 자리를 바꾼다',
      narrow > 0 && narrowRootPct > 20 && narrowRootPct < 80,
      '좁은 코드 $narrow개 중 근음 자리 $narrowRoot개 (${narrowRootPct.round()}%)',
    );

    // ── 5) 같은 입력 → 같은 자리 ──
    {
      var same = true;
      for (final def in kChordPatterns.take(12)) {
        final k = MusicKey(root: 3, mode: 'minor');
        final (_, a) = _voiceRun(def, k);
        final (_, b) = _voiceRun(def, k);
        if (a.toString() != b.toString()) same = false;
      }
      check('5) 같은 입력 → 같은 자리', same, '난수를 안 쓴다');
    }

    // ── 6) 자리바꿈이 실제로 손을 덜 움직이게 한다 ──
    //
    // 근음 자리로만 쌓은 것과 견준다. 자리바꿈이 이것보다 나쁘면 안 하느니 못하다.
    {
      var voicedMove = 0.0, rootMove = 0.0, runs = 0;
      for (final def in kChordPatterns) {
        for (final key in keys) {
          final (specs, voiced) = _voiceRun(def, key);
          if (specs.length < 2) continue;
          final roots = [for (final s in specs) chordMidiOf(s)];
          double mean(List<List<int>> vs) {
            var t = 0.0;
            for (var i = 0; i < vs.length; i++) {
              final a = vs[i], b = vs[(i + 1) % vs.length];
              final n = a.length < b.length ? a.length : b.length;
              var d = 0;
              for (var j = 0; j < n; j++) {
                d += (b[j] - a[j]).abs();
              }
              t += d / n;
            }
            return t / vs.length;
          }

          voicedMove += mean(voiced);
          rootMove += mean(roots);
          runs++;
        }
      }
      final vm = voicedMove / runs, rm = rootMove / runs;
      check(
        '6) 근음 자리로만 쌓는 것보다 손이 덜 움직인다',
        vm < rm * 0.6,
        '자리바꿈 ${vm.toStringAsFixed(2)}반음 · 근음만 ${rm.toStringAsFixed(2)}반음 ($runs벌)',
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '코드 자리바꿈 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
