# 일렉 기타(클린) 표본 출처

**FreePats — "EGuitar FSBS Clean" (브리지 픽업)**
<https://freepats.zenvoid.org/ElectricGuitar/clean-electric-guitar.html>
원본: <https://github.com/freepats/electric-guitar-FSBS-clean>

라이선스: **CC0 1.0 (퍼블릭 도메인)** — 크레딧 표기 의무 없음, 상업적 사용 포함
제한 없음.

원본은 6현 각 프렛 위치별로 세기 두 벌(soft/normal)·라운드로빈 4벌까지 있는
정식 멀티샘플(총 477MB)이다. 여기서는 라운드로빈 첫 벌(`_01`)만, 세기는
soft→pp/mf, normal→ff 로 매핑해서 18개 root(C2~C#6, 반음 3~4개 간격)만
추려 썼다 — 「기본팩」(늘 앱에 들어있음)이라 용량을 아껴야 해서다.
G4 이상은 원본에 soft 벌이 없어 pp/mf/ff 가 다 같은 표본이다(바이올린·
트럼펫·첼로와 같은 이유).

`tool/prep_samples.dart` 로 22.05kHz 모노로 낮추고, **기본팩 전용으로 3초
캡**(다른 표본 악기는 5초)을 걸었다 — 뜯는 소리라 3초면 자연 감쇄가 거의
끝난다.
