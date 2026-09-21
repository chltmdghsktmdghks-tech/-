// 악기 설정 확인 — 기타 본체·픽업, 피아노 모델·에이징이 실제로 트랙 EQ 에
// 얹히는지, 저장·왕복해도 남아 있는지 — `instrument_tone.dart`/`project.dart`.
//   flutter test test/instrument_tone_check_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/instrument_tone.dart';
import 'package:music_doodle_engine/project.dart';

void main() {
  test('악기 설정', () async {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    // 1) 순수 계산 — 기타가 아니면 (0,0,0).
    final none = instrumentToneEq(voice: 'pad');
    check('1) 기타·피아노가 아니면 손 안 댐', none == (0.0, 0.0, 0.0), '$none');

    // 2) 기타 — 본체+픽업이 더해진다.
    final strat = instrumentToneEq(
      voice: 'guitar',
      guitarBody: 'strat',
      guitarPickup: 'bridge',
    );
    check(
      '2) 스트랫+브릿지 = 둘 다 밝은 쪽이라 고음이 크게 올라간다',
      strat.$3 > 5,
      '$strat',
    );

    // 3) 피아노 — 에이징을 올릴수록 고음이 줄어든다.
    final fresh = instrumentToneEq(voice: 'piano', pianoAging: 0);
    final old = instrumentToneEq(voice: 'piano', pianoAging: 1);
    check('3) 에이징 1 이 0 보다 고음이 낮다', old.$3 < fresh.$3, '$fresh vs $old');

    // 4) Track 에 실제로 얹힌다 — 세터를 부르면 트랙 EQ 가 바뀐다.
    final t = Track('chord', name: '기타 트랙');
    t.voice = 'guitar';
    t.setGuitarBody('lespaul');
    t.setGuitarPickup('neck');
    check(
      '4) 트랙 EQ 에 실제로 얹힘',
      t.eq.lo > 0 && t.eq.hi < 0,
      '저 ${t.eq.lo} · 고 ${t.eq.hi}',
    );
    check('5) mixAuto 가 꺼진다(장르가 안 덮음)', !t.mixAuto, '${t.mixAuto}');

    // 6) 저장·왕복해도 남는다.
    final j = t.toJson();
    final t2 = Track.fromJson(j);
    check(
      '6) 저장 왕복 — 본체·픽업이 그대로',
      t2.guitarBody == 'lespaul' && t2.guitarPickup == 'neck',
      '${t2.guitarBody} · ${t2.guitarPickup}',
    );
    check(
      '7) 저장 왕복 — EQ 값도 그대로',
      t2.eq.lo == t.eq.lo && t2.eq.hi == t.eq.hi,
      '${t2.eq.lo} · ${t2.eq.hi}',
    );

    // 8) 피아노 트랙도 같은 방식.
    final p = Track('chord', name: '피아노 트랙');
    p.voice = 'piano';
    p.setPianoModel('upright');
    p.setPianoAging(0.5);
    check(
      '8) 피아노도 EQ 에 얹힘, 저장 왕복도 됨',
      Track.fromJson(p.toJson()).pianoAging == 0.5,
      '${p.pianoAging}',
    );

    // 9) 해당 없는 조합(guitarBody 를 준 피아노 트랙)은 무시된다.
    p.setGuitarBody('strat'); // 음색이 피아노라 계산에 안 쓰인다
    final afterIrrelevant = instrumentToneEq(
      voice: p.voice,
      guitarBody: p.guitarBody,
      pianoModel: p.pianoModel,
      pianoAging: p.pianoAging,
    );
    final beforeIrrelevant = instrumentToneEq(
      voice: 'piano',
      pianoModel: 'upright',
      pianoAging: 0.5,
    );
    check(
      '9) 피아노 음색에서 기타 설정은 무시된다',
      afterIrrelevant == beforeIrrelevant,
      '$afterIrrelevant',
    );

    // 10) 베이스·현악·관악도 같은 방식(사용자 요청, 2026-09-13: "악기들
    //     상세설정도 추가해") — 바디/편성/뮤트가 EQ 에 실제로 얹히고
    //     저장·왕복해도 남는다.
    final bs = Track('bass', name: '베이스 트랙');
    bs.voice = 'fingerbass';
    bs.setBassBody('jazz');
    check('10) 베이스 바디가 EQ 에 얹힘', bs.eq.lo != 0, '${bs.eq.lo}');
    check(
      '10-b) 저장 왕복 — 베이스 바디',
      Track.fromJson(bs.toJson()).bassBody == 'jazz',
      '',
    );

    final st = Track('chord', name: '현악 트랙');
    st.voice = 'violin';
    st.setStringsEnsemble('section');
    check('11) 현악 편성이 EQ 에 얹힘', st.eq.mid != 0, '${st.eq.mid}');
    check(
      '11-b) 저장 왕복 — 현악 편성',
      Track.fromJson(st.toJson()).stringsEnsemble == 'section',
      '',
    );

    final br = Track('melody', name: '관악 트랙');
    br.voice = 'trumpet';
    br.setBrassMute('mute');
    check('12) 관악 뮤트가 EQ 에 얹힘', br.eq.hi > 0, '${br.eq.hi}');
    check(
      '12-b) 저장 왕복 — 관악 뮤트',
      Track.fromJson(br.toJson()).brassMute == 'mute',
      '',
    );

    check(
      '13) hasInstrumentTone — 새 계열도 손잡이 대상',
      hasInstrumentTone('fingerbass') &&
          hasInstrumentTone('violin') &&
          hasInstrumentTone('trumpet') &&
          !hasInstrumentTone('pad'),
      '',
    );

    // ignore: avoid_print
    print(fail == 0 ? '악기 설정 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
