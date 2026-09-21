// 새 플러그인 6종 + 마스터링 2종 확인(사용자 요청, 2026-09-16: "플러그인들도
// 좀 더 추가해", "마스터링 플러그인도 추가해").
//   flutter test test/fx_new_check_test.dart
//
// 전부 안 죽는지(NaN·무한대·폭주 없음)부터 보고, 플러그인마다 "이게 이
// 플러그인이 하는 일이 맞나"를 하나씩 잰다.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/fx.dart';

List<double> _run(Fx fx, {double freq = 220, int n = 4800, double amp = 0.5}) {
  final out = <double>[];
  for (var i = 0; i < n; i++) {
    final x = amp * math.sin(2 * math.pi * freq * i / kSampleRate);
    fx.step(x, x);
    out.add(fx.outL);
  }
  return out;
}

double _rms(List<double> y) {
  var s = 0.0;
  for (final v in y) {
    s += v * v;
  }
  return math.sqrt(s / y.length);
}

double _peak(List<double> y) {
  var m = 0.0;
  for (final v in y) {
    if (v.abs() > m) m = v.abs();
  }
  return m;
}

bool _allFinite(List<double> y) => y.every((v) => v.isFinite && v.abs() < 10);

void main() {
  test('새 플러그인 확인', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    const newTypes = [
      'tremolo',
      'flanger',
      'phaser',
      'bitcrusher',
      'tape',
      'peq',
      'exciter',
      'maximizer',
    ];

    // 0) 전부 등록돼 있고, 기본값으로 돌려도 안 죽는다(NaN·폭주 없음).
    for (final t in newTypes) {
      final fx = makeFx(t);
      check('0) $t 등록됨', fx != null, '');
      if (fx == null) continue;
      final y = _run(fx, n: 4800);
      check('0-b) $t 기본값 — 안 죽음', _allFinite(y), '피크 ${_peak(y).toStringAsFixed(3)}');
    }

    // 1) 트레몰로 — 깊이 1이면 골에서 소리가 확 죽는다(RMS 가 원음보다 뚜렷이 낮다)
    {
      final dry = _run(makeFx('tremolo')!..set('depth', 0), n: 4800, freq: 220);
      final wet = _run(
        makeFx('tremolo')!
          ..set('rate', 2)
          ..set('depth', 1),
        n: 4800,
        freq: 220,
      );
      check(
        '1) 트레몰로 — 깊이 1이 깊이 0보다 조용하다',
        _rms(wet) < _rms(dry) * 0.85,
        '깊이0 ${_rms(dry).toStringAsFixed(3)} · 깊이1 ${_rms(wet).toStringAsFixed(3)}',
      );
    }

    // 2) 플랜저 — 피드백을 세게(0.9) 걸어도 폭주하지 않는다(콤필터라 피드백이
    //    잘못 짜면 발산하기 쉽다 — 여기가 제일 위험한 자리).
    {
      final y = _run(
        makeFx('flanger')!
          ..set('fb', 0.9)
          ..set('mix', 1.0)
          ..set('depth', 6),
        n: 9600,
      );
      check('2) 플랜저 — 피드백 0.9 에도 안정', _allFinite(y), '피크 ${_peak(y).toStringAsFixed(3)}');
    }

    // 3) 페이저 — 섞기 0 이면 원음 그대로(올패스는 위상만 돌리지만, 섞기 0
    //    이면 wet 자체를 안 섞으니 dry 와 같아야 한다).
    {
      final dry = _run(makeFx('peq')!, n: 2400); // 순수 사인파 원본 대조군
      final y = _run(makeFx('phaser')!..set('mix', 0), n: 2400);
      var maxDiff = 0.0;
      for (var i = 0; i < y.length; i++) {
        final d = (y[i] - dry[i]).abs();
        if (d > maxDiff) maxDiff = d;
      }
      check('3) 페이저 — 섞기 0 이면 원음과 같음', maxDiff < 1e-9, '최대 차 $maxDiff');
    }

    // 4) 비트크러셔 — 비트를 1로 낮추면 값이 몇 안 되는 계단이 된다.
    {
      final y = _run(
        makeFx('bitcrusher')!
          ..set('bits', 1)
          ..set('rate', 1)
          ..set('mix', 1.0),
        n: 4800,
      );
      final levels = y.map((v) => v.toStringAsFixed(3)).toSet();
      check('4) 비트크러셔 — 비트 1 이면 값이 몇 안 됨', levels.length <= 4, '서로 다른 값 ${levels.length}개');
    }

    // 5) 테이프 새추레이션 — 드라이브를 올리면 피크가 원음보다 눌린다
    //    (`_sat` 이 압축 방향으로 휘는 곡선이라 진폭이 줄어야 정상).
    {
      final dry = _run(makeFx('tape')!..set('drive', 0), n: 4800, amp: 0.9);
      final wet = _run(makeFx('tape')!..set('drive', 1.0), n: 4800, amp: 0.9);
      check(
        '5) 테이프 새추레이션 — 드라이브 올리면 피크가 눌림',
        _peak(wet) < _peak(dry),
        '드라이브0 ${_peak(dry).toStringAsFixed(3)} · 드라이브1 ${_peak(wet).toStringAsFixed(3)}',
      );
    }

    // 6) 파라메트릭 EQ — f1=150 을 +12dB 올리면 150Hz 사인파의 에너지가
    //    올린 만큼 커진다(피킹 필터가 실제로 그 자리를 잡았는가).
    {
      final flat = _run(makeFx('peq')!, freq: 150, n: 4800);
      final boosted = _run(
        makeFx('peq')!
          ..set('f1', 150)
          ..set('g1', 12),
        freq: 150,
        n: 4800,
      );
      check(
        '6) 파라메트릭 EQ — 그 자리를 올리면 커짐',
        _rms(boosted) > _rms(flat) * 1.5,
        '그대로 ${_rms(flat).toStringAsFixed(3)} · +12dB ${_rms(boosted).toStringAsFixed(3)}',
      );
    }

    // 7) 익사이터 — 섞기 0 이면 원음 그대로(고역을 더해 얹기만 하는 자리라
    //    섞기 0 이면 얹을 게 없어야 한다).
    {
      final dry = _run(makeFx('peq')!, freq: 3000, n: 2400);
      final y = _run(makeFx('exciter')!..set('mix', 0), freq: 3000, n: 2400);
      var maxDiff = 0.0;
      for (var i = 0; i < y.length; i++) {
        final d = (y[i] - dry[i]).abs();
        if (d > maxDiff) maxDiff = d;
      }
      check('7) 익사이터 — 섞기 0 이면 원음과 같음', maxDiff < 1e-9, '최대 차 $maxDiff');
    }

    // 8) 러프니스 맥시마이저 — 천장을 넘겨 밀어 넣어도 출력 피크가 천장
    //    언저리에서 잡힌다(리미터와 같은 핵심 약속).
    {
      final ceilDb = -1.0;
      final ceil = math.pow(10, ceilDb / 20).toDouble();
      final fx = makeFx('maximizer')!
        ..set('drive', 1.0)
        ..set('ceil', ceilDb)
        ..set('character', 0.5);
      final y = _run(fx, n: 9600, amp: 0.9);
      // 엔벨로프가 자리 잡을 시간을 준 뒤(뒤쪽 절반만) 잰다
      final settled = y.sublist(y.length ~/ 2);
      check(
        '8) 맥시마이저 — 피크가 천장 언저리에서 잡힘',
        _peak(settled) < ceil * 1.3,
        '천장 ${ceil.toStringAsFixed(3)} · 실제 피크 ${_peak(settled).toStringAsFixed(3)}',
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '새 플러그인 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
