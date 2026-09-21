# 피아노 표본 출처(2026-09-16 교체)

**Salamander Grand Piano V3** — Alexander Holm
<https://archive.org/details/SalamanderGrandPianoV3> ·
<https://github.com/sfzinstruments/SalamanderGrandPiano>

**CC BY 3.0 Unported** — 상업적 사용·재배포 포함 자유, 단 **크레딧 표기가
조건**이다(`settings_sheet.dart` 「소리 표본 출처」에 적어 뒀다 — 실제로는
Alexander Holm 저작, "퍼블릭도메인"이 아니라 저작자 표시 라이선스이니
혼동하지 말 것). 원본은 Yamaha C5 그랜드 피아노, 스테레오, 48kHz/24bit
FLAC, **세기 16단계** × 단3도 간격(거의 모든 음)으로 녹음.

여기서는 **단3도 간격 13자리(C2·D#2·F#2·A2·C3·D#3·F#3·A3·C4·D#4·F#4·A4·C5)
× 세기 3단계(v3=pp·v9=mf·v15=ff, 16단계 중 세 벌 골라 옴)** 를 가져왔다 —
`tool/prep_samples.dart` 로 22.05kHz 모노로 낮추고 5초로 잘라 용량을
줄였다(총 39개 파일, 8.2MB).

**예전(University of Iowa Steinway, C2·C3·C4·C5 네 자리만) 대비 개선점**:
- 자리 간격이 옥타브(반음 12개)에서 단3도(반음 3개)로 좁아져서, 어느
  건반을 눌러도 피치 시프트가 최대 반음 1.5개 안으로 줄었다(옥타브 자리는
  최대 반음 6개까지 늘여야 했다) — 늘인 만큼 음색이 원본과 멀어지는데,
  그 폭이 확 줄었다.
- 세 세기 다 **같은 최신 디지털 녹음**(University of Iowa 판은 아날로그
  시절 자료라 노이즈 바닥이 더 높다).

더 넓히려면(단3도보다 촘촘하게, 또는 세기를 16단계 다 가져오려면) 같은
저장소에서 더 받아 `tool/prep_samples.dart` 를 다시 돌리면 된다. 파일명의
`#`은 `s`로 바꿔 적었다(`F#2` → `Fs2`) — URL·파일시스템에서 `#`이 특수
문자라서다.
