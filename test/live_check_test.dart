// 5단계 13/N — 라이브 패드 확인.
//   flutter test test/live_check_test.dart
//
// 이 화면의 약속은 하나다: **아무 패드나 눌러도 지금 조에 맞는 음이 나온다.**
// 귀로는 확인이 안 된다 — 살짝 어긋난 음도 "그런 곡인가" 싶게 들리는 순간이 있다.
// 그래서 14개 패드의 주파수를 전부 꺼내 **음계 안에 있는지** 숫자로 본다.
// 조를 바꿔도(C단조 → F장조) 마찬가지여야 한다.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/live_ops.dart';
import 'package:music_doodle_engine/synth.dart' show kPartLive;
import 'package:music_doodle_engine/theory.dart';

/// 주파수 → MIDI 번호(반올림). 12평균율이라 되돌릴 수 있다.
int _midi(double f) => (69 + 12 * (math.log(f / 440) / math.ln2)).round();

void main() {
  test('라이브 패드', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    /// 그 조의 음계에 들어 있는 음정(피치클래스) 집합
    Set<int> pcsOf(MusicKey k) => {
      for (final s in kScale[k.mode]!) (s + k.root) % 12,
    };

    // 1) C단조 — 14개 패드가 전부 음계 안에 있다
    const cm = MusicKey(root: 0, mode: 'minor');
    final cmPc = pcsOf(cm);
    final cmNotes = [
      for (var d = 0; d < LivePads.count; d++)
        _midi(LivePads.freqOf(d, cm, 0)) % 12,
    ];
    check(
      '1) C단조 — 틀린 음 없음',
      cmNotes.every(cmPc.contains),
      '${cmNotes.length}개 전부 음계 안 · 음계 ${cmPc.toList()..sort()}',
    );

    // 2) 조를 바꾸면 따라간다 — F장조
    const fmaj = MusicKey(root: 5, mode: 'major');
    final fPc = pcsOf(fmaj);
    final fNotes = [
      for (var d = 0; d < LivePads.count; d++)
        _midi(LivePads.freqOf(d, fmaj, 0)) % 12,
    ];
    check(
      '2) F장조로 바꿔도',
      fNotes.every(fPc.contains) && fNotes.first == 5,
      '으뜸음 ${fNotes.first}(F=5) · ${fNotes.length}개 전부 음계 안',
    );

    // 3) 윗줄은 정확히 한 옥타브 위 — 아니면 두 줄이 같은 소리로 들린다
    final lo = LivePads.freqOf(0, cm, 0), hi = LivePads.freqOf(7, cm, 0);
    check(
      '3) 윗줄 = 한 옥타브 위',
      (hi / lo - 2).abs() < 1e-9,
      '${lo.toStringAsFixed(1)}Hz → ${hi.toStringAsFixed(1)}Hz (${(hi / lo).toStringAsFixed(3)}배)',
    );

    // 4) 옥타브 버튼 — +1 은 2배, -1 은 절반
    check(
      '4) 옥타브 이동',
      (LivePads.freqOf(0, cm, 1) / lo - 2).abs() < 1e-9 &&
          (LivePads.freqOf(0, cm, -1) / lo - 0.5).abs() < 1e-9,
      '+1 = ${LivePads.freqOf(0, cm, 1).toStringAsFixed(1)}Hz · -1 = ${LivePads.freqOf(0, cm, -1).toStringAsFixed(1)}Hz',
    );

    // 5) 화음 모드 — 그 도수의 다이아토닉 3화음 그대로
    final chords = diatonicChords(cm);
    var chordOk = true;
    for (var d = 0; d < 7; d++) {
      final want = chordFreqsOf(chords[d]);
      final got = LivePads.chordFreqs(d, cm, 0);
      if (got.length != want.length) chordOk = false;
      for (var i = 0; i < want.length && i < got.length; i++) {
        if ((got[i] - want[i]).abs() > 1e-9) chordOk = false;
      }
    }
    check(
      '5) 화음 = 다이아토닉 3화음',
      chordOk,
      '7도수 전부 일치 · 1도 ${LivePads.chordFreqs(0, cm, 0).length}음',
    );

    // 5-b) **화음이 라벨·단음·녹음과 같은 옥타브에 있는가.**
    //
    // 검사 5 는 C조만 보고, 게다가 `chordFreqsOf` 를 `chordFreqsOf` 와 견주는
    // 동어반복이라 옥타브 어긋남을 **원리적으로** 못 잡는다. 실제로 어긋나 있었다:
    // `diatonicChords` 는 근음을 `% 12` 로 접어 늘 C4 언저리에 쌓는데, 같은 패드의
    // 라벨·단음·녹음은 안 접힌 자리를 쓴다. C 조는 접힐 일이 없어 안 보였고,
    // A단조처럼 root 가 높은 조에서 도수 2~6 이 한 옥타브 밑으로 울렸다.
    // (그러고 녹음해 두면 재생은 안 접힌 자리로 나오니 **들은 것보다 한 옥타브 위**다)
    //
    // 그래서 세 길이 한자리에서 만나는지를 본다 — 한 조가 아니라 12조 전부.
    {
      var octOk = true;
      final bad = <String>[];
      for (var r = 0; r < 12; r++) {
        for (final mode in ['minor', 'major']) {
          final k = MusicKey(root: r, mode: mode);
          for (var d = 0; d < LivePads.count; d++) {
            final chordRoot = _midi(LivePads.chordFreqs(d, k, 0).first);
            final single = _midi(LivePads.freqOf(d, k, 0));
            if (chordRoot != single) {
              octOk = false;
              if (bad.length < 4) {
                bad.add('$r$mode ${d}도(화음 $chordRoot · 단음 $single)');
              }
            }
          }
        }
      }
      check(
        '5-b) 화음 밑음 = 단음 = 녹음 (12조 전부)',
        octOk,
        octOk ? '24조 × 14패드 전부 일치' : bad.join(' · '),
      );
    }

    // 6) 소리는 **전부 라이브 버스**로 — 여기가 틀리면 라이브 페이더가 안 먹고
    //    곡 트랙 버스에 얹혀 나간다(믹서에서 줄이면 반주까지 같이 줄어든다)
    var partOk = true, count = 0;
    for (final m in LiveMode.values) {
      for (var d = 0; d < LivePads.count; d++) {
        final ev = LivePads.events(
          d,
          mode: m,
          key: cm,
          oct: 0,
          voice: 'piano',
          dur: 0.9,
        );
        for (final e in ev) {
          count++;
          if (e[7] != kPartLive) partOk = false;
        }
      }
    }
    check('6) 라이브 버스로만', partOk, '이벤트 $count개 전부 kPartLive');

    // 7) 아르페지오는 시간차로 올라간다 — 한꺼번에 나면 그냥 화음이다
    final arp = LivePads.events(
      0,
      mode: LiveMode.arp,
      key: cm,
      oct: 0,
      voice: 'piano',
      dur: 0.5,
    );
    var rising = true;
    for (var i = 1; i < arp.length; i++) {
      if ((arp[i][6] as double) <= (arp[i - 1][6] as double)) rising = false;
      if ((arp[i][1] as double) <= (arp[i - 1][1] as double)) rising = false;
    }
    check(
      '7) 아르페지오',
      rising && arp.length >= 4,
      '${arp.length}음 · 시각 ${[for (final e in arp) (e[6] as double).toStringAsFixed(2)].join(' ')}',
    );

    // 8) 계이름 — 으뜸음 이름이 조와 맞는가(C단조=C, F장조=F)
    check(
      '8) 계이름',
      LivePads.midiOf(0, cm, 0) % 12 == 0 &&
          LivePads.midiOf(0, fmaj, 0) % 12 == 5,
      'C단조 1번 패드 ${LivePads.midiOf(0, cm, 0) % 12} · F장조 ${LivePads.midiOf(0, fmaj, 0) % 12}',
    );

    // ── 9) **메트로놈 — 앞질러 예약하기** ──
    //
    // 화면 타이머로 「지금」 울리면 박이 ±16ms 로 흔들린다 — 그건 자가 아니라 소음이다.
    // 앞질러 예약하고 시각은 엔진이 지킨다. 그 방식의 함정은 셋이다:
    // **두 번 놓기 · 건너뛰기 · 판 넘어가기.** 여기서 그 셋을 잰다.
    {
      const loop = 8.0, beat = 0.5; // 8초 판 · 120BPM(한 박 0.5초)
      // 9-a) 앞을 내다본 만큼만 낸다 · 지금 시각 기준 delay 로 낸다
      // 0.1초 자리에서 1초를 내다보면 0.5초·1.0초 두 박이 잡힌다.
      // (코앞의 박은 건너뛴다 — 이미 지나간 것을 예약하면 박이 앞으로 튄다)
      final a = beatsToSend(
        nowSec: 0.1,
        loopSec: loop,
        beatSec: beat,
        sent: <int>{},
        lead: 1.0,
      );
      check(
        '9-a) 앞질러 낼 박을 고른다',
        a.length == 2 &&
            a[0].beat == 1 &&
            (a[0].delay - 0.4).abs() < 1e-9 &&
            a[1].beat == 2 &&
            (a[1].delay - 0.9).abs() < 1e-9,
        a.map((t) => '${t.beat}박(+${t.delay.toStringAsFixed(2)}초)').join(' · '),
      );

      // 9-b) **같은 박을 두 번 안 낸다** — 두 번 놓으면 두 번 들린다
      final sent = <int>{};
      var total = 0;
      for (var step = 0; step < 40; step++) {
        final now = step * 0.2; // 0.2초마다 부른다
        if (now >= loop) break;
        final ticks = beatsToSend(
          nowSec: now,
          loopSec: loop,
          beatSec: beat,
          sent: sent,
        );
        for (final t in ticks) {
          sent.add(t.beat);
        }
        total += ticks.length;
      }
      check(
        '9-b) 같은 박을 두 번 안 낸다',
        total == sent.length,
        '낸 것 $total번 · 서로 다른 박 ${sent.length}개',
      );

      // 9-c) **건너뛰지 않는다** — 8초 판 120BPM 이면 박이 16개(0~15)
      final missing = [
        for (var k = 1; k < 16; k++)
          if (!sent.contains(k)) k,
      ];
      check(
        '9-c) 건너뛰는 박이 없다',
        missing.isEmpty,
        missing.isEmpty ? '1~15박 전부' : '빠진 박 ${missing.join(',')}',
      );

      // 9-d) **판을 넘는 박은 안 낸다** — 넘어가면 기록을 비우므로 다음 바퀴가 잡는다
      final over = beatsToSend(
        nowSec: 7.9,
        loopSec: loop,
        beatSec: beat,
        sent: <int>{},
        lead: 1.0,
      );
      check(
        '9-d) 판을 넘는 박은 안 낸다',
        over.isEmpty,
        '${over.length}개 (8초 판의 7.9초 자리)',
      );

      // 9-e) 이상한 값에도 안 죽는다
      final bad =
          beatsToSend(
            nowSec: 0,
            loopSec: 0,
            beatSec: 0.5,
            sent: <int>{},
          ).length +
          beatsToSend(nowSec: 0, loopSec: 8, beatSec: 0, sent: <int>{}).length;
      check('9-e) 0초 판·0초 박에도 안 죽는다', bad == 0, '$bad개');
    }

    // ignore: avoid_print
    print(fail == 0 ? '라이브 패드 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
