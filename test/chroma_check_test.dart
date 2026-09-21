// **적어 놓은 코드가 실제로 그 소리로 나오는가.** (데이터 → 소리 확인)
//   flutter test test/chroma_check_test.dart
//
// 여태 화성 시험은 전부 **패턴 데이터**만 봤다. 데이터가 맞아도 그 뒤가 틀리면
// (자리바꿈이 엉뚱한 음을 고르거나, 코드 타입 표가 어긋나거나, 조 계산이 밀리거나)
// 아무도 모른다. 여기서는 **소리를 낸 다음 그 소리를 다시 듣고** 확인한다:
//
//   씬의 코드 트랙만 렌더 → 마디마다 12음 에너지(크로마) → 제일 센 음들이
//   그 마디에 적어 놓은 코드톤인가
//
// 고에젤(Goertzel) 로 12음 × 4옥타브를 직접 재므로 FFT 라이브러리가 필요 없다(§15).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/export.dart';
import 'package:music_doodle_engine/genre_mix.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/synth.dart';
import 'package:music_doodle_engine/theory.dart';

const _kSr = 48000;
const _name = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];

/// 재는 창의 최대 길이 — 0.5초면 이 음역에서 음을 가르기에 충분하다.
///
/// 처음엔 음이 울리는 **내내** 쟀다. 긴 음(엠비언트 서브는 한 음이 6초다) 하나에
/// 15만 샘플 × 37음을 돌았고, 창을 만드는 `cos` 를 **샘플마다** 불렀다.
/// 길게 잰다고 더 정확해지지 않는다 — 분해능은 이미 남는다.
const int _kWin = 24000;

/// 창은 미리 만들어 둔다 — 같은 값을 수억 번 계산하고 있었다.
final Map<int, Float64List> _winCache = {};
Float64List _hann(int n) => _winCache.putIfAbsent(n, () {
  final w = Float64List(n);
  for (var i = 0; i < n; i++) {
    w[i] = 0.5 - 0.5 * math.cos(2 * math.pi * i / n);
  }
  return w;
});

/// 한 주파수의 세기 — 고에젤. (창 없이 쓰면 새는 값이 커서 해닝을 씌운다)
double _goertzel(
  List<double> x,
  int from,
  int n,
  double freq,
  Float64List win,
) {
  final w = 2 * math.pi * freq / _kSr;
  final c = 2 * math.cos(w);
  var s1 = 0.0, s2 = 0.0;
  for (var i = 0; i < n; i++) {
    final j = from + i;
    if (j >= x.length) break;
    final s0 = x[j] * win[i] + c * s1 - s2;
    s2 = s1;
    s1 = s0;
  }
  return math.sqrt(s1 * s1 + s2 * s2 - c * s1 * s2);
}

/// 12음 에너지 — 주어진 음역을 다 훑어 음이름별로 모은다.
///
/// **음역을 악기에 맞춰야 한다.** 베이스(C1~C2)를 C3~B6 로 재면 기음이 창 밖이라
/// 3배음(완전5도 위)이 제일 세게 잡힌다 — F 를 C 로 잘못 읽는다. 실제로 그렇게
/// 틀렸다. 소리가 아니라 **내가 어디를 봤는지**가 틀린 것이었다.
List<double> _chroma(
  List<double> x,
  int from,
  int n0, {
  int lo = 48,
  int hi = 95,
}) {
  final n = n0 > _kWin ? _kWin : n0;
  final win = _hann(n);
  final out = List<double>.filled(12, 0);
  for (var m = lo; m <= hi; m++) {
    final f = 440 * math.pow(2, (m - 69) / 12).toDouble();
    out[m % 12] += _goertzel(x, from, n, f, win);
  }
  final mx = out.reduce(math.max);
  if (mx <= 0) return out;
  for (var i = 0; i < 12; i++) {
    out[i] /= mx;
  }
  return out;
}

List<double> _renderChordsOnly(Project p, SceneBuild b, String bus) {
  final full = SceneSequencer.mixSnapshot(p);
  final only = {
    for (final e in full.entries)
      e.key: [e.key == bus ? e.value[0] : 0.0, 0.0, 0.0, ...e.value.sublist(3)],
  };
  final wav = renderWav(
    ExportJob(
      notes: b.notes,
      drums: b.drums,
      busNames: b.busNames,
      buses: only,
      inserts: SceneSequencer.insertSnapshot(p),
      masterVol: styleGain(p.genre),
      seconds: b.totalSec,
    ),
  );
  final out = <double>[];
  for (var i = 44; i + 3 < wav.length; i += 4) {
    int s16(int a) {
      final v = wav[a] | (wav[a + 1] << 8);
      return v >= 0x8000 ? v - 0x10000 : v;
    }

    out.add((s16(i) + s16(i + 2)) / 2 / 32768.0);
  }
  return out;
}

void main() {
  test('적은 코드가 그 소리로 나온다', () {
    Human.setLevel(0);
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final bad = <String>[];
    var bars = 0;
    var worst = 1.0;
    var worstAt = '';

    for (final g in kGenres) {
      final p = Project.initial()..setGenre(g.key);
      final tr = Transport()
        ..bpm = g.bpm
        ..mode = g.mode;
      // **모든 씬**을 본다. 씬 하나는 4~8마디라 렌더가 짧다 —
      // 한 장르에 하나만 보면 그 장르의 코러스·브리지는 아무도 안 본 셈이 된다.
      for (final pick in p.scenes) {
        Track? ct;
        String? clip;
        for (final t in p.tracks.where((t) => t.type == 'chord')) {
          final c = pick.clips[t.id];
          if (c == null) continue;
          final d = p.findNote('chord', c);
          if (d == null || d.notes.isEmpty) continue;
          ct = t;
          clip = c;
          break;
        }
        if (ct == null || clip == null) continue;

        final def = p.findNote('chord', clip)!;
        final b = SceneSequencer.build(
          p,
          tr,
          reps: 1,
          from: pick,
          arrange: false,
        );
        final pcm = _renderChordsOnly(p, b, SceneSequencer.busOf(ct));
        final stepSec = 60.0 / g.bpm / 4;
        final key = MusicKey(root: tr.root, mode: tr.mode);
        final chords = diatonicChords(key);

        // **코드가 바뀌는 자리마다** 본다 — 마디 단위로 보면 안 된다.
        // 록 코러스는 4마디 안에서 8칸째에 i → VII 로 바뀌는데, 마디 가운데를
        // 보면 그 둘이 섞인 소리를 듣고 「i 가 안 들린다」고 말하게 된다.
        // (실제로 그렇게 잘못 잡았다 — 곡이 아니라 내 창이 틀린 것이었다.)
        final onsets = <(int, List<Object?>)>[];
        for (final n in def.notes) {
          final st = n[1] as int;
          final sig = '${n[0]}|${n.length > 4 ? n[4] : ''}';
          if (onsets.isNotEmpty &&
              '${onsets.last.$2[0]}|'
                      '${onsets.last.$2.length > 4 ? onsets.last.$2[4] : ''}' ==
                  sig) {
            continue; // 같은 코드를 여러 번 치는 것(스탭)은 한 번으로 본다
          }
          onsets.add((st, n));
        }
        onsets.sort((a, b) => a.$1.compareTo(b.$1));
        for (var oi = 0; oi < onsets.length; oi++) {
          final st = onsets[oi].$1;
          final n = onsets[oi].$2;
          final until = oi + 1 < onsets.length
              ? onsets[oi + 1].$1
              : def.bars * kStepsPerBar;
          final span = until - st;
          if (span < 4) continue; // 너무 짧으면 울리기 전에 끝난다
          final bar = st ~/ kStepsPerBar;
          final idx = ((n[0] as int) % 7 + 7) % 7;
          var spec = chords[idx];
          if (n.length > 4 && n[4] is String) {
            spec = ChordSpec(root: spec.root, type: n[4] as String);
          } else {
            // **스타일이 정해 주는 종류**도 「적어 놓은 것」이다(록 기타 = 파워코드).
            // 이걸 안 보면 「Eb 를 적었는데 안 들린다」고 말하게 되는데,
            // 애초에 Eb 를 적은 적이 없다 — 3음이 없는 코드다.
            final ty = genreChordType(g.key, ct.voice);
            if (ty != null) spec = ChordSpec(root: spec.root, type: ty);
          }
          final want = {for (final m in chordMidiOf(spec)) m % 12};
          // 그 코드가 울리는 동안의 **가운데 절반** — 어택과 다음 코드 번짐을 피한다
          final from = ((st + span * 0.25) * stepSec * _kSr).round();
          final n2 = (span * 0.5 * stepSec * _kSr).round();
          if (n2 < 2000 || from + n2 >= pcm.length) continue;
          final ch = _chroma(pcm, from, n2);
          // 센 순서로 want.length 개를 뽑아 얼마나 맞는지
          final order = List.generate(12, (i) => i)
            ..sort((a, b2) => ch[b2].compareTo(ch[a]));
          final top = order.take(want.length).toSet();
          final hit = top.where(want.contains).length;
          final ratio = hit / want.length;
          bars++;
          if (ratio < worst) {
            worst = ratio;
            worstAt = '${g.key}/${pick.name} ${bar + 1}마디';
          }
          if (ratio < 0.75) {
            bad.add(
              '${g.key}/${pick.name} ${bar + 1}마디 '
              '적은것 ${want.map((i) => _name[i]).join(',')} · '
              '들린것 ${top.map((i) => _name[i]).join(',')}',
            );
          }
        }
      }
    }

    check(
      '1) 적어 놓은 코드톤이 실제 소리에서 제일 세다',
      bad.isEmpty,
      bad.isEmpty
          ? '$bars자리 · 제일 나쁜 곳 ${(worst * 100).round()}% ($worstAt)'
          : bad.take(4).join(' · '),
    );

    // ── 2) 베이스도 적은 대로 나오는가 ──
    //
    // 베이스는 홑음이라 제일 깨끗하게 확인된다. `degreeFreq('bass')` 는 C1(24) 기준
    // 이라 코드와 **다른 계산 경로**를 탄다 — 여기가 틀어져도 코드 검사는 통과한다.
    {
      final off = <String>[];
      var checked = 0;
      for (final g in kGenres) {
        final p = Project.initial()..setGenre(g.key);
        final tr = Transport()
          ..bpm = g.bpm
          ..mode = g.mode;
        final key = MusicKey(root: tr.root, mode: tr.mode);
        for (final pick in p.scenes) {
          Track? bt;
          String? clip;
          for (final t in p.tracks.where((t) => t.type == 'bass')) {
            final c = pick.clips[t.id];
            if (c == null) continue;
            final d = p.findNote('bass', c);
            if (d == null || d.notes.isEmpty) continue;
            bt = t;
            clip = c;
            break;
          }
          if (bt == null || clip == null) continue;
          final def = p.findNote('bass', clip)!;
          final b = SceneSequencer.build(
            p,
            tr,
            reps: 1,
            from: pick,
            arrange: false,
          );
          final pcm = _renderChordsOnly(p, b, SceneSequencer.busOf(bt));
          final stepSec = 60.0 / g.bpm / 4;
          for (final n in def.notes) {
            final len = n[2] as int;
            if (len < 6) continue; // 짧으면 창이 모자란다
            final st = n[1] as int;
            final from = ((st + len * 0.2) * stepSec * _kSr).round();
            final w = (len * 0.5 * stepSec * _kSr).round();
            if (w < 4000 || from + w >= pcm.length) continue;
            // 베이스는 C1(24)~C4(60) 를 본다 — 기음이 창 안에 있어야 한다
            final ch = _chroma(pcm, from, w, lo: 24, hi: 60);
            var top = 0;
            for (var i = 1; i < 12; i++) {
              if (ch[i] > ch[top]) top = i;
            }
            final want =
                ((69 +
                                12 *
                                    (math.log(
                                          degreeFreq(n[0] as int, 'bass', key) /
                                              440,
                                        ) /
                                        math.ln2))
                            .round() %
                        12 +
                    12) %
                12;
            checked++;
            if (top != want) {
              off.add(
                '${g.key}/${pick.name} ${st ~/ kStepsPerBar + 1}마디 '
                '적은것 ${_name[want]} · 들린것 ${_name[top]}',
              );
            }
          }
        }
      }
      check(
        '2) 베이스도 적은 대로 나온다',
        off.isEmpty,
        off.isEmpty ? '$checked음' : off.take(4).join(' · '),
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '크로마 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
