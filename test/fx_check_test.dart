// 5단계 45/N — 인서트 플러그인 확인.
//   flutter test test/fx_check_test.dart
//
// 이펙트는 **틀려도 그럴듯하게 들린다.** "뭔가 달라지긴 했네" 로 넘어가면
// 게인만 바뀌고 왜곡은 안 걸린 걸 못 잡는다. 그래서 숫자로 본다:
//  · 앰프  — 배음이 실제로 늘어나는가(THD), 성향마다 다른가
//  · 딜레이 — **정확히 그 시각에** 되돌아오는가
//  · 컴프  — 큰 소리만 눌리고 작은 소리는 그대로인가
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/engine.dart';
import 'package:music_doodle_engine/fx.dart';
import 'package:music_doodle_engine/mixer.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';

/// 사인파를 통과시키고 [출력 목록] 을 돌려준다.
List<double> _run(Fx fx, {double freq = 220, int n = 4800, double amp = 0.5}) {
  final out = <double>[];
  for (var i = 0; i < n; i++) {
    final x = amp * math.sin(2 * math.pi * freq * i / kSampleRate);
    fx.step(x, x);
    out.add(fx.outL);
  }
  return out;
}

/// 기본파를 뺀 나머지 에너지의 비율 — 클수록 많이 뭉갠 것이다.
double _thd(List<double> y, double freq) {
  // 기본파 성분을 상관으로 뽑아낸다
  var re = 0.0, im = 0.0, tot = 0.0;
  for (var i = 0; i < y.length; i++) {
    final w = 2 * math.pi * freq * i / kSampleRate;
    re += y[i] * math.cos(w);
    im += y[i] * math.sin(w);
    tot += y[i] * y[i];
  }
  final f = 2 * (re * re + im * im) / (y.length * y.length);
  final total = tot / y.length;
  if (total <= 1e-12) return 0;
  return math.max(0, (total - f)) / total;
}

double _rms(List<double> y) {
  var s = 0.0;
  for (final v in y) {
    s += v * v;
  }
  return math.sqrt(s / y.length);
}

void main() {
  _presetTests();
  _chorusTests();
  test('인서트 플러그인', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    // 0) 목록이 자기 손잡이를 설명한다 — 화면이 이걸 읽어 만든다
    final noParams = [
      for (final e in kFxCatalog.entries)
        if (e.value.params.isEmpty) e.key,
    ];
    check(
      '0) 플러그인마다 손잡이 설명',
      noParams.isEmpty,
      '${kFxCatalog.length}종 · 설명 없는 것 ${noParams.isEmpty ? '없음' : noParams.join(',')}',
    );

    // ── 앰프 ──
    double ampThd(int mode, double gain) {
      final a = makeFx('amp')!
        ..set('mode', mode.toDouble())
        ..set('gain', gain)
        ..set('tone', 0.5);
      // 필터가 안정될 때까지 조금 돌린 뒤 잰다
      _run(a, n: 2400);
      return _thd(_run(a, n: 4800), 220);
    }

    final clean = ampThd(0, 0.3);
    final crunch = ampThd(1, 0.5);
    final hi = ampThd(2, 0.8);
    check(
      '1) 앰프가 실제로 뭉갠다',
      clean > 0.001,
      '클린 배음 비율 ${(clean * 100).toStringAsFixed(1)}%',
    );
    check(
      '2) 성향마다 다르다',
      crunch > clean && hi > crunch,
      '클린 ${(clean * 100).toStringAsFixed(1)}% < '
          '크런치 ${(crunch * 100).toStringAsFixed(1)}% < '
          '하이게인 ${(hi * 100).toStringAsFixed(1)}%',
    );

    // 3) 게인을 올려도 **볼륨만 커지지 않는다** — 톤 비교가 볼륨 비교가 되면 안 된다
    double ampRms(double gain) {
      final a = makeFx('amp')!
        ..set('mode', 2)
        ..set('gain', gain);
      _run(a, n: 2400);
      return _rms(_run(a, n: 4800));
    }

    final lo = ampRms(0.1), hiR = ampRms(0.9);
    final ratio = hiR / (lo <= 1e-9 ? 1e-9 : lo);
    check(
      '3) 게인이 볼륨 아니다',
      ratio < 3.0,
      '게인 0.1 → 0.9 일 때 크기 ${ratio.toStringAsFixed(2)}배',
    );

    // ── 딜레이 ──
    // 4) **정확히 그 시각에** 되돌아온다
    final d = makeFx('delay')!
      ..set('time', 100) // 100ms = 4800샘플
      ..set('fb', 0)
      ..set('mix', 1)
      ..set('damp', 0)
      ..set('ping', 0);
    final tap = <int>[];
    for (var i = 0; i < 12000; i++) {
      d.step(i == 0 ? 1.0 : 0.0, i == 0 ? 1.0 : 0.0);
      if (d.outL.abs() > 0.2) tap.add(i);
    }
    const want = 4800;
    check(
      '4) 딜레이 시각',
      tap.isNotEmpty && (tap.first - want).abs() <= 2,
      '되돌아온 자리 ${tap.isEmpty ? '없음' : tap.first} (원하는 값 $want)',
    );

    // 5) 반복을 올리면 **여러 번** 되돌아온다
    final d2 = makeFx('delay')!
      ..set('time', 50)
      ..set('fb', 0.7)
      ..set('mix', 1)
      ..set('damp', 0);
    var echoes = 0;
    var last = -999;
    for (var i = 0; i < 24000; i++) {
      d2.step(i == 0 ? 1.0 : 0.0, i == 0 ? 1.0 : 0.0);
      if (d2.outL.abs() > 0.05 && i - last > 100) {
        echoes++;
        last = i;
      }
    }
    check('5) 반복', echoes >= 3, '$echoes번 되돌아옴');

    // 6) 섞기 0 이면 원음 그대로 — 꽂아 두고 0 으로 두면 없는 것과 같아야 한다
    final d3 = makeFx('delay')!..set('mix', 0);
    var same = true;
    for (var i = 0; i < 2000; i++) {
      final x = math.sin(i * 0.05);
      d3.step(x, x);
      if ((d3.outL - x).abs() > 1e-9) same = false;
    }
    check('6) 섞기 0 = 그대로', same, '원음과 한 비트도 안 다름');

    // ── 컴프 ──
    // 7) 큰 소리는 눌리고 작은 소리는 그대로
    double compGain(double amp) {
      final c = makeFx('comp')!
        ..set('mode', 2)
        ..set('thr', -20)
        ..set('ratio', 8)
        ..set('atk', 0)
        ..set('makeup', 0);
      final y = _run(c, amp: amp, n: 24000);
      // 뒤쪽(안정된 뒤)만 본다
      final tail = y.sublist(y.length ~/ 2);
      return _rms(tail) / (amp * math.sqrt1_2);
    }

    final quiet = compGain(0.03); // -30dB 언저리 — 문턱 아래
    final loud = compGain(0.7); // 문턱 한참 위
    check(
      '7) 큰 소리만 눌린다',
      quiet > 0.9 && loud < 0.6,
      '작은 소리 ${quiet.toStringAsFixed(2)}배 · 큰 소리 ${loud.toStringAsFixed(2)}배',
    );

    // 8) 방식마다 **반응 속도**가 다르다 — FET 이 제일 빨리 잡는다
    double firstCatchSamples(int mode) {
      final c = makeFx('comp')!
        ..set('mode', mode.toDouble())
        ..set('thr', -20)
        ..set('ratio', 8)
        ..set('atk', 0.5);
      for (var i = 0; i < 48000; i++) {
        c.step(0.8, 0.8);
        if (c.outL.abs() < 0.8 * 0.6) return i.toDouble();
      }
      return 48000;
    }

    final opto = firstCatchSamples(0);
    final fet = firstCatchSamples(1);
    final vca = firstCatchSamples(2);
    check(
      '8) 방식마다 속도가 다르다',
      fet < vca && vca < opto,
      'FET ${fet.round()} < VCA ${vca.round()} < 옵토 ${opto.round()} 샘플',
    );

    // 9) **채널 스트립에 실제로 꽂힌다** — DSP 가 아무리 맞아도 배선이 없으면
    //    사용자에게는 없는 기능이다(라이브 화면에서 같은 실수를 한 적이 있다).
    final mix = TrackMix();
    double peakOf(TrackMix m) {
      var pk = 0.0;
      for (var i = 0; i < 4800; i++) {
        final x = 0.5 * math.sin(2 * math.pi * 220 * i / kSampleRate);
        final (l, _) = m.process(x, x);
        if (i > 2400 && l.abs() > pk) pk = l.abs();
      }
      return pk;
    }

    final dry = peakOf(mix);
    mix.inserts.add(
      makeFx('amp')!
        ..set('mode', 2)
        ..set('gain', 0.9),
    );
    final wet = peakOf(mix);
    check(
      '9) 채널에 꽂힌다',
      (wet - dry).abs() > 0.01,
      '안 꽂았을 때 ${dry.toStringAsFixed(3)} → 앰프 꽂고 ${wet.toStringAsFixed(3)}',
    );

    // 10) **꺼 두면 없는 것과 같다** — 바이패스가 진짜 바이패스여야 한다.
    //     새 스트립으로 잰다 — 같은 스트립을 다시 쓰면 EQ 필터에 남은 상태 때문에
    //     0.2% 쯤 달라진다(그건 인서트 탓이 아니다. 여기서 한 번 헷갈렸다).
    final fresh = TrackMix()
      ..inserts.add(
        makeFx('amp')!
          ..set('mode', 2)
          ..set('gain', 0.9)
          ..on = false,
      );
    final bypass = peakOf(fresh);
    final plain = peakOf(TrackMix());
    check(
      '10) 끄면 그대로',
      (bypass - plain).abs() < 1e-12,
      '${bypass.toStringAsFixed(9)} vs ${plain.toStringAsFixed(9)}',
    );

    // ── 나머지 플러그인 (5단계 47/N) ──

    // 15) 리버브 — **꼬리가 남는다.** 소리를 끊고도 한참 이어져야 리버브다.
    double tailSec(int mode) {
      final rv = makeFx('reverb')!
        ..set('mode', mode.toDouble())
        ..set('mix', 1);
      var last = 0;
      for (var i = 0; i < kSampleRate * 5; i++) {
        rv.step(i < 100 ? 1.0 : 0.0, i < 100 ? 1.0 : 0.0);
        if (rv.outL.abs() > 0.001) last = i;
      }
      return last / kSampleRate;
    }

    final room = tailSec(0), plate = tailSec(1), hall = tailSec(2);
    check(
      '15) 리버브 꼬리',
      room > 0.2 && hall > room,
      '룸 ${room.toStringAsFixed(2)}s · 플레이트 ${plate.toStringAsFixed(2)}s · 홀 ${hall.toStringAsFixed(2)}s',
    );

    // 16) 그래픽 EQ — 그 밴드만 오르내린다
    double bandRms(int band, double db, double freq) {
      final eq = makeFx('geq')!..set('b$band', db);
      _run(eq, freq: freq, n: 2400);
      return _rms(_run(eq, freq: freq, n: 4800));
    }

    final up = bandRms(4, 12, 1000); // 1k 를 +12
    final flat = bandRms(4, 0, 1000);
    final other = bandRms(4, 12, 125); // 같은 설정에서 125Hz 는 그대로여야
    final otherFlat = bandRms(4, 0, 125);
    check(
      '16) 그래픽 EQ',
      up > flat * 2 && (other / otherFlat - 1).abs() < 0.15,
      '1k ${(up / flat).toStringAsFixed(2)}배 · 125Hz ${(other / otherFlat).toStringAsFixed(2)}배',
    );

    // 17) 리미터 — **천장을 안 넘는다.** 이게 안 되면 리미터가 아니다.
    final lim = makeFx('limiter')!
      ..set('drive', 12)
      ..set('ceil', -6);
    var pk = 0.0;
    for (var i = 0; i < 48000; i++) {
      final x = 0.9 * math.sin(2 * math.pi * 110 * i / kSampleRate);
      lim.step(x, x);
      if (i > 4800 && lim.outL.abs() > pk) pk = lim.outL.abs();
    }
    final ceilLin = math.pow(10, -6 / 20).toDouble();
    check(
      '17) 리미터 천장',
      pk <= ceilLin * 1.02,
      '피크 ${pk.toStringAsFixed(3)} · 천장 ${ceilLin.toStringAsFixed(3)}',
    );

    // 18) 드라이브 — 방식마다 더 세게 뭉갠다
    double driveThd(int mode) {
      final d = makeFx('drive')!
        ..set('mode', mode.toDouble())
        ..set('drive', 0.6);
      _run(d, n: 2400);
      return _thd(_run(d, n: 4800), 220);
    }

    final od = driveThd(0), dist = driveThd(1), fuzz = driveThd(2);
    check(
      '18) 드라이브 셋',
      od < dist && dist < fuzz,
      '오버드라이브 ${(od * 100).toStringAsFixed(0)}% < 디스토션 ${(dist * 100).toStringAsFixed(0)}% < 퍼즈 ${(fuzz * 100).toStringAsFixed(0)}%',
    );

    // 19) 베이스 앰프 — **저역은 안 뭉갠다.** 블렌드를 올려도 저역은 깨끗해야 한다.
    double bassThd(double freq) {
      final ba = makeFx('bassamp')!
        ..set('drive', 0.9)
        ..set('blend', 1);
      _run(ba, freq: freq, n: 2400);
      return _thd(_run(ba, freq: freq, n: 4800), freq);
    }

    final lowThd = bassThd(60), midThd = bassThd(800);
    check(
      '19) 베이스는 저역을 지킨다',
      lowThd < midThd,
      '60Hz ${(lowThd * 100).toStringAsFixed(1)}% < 800Hz ${(midThd * 100).toStringAsFixed(1)}%',
    );

    // 20) 요청한 것이 다 있다
    const needed = {
      '기타 앰프',
      '베이스 앰프',
      '드라이브',
      '컴프',
      '리버브',
      '딜레이',
      '그래픽 EQ',
      '리미터',
    };
    final have = {for (final d in kFxCatalog.values) d.name};
    final missing = needed.difference(have);
    check(
      '20) 목록',
      missing.isEmpty,
      '${have.length}종 · 빠진 것 ${missing.isEmpty ? '없음' : missing.join(',')}',
    );

    // ── 저장·내보내기까지 이어지는가 (5단계 46/N) ──
    //
    // DSP 가 맞고 화면이 있어도 **저장이 안 되면** 앱을 껐다 켜는 순간 사라진다.
    // 그리고 **내보내기가 인서트를 안 태우면** 들리던 것과 다른 파일이 나온다.
    // 둘 다 '나중에' 로 미루기 쉬운 자리라 여기서 못 박는다.
    final proj = Project.initial();
    final t = proj.tracks.first;
    t.addFx('amp');
    t.setFxParam(0, 'mode', 2);
    t.setFxParam(0, 'gain', 0.8);
    t.addFx('delay');
    t.setFxOn(1, false);

    check(
      '11) 꽂힌다',
      t.chain.length == 2 && t.chain[0].type == 'amp',
      '${[for (final f in t.chain) f.type].join(' → ')}',
    );

    // 순서 바꾸기 — **순서가 곧 소리다**
    t.moveFx(0, 1);
    check(
      '12) 순서를 바꾼다',
      t.chain[0].type == 'delay' && t.chain[1].type == 'amp',
      '${[for (final f in t.chain) f.type].join(' → ')}',
    );
    t.moveFx(0, 1); // 되돌려 놓고 계속

    // 저장 → 되살리기
    final back = Track.fromJson(t.toJson());
    final ok =
        back.chain.length == 2 &&
        back.chain[0].type == 'amp' &&
        back.chain[0].p['gain'] == 0.8 &&
        back.chain[0].p['mode'] == 2 &&
        back.chain[1].on == false;
    check(
      '13) 저장·되살리기',
      ok,
      '${back.chain.length}칸 · 게인 ${back.chain[0].p['gain']} · 딜레이 켜짐 ${back.chain[1].on}',
    );

    // 내보내기용 묶음에도 들어간다
    final snap = SceneSequencer.insertSnapshot(proj);
    final mine = snap[SceneSequencer.busOf(t)] ?? const [];
    check(
      '14) 내보내기에도 실린다',
      mine.length == 2 && mine[0]['type'] == 'amp',
      '${mine.length}칸',
    );

    // ── 마스터 인서트 (5단계 47/N) ────────────────────────────────────
    // 트랙과 **같은 통로**를 쓰는지, 그리고 저장까지 되는지.
    // 마스터링은 "곡 하나에 한 번" 이라 눈으로 확인할 기회가 적다 — 여기서 못 박는다.
    final m = MasterChannel();
    m.addFx('comp');
    m.setFxParam(0, 'mode', 1); // FET
    m.addFx('limiter');
    check(
      '15) 마스터에도 꽂힌다',
      m.chain.length == 2 && m.chain[1].type == 'limiter',
      '${[for (final f in m.chain) f.type].join(' → ')}',
    );

    // 트랙과 같은 인터페이스 — 화면(FxRack)이 하나로 돌아가는 근거
    check(
      '16) 트랙과 같은 통로',
      m is FxChainOwner && proj.tracks.first is FxChainOwner,
      '',
    );

    // 저장 꾸러미(store.dart 가 쓰는 그 모양) → 되살리기
    final mjson = [for (final f in m.chain) f.toJson()];
    final m2 = MasterChannel();
    for (final j in mjson) {
      m2.chain.add(FxSlot.fromJson(j as Map<String, dynamic>));
    }
    check(
      '17) 마스터 저장·되살리기',
      m2.chain.length == 2 &&
          m2.chain[0].p['mode'] == 1 &&
          m2.chain[1].type == 'limiter',
      '${m2.chain.length}칸 · 컴프 성향 ${m2.chain[0].p['mode']}',
    );

    // 엔진 쪽 — 'master' 라는 이름이 마스터 인서트로 간다
    final eng = Engine();
    final mf = makeFx('limiter')!;
    mf.set('ceil', -6);
    eng.masterInserts.add(mf);
    check('18) 엔진 마스터 자리', eng.masterInserts.length == 1, '');

    // ignore: avoid_print
    print(fail == 0 ? '인서트 플러그인 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}

void _presetTests() {
  test('원탭 프리셋', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    // 1) 목록에 적은 플러그인이 **전부 실제로 있는 종류**여야 한다.
    //    오타 하나면 그 프리셋은 조용히 한 칸 짧아진다 — 소리로만 알 수 있다.
    final unknown = <String>[];
    for (final ps in [...kTrackFxPresets, ...kMasterFxPresets]) {
      for (final (type, _) in ps.chain) {
        if (!kFxCatalog.containsKey(type)) unknown.add('${ps.name}/$type');
      }
    }
    check(
      '1) 모르는 플러그인을 안 적었다',
      unknown.isEmpty,
      unknown.isEmpty
          ? '${kTrackFxPresets.length + kMasterFxPresets.length}개 프리셋 전부'
          : unknown.join(', '),
    );

    // 2) 손잡이 이름도 실제로 있어야 한다 — 없는 이름은 **아무 일도 안 한다**.
    final badParam = <String>[];
    for (final ps in [...kTrackFxPresets, ...kMasterFxPresets]) {
      for (final (type, params) in ps.chain) {
        final def = kFxCatalog[type];
        if (def == null) continue;
        final keys = {for (final p in def.params) p.key};
        for (final k in params.keys) {
          if (!keys.contains(k)) badParam.add('${ps.name}/$type.$k');
        }
      }
    }
    check(
      '2) 모르는 손잡이를 안 적었다',
      badParam.isEmpty,
      badParam.isEmpty ? '전부 실제 손잡이' : badParam.join(', '),
    );

    // 3) 값이 그 손잡이 범위 안이어야 한다 — 밖이면 잘려서 적은 뜻과 달라진다.
    final outOfRange = <String>[];
    for (final ps in [...kTrackFxPresets, ...kMasterFxPresets]) {
      for (final (type, params) in ps.chain) {
        final def = kFxCatalog[type];
        if (def == null) continue;
        for (final p in def.params) {
          final v = params[p.key];
          if (v == null) continue;
          if (v < p.min || v > p.max) {
            outOfRange.add('${ps.name}/$type.${p.key}=$v (${p.min}~${p.max})');
          }
        }
      }
    }
    check(
      '3) 값이 범위 안이다',
      outOfRange.isEmpty,
      outOfRange.isEmpty ? '전부 범위 안' : outOfRange.join(', '),
    );

    // 4) **더하지 않고 갈아 끼운다** — 두 번 누르면 리버브가 둘이 되면 안 된다.
    {
      final m = MasterChannel();
      final wide = kTrackFxPresets.firstWhere((x) => x.name == '넓게');
      applyFxPreset(m, wide);
      final once = m.chain.length;
      applyFxPreset(m, wide);
      final twice = m.chain.length;
      // 값도 실렸는가
      final delay = m.chain.firstWhere((x) => x.type == 'delay');
      final wet = delay.p['mix'];
      applyFxPreset(m, kMasterFxPresets.firstWhere((x) => x.name == '그대로'));
      check(
        '4) 더하지 않고 갈아 끼운다',
        once == wide.chain.length &&
            twice == once &&
            wet != null &&
            m.chain.isEmpty,
        '한 번 $once개 · 두 번 $twice개 · 섞기 $wet · 「그대로」 뒤 ${m.chain.length}개',
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '원탭 프리셋 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}

void _chorusTests() {
  test('코러스', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    /// 사인파를 [sec]초 넣고 좌우 출력을 받는다.
    (List<double>, List<double>) run(Fx fx, double sec, {double freq = 220}) {
      final n = (kSampleRate * sec).round();
      final l = <double>[], r = <double>[];
      for (var i = 0; i < n; i++) {
        final v = math.sin(2 * math.pi * freq * i / kSampleRate) * 0.5;
        fx.step(v, v);
        l.add(fx.outL);
        r.add(fx.outR);
      }
      return (l, r);
    }

    // 1) **좌우가 달라져야 한다** — 같으면 두꺼워지기만 하고 안 넓어진다.
    //    (좌우를 반대 위상으로 흔드는 것이 코러스의 핵심이다)
    {
      final fx = makeFx('chorus')!;
      final (l, r) = run(fx, 1.0);
      var diff = 0.0;
      for (var i = kSampleRate ~/ 2; i < l.length; i++) {
        diff += (l[i] - r[i]).abs();
      }
      diff /= l.length - kSampleRate ~/ 2;
      check('1) 좌우가 갈린다', diff > 0.02, '평균 차이 ${diff.toStringAsFixed(4)}');
    }

    // 2) **섞기 0 이면 원음 그대로** — 안 걸었을 때 소리가 변하면 안 된다.
    {
      final fx = makeFx('chorus')!..set('mix', 0);
      var worst = 0.0;
      for (var i = 0; i < kSampleRate; i++) {
        final v = math.sin(2 * math.pi * 220 * i / kSampleRate) * 0.5;
        fx.step(v, v);
        final d = (fx.outL - v).abs();
        if (d > worst) worst = d;
      }
      check('2) 섞기 0 = 원음 그대로', worst < 1e-12, '제일 큰 차이 $worst');
    }

    // 3) **깊이를 키우면 흔들림이 커진다** — 손잡이가 실제로 무언가를 해야 한다.
    //
    // **낮은 음으로 재야 한다.** 220Hz 는 한 주기가 4.5ms 라, 깊이 1ms 와 9ms 가
    // 둘 다 반 주기를 넘어 버려서 좌우 차이가 똑같이 꽉 찬다(자가 천장에 붙는다).
    // 40Hz(25ms 주기)면 1ms = 14도, 9ms = 130도 — 차이가 그대로 보인다.
    {
      double swing(double depth) {
        final fx = makeFx('chorus')!
          ..set('depth', depth)
          ..set('mix', 1.0);
        final (l, r) = run(fx, 1.0, freq: 40);
        var d = 0.0;
        for (var i = kSampleRate ~/ 2; i < l.length; i++) {
          d += (l[i] - r[i]).abs();
        }
        return d / (l.length - kSampleRate ~/ 2);
      }

      final shallow = swing(1), deep = swing(9);
      check(
        '3) 깊이가 실제로 먹는다',
        deep > shallow * 1.3,
        '깊이1 ${shallow.toStringAsFixed(3)} → 깊이9 ${deep.toStringAsFixed(3)}',
      );
    }

    // 4) **안 터지고 안 넘친다** — 1을 넘으면 하드클립이 된다.
    {
      final fx = makeFx('chorus')!
        ..set('mix', 1.0)
        ..set('depth', 10)
        ..set('rate', 6);
      final (l, r) = run(fx, 2.0, freq: 55);
      var peak = 0.0;
      var bad = 0;
      for (var i = 0; i < l.length; i++) {
        final a = l[i].abs(), b = r[i].abs();
        if (a > peak) peak = a;
        if (b > peak) peak = b;
        if (!l[i].isFinite || !r[i].isFinite) bad++;
      }
      check(
        '4) 넘치거나 터지지 않는다',
        peak <= 1.0 && bad == 0,
        '봉우리 ${peak.toStringAsFixed(3)} · 이상한 값 $bad개',
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '코러스 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
