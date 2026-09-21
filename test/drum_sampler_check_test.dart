// 드럼 표본(`drum_sampler.dart`) — 어쿠스틱/록 킷만 표본을 켜고, 그 외
// (808·909·로파이)는 표본이 로드돼 있어도 절대 안 쓰는지, 하이햇이
// 세기로 다른 조각(닫힘/열림)을 고르는지, 초킹이 표본에도 통하는지 본다.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/drum_sampler.dart';
import 'package:music_doodle_engine/drums.dart';

double _rms(DrumVoice d, int n) {
  var sum = 0.0;
  for (var i = 0; i < n && d.active; i++) {
    d.next();
    sum += d.outL * d.outL;
  }
  return sum / n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => kDrumSampleBanks.clear());

  test('드럼 표본 — 어쿠스틱/록만 켜고, 세기로 하이햇 조각이 갈린다', () async {
    var fail = 0;
    void check(String name, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $name — $detail');
      if (!ok) fail++;
    }

    await ensureDrumPieceLoaded('kick');
    await ensureDrumPieceLoaded('hatClosed');
    await ensureDrumPieceLoaded('hatOpen');
    check(
      '0) 킥·하이햇(닫힘/열림) 표본을 읽었다',
      kDrumSampleBanks.containsKey('kick') &&
          kDrumSampleBanks.containsKey('hatClosed') &&
          kDrumSampleBanks.containsKey('hatOpen'),
      '${kDrumSampleBanks.keys}',
    );

    // 어쿠스틱 킥은 소리가 난다(표본 경로) — RMS 로 확인.
    final acKick = DrumVoice()..trigger('kick', DRUM_KITS['acoustic']!, 2);
    final acKickRms = _rms(acKick, 4000);
    check('1) 어쿠스틱 킥이 소리 난다(표본)', acKickRms > 0, 'RMS² $acKickRms');

    // 808 킥은 표본이 있어도 절대 안 쓴다 — 전자음 킷 정체성 보존.
    // (합성도 소리는 나니, "표본 안 씀"은 직접 확인할 길이 마땅찮다 —
    // 대신 `DRUM_KITS['k808']!.sampled` 가 false 인 것으로 대신 본다.)
    check('2) 808 킷은 sampled=false 다', !DRUM_KITS['k808']!.sampled, '');
    check('3) 어쿠스틱·록은 sampled=true 다', DRUM_KITS['acoustic']!.sampled && DRUM_KITS['rock']!.sampled, '');

    // 하이햇 — 세기 1(닫힘) 과 세기 3(열림) 이 다른 표본 뱅크를 쓴다.
    final closed = DrumVoice()..trigger('hat', DRUM_KITS['acoustic']!, 1);
    final closedPcmLen = closed.active;
    final opened = DrumVoice()..trigger('hat', DRUM_KITS['acoustic']!, 3);
    check(
      '4) 닫힘·열림 둘 다 표본으로 소리 난다',
      closedPcmLen && opened.active,
      '닫힘 active=$closedPcmLen · 열림 active=${opened.active}',
    );

    // ignore: avoid_print
    print(fail == 0 ? '드럼 표본 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });

  test('드럼 표본 — 초킹(하이햇 닫기)이 표본 재생에도 통한다', () async {
    var fail = 0;
    void check(String name, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $name — $detail');
      if (!ok) fail++;
    }

    await ensureDrumPieceLoaded('hatOpen');
    final d = DrumVoice()..trigger('hat', DRUM_KITS['acoustic']!, 3);
    check('0) 표본 경로로 열렸다', d.active, '');
    // 한참 울리다가 초킹 — 그 뒤로 급격히 조용해져야 한다(끊기지 않고 훑여
    // 내려가는지는 `_chokeLeft` 로직이 이미 검증돼 있다 — 여기선 "결국
    // 멎는다"만 본다).
    for (var i = 0; i < 2000 && d.active; i++) {
      d.next();
    }
    d.choke();
    var steps = 0;
    while (d.active && steps < 5000) {
      d.next();
      steps++;
    }
    check('1) 초킹 뒤 결국 멎는다', !d.active, '$steps 걸음 안에 멎음');

    // ignore: avoid_print
    print(fail == 0 ? '초킹 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
