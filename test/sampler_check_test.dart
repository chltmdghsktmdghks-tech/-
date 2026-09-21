// 악기 품질 1단계 — 표본(피아노·바이올린)이 실제로 도는가.
//   flutter test test/sampler_check_test.dart
//
// `sampler.dart` 는 **명시적으로 부르지 않으면 아무 일도 안 한다**
// (`ensureSamplesLoaded()`) — 그래서 다른 시험은 전부 지금까지처럼 합성으로
// 돈다. 여기서만 그 표본 경로를 켜서 잰다:
//  · 자산이 실제로 읽힌다(표본이 없으면 조용히 무음이 되는데, 그게 제일 안 보인다)
//  · 피치 시프트가 맞다 — root 가 아닌 음을 쳐도 그 주파수가 나온다
//  · 세기(pp/mf/ff)가 실제로 다른 표본을 고른다(피아노) · 음량이라도 세기를
//    따라가는가(바이올린 — 원본에 세기가 한 벌뿐이라 음색까지는 아직 안 갈린다)
//  · 손을 일찍 떼면(짧은 dur) 표본이 안 끊기고 짧게 눌려 끈다(release)
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/sampler.dart';
import 'package:music_doodle_engine/synth.dart';

List<double> _render(String voice, double freq, double dur, int vel) {
  final n = SynthNote();
  n.noteOn(voice, freq, dur, vel);
  final total = (2.0 * kSampleRate).round();
  final out = List<double>.filled(total, 0);
  for (var i = 0; i < total; i++) {
    if (!n.active) break;
    n.next();
    out[i] = n.outL;
  }
  return out;
}

double _rms(List<double> x) {
  if (x.isEmpty) return 0;
  var s = 0.0;
  for (final v in x) {
    s += v * v;
  }
  return math.sqrt(s / x.length);
}

/// 자기상관으로 [expectHz] **근처**의 기본 주파수를 잰다 — 표본이 정말
/// 그 높이로 울리는지만 본다(맹목적 피치 검출이 아니다). 피아노처럼 배음이
/// 강한 소리는 자기상관이 종종 반박자(옥타브 오차)를 고른다 — 넓게 훑으면
/// 그 함정에 빠진다. **찾는 lag 를 요청한 음 근처(±30%)로 좁혀서** 옥타브
/// 오차 자체가 안 나게 한다. 겹치는 길이로 나눠 평균하는 이유는 안 나누면
/// lag 가 커질수록 더해지는 항이 줄어 늘 제일 작은 lag 가 이겨서다.
double _fundamentalHz(
  List<double> x,
  double expectHz, {
  int from = 4000,
  int n = 4000,
}) {
  final seg = x.sublist(from, math.min(x.length, from + n));
  final centerLag = kSampleRate / expectHz;
  final loLag = (centerLag * 0.7).round().clamp(2, seg.length - 1);
  final hiLag = (centerLag * 1.3).round().clamp(loLag + 1, seg.length - 1);
  var bestLag = loLag, bestCorr = -1e18;
  for (var lag = loLag; lag <= hiLag; lag++) {
    var c = 0.0;
    final count = seg.length - lag;
    for (var i = 0; i < count; i++) {
      c += seg[i] * seg[i + lag];
    }
    c /= count;
    if (c > bestCorr) {
      bestCorr = c;
      bestLag = lag;
    }
  }
  return kSampleRate / bestLag;
}

void main() {
  // `rootBundle.load` 는 위젯을 안 띄우고 `test()` 만 써도 되지만, 바인딩은
  // 있어야 한다 — 다른 시험은 자산을 안 읽어서 지금까지 이게 필요 없었다.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await ensureSamplesLoaded();
  });

  tearDownAll(() {
    // 이 시험 뒤에 도는 다른 시험 파일에 표본 상태가 새면 안 된다 —
    // `kSampleBanks` 는 전역이다(`flutter test` 는 파일마다 새 프로세스라
    // 다른 파일엔 원래 안 새지만, 혹시 몰라 확실히 지운다).
    kSampleBanks.clear();
  });

  test('악기 품질 1단계 — 표본 피아노', () {
    var fail = 0;
    void check(String name, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $name — $detail');
      if (!ok) fail++;
    }

    check(
      '0) 자산을 실제로 읽었다',
      kSampleBanks.containsKey('piano'),
      kSampleBanks.containsKey('piano')
          ? '피아노 ${kSampleBanks['piano']!.byVel[2]!.length}개(세기2)'
          : '표본이 비어 있음(자산 경로·형식 확인)',
    );
    if (!kSampleBanks.containsKey('piano')) {
      // ignore: avoid_print
      print('실패 $fail건(자산을 못 읽어 나머지는 의미가 없다)');
      expect(fail, 0);
      return;
    }

    // 1) 소리가 난다(무음이 아니다)
    final c4 = _render('piano', 261.63, 1.0, 2);
    check('1) 소리가 난다', _rms(c4) > 0.001, 'RMS ${_rms(c4).toStringAsFixed(4)}');

    // 2) root 가 아닌 음(D4, root C4/C5 사이)도 그 높이로 난다 — 피치 시프트 확인
    final d4 = _render('piano', 293.66, 1.0, 2);
    final hz = _fundamentalHz(d4, 293.66);
    check(
      '2) 피치 시프트가 맞다(D4)',
      (hz - 293.66).abs() < 293.66 * 0.03, // 3% 이내(반음의 절반도 안 됨)
      '요청 293.66Hz · 잰 값 ${hz.toStringAsFixed(1)}Hz',
    );

    // 3) 세기가 다른 표본을 고른다 — pp 와 ff 는 애초에 다른 녹음이라 파형 자체가 다르다
    final pp = _render('piano', 261.63, 0.3, 1);
    final ff = _render('piano', 261.63, 0.3, 3);
    check(
      '3) 세기 1·3이 다른 표본이다',
      _rms(ff) > _rms(pp) * 1.05,
      'pp RMS ${_rms(pp).toStringAsFixed(4)} · ff RMS ${_rms(ff).toStringAsFixed(4)}',
    );

    // 4) 짧게 눌렀다 떼도(dur 0.05s) 안 끊기고 짧게 눌려 끈다 — release 뒤로는 무음.
    final short = _render('piano', 261.63, 0.05, 2);
    final tailStart = ((0.05 + 0.08 + 0.02) * kSampleRate).round();
    final tail = short.sublist(math.min(tailStart, short.length));
    check(
      '4) 짧은 음이 release 뒤로 조용해진다',
      tail.isEmpty || _rms(tail) < 0.001,
      tail.isEmpty ? '표본 끝까지 감(release 전에 끝)' : 'release 뒤 RMS ${_rms(tail).toStringAsFixed(5)}',
    );

    // ignore: avoid_print
    print(fail == 0 ? '표본 피아노 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });

  test('악기 품질 1단계 — 표본 바이올린', () {
    var fail = 0;
    void check(String name, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $name — $detail');
      if (!ok) fail++;
    }

    check(
      '0) 자산을 실제로 읽었다',
      kSampleBanks.containsKey('violin'),
      kSampleBanks.containsKey('violin')
          ? '바이올린 ${kSampleBanks['violin']!.byVel[2]!.length}개(세기2)'
          : '표본이 비어 있음(자산 경로·형식 확인)',
    );
    if (!kSampleBanks.containsKey('violin')) {
      // ignore: avoid_print
      print('실패 $fail건(자산을 못 읽어 나머지는 의미가 없다)');
      expect(fail, 0);
      return;
    }

    // 1) 소리가 난다
    final a4 = _render('violin', 440.0, 1.0, 2);
    check('1) 소리가 난다', _rms(a4) > 0.001, 'RMS ${_rms(a4).toStringAsFixed(4)}');

    // 2) root 가 아닌 음(C4, root B3/D4 사이)도 그 높이로 난다
    final c4 = _render('violin', 261.63, 1.0, 2);
    final hz = _fundamentalHz(c4, 261.63);
    check(
      '2) 피치 시프트가 맞다(C4)',
      (hz - 261.63).abs() < 261.63 * 0.03,
      '요청 261.63Hz · 잰 값 ${hz.toStringAsFixed(1)}Hz',
    );

    // 3) **원본에 세기 한 벌뿐이라** pp·ff 는 일부러 같은 표본이다(SOURCE.md) —
    // 음량만 `VG` 표로 갈린다. 「다른 표본」을 요구하면 이 악기의 실제 상태와
    // 안 맞으니, 여기서는 **음량만 세기를 따라간다**를 확인한다.
    final pp = _render('violin', 440.0, 0.3, 1);
    final ff = _render('violin', 440.0, 0.3, 3);
    check(
      '3) 세기가 음량에 반영된다(음색은 원본 제약상 아직 동일)',
      _rms(ff) > _rms(pp) * 1.2,
      'pp RMS ${_rms(pp).toStringAsFixed(4)} · ff RMS ${_rms(ff).toStringAsFixed(4)}',
    );

    // ignore: avoid_print
    print(fail == 0 ? '표본 바이올린 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });

  // 트럼펫은 바이올린과 같은 제약(세기 한 벌)이라 그 시험을 그대로 되풀이
  // 안 한다 — **자산 경로·root 주파수 표가 맞는지**(제일 잘 틀리는 자리)만 본다.
  test('악기 품질 1단계 — 표본 트럼펫', () {
    var fail = 0;
    void check(String name, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $name — $detail');
      if (!ok) fail++;
    }

    check(
      '0) 자산을 실제로 읽었다',
      kSampleBanks.containsKey('trumpet'),
      kSampleBanks.containsKey('trumpet')
          ? '트럼펫 ${kSampleBanks['trumpet']!.byVel[2]!.length}개(세기2)'
          : '표본이 비어 있음(자산 경로·형식 확인)',
    );
    if (!kSampleBanks.containsKey('trumpet')) {
      // ignore: avoid_print
      print('실패 $fail건(자산을 못 읽어 나머지는 의미가 없다)');
      expect(fail, 0);
      return;
    }

    // root 가 아닌 음(Eb4, root D4/F4 사이)도 그 높이로 난다
    final eb4 = _render('trumpet', 311.13, 1.0, 2);
    final hz = _fundamentalHz(eb4, 311.13);
    check(
      '1) 피치 시프트가 맞다(Eb4)',
      (hz - 311.13).abs() < 311.13 * 0.03,
      '요청 311.13Hz · 잰 값 ${hz.toStringAsFixed(1)}Hz',
    );

    // ignore: avoid_print
    print(fail == 0 ? '표본 트럼펫 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });

  // 첼로도 트럼펫과 같은 이유로(세기 한 벌) 그 시험을 안 되풀이한다 — 여기서는
  // **낮은 음역**이 처음이라 자기상관 lag 검색 창이 너무 좁게 잡혀 있지 않은지도
  // 같이 본다(±30% 창이 저음에서도 통하는지).
  test('악기 품질 1단계 — 표본 첼로', () {
    var fail = 0;
    void check(String name, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $name — $detail');
      if (!ok) fail++;
    }

    check(
      '0) 자산을 실제로 읽었다',
      kSampleBanks.containsKey('cello'),
      kSampleBanks.containsKey('cello')
          ? '첼로 ${kSampleBanks['cello']!.byVel[2]!.length}개(세기2)'
          : '표본이 비어 있음(자산 경로·형식 확인)',
    );
    if (!kSampleBanks.containsKey('cello')) {
      // ignore: avoid_print
      print('실패 $fail건(자산을 못 읽어 나머지는 의미가 없다)');
      expect(fail, 0);
      return;
    }

    // root 가 아닌 낮은 음(D2, root C2/Eb2 사이)도 그 높이로 난다
    final d2 = _render('cello', 73.42, 1.0, 2);
    final hz = _fundamentalHz(d2, 73.42);
    check(
      '1) 피치 시프트가 맞다(D2, 저음)',
      (hz - 73.42).abs() < 73.42 * 0.03,
      '요청 73.42Hz · 잰 값 ${hz.toStringAsFixed(1)}Hz',
    );

    // ignore: avoid_print
    print(fail == 0 ? '표본 첼로 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });

  // 기본팩 표본(밴드 악기) — 기타는 세기 두 벌(soft/normal)이 있어서 그
  // 다이내믹 차이도 같이 본다(바이올린류와 다르게 진짜로 다른 표본이다).
  test('악기 품질 1단계 — 표본 기타(기본팩)', () {
    var fail = 0;
    void check(String name, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $name — $detail');
      if (!ok) fail++;
    }

    check(
      '0) 자산을 실제로 읽었다',
      kSampleBanks.containsKey('guitar'),
      kSampleBanks.containsKey('guitar')
          ? '기타 ${kSampleBanks['guitar']!.byVel[2]!.length}개(세기2)'
          : '표본이 비어 있음(자산 경로·형식 확인)',
    );
    if (!kSampleBanks.containsKey('guitar')) {
      // ignore: avoid_print
      print('실패 $fail건(자산을 못 읽어 나머지는 의미가 없다)');
      expect(fail, 0);
      return;
    }

    // root 가 아닌 음(A3, root G3/B3 사이)도 그 높이로 난다
    final a3 = _render('guitar', 220.00, 1.0, 2);
    final hz = _fundamentalHz(a3, 220.00);
    check(
      '1) 피치 시프트가 맞다(A3)',
      (hz - 220.00).abs() < 220.00 * 0.03,
      '요청 220.00Hz · 잰 값 ${hz.toStringAsFixed(1)}Hz',
    );

    // soft(세기 1) 와 normal(세기 3) 이 **진짜 다른 표본**이다(원본에 둘 다
    // 있는 낮은 구간에서 확인 — G3 는 soft 벌이 있다).
    final pp = _render('guitar', 196.00, 0.3, 1);
    final ff = _render('guitar', 196.00, 0.3, 3);
    check(
      '2) 세기 1·3이 다른 표본이다',
      _rms(ff) > _rms(pp) * 1.05,
      'pp RMS ${_rms(pp).toStringAsFixed(4)} · ff RMS ${_rms(ff).toStringAsFixed(4)}',
    );

    // ignore: avoid_print
    print(fail == 0 ? '표본 기타 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });

  // 핑거 베이스는 첼로·트럼펫과 같은 이유(세기 한 벌)로 최소만 본다 —
  // **저음 악기 두 번째**라 자기상관 창이 이 음역에서도 통하는지를 겸해 본다.
  test('악기 품질 1단계 — 표본 핑거 베이스(기본팩)', () {
    var fail = 0;
    void check(String name, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $name — $detail');
      if (!ok) fail++;
    }

    check(
      '0) 자산을 실제로 읽었다',
      kSampleBanks.containsKey('fingerbass'),
      kSampleBanks.containsKey('fingerbass')
          ? '핑거베이스 ${kSampleBanks['fingerbass']!.byVel[2]!.length}개(세기2)'
          : '표본이 비어 있음(자산 경로·형식 확인)',
    );
    if (!kSampleBanks.containsKey('fingerbass')) {
      // ignore: avoid_print
      print('실패 $fail건(자산을 못 읽어 나머지는 의미가 없다)');
      expect(fail, 0);
      return;
    }

    // root 가 아닌 낮은 음(G1, root F#1/G#1 사이)도 그 높이로 난다
    final g1 = _render('fingerbass', 49.00, 1.0, 2);
    final hz = _fundamentalHz(g1, 49.00);
    check(
      '1) 피치 시프트가 맞다(G1, 저음)',
      (hz - 49.00).abs() < 49.00 * 0.03,
      '요청 49.00Hz · 잰 값 ${hz.toStringAsFixed(1)}Hz',
    );

    // ignore: avoid_print
    print(fail == 0 ? '표본 핑거 베이스 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });

  // 업라이트·색소폰도 트럼펫·첼로와 같은 이유(세기 한 벌)로 최소만 본다.
  test('악기 품질 1단계 — 표본 업라이트 베이스(추가팩)', () {
    var fail = 0;
    void check(String name, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $name — $detail');
      if (!ok) fail++;
    }

    check(
      '0) 자산을 실제로 읽었다',
      kSampleBanks.containsKey('upright'),
      kSampleBanks.containsKey('upright')
          ? '업라이트 ${kSampleBanks['upright']!.byVel[2]!.length}개(세기2)'
          : '표본이 비어 있음(자산 경로·형식 확인)',
    );
    if (!kSampleBanks.containsKey('upright')) {
      // ignore: avoid_print
      print('실패 $fail건(자산을 못 읽어 나머지는 의미가 없다)');
      expect(fail, 0);
      return;
    }

    // root 가 아닌 음(D1, root C1/Eb1 사이)도 그 높이로 난다
    final d1 = _render('upright', 36.71, 1.0, 2);
    final hz = _fundamentalHz(d1, 36.71);
    check(
      '1) 피치 시프트가 맞다(D1, 저음)',
      (hz - 36.71).abs() < 36.71 * 0.03,
      '요청 36.71Hz · 잰 값 ${hz.toStringAsFixed(1)}Hz',
    );

    // ignore: avoid_print
    print(fail == 0 ? '표본 업라이트 베이스 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });

  test('악기 품질 1단계 — 표본 색소폰(추가팩)', () {
    var fail = 0;
    void check(String name, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $name — $detail');
      if (!ok) fail++;
    }

    check(
      '0) 자산을 실제로 읽었다',
      kSampleBanks.containsKey('sax'),
      kSampleBanks.containsKey('sax')
          ? '색소폰 ${kSampleBanks['sax']!.byVel[2]!.length}개(세기2)'
          : '표본이 비어 있음(자산 경로·형식 확인)',
    );
    if (!kSampleBanks.containsKey('sax')) {
      // ignore: avoid_print
      print('실패 $fail건(자산을 못 읽어 나머지는 의미가 없다)');
      expect(fail, 0);
      return;
    }

    // root 가 아닌 음(F3, root E3/G3 사이)도 그 높이로 난다
    final f3 = _render('sax', 174.61, 1.0, 2);
    final hz = _fundamentalHz(f3, 174.61);
    check(
      '1) 피치 시프트가 맞다(F3)',
      (hz - 174.61).abs() < 174.61 * 0.03,
      '요청 174.61Hz · 잰 값 ${hz.toStringAsFixed(1)}Hz',
    );

    // ignore: avoid_print
    print(fail == 0 ? '표본 색소폰 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });

  // 일렉 피아노 — 세기가 진짜 세 벌(v60/v80/v100)이다, 기타처럼.
  test('악기 품질 1단계 — 표본 일렉 피아노(추가팩)', () {
    var fail = 0;
    void check(String name, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $name — $detail');
      if (!ok) fail++;
    }

    check(
      '0) 자산을 실제로 읽었다',
      kSampleBanks.containsKey('epiano'),
      kSampleBanks.containsKey('epiano')
          ? '일렉피아노 ${kSampleBanks['epiano']!.byVel[2]!.length}개(세기2)'
          : '표본이 비어 있음(자산 경로·형식 확인)',
    );
    if (!kSampleBanks.containsKey('epiano')) {
      // ignore: avoid_print
      print('실패 $fail건(자산을 못 읽어 나머지는 의미가 없다)');
      expect(fail, 0);
      return;
    }

    // root 가 아닌 음(A3, root F#3/C4 사이)도 그 높이로 난다
    final a3 = _render('epiano', 220.00, 1.0, 2);
    final hz = _fundamentalHz(a3, 220.00);
    check(
      '1) 피치 시프트가 맞다(A3)',
      (hz - 220.00).abs() < 220.00 * 0.03,
      '요청 220.00Hz · 잰 값 ${hz.toStringAsFixed(1)}Hz',
    );

    // 세기 1·3이 진짜 다른 표본(v60 vs v100)이다.
    final pp = _render('epiano', 261.63, 0.3, 1);
    final ff = _render('epiano', 261.63, 0.3, 3);
    check(
      '2) 세기 1·3이 다른 표본이다',
      _rms(ff) > _rms(pp) * 1.05,
      'pp RMS ${_rms(pp).toStringAsFixed(4)} · ff RMS ${_rms(ff).toStringAsFixed(4)}',
    );

    // ignore: avoid_print
    print(fail == 0 ? '표본 일렉 피아노 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
