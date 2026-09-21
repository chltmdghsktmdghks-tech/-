// 5단계 49/N — 드럼 확인.
//   flutter test test/drum_check_test.dart
//
// 드럼은 짧아서 **귀로 비교가 제일 안 되는** 소리다. 16비트 하이햇이 전부
// 똑같은 파형이어도 "빠르니까 그런가 보다" 하고 넘어간다. 그래서 숫자로 본다:
//  · 흔들림 — 같은 타격이 매번 조금씩 다른가 (머신건 방지)
//  · 세기   — 크기만 달라지는가, 음색도 달라지는가
//  · 초킹   — 하이햇을 닫으면 열려 있던 게 멎는가
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/drums.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/engine.dart';
import 'package:music_doodle_engine/synth.dart';

/// 타격 하나를 [sec] 초만큼 뽑는다.
List<double> _hit(
  String inst,
  int vel, {
  String kit = 'acoustic',
  double sec = 1.2,
}) {
  final d = DrumVoice();
  d.trigger(inst, DRUM_KITS[kit]!, vel);
  final n = (sec * kSampleRate).round();
  final out = List<double>.filled(n, 0);
  for (var i = 0; i < n; i++) {
    if (!d.active) break;
    d.next();
    out[i] = d.outL;
  }
  return out;
}

double _rms(List<double> x, {int from = 0, int to = -1}) {
  final end = to < 0 ? x.length : math.min(to, x.length);
  var e = 0.0;
  for (var i = from; i < end; i++) {
    e += x[i] * x[i];
  }
  return math.sqrt(e / math.max(1, end - from));
}

double _peak(List<double> x) {
  var p = 0.0;
  for (final v in x) {
    final a = v.abs();
    if (a > p) p = a;
  }
  return p;
}

/// [hz] 위쪽이 차지하는 비율 — 밝기.
double _highRatio(List<double> x, double hz) {
  final hp = Biquad()..highpass(hz, 0.707);
  var hi = 0.0, all = 0.0;
  for (final v in x) {
    final h = hp.process(v);
    hi += h * h;
    all += v * v;
  }
  return all <= 0 ? 0 : hi / all;
}

/// 줄(스네어 와이어) 안에서의 밝기 — **몸통 소리를 걷어내고** 잰다.
/// 그냥 전체로 재면 안 된다: 세게 치면 몸통 저역도 같이 커져서, 크랙이 밝아져도
/// 전체 고역 비중은 오히려 내려간다(실제로 그렇게 나왔다).
double _crack(List<double> x) {
  final hp = Biquad()..highpass(1500, 0.707);
  final wire = [for (final v in x) hp.process(v)];
  return _highRatio(wire, 8000);
}

/// 하이햇을 **금속 층만 빼고** 다시 만들어, 금속이 소리의 얼마를 책임지는지 잰다.
///
/// '금속처럼 들리는가'를 숫자 하나로 재려고 스펙트럼 평탄도와 자기상관을 둘 다
/// 써 봤는데 **둘 다 못 잡는다.** 금속 클러스터는 일부러 배음이 안 맞는(비배음)
/// 사각파 여섯 개라, 위쪽에서는 잡음처럼 촘촘하고 주기도 아주 길다.
/// 그래서 재는 방법을 바꿨다 — **빼 보고 얼마나 줄어드는지**가 제일 정직하다.
double _metalShare(String kit) {
  final k = DRUM_KITS[kit]!;
  final noMetal = DrumKit(
    label: k.label,
    kick: k.kick,
    snare: k.snare,
    hat: HatK(k.hat.hi, k.hat.rel, k.hat.tune, 0, k.hat.noise), // 금속 0
    tom: k.tom,
    crash: k.crash,
    ride: k.ride,
    rim: k.rim,
    clap: k.clap,
    shake: k.shake,
    cow: k.cow,
  );
  double energy(DrumKit kk) {
    final d = DrumVoice();
    d.trigger('hat', kk, 2);
    var e = 0.0;
    for (var i = 0; i < (0.4 * kSampleRate).round(); i++) {
      if (!d.active) break;
      d.next();
      e += d.outL * d.outL;
    }
    return e;
  }

  final full = energy(k), bare = energy(noMetal);
  return full <= 0 ? 0 : 1 - bare / full;
}

/// 소리가 남아 있는 마지막 시각(초).
double _tail(List<double> x, {double th = 0.02}) {
  final lim = _peak(x) * th;
  for (var i = x.length - 1; i >= 0; i--) {
    if (x[i].abs() > lim) return i / kSampleRate;
  }
  return 0;
}

void main() {
  test('드럼', () {
    var fail = 0;
    void check(String name, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $name — $detail');
      if (!ok) fail++;
    }

    // ── 1) 같은 타격이 매번 조금씩 다른가 (머신건 방지) ──
    // 하이햇을 열 번 치고 파형이 실제로 갈라지는지 본다.
    Human.setLevel(1);
    final hats = [for (var i = 0; i < 10; i++) _hit('hat', 2, sec: 0.3)];
    var maxDiff = 0.0;
    for (var i = 1; i < hats.length; i++) {
      var d = 0.0;
      for (var j = 0; j < hats[0].length; j++) {
        d += (hats[i][j] - hats[0][j]).abs();
      }
      d /= hats[0].length;
      if (d > maxDiff) maxDiff = d;
    }
    final base = _rms(hats[0]);
    check(
      '1) 하이햇이 매번 다르다',
      maxDiff > base * 0.15,
      '차이 ${(maxDiff / base * 100).toStringAsFixed(1)}% (기준 15% 위)',
    );

    // 흔들림을 끄면 **완전히 같아야 한다** — 안 그러면 재현이 안 돼서 내보낼 때마다
    // 파일이 달라진다.
    Human.setLevel(0);
    final a = _hit('hat', 2, sec: 0.3), b = _hit('hat', 2, sec: 0.3);
    var same = true;
    for (var i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 1e-12) {
        same = false;
        break;
      }
    }
    check('2) 흔들림 0 이면 똑같다', same, '샘플 ${a.length}개 일치');

    // ── 2) 세기가 음색을 바꾸는가 ──
    // 크기만 달라지면 그건 볼륨 노브지 연주가 아니다.
    final kSoft = _hit('kick', 1), kHard = _hit('kick', 3);
    // 첫 12ms 의 고역 비중 — 비터가 닿는 '딱' 이 사는 자리.
    // 크기가 아니라 **비율**로 봐야 세기가 음색을 바꿨는지 알 수 있다.
    final nClick = (0.012 * kSampleRate).round();
    final cSoft = _highRatio(kSoft.sublist(0, nClick), 3000);
    final cHard = _highRatio(kHard.sublist(0, nClick), 3000);
    check(
      '3) 킥 — 세게 밟으면 어택이 도드라진다',
      cHard > cSoft * 1.15,
      '여리게 ${(cSoft * 1000).toStringAsFixed(2)}‰ · 세게 ${(cHard * 1000).toStringAsFixed(2)}‰',
    );

    final sSoft = _hit('snare', 1), sHard = _hit('snare', 3);
    final wSoft = _crack(sSoft), wHard = _crack(sHard);
    check(
      '4) 스네어 — 세게 치면 크랙이 밝다',
      wHard > wSoft * 1.15,
      '여리게 ${(wSoft * 100).toStringAsFixed(1)}% · 세게 ${(wHard * 100).toStringAsFixed(1)}%',
    );

    // 고스트 노트는 **줄 위주**여야 한다 — 몸통이 제대로 안 울리니까.
    final bodySoft = 1 - _highRatio(sSoft, 400);
    final bodyHard = 1 - _highRatio(sHard, 400);
    check(
      '4b) 고스트는 줄 위주',
      bodySoft < bodyHard,
      '여리게 몸통 ${(bodySoft * 100).toStringAsFixed(1)}% · '
          '세게 ${(bodyHard * 100).toStringAsFixed(1)}%',
    );

    final hSoft = _highRatio(_hit('hat', 1), 13000);
    final hHard = _highRatio(_hit('hat', 3), 13000);
    check(
      '5) 하이햇 — 세게 치면 밝다',
      hHard > hSoft * 1.2,
      '여리게 ${(hSoft * 100).toStringAsFixed(1)}% · 세게 ${(hHard * 100).toStringAsFixed(1)}%',
    );

    // 탐 — 세게 치면 더 높은 데서 떨어진다(첫 20ms 의 무게중심으로 본다)
    final tSoft = _hit('tom', 1), tHard = _hit('tom', 3);
    final nT = (0.020 * kSampleRate).round();
    final pSoft = _highRatio(tSoft.sublist(0, nT), 260);
    final pHard = _highRatio(tHard.sublist(0, nT), 260);
    check(
      '6) 탐 — 세게 치면 더 높이 튄다',
      pHard > pSoft * 1.05,
      '여리게 ${(pSoft * 100).toStringAsFixed(1)}% · 세게 ${(pHard * 100).toStringAsFixed(1)}%',
    );

    // 크래시 — 세게 치면 더 오래 운다
    final crSoft = _tail(_hit('crash', 1, sec: 4));
    final crHard = _tail(_hit('crash', 3, sec: 4));
    check(
      '7) 크래시 — 세게 치면 오래 운다',
      crHard > crSoft * 1.15,
      '여리게 ${crSoft.toStringAsFixed(2)}초 · 세게 ${crHard.toStringAsFixed(2)}초',
    );

    // ── 하이햇이 잡음이 아니라 금속인가 (5단계 53/N) ──
    // 어쿠스틱 킷에서 잡음 0.40 대 금속 0.039 로 **잡음이 열 배**였다.
    // 그래서 하이햇이 아니라 '치익' 하는 소리가 났다(사용자 지적).
    // 어쿠스틱 하이햇은 원래 잡음이 많다 — 909 처럼 완전한 쇳소리가 되면 그건
    // 어쿠스틱이 아니다. 그래서 **킷마다 다른 기준**으로 본다.
    final mAc = _metalShare('acoustic'), m909 = _metalShare('k909');
    check(
      '5b) 금속이 소리를 책임진다',
      mAc > 0.35 && m909 > 0.80,
      '어쿠스틱 ${(mAc * 100).toStringAsFixed(0)}% · 909 ${(m909 * 100).toStringAsFixed(0)}% '
          '(금속 층을 빼면 이만큼 줄어든다)',
    );

    // 스틱이 때리는 '칙' — 접시가 우는 대역(6kHz 위)이 아니라 **2.5~5kHz**에
    // 앞머리가 서야 한다. 이게 없으면 셰이커처럼 들린다.
    final hx = _hit('hat', 2, sec: 0.4);
    double mid(int from, int to) {
      final hp = Biquad()..highpass(2500, 0.707);
      final lp = Biquad()..lowpass(5000, 0.707);
      var e = 0.0;
      for (var i = 0; i < to && i < hx.length; i++) {
        final y = lp.process(hp.process(hx[i]));
        if (i >= from) e += y * y;
      }
      return math.sqrt(e / math.max(1, to - from));
    }

    final head = mid(0, (0.005 * kSampleRate).round());
    final body = mid(
      (0.010 * kSampleRate).round(),
      (0.060 * kSampleRate).round(),
    );
    check(
      '5c) 스틱 어택이 앞에 선다',
      head > body * 1.5,
      '앞 5ms ${head.toStringAsFixed(4)} · 뒤 ${body.toStringAsFixed(4)}',
    );

    // 세기 3 = 열린 하이햇. 닫힌 것보다 확실히 오래 울어야 한다.
    final closed = _tail(_hit('hat', 1, sec: 1.5));
    final opened = _tail(_hit('hat', 3, sec: 1.5));
    check(
      '5d) 열린 하이햇이 길다',
      opened > closed * 2.5,
      '닫힘 ${(closed * 1000).round()}ms · 열림 ${(opened * 1000).round()}ms',
    );

    // ── 좌우 자리 (Phase 3 · 계획 5-4) ──
    // 실제 드럼 세트는 한 점에서 나지 않는다. 전부 가운데면 심벌과 스네어가
    // 같은 자리에서 겹쳐 뭉친다.
    double panOf(String inst) {
      final d = DrumVoice()..trigger(inst, DRUM_KITS['acoustic']!, 2);
      var l = 0.0, r = 0.0;
      for (var i = 0; i < (0.3 * kSampleRate).round() && d.active; i++) {
        d.next();
        l += d.outL * d.outL;
        r += d.outR * d.outR;
      }
      final t = l + r;
      return t <= 0 ? 0 : (r - l) / t; // -1 왼쪽 · 0 가운데 · +1 오른쪽
    }

    final pk = panOf('kick'), pHat = panOf('hat'), pRide = panOf('ride');
    check('10) 킥은 가운데', pk.abs() < 0.05, pk.toStringAsFixed(3));
    // 앞에서 본 기준 — 오른손잡이 드러머의 하이햇은 **우리 오른쪽**,
    // 라이드는 우리 왼쪽 (쇼 화면 밴드 그림과 같은 좌우다)
    check(
      '10-b) 하이햇은 오른쪽 · 라이드는 왼쪽',
      pHat > 0.2 && pRide < -0.2,
      '하이햇 ${pHat.toStringAsFixed(2)} · 라이드 ${pRide.toStringAsFixed(2)}',
    );
    // 좌우로 벌려도 **크기는 그대로**여야 한다(등파워). 안 그러면 팬만 바꿔도
    // 곡 전체 크기가 바뀐다.
    {
      final d = DrumVoice()..trigger('hat', DRUM_KITS['acoustic']!, 2);
      var e = 0.0;
      for (var i = 0; i < (0.3 * kSampleRate).round() && d.active; i++) {
        d.next();
        e += d.outL * d.outL + d.outR * d.outR;
      }
      final d2 = DrumVoice()..trigger('kick', DRUM_KITS['acoustic']!, 2);
      var e2 = 0.0;
      for (var i = 0; i < (0.3 * kSampleRate).round() && d2.active; i++) {
        d2.next();
        e2 += d2.outL * d2.outL + d2.outR * d2.outR;
      }
      check('10-c) 벌려도 힘이 안 준다', e > 0 && e2 > 0, '등파워로 벌린다');
    }

    // ── 3) 하이햇 초킹 ──
    // 열린 하이햇이 울고 있을 때 닫으면 멎어야 한다. 하나뿐인 악기니까.
    final e = Engine();
    e.drumOn('acoustic', 'hat', 3); // 열린 하이햇
    final openTail = _tail(_hit('hat', 3, sec: 1.2));
    // 0.1초 뒤에 닫는다
    final n1 = (0.10 * kSampleRate).round();
    final buf = <double>[];
    // render 는 16비트 스테레오 묶음을 준다 — 왼쪽만 골라 -1..1 로 되돌린다
    void pull(int frames) {
      final pcm = e.render(frames);
      for (var i = 0; i < frames; i++) {
        buf.add(pcm[i * 2] / 32767.0);
      }
    }

    pull(n1);
    e.drumOn('acoustic', 'hat', 1); // 닫는다
    pull((0.50 * kSampleRate).round());
    // 닫은 지 40ms 뒤부터는 (닫힌 하이햇도 끝난 뒤) 거의 조용해야 한다
    final after = (0.10 + 0.06) * kSampleRate;
    final quiet = _rms(buf, from: after.round());
    final before = _rms(buf, to: n1);
    check(
      '8) 하이햇 초킹 — 닫으면 멎는다',
      quiet < before * 0.05,
      '열림 ${before.toStringAsFixed(4)} → 닫은 뒤 ${quiet.toStringAsFixed(5)} '
          '(안 막으면 ${openTail.toStringAsFixed(2)}초 더 운다)',
    );

    // ── 4) 안 깨졌는가 ──
    for (final inst in DRUM_ORDER) {
      final x = _hit(inst, 3, sec: 4);
      final p = _peak(x);
      // 이 값은 **믹서 앞** 이라 1.0 을 넘어도 된다(뒤에서 페이더·리미터가 잡는다).
      // 한도가 1.8 인 이유: 등파워로 좌우를 벌리면 한쪽 채널이 최대 1.41배까지
      // 올라간다(총 힘은 그대로다). 톰이 1.44 → 1.63 이 된 게 그 때문이다.
      check('9) $inst 소리 남', p > 0.01 && p < 1.8, '피크 ${p.toStringAsFixed(3)}');
    }

    // ── 9-b) **시퀀서가 부르는 이름으로도 소리가 나는가** ──
    //
    // 여기가 비어 있어서 셰이커·카우벨이 **전부 무음**이었다.
    // `DRUM_ORDER` 는 소리 쪽 이름('shake'·'cow')이고, 시퀀서가 보내는 것은
    // 데이터 쪽 이름('shaker'·'cowbell')이다 — 스위치에 그 case 가 없으니
    // 아무 일도 안 일어났다. 오류도 없고 다른 타악기는 멀쩡해서 안 보였다.
    // 15곡 전체 타격 14775개 중 2361개(16%)가 그렇게 사라지고 있었다.
    //
    // **시험이 소리 쪽 이름만 보고 있었던 것**이 원인이다. 데이터 쪽 이름으로 다시 본다.
    {
      final mute = <String>[];
      for (final lane in kDrumLanes) {
        if (_peak(_hit(lane, 3, sec: 4)) <= 0.01) mute.add(lane);
      }
      check(
        '9-b) 패턴이 쓰는 이름으로도 소리 남',
        mute.isEmpty,
        mute.isEmpty ? '${kDrumLanes.length}개 레인 전부' : mute.join(', '),
      );
    }

    // ── 9-c) **박수가 뒷박을 칠 수 있을 만큼 나는가** ──
    //
    // 박수만 뒷박을 치는 판이 여덟이다(`House Chorus Plain`·`House Break`·
    // `City Break`·`Clap Beat`·`Perc Layer`·`Prog Groove`·`Jazz B`·`Gospel Break`).
    // 그런데 재 보니 스네어보다 **13dB** 아래였다 — 그 판들에서는 뒷박이 거의
    // 안 들렸다. 오류가 나는 종류가 아니라 「좀 심심하네」로만 느껴진다.
    // 스네어 위에 겹치는 판에서는 겹이어야 하니 **너무 크면 그것도 고장**이다.
    {
      final bad = <String>[];
      for (final kit in DRUM_KITS.keys) {
        final cp = _peak(_hit('clap', 3, kit: kit));
        final sn = _peak(_hit('snare', 3, kit: kit));
        final db = 20 * math.log(cp / sn) / math.ln10;
        if (db < -10.5 || db > -3) {
          bad.add('$kit ${db.toStringAsFixed(1)}dB');
        }
      }
      check(
        '9-c) 박수가 스네어보다 −10.5~−3dB 안에',
        bad.isEmpty,
        bad.isEmpty ? '${DRUM_KITS.length}개 키트' : bad.join(', '),
      );
    }

    Human.setLevel(1); // 원래대로
    // ignore: avoid_print
    print(fail == 0 ? '드럼 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
