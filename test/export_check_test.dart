// 5단계 9/N — 내보내기(WAV) 확인.
//   flutter test test/export_check_test.dart
//
// 확인하는 것:
//  1) WAV 헤더가 규격대로인가(RIFF/WAVE/fmt/data · 48000 · 스테레오 · 16비트)
//  2) 길이가 곡 길이 + 꼬리 2초인가
//  3) **실제로 소리가 들어 있는가**(무음 파일을 뽑아 놓고 성공했다고 하면 최악이다)
//  4) 믹서 값이 반영되는가 — 트랙을 뮤트하면 파일이 조용해져야 한다
//  5) 클리핑이 없는가(꽉 찬 샘플이 거의 없어야 한다)
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/genre_mix.dart';
import 'package:music_doodle_engine/export.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/synth.dart';
import 'package:music_doodle_engine/theory.dart';

String _tag(Uint8List b, int at) => String.fromCharCodes(b.sublist(at, at + 4));

ExportJob _job(Project p, Transport tr) {
  final b = SceneSequencer.buildSong(p, tr);
  return ExportJob(
    notes: b.notes,
    drums: b.drums,
    busNames: b.busNames,
    buses: SceneSequencer.mixSnapshot(p),
    masterVol: 1.0,
    seconds: b.totalSec,
  );
}

void main() {
  test('내보내기', () {
    Human.setLevel(0);
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final p = Project.initial();
    final tr = Transport();
    // 2분 40초를 매번 렌더하면 시험이 느리다 — 구간을 줄여 짧은 곡으로 본다.
    p.song.sections.removeRange(2, p.song.sections.length);
    final job = _job(p, tr);

    final sw = Stopwatch()..start();
    final wav = renderWav(job);
    sw.stop();

    // 1) 헤더
    final d = ByteData.view(wav.buffer);
    final headOk =
        _tag(wav, 0) == 'RIFF' &&
        _tag(wav, 8) == 'WAVE' &&
        _tag(wav, 12) == 'fmt ' &&
        _tag(wav, 36) == 'data' &&
        d.getUint16(22, Endian.little) == 2 &&
        d.getUint32(24, Endian.little) == kSampleRate &&
        d.getUint16(34, Endian.little) == 16 &&
        d.getUint32(4, Endian.little) == wav.length - 8 &&
        d.getUint32(40, Endian.little) == wav.length - 44;
    check(
      '1) WAV 헤더',
      headOk,
      '${d.getUint32(24, Endian.little)}Hz · ${d.getUint16(22, Endian.little)}채널 · '
          '${d.getUint16(34, Endian.little)}비트 · ${(wav.length / 1048576).toStringAsFixed(1)}MB',
    );

    // 2) 길이
    final frames = (wav.length - 44) ~/ 4;
    final want = ((job.seconds + 2.0) * kSampleRate).round();
    check(
      '2) 길이',
      frames == want,
      '${(frames / kSampleRate).toStringAsFixed(1)}초 '
          '(곡 ${job.seconds.toStringAsFixed(1)}초 + 꼬리 2초) · '
          '렌더에 ${sw.elapsedMilliseconds}ms',
    );

    // 3) 진짜 소리가 들어 있는가
    final pcm = Int16List.view(wav.buffer, 44, frames * 2);
    double rms(int from, int to) {
      double s = 0;
      var n = 0;
      for (var i = from * 2; i < to * 2; i++) {
        final v = pcm[i] / 32768.0;
        s += v * v;
        n++;
      }
      return n == 0 ? 0 : sqrt(s / n);
    }

    var peak = 0;
    var clipped = 0;
    for (final v in pcm) {
      final a = v.abs();
      if (a > peak) peak = a;
      if (a >= 32700) clipped++;
    }
    final all = rms(0, frames);
    check(
      '3) 소리가 들어 있다',
      all > 0.02 && peak > 6000,
      'RMS ${all.toStringAsFixed(4)} · 피크 ${(peak / 32768).toStringAsFixed(3)}',
    );

    // 4) 믹서가 반영되는가 — 전부 뮤트하면 조용해야 한다
    for (final t in p.tracks) {
      t.mute = true;
    }
    final quiet = renderWav(_job(p, tr));
    final qpcm = Int16List.view(quiet.buffer, 44, (quiet.length - 44) ~/ 2);
    var qpeak = 0;
    for (final v in qpcm) {
      if (v.abs() > qpeak) qpeak = v.abs();
    }
    for (final t in p.tracks) {
      t.mute = false;
    }
    check(
      '4) 믹서 반영(전부 뮤트)',
      qpeak < 100,
      '피크 ${(qpeak / 32768).toStringAsFixed(4)}',
    );

    // 5) 클리핑
    check(
      '5) 클리핑 없음',
      clipped < frames ~/ 1000,
      '꽉 찬 샘플 $clipped개 / ${pcm.length}개',
    );

    // 6) **마스터 페이더가 파일에 실린다.**
    //
    // 재생은 엔진이 스타일 보정과 사용자 페이더를 따로 곱하는데, 내보내기는
    // 곱할 자리가 하나뿐이라 **둘을 합쳐 넣어야 한다.** 예전엔 스타일 보정만
    // 실었다 — 믹서에서 마스터를 내려 놓고 내보내면 파일만 그대로였다.
    // 마스터 **인서트**는 실리는데 페이더만 안 실린 채로.
    {
      final p6 = Project.initial()..setGenre('lofi');
      final m6 = MasterChannel()..vol = 0.5;
      final full = SceneSequencer.exportMasterVol(p6, MasterChannel());
      final half = SceneSequencer.exportMasterVol(p6, m6);
      check(
        '6) 마스터 페이더가 파일에 실린다',
        (half - full * 0.5).abs() < 1e-9 &&
            (full - styleGain('lofi')).abs() < 1e-9,
        '기본 ${full.toStringAsFixed(3)} · 절반으로 내리면 '
            '${half.toStringAsFixed(3)}',
      );
    }

    // 7) **장르가 정한 필터도 파일에 실린다.**
    //
    //    `kGenreMix` 는 슬롯마다 고역통과(보컬 200Hz 등)와 느린 로우패스
    //    움직임(엠비언트 패드)을 적어 뒀다 — 52군데. 그게 **재생에도 파일에도**
    //    안 실리고 있었다. 스냅샷이 여섯 칸만 담았기 때문이다.
    //    여기서는 **저역이 실제로 줄어드는지**로 확인한다(칸 개수만 세면
    //    담기만 하고 안 쓰는 경우를 못 잡는다).
    {
      final p7 = Project.initial()..setGenre('lofi');
      final tr7 = Transport()..bpm = 78;
      final b7 = SceneSequencer.buildSong(p7, tr7);
      double lowEnergy(double hpf) {
        // 베이스 트랙에만 고역통과를 건다 — 저역이 줄면 실린 것이다
        for (final t in p7.tracks) {
          if (t.type == 'bass') t.hpf = hpf;
        }
        final wav = renderWav(
          ExportJob(
            notes: b7.notes,
            drums: b7.drums,
            busNames: b7.busNames,
            buses: SceneSequencer.mixSnapshot(p7),
            masterVol: 1.0,
            seconds: b7.totalSec,
          ),
        );
        final pcm = wav.buffer.asInt16List(44);
        // 저역만 — 아주 성긴 로우패스(1차 IIR) 로 100Hz 아래를 남긴다
        var y = 0.0, e = 0.0;
        const a = 0.012; // ≈100Hz @48k
        for (var i = 0; i < pcm.length; i += 2) {
          y += a * (pcm[i] / 32768.0 - y);
          e += y * y;
        }
        return sqrt(e / (pcm.length / 2));
      }

      final open = lowEnergy(20);
      final cut = lowEnergy(300);
      final snapLen = SceneSequencer.mixSnapshot(p7).values.first.length;
      check(
        '7) 장르 필터가 파일에 실린다',
        snapLen >= 10 && cut < open * 0.7,
        '스냅샷 $snapLen칸 · 저역 ${open.toStringAsFixed(5)} → '
            '${cut.toStringAsFixed(5)} (300Hz 로 자르면)',
      );
    }

    // ── 8) 파일 이름 ──
    // 곡 이름을 안 쓰면 같은 장르 곡이 **전부 같은 파일 이름**이 된다.
    {
      final cases = <(String, String, String)>[
        ('새벽 네 시', '팝', '음악낙서장_새벽 네 시'),
        ('  여백  많은   이름 ', '팝', '음악낙서장_여백 많은 이름'),
        ('a/b:c*d?e"f<g>h|i', '팝', '음악낙서장_abcdefghi'),
        ('', '재즈', '음악낙서장_재즈'), // 이름이 없으면 장르로
        ('///', '재즈', '음악낙서장_재즈'), // 걷어 내니 아무것도 안 남으면 장르로
        ('.숨김', '팝', '음악낙서장_숨김'), // 점으로 시작하면 숨김 파일이 된다
        ('줄\n바꿈', '팝', '음악낙서장_줄바꿈'),
      ];
      for (final c in cases) {
        check(
          '8) 파일 이름 「${c.$1}」',
          exportStem(c.$1, c.$2) == c.$3,
          '→ ${exportStem(c.$1, c.$2)} (바라는 값 ${c.$3})',
        );
      }
      final long = exportStem('가' * 80, '팝');
      check(
        '8) 너무 긴 이름은 자른다',
        long.runes.length <= 36,
        '${long.runes.length}글자',
      );
    }

    // ── **내보낸 파일이 들리던 것과 같은 흔들림인가** ──
    //
    // 렌더는 다른 아이솔레이트에서 돈다. `Human` 은 static 이라 거기서는 늘 기본값
    // (1)으로 시작한다 — 실어 보내지 않으면 사용자가 「끔」으로 해 놓아도 파일에는
    // 흔들림이 들어간다. **들은 것과 파일이 다르면 그건 앱이 거짓말을 한 것이다.**
    // (마스터 페이더가 정확히 이 이유로 한 번 빠졌었다 — 2026-08-30)
    {
      ExportJob job(int human) => ExportJob(
        notes: [
          for (var i = 0; i < 8; i++)
            ['piano', 440.0, 0.1, 3, false, 0.0, i * 0.05, 2],
        ],
        drums: const [],
        busNames: const ['a'],
        buses: const {},
        masterVol: 1.0,
        seconds: 0.6,
        human: human,
      );

      List<int> once(int human) => renderWav(job(human));
      final off1 = once(0), off2 = once(0);
      var offSame = off1.length == off2.length;
      for (var i = 0; offSame && i < off1.length; i++) {
        if (off1[i] != off2[i]) offSame = false;
      }
      final on1 = once(2), on2 = once(2);
      var onSame = on1.length == on2.length;
      for (var i = 0; onSame && i < on1.length; i++) {
        if (on1[i] != on2[i]) onSame = false;
      }
      check(
        '흔들림이 파일까지 간다 (끄면 같고 켜면 다르다)',
        offSame && !onSame,
        '끔 같음 $offSame · 켬 다름 ${!onSame}',
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '내보내기 확인 통과' : '실패 $fail건');
    // **새로 생긴 길도 내보내기에 실리는가.**
    //
    // 타임라인 트랙 클립·덧줄·반음 줄은 전부 `buildSong` 을 거치므로 자동으로
    // 실려야 한다 — 「자동으로 실린다」는 **믿을 것이 아니라 재는 것**이다.
    // 재생과 내보내기가 갈라지면 「폰에서는 나는데 파일에는 없다」가 된다.
    {
      final q = Project.initial()..setGenre('lofi');
      final tr2 = Transport();
      final plain = SceneSequencer.buildSong(q, tr2);

      // ① 타임라인 트랙 클립
      final mel = q.tracks.firstWhere((t) => t.type == 'melody');
      final other = kMelodyPatterns.firstWhere((d) => d.bars <= 2);
      q.song.putLane(0, 0, mel.id, other.name);
      final withLane = SceneSequencer.buildSong(q, tr2);
      check(
        '내보내기 1) 트랙 클립이 실린다',
        withLane.notes.length != plain.notes.length,
        '${plain.notes.length} → ${withLane.notes.length}음',
      );

      // ② 덧줄(한 판에 화음+낱음)
      final chord = q.tracks.firstWhere((t) => t.type == 'chord');
      final cname = q.makeEditable(chord);
      final cd = q.userNote[cname]!;
      q.userNote[cname] = NotePatternDef(
        cd.name,
        cd.bars,
        cd.src,
        cd.notes,
        also: [
          [7, 0, 2, 3],
        ],
      );
      final withAlso = SceneSequencer.buildSong(q, tr2);
      check(
        '내보내기 2) 덧줄이 실린다',
        withAlso.notes.length > withLane.notes.length,
        '${withLane.notes.length} → ${withAlso.notes.length}음',
      );

      // ③ 반음 줄(프로 모드)
      final mname = q.makeEditable(mel);
      final md = q.userNote[mname]!;
      q.userNote[mname] = NotePatternDef(mname, md.bars, md.src, [
        [6, 0, 2, 2],
      ], chromatic: true);
      final key = MusicKey(root: tr2.root, mode: tr2.mode);
      final want = semiFreq(6, 'melody', key);
      final part = SceneSequencer.busNames(q).indexOf(mel.id);
      final pro = SceneSequencer.buildSong(q, tr2);
      check(
        '내보내기 3) 반음 줄이 그 소리로 실린다',
        pro.notes.any(
          (n) => n[7] == part && ((n[1] as double) - want).abs() < 0.01,
        ),
        '바라던 것 ${want.toStringAsFixed(2)}Hz',
      );

      // ④ **내보내기 일감이 재생과 같은 목록을 쓴다** — 여기가 갈라지면 끝이다.
      final j = _job(q, tr2);
      check(
        '내보내기 4) 재생과 같은 목록',
        j.notes.length == pro.notes.length &&
            j.drums.length == pro.drums.length,
        '음 ${j.notes.length}/${pro.notes.length} · '
            '드럼 ${j.drums.length}/${pro.drums.length}',
      );
    }

    expect(fail, 0);
  });
}
