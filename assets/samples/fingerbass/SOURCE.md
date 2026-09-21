# 핑거 베이스(일렉 베이스) 표본 출처(2026-09-19 교체)

**Karoryfer Samples — "Fashionbass"** (D. Smolken)
<https://github.com/sfzinstruments/karoryfer.fashionbass>

라이선스: **CC0 1.0 (퍼블릭 도메인)** — 크레딧 표기 의무 없음, 상업적 사용 포함
제한 없음.

예전(FreePats "Finger Bass YR") 표본은 세기 한 벌뿐이라 pp/mf/ff 세 파일이
전부 같은 녹음이었다(음량만 `VG` 표로 갈렸다). 여기서는 **진짜 pp/mf/ff
세 벌**(원본은 pp/p/mf/f/ff 다섯 벌이지만 엔진의 세기 체계가 세 단계라
pp·mf·ff만 골라 옴) 녹음을 그대로 썼다 — 다른 표본 악기들과 달리 이번엔
세기가 정말 셋 다 다르다.

자리는 원본 열아홉 군데(단3도 간격, F#0~A4) 중 rr1(라운드로빈 1번)만 골라
그대로 썼다: F#0·A0·C1·D1·F1·G#1·B1·D2·F2·G#2·B2·D3·F3·G#3·B3·D4·F4·G#4·A4.
(원본 파일명은 플랫 표기 — gb0·ab1 등 — 라 우리 쪽 관례(샵 표기)에 맞춰
Fs0·Gs1 식으로 바꿨다.)

`tool/prep_samples.dart`로 3초로 잘랐다(뜯는 소리라 3초면 자연 감쇄가 거의
끝난다 — 예전과 같은 기준). 원본은 44.1kHz 모노 IEEE float라 `afconvert`로
먼저 22.05kHz 16비트 정수로 낮췄다.
