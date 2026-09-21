// 표본 콘텐츠팩의 핵심 약속 — **곡이 안 쓰는 악기는 안 읽고, 처음 치는 순간엔
// 끊기지 않고 합성으로 대신 나간다.** `sampler_check_test.dart` 는 이미 다
// 불러온 뒤의 소리를 본다 — 여기서는 **불러오기 전** 그 순간만 본다.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/sampler.dart';
import 'package:music_doodle_engine/synth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() => kSampleBanks.clear());

  test('표본 지연 로딩 — 안 친 악기는 안 읽혀 있다, 처음 쳐도 안 끊긴다', () async {
    var fail = 0;
    void check(String name, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $name — $detail');
      if (!ok) fail++;
    }

    check(
      '0) 시작할 때 표본을 하나도 안 읽어 놨다',
      kSampleBanks.isEmpty,
      '이미 든 것: ${kSampleBanks.keys}',
    );

    // 첼로를 한 번도 안 건드린 상태에서 바로 친다 — 로드가 끝나기 전이라
    // 합성 경로로 가야 한다(무음이 아니어야 함, 예외도 없어야 함).
    final n = SynthNote();
    n.noteOn('cello', 130.81, 0.3, 2);
    var rms = 0.0;
    var count = 0;
    for (var i = 0; i < (0.2 * kSampleRate).round() && n.active; i++) {
      n.next();
      rms += n.outL * n.outL;
      count++;
    }
    rms = count == 0 ? 0 : rms / count;
    check(
      '1) 첫 음은 예외 없이, 무음 아니게 난다(합성 대신)',
      rms > 0,
      'RMS² 평균 ${rms.toStringAsFixed(6)}',
    );

    // `noteOn` 이 백그라운드로 건 로드는 이미 `_loading` 에 들어가 있어서
    // `ensureInstrumentLoaded` 를 여기서 또 불러도(가드 때문에) 그 로드 자체를
    // 기다려 주지 않는다 — 그래서 끝날 때까지 짧게 폴링한다.
    var waited = 0.0;
    while (!kSampleBanks.containsKey('cello') && waited < 5.0) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      waited += 0.02;
    }
    check('2) 로드가 끝났다', kSampleBanks.containsKey('cello'), '${kSampleBanks.keys}');

    // ignore: avoid_print
    print(fail == 0 ? '지연 로딩 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
