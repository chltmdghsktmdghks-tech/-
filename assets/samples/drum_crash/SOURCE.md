# 드럼(어쿠스틱/록 킷) 표본 출처

**FreePats — "MuldjordKit"** (원본: Lars Muldjord, DrumGizmo용)
<https://freepats.zenvoid.org/Percussion/acoustic-drum-kit.html>
원본: <https://github.com/freepats/muldjordkit>

라이선스: **CC BY 4.0** — <http://creativecommons.org/licenses/by/4.0/>
**크레딧 표기 필요**: "MuldjordKit by Lars Muldjord (www.muldjord.com,
www.drumgizmo.org), FreePats 버전 조립: roberto@zenvoid.org" — 앱을
출시하기 전에 이 문구를 크레딧/정보 화면에 넣어야 한다(아직 그 화면이
없다 — HANDOFF.md 에 남겨 둠).

## 무엇을 가져왔나

원본은 킥·스네어·하이햇(닫힘/열림)·크래시·라이드·탐 각각 라운드로빈
9~56벌짜리 정식 멀티샘플(233MB)이다. 여기서는 조각마다 세기 3벌(pp·mf·ff
— 원본 파일 번호가 조용함→큼 순서라 낮은/중간/높은 번호를 세기로 묶었다)
×라운드로빈 1~2벌만 추려 썼다.

| 조각 | 원본 폴더 | 고른 파일 번호(세기 순) | 라운드로빈 |
|---|---|---|---|
| kick | KdrumL | 3,6 / 12,15 / 21,24 | 2 |
| snare | Snare1 | 5,10 / 25,30 / 45,50 | 2 |
| hatClosed | HihatClosed | 3,6 / 13,16 / 24,27 | 2 |
| hatOpen | HihatOpen | 4,6 / 14,17 / 25,28 | 2 |
| crash | CrashL | 1 / 4 / 8 | 1 |
| ride | RideL | 1 / 5 / 9 | 1 |
| tom | Tom2 | 2 / 7 / 12 | 1 |

**하이햇은 세기 3(열림)과 1~2(닫힘)가 다른 녹음이다** — `drums.dart` 의
`hat()` 이 원래 그렇게 나누고 있어서(`open = vel >= 3`) 표본도 그 경계를
그대로 따랐다(`hatClosed`/`hatOpen` 두 폴더).

**탐만 피치가 있다** — 곡마다 다른 음높이(`tomFreq`)로 틀어야 해서
`drum_sampler.dart` 의 `kDrumRootFreq['tom'] = 180.0` 을 기준으로 피치
시프트한다. 나머지 조각은 항상 원음 그대로 튼다.

`tool/prep_samples.dart` 로 22.05kHz 모노로 낮추고, 조각마다 다른 길이
캡을 걸었다(하이햇 닫힘 0.3초 ~ 크래시/라이드 2.5초 — `maxSecOverride`).

이 SOURCE.md 는 `drum_kick`·`drum_snare`·`drum_hatClosed`·`drum_hatOpen`·
`drum_crash`·`drum_ride`·`drum_tom` 일곱 폴더에 똑같이 들어있다.
