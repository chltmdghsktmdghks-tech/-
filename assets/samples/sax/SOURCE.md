# 색소폰 표본 출처(2026-09-16 교체)

**FreePats "Tenor Saxophone"** — Versilian Community Sample Library
(Versilian Studios LLC) 표본을 roberto@zenvoid.org 가 SFZ로 엮음.
<https://freepats.zenvoid.org/Reed/saxophone.html>

**CC0(퍼블릭도메인)** — 상업적 사용 포함 제한 없음, 저작권료·크레딧
표기 의무 없음.

예전(University of Iowa, 알토 색소폰) 표본은 비브라토 세기 한 벌(ff)뿐
이라 pp·mf·ff 세 파일이 전부 같은 녹음이었다. 여기서는 v2(여리게)·
v3(세게) 두 벌 녹음이 있는 자리 5곳(C3·C4·E3·G#2·G#3)은 실제로
pp·mf=v2, ff=v3로 나눴다. 나머지 8곳(C5·C6·E2·E4·E5·E6·G#4·G#5)은
v3 한 벌뿐이라 예전처럼 세 파일이 같다. 자리도 9군데(단3도 간격,
Db3~Db5)에서 13군데(장3도 간격, E2~E6)로 넓혔다.

**테너 색소폰**이라 예전 알토보다 낮은 음역 표본이지만, `sampler.dart`
는 어차피 가장 가까운 자리를 피치 시프트해서 쓰므로 실제 사용(재즈·
팝 서브 멜로디)에는 문제없다.

가져온 음: E2·G#2·C3·E3·G#3·C4·E4·G#4·C5·E5·G#5·C6·E6.

`tool/prep_samples.dart` 로 22.05kHz 모노로 낮추고 5초로 잘라(afconvert
로 먼저 22.05kHz 변환) 용량을 줄였다.
