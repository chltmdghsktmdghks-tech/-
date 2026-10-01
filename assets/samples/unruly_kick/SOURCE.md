# 드럼(unruly 킷) 표본 출처

**Unruly Drums** — sfzinstruments/karoryfer.unruly-drums (Karoryfer Samples, Paul Battersby)
원본: <https://github.com/sfzinstruments/karoryfer.unruly-drums>
라이선스: **CC0-1.0** (퍼블릭 도메인 헌정) — 크레딧 표기 불필요, 상업 배포 가능.
받기 직전(2026-10-01) 저장소 `LICENSE` 원문("Creative Commons Legal Code / CC0 1.0 Universal")과
GitHub API 메타(spdx `CC0-1.0`)를 확인했다. 저장소 설명: 「모든 드럼에 스네어 와이어가 걸린 킷」(록/펑크 성향, 20" 킥·14" 스네어·14" 하이햇·16" 크래시·20" 라이드).

## 무엇을 가져왔나

원본은 멀티마이크 FLAC(16bit/44.1kHz, 모노 파일, 640MB). 받은 건 필요한 조각만(약 600MB 중 변환 후 **6.1MB**).
마이크를 **모노 한 벌로 섞었다**(샘플 단위 합, 마이크 간 시간차는 그대로 둠 — 오버헤드의 자연스러운 공간감):

| 폴더 | 마이크 섞기 | pp | mf | ff | 벌(rr) |
|---|---|---|---|---|---|
| unruly_kick | k20 out 0.6 + in 0.8 + oh 0.6 | clean vl3 | dirty vl5 | dirtiest vl8 | 3 |
| unruly_snare | s14 top 1.0 + btm 0.8 + ohl 0.4 + ohr 0.4 | center vl2 | center vl4 | center vl8 | 4 |
| unruly_hatClosed | h14 cl 1.0 + ohl 0.35 + ohr 0.35 | closed_tip vl4 | closed_tip vl6 | closed_tip vl7 (엔진은 안 씀) | 4 |
| unruly_hatOpen | 위와 같음 | open_tip vl5 | open_tip vl6 | open_tip vl7 | 2 |
| unruly_crash | c16 cl 1.0 + oh 0.6 | cr_bow vl2 | cr_bow vl3 | cr_bow vl5 | 2 |
| unruly_ride | r20 cl 1.0 + oh 0.6 | ride_bow vl3 | ride_bow vl5 | ride_bow vl8 | 2 |
| unruly_tom | top 1.0 + ohl 0.4 + ohr 0.4 | rr1 = s14 `tom_clean`(140Hz), rr2 = s13 `tom_clean` +4반음(≈200Hz) | vl3 | vl6 | 낮은/높은 톰 2벌 |

- 세기 층은 마이크 섞은 뒤 100ms RMS 를 재서 고름(mf ≈ ff-5dB · pp ≈ ff-10~13dB 안팎).
- 가공: 시작 무음(-44dB 아래) 잘라냄 → 길이 제한(킥 0.6s·스네어 0.7s·닫힌 햇 0.45s·열린 햇/라이드 2.2s·크래시 3.2s·톰 1.0s) → 끝 페이드 → 조각별로 ff 피크를 -3dBFS 로 정규화(층 사이 상대 레벨은 그대로).
- 톰은 원본이 「와이어를 푼 스네어」 — 이 킷엔 전용 톰이 없다. 14" 와 13" 스네어의 `tom_clean`.
- 변환: `afconvert -f WAVE -d LEI16@44100 -c 1 in.flac out.wav` 후 numpy 로 섞음(일회성, 스크립트는 저장소에 없음).
- 세트 키 `unruly`: `lib/drum_sampler.dart`. 되돌리려면 `lib/drums.dart` 의 `acoustic`/`rock` `sampleSet` 을 `'avirt'` 로.
