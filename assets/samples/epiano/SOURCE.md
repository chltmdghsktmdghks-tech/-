# 일렉 피아노(FM epiano) 표본 출처

**FreePats — "FM Piano 1"**
<https://freepats.zenvoid.org/ElectricPiano/synthesized-piano.html>
원본: <https://github.com/freepats/fm-piano1>

라이선스: **CC0 1.0 (퍼블릭 도메인)** — 크레딧 표기 의무 없음, 상업적 사용
제한 없음.

**진짜 1980년대 DX7(야마하 FM 신스)의 "E. Piano 1" 패치를 재현한 표본**
이다 — DX7 을 정확히 모델링한 무료 소프트웨어 신스 Hexter 로 녹음했다.
합성기 자체가 아니라 **그 출력을 녹음한 표본**이라 우리 엔진의 다른
표본 악기와 똑같이 다룰 수 있다(피치 시프트 재생).

root 12개(F#1~C7, 반음 6개 간격) × **세기 세 벌**(v60/v80/v100 →
pp/mf/ff, 다른 Iowa 표본과 달리 진짜 다른 녹음). `tool/prep_samples.dart`
로 22.05kHz 모노로 낮추고 5초로 잘랐다(원본은 13초 넘게 울린다).

재즈·디스코·R&B 세 장르(`epiano` voice)가 이 표본을 쓴다.
