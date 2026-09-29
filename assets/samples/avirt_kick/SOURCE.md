# 드럼(avirt 킷) 표본 출처

**Virtuosity Drums** — sfzinstruments/virtuosity_drums (Austin McMahon 연주, Virtuosity Musical Instruments, 보스턴)
원본: <https://github.com/sfzinstruments/virtuosity_drums>
라이선스: **CC0-1.0** (퍼블릭 도메인 헌정) — 크레딧 표기 불필요, 상업 배포 가능.
받기 직전(2026-09-29) 저장소 `LICENSE` 원문("CC0 1.0 Universal")과 GitHub 메타(spdx `CC0-1.0`)를 다시 확인했다.

## 무엇을 가져왔나

원본은 재즈 킷(스틱 연주) 6마이크 멀티샘플(1.1GB, FLAC 24bit/48kHz)이다.
**`Samples/mid/` 마이크 하나로만** 통일했다(톤 통일). 조각마다 세기 3층(pp·mf·ff)
× 2벌씩 42개만 받았다(원본 파일에서 44.1kHz 모노 16비트로 변환 후
`tool/prep_samples.dart` 로 앞 무음/뒤 길이 다듬음).

변환: `afconvert -f WAVE -d LEI16@44100 -c 1 in.flac out.raw.wav`
(**주의: `-r 44100` 은 샘플레이트가 아니라 비트레이트 옵션이라 무시된다** — `-d LEI16@44100` 이 맞다.)

세기는 원본 층의 실제 세기를 잰 값으로 골랐다(pp ≈ ff-16dB · mf ≈ ff-7dB, 피크 기준).
`drum_sampler.dart` 의 `drumSetVelGain`: 이 세트는 신스용 VG(0.3/0.6/1.0)를 또 곱하지 않는다.

| 폴더/조각 | 원본 폴더 · 파일 | pp | mf | ff | 벌 |
|---|---|---|---|---|---|
| avirt_kick | kick/`mid_kick_snon_*` (스네어 스프링 켜짐) | vl2 | vl3 | vl4 | rr1, rr2 |
| avirt_snare | snare/`mid_snare_center_*` | vl11 / vl12 | vl23 / vl24 | vl33 / vl34 | 이웃 세기 층 두 벌 |
| avirt_hatClosed | hh/`mid_hh_closed_*` | vl3 | vl4 | vl4 | rr1, rr2 (ff 는 열림으로 갈리므로 안 쓰임) |
| avirt_hatOpen | hh/`mid_hh_open_*` | vl1 | vl3 | vl4 | rr1, rr2 |
| avirt_crash | crash/`mid_crash_crash_*` | vl1 | vl2 | vl3 | rr1, rr2 |
| avirt_ride | ride/`mid_ride_ride_*` | vl2 | vl3 | vl3 | rr1, rr2 |
| avirt_tom | ltom/`mid_ltom_center_*` + htom/`mid_htom_center_*` | vl6 / vl5 | vl9 / vl9 | vl14 / vl15 | 벌1 = 낮은 톰, 벌2 = 높은 톰 (원음 그대로) |

전체 42개 파일 · 약 5.6MB. 받은 파일 이름은 `<조각>.<pp|mf|ff>.<n>.wav`.
