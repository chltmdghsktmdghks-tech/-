// Phase 3 — **대표 악기 품질 기준.** (개선 계획 5-1·5-2)
//   flutter test test/instrument_quality_test.dart
//
// 계획이 대표 악기 열 개를 꼽고, 각각 다섯 가지를 보라고 한다.
// 이미 있는 것과 없는 것을 갈라 보면:
//
//   1. 기본 음색            — 웹에서 검증된 배음표를 그대로 쓴다
//   2. 세기 반응            — `env_check_test` · `drum_check_test` 가 본다
//   3. **음역별 자연스러움** — 없었다 ← 여기서 만든다
//   4. **연속 연주**        — 없었다 ← 여기서 만든다
//   5. **믹스 안 존재감**   — 없었다 ← 여기서 만든다
//
// 계획이 못 박은 우선순위: **"단독으로 좋은 소리보다 Mix 안에서 좋은 소리"**.
// 그래서 5번이 제일 중요하다 — 혼자 들으면 멀쩡한데 곡에 넣으면 사라지는 악기가
// 실제로 있었다(53/N 피아노, 세기가 두 번 곱해지던 버그).
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/engine.dart';
import 'package:music_doodle_engine/genre_mix.dart';
import 'package:music_doodle_engine/instruments.dart' show ALL_VOICES;
import 'package:music_doodle_engine/synth.dart';

/// 계획 5-1 의 대표 악기 → 이 프로젝트의 음색 이름.
/// (킥·스네어·하이햇은 타악기라 `drum_check_test` 가 따로 본다)
const _voices = {
  '베이스': 'fingerbass',
  '서브 베이스': 'sine',
  '피아노': 'piano',
  '일렉 피아노': 'epiano',
  '패드': 'pad',
  '리드': 'lead',
  '플럭': 'pluck',
};

double _midi(int n) => 440 * math.pow(2, (n - 69) / 12).toDouble();

List<double> _render(Engine e, double sec) {
  final total = (sec * kSampleRate).round();
  final out = List<double>.filled(total, 0);
  var done = 0;
  while (done < total) {
    final n = math.min(1024, total - done);
    final pcm = e.render(n);
    for (var i = 0; i < n; i++) {
      out[done + i] = (pcm[i * 2] + pcm[i * 2 + 1]) / 2 / 32768.0;
    }
    done += n;
  }
  return out;
}

Engine _eng() => Engine()..trackMix.configure(['a']);

double _rmsDb(List<double> x, {int from = 0, int? to}) {
  final end = to ?? x.length;
  var e = 0.0;
  for (var i = from; i < end && i < x.length; i++) {
    e += x[i] * x[i];
  }
  final r = math.sqrt(e / math.max(1, end - from));
  return r <= 1e-9 ? -120 : 20 * math.log(r) / math.ln10;
}

double _peak(List<double> x, {int from = 0, int? to}) {
  final end = to ?? x.length;
  var p = 0.0;
  for (var i = from; i < end && i < x.length; i++) {
    final a = x[i].abs();
    if (a > p) p = a;
  }
  return p;
}

/// 한 음을 치고 [sec] 초 받아 온다.
List<double> _note(
  String voice,
  int midi,
  int vel, {
  double dur = 0.5,
  double sec = 1.2,
}) {
  final e = _eng();
  e.schedule(0.01, voice, _midi(midi), dur, vel, part: kPartBass);
  return _render(e, sec);
}

void main() {
  test('대표 악기 품질', () {
    Human.setLevel(0);
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $what — $detail');
      if (!ok) fail++;
    }

    // ══ 3. 음역별 자연스러움 ══
    //
    // 같은 악기를 낮게·가운데·높게 쳤을 때 **크기가 고르게 나와야** 한다.
    // 한 음역만 크거나 작으면 그 악기는 그 음역에서 사라지거나 튄다.
    // (피아노를 낮게 치면 안 들리고 높게 치면 째지는 것이 이 문제다)
    // ignore: avoid_print
    print('\n── 3. 음역별 (같은 세기로 세 옥타브) ──');
    for (final e in _voices.entries) {
      // 베이스 계열은 두 옥타브 낮게 본다 — 원래 그 음역을 쓰는 악기다
      final low = e.value == 'fingerbass' || e.value == 'sine' ? 28 : 48;
      final mids = [low, low + 12, low + 24];
      final dbs = [
        for (final m in mids)
          _rmsDb(_note(e.value, m, 3), to: (0.4 * kSampleRate).round()),
      ];
      final spread = dbs.reduce(math.max) - dbs.reduce(math.min);
      check(
        '  ${e.key.padRight(7)} 음역 균형',
        spread < 12,
        '${dbs.map((d) => d.toStringAsFixed(1)).join(' / ')}dB · 벌어짐 ${spread.toStringAsFixed(1)}dB',
      );
    }

    // ══ 4. 연속 연주 ══
    //
    // 같은 음을 16분음표로 여덟 번 친다. **뒷음이 앞음에 먹히면 안 된다.**
    // 앞 음의 꼬리가 남아 있는 상태에서 다시 치면, 엔벨로프나 목소리 재활용이
    // 잘못돼 있을 때 뒷음이 안 들리거나 뚝 끊긴다.
    // ignore: avoid_print
    print('\n── 4. 연속 연주 (같은 음 16분 8번) ──');
    const gap = 0.125; // 120BPM 16분
    for (final e in _voices.entries) {
      final eng = _eng();
      final base = e.value == 'fingerbass' || e.value == 'sine' ? 40 : 60;
      for (var i = 0; i < 8; i++) {
        eng.schedule(
          0.01 + i * gap,
          e.value,
          _midi(base),
          gap * 0.9,
          3,
          part: kPartBass,
        );
      }
      final x = _render(eng, 0.01 + gap * 8 + 0.3);
      // 각 음의 앞 30ms 에서 봉우리를 잰다 — 다 비슷해야 한다
      final peaks = [
        for (var i = 0; i < 8; i++)
          _peak(
            x,
            from: ((0.01 + i * gap) * kSampleRate).round(),
            to: ((0.01 + i * gap + 0.03) * kSampleRate).round(),
          ),
      ];
      final lo = peaks.reduce(math.min), hi = peaks.reduce(math.max);
      // 뒷음이 앞음의 40% 아래로 떨어지면 '먹혔다'고 본다
      check(
        '  ${e.key.padRight(7)} 8연타',
        lo > hi * 0.4,
        '제일 작은 것 ${(lo / hi * 100).toStringAsFixed(0)}% '
            '(${peaks.map((p) => (p / hi * 100).round()).join('·')})',
      );
    }

    // ══ 5. 믹스 안 존재감 ══
    //
    // **계획이 제일 앞에 둔 기준이다.** 같은 세기로 쳤을 때 악기끼리 크기가
    // 너무 벌어지면, 곡에 같이 넣는 순간 작은 쪽이 사라진다.
    // (53/N 에서 피아노가 그랬다 — 세기가 두 번 곱해져 −21dB 였다)
    // ignore: avoid_print
    print('\n── 5. 믹스 존재감 (같은 세기 3, 같은 음) ──');
    final loud = <String, double>{};
    for (final e in _voices.entries) {
      final m = e.value == 'fingerbass' || e.value == 'sine' ? 40 : 60;
      loud[e.key] = _rmsDb(
        _note(e.value, m, 3),
        to: (0.3 * kSampleRate).round(),
      );
    }
    final sorted = loud.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    // ignore: avoid_print
    print(
      '     ${sorted.map((e) => '${e.key} ${e.value.toStringAsFixed(1)}').join(' · ')}',
    );

    // **저역 악기와 중역 악기를 같은 자로 재면 안 된다.** 베이스가 큰 것은
    // 정상이다 — 저역이 에너지를 훨씬 많이 쓴다. 곡에서는 믹서 페이더가
    // 그 차이를 잡는다. 문제가 되는 것은 **같은 자리를 다투는 악기끼리** 벌어질 때다.
    const midRange = ['피아노', '일렉 피아노', '패드', '리드', '플럭'];
    final mid = [for (final k in midRange) loud[k]!];
    final midSpan = mid.reduce(math.max) - mid.reduce(math.min);
    check(
      '  중역 악기끼리 크기 차이',
      midSpan < 9,
      '${midSpan.toStringAsFixed(1)}dB (${midRange.length}종)',
    );

    // 드럼과 견줘도 묻히면 안 된다 — 곡에서 제일 큰 것이 드럼이다
    final kickDb = () {
      final eng = _eng();
      eng.scheduleDrum(0.01, 'acoustic', 'kick', 3);
      return _rmsDb(_render(eng, 0.5), to: (0.3 * kSampleRate).round());
    }();
    final quietest = sorted.last;
    check(
      '  제일 작은 악기도 킥에 안 묻힌다',
      quietest.value > kickDb - 20,
      '${quietest.key} ${quietest.value.toStringAsFixed(1)}dB · '
          '킥 ${kickDb.toStringAsFixed(1)}dB '
          '(차이 ${(kickDb - quietest.value).toStringAsFixed(1)}dB)',
    );

    // ══ 6. 폰 스피커 — 모노로 합쳐도 사라지지 않는가 ══ (계획 5-3 Stereo behavior)
    //
    // **이 앱의 목적지는 폰이다.** 폰 스피커는 사실상 모노라, 좌우로 벌린 소리가
    // 합쳐질 때 서로 지우면 그 악기는 폰에서 안 들린다. 헤드폰으로는 멀쩡한데
    // 폰에서만 사라지는 것이라 귀로 잡기 제일 어려운 종류다.
    // ignore: avoid_print
    print('\n── 6. 모노 합산 (폰 스피커) ──');
    {
      final bad = <String>[];
      var worst = 0.0;
      String worstName = '';
      for (final v in ALL_VOICES) {
        final e = _eng();
        e.schedule(0.01, v, _midi(60), 0.6, 3, part: kPartBass);
        final n = (1.0 * kSampleRate).round();
        var sl = 0.0, sr = 0.0, mono = 0.0;
        var done = 0;
        while (done < n) {
          final k = math.min(1024, n - done);
          final pcm = e.render(k);
          for (var i = 0; i < k; i++) {
            final l = pcm[i * 2] / 32768.0, r = pcm[i * 2 + 1] / 32768.0;
            sl += l * l;
            sr += r * r;
            final m = (l + r) * 0.5;
            mono += m * m;
          }
          done += k;
        }
        if (sl + sr <= 0) continue;
        final loss =
            10 * math.log(((sl + sr) / 2) / math.max(mono, 1e-30)) / math.ln10;
        if (loss > worst) {
          worst = loss;
          worstName = v;
        }
        if (loss > 1.5) bad.add('$v ${loss.toStringAsFixed(1)}dB');
      }
      check(
        '  모노로 합쳐도 안 사라진다',
        bad.isEmpty,
        '제일 큰 손실 $worstName ${worst.toStringAsFixed(2)}dB '
            '(${ALL_VOICES.length}종 · 기준 1.5dB)',
      );
    }

    // 저역은 **가운데**여야 한다. 저음을 좌우로 벌리면 힘이 빠지고,
    // 폰처럼 모노로 합쳐지는 곳에서 특히 그렇다.
    {
      final off = <String>[];
      for (final v in ['bass', 'fingerbass', 'moogbass', 'upright', 'sine']) {
        final e = _eng();
        e.schedule(0.01, v, _midi(40), 0.6, 3, part: kPartBass);
        final n = (0.8 * kSampleRate).round();
        var sl = 0.0, sr = 0.0;
        var done = 0;
        while (done < n) {
          final k = math.min(1024, n - done);
          final pcm = e.render(k);
          for (var i = 0; i < k; i++) {
            sl += math.pow(pcm[i * 2] / 32768.0, 2);
            sr += math.pow(pcm[i * 2 + 1] / 32768.0, 2);
          }
          done += k;
        }
        final bal = (sr - sl) / math.max(sr + sl, 1e-30);
        if (bal.abs() > 0.12) off.add('$v ${bal.toStringAsFixed(2)}');
      }
      check(
        '  저역은 가운데',
        off.isEmpty,
        off.isEmpty ? '베이스 5종 모두 중앙' : off.join(', '),
      );
    }

    // ══ 7. 비용 ══ (계획 5-3 "CPU 사용량을 함께 측정하십시오")
    //
    // 악기 하나가 갑자기 몇 배로 비싸지면 폰에서 소리가 끊긴다.
    // **실제 곡**으로 잰다 — 8음을 억지로 쌓은 값은 겁만 준다(실제 곡은 14~21음이다).
    // 맥(JIT) 기준이고 폰은 약 8배다. 한도를 넉넉히(3배) 둬서 **진짜 회귀만** 잡는다.
    {
      final buf = Int16List(1024 * 2);
      final e = _eng();
      // 재즈가 제일 비싸다(피아노+비브라폰+색소폰+기타) — 그걸 흉내 낸다
      for (var bar = 0; bar < 40; bar++) {
        final t = bar * 0.5;
        e.scheduleDrum(t, 'acoustic', 'kick', 3);
        e.scheduleDrum(t + 0.25, 'acoustic', 'ride', 2);
        e.schedule(t, 'upright', 98.0, 0.45, 3, part: kPartBass);
        for (final f in [261.63, 311.13, 392.0, 466.16]) {
          e.schedule(t, 'epiano', f, 0.9, 2, soft: true, part: kPartBass);
        }
        e.schedule(t + 0.25, 'sax', 523.25, 0.3, 3, part: kPartBass);
        e.schedule(t + 0.375, 'nylon', 349.23, 0.3, 2, part: kPartBass);
      }
      final rounds = (20.0 * kSampleRate / 1024).round();
      final sw = Stopwatch()..start();
      for (var r = 0; r < rounds; r++) {
        e.renderInto(buf, 1024);
      }
      sw.stop();
      final pct = sw.elapsedMicroseconds / 1e6 / 20.0 * 100;
      check(
        '  빽빽한 곡 한 대목이 실시간을 안 넘는다',
        pct < 15,
        '맥 ${pct.toStringAsFixed(1)}% · 폰 추정 ${(pct * 8).toStringAsFixed(0)}% '
            '· 최대 동시 ${e.maxActive}음 (한도 15%)',
      );
    }

    // ══ 8. 킥↔베이스 비켜 주기 ══ (계획 6-5 Auto Mix)
    //
    // 계획이 제일 먼저 꼽은 충돌이다. 둘 다 저역을 쓰니 겹치면 킥이 뭉개지거나
    // 베이스가 안 들린다. 표준 처리는 **킥이 칠 때 나머지를 잠깐 낮추는 것**.
    // ignore: avoid_print
    print('\n── 8. 비켜 주기 ──');
    {
      // **두 렌더를 빼서 본다.**
      //
      // 크기 비율(dB)로 재려다 세 번 헛짚었다. 킥이 멜로디보다 7배 커서,
      // 멜로디를 **통째로 지워도** 전체 RMS 는 1dB 밖에 안 움직인다 — 산수 문제다.
      // 드럼은 비켜 주기를 안 받으므로 두 렌더에서 똑같다. 그러니
      // **차이 신호 = 눌린 멜로디**다. 이건 헷갈릴 여지가 없다.
      List<double> run(double amount) {
        final e = _eng()..duckAmount = amount;
        e.schedule(0.0, 'lead', _midi(72), 3.0, 3, part: kPartBass);
        e.scheduleDrum(0.5, 'acoustic', 'kick', 3);
        return _render(e, 1.2);
      }

      final dry = run(0), wet = run(0.45);

      /// [t] 부터 10ms 안에서 두 렌더가 제일 많이 벌어진 값.
      double gap(double t) {
        final f = (t * kSampleRate).round();
        final to = ((t + 0.01) * kSampleRate).round();
        var d = 0.0;
        for (var i = f; i < to && i < dry.length; i++) {
          final x = (dry[i] - wet[i]).abs();
          if (x > d) d = x;
        }
        return d;
      }

      // 킥 **직전**의 멜로디 크기 — 기준이 된다
      final melody = _peak(
        dry,
        from: (0.46 * kSampleRate).round(),
        to: (0.49 * kSampleRate).round(),
      );
      final atKick = gap(0.50);
      final mid = gap(0.60);
      final late = gap(0.90);

      check('  안 걸면 안 눌린다', gap(0.46) < 1e-9, '킥 전에는 차이 0');
      // 0.45 로 걸면 멜로디의 45% 가 깎인다
      check(
        '  걸면 눌린다',
        atKick > melody * 0.3 && atKick < melody * 1.3,
        '멜로디 ${melody.toStringAsFixed(4)} 중 ${atKick.toStringAsFixed(4)} 깎임 '
            '(${(atKick / melody * 100).round()}%)',
      );
      // **되돌아와야 한다** — 계속 눌린 채면 곡이 통째로 작아진다
      check(
        '  되돌아온다',
        mid < atKick && late < atKick * 0.25,
        '직후 ${atKick.toStringAsFixed(4)} → 0.1초 ${mid.toStringAsFixed(4)} '
            '→ 0.4초 ${late.toStringAsFixed(4)}',
      );

      // **장르마다 다르다** — 재즈·발라드·록에 펌핑을 걸면 그건 고장이다
      final acoustic = [
        'jazz',
        'ballad',
        'rock',
      ].where((g) => (kGenreDuck[g] ?? 0) > 0).toList();
      check(
        '  어쿠스틱 장르는 안 건다',
        acoustic.isEmpty,
        acoustic.isEmpty ? '재즈·발라드·록 전부 0' : '걸려 있음: ${acoustic.join(', ')}',
      );
      check(
        '  전기 장르는 건다',
        (kGenreDuck['house'] ?? 0) > 0.2 &&
            (kGenreDuck['proghouse'] ?? 0) > 0.2,
        '하우스 ${kGenreDuck['house']} · 프로그 ${kGenreDuck['proghouse']}',
      );
    }

    // ── 금속 클러스터(하이햇·크래시·라이드)를 하나로 구울 때 ──
    //
    // 보급형 폰에서는 오실레이터 6개 대신 **한 파형에 미리 구운 것**을 쓴다
    // (`metalWave`, `highQuality == false` 경로). 6개를 배음 칸에 반올림해
    // 넣는데, 기본음이 너무 높으면 칸이 성겨서 서로 겹친다 — 예전엔 실제로
    // 6개가 4칸으로 뭉갰고, 살아남은 두 칸이 정확히 옥타브(2:1)라
    // 「정수배가 아니어야 심벌답다」는 이 코드의 목적과 정반대로 갔다.
    {
      const h = 64;
      final bins = [
        for (final f in kMetalF) (f / kMetalFund).round().clamp(1, h),
      ];
      check(
        '금속 1) 여섯이 각자 칸을 얻는다',
        bins.toSet().length == kMetalF.length,
        '칸 $bins — ${bins.toSet().length}/${kMetalF.length}가지',
      );

      // 3배음도 같이 굽는다 — 그게 64를 넘으면 마지막 칸에 몰려 도로 뭉갠다
      final h3 = [for (final b in bins) b * 3];
      check(
        '금속 2) 3배음도 칸 안에 들어온다',
        h3.every((v) => v <= h),
        '3배음 최대 ${h3.reduce(math.max)} / $h',
      );

      // 실제로 나는 주파수가 노린 값에 얼마나 가까운가 — 반음(100센트)의
      // 절반 안이면 귀로는 같은 음이다.
      var worst = 0.0;
      for (var i = 0; i < kMetalF.length; i++) {
        final got = bins[i] * kMetalFund;
        final cents = (1200 * math.log(got / kMetalF[i]) / math.ln2).abs();
        if (cents > worst) worst = cents;
      }
      check('금속 3) 노린 주파수에서 반음 안', worst < 100, '제일 먼 것 ${worst.round()}센트');

      // **없던 정수배를 만들어 내면 안 된다.**
      //
      // 「6개가 서로 정수배가 아니어야 한다」로 재면 안 된다 — 원본 여섯 중
      // 두 짝(1153:2247 · 1478:2996)이 **이미** 옥타브에서 45·23센트 안이다.
      // 그런 짝이 반올림으로 딱 2:1 에 앉는 건 어쩔 수 없고 귀에도 그대로다.
      //
      // 잡아야 하는 건 **원본에는 없던 정수배**다. 예전 버그가 정확히 그것이었다:
      // 821 과 1153(비율 1.40, 어느 정수배와도 멀다)이 같은 칸에 뭉개지면서
      // 살아남은 칸들이 딱 2:1·3:1 이 됐다.
      final invented = <String>[];
      for (var i = 0; i < bins.length; i++) {
        for (var j = i + 1; j < bins.length; j++) {
          if (bins[j] % bins[i] != 0) continue;
          final want = bins[j] ~/ bins[i];
          if (want < 2) continue;
          // 원본에서 이 짝이 그 정수배에 얼마나 가까웠나
          final src = kMetalF[j] / kMetalF[i];
          final cents = (1200 * math.log(src / want) / math.ln2).abs();
          if (cents > 60) invented.add('${kMetalF[i]}:${kMetalF[j]}');
        }
      }
      check(
        '금속 4) 없던 정수배를 만들지 않는다',
        invented.isEmpty,
        invented.isEmpty ? '없음' : '새로 생긴 정수배 ${invented.join(' · ')}',
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '\n대표 악기 품질 통과' : '\n실패 $fail건');
    expect(fail, 0);
  });
}
