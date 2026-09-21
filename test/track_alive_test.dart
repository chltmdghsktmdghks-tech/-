// **모든 트랙이 실제로 소리를 내는가** — 층 하나가 조용해도 오류는 안 난다.
//   flutter test test/track_alive_test.dart
//
// 이 프로젝트에서 제일 오래 안 잡힌 고장들이 다 이 모양이었다:
//  · 셰이커·카우벨이 이름이 안 맞아 **타격 2361개가 통째로 무음**이었다
//  · 보컬이 음색표에 없어서 삼각파로 울고 있었다
//  · 스트링·오르간이 믹스 편성에 없어 투명한 기본값으로 났다
// 셋 다 「소리는 나는 것 같은데」로 보여서 귀로도 잘 안 잡혔다.
//
// 그래서 **트랙 하나만 남기고 렌더해서** 정말 우는지 본다. 곡 전체를 돌리면
// 비싸므로, 그 트랙의 **첫 음 언저리 6초**만 잘라 본다.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/engine.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/synth.dart' show Human;

void main() {
  test('트랙이 다 운다', () {
    Human.setLevel(0);
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final dead = <String>[];
    final faint = <String>[];
    var looked = 0;

    for (final g in kGenres) {
      final probe = Project.initial()..setGenre(g.key);
      final names = [for (final t in probe.tracks) t.name];
      for (final name in names) {
        final p = Project.initial()..setGenre(g.key);
        for (final t in p.tracks) {
          t.mute = t.name != name;
        }
        final tr = Transport()
          ..bpm = g.bpm
          ..mode = g.mode;
        final b = SceneSequencer.buildSong(p, tr);
        if (b.notes.isEmpty && b.drums.isEmpty) {
          // 어느 구간에도 안 실린 트랙 — 그건 편성 쪽 이야기다(genre_check 5-i)
          continue;
        }
        looked++;
        // 첫 소리 자리 찾기
        var from = 1e9;
        for (final n in b.notes) {
          final t0 = (n[6] as num).toDouble();
          if (t0 < from) from = t0;
        }
        for (final d in b.drums) {
          final t0 = (d[4] as num).toDouble();
          if (t0 < from) from = t0;
        }
        final until = math.min(b.totalSec, from + 6.0);

        final e = Engine()..trackMix.configure(b.busNames);
        SceneSequencer.mixSnapshot(p).forEach((bus, v) {
          final m = bus == 'drum' ? e.trackMix.drum : e.trackMix.bus(bus);
          if (m == null) return;
          m
            ..vol = v[0]
            ..pan = v[1]
            ..rev = v[2]
            ..eqLoDb = v[3]
            ..eqMidDb = v[4]
            ..eqHiDb = v[5]
            ..hpfFreq = v[6]
            ..lpfFreq = v[7]
            ..lfoHz = v[8]
            ..lfoDepth = v[9]
            ..markDirty();
        });
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
        final total = (until * kSampleRate).round();
        final skip = (from * kSampleRate).round();
        var done = 0, cnt = 0;
        var energy = 0.0, peak = 0.0;
        while (done < total) {
          final n = math.min(1024, total - done);
          final pcm = e.render(n);
          for (var i = 0; i < n; i++) {
            if (done + i < skip) continue;
            final v = (pcm[i * 2] + pcm[i * 2 + 1]) / 2 / 32768.0;
            energy += v * v;
            if (v.abs() > peak) peak = v.abs();
            cnt++;
          }
          done += n;
        }
        final rms = cnt == 0 ? 0.0 : math.sqrt(energy / cnt);
        final db = rms <= 1e-9 ? -120.0 : 20 * math.log(rms) / math.ln10;
        if (peak < 1e-5) {
          dead.add('${g.key}/$name');
        } else if (db < -55) {
          faint.add('${g.key}/$name(${db.toStringAsFixed(0)}dB)');
        }
      }
    }

    check(
      '1) 실린 트랙은 하나도 빠짐없이 운다',
      dead.isEmpty && looked >= 60,
      dead.isEmpty ? '$looked개 트랙' : dead.join(', '),
    );
    // −55dB 은 「거의 안 들린다」가 아니라 **「뭔가 잘못됐다」** 자리다.
    // 지금 제일 여린 것이 −40dB 언저리다(엠비언트 하프).
    check(
      '2) 터무니없이 여린 트랙이 없다',
      faint.isEmpty,
      faint.isEmpty ? '전부 -55dB 위' : faint.join(', '),
    );

    // ignore: avoid_print
    print(fail == 0 ? '트랙 소리 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
