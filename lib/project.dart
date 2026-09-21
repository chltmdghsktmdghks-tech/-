// 프로젝트 상태 — 웹 `P`(app.html 2973줄~) 와 `mkTrack()` 을 옮긴 것.
// 화면 여섯 개(씬·타임라인·라이브·쇼·믹서·편집기)가 전부 여기서 그려진다.
//
// ── 설계에서 가장 중요한 것: 무엇이 무엇을 다시 그리게 하는가 ──
// 시험 화면(main.dart)에서 이미 값을 치렀다. 슬라이더 하나를 움직일 때마다
// `setState` 로 **화면 전체**를 다시 그렸더니 20밴드 EQ 조작이 눈에 띄게 느려졌다
// (악기 칩 33개 + 버튼 수십 개 + 건반 26키를 초당 60번 다시 그린 셈).
// 타임라인·믹서는 위젯이 그보다 훨씬 많으므로 같은 식으로 짜면 그대로 터진다.
//
// 그래서 **트랙 하나하나가 각자 ChangeNotifier** 다:
//   - 채널 스트립의 볼륨을 만지면 → 그 트랙만 다시 그린다
//   - 트랙을 추가/삭제하면 → [Project] 가 알린다(목록 구조가 바뀔 때만)
// 화면은 트랙 목록을 `Project` 로, 각 스트립 안쪽을 `Track` 으로 구독한다.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;

import 'fx.dart' show FxPresetDef, kFxCatalog;
import 'genres.dart' show genreDef;
import 'instrument_tone.dart';
import 'instruments.dart';
import 'feel.dart';
import 'patterns.dart';
import 'presets.dart';
import 'prog_ops.dart';
import 'genre_fx.dart';
import 'meter.dart';
import 'genre_mix.dart';
import 'song.dart';

/// 트랙 타입 — 어느 패턴 표를 쓰고 어떤 빌더를 타는지 정한다(song.dart 와 같은 뜻).
const List<String> kTrackTypes = ['drum', 'bass', 'chord', 'melody'];

/// 화면에 보일 타입 이름.
/// 화면에 보일 타입 이름 — **악기가 하는 일**을 말한다.
///
/// 「코드」·「멜로디」는 만드는 사람의 말이지 **치는 사람의 말이 아니다.**
/// 악보를 모르는 사람에게 「코드 트랙을 하나 더하세요」는 아무 뜻이 없다.
/// 무엇을 넣을지는 [kInstrumentPicks] 가 **악기 이름**으로 보여 주고,
/// 여기는 그 악기가 곡에서 하는 일만 한 마디로 적는다.
const Map<String, String> kTrackTypeLabel = {
  'drum': '드럼',
  'bass': '베이스',
  'chord': '화음',
  'melody': '가락',
};

/// 트랙 종류 아이콘 — 씬/믹서 화면의 트랙 줄에 라벨만으론 훑어보기
/// 어렵다(사용자 요청, 2026-09-16: "트랙 등등 아이콘표기하는게 나은거는
/// 아이콘 표기하자"). `home_view.dart` 프로젝트 카드 미리보기와 같은
/// 매핑(드럼=앨범·베이스=그래픽이퀄라이저·화음=피아노·가락=음표).
const Map<String, IconData> kTrackTypeIcon = {
  'drum': Icons.album,
  'bass': Icons.graphic_eq,
  'chord': Icons.piano,
  'melody': Icons.music_note,
};

/// 「악기 추가」에 내놓는 악기들 — (음색, 보이는 이름, 트랙 종류).
///
/// 여태는 **종류 넷**(드럼·베이스·코드·멜로디)을 먼저 고르게 했다. 그건 이 앱의
/// 속사정이지 사람이 아는 말이 아니다 — 기타를 넣고 싶은 사람은 「코드인가
/// 멜로디인가」부터 답해야 했다. 여기서는 **악기를 고르면 종류가 따라온다.**
///
/// 서른네 음색을 다 내놓지 않는다(§15 — 있다고 다 내놓지 않는다). 여기 없는
/// 음색은 트랙을 만든 뒤 「음색」 칸에서 얼마든지 고를 수 있다.
const List<(String, String, String)> kInstrumentPicks = [
  ('', '드럼', 'drum'),
  ('bass', '신스 베이스', 'bass'),
  ('fingerbass', '핑거 베이스', 'bass'),
  ('upright', '업라이트 베이스', 'bass'),
  ('piano', '피아노', 'chord'),
  ('epiano', '일렉 피아노', 'chord'),
  ('guitar', '기타', 'chord'),
  ('nylon', '나일론 기타', 'chord'),
  ('organ', '오르간', 'chord'),
  ('pad', '패드', 'chord'),
  ('strings', '스트링', 'chord'),
  ('lead', '리드 신스', 'melody'),
  ('bell', '벨', 'melody'),
  ('marimba', '마림바', 'melody'),
  ('flute', '플루트', 'melody'),
  ('sax', '색소폰', 'melody'),
  ('trumpet', '트럼펫', 'melody'),
  ('violin', '바이올린', 'melody'),
  ('vocal', '보컬', 'melody'),
  ('chip', '칩튠', 'melody'),
];

/// 타입별 기본 음색 — 웹 `TYPE_VOICE`.
const Map<String, String> kTypeVoice = {
  'drum': 'drum',
  'bass': 'bass',
  'chord': 'pad',
  'melody': 'lead',
};

/// **스타일이 정해 주는 기본 음색** — 타입별 기본값([kTypeVoice])을 덮는다.
///
/// 록의 화음은 패드가 아니라 **리듬 기타**다. 스타일 설명에도 「기타가 앞에」라고
/// 적혀 있고 화음 판 이름도 `Rock Power` 인데, 정작 소리는 패드가 내고 있었다.
/// 기타가 화음을 맡으면 [genreChordType] 이 **파워코드**로 친다.
///
/// 사용자가 음색을 고른 뒤에는 안 건드린다([_voiceIsAuto]).
const Map<String, Map<String, String>> kGenreTypeVoice = {
  // 록은 **기타 두 대**다 — 화음을 긁는 리듬 기타와 가락을 켜는 리드 기타.
  // 가락이 신스 리드로 나면 그 순간 록이 아니라 신스팝이 된다.
  // 베이스도 마찬가지다 — 기타를 든 밴드인데 베이스만 신스 톱니파(`bass`)면
  // 안 어울린다. 표본화된 핑거 베이스(`fingerbass`)로 맞춘다(2026-09,
  // "밴드가 안 좋게 들린다"는 지적으로 찾았다 — pop·gospel 은 이미 이걸
  // 쓰고 있었는데 록만 빠져 있었다).
  'rock': {'chord': 'guitar', 'melody': 'guitar', 'bass': 'fingerbass'},
};

/// 지금 음색이 **아직 아무도 안 고른 것**인가 — 타입 기본값이거나 어느 스타일의
/// 기본값이면 그렇다. 사용자가 고른 음색은 스타일을 바꿔도 그대로 둔다.
bool _voiceIsAuto(Track t) {
  if (t.voice == kTypeVoice[t.type]) return true;
  for (final m in kGenreTypeVoice.values) {
    if (m[t.type] == t.voice) return true;
  }
  return false;
}

/// 타입별 기본 좌우 배치 방향 — 웹 `mkTrack()` 의 `dir`.
/// 코드는 왼쪽, 멜로디는 오른쪽으로 벌려 서로 자리를 비운다.
const Map<String, int> kTypePanDir = {
  'drum': 0,
  'bass': 0,
  'chord': -1,
  'melody': 1,
};

/// 라이브에서 친 걸 담는 트랙 이름 — 이 이름으로 찾아서 다시 쓴다(칠 때마다 트랙이
/// 늘면 열 번 치고 나서 트랙이 열 개가 된다).
const String kLiveTrackName = '라이브';

/// 트랙을 새로 만들 때 얹어 주는 패턴. 넷이 같은 계열(로파이/기본)이라 같이 틀면 붙는다.
const Map<String, String> kDefaultPattern = {
  'drum': 'Lofi Chorus',
  'bass': 'Lofi Walk C',
  'chord': 'Lofi Keys C',
  'melody': 'Lofi Hook',
};

/// 인서트 한 칸 (5단계 46/N) — 무엇을 꽂았고, 켜져 있고, 손잡이를 어디에 뒀나.
///
/// **소리 계산은 여기서 안 한다.** 이건 저장·화면용 기록이고, 실제 DSP 는 오디오
/// 아이솔레이트의 `TrackMix.inserts` 가 한다. 둘을 한 객체로 묶으면 아이솔레이트
/// 경계를 넘길 수 없다(오디오 객체는 그쪽에만 산다).
class FxSlot {
  final String type;
  bool on;

  /// 손잡이 값. 비어 있으면 그 플러그인의 기본값을 쓴다.
  final Map<String, double> p;

  FxSlot(this.type, {this.on = true, Map<String, double>? params})
    : p = params ?? {};

  Map<String, dynamic> toJson() => {'type': type, 'on': on, 'p': p};

  static FxSlot fromJson(Map<String, dynamic> j) => FxSlot(
    j['type'] as String,
    on: j['on'] as bool? ?? true,
    params: {
      for (final e in (j['p'] as Map? ?? const {}).entries)
        e.key as String: (e.value as num).toDouble(),
    },
  );
}

/// 인서트를 가진 것 — 트랙이든 마스터든. **화면은 이것만 안다.**
/// 둘이 같은 랙 화면을 쓰려면 이름이 같아야 한다(예전엔 랙이 `Track` 을 직접 받았다).
abstract class FxChainOwner implements Listenable {
  List<FxSlot> get chain;
  void addFx(String type);
  void removeFx(int i);
  void moveFx(int from, int to);
  void setFxParam(int i, String key, double v);
  void setFxOn(int i, bool on);
}

/// 프리셋을 [owner] 에 **통째로 갈아 끼운다.**
///
/// 더하지 않고 **바꾼다** — 프리셋은 「이 조합으로 들리게 해 줘」라는 뜻이지
/// 「지금 것 위에 얹어 줘」가 아니다. 얹으면 두 번 눌렀을 때 리버브가 두 개가 된다.
void applyFxPreset(FxChainOwner owner, FxPresetDef preset) {
  while (owner.chain.isNotEmpty) {
    owner.removeFx(owner.chain.length - 1);
  }
  for (final (type, params) in preset.chain) {
    if (!kFxCatalog.containsKey(type)) continue; // 모르는 종류는 건너뛴다
    owner.addFx(type);
    final i = owner.chain.length - 1;
    params.forEach((k, v) => owner.setFxParam(i, k, v));
  }
}

class TrackEq {
  String mode; // '3' | '10'
  double lo, mid, hi;
  final List<double> b10;
  TrackEq({
    this.mode = '3',
    this.lo = 0,
    this.mid = 0,
    this.hi = 0,
    List<double>? b10,
  }) : b10 = b10 ?? List<double>.filled(10, 0);
}

int _trkSeq = 0;

/// 트랙 하나. **자기 변화는 자기가 알린다** — 채널 스트립이 이것만 구독하면
/// 볼륨을 만져도 다른 트랙·다른 화면은 다시 그려지지 않는다.
class Track extends ChangeNotifier implements FxChainOwner {
  final String id;
  String name;
  String type;
  String _voice;
  bool autoName;

  /// 이 트랙이 연주할 패턴 이름(`patterns.dart` 의 `kDrumPatterns`/`kBassPatterns`/
  /// `kChordPatterns`/`kMelodyPatterns` 중 타입에 맞는 목록). null 이면 안 친다.
  String? _pattern;

  bool _mute = false, _solo = false;
  double _vol = 1.0, _pan = 0.0;

  /// 지금 믹서 값(볼륨·좌우·잔향·EQ)이 **장르가 정해 준 것**인가.
  ///
  /// `fxAuto` 와 같은 규칙이다 — 사용자가 페이더를 하나라도 만지면 false 가 되고,
  /// 그다음부터 스타일을 바꿔도 이 트랙의 믹서는 안 건드린다.
  /// (예전엔 `spaceAuto` 라는 이름으로 **꺼지기만 하고 아무도 안 읽는** 깃발이었다.)
  bool mixAuto = true;

  /// 장르가 정하는 필터·움직임 — **사용자 UI 는 없다.**
  ///
  /// `kGenreMix` 는 슬롯마다 고역 통과(보컬 200Hz 로 저음 걷어내기 등)와
  /// 느린 로우패스 움직임(엠비언트 패드)을 적어 뒀다. 52군데나 된다.
  /// 그런데 그 값이 **어디에도 안 실리고 있었다** — 버스 쪽 장르 몫은 재생할 때
  /// 늘 걷어내고(`setGenreMix(null)`), 트랙에는 담을 칸이 없었다.
  /// 트랩은 이게 없고 있고의 차이가 음악보다 **6dB 아래**였다(= 잘 들린다).
  double hpf = 20, lpf = 20000, lfoHz = 0, lfoDepth = 0;
  double _rev = 0, _dly = 0;
  @override
  final List<FxSlot> chain;
  final TrackEq eq;

  /// **악기 설정**(`instrument_tone.dart`) — 기타 본체·픽업, 피아노 모델·
  /// 에이징. 음색이 그 악기일 때만 뜻이 있다(화면도 그럴 때만 손잡이를 보여
  /// 준다). 바꾸면 [_applyInstrumentTone] 이 이 트랙의 EQ 에 그대로 얹는다.
  String? guitarBody; // 'strat' | 'lespaul'
  String? guitarPickup; // 'neck' | 'mid' | 'bridge'
  String? pianoModel; // 'grand' | 'upright'
  double pianoAging = 0; // 0(새 것) ~ 1(오래된 것)
  String? bassBody; // 'precision' | 'jazz'
  String? stringsEnsemble; // 'solo' | 'section'
  String? brassMute; // 'open' | 'mute'

  /// **ADSR** — 신스 계열 악기만 뜻이 있다(표본 악기·뜯는 계열은 화면에
  /// 손잡이 자체가 안 뜬다, `hasAdsr()` 참고). null 이면 악기 기본값 그대로.
  /// EQ 손잡이와 달리 `mixAuto`/`eqChanged` 규칙을 안 탄다 — 장르를 나중에
  /// 바꿔도 사용자가 잡은 ADSR 은 그대로 남는다(픽업·바디처럼 "악기 자체의
  /// 성격"이지 장르가 매만지는 자리가 아니다). 사용자 요청, 2026-09-15:
  /// "악기들 ADSR 필요한 악기들은 악기 설정에 넣어 놓자".
  double? adsrAttack, adsrDecay, adsrSustain, adsrRelease;

  void setAdsrAttack(double? v) {
    adsrAttack = v;
    notifyListeners();
  }

  void setAdsrDecay(double? v) {
    adsrDecay = v;
    notifyListeners();
  }

  void setAdsrSustain(double? v) {
    adsrSustain = v;
    notifyListeners();
  }

  void setAdsrRelease(double? v) {
    adsrRelease = v;
    notifyListeners();
  }

  /// **유니즌** — ADSR과 같은 대상(신스 계열, `hasAdsr()`)에만 뜻이 있다.
  /// null 이면 악기 기본값(`Inst.uni`) 그대로. 사용자 요청, 2026-09-17:
  /// "유니즌/디투리즈로 두꺼워지게". ADSR처럼 `eqChanged` 규칙을 안 탄다 —
  /// 장르를 나중에 바꿔도 사용자가 잡은 값이 그대로 남는다.
  ///
  /// **필터 움직임**은 새로 만들 필요가 없었다 — [lfoHz]/[lfoDepth]가
  /// 이미 그 자리다(엠비언트 패드용으로 먼저 있었는데 화면에 손잡이만
  /// 없었다). 믹서 "질감" 서랍에서 그 두 값을 그대로 손잡이로 노출한다.
  double? uniCents; // 유니즌 폭(cent) — 0이면 끔, 악기 기본값은 [Inst.uni]

  void setUniCents(double? v) {
    uniCents = v;
    notifyListeners();
  }

  void setGuitarBody(String? v) {
    guitarBody = v;
    _applyInstrumentTone();
  }

  void setGuitarPickup(String? v) {
    guitarPickup = v;
    _applyInstrumentTone();
  }

  void setPianoModel(String? v) {
    pianoModel = v;
    _applyInstrumentTone();
  }

  void setPianoAging(double v) {
    pianoAging = v.clamp(0, 1);
    _applyInstrumentTone();
  }

  void setBassBody(String? v) {
    bassBody = v;
    _applyInstrumentTone();
  }

  void setStringsEnsemble(String? v) {
    stringsEnsemble = v;
    _applyInstrumentTone();
  }

  void setBrassMute(String? v) {
    brassMute = v;
    _applyInstrumentTone();
  }

  /// 악기 설정을 실제 EQ 값으로 바꿔 얹는다. 새 신호줄을 만들지 않고 이미
  /// 재생에 실려 있는 자리(`eq`)를 쓴다 — **사용자가 만졌다**로 적혀서
  /// (`eqChanged`) 장르를 나중에 바꿔도 이 트랙의 EQ는 안 덮인다.
  void _applyInstrumentTone() {
    final (lo, mid, hi) = instrumentToneEq(
      voice: _voice,
      guitarBody: guitarBody,
      guitarPickup: guitarPickup,
      pianoModel: pianoModel,
      pianoAging: pianoAging,
      bassBody: bassBody,
      stringsEnsemble: stringsEnsemble,
      brassMute: brassMute,
    );
    eq
      ..lo = lo
      ..mid = mid
      ..hi = hi;
    eqChanged();
  }

  /// 지금 꽂혀 있는 인서트가 **장르가 꽂아 준 것**인가. (계획 7 · `genre_fx.dart`)
  ///
  /// 사용자가 인서트를 하나라도 만지면 false 가 되고, 그다음부터 스타일을 바꿔도
  /// 이 트랙의 인서트는 안 건드린다. **공들여 꽂아 둔 게 조용히 날아가면 안 된다.**
  /// 옛 파일은 false 로 읽는다 — 그 체인은 사용자가 꽂은 것이기 때문이다.
  bool fxAuto = false;

  Track._({
    required this.id,
    required this.name,
    required this.type,
    required String voice,
    required this.autoName,
    required double pan,
    required double rev,
    required this.chain,
    required this.eq,
    required String? pattern,
  }) : _voice = voice,
       _pan = pan,
       _rev = rev,
       _pattern = pattern;
  // ignore_for_file: prefer_initializing_formals

  /// 웹 `mkTrack(type, name)` 그대로. 패턴 기본값은 웹에 없던 것 —
  /// 트랙을 만들자마자 ▶를 누르면 소리가 나야 뭘 만들고 있는지 알 수 있다.
  factory Track(String type, {String? name}) {
    _trkSeq++;
    final voice = kTypeVoice[type] ?? 'lead';
    final sp = spaceOf(voice);
    final dir = kTypePanDir[type] ?? 0;
    return Track._(
      id: 't$_trkSeq',
      // 드럼은 음색표(VOICE_LABEL)에 없다 — 그대로 두면 이름이 'drum' 으로 찍힌다
      name: name ?? VOICE_LABEL[voice] ?? kTrackTypeLabel[type] ?? voice,
      type: type,
      voice: voice,
      pattern: kDefaultPattern[type],
      autoName: name == null,
      // ② 공간감 기본 배치 — 음색이 가진 폭(SPACE)만큼 타입 방향으로 벌린다
      pan: sp.pan.abs() * dir,
      rev: sp.rev,
      chain: [], // 인서트는 처음엔 비어 있다 — 사용자가 꽂는다
      eq: TrackEq(),
    );
  }

  /// 저장해 둔 것에서 되살린다 — **id 를 그대로 써야 한다**(씬의 클립이 id 로 묶여 있다).
  factory Track.fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String;
    // 새로 만들 트랙이 옛 id 와 부딪히지 않게 번호를 밀어 둔다
    final n = int.tryParse(id.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (n > _trkSeq) _trkSeq = n;
    final t = Track._(
      id: id,
      name: j['name'] as String,
      type: j['type'] as String,
      voice: j['voice'] as String,
      autoName: j['autoName'] as bool? ?? false,
      pan: (j['pan'] as num).toDouble(),
      rev: (j['rev'] as num).toDouble(),
      chain: [
        for (final raw in (j['fx'] as List? ?? const []))
          FxSlot.fromJson(Map<String, dynamic>.from(raw as Map)),
      ],
      eq: TrackEq(
        lo: (j['eqLo'] as num?)?.toDouble() ?? 0,
        mid: (j['eqMid'] as num?)?.toDouble() ?? 0,
        hi: (j['eqHi'] as num?)?.toDouble() ?? 0,
      ),
      pattern: j['pattern'] as String?,
    );
    t._kit = j['kit'] as String? ?? 'acoustic';
    // 옛 파일에는 이 칸이 없다 → false. 그 체인은 사용자가 꽂은 것이라 안 건드리는 게 맞다.
    t.fxAuto = j['fxAuto'] as bool? ?? false;
    // 옛 파일에는 이 칸이 없다 → **true**. 그때는 믹스를 얹는 길 자체가 없었으니
    // 지금 들어 있는 값은 사용자가 맞춘 게 아니라 그냥 기본값이다.
    // (fxAuto 를 false 로 읽는 것과 반대인 이유: 인서트는 있으면 사용자가 꽂은 것이다.)
    t.mixAuto = j['mixAuto'] as bool? ?? true;
    t.hpf = (j['hpf'] as num?)?.toDouble() ?? 20;
    t.lpf = (j['lpf'] as num?)?.toDouble() ?? 20000;
    t.lfoHz = (j['lfoHz'] as num?)?.toDouble() ?? 0;
    t.lfoDepth = (j['lfoDepth'] as num?)?.toDouble() ?? 0;
    t._vol = (j['vol'] as num?)?.toDouble() ?? 1.0;
    t._mute = j['mute'] as bool? ?? false;
    t._solo = j['solo'] as bool? ?? false;
    t.guitarBody = j['guitarBody'] as String?;
    t.guitarPickup = j['guitarPickup'] as String?;
    t.pianoModel = j['pianoModel'] as String?;
    t.pianoAging = (j['pianoAging'] as num?)?.toDouble() ?? 0;
    t.bassBody = j['bassBody'] as String?;
    t.stringsEnsemble = j['stringsEnsemble'] as String?;
    t.brassMute = j['brassMute'] as String?;
    t.adsrAttack = (j['adsrAttack'] as num?)?.toDouble();
    t.adsrDecay = (j['adsrDecay'] as num?)?.toDouble();
    t.adsrSustain = (j['adsrSustain'] as num?)?.toDouble();
    t.adsrRelease = (j['adsrRelease'] as num?)?.toDouble();
    t.uniCents = (j['uniCents'] as num?)?.toDouble();
    return t;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'voice': _voice,
    'kit': _kit,
    'autoName': autoName,
    'vol': _vol,
    'pan': _pan,
    'rev': _rev,
    'mute': _mute,
    'solo': _solo,
    'eqLo': eq.lo,
    'eqMid': eq.mid,
    'eqHi': eq.hi,
    'pattern': _pattern,
    // 인서트 — 꽂은 순서·켜짐·손잡이 값까지 그대로 남긴다(5단계 46/N)
    'fx': [for (final f in chain) f.toJson()],
    'fxAuto': fxAuto,
    'mixAuto': mixAuto,
    // 투명한 값이면 안 적는다 — 옛 파일과 모양이 같아진다
    if (hpf != 20) 'hpf': hpf,
    if (lpf != 20000) 'lpf': lpf,
    if (lfoHz != 0) 'lfoHz': lfoHz,
    if (lfoDepth != 0) 'lfoDepth': lfoDepth,
    if (guitarBody != null) 'guitarBody': guitarBody,
    if (guitarPickup != null) 'guitarPickup': guitarPickup,
    if (pianoModel != null) 'pianoModel': pianoModel,
    if (pianoAging != 0) 'pianoAging': pianoAging,
    if (bassBody != null) 'bassBody': bassBody,
    if (stringsEnsemble != null) 'stringsEnsemble': stringsEnsemble,
    if (brassMute != null) 'brassMute': brassMute,
    if (adsrAttack != null) 'adsrAttack': adsrAttack,
    if (adsrDecay != null) 'adsrDecay': adsrDecay,
    if (adsrSustain != null) 'adsrSustain': adsrSustain,
    if (adsrRelease != null) 'adsrRelease': adsrRelease,
    if (uniCents != null) 'uniCents': uniCents,
  };

  /// 음색 — 이제 **실제로 들린다**(씬 재생이 이 값으로 친다). 5단계 2/N 전에는
  /// 화면 글씨일 뿐이었다(곡 재생은 곡 데이터 안의 음색을 썼다).
  String get voice => _voice;
  set voice(String v) {
    if (_voice == v) return;
    _voice = v;
    if (autoName) name = VOICE_LABEL[v] ?? v;
    notifyListeners();
  }

  /// 드럼 트랙일 때 쓰는 키트(`drums.dart` `DRUM_KIT_ORDER`). 다른 타입에선 안 쓴다.
  /// [voice] 와 따로 둔 이유: 드럼은 음색표가 아니라 키트표를 쓰고, 트랙 이름 자동
  /// 짓기도 음색을 따라가면 안 된다('드럼' 이어야지 '어쿠스틱' 이면 이상하다).
  String _kit = 'acoustic';
  String get kit => _kit;
  set kit(String v) {
    if (_kit == v) return;
    _kit = v;
    notifyListeners();
  }

  String? get pattern => _pattern;
  set pattern(String? v) {
    if (_pattern == v) return;
    _pattern = v;
    notifyListeners();
  }

  /// 알림 없이 값만 바꾼다. 화면을 **짓는 도중**에 바꿔야 할 때가 있다
  /// (편집기의 `initState`) — 그때 알리면 Flutter 가 알림을 버린다.
  /// 부른 쪽이 [ping] 으로 나중에 알려야 한다.
  void setPatternQuiet(String? v) => _pattern = v;

  /// "지금 다시 그려라" — 미뤄 둔 알림을 밖에서 터뜨릴 때.
  /// 미룬 사이에 트랙이 없어졌을 수 있다(스타일을 바꾸면 트랙을 통째로 갈아 낀다)
  /// → 버려진 트랙에 알리면 터진다. 그래서 살아 있을 때만 알린다.
  void ping() {
    if (!_dead) notifyListeners();
  }

  bool _dead = false;

  @override
  void dispose() {
    _dead = true;
    super.dispose();
  }

  // ── 인서트 (5단계 46/N) ──
  //
  // 목록을 그대로 쓴다(정렬하지 않는다) — **순서가 곧 소리다.**
  // 컴프 뒤 드라이브와 드라이브 뒤 컴프는 완전히 다른 소리가 난다.

  /// **사용자가 만졌다** — 이제부터 장르가 이 트랙의 인서트를 안 건드린다.
  void _mine() => fxAuto = false;

  @override
  void addFx(String type) {
    _mine();
    chain.add(FxSlot(type));
    notifyListeners();
  }

  @override
  void removeFx(int i) {
    if (i < 0 || i >= chain.length) return;
    _mine();
    chain.removeAt(i);
    notifyListeners();
  }

  @override
  void moveFx(int from, int to) {
    if (from < 0 || from >= chain.length) return;
    _mine();
    final f = chain.removeAt(from);
    chain.insert(to.clamp(0, chain.length), f);
    notifyListeners();
  }

  @override
  void setFxParam(int i, String key, double v) {
    if (i < 0 || i >= chain.length) return;
    _mine();
    chain[i].p[key] = v;
    notifyListeners();
  }

  @override
  void setFxOn(int i, bool on) {
    if (i >= 0 && i < chain.length) _mine();
    if (i < 0 || i >= chain.length) return;
    chain[i].on = on;
    notifyListeners();
  }

  void rename(String v) {
    name = v;
    autoName = false;
    notifyListeners();
  }

  bool get mute => _mute;
  set mute(bool v) {
    if (_mute == v) return;
    _mute = v;
    notifyListeners();
  }

  bool get solo => _solo;
  set solo(bool v) {
    if (_solo == v) return;
    _solo = v;
    notifyListeners();
  }

  // ── 믹서 값 ──
  // **세터는 「사용자가 만졌다」는 뜻이다.** 그래서 [mixAuto] 를 끈다.
  // 장르가 얹을 때는 세터를 쓰지 말고 [applyMix] 를 쓸 것 —
  // 라이브 음색에서 똑같은 것에 한 번 데였다(`LiveChannel.restore`).
  double get vol => _vol;
  set vol(double v) {
    if (_vol == v) return;
    _vol = v;
    mixAuto = false;
    notifyListeners();
  }

  double get pan => _pan;
  set pan(double v) {
    if (_pan == v) return;
    _pan = v;
    mixAuto = false;
    notifyListeners();
  }

  double get rev => _rev;
  set rev(double v) {
    if (_rev == v) return;
    _rev = v;
    mixAuto = false;
    notifyListeners();
  }

  /// EQ 는 안쪽 객체를 직접 고치므로 세터가 없다 — 고친 뒤 이걸 부른다.
  /// (`touch()` 와 달리 **「사용자가 만졌다」까지 적는다.**)
  void eqChanged() {
    mixAuto = false;
    notifyListeners();
  }

  /// 장르가 정한 믹스를 얹는다 — **[mixAuto] 는 건드리지 않는다.**
  /// 값을 넣는 것과 「내가 골랐다」고 적는 것은 다른 일이다.
  void applyMix(
    double v,
    double p,
    double r,
    double lo,
    double mid,
    double hi, {
    double hpf = 20,
    double lpf = 20000,
    double lfoHz = 0,
    double lfoDepth = 0,
  }) {
    _vol = v;
    _pan = p;
    _rev = r;
    eq
      ..lo = lo
      ..mid = mid
      ..hi = hi;
    this.hpf = hpf;
    this.lpf = lpf;
    this.lfoHz = lfoHz;
    this.lfoDepth = lfoDepth;
    notifyListeners();
  }

  double get dly => _dly;
  set dly(double v) {
    if (_dly == v) return;
    _dly = v;
    notifyListeners();
  }

  /// EQ·체인처럼 안쪽 객체를 직접 고친 뒤에 부른다.
  void touch() => notifyListeners();
}

/// 라이브 채널 — **손으로 치는 건반**. 웹 `liveVoice`/`liveVol`/`liveFX` 를 옮긴 것.
///
/// 트랙과 완전히 분리된 채널이다. 오디오 쪽도 전용 버스(`TrackMixSet.live`)를 따로
/// 두었다 — 안 그러면 멜로디 트랙 페이더를 내릴 때 내가 치는 소리까지 같이 작아진다.
///
/// 딜레이(웹 `liveFX.dly`)는 **아직 엔진에 없다**(리버브만 있다). 있는 척 노브만
/// 달아 두면 만져도 아무 일이 안 일어나므로 넣지 않았다.
class LiveChannel extends ChangeNotifier implements FxChainOwner {
  /// 라이브 인서트 — **손으로 치는 소리에만** 걸리는 플러그인 자리.
  ///
  /// 엔진 쪽은 이미 되어 있었다(`live` 는 붙박이 버스라 `inserts` 를 들고 있다).
  /// 없던 것은 **꽂을 자리**뿐이었다 — 트랙과 마스터에는 랙이 있는데 라이브만
  /// 볼륨·울림 두 손잡이로 끝이었다. 라이브는 반주 위에 얹어 치는 소리라
  /// 딜레이 하나만 걸어도 완전히 달라진다.
  @override
  final List<FxSlot> chain = [];

  @override
  void addFx(String type) {
    chain.add(FxSlot(type));
    notifyListeners();
  }

  @override
  void removeFx(int i) {
    if (i < 0 || i >= chain.length) return;
    chain.removeAt(i);
    notifyListeners();
  }

  @override
  void moveFx(int from, int to) {
    if (from < 0 || from >= chain.length) return;
    final f = chain.removeAt(from);
    chain.insert(to.clamp(0, chain.length), f);
    notifyListeners();
  }

  @override
  void setFxParam(int i, String key, double v) {
    if (i < 0 || i >= chain.length) return;
    chain[i].p[key] = v;
    notifyListeners();
  }

  @override
  void setFxOn(int i, bool on) {
    if (i < 0 || i >= chain.length) return;
    chain[i].on = on;
    notifyListeners();
  }

  String _voice = 'piano';
  double _vol = 1.0, _rev = 0.18;

  /// 지금 음색이 **장르가 정해 준 것**인가. (계획 7 의 Live Behavior)
  /// 사용자가 한 번이라도 고르면 false — 그다음부터 장르가 안 건드린다.
  bool voiceAuto = true;

  String get voice => _voice;

  /// **사용자가 고른** 음색. 이걸로 바꾸면 장르가 더는 안 건드린다.
  set voice(String v) {
    voiceAuto = false;
    if (_voice == v) return;
    _voice = v;
    notifyListeners();
  }

  /// **장르가 정해 준** 음색 — 사용자가 고른 적 있으면 아무 일도 안 한다.
  ///
  /// **알림을 안 보낸다.** 이건 라이브 화면이 열릴 때(`initState`) 불리는데,
  /// 빌드 도중에 알림을 보내면 그 값을 듣고 있는 화면이 「빌드 중 재빌드」로 터진다.
  /// 지금은 듣는 쪽이 자동 저장뿐이라 안 터지지만, **나중에 하나만 더 붙어도** 터진다.
  ///
  /// 안 보내도 되는 이유: 값은 이미 바뀌었고, 이 화면은 그다음 빌드에서 읽는다.
  /// 저장이 안 되는 것도 문제가 아니다 — **장르가 정해 주는 기본값**이라 다음에
  /// 열 때 또 얹힌다(사용자가 고른 것만 저장되면 된다).
  void suggestVoice(String v) {
    if (!voiceAuto || _voice == v) return;
    _voice = v;
  }

  /// 저장 파일에서 되살릴 때 쓴다 — **[voiceAuto] 를 건드리지 않고** 값만 넣는다.
  ///
  /// 예전엔 불러오기가 그냥 `live.voice = ...` 를 썼다. 그런데 그 setter 는
  /// 「사용자가 골랐다」는 뜻이라 **`voiceAuto` 를 false 로 만든다.**
  /// 결과: 곡을 한 번이라도 저장했다 열면(= 자동 저장이 있으니 늘) 그 곡은
  /// 영영 `voiceAuto = false` 가 되고, **장르별 라이브 기본 음색(계획 7)이
  /// 통째로 죽었다.** 값을 넣는 것과 「내가 골랐다」고 적는 것은 다른 일이다.
  void restore({String? voice, double? vol, double? rev, bool? auto}) {
    if (voice != null) _voice = voice;
    if (vol != null) _vol = vol;
    if (rev != null) _rev = rev;
    if (auto != null) voiceAuto = auto;
    notifyListeners();
  }

  double get vol => _vol;
  set vol(double v) {
    if (_vol == v) return;
    _vol = v;
    notifyListeners();
  }

  double get rev => _rev;
  set rev(double v) {
    if (_rev == v) return;
    _rev = v;
    notifyListeners();
  }
}

/// 재생 상태 — 템포·조·반복. 웹 `P.bpm` / `KEY` / 재생 버튼 자리.
///
/// 지금은 **예약형 재생**이다: ▶를 누르면 `reps` 번 반복할 분량을 한꺼번에 엔진 예약
/// 큐에 넣는다(곡 재생이 쓰는 것과 같은 길). 진짜 무한 루프(재생 중 패턴을 바꾸면 다음
/// 마디부터 바뀌는 식)는 재생 위치를 UI 가 알아야 해서 다음 덩어리로 미뤘다.
class Transport extends ChangeNotifier {
  double _bpm = 92;
  int _root = 0; // 0=C
  String _mode = 'minor';
  int _reps = 8; // 몇 번 반복해서 예약할지
  bool _playing = false;

  double get bpm => _bpm;
  set bpm(double v) {
    if (_bpm == v) return;
    _bpm = v;
    notifyListeners();
  }

  int get root => _root;
  set root(int v) {
    if (_root == v) return;
    _root = v;
    notifyListeners();
  }

  String get mode => _mode;
  set mode(String v) {
    if (_mode == v) return;
    _mode = v;
    notifyListeners();
  }

  int get reps => _reps;
  set reps(int v) {
    if (_reps == v) return;
    _reps = v;
    notifyListeners();
  }

  bool get playing => _playing;
  set playing(bool v) {
    if (_playing == v) return;
    _playing = v;
    notifyListeners();
  }

  /// **지금 도는 것이 씬 한 판 루프가 아니라 「곡 재생」(구간을 전부 이어붙인
  /// 한 판)인가.** 씬 한 판은 몇 마디 안 되지만 「곡 재생」은 그 자체로
  /// 몇 분짜리 한 판이다 — 씬 화면에서 다른 씬 칩을 눌러도 `refreshLoop` 가
  /// "다음 판부터"를 그 몇 분 뒤로 잡아서, 씬을 눌러도 아무 일도 안 일어나는
  /// 것처럼 보였다(사용자가 실기기에서 "안 넘어가고 반복되던데"로 잡음).
  /// 씬 칩을 누르는 쪽은 이 값을 보고, 켜져 있으면 이어 가는 대신 그 자리에서
  /// 새 씬 루프로 갈아탄다.
  bool songLoop = false;
}

/// 조 이름 — 0=C. 웹 표기와 같다.
const List<String> kKeyNames = [
  'C',
  'C#',
  'D',
  'D#',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'A#',
  'B',
];

/// **조 이름은 장·단조마다 다르게 적는다.**
/// 「D# 단조」라고 쓰는 사람은 없다 — E♭단조라고 쓴다. 마찬가지로 장조에서는
/// C♯장조가 아니라 D♭장조다. 소리는 같아도 **악보에서는 다른 이름**이고,
/// 악보를 읽는 사람에게는 그게 곧 틀린 표기다.
const List<String> kMinorKeyNames = [
  'C',
  'C#',
  'D',
  'Eb',
  'E',
  'F',
  'F#',
  'G',
  'G#',
  'A',
  'Bb',
  'B',
];
const List<String> kMajorKeyNames = [
  'C',
  'Db',
  'D',
  'Eb',
  'E',
  'F',
  'F#',
  'G',
  'Ab',
  'A',
  'Bb',
  'B',
];

/// 화면에 적는 조 이름 — 「E♭ 단조」처럼 읽히게.
String keyLabel(int root, String mode) {
  final i = ((root % 12) + 12) % 12;
  final n = mode == 'minor' ? kMinorKeyNames[i] : kMajorKeyNames[i];
  return '$n ${mode == 'minor' ? '단조' : '장조'}';
}

/// 마스터 채널 — 전체 출력. 웹 `MASTER.vol`.
/// 엔진의 고정 헤드룸(0.55)에 곱해진다. 1.0 이 기준(0dB).
class MasterChannel extends ChangeNotifier implements FxChainOwner {
  /// 마스터 인서트 (5단계 47/N) — 마스터링 플러그인이 꽂히는 자리.
  @override
  final List<FxSlot> chain = [];

  /// 지금 마스터 인서트가 **장르가 자동으로 건 것**인가(§계획 — "장르별
  /// 자동 마스터링"). 사용자가 랙에서 하나라도 만지면(원탭 프리셋을 골라도
  /// 마찬가지 — [applyFxPreset] 도 이 클래스의 [addFx] 를 거친다) false 가
  /// 되고, 그다음부터 스타일을 바꿔도 마스터 인서트는 안 건드린다 — 트랙의
  /// `fxAuto` 와 같은 규칙이다.
  bool fxAuto = false;

  /// **사용자가 만졌다** — 이제부터 스타일을 바꿔도 마스터 인서트는 그대로 둔다.
  void _mine() => fxAuto = false;

  @override
  void addFx(String type) {
    _mine();
    chain.add(FxSlot(type));
    notifyListeners();
  }

  @override
  void removeFx(int i) {
    if (i < 0 || i >= chain.length) return;
    _mine();
    chain.removeAt(i);
    notifyListeners();
  }

  @override
  void moveFx(int from, int to) {
    if (from < 0 || from >= chain.length) return;
    _mine();
    final f = chain.removeAt(from);
    chain.insert(to.clamp(0, chain.length), f);
    notifyListeners();
  }

  @override
  void setFxParam(int i, String key, double v) {
    if (i < 0 || i >= chain.length) return;
    _mine();
    chain[i].p[key] = v;
    notifyListeners();
  }

  @override
  void setFxOn(int i, bool on) {
    if (i < 0 || i >= chain.length) return;
    _mine();
    chain[i].on = on;
    notifyListeners();
  }

  /// **장르별 자동 마스터링** — 스타일을 고르면(`project_settings_sheet.dart`)
  /// `fx.dart` 의 [kGenreMasterPreset] 이름으로 찾은 프리셋을 통째로 얹는다.
  /// 사용자가 이미 마스터 랙을 만졌으면([fxAuto] false) 손대지 않는다.
  void applyGenrePreset(FxPresetDef preset) {
    if (chain.isNotEmpty && !fxAuto) return; // 사용자 것 — 손대지 않는다
    chain
      ..clear()
      ..addAll([
        for (final (type, params) in preset.chain)
          FxSlot(type, params: Map<String, double>.from(params)),
      ]);
    fxAuto = true;
    notifyListeners();
  }

  double _vol = 1.0;
  double get vol => _vol;
  set vol(double v) {
    if (_vol == v) return;
    _vol = v;
    notifyListeners();
  }
}

/// 씬 하나 — **한 벌의 클립 + 그 벌에 어울리는 템포·키트.**
///
/// 웹 씬 뷰는 트랙×씬 격자에 클립을 놓고 씬을 '발사(launch)'한다. 여기도 같은 뜻인데,
/// 폰 세로 화면에 격자를 그리면 칸이 너무 작아져서 **씬 칩 + 트랙 목록** 으로 폈다.
/// 어느 씬을 고르면 그 씬의 클립이 트랙에 실린다.
///
/// [bpm]/[kit] 을 씬이 들고 있는 게 웹과 다른 점이다. 장르가 통째로 바뀔 때 템포와
/// 드럼 키트가 같이 안 바뀌면 그 장르로 안 들린다(로파이 78 → 하우스 124).
/// 씬을 새로 만들 때 **돌아가며** 붙이는 캐릭터([Scene.critter]).
///
/// 값은 `lib/ui/critters.dart` 의 id 와 같아야 한다 — 여기서 지어낸 이름을 쓰면
/// 화면에는 아무것도 안 그려지고 오류도 안 난다. 그래서 **시험이 두 목록이
/// 맞는지 본다**(`critter_check_test`). 이 프로젝트에서 제일 자주 나온 병이
/// 「말없이 어긋난 두 표」다.
const List<String> kDefaultCritters = [
  '@dancer',
  '@cat',
  '@note',
  '@slime',
  '@mushroom',
  '@robot',
  '@bird',
  '@gem',
  '@eyeball',
  '@alien',
  '@hero',
];

class Scene {
  String name;
  double? bpm;
  String? kit;

  /// 이 씬에 붙인 **캐릭터**(`@dancer` 같은 값이거나 그냥 이모지). 없으면 null.
  ///
  /// 씬 이름은 「벌스 2」 처럼 다 비슷하게 남는다 — 이름만으로는 어느 씬이
  /// 어느 씬인지 안 보인다. 캐릭터는 **한눈에 다른 것**이 되어 주고, 돌고 있을 때는
  /// 박자에 맞춰 움직여서 지금 무엇이 도는지도 같이 알려 준다.
  String? critter;

  /// 트랙 id → 패턴 이름. 값이 없거나 null 이면 그 씬에서 그 트랙은 **쉰다**.
  final Map<String, String?> clips;

  Scene(
    this.name, {
    this.bpm,
    this.kit,
    this.critter,
    Map<String, String?>? clips,
  }) : clips = clips ?? {};

  Map<String, dynamic> toJson() => {
    'name': name,
    'bpm': bpm,
    'kit': kit,
    'critter': critter,
    'clips': clips,
  };

  factory Scene.fromJson(Map<String, dynamic> j) => Scene(
    j['name'] as String,
    bpm: (j['bpm'] as num?)?.toDouble(),
    kit: j['kit'] as String?,
    critter: j['critter'] as String?,
    clips: {
      for (final e in (j['clips'] as Map).entries)
        e.key as String: e.value as String?,
    },
  );

  Scene copyWith(String newName) => Scene(
    newName,
    bpm: bpm,
    kit: kit,
    critter: critter,
    clips: Map<String, String?>.from(clips),
  );
}

/// 곡의 한 구간 — "몇 번 씬을 몇 판 돌린다".
///
/// 길이 단위를 **마디가 아니라 판(loop)** 으로 잡았다. 씬마다 패턴 길이가 다른데
/// (2마디짜리도 4마디짜리도 있다) 마디로 자르면 패턴이 중간에 잘려서 어색해진다.
/// 판 단위면 항상 프레이즈가 온전히 끝난다.
class Section {
  int scene;
  int reps;
  Section(this.scene, {this.reps = 2});
}

/// 스타일을 바꾸기 **직전**의 곡 전체 — 되돌리기용.
///
/// [Project.setGenre] 는 이 앱에서 **한 번에 제일 많이 바꾸는 손짓**이다.
/// 씬·트랙·클립·믹서·인서트·구간표가 통째로 갈린다(객체형 장르는 편성까지).
/// 그런데 스타일 칩은 곡 화면에서 옆으로 흐르는 줄에 있어서 **스크롤하다 잘못
/// 눌리기 쉽다.** 트랙 하나를 지울 때는 확인까지 받으면서, 곡 전체가 갈리는
/// 여기에는 여태 되돌릴 길이 없었다.
///
/// 새로 만들지 않고 **이미 잘 도는 길**(`toJson`/`loadJson`)을 그대로 쓴다 —
/// 곡을 저장하고 여는 바로 그 길이라, 여기서만 빠뜨리는 값이 생기지 않는다.
class GenreUndo {
  final String genre;
  final Map<String, dynamic> json;
  final double bpm;
  final int root;
  final String mode;
  const GenreUndo(this.genre, this.json, this.bpm, this.root, this.mode);

  /// 지금 상태를 통째로 뜬다. **바꾸기 전에** 불러야 한다.
  factory GenreUndo.of(Project p, Transport tr) =>
      GenreUndo(p.genre, p.toJson(), tr.bpm, tr.root, tr.mode);

  void restore(Project p, Transport tr) {
    p.loadJson(json);
    tr
      ..bpm = bpm
      ..root = root
      ..mode = mode;
  }
}

/// 지운 트랙을 되돌릴 수 있게 통째로 들고 있는 것.
/// 트랙 자체 · 트랙 목록에서의 자리 · **씬마다 실려 있던 클립**.
///
/// 트랙은 `ChangeNotifier` 라 언젠가는 [drop] 해 줘야 한다.
/// 되돌리기 알림이 사라질 때 부르면 된다 — 되돌렸으면 부르지 않는다.
class RemovedTrack {
  final Track track;
  final int at;
  final Map<Scene, String?> clips;

  /// 타임라인 트랙 줄에 놓여 있던 클립들 — 트랙과 **같이** 나갔다 같이 돌아온다.
  /// (트랙을 지웠는데 클립이 남으면 없는 악기를 가리키는 클립이 된다)
  final List<LaneClip> lanes;
  bool _dropped = false;
  RemovedTrack({
    required this.track,
    required this.at,
    required this.clips,
    this.lanes = const [],
  });

  /// 되돌리지 않기로 했다 — 이제 치운다. 두 번 불러도 괜찮다.
  void drop() {
    if (_dropped) return;
    _dropped = true;
    track.dispose();
  }
}

/// 지운 씬을 되돌릴 수 있게 통째로 들고 있는 것.
/// 씬 자체 · 씬 목록에서의 자리 · **지워지기 전의 곡 구간표** · 보고 있던 씬.
class RemovedScene {
  final Scene scene;
  final int at;
  final List<Section> sections;

  /// 타임라인 트랙 줄도 같이 들고 나온다 — 씬을 지우면 그 구간의 클립도
  /// 같이 없어지는데, 되돌릴 때 구간만 살아나면 트랙 줄이 빈 채로 돌아온다.
  final List<LaneClip> lanes;
  final int wasCurrent;
  const RemovedScene({
    required this.scene,
    required this.at,
    required this.sections,
    required this.lanes,
    required this.wasCurrent,
  });
}

/// 타임라인 **트랙 줄**에 놓은 클립 하나 — 그 자리에서 이 트랙은 씬 것 대신 이걸 친다.
///
/// 옛 앱(뮤직 두들)의 `P.tl.clips` 를 가져온 것이되 **자리를 잡는 법이 다르다.**
/// 거기는 「곡 전체 몇 마디째」였다. 여기서 그러면 구간을 하나 끼우거나 판 수를
/// 늘리는 순간 뒤엣것이 **전부 어긋난다** — 씬 번호가 밀리는 것과 똑같은 병이고
/// 이 저장소에서 이미 두 번 겪었다(`onSceneInserted` 주석 참고).
/// 그래서 **(구간, 구간 안 몇 마디째)** 로 잡는다. 구간을 옮기면 클립도 따라간다.
class LaneClip {
  int section;

  /// 그 구간 안에서 몇 마디째(0 = 구간 첫 마디).
  int bar;
  final String trackId;
  String pattern;
  LaneClip({
    required this.section,
    required this.bar,
    required this.trackId,
    required this.pattern,
  });

  Map<String, dynamic> toJson() => {
    'section': section,
    'bar': bar,
    'track': trackId,
    'pattern': pattern,
  };

  factory LaneClip.fromJson(Map<String, dynamic> j) => LaneClip(
    section: j['section'] as int,
    bar: j['bar'] as int,
    trackId: j['track'] as String,
    pattern: j['pattern'] as String,
  );

  LaneClip copy() =>
      LaneClip(section: section, bar: bar, trackId: trackId, pattern: pattern);
}

/// 곡(타임라인) — 씬을 시간 순서로 늘어놓은 것. 웹 타임라인 뷰의 자리.
class Arrangement extends ChangeNotifier {
  final List<Section> sections;

  /// 타임라인 트랙 줄에 놓인 클립들. 비어 있으면 여태와 똑같이 돈다 —
  /// **옛 파일에는 이 칸이 없다**(빈 목록으로 읽힌다).
  final List<LaneClip> lanes;
  Arrangement([List<Section>? s, List<LaneClip>? l])
    : sections = s ?? [],
      lanes = l ?? [];

  /// 그 구간의 그 트랙에 놓인 클립들 — 앞에서부터.
  List<LaneClip> lanesIn(int section, String trackId) => [
    for (final c in lanes)
      if (c.section == section && c.trackId == trackId) c,
  ];

  /// 클립을 놓는다. **같은 자리에 이미 있으면 갈아 끼운다** — 겹쳐 놓으면
  /// 어느 것이 나는지 알 수 없다(옛 앱은 「이미 클립이 있습니다」로 막았는데,
  /// 그러면 바꾸려면 지웠다 다시 놓아야 한다).
  void putLane(int section, int bar, String trackId, String pattern) {
    for (final c in lanes) {
      if (c.section == section && c.bar == bar && c.trackId == trackId) {
        c.pattern = pattern;
        notifyListeners();
        return;
      }
    }
    lanes.add(
      LaneClip(section: section, bar: bar, trackId: trackId, pattern: pattern),
    );
    notifyListeners();
  }

  void removeLane(LaneClip c) {
    if (lanes.remove(c)) notifyListeners();
  }

  /// 구간 번호가 밀리거나 사라졌을 때 클립을 따라 옮긴다.
  /// [map] 은 옛 번호 → 새 번호(없어졌으면 null).
  void _remapLanes(int? Function(int) map) {
    final keep = <LaneClip>[];
    for (final c in lanes) {
      final to = map(c.section);
      if (to == null) continue;
      c.section = to;
      keep.add(c);
    }
    lanes
      ..clear()
      ..addAll(keep);
  }

  void add(int scene) {
    sections.add(Section(scene));
    notifyListeners();
  }

  /// [at] 자리에 끼운다 — 뒤엣것은 한 칸씩 밀린다.
  void insert(int at, int scene, {int reps = 2}) {
    final k = at.clamp(0, sections.length);
    sections.insert(k, Section(scene, reps: reps));
    _remapLanes((i) => i >= k ? i + 1 : i);
    notifyListeners();
  }

  /// **바로 뒤에 한 벌 더.** 코러스를 두 번 돌리려고 맨 뒤에 붙였다가 열 칸을
  /// 끌어 올릴 필요가 없다 — 그게 여태 유일한 길이었다.
  void duplicateAt(int i) {
    if (i < 0 || i >= sections.length) return;
    final s = sections[i];
    // **놓아 둔 클립도 같이 베낀다.** 「한 벌 더」는 그 구간을 그대로 한 번 더
    // 라는 뜻인데, 트랙 줄만 빠지면 두 번째가 딴 소리가 난다.
    final mine = [
      for (final c in lanes)
        if (c.section == i) c.copy(),
    ];
    sections.insert(i + 1, Section(s.scene, reps: s.reps));
    _remapLanes((k) => k > i ? k + 1 : k);
    for (final c in mine) {
      c.section = i + 1;
      lanes.add(c);
    }
    notifyListeners();
  }

  void removeAt(int i) {
    if (i < 0 || i >= sections.length) return;
    sections.removeAt(i);
    _remapLanes((k) => k == i ? null : (k > i ? k - 1 : k));
    notifyListeners();
  }

  void move(int from, int to) {
    if (from == to || from < 0 || to < 0) return;
    if (from >= sections.length || to >= sections.length) return;
    sections.insert(to, sections.removeAt(from));
    // 끌어 옮긴 구간의 클립도 **같이 간다.** 안 그러면 코러스를 앞으로 옮겼을 때
    // 트랙 줄만 제자리에 남아 딴 구간에 붙는다.
    _remapLanes((k) {
      if (k == from) return to;
      if (from < to) return (k > from && k <= to) ? k - 1 : k;
      return (k >= to && k < from) ? k + 1 : k;
    });
    notifyListeners();
  }

  void setReps(int i, int reps) {
    if (i < 0 || i >= sections.length) return;
    sections[i].reps = reps.clamp(1, 32);
    notifyListeners();
  }

  /// 지우기 전의 구간표로 통째로 되돌린다 ([Project.undoRemoveScene] 이 쓴다).
  void restore(List<Section> prev, [List<LaneClip>? prevLanes]) {
    sections
      ..clear()
      ..addAll(prev);
    if (prevLanes != null) {
      lanes
        ..clear()
        ..addAll(prevLanes);
    }
    notifyListeners();
  }

  /// 씬을 [at] 자리에 끼우면 **뒤쪽 번호가 하나씩 밀린다** — 구간도 따라가야 한다.
  /// (`onSceneRemoved` 의 짝. 이게 없어서 씬을 복제하면 곡이 어긋났다.)
  void onSceneInserted(int at) {
    var moved = 0;
    for (final s in sections) {
      if (s.scene >= at) {
        s.scene++;
        moved++;
      }
    }
    if (moved > 0) notifyListeners();
  }

  /// 씬을 지우면 그 씬을 가리키던 구간도 정리해야 한다 — 안 그러면 엉뚱한 씬을 가리킨다.
  void onSceneRemoved(int removed) {
    // 구간이 통째로 빠지므로 **번호가 밀린다** — 놓아 둔 클립도 따라가야 한다.
    // (여기를 빠뜨리면 씬 하나를 지웠을 때 트랙 줄이 엉뚱한 구간에 붙는다)
    var k = 0;
    final map = <int, int?>{};
    for (var i = 0; i < sections.length; i++) {
      map[i] = sections[i].scene == removed ? null : k++;
    }
    sections.removeWhere((s) => s.scene == removed);
    for (final s in sections) {
      if (s.scene > removed) s.scene--;
    }
    _remapLanes((i) => map[i]);
    notifyListeners();
  }
}

/// 프로젝트 전체. **구조가 바뀔 때만** 알린다(트랙 추가·삭제·순서, 씬 추가 등).
/// 트랙 안쪽 값(볼륨·팬·뮤트)은 [Track] 이 스스로 알리므로 여기서는 안 알린다 —
/// 그래야 채널 스트립 하나만 다시 그려진다.
class Project extends ChangeNotifier {
  final List<Track> tracks;
  final List<Scene> scenes;
  final Arrangement song;

  /// 지금 트랙에 실려 있는 씬. **밖에서는 못 바꾼다** — [launchScene] 을 쓸 것.
  ///
  /// 그냥 필드였을 때는 `p.currentScene = 3` 이 가능했는데, 그러면 번호만 바뀌고
  /// **트랙에 실린 판은 그대로**다. 겉보기엔 3번 씬인데 소리는 2번 씬이고,
  /// 저장했다 열면 그제서야 3번 씬의 판이 실린다(왕복에서 내용이 달라진다).
  /// 「막 써 보기」 시험이 이걸 잡았다 — 앱은 아직 그런 적이 없지만, 필드가 열려
  /// 있는 한 언젠가 생긴다.
  int _currentScene = 0;
  int get currentScene => _currentScene;

  Project._(this.tracks, this.scenes, this.song);

  /// 미뤄 둔 알림이 도착했을 때 이미 버려진 뒤일 수 있다 → 살아 있는지 표시해 둔다.
  bool _dead = false;

  @override
  void dispose() {
    _dead = true;
    super.dispose();
  }

  /// 이 곡의 스타일 — `kSongForms` 의 키. **곡 하나는 스타일 하나다.**
  String genre = 'lofi';

  /// 이 곡의 **박자** — `kMeters` 의 키('4/4'·'3/4'·'6/8'·'5/4'·'7/8').
  ///
  /// **곡 하나는 박자 하나다.** 마디 길이가 트랙마다 다르면 마디라는 것이 없어진다 —
  /// 씬도 구간도 타임라인도 전부 마디로 세는데, 그 자가 트랙마다 다르면 아무것도
  /// 못 맞춘다. 판은 제 박자(`spb`)를 들고 다니지만, **곡에 실릴 수 있는 것은
  /// 이 박자와 맞는 판뿐**이다(고르는 화면이 걸러 준다).
  String meter = '4/4';

  /// 이 곡의 한 마디가 몇 칸인가 — 여태 `kStepsPerBar` 를 쓰던 자리가 이걸 쓴다.
  int get spb => meterStepsOf(meter);

  /// 이 곡의 박자 표.
  MeterDef get meterDef => meterOf(meter);

  /// 곡 이름 — 목록에 보이는 이름. 5단계 10/N(곡 여러 개)부터 쓴다.
  String name = '새 곡';

  /// **비켜주기(사이드체인 덕킹) 세기** — 킥이 칠 때 나머지가 얼마나
  /// 눌리는가. `null` 이면 장르 기본값(`kGenreDuck`)을 그대로 따른다 —
  /// 사용자가 마스터 믹서에서 직접 만지면 이 값이 채워지고, 그 뒤로는
  /// 스타일을 바꿔도(장르 기본값이 달라져도) **사용자가 정한 세기가
  /// 이긴다**(`mixer_view.dart`).
  double? duckAmountOverride;

  /// **비켜준 뒤 되돌아오는 시간**(초) — 너무 짧으면 딸꾹질처럼, 너무
  /// 길면 늘 눌린 채로 들린다. 장르가 정하는 값이 아니라 처음부터
  /// 사용자 손잡이다(`Engine.duckRelSec`).
  double duckRelSec = 0.16;

  /// 드럼/베이스/코드/멜로디 4트랙 + **곡 구간(인트로·벌스·코러스·브레이크·아웃트로)**.
  ///
  /// 5단계 5/N 에서는 씬마다 장르를 다르게 넣었다(로파이→하우스→힙합). 사용자 지적대로
  /// **그건 곡이 아니라 짜깁기다.** 곡은 스타일 하나 안에서 **구간**이 흘러야 한다.
  /// 그래서 씬 = `song.dart` `kSongForms[genre]` 의 섹션, 얼개 = `kFormOrder`
  /// (인트로→벌스→코러스→브레이크→벌스→코러스→아웃트로) 로 바꿨다.
  factory Project.initial() {
    final tracks = [
      Track('drum'),
      Track('bass'),
      Track('chord'),
      Track('melody'),
    ];
    final proj = Project._(tracks, [], Arrangement());
    proj.setGenre('lofi');
    return proj;
  }

  /// **빈 캔버스.** 장르를 안 씌운다 — 씬 하나(전부 쉼)와 구간 하나뿐이다.
  ///
  /// 사용자 결정(2026-09): 장르 송폼을 프로젝트 시작의 필수 첫 단계에서
  /// 빼고, **나중에 고를 수 있는 프리셋**으로 남긴다. 새 프로젝트는 여기서
  /// 시작해서 직접 미디를 찍거나 표본 악기를 얹는다 — 장르는 씬 화면의
  /// "스타일 바꾸기"(`setGenre`, 이미 있던 기능)로 언제든 나중에 씌운다.
  ///
  /// [Project.initial] 은 **손 안 댔다** — 기존 시험 수십 개가 "새
  /// 프로젝트 = 장르가 이미 씌워짐"을 전제로 만들어져 있어서, 그 전제를
  /// 건드리면 이 변경과 무관한 곳까지 다 깨진다. 앱이 실제로 띄우는 진짜
  /// 프로젝트만 이걸 쓴다(`main.dart`).
  factory Project.blank() {
    final tracks = [
      Track('drum'),
      Track('bass'),
      Track('chord'),
      Track('melody'),
    ];
    final scene = Scene('씬 1');
    final proj = Project._(tracks, [scene], Arrangement([Section(0)]));
    // 빈 문자열 — `genreDef`/`songGenreOf` 는 모르는 키를 첫 장르로 떨어뜨려
    // 안 죽지만, **그 값을 그대로 화면에 보이면 안 된다**("로파이" 라고 써
    // 있는데 패턴은 하나도 없다). 화면 쪽에서 `genre.isEmpty` 로 "빈
    // 프로젝트"를 따로 보여준다(`home_view.dart`).
    proj.genre = '';
    return proj;
  }

  /// 곡 스타일을 갈아입힌다 — 구간 구성은 그 곡의 송폼으로, 얼개도 그 곡 순서로.
  ///
  /// 스타일에는 두 종류가 있다:
  /// - **배열형**(`kSongForms`, 로파이~록) — 드럼/베이스/코드/멜로디 4트랙 고정.
  ///   트랙을 그대로 두고 클립만 갈아 끼운다(믹서에서 맞춘 값이 살아남는다).
  /// - **객체형**(`kObjectSongForms`, 트랩~엠비언트) — **곡마다 편성이 다르다.**
  ///   트랩은 808·패드·브라스·벨·플럭. 4트랙으로는 그 곡을 연주할 수 없으므로
  ///   **트랙 목록 자체를 그 곡의 것으로 새로 만든다.**
  void setGenre(String key) {
    final g = songGenreOf(key);
    final obj = kObjectSongForms[key];
    if (obj == null && kSongForms[key] == null) return;
    genre = key;
    // **박자를 스타일이 정한다** (5단계 47/N). 판 라이브러리가 박자마다 따로라,
    // 여기서 안 옮기면 왈츠를 골라도 격자·타임라인은 여전히 4/4로 세다가
    // 3/4 판(spb 12)과 어긋난다.
    meter = genreDef(key).meter;

    if (obj != null) {
      _seedObject(obj, g);
    } else {
      _seedArray(kSongForms[key]!, g);
    }

    // 처음 보이는 구간은 **곡에서 제일 센 데**로 — 인트로는 드럼도 베이스도 쉬는
    // 구간이라 씬 화면에서 ▶를 누르면 "왜 이렇게 허전하지"가 된다.
    // 이름으로 먼저 찾고(코러스·훅·드롭), 없으면 파트가 제일 많은 구간.
    var best = scenes.indexWhere(
      (e) => e.name == '코러스' || e.name == '훅' || e.name == '드롭',
    );
    if (best < 0) {
      var bestCount = -1;
      best = 0;
      for (var i = 0; i < scenes.length; i++) {
        final n = scenes[i].clips.values.where((v) => v != null).length;
        if (n > bestCount) {
          bestCount = n;
          best = i;
        }
      }
    }
    _currentScene = best;
    _loadScene(currentScene);
    notifyListeners();
  }

  /// 지금 스타일의 대표 패턴 — [addTrack] 이 4/4 가 아닐 때 이걸 쓴다
  /// (그 스타일이 고른 것이니 반드시 지금 박자와 맞는다).
  String? _genreDefaultPattern(String type) {
    final g = genreDef(genre);
    return switch (type) {
      'drum' => g.drumPat,
      'bass' => g.bassPat,
      'chord' => g.chordPat,
      _ => g.melodyPat,
    };
  }

  /// 마지막으로 편성을 통째로 만든 객체형 스타일. null 이면 기본 4트랙 편성이다.
  /// 객체형(트랩 6트랙) 에서 배열형(로파이 4트랙) 으로 돌아올 때 **트랙을 되돌리려고**
  /// 들고 있는다. 안 그러면 트랩의 벨·플럭이 남아서 로파이에 엉뚱한 트랙이 붙는다.
  String? _formTracksGenre;

  /// 스타일을 바꾼 뒤, 손으로 고친 판을 **그대로 둔 개수**(배열형)와
  /// 편성이 바뀌어 **씬에서 빠진 개수**(객체형). 화면이 이걸 읽어 한 줄로 알려 준다.
  int keptMine = 0, parkedMine = 0;

  /// 지금 씬들에 실려 있는 **내가 고친 판**을 (씬번호:트랙타입) 으로 적어 둔다.
  Map<String, String> _mineByScene() {
    final out = <String, String>{};
    for (var i = 0; i < scenes.length; i++) {
      final occ = <String, int>{};
      for (final t in tracks) {
        // 자리를 **타입만이 아니라 "같은 타입 중 몇 번째"까지** 본다. `addTrack`
        // 은 같은 타입을 몇 개든 더할 수 있는데(트랙 종류를 고르는 버튼에
        // 개수 제한이 없다), 타입만으로 키를 삼으면 두 번째 베이스 트랙이
        // 첫 번째 것의 자리를 덮어써 버린다 — 씬에 남은 사용자 패턴 하나가
        // 조용히 사라진다. 대부분(타입마다 트랙 하나)은 항상 0번째라
        // 예전과 똑같이 동작한다.
        final n = occ[t.type] = (occ[t.type] ?? -1) + 1;
        final c = scenes[i].clips[t.id];
        if (isMine(c)) out['$i:${t.type}:$n'] = c!;
      }
    }
    return out;
  }

  void _seedArray(List<SongSection> form, SongGenre g) {
    // **스타일을 바꿨다고 사용자가 만든 걸 버리면 안 된다.** 씬을 통째로 새로 만들기
    // 전에 적어 두고, 같은 자리(같은 구간·같은 종류 트랙)에 다시 실어 준다.
    // 라이브러리 판은 그대로 새 스타일 것으로 갈린다 — 그건 사용자가 만든 게 아니다.
    final mine = _mineByScene();
    if (_formTracksGenre != null) {
      for (final t in tracks) {
        t.dispose();
      }
      tracks
        ..clear()
        ..addAll([
          Track('drum'),
          Track('bass'),
          Track('chord'),
          Track('melody'),
        ]);
      _formTracksGenre = null;
    }
    // 스타일이 정해 주는 음색(록 화음 = 기타). **고른 것은 안 건드린다.**
    final wantVoice = kGenreTypeVoice[g.$1];
    for (final t in tracks) {
      if (t.type == 'drum') continue;
      final v = wantVoice?[t.type] ?? kTypeVoice[t.type];
      if (v != null && v != t.voice && _voiceIsAuto(t)) t.voice = v;
    }
    scenes
      ..clear()
      ..addAll([
        for (final s in form)
          Scene(
            s.name,
            bpm: g.$3,
            kit: g.$4,
            clips: {
              for (final t in tracks)
                t.id: switch (t.type) {
                  'drum' => s.drum,
                  'bass' => s.bass,
                  'chord' => s.chord,
                  _ => s.melody,
                },
            },
          ),
      ]);
    _seedCritters();

    keptMine = 0;
    parkedMine = 0;
    for (var i = 0; i < scenes.length; i++) {
      // 저장할 때와 **같은 규칙**으로 "같은 타입 중 몇 번째"를 다시 센다.
      final occ = <String, int>{};
      for (final t in tracks) {
        final n = occ[t.type] = (occ[t.type] ?? -1) + 1;
        final k = mine['$i:${t.type}:$n'];
        if (k == null) continue;
        // **박자가 바뀌면 안 맞는 판은 안 되살린다.** 4/4 로 만든 내 판을
        // 3/4 곡에 그대로 실으면 12칸 격자에 16칸짜리 음이 얹혀 뒤가 넘친다
        // (5단계 47/N — 왈츠를 넣으며 처음으로 이 자리가 걸렸다).
        final mySpb = t.type == 'drum' ? userDrum[k]?.spb : userNote[k]?.spb;
        if (mySpb != null && mySpb != spb) continue;
        scenes[i].clips[t.id] = k;
        keptMine++;
      }
    }
    // 새 얼개가 더 짧아 없어진 구간의 것은 되살릴 자리가 없다 — 개수만 알려 준다
    // (박자가 안 맞아 못 되살린 것도 여기 섞인다 — 둘 다 "자리가 없다"는 같은 말이다)
    parkedMine = mine.length - keptMine;

    // 배열형은 **트랙 타입이 곧 슬롯**이다(드럼·베이스·코드·멜로디) — 다만
    // 한 슬롯에 트랙이 **여럿**일 수 있다(`addTrack` 은 같은 타입을 몇 개든
    // 더할 수 있다). 예전엔 마지막 트랙 하나만 `bySlot` 에 남아서, 장르를
    // 바꾸면 두 번째 베이스 트랙은 믹스·인서트가 하나도 안 갱신되고 이전
    // 장르 값에 그대로 머물렀다.
    final bySlot = <String, List<Track>>{};
    for (final t in tracks) {
      (bySlot[t.type] ??= []).add(t);
    }

    // 장르 몫(볼륨·좌우·잔향·EQ)을 얹는다.
    //
    // **여기가 여태 비어 있었다.** 객체형(트랩·팝·재즈…)만 얹고 배열형 6종
    // (로파이·하우스·힙합·시티팝·발라드·록)은 안 얹어서, 그 여섯은 어느 스타일이든
    // 전부 vol 1.0 · pan 0 으로 똑같이 났다. 재생 경로가 버스 쪽 장르 몫을
    // `setGenreMix(null)` 로 걷어내므로(사용자 믹서를 살리려고), 트랙에 안 얹으면
    // **어디에도 안 얹힌다** — `kGenreMix` 의 그 여섯 줄이 통째로 죽어 있었다.
    _seedMix(g.$1, bySlot);
    _seedFx(g.$1, bySlot);

    _seedOrder(formOrderOf(g.$1), [for (final s in form) s.bars]);
  }

  /// 장르가 정한 믹스를 얹는다 — **손으로 맞춰 둔 트랙은 건드리지 않는다.**
  static void _seedMix(String genre, Map<String, List<Track>> bySlot) {
    final mix = kGenreMix[genre];
    if (mix == null) return;
    mix.parts.forEach((slot, spec) {
      // 슬롯 하나에 트랙이 여럿이면(같은 타입을 두 개 넣은 경우) **전부**
      // 같은 몫을 받는다 — 장르 표는 트랙 인스턴스가 아니라 슬롯 하나당
      // 값 하나만 갖고 있어서, 여럿이면 똑같이 적용하는 게 유일하게 말이 되는 규칙이다.
      for (final t in bySlot[slot] ?? const <Track>[]) {
        if (!t.mixAuto) continue;
        t.applyMix(
          spec.vol,
          spec.pan,
          spec.rev,
          spec.eqLo,
          spec.eqMid,
          spec.eqHi,
          hpf: spec.hpf ?? 20,
          lpf: spec.lpf ?? 20000,
          lfoHz: spec.lfoHz,
          lfoDepth: spec.lfoDepth,
        );
      }
    });
  }

  /// **지금 트랙 편성**에 이 장르의 믹스(볼륨·좌우·잔향·EQ)·인서트를 얹는다 —
  /// `setGenre` 안에서 배열형이 쓰는 것과 같은 몫이다. `setGenre` 는 씬·패턴까지
  /// 통째로 새로 짜므로, 씬을 손수 짜는 자리(샘플곡처럼 `genre` 필드만 바로
  /// 넣고 타임라인 레인을 직접 놓는 경우)에서는 이걸 대신 부른다 — 안 그러면
  /// 그 장르의 소리 성격(인서트·좌우·잔향)이 하나도 안 걸리고 전부 기본값
  /// (vol 1.0·pan 0·인서트 없음)으로 난다.
  void applyGenreTone() {
    final bySlot = <String, List<Track>>{};
    for (final t in tracks) {
      (bySlot[t.type] ??= []).add(t);
    }
    _seedMix(genre, bySlot);
    _seedFx(genre, bySlot);
  }

  /// 장르가 정한 인서트를 얹는다 (계획 7 · `genre_fx.dart`).
  ///
  /// **비어 있거나, 앞서 장르가 꽂아 준 것일 때만** 갈아 끼운다.
  /// 사용자가 하나라도 만진 트랙(`fxAuto == false` 이고 체인이 비지 않음)은 그대로 둔다.
  static void _seedFx(String genre, Map<String, List<Track>> bySlot) {
    bySlot.forEach((slot, ts) {
      final want = genreFxFor(genre, slot);
      for (final t in ts) {
        if (t.chain.isNotEmpty && !t.fxAuto) continue; // 사용자 것 — 손대지 않는다
        t.chain.clear();
        for (final f in want) {
          final slotFx = FxSlot(f.type);
          f.params.forEach((k, v) => slotFx.p[k] = v);
          t.chain.add(slotFx);
        }
        t.fxAuto = want.isNotEmpty;
      }
    });
  }

  /// 객체형 — 트랙을 그 곡의 편성으로 새로 만든다.
  /// 이름은 슬롯 라벨(808 베이스·패드·브라스…), 음색은 곡이 지정한 것.
  void _seedObject(ObjectSongForm form, SongGenre g) {
    // 객체형은 **편성 자체가 바뀐다**(트랩은 808·패드·브라스…). 고친 판을 아무 트랙에나
    // 얹으면 그 곡에서 중요한 파트를 밀어낸다 → 여기서는 안 되살리고 **개수만** 알린다.
    // 판 자체는 안 지운다(`userNote`/`userDrum` 에 그대로 있고 편집기 목록 맨 위에 뜬다).
    parkedMine = _mineByScene().length;
    keptMine = 0;
    _formTracksGenre = g.$1;
    for (final t in tracks) {
      t.dispose();
    }
    tracks.clear();
    final bySlot = <String, Track>{};
    for (final ot in form.tracks) {
      final t = Track(ot.type, name: kSlotLabel[ot.slot] ?? ot.slot);
      if (ot.type == 'drum') {
        t.kit = ot.voice; // 드럼은 voice 칸에 키트가 들어 있다
      } else {
        t.voice = ot.voice;
      }
      tracks.add(t);
      bySlot[ot.slot] = t;
    }
    // 이 장르의 믹스 몫(볼륨·좌우·잔향)을 트랙 초기값으로 얹는다 — 안 얹으면
    // 트랩 808 이 패드와 같은 크기로 나와서 그 장르로 안 들린다.
    //
    // 객체형은 슬롯 이름(808·패드·브라스…)이 트랙마다 유일해서(곡 표가 그렇게
    // 정의한다) `bySlot` 이 원래 1:1 이다 — `_seedMix`/`_seedFx` 는 배열형과
    // 같이 쓰느라 목록을 받으므로 여기서 한 칸짜리로 감싸 준다.
    final bySlotList = {
      for (final e in bySlot.entries) e.key: [e.value],
    };
    _seedMix(g.$1, bySlotList);
    // 인서트도 같이 — 슬롯 이름으로 찾는다(808·패드·벨은 타입이 겹친다)
    _seedFx(g.$1, bySlotList);

    scenes
      ..clear()
      ..addAll([
        for (final s in form.sections)
          Scene(
            s.name,
            bpm: g.$3,
            kit: g.$4,
            clips: {for (final e in bySlot.entries) e.value.id: s.parts[e.key]},
          ),
      ]);
    _seedCritters();
    _seedOrder(form.order, [for (final s in form.sections) s.bars]);
  }

  /// 얼개 — 구간 순서대로, 판 수는 **섹션 마디 ÷ 그 구간의 판 길이**.
  void _seedOrder(List<int> order, List<int> sectionBars) {
    song.sections
      ..clear()
      ..addAll([
        for (final si in order)
          if (si >= 0 && si < scenes.length)
            Section(si, reps: _repsFor(si, sectionBars[si])),
      ]);
    // **타임라인 트랙 줄도 비운다.** 스타일을 바꾸면 트랙도 씬도 구간도 통째로
    // 새것이다 — 옛 클립은 없는 트랙·없는 구간을 가리키게 된다(막 써 보기가
    // 잡았다). 「스타일 바꾸기」는 되돌릴 수 있으므로(`GenreUndo`) 잃지 않는다.
    song.lanes.clear();
  }

  /// 이 씬의 한 판이 몇 마디인지 — 그 씬에서 가장 긴 패턴 기준(시퀀서와 같은 규칙).
  int loopBarsOf(int sceneIndex) {
    if (sceneIndex < 0 || sceneIndex >= scenes.length) return 4;
    var m = 0;
    final s = scenes[sceneIndex];
    for (final t in tracks) {
      final b = barsOf(t.type, s.clips[t.id]);
      if (b > m) m = b;
    }
    return m <= 0 ? 4 : m;
  }

  int _repsFor(int sceneIndex, int sectionBars) {
    final lb = loopBarsOf(sceneIndex);
    final r = (sectionBars / lb).round();
    return r < 1 ? 1 : r;
  }

  // ── 내가 만든 패턴 (5단계 6/N) ──
  // 라이브러리(`patterns.dart` 의 kDrumPatterns 등)는 **읽기 전용 상수**다. 편집기는
  // 거기에 못 쓴다. 그래서 사용자가 고친 패턴은 여기 따로 담고, 찾을 때 **여기를 먼저**
  // 본다. 담는 그릇은 라이브러리와 **같은 타입**이라(DrumPatternDef/NotePatternDef)
  // 만드는 쪽 코드(buildDrumPattern 등)를 하나도 안 고쳐도 된다.
  final Map<String, DrumPatternDef> userDrum = {};
  final Map<String, NotePatternDef> userNote = {};

  /// [userNote] 의 각 이름이 **어느 트랙 타입(베이스·코드·멜로디)에서 만들어졌는가.**
  /// 이름이 없으면(=`userNote` 에는 있는데 여기 없으면) **모른다**는 뜻이다 —
  /// 이 표가 생기기 전에 저장된 옛 곡이 그렇다. 모르면 예전처럼 아무 타입에나
  /// 보여 준다(그게 그동안의 실제 동작이었다) — 새로 만드는 패턴부터 제대로 잠근다.
  ///
  /// **왜 필요한가**: `userNote` 는 베이스·코드·멜로디 세 타입이 **한 표를 같이
  /// 쓴다**(이름만으로 구분). 그래서 베이스 트랙에서 만든 패턴 이름이 코드·멜로디
  /// 트랙의 패턴 고르기에도 그대로 떴다 — 고르면 소리는 나는데(오류가 없다)
  /// 베이스의 단선율 데이터를 코드/멜로디로 잘못 해석해 음악적으로 틀린 소리가
  /// 났다(2026-09-03 워크플로 사냥에서 잡았다).
  final Map<String, String> userNoteType = {};

  DrumPatternDef? findDrum(String? n) =>
      n == null ? null : (userDrum[n] ?? findDrumPattern(n));

  NotePatternDef? findNote(String type, String? n) {
    if (n == null) return null;
    final mine = userNote[n];
    if (mine != null) {
      final ty = userNoteType[n];
      // 타입을 모르면(옛 곡) 예전처럼 통과시킨다. 알면서 다르면 — 베이스로 만든
      // 패턴을 코드 트랙이 부르는 것 — **못 찾은 것으로 친다.** 틀린 음을 내느니
      // 조용한 편이 낫다.
      if (ty == null || ty == type) return mine;
    }
    switch (type) {
      case 'bass':
        return findBassPattern(n);
      case 'chord':
        return findChordPattern(n);
      default:
        return findMelodyPattern(n);
    }
  }

  int barsOf(String type, String? name) => type == 'drum'
      ? (findDrum(name)?.bars ?? 0)
      : (findNote(type, name)?.bars ?? 0);

  /// 이 트랙이 **실제로 소리를 내는가** (5단계 51/N).
  ///
  /// 패턴 이름이 붙어 있어도 안이 비어 있으면 무음이다. 화면에는 이름만 보이니
  /// **왜 안 들리는지 알 방법이 없다** — 폰에서 드럼이 통째로 안 나는데 트랙 줄만
  /// 봐서는 멀쩡해 보였다(씬 머리글의 「타격 0개」를 보고서야 알았다).
  bool isSilent(Track t) {
    final n = t.pattern;
    if (n == null) return true;
    if (t.type == 'drum') {
      final d = findDrum(n);
      if (d == null) return true;
      for (final lane in d.hits.values) {
        if (lane.isNotEmpty) return false;
      }
      return true;
    }
    final p = findNote(t.type, n);
    return p == null || p.notes.isEmpty;
  }

  bool isMine(String? name) =>
      name != null &&
      (userDrum.containsKey(name) || userNote.containsKey(name));

  /// 편집하려면 **내 패턴이어야 한다**. 라이브러리 패턴이면 같은 내용으로 복사해서
  /// 새 이름을 준다(원본은 그대로 남는다 — 다른 씬이 쓰고 있을 수 있다).
  /// 트랙의 지금 클립을 그 복사본으로 갈아 끼우고 이름을 돌려준다.
  ///
  /// **복사본은 실제로 펼쳐야 한다.** 라이브러리 패턴은 `bars > src` 면(예: 1마디를
  /// 두 번 도는 2마디 패턴) 재생할 때 `buildDrumPattern`/`tileNoteList` 가 그 자리에서
  /// 반복해 채운다. 여기서 `src.hits`/`src.notes` 를 그대로 복사하면서 `src=bars`
  /// 라고만 표시하면 — "이미 펼쳐진 걸로 친다"는 뜻인데 실제로는 **첫 마디만** 있고
  /// 나머지는 빈 채로 저장된다. 편집기를 열자마자 뒷마디가 조용해지고, 한 번이라도
  /// 저장하면(`DrumOps.toDef`/편집기 저장도 늘 `src=bars`) 그 반복이 영영 사라진다.
  /// 그래서 **먼저 펼치고**(`tileDrumHits`/`tileNoteList`) 나서 `src=bars` 로 적는다 —
  /// 그래야 "이미 펼쳐졌다"가 사실과 맞는다.
  String makeEditable(Track t) {
    final cur = t.pattern;
    if (isMine(cur)) return cur!;
    var name = '${t.name} 내 패턴';
    var i = 2;
    while (userDrum.containsKey(name) || userNote.containsKey(name)) {
      name = '${t.name} 내 패턴 $i';
      i++;
    }
    if (t.type == 'drum') {
      final lib = findDrum(cur);
      final bars = lib?.bars ?? 2;
      // 박자는 **라이브러리 판의 것을 그대로** 들고 온다 — 내 판으로 베끼면서
      // 16칸으로 되돌리면 3/4 판이 그 자리에서 4/4 가 된다(소리는 나는데 마디가 밀린다).
      // 물려받을 판이 없으면(빈 클립) **이 곡의 지금 박자**를 쓴다 — 여기서
      // `kStepsPerBar` 를 그대로 쓰면 왈츠 곡의 빈 트랙을 고칠 때 4/4 판이 나온다.
      final spb = lib?.spb ?? this.spb;
      final (tiledHits, tiledVels) = tileDrumHits(
        lib?.hits ?? const <String, List<int>>{},
        lib?.vels,
        lib?.src ?? bars,
        bars,
        spb: spb,
      );
      userDrum[name] = DrumPatternDef(
        name,
        bars,
        bars,
        tiledHits,
        tiledVels,
        spb,
      );
    } else {
      final lib = findNote(t.type, cur);
      final bars = lib?.bars ?? 2;
      final tiled = lib == null
          ? const <List<Object?>>[]
          : tileNoteList(lib.notes, lib.src, lib.bars, spb: lib.spb);
      // **덧줄도 같이 옮긴다.** 본줄만 복사하면 라이브러리 판을 고치는 순간
      // 얹어 둔 낱음(또는 화음)이 조용히 사라진다.
      userNote[name] = NotePatternDef(
        name,
        bars,
        bars,
        [for (final n in tiled) List<Object?>.from(n)],
        also: lib == null
            ? const []
            : [
                for (final n in tileNoteList(
                  lib.also,
                  lib.src,
                  lib.bars,
                  spb: lib.spb,
                ))
                  List<Object?>.from(n),
              ],
        chromatic: lib?.chromatic ?? false,
        // 드럼과 같은 이유 — 라이브러리 판의 박자를 그대로 들고 오고,
        // 물려받을 판이 없으면 이 곡의 지금 박자를 쓴다.
        spb: lib?.spb ?? spb,
      );
      userNoteType[name] = t.type;
    }
    // 값은 지금 바꾸고, **알림은 다음 차례로 미룬다.**
    // 이 함수는 편집기가 화면을 짓는 도중(`initState`/`didUpdateWidget`)에 부른다.
    // 그 자리에서 알리면 Flutter 가 "setState() called during build" 로 막고
    // **그 알림을 통째로 버린다** — 뒤에 있던 씬 화면이 안 고쳐진다(폰에서 잡았다).
    scene.clips[t.id] = name;
    t.setPatternQuiet(name);
    scheduleMicrotask(() {
      t.ping();
      if (!_dead) notifyListeners();
    });
    return name;
  }

  /// 편집기가 고친 결과를 넣는다(같은 이름으로 덮어쓴다).
  void putUserPattern(
    String type,
    String name, {
    DrumPatternDef? drum,
    NotePatternDef? note,
  }) {
    if (type == 'drum' && drum != null) {
      userDrum[name] = drum;
    } else if (note != null) {
      userNote[name] = note;
      userNoteType[name] = type;
    }
    notifyListeners();
  }

  // ── 저장·불러오기 (5단계 8/N) ──
  // **트랙 목록을 통째로 갈아 끼운다.** 화면은 `Project` 를 구독하고 줄마다
  // `ValueKey(track.id)` 를 쓰므로, 알리기만 하면 알아서 새 목록으로 다시 그린다.

  /// 결과 손잡이(느낌) — 신남·빽빽함·그루브 (Phase 2 · 계획 4-4).
  /// 곡마다 따로 남는다. 가운데면 예전 소리 그대로다.
  Feel feel = Feel.none;

  void setFeel(Feel f) {
    feel = f;
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {
    'v': 1,
    'name': name,
    'genre': genre,
    // **4/4 가 아닐 때만** 적는다 — 없는 걸 굳이 적으면 옛 앱이 못 읽는다
    // (userDrum 의 vels·판의 spb 와 같은 규칙).
    if (meter != '4/4') 'meter': meter,
    // 없는 걸 굳이 적으면 옛 앱이 못 읽는다 — userDrum 의 vels 와 같은 규칙.
    if (duckAmountOverride != null) 'duck': duckAmountOverride,
    if (duckRelSec != 0.16) 'duckRel': duckRelSec,
    'feel': feel.toJson(),
    'cur': currentScene,
    'tracks': [for (final t in tracks) t.toJson()],
    'scenes': [for (final s in scenes) s.toJson()],
    'song': [
      for (final s in song.sections) {'scene': s.scene, 'reps': s.reps},
    ],
    // 타임라인 트랙 줄. 없는 곡이 대부분이라 **있을 때만** 적는다
    // (없는 걸 굳이 적으면 옛 앱이 못 읽는다 — userDrum 의 vels 와 같은 규칙).
    if (song.lanes.isNotEmpty)
      'lanes': [for (final c in song.lanes) c.toJson()],
    'userDrum': {
      for (final e in userDrum.entries)
        e.key: {
          'bars': e.value.bars,
          'hits': e.value.hits,
          // 세기는 만진 패턴에만 있다 — 없는 걸 굳이 적으면 옛 앱이 못 읽는다
          if (e.value.vels != null) 'vels': e.value.vels,
          // 박자도 **4/4 가 아닐 때만** 적는다(같은 규칙). 안 적으면 3/4 판이
          // 저장했다 열 때 4/4 로 되살아난다 — 소리는 나는데 마디가 밀린다.
          if (e.value.spb != kStepsPerBar) 'spb': e.value.spb,
        },
    },
    'userNote': {
      for (final e in userNote.entries)
        e.key: {
          'bars': e.value.bars,
          'notes': e.value.notes,
          // 덧줄·반음 줄은 **있을 때만** 적는다 — 없는 걸 굳이 적으면 옛 앱이 못 읽는다.
          if (e.value.also.isNotEmpty) 'also': e.value.also,
          if (e.value.chromatic) 'chro': true,
          if (e.value.spb != kStepsPerBar) 'spb': e.value.spb,
          // 없는 걸 굳이 적으면 옛 앱이 못 읽는다 — userDrum 의 vels 와 같은 규칙.
          if (userNoteType[e.key] != null) 'type': userNoteType[e.key],
        },
    },
  };

  void loadJson(Map<String, dynamic> j) {
    name = j['name'] as String? ?? '새 곡';
    genre = j['genre'] as String? ?? 'lofi';
    // 옛 파일에는 이 칸이 없다 → 4/4. 모르는 값도 4/4 로 떨어진다(`meterOf`).
    meter = meterOf(j['meter'] as String?).key;
    duckAmountOverride = (j['duck'] as num?)?.toDouble();
    duckRelSec = (j['duckRel'] as num?)?.toDouble() ?? 0.16;
    feel = Feel.fromJson(j['feel'] as Map<String, dynamic>?);

    for (final t in tracks) {
      t.dispose();
    }
    tracks
      ..clear()
      ..addAll([
        for (final t in (j['tracks'] as List))
          Track.fromJson(Map<String, dynamic>.from(t as Map)),
      ]);

    scenes
      ..clear()
      ..addAll([
        for (final s in (j['scenes'] as List))
          Scene.fromJson(Map<String, dynamic>.from(s as Map)),
      ]);
    // **캐릭터가 생기기 전에 저장한 곡**에는 하나도 없다 — 그러면 이 기능이
    // 기존 곡에서만 없는 것이 된다(정작 제일 많이 여는 곡들이다). 옛 파일일 때만
    // 채운다: 새 파일에서 비어 있는 씬은 **사용자가 일부러 뗀 것**이라 되살리면 안 된다.
    //
    // 가르는 자는 **값이 아니라 칸의 유무**다. 옛 파일에는 'critter' 라는 칸 자체가
    // 없고, 새 파일에는 값이 null 이어도 칸이 있다. 값만 보면(「하나도 없으면 옛
    // 파일」) 둘을 구별할 수 없다 — 씬이 하나뿐인 곡에서 그 하나를 떼면 늘 옛
    // 파일로 보이고, 저장했다 열 때마다 **뗀 캐릭터가 되살아난다.**
    // (주석은 「일부러 뗀 것은 안 되살린다」고 적고 있었는데 코드는 그걸 못 했다.
    //  막 써 보기가 왕복에서 잡았다 — 씬 하나짜리 하우스 곡에서 캐릭터를 떼자
    //  저장 전 null 이 저장 후 '@dancer' 로 돌아왔다)
    final hadCritterField = (j['scenes'] as List).any(
      (s) => (s as Map).containsKey('critter'),
    );
    if (!hadCritterField) _seedCritters();

    song.sections
      ..clear()
      ..addAll([
        for (final s in (j['song'] as List))
          Section((s as Map)['scene'] as int, reps: s['reps'] as int),
      ]);
    // 옛 파일에는 이 칸이 아예 없다 → 빈 목록. 있어도 **없는 구간을 가리키는 것**은
    // 버린다(구간이 줄어든 파일을 손으로 고쳤을 때 재생이 엉킨다).
    song.lanes
      ..clear()
      ..addAll([
        for (final c in (j['lanes'] as List? ?? const []))
          LaneClip.fromJson(Map<String, dynamic>.from(c as Map)),
      ]);
    song.lanes.removeWhere(
      (c) => c.section < 0 || c.section >= song.sections.length || c.bar < 0,
    );

    userDrum.clear();
    (j['userDrum'] as Map?)?.forEach((k, v) {
      final m = Map<String, dynamic>.from(v as Map);
      final vels = m['vels'] as Map?;
      userDrum[k as String] = DrumPatternDef(
        k,
        m['bars'] as int,
        m['bars'] as int,
        {
          for (final e in (m['hits'] as Map).entries)
            e.key as String: List<int>.from(e.value as List),
        },
        vels == null
            ? null
            : {
                for (final e in vels.entries)
                  e.key as String: List<int>.from(e.value as List),
              },
        // 옛 파일에는 이 칸이 없다 → 4/4(16칸). 여태와 똑같이 돈다.
        m['spb'] as int? ?? kStepsPerBar,
      );
    });

    userNote.clear();
    userNoteType.clear();
    (j['userNote'] as Map?)?.forEach((k, v) {
      final m = Map<String, dynamic>.from(v as Map);
      userNote[k as String] = NotePatternDef(
        k,
        m['bars'] as int,
        m['bars'] as int,
        [for (final n in (m['notes'] as List)) List<Object?>.from(n as List)],
        // 옛 파일에는 이 칸이 없다 → 빈 목록.
        also: [
          for (final n in (m['also'] as List? ?? const []))
            List<Object?>.from(n as List),
        ],
        chromatic: m['chro'] as bool? ?? false,
        spb: m['spb'] as int? ?? kStepsPerBar,
      );
      // 없으면(옛 파일) **모른다** — 어느 타입에나 통과시킨다(예전 동작 그대로).
      final ty = m['type'] as String?;
      if (ty != null) userNoteType[k] = ty;
    });

    _currentScene = (j['cur'] as int? ?? 0).clamp(
      0,
      scenes.isEmpty ? 0 : scenes.length - 1,
    );
    if (scenes.isNotEmpty) _loadScene(currentScene);
    notifyListeners();
  }

  /// 처음 상태로 되돌린다(트랙까지 전부 새로). 저장된 것도 같이 지우려면 부른 쪽에서.
  ///
  /// **참고 — 아직 `Project.blank()` 와 다르다.** 여기는 여전히
  /// `setGenre('lofi')` 로 미리 채운다("내 곡 ▸ 새 곡"·"지금 곡 처음으로"가
  /// 이걸 쓴다). 앱을 처음 켤 때(`main.dart`)만 빈 캔버스다. 이 둘을
  /// 맞추려면 `scene_check_test.dart`(22번)·`store_check_test.dart`(220·231
  /// 번 — lofi 장르 기본값에 기대는 시험들)를 같이 고쳐야 해서, 이번
  /// 홈 화면 작업 범위 밖으로 남겨 둔다.
  void reset({String? newName}) {
    name = newName ?? '새 곡';
    for (final t in tracks) {
      t.dispose();
    }
    tracks
      ..clear()
      ..addAll([Track('drum'), Track('bass'), Track('chord'), Track('melody')]);
    userDrum.clear();
    userNote.clear();
    userNoteType.clear();
    setGenre('lofi');
  }

  Scene get scene => scenes[currentScene.clamp(0, scenes.length - 1)];

  /// 씬의 클립을 트랙에 싣는다(소리는 안 건드린다 — 부른 쪽이 루프를 새로 보낸다).
  void _loadScene(int i) {
    _currentScene = i.clamp(0, scenes.length - 1);
    final s = scenes[currentScene];
    for (final t in tracks) {
      t.pattern = s.clips[t.id];
      if (t.type == 'drum' && s.kit != null) t.kit = s.kit!;
    }
  }

  /// 씬 전환. 재생 중이면 부른 쪽이 `refreshLoop` 로 다음 판부터 반영한다.
  void launchScene(int i) {
    _loadScene(i);
    notifyListeners();
  }

  /// 지금 씬의 클립을 바꾼다. **트랙과 씬 양쪽에 쓴다** — 한쪽만 쓰면
  /// 씬을 갔다 오는 순간 방금 고른 게 사라진다.
  void setClip(Track t, String? pattern) {
    scene.clips[t.id] = pattern;
    t.pattern = pattern;
  }

  /// 드럼 키트도 씬에 남긴다(씬마다 키트가 다르다).
  void setKit(Track t, String kit) {
    t.kit = kit;
    scene.kit = kit;
  }

  /// 빠르기도 **씬에 같이 남긴다** — 클립·키트와 같은 짝이다.
  ///
  /// [Transport] 에만 쓰면 씬 칩을 한 번 타는 순간 `_launch` 가 그 씬이 들고 있던
  /// 옛 템포로 되돌린다. 사용자는 슬라이더를 옮겨 놓고 씬을 한 번 눌렀을 뿐인데
  /// 빠르기가 말없이 제자리로 간다 — 「눌렀더니 사라졌다」는 고장으로 보인다.
  void setBpm(Transport tr, double v) {
    tr.bpm = v;
    scene.bpm = v;
  }

  /// 구간을 하나 더 만든다 — **지금 구간을 복제**한다.
  /// (예전엔 다른 장르 프리셋을 붙였는데, 곡 하나가 여러 장르를 오가는 건 곡이 아니다)
  void addScene() {
    // 캐릭터까지 그대로 베끼면 **똑같은 것 둘**이 된다 — 구별하라고 붙이는 것인데
    // 구별이 안 된다. 아직 안 쓴 것 하나를 골라 준다.
    scenes.add(scene.copyWith('${scene.name} 2')..critter = _freshCritter());
    notifyListeners();
  }

  /// 아직 아무 씬도 안 쓴 캐릭터 하나. 다 썼으면 처음부터 돌린다.
  String _freshCritter() {
    final used = {for (final s in scenes) s.critter};
    for (final id in kDefaultCritters) {
      if (!used.contains(id)) return id;
    }
    return kDefaultCritters[scenes.length % kDefaultCritters.length];
  }

  /// 장르가 씬을 통째로 새로 깔았을 때 캐릭터를 순서대로 붙인다.
  void _seedCritters() {
    for (var i = 0; i < scenes.length; i++) {
      scenes[i].critter = kDefaultCritters[i % kDefaultCritters.length];
    }
  }

  /// 씬을 복제해 **바로 뒤에** 끼운다.
  ///
  /// 끼우면 **뒤쪽 씬들의 번호가 하나씩 밀린다.** 여태 그걸 아무도 안 고쳤다:
  ///  · 곡 구간이 번호로 씬을 가리키므로 **곡이 통째로 어긋났다** —
  ///    「인트로·벌스·코러스·브레이크」가 「인트로·인트로 복사·벌스·코러스」가 됐다.
  ///    브레이크가 곡에서 사라지고 복사본이 끼어든다. 오류는 안 난다.
  ///  · 보고 있던 씬 번호도 밀려서, 트랙에는 브레이크가 실려 있는데
  ///    씬 바는 코러스를 가리켰다.
  /// 지우는 쪽([removeScene])은 처음부터 [Arrangement.onSceneRemoved] 로
  /// 이걸 하고 있었다 — **끼우는 쪽만 짝이 없었다.**
  void duplicateScene(int i) {
    if (i < 0 || i >= scenes.length) return;
    scenes.insert(i + 1, scenes[i].copyWith('${scenes[i].name} 복사'));
    song.onSceneInserted(i + 1);
    if (_currentScene > i) _currentScene++;
    notifyListeners();
  }

  /// 씬을 지운다 — **되돌릴 거리를 들고 나온다.**
  ///
  /// 씬 하나에 트랙 전부의 패턴이 들어 있고, 게다가 지우면
  /// [Arrangement.onSceneRemoved] 가 **그 씬을 쓰던 곡 구간까지 같이 지운다.**
  /// 여태 이걸 확인 한 번 없이 「⋮ → 삭제」 한 번에 했다 — 곡 절반이 날아가도
  /// 되돌릴 방법이 없었다. 씬·자리·구간표·열려 있던 씬을 통째로 들고 나온다.
  RemovedScene? removeScene(int i) {
    if (scenes.length <= 1 || i < 0 || i >= scenes.length) return null;
    final keep = RemovedScene(
      scene: scenes[i],
      at: i,
      // 구간은 **깊게** 복사한다 — onSceneRemoved 가 남은 것들의 번호를
      // 그 자리에서 내리므로, 얕게 들고 있으면 되돌릴 때 이미 어긋나 있다.
      sections: [for (final s in song.sections) Section(s.scene, reps: s.reps)],
      lanes: [for (final c in song.lanes) c.copy()],
      wasCurrent: currentScene,
    );
    scenes.removeAt(i);
    song.onSceneRemoved(i);
    // 지운 자리가 **보고 있던 자리보다 앞이면** 뒤엣것들이 한 칸씩 당겨 온다 —
    // `duplicateScene` 의 `if (_currentScene > i) _currentScene++;` 과 정확히
    // 반대 방향 짝이다. 이게 없으면 씬을 지운 뒤에도 번호만 그대로 남아
    // **엉뚱한 씬**을 가리켰다(폭에 안 걸리면 조용히 넘어간다 — 안 걸리는 경우가
    // 더 흔하다).
    if (i < _currentScene) _currentScene--;
    if (_currentScene >= scenes.length) _currentScene = scenes.length - 1;
    _loadScene(currentScene);
    notifyListeners();
    return keep;
  }

  /// [removeScene] 을 되돌린다 — 씬도, 그 씬을 쓰던 곡 구간도, 보던 자리도.
  void undoRemoveScene(RemovedScene r) {
    if (scenes.contains(r.scene)) return; // 이미 돌아와 있다
    scenes.insert(r.at.clamp(0, scenes.length), r.scene);
    song.restore(r.sections, r.lanes);
    _currentScene = r.wasCurrent.clamp(0, scenes.length - 1);
    _loadScene(currentScene);
    notifyListeners();
  }

  void renameScene(int i, String name) {
    scenes[i].name = name;
    notifyListeners();
  }

  /// 지금 씬의 **코드 진행**을 읽는다 — 코드 트랙이 없거나 안 치면 빈 목록.
  ///
  /// 돌려주는 `steps` 는 코드 패턴 전체 칸 수다(따라 옮길 때 다시 쓴다).
  (List<ProgSlot>, int) readSceneProg() {
    final t = _chordTrack();
    if (t == null) return (const [], 0);
    final def = findNote('chord', t.pattern);
    if (def == null) return (const [], 0);
    final notes = tileNoteList(def.notes, def.src, def.bars, spb: def.spb);
    final steps = def.bars * def.spb;
    return (readProg(notes, steps, meter: meterDef), steps);
  }

  Track? _chordTrack() {
    for (final t in tracks) {
      if (t.type == 'chord' && t.pattern != null) return t;
    }
    return null;
  }

  /// 코드 자리 하나를 [to] 로 바꾸고 **베이스·멜로디를 같은 만큼 옮긴다.**
  ///
  /// 바뀐 것이 없으면 null. 돌려주는 것은 **되돌리기 표**다 — 씬 지우기와 같은
  /// 방식으로 맞춘다(확인 창 대신 되돌리기).
  /// [mode] 는 지금 곡의 조성('minor'/'major') — **반음 줄 판을 옮길 때** 필요하다
  /// (도수 3이 몇 반음인지는 조성이 정한다).
  ProgUndo? changeChord(ProgSlot slot, int to, {String mode = 'minor'}) {
    final ct = _chordTrack();
    if (ct == null) return null;
    final delta = progDelta(slot.degree, to);

    final undo = ProgUndo({}, {});
    void keep(String name) {
      if (undo.notes.containsKey(name)) return;
      final d = userNote[name];
      if (d == null) return;
      undo.notes[name] = NotePatternDef(
        name,
        d.bars,
        d.src,
        [for (final n in d.notes) List<Object?>.from(n)],
        also: [for (final n in d.also) List<Object?>.from(n)],
        chromatic: d.chromatic,
      );
    }

    // 코드 트랙 — 라이브러리 패턴이면 여기서 내 것으로 복사된다.
    // **적어 두는 것이 먼저다** — `makeEditable` 이 `scene.clips` 를 그 자리에서
    // 갈아 끼우므로, 뒤에 적으면 새 이름을 옛 이름이라고 적게 된다.
    undo.clips[ct.id] = scene.clips[ct.id];
    final cname = makeEditable(ct);
    keep(cname);
    final cdef = userNote[cname]!;
    final cbars = cdef.bars;
    final csteps = cbars * cdef.spb;
    // **바꿀 것만 적는다**(`copyWith`) — 덧줄·반음 줄 깃발을 손으로 옮기다 보면
    // 언젠가 한 번 빠뜨린다. 코드를 바꾼다고 버릴 뜻이 아니다.
    userNote[cname] = cdef.copyWith(
      bars: cbars,
      src: cbars,
      notes: setProg(cdef.notes, slot, to),
    );

    // 따라가는 트랙 — 베이스·멜로디. 코드만 바뀌고 이것들이 그대로면
    // **그 구간만 어긋난 채** 돈다(이 기능이 있는 이유가 바로 그것이다).
    if (delta != 0) {
      for (final t in tracks) {
        if (t.type != 'bass' && t.type != 'melody') continue;
        if (t.pattern == null) continue;
        undo.clips[t.id] = scene.clips[t.id];
        final fname = makeEditable(t);
        keep(fname);
        final fdef = userNote[fname]!;
        var notes = fdef.notes;
        var fbars = fdef.bars;
        // 짧으면 **먼저 펼친다.** 안 그러면 한 마디가 두 코드에 같이 쓰여서,
        // 한쪽을 맞추는 순간 다른 쪽이 어긋난다.
        if (fbars < cbars) {
          if (cbars % fbars != 0) continue; // 3마디 대 4마디 같은 것 — 손대지 않는다
          notes = tileNoteList(notes, fbars, cbars, spb: fdef.spb);
          fbars = cbars;
        }
        // 길면 코드가 **되풀이된다** — 되풀이되는 자리마다 같이 옮긴다.
        final fsteps = fbars * fdef.spb;
        // 반음 줄(프로 모드) 판은 **반음으로** 옮긴다 — 도수만큼 옮기면
        // 3도 올리려다 3반음만 올라가 화성이 어긋난다.
        final semi = progSemiDelta(slot.degree, to, mode);
        for (var off = 0; off < fsteps; off += csteps) {
          notes = followProg(
            notes,
            ProgSlot(
              slot.degree,
              slot.step + off,
              slot.untilStep + off,
              meter: slot.meter,
            ),
            delta,
            chromatic: fdef.chromatic,
            semiDelta: semi,
          );
        }
        userNote[fname] = fdef.copyWith(bars: fbars, src: fbars, notes: notes);
      }
    }
    notifyListeners();
    return undo;
  }

  /// [changeChord] 를 되돌린다.
  void undoChangeChord(ProgUndo u) {
    for (final e in u.notes.entries) {
      userNote[e.key] = e.value;
    }
    for (final e in u.clips.entries) {
      if (e.value != null) scene.clips[e.key] = e.value;
    }
    _loadScene(currentScene);
    notifyListeners();
  }

  /// 씬에 붙은 캐릭터를 바꾼다. `null` 이면 뗀다.
  void setSceneCritter(int i, String? v) {
    if (i < 0 || i >= scenes.length) return;
    scenes[i].critter = (v == null || v.isEmpty) ? null : v;
    notifyListeners();
  }

  /// 이 트랙이 실제로 들리는가 — 웹 `audible()` 그대로.
  /// **솔로가 하나라도 켜져 있으면 솔로인 트랙만** 들린다(뮤트는 항상 이긴다).
  bool audible(Track t) {
    final anySolo = tracks.any((x) => x.solo);
    return anySolo ? (t.solo && !t.mute) : !t.mute;
  }

  /// 악기를 하나 더한다. [voice] 를 주면 그 음색으로 만든다
  /// (「악기 추가」가 이 길로 온다 — 사람은 종류가 아니라 악기를 고른다).
  void addTrack(String type, {String? voice}) {
    final t = Track(type);
    if (voice != null && voice.isNotEmpty) t.voice = voice;
    tracks.add(t);
    // 새 트랙은 **모든 씬에** 기본 패턴으로 들어간다. 안 그러면 트랙을 만든 뒤
    // 다른 씬으로 갔을 때 그 트랙만 조용해서 고장처럼 보인다.
    //
    // **박자가 4/4 가 아니면 로파이 기본값을 안 쓴다.** `kDefaultPattern` 은
    // 전부 4/4 판이라, 왈츠 곡에 트랙을 더하면 12칸 격자에 16칸짜리 판이
    // 실려 뒤가 넘친다 — 지금 스타일의 대표 패턴(제 박자를 든다)을 쓴다.
    final fallback = meterDef.isFour
        ? kDefaultPattern[type]
        : _genreDefaultPattern(type);
    for (final s in scenes) {
      s.clips[t.id] ??= fallback;
    }
    t.pattern = scene.clips[t.id];
    // 드럼이면 **지금 씬의 키트**를 따른다. 안 그러면 새로 만든 드럼만 어쿠스틱으로
    // 나서, 록 곡에 어쿠스틱 드럼이 하나 더 붙는다. 게다가 저장했다 열면
    // `_loadScene` 이 씬 키트를 얹으므로 **그때 소리가 바뀐다** —
    // 「어제는 이 소리가 아니었는데」가 여기서 나온다.
    if (type == 'drum' && scene.kit != null) t.kit = scene.kit!;
    notifyListeners();
  }

  /// 라이브에서 친 걸 담을 트랙을 찾거나 만든다 (5단계 14/N).
  ///
  /// **다른 씬에는 클립을 안 넣는다** — `addTrack` 은 모든 씬에 기본 패턴을 채우는데
  /// (트랙만 만들고 다른 씬에 갔을 때 조용하면 고장처럼 보이니까), 라이브 트랙은
  /// 그러면 안 된다. 인트로에서 친 걸 코러스에서도 되풀이하면 곡이 아니라 사고다.
  Track ensureLiveTrack(String voice) {
    for (final t in tracks) {
      if (t.type == 'melody' && t.name == kLiveTrackName) {
        t.voice = voice;
        return t;
      }
    }
    final t = Track('melody', name: kLiveTrackName);
    t.voice = voice;
    tracks.add(t);
    for (final s in scenes) {
      s.clips[t.id] = null; // 친 씬에서만 소리가 난다
    }
    t.pattern = null;
    notifyListeners();
    return t;
  }

  /// 트랙을 지운다 — **되돌릴 거리를 들고 나온다.**
  ///
  /// 이 앱에서 제일 많이 잃는 한 번의 손짓이다. 트랙 하나에는
  /// **모든 씬의 클립**이 달려 있으므로, 곡 전체에서 그 악기가 통째로 사라진다.
  /// 곡([Store.remove])도 씬([removeScene])도 되돌릴 수 있는데 트랙만 없었다 —
  /// 그래서 대화상자에 「되돌릴 수 없어요」라고 적어 두는 것으로 때웠다.
  /// 경고는 되돌리기의 대신이 아니다.
  ///
  /// **여기서는 `dispose()` 하지 않는다.** 되돌릴 수 있어야 하니 살려 둔다.
  /// 정말 안 쓰게 되면 [RemovedTrack.drop] 이 치운다(되돌리기 알림이 사라질 때).
  RemovedTrack? removeTrack(Track t) {
    if (tracks.length <= 1) return null; // 마지막 하나는 남긴다
    final at = tracks.indexOf(t);
    if (at < 0) return null;
    // 씬을 **객체로** 붙잡는다 — 되돌리기 전에 씬이 지워지거나 순서가 바뀔 수 있어서
    // 번호로 들고 있으면 엉뚱한 씬에 클립이 돌아간다.
    final clips = <Scene, String?>{
      for (final s in scenes)
        if (s.clips.containsKey(t.id)) s: s.clips[t.id],
    };
    // **타임라인 트랙 줄도 같이 걷는다.** 안 걷으면 없는 악기를 가리키는 클립이
    // 남는다 — 화면에는 그 줄이 아예 없으니 지울 길도 없다(막 써 보기가 잡았다).
    final lanes = [
      for (final c in song.lanes)
        if (c.trackId == t.id) c,
    ];
    song.lanes.removeWhere((c) => c.trackId == t.id);
    tracks.remove(t);
    for (final s in scenes) {
      s.clips.remove(t.id);
    }
    notifyListeners();
    return RemovedTrack(track: t, at: at, clips: clips, lanes: lanes);
  }

  /// [removeTrack] 을 되돌린다 — 트랙도, 씬마다 실려 있던 클립도, 있던 자리도.
  void undoRemoveTrack(RemovedTrack r) {
    if (tracks.any((x) => x.id == r.track.id)) return; // 이미 돌아와 있다
    tracks.insert(r.at.clamp(0, tracks.length), r.track);
    for (final e in r.clips.entries) {
      // 그 사이에 지워진 씬에는 안 되돌린다
      if (scenes.contains(e.key)) e.key.clips[r.track.id] = e.value;
    }
    // 타임라인 줄도 같이 돌아온다. 그 사이에 구간이 줄었으면 **버린다** —
    // 없는 구간을 가리키면 그때부터 소리가 엉킨다.
    for (final c in r.lanes) {
      if (c.section >= 0 && c.section < song.sections.length) song.lanes.add(c);
    }
    // 지금 보고 있는 씬의 클립을 트랙에 다시 실어 준다 — 안 하면 되돌린 트랙이
    // 이름만 돌아오고 **아무것도 안 친다.**
    _loadScene(currentScene);
    notifyListeners();
  }

  void moveTrack(int from, int to) {
    if (from == to || from < 0 || to < 0) return;
    if (from >= tracks.length || to >= tracks.length) return;
    tracks.insert(to, tracks.removeAt(from));
    notifyListeners();
  }
}

/// 자동 레벨 밸런스 + 사이드체인 덕킹 — 웹 `MIX`.
/// duckAmt: 킥이 올 때 베이스·패드를 얼마나 눌러줄지(0~0.9).
/// 하우스·EDM 은 이게 클수록 장르감이 산다.
class MixSettings extends ChangeNotifier {
  bool _auto = true, _duck = true;
  double _duckAmt = 0.58;

  bool get auto => _auto;
  set auto(bool v) {
    _auto = v;
    notifyListeners();
  }

  bool get duck => _duck;
  set duck(bool v) {
    _duck = v;
    notifyListeners();
  }

  double get duckAmt => _duckAmt;
  set duckAmt(double v) {
    _duckAmt = v;
    notifyListeners();
  }
}

/// 박자표 — 웹 `METERS`. 마디당 스텝 수 = 분자 × (16/분모).
const Map<String, List<int>> kMeters = {
  '4/4': [4, 4],
  '3/4': [3, 4],
  '6/8': [6, 8],
  '12/8': [12, 8],
  '2/4': [2, 4],
};

/// 앱 설정 — 웹 `SETTINGS`.
class AppSettings extends ChangeNotifier {
  String theme = 'pro';
  String layout = 'h';
  String grid = '16';
  String noteName = 'abs';
  bool pro = false;
  String meter = '4/4';
  String quality = 'normal';

  /// 한 마디의 스텝 수 — 웹 `meterSteps()`.
  int get stepsPerBar {
    final m = kMeters[meter] ?? kMeters['4/4']!;
    return (m[0] * (16 / m[1])).round();
  }

  int get beatsPerBar => (kMeters[meter] ?? kMeters['4/4']!)[0];
  int get stepsPerBeat {
    final s = stepsPerBar ~/ beatsPerBar;
    return s < 1 ? 1 : s;
  }

  void set(void Function() f) {
    f();
    notifyListeners();
  }
}
