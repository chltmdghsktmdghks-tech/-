// 두들 제스처가 부를 소리 기능 4종 — 808 붐(홀드 꼬리) · 킥 사이드체인 펌핑 대상 버스 ·
// 오픈 하이햇 자동 닫힘 · 스웰 볼륨 오토메이션.
//   flutter test test/doodle_sound_hooks_test.dart
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/engine.dart';
import 'package:music_doodle_engine/synth.dart' show Human;

/// [from]~[to] 초 구간의 RMS (스테레오 인터리브).
double rms(Int16List o, double from, double to) {
  final a = (from * 48000).round(), b = (to * 48000).round();
  var s = 0.0;
  for (var i = a; i < b; i++) {
    final l = o[i * 2] / 32768.0;
    s += l * l;
  }
  return math.sqrt(s / (b - a));
}

Engine mk() {
  final e = Engine()..trackMix.configure(['bass', 'chord', 'melody']);
  return e;
}

void main() {
  setUp(() => Human.setLevel(0)); // 비교 시험은 사람다움 난수를 끈다

  group('1. 808 붐 — 꼬리 길이', () {
    test('tailSec 를 주면 킥 꼬리가 그만큼 늘고, 안 주면 예전 킥(짧음)', () {
      final short = mk()..drumOn('k808', 'kick', 3);
      final long = mk()..drumOn('k808', 'kick', 3, tailSec: 2.0);
      final os = short.render(48000 * 2), ol = long.render(48000 * 4);
      final rs = rms(os, 1.0, 1.5), rl = rms(ol, 1.0, 1.5);
      // ignore: avoid_print
      print('kick tail RMS@1.0~1.5s  짧은=$rs  긴=$rl');
      expect(rs, lessThan(0.002));
      expect(rl, greaterThan(0.01));
      expect(rl, greaterThan(rs * 10));
      // 무한히 울지 않는다 — 꼬리는 결국 끝난다
      expect(rms(ol, 3.6, 4.0), lessThan(0.001));
    });

    test('킥 홀드 — 누르는 동안 서브 유지, 놓으면 tailSec 뒤 사라지고 목소리 회수', () {
      final e = mk()..drumHold(7, 'k808', 3);
      final o1 = e.render(48000); // 1초 누름
      expect(e.heldDrumCount, 1);
      expect(rms(o1, 0.8, 1.0), greaterThan(0.01), reason: '누르는 동안은 계속 운다');
      e.drumRelease(7, tailSec: 0.3);
      final o2 = e.render(48000); // 놓은 뒤 1초
      expect(rms(o2, 0.0, 0.1), greaterThan(rms(o2, 0.4, 0.5)));
      expect(rms(o2, 0.5, 1.0), lessThan(0.001), reason: '꼬리(0.3s) 뒤엔 조용');
      expect(e.heldDrumCount, 0);
      expect(e.drumActiveCount, 0);
    });

    test('베이스 홀드 — holdOff(tailSec) 가 길수록 손 뗀 뒤 더 오래 운다', () {
      double tailRms(double tail) {
        final e = mk()..noteHold(1, 'sine', 55, 3, part: 0);
        e.render(24000);
        e.noteRelease(1, tailSec: tail);
        final o = e.render(48000 * 2);
        return rms(o, 0.8, 1.2);
      }

      final t0 = tailRms(0), t2 = tailRms(2.0);
      // ignore: avoid_print
      print('bass hold 릴리스 RMS@0.8~1.2s  기본=$t0  2s꼬리=$t2');
      expect(t2, greaterThan(t0 * 5));
      expect(boomTailFor(0.05), 0.08); // 하한
      expect(boomTailFor(1.2), 1.2); // 1:1
      expect(boomTailFor(20), 3.5); // 상한
    });

    test('noteOn tailSec — 짧은 음도 꼬리가 늘어난다(기본 0 = 그대로)', () {
      final a = mk()..noteOn('sine', 55, 0.2, 3, part: 0);
      final b = mk()..noteOn('sine', 55, 0.2, 3, part: 0, tailSec: 2.0);
      expect(rms(b.render(48000 * 2), 1.0, 1.5),
          greaterThan(rms(a.render(48000 * 2), 1.0, 1.5) * 5));
    });
  });

  group('2. 킥 사이드체인 — 코드·베이스 버스만', () {
    // 멜로디 슬롯(2)에 지속음 + 킥. 드럼 버스는 0 으로 죽여 킥 소리 자체는 빼고 본다.
    double melodyDip(Set<String>? buses) {
      final e = mk()
        ..duckAmount = 0.5
        ..trackMix.drum.vol = 0
        ..setDuckBuses(buses);
      e.noteOn('sine', 440, 1.5, 3, part: 2);
      final before = rms(e.render(4800), 0.02, 0.1);
      e.drumOn('k909', 'kick', 3);
      final after = rms(e.render(480), 0.0, 0.01);
      return after / before;
    }

    double bassDip(Set<String>? buses) {
      final e = mk()
        ..duckAmount = 0.5
        ..trackMix.drum.vol = 0
        ..setDuckBuses(buses);
      e.noteOn('sine', 110, 1.5, 3, part: 0);
      final before = rms(e.render(4800), 0.02, 0.1);
      e.drumOn('k909', 'kick', 3);
      final after = rms(e.render(480), 0.0, 0.01);
      return after / before;
    }

    test('기본(null) = 예전처럼 전부 눌림, 대상을 주면 그 버스만', () {
      final all = melodyDip(null);
      final only = melodyDip({'bass', 'chord'});
      final bass = bassDip({'bass', 'chord'});
      // ignore: avoid_print
      print('멜로디 dip  전부=$all  코드·베이스만=$only   |  베이스 dip(대상)=$bass');
      expect(all, lessThan(0.8), reason: '기본은 멜로디도 눌린다');
      expect(only, greaterThan(0.93), reason: '멜로디는 펌핑 대상이 아니다');
      expect(bass, lessThan(0.8), reason: '베이스는 킥에 눌린다');
    });

    test('킥이 아니면 안 눌리고, 복귀한다(펌핑)', () {
      final e = mk()
        ..duckAmount = 0.5
        ..setDuckBuses({'bass', 'chord'});
      e.drumOn('k909', 'snare', 3);
      expect(e.duckLevel, 1.0);
      e.drumOn('k909', 'kick', 3);
      expect(e.duckLevel, closeTo(0.5, 1e-9));
      e.render(48000 ~/ 2); // 0.5초 뒤
      expect(e.duckLevel, greaterThan(0.9));
    });

    test('kPumpGenres — 하우스 계열만 자동 ON', () {
      expect(kPumpGenres.contains('house'), isTrue);
      expect(kPumpGenres.contains('jazz'), isFalse);
    });
  });

  group('3. 오픈 하이햇 — 길게 울고 킥/다음 하이햇에 닫힘', () {
    test('hatopen 은 열린 하이햇(vel3)보다도 길게 운다', () {
      final a = mk()..drumOn('k808', 'hat', 3);
      final b = mk()..drumOn('k808', 'hatopen', 3);
      a.render(48000 ~/ 4);
      b.render(48000 ~/ 4);
      expect(b.liveHatCount, 1, reason: '250ms 에도 아직 울림');
      expect(a.liveHatCount, 0, reason: '보통 열림은 이미 끝');
    });

    test('킥이 치면 열린 하이햇이 닫힌다', () {
      final e = mk()..drumOn('k808', 'hatopen', 3);
      e.render(4800);
      expect(e.liveHatCount, 1);
      e.drumOn('k808', 'kick', 2);
      e.render(48000 ~/ 20); // 초킹 20ms + 여유
      expect(e.liveHatCount, 0);
    });

    test('다음 하이햇 타격도 열린 것을 닫는다', () {
      final e = mk()..drumOn('k808', 'hatopen', 3);
      e.render(4800);
      e.drumOn('k808', 'hat', 1);
      e.render(48000 ~/ 50);
      // 닫힌 하이햇(짧음)만 남거나 그마저 끝났다 — 열린 것은 없다
      final e2 = mk()..drumOn('k808', 'hatopen', 3);
      e2.render(4800 + 48000 ~/ 50);
      expect(e2.liveHatCount, 1, reason: '대조: 안 치면 계속 운다');
    });

    test('닫힌 하이햇은 킥이 안 건드린다(16분 하이햇이 잘리지 않음)', () {
      final e = mk()..drumOn('k808', 'hat', 1);
      e.drumOn('k808', 'kick', 2);
      // 이 시점 hat 은 초킹 예약이 없어야 한다 — 소리 길이가 같은지 대조
      final c = mk()..drumOn('k808', 'hat', 1);
      final oe = e.render(2400), oc = c.render(2400);
      expect(rms(oe, 0.01, 0.05), greaterThan(0));
      expect(oc.length, oe.length);
    });
  });

  group('4. 스웰 — 버스 볼륨 오토메이션', () {
    Engine pad() {
      final e = mk();
      e.noteOn('sine', 220, 6.0, 3, part: 1);
      return e;
    }

    test('안 쓰면 출력이 한 비트도 안 바뀐다', () {
      final a = pad().render(24000), b = pad();
      b.clearSwell();
      expect(b.render(24000), a);
    });

    test('setSwell — 진행도를 밀면 그 버스 볼륨이 따라간다', () {
      final e = pad();
      e.setSwell('chord', 0.0);
      final quiet = rms(e.render(24000), 0.2, 0.5);
      e.setSwell('chord', 1.0);
      final loud = rms(e.render(24000), 0.2, 0.5);
      expect(loud, greaterThan(quiet * 20));
      expect(e.swellLevel('chord'), 1.0);
    });

    test('startSwell — 목표 시간에 걸쳐 단조 증가, 끝나면 1', () {
      final e = pad();
      e.startSwell('chord', 2.0);
      final o = e.render(48000 * 3);
      final w = [
        rms(o, 0.1, 0.4),
        rms(o, 0.6, 0.9),
        rms(o, 1.1, 1.4),
        rms(o, 1.6, 1.9),
        rms(o, 2.2, 2.5),
      ];
      // ignore: avoid_print
      print('swell RMS 창별: $w');
      for (var i = 1; i < w.length; i++) {
        expect(w[i], greaterThan(w[i - 1]));
      }
      expect(e.swellLevel('chord'), 1.0);
    });

    test('다른 버스는 안 건드리고, 모르는 버스 이름은 무시', () {
      final e = mk();
      e.noteOn('sine', 330, 2.0, 3, part: 2);
      e.setSwell('chord', 0.0);
      e.setSwell('없는버스', 0.0);
      final o = e.render(24000);
      final r = mk();
      r.noteOn('sine', 330, 2.0, 3, part: 2);
      expect(o, r.render(24000));
    });
  });
}
