// 설정 시트 — **앱 전체에 걸리는 몇 가지.**
//
// 곡에 딸린 값(스타일·템포·믹스)은 여기 없다. 그건 곡 화면·믹서의 몫이다.
// 여기 있는 것은 **앱을 쓰는 방식**이다: 화면이 도는가, 소리를 얼마나 무겁게
// 만드는가, 손잡이를 다 보여 주는가.
//
// 화면을 따로 만들지 않고 시트로 둔 이유: 항목이 셋뿐이다. 항목 셋짜리 화면은
// 「설정이 어디 있지」를 한 번 더 묻게 만든다.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio_isolate.dart';
import '../store.dart';

/// 저장된 값대로 화면 방향을 건다. 앱을 켤 때와 바꿀 때 부른다.
///
/// **`SystemChrome` 은 앱 전체에 걸린다** — 쇼 화면이 전체화면을 걸 듯이.
/// 여기서 한 곳으로 모아 두지 않으면 어느 화면이 마지막에 말했는지로 정해진다.
Future<void> applyOrient(String orient) {
  switch (orient) {
    case 'portrait':
      return SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    case 'landscape':
      return SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    default:
      // 빈 목록 = 잠그지 않는다(기기 설정을 따른다)
      return SystemChrome.setPreferredOrientations(const []);
  }
}

void showSettingsSheet(BuildContext context, Store store, AudioClient? host) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF16181C),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => SafeArea(
      child: AnimatedBuilder(
        animation: store,
        builder: (context, _) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '설정',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),

              // ── 화면 방향 ──
              const _Head('화면 방향', '눕혀 놓고 칠 때 화면이 제멋대로 안 돌게'),
              _Pick(
                value: store.orient,
                options: const [
                  ('auto', '자동'),
                  ('portrait', '세로 고정'),
                  ('landscape', '가로 고정'),
                ],
                onPick: (v) async {
                  await store.setOrient(v);
                  await applyOrient(v);
                },
              ),
              const SizedBox(height: 18),

              // ── 소리 품질 ──
              //
              // 엔진에는 처음부터 있었는데 **부르는 데가 없었다.** 무거운 곡에서
              // 소리가 끊기면 사용자가 할 수 있는 일이 하나도 없었다는 뜻이다.
              const _Head('소리 품질', '끊기거나 지직거리면 「가볍게」로 내려 보세요'),
              _Pick(
                value: store.highQuality ? 'high' : 'normal',
                options: const [('high', '좋게'), ('normal', '가볍게')],
                onPick: (v) async {
                  final high = v == 'high';
                  await store.setHighQuality(high);
                  host?.setQuality(high);
                },
              ),
              const SizedBox(height: 18),

              // ── 연주 흔들림 ──
              //
              // 음정·세기·**타이밍**을 매번 조금씩 다르게 한다. 여태 타이밍은
              // 안 흔들렸다 — 박이 자로 잰 듯 딱 맞으면 기계가 친 것처럼 들린다.
              const _Head('연주 흔들림', '사람이 친 것처럼 박과 세기를 조금씩 다르게'),
              _Pick(
                value: '${store.human}',
                options: const [('0', '끔'), ('1', '자연스럽게'), ('2', '많이')],
                onPick: (v) => store.setHuman(int.tryParse(v) ?? 1),
              ),
              const SizedBox(height: 18),

              // ── 프로 모드 ──
              //
              // 도수 줄은 **조에 맞는 음만** 낼 수 있다. 그 제약이 「아무거나 눌러도
              // 어울린다」를 만들어 주므로 대부분에게는 그게 낫다 — 그래서 기본은
              // 꺼짐이고, 켠 사람에게만 편집기에 반음 손잡이가 보인다(§15).
              const _Head('프로 모드', '편집기에서 반음(검은 건반)까지 찍습니다'),
              _Pick(
                value: store.pro ? 'on' : 'off',
                options: const [('off', '보통'), ('on', '프로')],
                onPick: (v) => store.setPro(v == 'on'),
              ),
              const SizedBox(height: 18),

              // ── 초보 모드(라이브 반음 건반) ──
              //
              // 라이브 화면의 반음 건반은 12음 전부를 낸다 — 도수 패드와 달리
              // 틀린 음도 낼 수 있다. 초보 모드를 켜 두면 지금 조에 안 맞는
              // 건반이 흐려지고 눌러도 소리가 안 난다(도수 패드와 같은 안전).
              const _Head('초보 모드', '라이브 반음 건반에서 틀린 음을 흐리게·소리 안 나게'),
              _Pick(
                value: store.beginner ? 'on' : 'off',
                options: const [('on', '켬'), ('off', '끔')],
                onPick: (v) => store.setBeginner(v == 'on'),
              ),
              const SizedBox(height: 18),

              // ── 카드 미리보기 ──
              //
              // 첫 화면 프로젝트 카드가 씬 구성을 작은 색 블록으로 그린다.
              // 무엇을 그릴지(씬 악기 구성 · 타임라인 구간 줄 · 쇼 무대)는
              // 카드마다가 아니라 **여기서 한 번에** 정한다.
              const _Head('카드 미리보기', '첫 화면 카드에 무엇을 작은 그림으로 그릴지'),
              _Pick(
                value: store.previewMode,
                options: const [
                  ('scene', '씬'),
                  ('timeline', '타임라인'),
                  ('show', '쇼'),
                ],
                onPick: (v) => store.setPreviewMode(v),
              ),
              const SizedBox(height: 18),

              // ── 간단히 보기 ──
              const _Head('손잡이', '「간단히」는 믹서·편집기 진입점을 감춥니다 (기능은 그대로)'),
              _Pick(
                value: store.simpleMode ? 'simple' : 'all',
                options: const [('simple', '간단히'), ('all', '전부 보기')],
                onPick: (v) => store.setSimpleMode(v == 'simple'),
              ),
              const SizedBox(height: 18),

              // ── 소리 표본 크레딧 ──
              //
              // 어쿠스틱/록 드럼 표본(MuldjordKit)과 피아노 표본(Salamander,
              // 2026-09-16 교체)이 각각 CC BY 4.0·CC BY 3.0 이라 **크레딧
              // 표기가 라이선스 조건**이다(`assets/samples/drum_kick/SOURCE.md`,
              // `assets/samples/piano/SOURCE.md`). 나머지 표본은 전부 CC0라
              // 의무는 없지만 같이 적어 둔다.
              const _Head('소리 표본 출처', ''),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  '드럼(어쿠스틱·록): MuldjordKit by Lars Muldjord '
                  '(www.muldjord.com, www.drumgizmo.org) — CC BY 4.0\n'
                  '피아노: Salamander Grand Piano by Alexander Holm '
                  '(archive.org/details/SalamanderGrandPianoV3) — CC BY 3.0\n'
                  '바이올린·트럼펫·첼로·업라이트 베이스: VSCO2 Community Edition '
                  '(github.com/sgossner/VSCO-2-CE) — CC0\n'
                  '기타·색소폰: FreePats (freepats.zenvoid.org) — CC0\n'
                  '핑거 베이스: Karoryfer Fashionbass '
                  '(github.com/sfzinstruments/karoryfer.fashionbass) — CC0\n'
                  '일렉 피아노: FreePats FM Piano 1 '
                  '(freepats.zenvoid.org) — CC0',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Head extends StatelessWidget {
  final String title, desc;
  const _Head(this.title, this.desc);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 2),
      Text(desc, style: const TextStyle(fontSize: 11.5, color: Colors.white38)),
      const SizedBox(height: 8),
    ],
  );
}

/// 몇 개 중 하나 — 칩 줄. 손가락 바닥선(세로 32)을 지킨다.
class _Pick extends StatelessWidget {
  final String value;
  final List<(String, String)> options;
  final void Function(String) onPick;
  const _Pick({
    required this.value,
    required this.options,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final (key, label) in options)
        GestureDetector(
          onTap: () => onPick(key),
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: value == key ? Colors.tealAccent.shade400 : Colors.white10,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: value == key ? FontWeight.w800 : FontWeight.w500,
                color: value == key ? Colors.black : Colors.white70,
              ),
            ),
          ),
        ),
    ],
  );
}
