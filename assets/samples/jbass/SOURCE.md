# 일렉 베이스(J-Bass) 표본 출처(2026-09-28 추가)

**bk! New JBass** — 사용자가 개인적으로 갖고 있던 녹음(`~/Downloads/bk!'s_new_jbass/`).

라이선스: **NEEDS VERIFICATION** — 출처(제작자·배포 조건)가 확인되지 않았다.
상업적 배포 전에 반드시 라이선스를 확인할 것.

일반(언뮤트) 연주 4개만 썼다(뮤트(M) 파일 4개는 안 씀). 24비트·48kHz·모노,
재어택 없는 38~39초 자연감쇄.

| 원본 파일 | 등록 root | 비고 |
|---|---|---|
| E1_01-02.wav | E1 (41.2Hz, MIDI28) | |
| A1_01-03.wav | A1 (55.2Hz, MIDI33) | |
| D1_01-03.wav | D2 (73.4Hz, MIDI38) | 파일명은 D1 이지만 실측 피치는 D2 |
| G1_01-03.wav | G2 (98.0Hz, MIDI43) | 파일명은 G1 이지만 실측 피치는 G2 |

5현 베이스의 최저현 B0(30.9Hz)는 별도 표본이 없다 — `SampleBank.pick`
(`lib/sampler.dart`)이 로그스케일로 가장 가까운 root(E1)를 골라 피치
시프트로 채운다(사용자 확정 결정).

**세기 한 벌뿐**이라(pp/mf/ff 벨로시티 레이어를 실제로 나눠 녹음하지
않음) 세 파일이 다 같은 녹음이다 — `kRealVelSamples`(sampler.dart)에
안 넣었고, 음량만 기존 `VG` 표로 갈린다(기타·업라이트와 같은 처리).

`afconvert -f WAVE -d LEI16`로 24비트→16비트 모노 변환(48kHz는 그대로
— `synth.dart`의 `_smRatio`가 재생 시 보정하므로 리샘플 불필요), 이어서
`tool/prep_samples.dart`로 3초 트림 + 끝 150ms 페이드(`maxSecOverride`
`jbass: 3.0`, fingerbass/guitar와 같은 기준 — 뜯는 소리라 3초면 자연
감쇄가 거의 끝난다).
