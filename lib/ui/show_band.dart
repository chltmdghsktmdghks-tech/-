// 쇼 화면의 **밴드** (5단계 18/N) — 무대 위에서 연주하는 사람들.
//
// 막대 그래프는 정확하지만 남에게 보여 주는 화면으로는 밋밋하다. 같은 숫자
// (`ShowScore` 의 0~1)를 사람 모양으로 바꾼다 — **누가 지금 연주하는지**가
// 한눈에 보이는 게 목적이다(악기 이름을 읽지 않아도).
//
// ── 그림은 전부 코드로 그린다 ──
// 이미지 파일을 안 쓴다. 이유가 셋이다:
//  1) **저작권** — 남의 그림이 섞일 여지가 없다. 출시가 걸려 있다.
//  2) 앱 크기 — 캐릭터 몇 십 장이면 몇 MB 다. 코드는 몇 KB.
//  3) **소리에 맞춰 움직여야 한다** — 팔 각도·몸 기울기가 매 프레임 바뀐다.
//     그림판이면 프레임마다 다른 장을 그려야 하는데, 코드는 값 하나만 바꾸면 된다.
//
// ── 어떻게 '연주'로 보이게 하나 ──
// 사람은 **박자에 맞는 움직임**을 아주 잘 알아본다. 그래서 세 가지만 지킨다:
//  · 소리가 나면 **몸이 내려앉았다 올라온다**(무릎 굽히기 — 사람은 이걸 리듬으로 읽는다)
//  · 팔이 악기 쪽으로 움직인다(건반은 위아래, 기타는 스트로크, 관악기는 몸이 젖혀진다)
//  · 소리 크기만큼 **빛난다**(어두운 무대라 빛이 곧 소리다)

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../genres.dart';

/// 무대에 세울 연주자 하나.
class BandMember {
  final String name;
  final String type; // 'bass' | 'chord' | 'melody' | 'drum'
  final Color color;

  /// 0~1, **지금 얼마나 소리가 나고 있나** — 서스테인을 포함한다.
  /// 길게 끄는 음은 그 동안 계속 높다 → **빛**에 쓴다.
  final double level;

  /// 0~1, **방금 친 정도**(서스테인 없음). 무릎 굽히기·팔 움직임처럼
  /// 타점에서만 일어나야 하는 것에 쓴다. 이걸 [level] 로 하면 패드가 4초 내내
  /// 무릎을 굽히고 있는다.
  final double hit;

  /// 사용자가 고른 **음색**. 어떤 악기를 들려 줄지는 트랙 종류가 아니라 이걸로 정한다 —
  /// 「기타」 라고 이름 짓고 나일론 기타를 골랐는데 화면에서 색소폰을 불고 있으면
  /// 그 자리에서 가짜가 된다(폰에서 확인).
  final String voice;

  /// 지금 울리는 음의 **높이**(0~1, 그 트랙 안에서). 기타리스트의 왼손이 넥 어디를
  /// 잡을지 정한다 — **음이 바뀔 때만** 바뀌므로 손이 계속 흔들리지 않는다.
  final double pitch;

  final bool muted;
  const BandMember({
    required this.name,
    required this.type,
    required this.voice,
    required this.color,
    required this.level,
    required this.hit,
    required this.muted,
    this.pitch = 0.5,
  });

  /// 무엇을 들려 줄까 — 'keys' · 'guitar' · 'horn'.
  String get instrument {
    for (final e in kBandInstrument.entries) {
      if (e.value.contains(voice)) return e.key;
    }
    // 음색을 모르면 트랙 종류로 — 예전 규칙 그대로
    return type == 'chord' ? 'keys' : (type == 'bass' ? 'guitar' : 'horn');
  }
}

/// 음색 → 화면에 들려 줄 악기. `instruments.dart` 의 `kVoiceFamily` 를 그림 기준으로
/// 다시 묶은 것이다(현악기는 활 대신 기타로, 신스는 건반으로 그린다).
const Map<String, List<String>> kBandInstrument = {
  // 건반 — 앞에 판을 놓고 **두 손으로 두드리는** 것들.
  // 마림바·벨·하프도 여기다. `kVoiceFamily` 는 이 셋을 '뜯고 치는' 으로 묶지만,
  // 그건 소리 내는 방식 기준이고 **화면은 자세 기준**이다. 마림바 연주자가
  // 기타를 메고 있으면 그 자리에서 가짜가 된다(폰에서 확인).
  'keys': [
    'piano',
    'epiano',
    'organ',
    'vintorgan',
    'lead',
    'moogleadv',
    'saw',
    'chip',
    'sine',
    'wobble',
    'stab',
    'pad',
    'analogpad',
    'marimba',
    'bell',
    'harp',
    'pluck',
    'strings',
    'jpstrings',
  ],
  // 기타류 — 몸에 **걸치고 목을 잡는** 것들(현악기·베이스 포함)
  'guitar': [
    'guitar',
    'nylon',
    'violin',
    'cello',
    'upright',
    'bass',
    'fingerbass',
    'moogbass',
  ],
  // 관악기 — **입에 대고 부는** 것들
  'horn': ['sax', 'trumpet', 'clarinet', 'flute', 'brass', 'analogbrass'],
  // 노래 — **아무것도 안 들고 마이크만 잡는다.**
  // 이게 없어서 'vocal' 이 트랙 종류('melody')로 떨어졌고, 팝·R&B·가스펠의
  // 보컬이 무대에서 **관악기를 불고 있었다.** 소리는 사람 목소리인데.
  'voice': ['vocal'],
};

/// 스타일마다 무대 조명 색이 다르다 — 로파이는 따뜻하고, 하우스는 차갑고,
/// 재즈는 술집 조명이다. 곡이 바뀌면 **화면 분위기도 같이 바뀌어야** 쇼가 된다.
/// **`kGenres` 에서 뽑아 쓴다** (계획 7-1) — 색은 거기 int 로 적혀 있다
/// (그 파일은 순수 Dart 라 `Color` 를 못 쓴다).
final Map<String, List<Color>> kStageLights = {
  for (final g in kGenres) g.key: [for (final c in g.lights) Color(c)],
};

const _kDefaultLights = [
  Color(0xFF42A5F5),
  Color(0xFFAB47BC),
  Color(0xFFFFA726),
];

/// 연주자 한 명의 생김새 — **이름에서 뽑는다.** 무작위가 아니다.
/// `paint` 는 초당 60번 불리므로 랜덤을 쓰면 매 프레임 다른 사람이 된다.
class _Persona {
  final int hair; // 0 짧은머리 · 1 긴머리 · 2 상투 · 3 캡 · 4 비니
  final int top; // 0 티셔츠 · 1 재킷 · 2 후드 · 3 민소매
  final double build; // 몸집
  final double tall; // 키
  final double stance; // 다리 벌린 정도
  final double phase; // 리듬 타는 위상 — 다 같이 움직이면 기계로 보인다
  final double lean; // 서 있는 방향
  const _Persona({
    required this.hair,
    required this.top,
    required this.build,
    required this.tall,
    required this.stance,
    required this.phase,
    required this.lean,
  });
}

class BandPainter extends CustomPainter {
  final List<BandMember> members;
  final double kick, snare, hat, crash;
  final bool playing;

  /// 무대 조명이 천천히 흔들리게 하는 값(0~1 순환). 소리와 무관한 '살아 있음'.
  final double sway;

  /// 조명 세 기둥의 색. 스타일에 따라 달라진다([kStageLights]).
  final List<Color> lights;

  /// 구간이 막 바뀐 정도(0~1). 인트로 → 벌스 → 코러스가 **화면에서도 넘어가야**
  /// 곡을 듣는 맛이 난다. 1 이면 방금 넘어간 참이다.
  final double flash;

  /// **다음 타격까지의 진행도**(0 = 방금 쳤다, 1 = 지금 친다, −1 = 쉼). (5단계 53/N)
  /// 스틱 높이는 세기가 아니라 **이 값**이 정한다 — 세기로 움직이면 박 사이에
  /// 팔이 허공에 멈춘다.
  final double snarePhase, hatPhase;

  /// 지금 구간이 얼마나 달아올랐는가 — 0(브레이크) ~ 1(드롭). (Phase 6 · 계획 8)
  /// 0.55 가 '보통'이다. 타격에 반응하는 것(kick·crash)과 달리 이건 **곡의 짜임**이라
  /// 한 구간 내내 이어진다 — 그래야 「이 대목이 큰 데구나」가 보인다.
  final double energy;

  BandPainter({
    required this.members,
    required this.kick,
    required this.snare,
    required this.hat,
    required this.crash,
    required this.playing,
    required this.sway,
    this.lights = _kDefaultLights,
    this.flash = 0,
    this.snarePhase = -1,
    this.hatPhase = -1,
    this.energy = 0.55,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final floorY = h * 0.82; // 바닥선 — 이 위에 사람들이 선다

    final front = [
      for (final m in members)
        if (m.type != 'drum') m,
    ];
    // 사람 크기는 **폭과 높이 둘 다** 본다. 예전엔 폭만 보고 1.0 에서 잘랐더니
    // 폰 세로 화면에서 사람이 작고 무대가 텅 비어 보였다(폰에서 확인).
    // 앞줄 키가 100 남짓이라 무대 높이의 1/4 쯤이 되게 잡는다.
    final slot = front.isEmpty ? w : w / front.length;
    final scale = math.min(slot / 88, h / 360).clamp(0.55, 1.9).toDouble();

    _stage(canvas, size, floorY);
    _drummer(canvas, size, floorY, scale);

    if (front.isEmpty) return;
    for (var i = 0; i < front.length; i++) {
      _player(canvas, front[i], Offset(slot * (i + 0.5), floorY), scale);
    }
  }

  /// 이름표 — 앞줄도 드러머도 같은 모양으로 붙인다.
  void _label(Canvas canvas, String text, Offset at, double s, bool muted) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: 11 * (0.8 + 0.2 * s),
          fontWeight: FontWeight.w700,
          color: muted ? Colors.white24 : Colors.white54,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 110 * s);
    tp.paint(canvas, Offset(at.dx - tp.width / 2, at.dy));
  }

  // ── 무대 ──

  void _stage(Canvas canvas, Size size, double floorY) {
    final w = size.width, h = size.height;

    // 뒷벽 — 아래로 갈수록 살짝 밝다(공간이 있어 보인다)
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF000000), Color(0xFF0B0E14)],
        ).createShader(Offset.zero & size),
    );

    // 조명 — 위에서 내려오는 빛기둥 셋. 킥에 맞춰 세지고, **구간에 따라 달아오른다.**
    //
    // 셋을 다르게 쓴다:
    //  · 밝기 — 브레이크에서 확 죽고 드롭에서 터진다(제일 눈에 걸리는 것)
    //  · 폭   — 달아오르면 빛이 넓게 퍼진다
    //  · 흔들림 — 달아오르면 더 크게 흔들린다(계획 8 의 「움직임 증가」)
    final e = energy.clamp(0.0, 1.0);
    final beat = (kick * 0.6 + crash * 0.4 + flash * 0.8).clamp(0.0, 1.0);
    final spread = 0.16 + 0.10 * e; // 0.22 가 예전 값 — 보통(0.55)에서 그대로다
    final wobble = 0.02 + 0.036 * e;
    for (var i = 0; i < 3; i++) {
      final x =
          w * (0.2 + 0.3 * i) + math.sin((sway * 2 * math.pi) + i) * w * wobble;
      final c = lights.length > i ? lights[i] : _kDefaultLights[i];
      final path = Path()
        ..moveTo(x, -h * 0.05)
        ..lineTo(x - w * spread, floorY)
        ..lineTo(x + w * spread, floorY)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              c.withValues(alpha: (0.03 + 0.11 * e) + (0.10 + 0.12 * e) * beat),
              c.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromLTRB(0, 0, w, floorY))
          ..blendMode = BlendMode.plus,
      );
    }

    // 바닥 — 선 하나와 그 아래 반사光. 선이 있어야 사람이 '서 있는' 걸로 보인다.
    canvas.drawRect(
      Rect.fromLTRB(0, floorY, w, h),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF11161F).withValues(alpha: 0.9),
            const Color(0xFF000000),
          ],
        ).createShader(Rect.fromLTRB(0, floorY, w, h)),
    );
    canvas.drawLine(
      Offset(0, floorY),
      Offset(w, floorY),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10 + 0.25 * beat)
        ..strokeWidth = 1.4,
    );

    _crowd(canvas, size, floorY);

    // 구간이 바뀌면 무대가 한 번 **환해졌다 꺼진다**. 인트로 → 벌스 → 코러스가
    // 귀로만 넘어가면 화면은 계속 같아 보인다 — 곡의 얼개가 눈에도 보여야 한다.
    if (flash > 0.01) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.10 * flash)
          ..blendMode = BlendMode.plus,
      );
    }
  }

  /// 관객 — 무대 앞 실루엣.
  ///
  /// 두 가지를 한다: 화면 아래 빈 띠를 채우고, **킥에 맞춰 들썩여서** 무대가
  /// 혼자 노는 게 아니라 '보는 사람이 있는' 곳으로 보이게 한다.
  ///
  /// ── 실루엣이 안 보였던 이유 ──
  /// 처음엔 사람을 거의 검게(0xFF05070B) 칠했는데, **그 자리 배경이 이미 새까맣다.**
  /// 검은 데에 검은 걸 그리면 아무것도 안 보인다 — 테두리만 남아서 도넛처럼 보였다.
  /// 그래서 먼저 **무대 빛이 새어 나오는 띠**를 깔고, 그 위에 사람을 앉힌다.
  /// (실루엣은 어두워서 보이는 게 아니라 **밝은 배경 앞에 있어서** 보인다.)
  ///
  /// 무작위를 안 쓴다 — 매 프레임 다시 그리므로 랜덤이면 관객이 순간이동한다.
  /// 대신 사인파로 자리를 흩는다(같은 i 는 늘 같은 자리).
  void _crowd(Canvas canvas, Size size, double floorY) {
    final w = size.width, h = size.height;
    // 앞줄 사람 **이름표 아래**에서 시작한다(이름표는 바닥선 + 12*scale 쯤에 있다).
    final bandTop = floorY + (h - floorY) * 0.30;
    if (h - bandTop < 24) return; // 자리가 없으면 그리지 않는다

    final glow = lights.isEmpty ? _kDefaultLights[0] : lights[1];
    final e = energy.clamp(0.0, 1.0);

    // 무대에서 새어 나오는 빛 — 관객보다 **뒤에** 깔린다
    canvas.drawRect(
      Rect.fromLTRB(0, bandTop - 18, w, h),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // 위쪽을 투명에서 시작한다 — 바로 밝게 하면 **가로줄 하나가 그어진 것**처럼
          // 보인다(그림으로 뽑아 보고 잡았다).
          stops: const [0.0, 0.35, 1.0],
          colors: [
            glow.withValues(alpha: 0.0),
            // 무대 앞 빛도 구간을 따라간다 — 빛기둥만 밝히면 **위쪽만 달라져서**
            // 관객 쪽은 브레이크나 드롭이나 똑같아 보인다(재 보고 알았다:
            // 전체 밝기는 1.24배인데 위쪽 절반만 1.54배였다).
            glow.withValues(alpha: (0.10 + 0.18 * e) + 0.12 * kick),
            glow.withValues(alpha: 0.02 + 0.04 * e),
          ],
        ).createShader(Rect.fromLTRB(0, bandTop - 18, w, h))
        ..blendMode = BlendMode.plus,
    );

    // 관객은 무대보다 **앞에** 있으니 커야 한다. 작게 그렸더니 자갈처럼 보였다.
    final p = Paint()..color = Colors.black;
    // 뒷줄 먼저(작고 흐릿) → 앞줄 나중(크고 진하게). 두 줄이면 '무리'로 보인다.
    for (final row in const [(11, 0.72, 0.55), (8, 1.0, 1.0)]) {
      final n = row.$1;
      final scale = row.$2;
      final r = w / 9 * 0.5 * scale;
      final top = bandTop + (1 - scale) * 16;
      p.color = Colors.black.withValues(alpha: row.$3);
      for (var i = 0; i < n; i++) {
        // 자리와 키를 사인으로 흩는다 — 줄 세우면 관객이 아니라 울타리로 보인다
        final x = w * (i + 0.5) / n + math.sin(i * 2.3 + n) * w * 0.02;
        final tall = 1.0 + math.sin(i * 1.7 + n) * 0.18;
        // 킥에 맞춰 들썩 — 사람마다 조금씩 어긋나게(다 같이 뛰면 기계 같다)
        final bob =
            kick * r * 0.45 * (0.6 + 0.4 * math.sin(i * 3.1 + sway * 6.28));
        final head = Offset(x, top + r * 1.0 * tall - bob);
        canvas.drawCircle(head, r * 0.5 * tall, p);
        // 어깨 — 머리와 겹치게 그려야 목 없이 한 덩어리로 보인다
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(x, head.dy + r * 1.15 * tall),
            width: r * 2.0 * tall,
            height: r * 2.0 * tall,
          ),
          p,
        );
      }
    }
  }

  // ── 드러머(뒤쪽 가운데) ──

  void _drummer(Canvas canvas, Size size, double floorY, double scale) {
    final w = size.width;
    final cx = w / 2;
    // 띄우는 높이는 **앞줄 키에 맞춰** 정한다. 고정 비율(0.34)로 두면 편성이 여섯이라
    // 사람이 작아졌을 때 사이가 텅 비고, 반대로 셋뿐이라 사람이 커지면 겹친다.
    //
    // 숫자의 근거: 앞줄 사람은 발끝에서 머리 꼭대기까지 약 `110 * scale`,
    // 드럼 세트는 기준점에서 아래로 약 `58 * scale` 뻗는다. 둘이 안 닿으려면
    // 최소 `168 * scale` 을 띄워야 한다 → 여유를 붙여 185.
    final y = floorY - math.max(size.height * 0.20, 185 * scale);
    final s = scale * 0.85;
    final me = members.where((m) => m.type == 'drum');
    final muted = me.isNotEmpty && me.first.muted;
    final kc = muted ? Colors.white24 : const Color(0xFF7CB342);
    final beat = muted ? 0.0 : kick;
    final sn = muted ? 0.0 : snare;
    final hh = muted ? 0.0 : hat;
    final cr = muted ? 0.0 : crash;

    // ── 세트 배치 (기준점 y 에서 상대) ──
    //
    // **오른손잡이 드러머의 실제 배치**를 따랐다(우리가 정면에서 보는 그림이므로
    // 좌우가 뒤집힌다 — 드러머의 왼쪽이 화면의 오른쪽이다):
    //   · 하이햇은 드러머 **왼쪽** → 화면 오른쪽
    //   · 스네어는 몸 바로 앞, 살짝 왼쪽 → 화면 가운데 조금 오른쪽
    //   · 라이드는 드러머 오른쪽 위 → 화면 왼쪽 위
    //   · 킥은 발 — 몸 정면 아래
    //
    // 그래서 **오른팔이 왼팔 위로 건너간다**(크로스 그립). 드럼을 배운 사람이면
    // 팔이 안 겹친 그림을 보고 바로 "저건 드럼 치는 게 아니다" 라고 안다.
    // 탐이 킥 **안**에 있으면 전부 한 덩어리로 뭉쳐 '초록 공' 이 된다
    // (그림으로 뽑아 보고 잡았다). 탐은 킥 **위에 얹고**, 스네어는 킥 옆으로 뺀다.
    // 세로 기준을 하나로 잡는다 — **단(무대) 윗면**. 킥은 여기에 '얹혀' 있어야
    // 하고 스탠드 다리도 여기까지 내려와야 한다. 예전엔 킥이 단을 뚫고 있었다.
    final deck = y + 56 * s;
    const kickRad = 27.0; // 실제로 킥은 탐보다 훨씬 크다(22인치 대 12인치)
    final kickC = Offset(cx, deck - kickRad * s);
    final kickR = kickRad * s * (1 + 0.06 * beat);
    final snareC = Offset(cx + 42 * s, y + 22 * s); // 몸 앞, 킥 오른쪽 옆
    final hatC = Offset(cx + 56 * s, y + 0 * s); // 드러머 왼쪽
    final crashC = Offset(cx + 62 * s, y - 26 * s);
    final rideC = Offset(cx - 56 * s, y - 16 * s); // 드러머 오른쪽
    // 킥 위에 얹힌 두 통 — 왼쪽이 작고(하이탐) 오른쪽이 크다(로우탐)
    // 킥 **위 테두리 위에** 얹는다. 반지름에서 계산해야 킥 크기를 바꿔도 안 파묻힌다.
    final kickTop = deck - 2 * kickRad * s;
    final tomC = [
      Offset(cx - 17 * s, kickTop - 4 * s),
      Offset(cx + 15 * s, kickTop - 6 * s),
    ];

    // ── 색을 셋으로 가른다 (5단계 50/N) ──
    // 셸·가죽·쇠붙이를 **한 색으로 칠하면 기하가 아무리 맞아도 덩어리로 보인다.**
    // 실제 드럼 세트가 눈에 확 들어오는 건 이 세 가지가 서로 다른 색이기 때문이다:
    //   · 셸(통)   — 밴드 색
    //   · 가죽(헤드) — 크림색. 북에서 제일 밝은 면이다.
    //   · 쇠붙이   — 크롬(밝은 회백)
    final head = muted
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFF2EDDF);
    Paint headPaint(double v) =>
        Paint()
          ..color = head.withValues(alpha: (0.34 + 0.5 * v).clamp(0.0, 1.0));
    final edge = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * s;
    final stand = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..strokeWidth = 1.8 * s
      ..strokeCap = StrokeCap.round;

    // 단 — 드러머가 '뒤에 높이' 있다는 걸 알려 준다
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(cx, deck + 6 * s),
          width: 230 * s,
          height: 12 * s,
        ),
        Radius.circular(4 * s),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.06 + 0.10 * beat),
    );

    // 심벌 스탠드 — 사람보다 뒤
    canvas.drawLine(crashC, Offset(crashC.dx - 6 * s, deck), stand);
    canvas.drawLine(rideC, Offset(rideC.dx + 6 * s, deck), stand);

    // ── 드러머 — **앉아 있다.** 세트보다 뒤에 그린다 ──
    //
    // 다리는 안 그린다. 앉아 있으면 하체가 킥 드럼과 스네어에 완전히 가린다 —
    // 그려 봐야 통 뒤에서 삐져나온 막대로만 보인다(사용자 지적).
    final dip = 4 * s * beat;
    final per = me.isEmpty
        ? const _Persona(
            hair: 3,
            top: 3,
            build: 1.0,
            tall: 1.0,
            stance: 8,
            phase: 0,
            lean: 0,
          )
        : _personaOf(me.first);
    final hip = Offset(cx, y + 8 * s + dip);
    final shoulder = hip.translate(0, -30 * s);

    // 몸통 + 머리
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: hip.translate(0, -15 * s),
          width: 26 * s * per.build,
          height: 30 * s,
        ),
        Radius.circular(10 * s),
      ),
      Paint()..color = kc.withValues(alpha: 0.5 + 0.4 * beat),
    );
    _head(canvas, shoulder.translate(0, -13 * s), s, kc, beat, per);

    // ── 팔 + 스틱 ── (5단계 53/N)
    //
    // 예전엔 스틱 높이를 **세기**로 정했다: 친 순간 내려오고 0.22초면 다시 올라간다.
    // 그런데 8분음표 간격은 88BPM 에서 0.34초다 — 그 사이 내내 팔이 허공에 멈춰
    // 있었다(사용자 지적: "드럼을 안 치고 팔을 어정쩡하게 들고 있어").
    //
    // 실제 스틱은 **친 자리에서 튀어 올랐다가 다음 박에 맞춰 내려온다.**
    // 그래서 다음 타격까지의 진행도(`phase`)로 높이를 정한다.
    //  · 0.00 방금 쳤다 → 헤드에 닿아 있다
    //  · 0.45 제일 높다 (리바운드 꼭대기)
    //  · 1.00 다시 헤드 → 그 순간이 다음 타격
    //  · −1   칠 게 없다 → 헤드 바로 위에서 쉰다(허공에 들지 않는다)
    double lift(double ph) {
      if (ph < 0) return 0.16; // 쉴 때도 스틱은 북 가까이
      return ph < 0.45
          ? ph / 0.45
          : math.pow(1 - (ph - 0.45) / 0.55, 1.6).toDouble();
    }

    void arm(Offset from, Offset target, double v, double phase) {
      final tip = target.translate(0, -26 * s * lift(phase));
      final hand = Offset.lerp(from, tip, 0.42)!;
      _arm(
        canvas,
        from,
        hand,
        s,
        kc,
        beat,
        bend: (tip.dx - from.dx) > 0 ? -0.28 : 0.28,
      );
      canvas.drawLine(
        hand,
        tip,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.45 + 0.45 * v)
          ..strokeWidth = 2.6 * s
          ..strokeCap = StrokeCap.round,
      );
    }

    // ── 세트 — 사람 앞에 그린다 ──
    // 탐 — 살짝 기울어 우리를 향한다. 통(옆면)과 가죽(윗면)을 갈라 그린다.
    for (var i = 0; i < tomC.length; i++) {
      final c = tomC[i];
      final tw = (i == 0 ? 28.0 : 32.0) * s; // 하이탐이 작다
      final th = tw * 0.56;
      // 통 — 가죽 아래로 살짝 보이는 옆면
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(c.dx - tw / 2, c.dy - th / 2, tw, th * 0.95 + 5 * s),
          Radius.circular(3 * s),
        ),
        Paint()..color = Colors.black.withValues(alpha: 0.42),
      );
      // 가죽 — 크림. 통(밴드 색)과 갈라져야 통이 통으로 보인다.
      canvas.drawOval(
        Rect.fromCenter(center: c, width: tw, height: th),
        headPaint(beat),
      );
      // 테 — 가죽을 눌러 잡는 링
      canvas.drawOval(
        Rect.fromCenter(center: c, width: tw, height: th),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4 * s
          ..color = kc.withValues(alpha: 0.5 + 0.4 * beat),
      );
      canvas.drawOval(Rect.fromCenter(center: c, width: tw, height: th), edge);
      // 마운트 봉 — 킥에서 올라온다
      canvas.drawLine(
        c.translate(0, th * 0.4),
        Offset(c.dx * 0.5 + cx * 0.5, y + 16 * s),
        stand,
      );
    }

    // 스네어 — 스탠드 + 통
    canvas.drawLine(snareC, Offset(snareC.dx, deck), stand);
    // 하이햇 — **접시 두 장.** 밟으면 붙고 놓으면 벌어진다.
    // 벌어진 틈이 보이는 게 하이햇을 하이햇으로 만든다(한 장이면 그냥 심벌이다).
    canvas.drawLine(hatC, Offset(hatC.dx, deck), stand);
    final gap = 6 * s * (1 - hh); // 칠 때(hh=1) 붙는다
    final cym = const Color(0xFFFFD54F);
    // 아래 접시 — 고정
    canvas.drawOval(
      Rect.fromCenter(center: hatC, width: 27 * s, height: 6 * s),
      Paint()..color = cym.withValues(alpha: 0.22 + 0.35 * hh),
    );
    // 위 접시 — 내려온다
    canvas.drawOval(
      Rect.fromCenter(
        center: hatC.translate(0, -3 * s - gap),
        width: 27 * s,
        height: 6 * s,
      ),
      Paint()..color = cym.withValues(alpha: 0.26 + 0.55 * hh),
    );
    // 클러치 봉 — 위 접시를 매단 쇠막대
    canvas.drawLine(
      hatC.translate(0, -10 * s - gap),
      hatC.translate(0, 4 * s),
      stand,
    );

    // ── 팔 + 스틱 ── **통을 다 그린 뒤**에 그린다.
    // 스틱 끝이 북 가죽 위에 보여야 '치는 중' 으로 읽힌다 — 통 뒤에 깔리면
    // 팔만 허공에 뻗은 그림이 된다(그림으로 뽑아 보고 순서를 바꿨다).
    //
    // **정면에서 보면 좌우가 뒤집힌다.** 드러머의 오른손은 화면의 **왼쪽 어깨**에서
    // 나와, 화면 오른쪽에 있는 하이햇까지 **건너간다**. 그게 크로스 그립이다.
    // (한 번 반대로 그렸다가 팔이 나란히 오른쪽만 가리켰다 — 교차가 안 보였다)
    arm(shoulder.translate(9 * s, 2 * s), snareC, sn, snarePhase); // 드러머 왼손
    // 크래시를 치는 순간에는 그쪽으로 팔이 간다 — 실제로 하이햇 손이 크래시를 친다
    final rightTarget = cr > 0.35 ? crashC : hatC;
    arm(
      shoulder.translate(-9 * s, 2 * s),
      rightTarget,
      math.max(hh, cr),
      cr > 0.35 ? 1 - cr : hatPhase,
    ); // 드러머 오른손 — 건너간다

    // ══════════════ 킥 드럼 ══════════════
    //
    // 큰 원 하나로 칠하면 그냥 **공**이다(사용자 지적). 킥으로 보이게 하는 건
    // 색이 아니라 **쇠붙이**다. 실제 베이스 드럼을 정면에서 보면 이렇게 생겼다:
    //
    //   · 후프 — 헤드를 눌러 고정하는 두꺼운 나무 테. 얇은 선이 아니라 '띠'다.
    //   · 러그 — 후프를 조이는 조임쇠. 둘레에 **여덟 개**가 고르게 박혀 있다.
    //            이게 핵심이다. 러그가 없으면 무엇을 해도 드럼으로 안 읽힌다.
    //   · 포트홀 — 앞 헤드에 뚫린 구멍(마이크 자리). 가운데가 아니라 **비켜서** 뚫는다.
    //   · 스퍼 — 앞으로 비스듬히 뻗어 바닥을 짚는 다리 두 개
    //   · 페달 — 바닥 가운데 판. 이게 있어야 '밟는 북' 이 된다.
    //
    // 그리는 순서는 뒤에서 앞으로: 통 그늘 → 헤드 → 광 → 포트홀 → 후프 → 러그 → 스퍼·페달.
    final metal = Colors.white.withValues(alpha: 0.30 + 0.30 * beat);

    // 통 그늘 — 헤드 뒤로 통이 이어진다는 표시
    canvas.drawCircle(
      kickC.translate(0, 1.5 * s),
      kickR * 1.02,
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );
    // 셸(통) — 밴드 색. 가죽보다 한 겹 바깥이다.
    canvas.drawCircle(
      kickC,
      kickR,
      Paint()..color = kc.withValues(alpha: 0.30 + 0.45 * beat),
    );
    // 앞 가죽 — **크림색.** 통과 색이 같으면 무엇을 그려도 '초록 공' 이다.
    canvas.drawCircle(kickC, kickR * 0.855, headPaint(beat));
    // 광 — 헤드는 팽팽한 막이라 위쪽에서 빛을 받는다. 가운데를 칠하면 평평해 보인다.
    canvas.drawCircle(
      kickC.translate(-kickR * 0.24, -kickR * 0.28),
      kickR * 0.44,
      Paint()..color = Colors.white.withValues(alpha: 0.10 + 0.10 * beat),
    );
    // 포트홀 — 왼쪽 아래로 비켜 뚫는다
    final port = kickC.translate(-kickR * 0.34, kickR * 0.30);
    canvas.drawCircle(
      port,
      kickR * 0.22,
      Paint()..color = Colors.black.withValues(alpha: 0.62),
    );
    canvas.drawCircle(
      port,
      kickR * 0.22,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4 * s
        ..color = Colors.white.withValues(alpha: 0.14),
    );
    // 후프 — 얇은 선이 아니라 **띠**여야 테로 보인다. 가죽 가장자리를 물고 있다.
    canvas.drawCircle(
      kickC,
      kickR * 0.905,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.0 * s
        ..color = kc.withValues(alpha: 0.55 + 0.45 * beat),
    );
    canvas.drawCircle(
      kickC,
      kickR * 0.855,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * s
        ..color = Colors.black.withValues(alpha: 0.30),
    );
    canvas.drawCircle(
      kickC,
      kickR,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * s
        ..color = Colors.black.withValues(alpha: 0.45),
    );
    // ── 러그 여덟 개 ── 후프를 물고 있는 조임쇠
    for (var i = 0; i < 8; i++) {
      final a = -math.pi / 2 + i * math.pi / 4 + math.pi / 8;
      canvas.save();
      canvas.translate(
        kickC.dx + math.cos(a) * kickR * 0.905,
        kickC.dy + math.sin(a) * kickR * 0.905,
      );
      canvas.rotate(a);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 6.2 * s, height: 3.4 * s),
          Radius.circular(1.2 * s),
        ),
        Paint()..color = metal,
      );
      canvas.restore();
    }
    // ── 스퍼(다리) 두 개 ── 앞으로 비스듬히 뻗어 바닥을 짚는다
    final spur = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = 2.4 * s
      ..strokeCap = StrokeCap.round;
    for (final d in [-1.0, 1.0]) {
      final from = kickC.translate(d * kickR * 0.86, kickR * 0.12);
      final to = Offset(kickC.dx + d * kickR * 1.34, deck);
      canvas.drawLine(from, to, spur);
      canvas.drawCircle(to, 1.8 * s, Paint()..color = metal);
    }
    // 스네어 — 얕고 넓은 통. 옆면(금속)·가죽·테를 갈라 그린다.
    // **킥보다 앞**에 그린다: 실제로도 킥 옆에 나와 있어서 가려지지 않는다.
    const sw = 34.0;
    final sh = sw * 0.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          snareC.dx - sw / 2 * s,
          snareC.dy - sh / 2 * s,
          sw * s,
          sh * s + 7 * s,
        ),
        Radius.circular(3 * s),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.13),
    );
    canvas.drawOval(
      Rect.fromCenter(center: snareC, width: sw * s, height: sh * s),
      headPaint(sn),
    );
    canvas.drawOval(
      Rect.fromCenter(center: snareC, width: sw * s, height: sh * s),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6 * s
        ..color = kc.withValues(alpha: 0.5 + 0.45 * sn),
    );
    canvas.drawOval(
      Rect.fromCenter(center: snareC, width: sw * s, height: sh * s),
      edge,
    );
    // ── 페달 ── 바닥 가운데. 밟으면 앞이 내려간다.
    final pedY = deck - 1.5 * s;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(kickC.dx - 4 * s, pedY - 2 * s * beat, 13 * s, 3 * s),
        Radius.circular(1.2 * s),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.20 + 0.25 * beat),
    );

    // 크래시 · 라이드 — 비스듬한 접시. 맞으면 기울어진다.
    void cymbal(Offset at, double v, double baseTilt, double rx) {
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(baseTilt + 0.28 * v);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: rx * s, height: 8 * s),
        Paint()
          ..color = const Color(0xFFFFD54F).withValues(alpha: 0.28 + 0.65 * v),
      );
      canvas.restore();
    }

    cymbal(crashC, cr, 0.30, 44);
    cymbal(rideC, hh * 0.5, -0.22, 40);

    // 이름표 — 단 아래
    if (me.isNotEmpty) {
      _label(canvas, me.first.name, Offset(cx, deck + 20 * s), s, muted);
    }
  }

  // ══════════════════ 연주자 ══════════════════
  //
  // ── 왜 사람마다 달라야 하나 ──
  // 같은 모양 셋이 나란히 서 있으면 **복사한 그림**으로 보인다. 밴드가 아니라
  // 아이콘 세 개다. 그렇다고 무작위로 흩으면 매 프레임 다른 사람이 된다
  // (`paint` 는 초당 60번 불린다) — 그래서 **이름에서 뽑은 씨앗**으로 정한다.
  // 같은 트랙은 언제나 같은 사람이고, 다른 트랙은 다른 사람이다.
  //
  // ── 무엇을 다르게 하나 ──
  // 키·몸집·머리 모양·옷·다리 벌린 정도·리듬 타는 위상. 여섯 가지면 충분히
  // "다른 사람들"로 보인다(사람은 실루엣 차이를 아주 잘 알아본다).

  /// 연주자 한 명의 생김새. 이름에서 뽑으므로 **늘 같다.**
  _Persona _personaOf(BandMember m) {
    var h = 0;
    for (final ch in m.name.codeUnits) {
      h = (h * 31 + ch) & 0x7fffffff;
    }
    // 트랙 종류도 섞는다 — 이름이 같아도 악기가 다르면 다른 사람이다
    for (final ch in m.type.codeUnits) {
      h = (h * 17 + ch) & 0x7fffffff;
    }
    int pick(int n) {
      h = (h * 1103515245 + 12345) & 0x7fffffff;
      return (h >> 8) % n;
    }

    return _Persona(
      hair: pick(5),
      top: pick(4),
      build: 0.88 + pick(7) * 0.05, // 0.88 ~ 1.18
      tall: 0.93 + pick(6) * 0.025, // 0.93 ~ 1.06
      stance: 7.0 + pick(6) * 1.4, // 다리 벌린 정도
      phase: pick(12) / 12.0 * 2 * math.pi, // 리듬 타는 위상
      lean: (pick(5) - 2) * 0.02, // 서 있는 방향 살짝
    );
  }

  void _player(Canvas canvas, BandMember m, Offset foot, double scale) {
    final v = m.muted ? 0.0 : m.level; // 빛(서스테인 포함)
    final h = m.muted ? 0.0 : m.hit; // 움직임(타점에서만)
    final per = _personaOf(m);
    final s = scale * per.tall;
    final c = m.muted ? Colors.white24 : m.color;

    // 몸을 좌우로 싣는다 — 소리와 무관한 '살아 있음'. 사람마다 위상이 다르다.
    final swayX = math.sin(sway * 2 * math.pi + per.phase) * 3.0 * s;

    // 그림자 — 바닥에 붙어 있어야 '서 있는' 것으로 보인다
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(foot.dx + swayX * 0.5, foot.dy + 3 * s),
        width: 54 * s,
        height: 12 * s,
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.55),
    );

    // 무릎 굽히기 — **친 순간**에만 내려앉는다(리듬으로 읽힌다).
    // 서스테인으로 하면 긴 음 내내 굽히고 있어 굳은 것처럼 보인다.
    final dip = 7 * s * h;
    final hip = Offset(foot.dx + swayX, foot.dy - 46 * s + dip);

    // 발 — 한쪽만 박자에 맞춰 든다(발장단). 사람마다 드는 쪽이 다르다.
    final tapSide = per.hair.isEven ? -1 : 1;
    final tapLift =
        3.0 * s * math.max(0.0, math.sin(sway * 4 * math.pi + per.phase));
    _leg(
      canvas,
      hip,
      Offset(foot.dx - per.stance * s, foot.dy),
      s,
      c,
      v,
      per,
      crouch: h,
      lift: tapSide < 0 ? tapLift : 0,
      side: -1,
    );
    _leg(
      canvas,
      hip,
      Offset(foot.dx + per.stance * s, foot.dy),
      s,
      c,
      v,
      per,
      crouch: h,
      lift: tapSide > 0 ? tapLift : 0,
      side: 1,
    );

    _body(
      canvas,
      hip,
      s,
      c,
      v,
      per: per,
      nod: h,
      arms: (cv, shoulder, sc) {
        // **음색**으로 정한다(트랙 종류가 아니라) — 「기타」 트랙이 색소폰을 불고 있었다
        switch (m.instrument) {
          case 'keys':
            _keys(cv, shoulder, sc, c, h, v, per, pitch: m.pitch);
          case 'voice':
            _mic(cv, shoulder, sc, c, h, v, per);
          case 'guitar':
            _guitar(
              cv,
              shoulder,
              sc,
              c,
              h,
              v,
              per,
              low: m.type == 'bass',
              pitch: m.pitch,
            );
          default:
            // 색소폰·클라리넷은 벨이 아래, 트럼펫·플루트·브라스는 앞·위
            _horn(
              cv,
              shoulder,
              sc,
              c,
              h,
              v,
              per,
              bellDown: m.voice == 'sax' || m.voice == 'clarinet',
            );
        }
      },
    );

    // 이름 — 무대 아래
    _label(canvas, m.name, Offset(foot.dx, foot.dy + 12 * s), s, m.muted);
  }

  /// 다리 하나 — **무릎이 있어야 다리로 보인다.**
  ///
  /// 예전엔 엉덩이에서 발까지 직선 하나였다. 그러면 무릎 굽히기를 해도 막대가
  /// 짧아졌다 길어질 뿐이라 '앉았다 서는' 느낌이 안 난다.
  /// 허벅지 → 무릎 → 정강이로 꺾고, 칠 때 무릎이 **앞으로** 나오게 했다.
  /// 발은 작은 타원 — 발이 없으면 다리가 바닥에 꽂힌 것처럼 보인다.
  void _leg(
    Canvas canvas,
    Offset hip,
    Offset ankle,
    double s,
    Color c,
    double v,
    _Persona per, {
    required double crouch,
    required double lift,
    required int side,
  }) {
    final ax = ankle.dx, ay = ankle.dy - lift;
    // 무릎 — 엉덩이와 발목 사이 조금 위. 굽힐수록 앞(아래쪽 화면 기준 바깥)으로 나온다.
    final knee = Offset(
      hip.dx + (ax - hip.dx) * 0.55 + side * (2 + 5 * crouch) * s,
      hip.dy + (ay - hip.dy) * 0.52,
    );

    final w = 5.2 * s * per.build;
    void stroke(Offset a, Offset b, double width, Paint paint) {
      canvas.drawLine(a, b, paint..strokeWidth = width);
    }

    final edge = Paint()
      ..color = Colors.black.withValues(alpha: 0.35)
      ..strokeCap = StrokeCap.round;
    final skin = Paint()
      ..color = c.withValues(alpha: 0.45 + 0.35 * v)
      ..strokeCap = StrokeCap.round;

    // 테두리 먼저 — 다리끼리 겹쳐도 둘로 읽힌다
    stroke(hip, knee, w + 2.0 * s, edge);
    stroke(knee, Offset(ax, ay), w + 1.4 * s, edge);
    // 허벅지가 정강이보다 굵다
    stroke(hip, knee, w, skin);
    stroke(knee, Offset(ax, ay), w * 0.8, skin);

    // 발 — 든 쪽은 앞꿈치를 들어 살짝 기울인다
    canvas.save();
    canvas.translate(ax, ay);
    if (lift > 0) canvas.rotate(-0.25 * side.toDouble());
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(side * 2.0 * s, 1.5 * s),
          width: 12 * s,
          height: 4.6 * s,
        ),
        Radius.circular(2.2 * s),
      ),
      Paint()..color = c.withValues(alpha: 0.55 + 0.3 * v),
    );
    canvas.restore();
  }

  /// 몸통 + 머리. [arms] 는 어깨 위치를 받아 악기를 그린다.
  void _body(
    Canvas canvas,
    Offset hip,
    double s,
    Color c,
    double v, {
    required _Persona per,
    required double nod,
    required void Function(Canvas, Offset, double) arms,
  }) {
    final glow = Paint()
      ..color = c.withValues(alpha: 0.5 * v)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 18 * v + 2);
    if (v > 0.05) {
      canvas.drawCircle(hip.translate(0, -22 * s), 26 * s, glow);
    }

    final bodyH = 38 * s;
    final bodyW = 26 * s * per.build;
    // 상체를 살짝 기울인다(사람마다 다른 방향) + 칠 때 앞으로 숙인다
    final tilt = per.lean + 0.05 * nod;
    final shoulder = hip.translate(
      -math.sin(tilt) * bodyH,
      -bodyH * math.cos(tilt),
    );

    canvas.save();
    canvas.translate(hip.dx, hip.dy);
    canvas.rotate(tilt);

    final bodyPaint = Paint()..color = c.withValues(alpha: 0.45 + 0.55 * v);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, -bodyH / 2),
          width: bodyW,
          height: bodyH,
        ),
        Radius.circular(11 * s),
      ),
      bodyPaint,
    );
    _top(canvas, bodyW, bodyH, s, c, v, per);
    canvas.restore();

    _head(
      canvas,
      shoulder.translate(math.sin(tilt) * -2 * s + 2 * s * nod, -14 * s),
      s,
      c,
      v,
      per,
    );

    arms(canvas, shoulder, s);
  }

  /// 옷 — 실루엣만으로 사람을 구별하게 만드는 제일 싼 방법.
  /// 몸통 좌표계(가운데 0, 위가 −) 안에서 그린다.
  void _top(
    Canvas canvas,
    double w,
    double hgt,
    double s,
    Color c,
    double v,
    _Persona per,
  ) {
    final ink = Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * s
      ..strokeCap = StrokeCap.round;
    final light = Paint()
      ..color = Colors.white.withValues(alpha: 0.14 + 0.10 * v);

    switch (per.top) {
      case 0: // 티셔츠 — 목선만
        canvas.drawArc(
          Rect.fromCenter(
            center: Offset(0, -hgt + 3 * s),
            width: w * 0.5,
            height: 7 * s,
          ),
          0,
          math.pi,
          false,
          ink,
        );
      case 1: // 재킷 — 앞섶 한 줄 + 옷깃 두 개
        canvas.drawLine(Offset(0, -hgt + 4 * s), Offset(0, -4 * s), ink);
        canvas.drawLine(
          Offset(-w * 0.18, -hgt + 2 * s),
          Offset(-w * 0.04, -hgt + 11 * s),
          ink,
        );
        canvas.drawLine(
          Offset(w * 0.18, -hgt + 2 * s),
          Offset(w * 0.04, -hgt + 11 * s),
          ink,
        );
      case 2: // 후드 — 목 뒤 후드 덩어리 + 끈 두 줄
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(0, -hgt + 1 * s),
            width: w * 0.95,
            height: 10 * s,
          ),
          light,
        );
        canvas.drawLine(
          Offset(-3 * s, -hgt + 5 * s),
          Offset(-3 * s, -hgt + 14 * s),
          ink,
        );
        canvas.drawLine(
          Offset(3 * s, -hgt + 5 * s),
          Offset(3 * s, -hgt + 14 * s),
          ink,
        );
      default: // 민소매 — 어깨 라인이 안쪽으로 파인다
        canvas.drawLine(
          Offset(-w * 0.34, -hgt + 3 * s),
          Offset(-w * 0.18, -hgt * 0.62),
          ink,
        );
        canvas.drawLine(
          Offset(w * 0.34, -hgt + 3 * s),
          Offset(w * 0.18, -hgt * 0.62),
          ink,
        );
    }
  }

  /// 머리 — 모양 다섯 가지. 실루엣이 다르면 다른 사람으로 보인다.
  void _head(
    Canvas canvas,
    Offset at,
    double s,
    Color c,
    double v,
    _Persona per,
  ) {
    final r = 11 * s;
    final skin = Paint()..color = c.withValues(alpha: 0.55 + 0.45 * v);
    final hair = Paint()..color = Colors.black.withValues(alpha: 0.35);

    switch (per.hair) {
      case 1: // 긴 머리 — 어깨까지 내려온다
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: at.translate(0, r * 0.75),
              width: r * 2.1,
              height: r * 2.6,
            ),
            Radius.circular(r * 0.8),
          ),
          hair,
        );
        canvas.drawCircle(at, r, skin);
      case 2: // 상투 — 위로 묶었다
        canvas.drawCircle(at, r, skin);
        canvas.drawCircle(at.translate(0, -r * 1.15), r * 0.42, hair);
        canvas.drawArc(
          Rect.fromCircle(center: at, radius: r),
          math.pi,
          math.pi,
          false,
          Paint()
            ..color = Colors.black.withValues(alpha: 0.30)
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.5,
        );
      case 3: // 캡 — 챙이 앞으로
        canvas.drawCircle(at, r, skin);
        canvas.drawArc(
          Rect.fromCircle(center: at, radius: r * 1.02),
          math.pi,
          math.pi,
          true,
          hair,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: at.translate(r * 0.85, -r * 0.18),
              width: r * 1.5,
              height: r * 0.42,
            ),
            Radius.circular(r * 0.2),
          ),
          hair,
        );
      case 4: // 비니 — 머리 위를 덮는다
        canvas.drawCircle(at, r, skin);
        canvas.drawArc(
          Rect.fromCircle(center: at, radius: r * 1.04),
          math.pi,
          math.pi,
          true,
          hair,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: at.translate(0, -r * 0.12),
              width: r * 2.1,
              height: r * 0.42,
            ),
            Radius.circular(r * 0.2),
          ),
          hair,
        );
      default: // 짧은 머리
        canvas.drawCircle(at, r, skin);
        canvas.drawArc(
          Rect.fromCircle(center: at, radius: r * 0.98),
          math.pi + 0.25,
          math.pi - 0.5,
          true,
          hair,
        );
    }
  }

  /// 노래하는 사람 — **마이크를 들고 선다.**
  ///
  /// 크게 부를 때 마이크를 입에 붙이고, 빈 손을 든다. 악기를 안 들었다는 것 자체가
  /// 이 사람의 표시라 손에 아무것도 더 쥐여 주지 않는다.
  void _mic(
    Canvas canvas,
    Offset shoulder,
    double s,
    Color c,
    double hit,
    double v,
    _Persona per,
  ) {
    final lean = 2.2 * s * hit;
    final head = shoulder.translate(5 * s, -13 * s - lean); // 마이크 머리(입 앞)
    final hand = shoulder.translate(13 * s, 1 * s - lean * 0.4); // 쥔 손

    // 대 — 손에서 입까지. **테두리를 먼저 깐다**(팔·관악기와 같은 이유).
    canvas.drawLine(
      hand,
      head,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.50)
        ..strokeWidth = 5.6 * s
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      hand,
      head,
      Paint()
        ..color = c.withValues(alpha: 0.55 + 0.35 * v)
        ..strokeWidth = 3.2 * s
        ..strokeCap = StrokeCap.round,
    );
    // 마이크 머리 — 둥근 그물
    canvas.drawCircle(
      head,
      5.0 * s,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    canvas.drawCircle(
      head,
      4.0 * s,
      Paint()..color = c.withValues(alpha: 0.65 + 0.35 * v),
    );
    // 소리 고리 — 지금 부르고 있다는 표시
    if (hit > 0.05) {
      canvas.drawCircle(
        head.translate(-4 * s, 0),
        (7 + 10 * hit) * s,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.22 * hit)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 * s,
      );
    }
    _arm(canvas, shoulder.translate(9 * s, 2 * s), hand, s, c, v, bend: -0.30);
    // 빈 손은 박자에 맞춰 든다
    _arm(
      canvas,
      shoulder.translate(-9 * s, 2 * s),
      shoulder.translate(-20 * s, 10 * s - 14 * s * hit),
      s,
      c,
      v,
      bend: 0.40,
    );
  }

  /// 팔 하나 — 어깨에서 손까지. 팔꿈치를 살짝 꺾어야 막대가 아니라 팔로 보인다.
  void _arm(
    Canvas canvas,
    Offset shoulder,
    Offset hand,
    double s,
    Color c,
    double v, {
    double bend = 0.35,
  }) {
    final mid = Offset(
      (shoulder.dx + hand.dx) / 2,
      (shoulder.dy + hand.dy) / 2,
    );
    final dx = hand.dx - shoulder.dx, dy = hand.dy - shoulder.dy;
    // 팔꿈치는 진행 방향의 **바깥쪽**으로 밀어 둔다
    final elbow = mid.translate(-dy * bend * 0.5, dx * bend * 0.5);
    final path = Path()
      ..moveTo(shoulder.dx, shoulder.dy)
      ..quadraticBezierTo(elbow.dx, elbow.dy, hand.dx, hand.dy);
    // **테두리를 먼저 깐다.** 팔이 몸통과 같은 색이라, 안 그으면 몸에 묻혀
    // 아예 안 보인다(그림으로 뽑아 보고 잡았다 — 건반 연주자는 팔이 없어 보였다).
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.2 * s
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = c.withValues(alpha: 0.75 + 0.25 * v)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0 * s
        ..strokeCap = StrokeCap.round,
    );
    // 손
    canvas.drawCircle(
      hand,
      3.0 * s,
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    canvas.drawCircle(
      hand,
      2.2 * s,
      Paint()..color = c.withValues(alpha: 0.85 + 0.15 * v),
    );
  }

  /// 건반 — **두 손이 번갈아** 내려간다. 같이 움직이면 인형처럼 보인다.
  void _keys(
    Canvas canvas,
    Offset shoulder,
    double s,
    Color c,
    double hit,
    double v,
    _Persona per, {
    double pitch = 0.5,
  }) {
    // 건반을 **허리 높이까지 내리고 넓힌다.** 가슴 높이에 두면 팔이 짧아서
    // 몸통 뒤에 숨는다 — 연주하는 것으로 안 보인다(그림으로 뽑아 보고 잡았다).
    final board = Rect.fromCenter(
      center: shoulder.translate(0, 34 * s),
      width: 64 * s,
      height: 8 * s,
    );
    // 건반 — 흰 판 위에 검은 건반 몇 개
    final boardR = RRect.fromRectAndRadius(board, Radius.circular(2 * s));
    canvas.drawRRect(
      boardR,
      Paint()..color = Colors.white.withValues(alpha: 0.30 + 0.5 * v),
    );
    canvas.drawRRect(
      boardR,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * s,
    );
    // ── 건반 무늬 ── (5단계 50/N)
    // 검은 건반을 **고르게** 박으면 건반이 아니라 줄무늬다. 실제 건반은
    // **두 개 · 세 개**가 번갈아 묶여 있고, 그 묶음이 있어야 피아노로 읽힌다.
    const nWhite = 14; // 두 옥타브
    final wKey = board.width / nWhite;
    final line = Paint()
      ..color = Colors.black.withValues(alpha: 0.28)
      ..strokeWidth = 0.9 * s;
    for (var i = 1; i < nWhite; i++) {
      final x = board.left + wKey * i;
      canvas.drawLine(
        Offset(x, board.top + 1 * s),
        Offset(x, board.bottom),
        line,
      );
    }
    final blk = Paint()..color = Colors.black.withValues(alpha: 0.72);
    // 한 옥타브 안에서 검은 건반은 흰 건반 1·2 사이, 그리고 4·5·6 사이에 온다
    const gaps = [1, 2, 4, 5, 6];
    for (var oct = 0; oct < 2; oct++) {
      for (final g in gaps) {
        final x = board.left + wKey * (oct * 7 + g);
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(x, board.top + 2.6 * s),
            width: wKey * 0.55,
            height: 5.2 * s,
          ),
          blk,
        );
      }
    }
    // 스탠드 — X 다리. 한 줄이면 막대에 얹은 것처럼 보인다.
    final leg = Paint()
      ..color = Colors.white.withValues(alpha: 0.14)
      ..strokeWidth = 2 * s
      ..strokeCap = StrokeCap.round;
    for (final d in [-1.0, 1.0]) {
      canvas.drawLine(
        Offset(board.center.dx - d * 9 * s, board.bottom),
        Offset(board.center.dx + d * 11 * s, board.bottom + 15 * s),
        leg,
      );
    }

    // 실제 건반 연주: **어깨는 거의 안 움직이고 손이 좌우로 옮겨 다닌다.**
    // 높은 음일수록 오른쪽이다. 두 손은 한 옥타브쯤 벌리고 같이 움직인다.
    final span = board.width * 0.30;
    final centerX = board.center.dx + (pitch - 0.5) * span * 2;
    // 왼손·오른손이 **엇갈려** 내려간다(위상 반대) — 같이 누르면 인형처럼 보인다
    final wob = math.sin(sway * 6 * math.pi + per.phase);
    final lDrop = (0.5 + 0.5 * wob) * 5 * s * (0.4 + 0.6 * hit);
    final rDrop = (0.5 - 0.5 * wob) * 5 * s * (0.4 + 0.6 * hit);
    final lx = (centerX - 13 * s).clamp(
      board.left + 6 * s,
      board.right - 6 * s,
    );
    final rx = (centerX + 13 * s).clamp(
      board.left + 6 * s,
      board.right - 6 * s,
    );
    _arm(
      canvas,
      shoulder.translate(-9 * s, 2 * s),
      Offset(lx, board.top - 1 * s + lDrop),
      s,
      c,
      v,
      bend: 0.45,
    );
    _arm(
      canvas,
      shoulder.translate(9 * s, 2 * s),
      Offset(rx, board.top - 1 * s + rDrop),
      s,
      c,
      v,
      bend: -0.45,
    );
  }

  /// 기타 몸통 윤곽 — **허리가 있어야 기타로 읽힌다** (5단계 50/N).
  ///
  /// 둥근 네모로 그리면 그냥 판때기다. 실루엣만으로 악기를 알아보게 하는 건
  /// 색도 무늬도 아니고 **허리 잘록한 선 하나**다.
  /// 위·아래 두 덩이(볼)를 겹치고 사이를 좁힌다. +x 가 넥 쪽.
  /// [bass] 는 몸통이 조금 작고 각지다(실제 베이스가 그렇다 — 넥이 길어서
  /// 균형상 몸통을 키우지 않는다).
  Path _guitarBody(double s, {required bool bass}) {
    final lo = bass ? 11.5 : 12.5; // 아래볼
    final up = bass ? 9.0 : 10.0; // 위볼 — 아래보다 작다
    final wa = bass ? 6.2 : 6.8; // 허리
    const xe = -18.0, xn = 18.0; // 엔드핀 ↔ 넥 붙는 곳
    return Path()
      ..moveTo(xe * s, 0)
      // 위쪽 윤곽
      ..cubicTo(
        xe * s,
        -lo * s,
        -13 * s,
        -lo * 1.08 * s,
        -6 * s,
        -lo * 0.92 * s,
      )
      ..cubicTo(-1.5 * s, -lo * 0.74 * s, 0.5 * s, -wa * s, 3.5 * s, -wa * s)
      ..cubicTo(7 * s, -wa * s, 11 * s, -up * 1.08 * s, 15 * s, -up * 0.84 * s)
      ..cubicTo(17.5 * s, -up * 0.66 * s, xn * s, -3.2 * s, xn * s, 0)
      // 아래쪽 — 위와 대칭
      ..cubicTo(xn * s, 3.2 * s, 17.5 * s, up * 0.66 * s, 15 * s, up * 0.84 * s)
      ..cubicTo(11 * s, up * 1.08 * s, 7 * s, wa * s, 3.5 * s, wa * s)
      ..cubicTo(0.5 * s, wa * s, -1.5 * s, lo * 0.74 * s, -6 * s, lo * 0.92 * s)
      ..cubicTo(-13 * s, lo * 1.08 * s, xe * s, lo * s, xe * s, 0)
      ..close();
  }

  /// 기타/베이스 — 몸통·목·헤드까지 그리고, **왼손이 넥 위를 오르내린다.**
  void _guitar(
    Canvas canvas,
    Offset shoulder,
    double s,
    Color c,
    double hit,
    double v,
    _Persona per, {
    bool low = false,
    double pitch = 0.5,
  }) {
    // 넥은 **위로·오른쪽으로** 뻗는다(연주자가 우리를 보고 서 있을 때의 모습).
    // 예전엔 아래로 뻗어서 팔에 덮여 아예 안 보였다.
    final ang = low ? -0.34 : -0.28;
    final origin = shoulder.translate(-9 * s, 24 * s); // 몸통보다 아래·왼쪽
    final edge = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * s;
    // 베이스는 넥이 길다 — 실제로 스케일이 34인치 대 25.5인치다.
    // 이 비율이 기타와 베이스를 **한눈에** 가르는 두 번째 단서다(첫째는 몸통 크기).
    final neckLen = low ? 54.0 : 46.0;
    final neckX = 15.0 + neckLen / 2;
    final headX = neckX + neckLen / 2 + (low ? 7.5 : 6.0);

    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.rotate(ang);

    // ── 몸통 ──
    final body = _guitarBody(s, bass: low);
    canvas.drawPath(
      body,
      Paint()..color = c.withValues(alpha: 0.65 + 0.35 * v),
    );
    canvas.drawPath(body, edge);

    // 사운드홀(기타) / 픽업 두 개(베이스) — 여기서 둘의 성격이 갈린다
    if (low) {
      for (final px in [-2.0, 6.0]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(px * s, 0),
              width: 4 * s,
              height: 13 * s,
            ),
            Radius.circular(1.2 * s),
          ),
          Paint()..color = Colors.black.withValues(alpha: 0.42),
        );
      }
    } else {
      canvas.drawCircle(
        Offset(4 * s, 0),
        4.6 * s,
        Paint()..color = Colors.black.withValues(alpha: 0.5),
      );
    }
    // 브리지 — 줄이 시작되는 곳
    canvas.drawRect(
      Rect.fromCenter(center: Offset(-8 * s, 0), width: 3 * s, height: 9 * s),
      Paint()..color = Colors.black.withValues(alpha: 0.38),
    );

    // ── 목 ──
    final neck = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(neckX * s, -1 * s),
        width: neckLen * s,
        height: (low ? 6.2 : 5.5) * s,
      ),
      Radius.circular(2 * s),
    );
    canvas.drawRRect(
      neck,
      Paint()..color = c.withValues(alpha: 0.55 + 0.4 * v),
    );
    canvas.drawRRect(neck, edge);

    // 프렛 — 짧은 눈금 몇 개. 있으면 '목'이 아니라 '지판'으로 읽힌다.
    final fretPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.30)
      ..strokeWidth = 1.2 * s;
    for (var i = 1; i <= 5; i++) {
      final fx = (15 + neckLen * i / 6) * s;
      canvas.drawLine(Offset(fx, -3.6 * s), Offset(fx, 1.6 * s), fretPaint);
    }
    // 포지션 마크 — 실제 기타에 있는 점(3·5·7프렛)
    for (var i = 2; i <= 4; i += 2) {
      canvas.drawCircle(
        Offset((15 + neckLen * i / 6) * s, -1 * s),
        0.9 * s,
        Paint()..color = Colors.white.withValues(alpha: 0.28),
      );
    }

    // ── 줄 ── 브리지에서 헤드까지. 기타 6줄 · 베이스 4줄(굵다).
    final nStr = low ? 4 : 6;
    final strPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.30 + 0.25 * v)
      ..strokeWidth = (low ? 0.9 : 0.6) * s;
    for (var i = 0; i < nStr; i++) {
      final off = (i - (nStr - 1) / 2) * (low ? 1.5 : 0.95) * s;
      canvas.drawLine(
        Offset(-8 * s, off * 1.6),
        Offset(headX * s, off - 1 * s),
        strPaint,
      );
    }

    // ── 헤드 ── 여기까지 그려야 '기타'로 읽힌다
    final headW = low ? 13.0 : 11.0;
    final head = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(headX * s, -1 * s),
        width: headW * s,
        height: (low ? 9.0 : 10.0) * s,
      ),
      Radius.circular(2.5 * s),
    );
    canvas.drawRRect(head, Paint()..color = c.withValues(alpha: 0.6 + 0.4 * v));
    canvas.drawRRect(head, edge);
    // 튜너 — 기타는 양쪽 3개씩, 베이스는 한쪽에 4개(실제 배치가 그렇다)
    final peg = Paint()..color = Colors.black.withValues(alpha: 0.40);
    if (low) {
      for (var i = 0; i < 4; i++) {
        canvas.drawCircle(
          Offset((headX - 4 + i * 2.7) * s, -6.5 * s),
          1.3 * s,
          peg,
        );
      }
    } else {
      for (var i = 0; i < 3; i++) {
        canvas.drawCircle(
          Offset((headX - 3 + i * 3.0) * s, -6.5 * s),
          1.2 * s,
          peg,
        );
        canvas.drawCircle(
          Offset((headX - 3 + i * 3.0) * s, 4.5 * s),
          1.2 * s,
          peg,
        );
      }
    }
    canvas.restore();

    // 넥 위의 왼손 — **음 높이가 자리를 정한다.** 높은 음일수록 헤드 쪽으로 올라간다.
    // 예전엔 사인파로 계속 흔들었는데, 그건 연주가 아니라 떨림이다
    // (사용자 지적: "손을 계속 움직이는 게 아니라 음이 나오는 순간에 움직여야").
    // `pitch` 는 음이 바뀔 때만 바뀌므로 손도 그때만 옮겨진다.
    final fret = 26 + (neckLen * 0.65) * pitch;
    final fretHand = Offset(
      origin.dx + fret * s * math.cos(ang),
      origin.dy + fret * s * math.sin(ang) - 3 * s,
    );
    _arm(
      canvas,
      shoulder.translate(10 * s, 3 * s),
      fretHand,
      s,
      c,
      v,
      bend: -0.3,
    );

    // 스트로크 하는 오른손 — 울릴 때 몸통 위를 아래로 훑는다.
    // 베이스는 스트로크가 아니라 **손가락으로 뜯는다** — 폭이 훨씬 작다.
    final reach = low ? 7.0 : 16.0;
    final strum = Offset(origin.dx + 2 * s, origin.dy - (10 - reach * hit) * s);
    _arm(
      canvas,
      shoulder.translate(-10 * s, 2 * s),
      strum,
      s,
      c,
      v,
      bend: 0.28,
    );
  }

  /// 관악기 — 색소폰과 트럼펫은 **생김새가 아예 다르다** (5단계 50/N).
  ///
  /// 예전엔 둘 다 '삼각형 + 동그라미' 였다. 각도만 달랐으니 색소폰인지
  /// 트럼펫인지 알 수가 없었다(그림으로 뽑아 보고 갈랐다).
  ///   · 색소폰 — 몸 앞에 매달린 **구부러진 관**. 아래에서 U 로 꺾여 벨이 앞을 본다.
  ///   · 트럼펫 — **곧은 관** + 밸브 세 개 + 나팔. 어깨 높이로 든다.
  void _horn(
    Canvas canvas,
    Offset shoulder,
    double s,
    Color c,
    double hit,
    double v,
    _Persona per, {
    bool bellDown = false,
  }) {
    final edge = Paint()
      ..color = Colors.black.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0 * s;
    final brass = c.withValues(alpha: 0.72 + 0.28 * v);
    final tube = Paint()
      ..color = brass
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.2 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // **관에 테두리를 두른다.** 악기와 연주자가 같은 색이라, 테가 없으면 관이
    // 몸통에 그대로 묻힌다(팔에 테두리를 두른 것과 같은 이유다).
    final tubeEdge = Paint()
      ..color = Colors.black.withValues(alpha: 0.42)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7.8 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final btn = Paint()..color = Colors.black.withValues(alpha: 0.40);

    if (bellDown) {
      // ══ 색소폰 ══ 큰 소리를 낼 때 잠깐 위로 들어 올린다.
      final ang = 0.16 - 0.20 * hit;
      // 몸 정면에 붙이면 몸통에 겹쳐 안 보인다 — 실제로도 오른쪽 앞에 매단다
      final origin = shoulder.translate(10 * s, 4 * s);
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      canvas.rotate(ang);
      // 목 — 마우스피스에서 몸통으로 굽어 내려온다
      // **몸통이 허리 아래까지 내려가야** 색소폰으로 보인다. 짧게 그리면
      // 어디에 매달렸는지 안 보여서 작은 트럼펫처럼 읽힌다.
      final path = Path()
        ..moveTo(-2 * s, -6 * s)
        ..quadraticBezierTo(5 * s, -4 * s, 7 * s, 5 * s)
        ..lineTo(11 * s, 32 * s)
        ..quadraticBezierTo(13 * s, 43 * s, 24 * s, 41 * s) // 아래 U 굽이
        ..lineTo(30 * s, 31 * s);
      canvas.drawPath(path, tubeEdge);
      canvas.drawPath(path, tube);
      // 벨 — 관 끝에서 **위앞으로 점점 굵어지다** 나팔로 벌어진다.
      // 사각형으로 그렸더니 손에 쥔 상자로 보였다(그림으로 뽑아 보고 고쳤다).
      // 굵기를 키운 선분을 잇는 쪽이 다각형보다 훨씬 안정적으로 '나팔'이 된다.
      void flare(Offset a, Offset b, double w) => canvas.drawLine(
        a,
        b,
        Paint()
          ..color = brass
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * s
          ..strokeCap = StrokeCap.round,
      );
      flare(Offset(30 * s, 31 * s), Offset(34 * s, 24 * s), 7);
      flare(Offset(34 * s, 24 * s), Offset(37 * s, 18 * s), 11);
      canvas.drawCircle(Offset(39 * s, 14 * s), 9 * s, Paint()..color = brass);
      canvas.drawCircle(Offset(39 * s, 14 * s), 9 * s, edge);
      // 나팔 안쪽 — 뚫린 곳이라 어둡다
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(40.5 * s, 13 * s),
          width: 9 * s,
          height: 13 * s,
        ),
        Paint()..color = Colors.black.withValues(alpha: 0.35),
      );
      // 마우스피스 — 입에 닿는 검은 부분
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(-4 * s, -7 * s),
            width: 7 * s,
            height: 4 * s,
          ),
          Radius.circular(1.5 * s),
        ),
        btn,
      );
      // 키(버튼) — 관을 따라. 색소폰을 색소폰으로 만드는 자잘한 쇠붙이.
      for (var i = 0; i < 6; i++) {
        canvas.drawCircle(
          Offset((7.8 + i * 0.7) * s, (7 + i * 4.6) * s),
          1.7 * s,
          Paint()..color = Colors.white.withValues(alpha: 0.32),
        );
      }
      canvas.restore();
      // 두 손 — 관 앞뒤를 잡는다
      Offset on(double dx, double dy) => Offset(
        origin.dx + (dx * math.cos(ang) - dy * math.sin(ang)) * s,
        origin.dy + (dx * math.sin(ang) + dy * math.cos(ang)) * s,
      );
      _arm(
        canvas,
        shoulder.translate(-8 * s, 3 * s),
        on(7, 12),
        s,
        c,
        v,
        bend: 0.34,
      );
      _arm(
        canvas,
        shoulder.translate(8 * s, 3 * s),
        on(11, 30),
        s,
        c,
        v,
        bend: -0.28,
      );
      return;
    }

    // ══ 트럼펫 ══ 어깨 높이로 곧게 든다. 큰 음에서 더 들어 올린다.
    final ang = -0.20 - 0.22 * hit;
    final origin = shoulder.translate(5 * s, -3 * s);
    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.rotate(ang);
    // 곧은 관
    canvas.drawLine(Offset(0, 0), Offset(26 * s, 0), tubeEdge);
    canvas.drawLine(Offset(0, 0), Offset(26 * s, 0), tube);
    // 밸브 세 개 — 위로 솟은 원통. 트럼펫의 표식이다.
    for (var i = 0; i < 3; i++) {
      final vx = (9 + i * 4.6) * s;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(vx - 1.6 * s, -8.5 * s, 3.2 * s, 8 * s),
          Radius.circular(1.2 * s),
        ),
        Paint()..color = brass,
      );
      canvas.drawCircle(
        Offset(vx, -9 * s),
        1.7 * s,
        Paint()..color = Colors.white.withValues(alpha: 0.30),
      );
    }
    // 나팔 — 끝에서 확 벌어진다(색소폰과 같은 방식으로 굵기를 키운다)
    void flare(Offset a, Offset b, double w) => canvas.drawLine(
      a,
      b,
      Paint()
        ..color = brass
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * s
        ..strokeCap = StrokeCap.round,
    );
    flare(Offset(26 * s, 0), Offset(30 * s, 0), 8);
    flare(Offset(30 * s, 0), Offset(34 * s, 0), 13);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(36 * s, 0), width: 7 * s, height: 19 * s),
      Paint()..color = brass,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(36 * s, 0), width: 7 * s, height: 19 * s),
      edge,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(37 * s, 0), width: 4 * s, height: 13 * s),
      Paint()..color = Colors.black.withValues(alpha: 0.35),
    );
    // 마우스피스
    canvas.drawCircle(Offset(-1 * s, 0), 2.6 * s, btn);
    canvas.restore();

    Offset on(double dx, double dy) => Offset(
      origin.dx + (dx * math.cos(ang) - dy * math.sin(ang)) * s,
      origin.dy + (dx * math.sin(ang) + dy * math.cos(ang)) * s,
    );
    _arm(
      canvas,
      shoulder.translate(-8 * s, 2 * s),
      on(6, 2),
      s,
      c,
      v,
      bend: 0.30,
    );
    _arm(
      canvas,
      shoulder.translate(8 * s, 2 * s),
      on(16, 3),
      s,
      c,
      v,
      bend: -0.26,
    );
  }

  @override
  bool shouldRepaint(covariant BandPainter old) => true; // 매 프레임 값이 바뀐다
}
