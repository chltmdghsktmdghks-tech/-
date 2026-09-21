// 내보내기(WAV)가 실제로 표본을 쓰는지 — 사용자 지적("샘플 쓰고 있는거
// 맞아?")으로 찾은 버그의 회귀 시험.
//   flutter test test/export_sample_check_test.dart
//
// 렌더는 별도 아이솔레이트에서 도는데, 그 아이솔레이트가 `RootIsolateToken`
// 없이 뜨면 `rootBundle.load` 가 조용히 실패해서(표본 로더의 try/catch가
// 삼킨다) **표본 악기가 전부 합성으로 대신 나갔다** — 재생은 멀쩡했는데
// 내보낸 파일만 그랬다. 이제 `renderWavInIsolate` 가 토큰을 넘기고,
// `preloadExportSamples` 가 렌더 **시작 전에** 표본을 다 읽어 둔다.
//
// 아이솔레이트 경계 너머(진짜 렌더 아이솔레이트) 상태는 이 프로세스에서
// 직접 못 본다 — 그래서 `preloadExportSamples` 를 따로 떼어 **이 로직
// 자체**(어떤 악기를 고르고, 실제로 `kSampleBanks` 를 채우는지)를
// 여기서 직접 확인한다. 토큰을 넘기는 배선(`RootIsolateToken.instance`
// → `_renderEntry` → `ensureInitialized`)은 컴파일 타임에 타입으로
// 강제되는 단순 배선이라 상대적으로 덜 위험하다.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/drum_sampler.dart';
import 'package:music_doodle_engine/export.dart';
import 'package:music_doodle_engine/sampler.dart';
import 'package:music_doodle_engine/synth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    kSampleBanks.clear();
    kDrumSampleBanks.clear();
  });

  test('preloadExportSamples — job 이 쓰는 표본 악기·표본 드럼을 실제로 읽는다', () async {
    var fail = 0;
    void check(String name, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $name — $detail');
      if (!ok) fail++;
    }

    check('0) 시작할 때 아무것도 안 읽혀 있다', kSampleBanks.isEmpty, '${kSampleBanks.keys}');

    // 표본 악기(피아노·기타) 음과, 표본 없는 신스 악기(pad) 음을 섞어 둔다 —
    // pad 는 안 읽혀야 "쓰는 것만 고른다"가 지켜진다. 드럼은 어쿠스틱 킷
    // 하나만 친다.
    final job = ExportJob(
      notes: [
        ['piano', 261.63, 1.0, 2, false, 0.0, 0.0, kPartMelody],
        ['guitar', 220.0, 1.0, 2, false, 0.0, 0.0, kPartMelody],
        ['pad', 220.0, 1.0, 2, false, 0.0, 0.0, kPartChord],
      ],
      drums: [
        ['acoustic', 'kick', 2, 180.0, 0.0],
      ],
      busNames: const ['t1'],
      buses: const {},
      masterVol: 1.0,
      seconds: 2.0,
    );

    await preloadExportSamples(job);

    check(
      '1) 쓴 표본 악기(피아노·기타)를 읽었다',
      kSampleBanks.containsKey('piano') && kSampleBanks.containsKey('guitar'),
      '${kSampleBanks.keys}',
    );
    check(
      '2) 안 쓴 표본 악기(바이올린 등)는 안 읽었다',
      !kSampleBanks.containsKey('violin') && !kSampleBanks.containsKey('cello'),
      '${kSampleBanks.keys}',
    );
    check(
      '3) 표본 없는 신스 악기(pad)는 당연히 안 건드린다',
      !kSampleBanks.containsKey('pad'),
      '${kSampleBanks.keys}',
    );
    check(
      '4) 어쿠스틱 킷을 썼으니 드럼 표본도 읽었다',
      kDrumSampleBanks.containsKey('kick'),
      '${kDrumSampleBanks.keys}',
    );

    // ignore: avoid_print
    print(fail == 0 ? '내보내기 표본 로딩 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });

  test('preloadExportSamples — 전자음 킷만 쓰면 드럼 표본은 안 읽는다', () async {
    var fail = 0;
    void check(String name, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $name — $detail');
      if (!ok) fail++;
    }

    final job = ExportJob(
      notes: const [],
      drums: [
        ['k808', 'kick', 2, 180.0, 0.0],
      ],
      busNames: const ['t1'],
      buses: const {},
      masterVol: 1.0,
      seconds: 1.0,
    );
    await preloadExportSamples(job);
    check(
      '808 킷은 표본이 없어야 정체성이 안 깨진다',
      kDrumSampleBanks.isEmpty,
      '${kDrumSampleBanks.keys}',
    );

    // ignore: avoid_print
    print(fail == 0 ? '전자음 킷 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
