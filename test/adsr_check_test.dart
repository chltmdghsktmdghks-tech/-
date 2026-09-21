// ADSR 손잡이 확인 — 신스 악기만 대상인지, 값이 실제로 엔벨로프에 얹히는지,
// 저장·왕복해도 남는지 (사용자 요청, 2026-09-15: "악기들 ADSR 필요한
// 악기들은 악기 설정에 넣어 놓자").
//   flutter test test/adsr_check_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/instruments.dart';
import 'package:music_doodle_engine/project.dart';

void main() {
  test('ADSR 손잡이', () async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    // 1) 대상 걸러내기 — 신스만, 표본·뜯는 계열·모르는 이름(드럼 킷 등)은 빠진다.
    check('1) 신스 베이스는 대상', hasAdsr('moogbass'), '');
    check('1-b) 패드는 대상', hasAdsr('pad'), '');
    check('1-c) 표본 피아노는 대상 아님', !hasAdsr('piano'), '');
    check('1-d) 표본 바이올린은 대상 아님', !hasAdsr('violin'), '');
    check('1-e) 뜯는 계열(하프)은 대상 아님', !hasAdsr('harp'), '');
    check(
      '1-f) 드럼 킷 이름은 대상 아님(악기 표에 없는 이름)',
      !hasAdsr('로파이') && !hasAdsr('lofi') && !hasAdsr('acoustic'),
      '',
    );

    // 2) buildAdsr — decOverride 를 주면 그 시간으로 피크→서스테인이 내려간다.
    final e1 = Env();
    buildAdsr(e1, 0.01, 0.5, 0.2, 1.0, 0.5, decOverride: 0.3);
    // 어택(0.01) 다음, 디케이 0.3초 동안 피크(1.0)에서 서스테인(0.5)까지
    // 지수로 내려간다 — 그 구간 끝 부분에서는 값이 피크보다 뚜렷이 낮아야 한다.
    for (var i = 0; i < ((0.01 + 0.31) * kSampleRate).round(); i++) {
      e1.next();
    }
    check(
      '2) decOverride 뒤엔 서스테인 근처로 내려가 있다',
      e1.value < 0.7,
      e1.value.toStringAsFixed(3),
    );

    // 3) 손잡이가 없으면(둘 다 null) 예전과 같은 모양 — 죽지 않는다.
    final e2 = Env();
    buildAdsr(e2, 0.01, 0.5, 0.2, 1.0, null);
    check('3) sus 없으면 그대로 hold 만큼 유지', e2.totalSamples > 0, '');

    // 4) Track — 세터가 값 얹고, 저장·왕복해도 남는다.
    final t = Track('chord', name: '리드 트랙');
    t.voice = 'lead';
    t.setAdsrAttack(0.08);
    t.setAdsrDecay(0.12);
    t.setAdsrSustain(0.6);
    t.setAdsrRelease(0.4);
    check(
      '4) 세터가 값을 얹는다',
      t.adsrAttack == 0.08 &&
          t.adsrDecay == 0.12 &&
          t.adsrSustain == 0.6 &&
          t.adsrRelease == 0.4,
      '${t.adsrAttack}',
    );
    final t2 = Track.fromJson(t.toJson());
    check(
      '4-b) 저장 왕복해도 남는다',
      t2.adsrAttack == 0.08 &&
          t2.adsrDecay == 0.12 &&
          t2.adsrSustain == 0.6 &&
          t2.adsrRelease == 0.4,
      '${t2.adsrAttack} · ${t2.adsrDecay} · ${t2.adsrSustain} · ${t2.adsrRelease}',
    );

    // 5) 안 만지면(null) 저장 파일에 아예 안 적힌다 — 옛 파일과 모양이 같다.
    final t3 = Track('chord', name: '안 만진 트랙');
    check(
      '5) 안 만지면 JSON 에 안 남는다',
      !t3.toJson().containsKey('adsrAttack') &&
          !t3.toJson().containsKey('adsrRelease'),
      '',
    );

    // ignore: avoid_print
    print(fail == 0 ? 'ADSR 손잡이 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
