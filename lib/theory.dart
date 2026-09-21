// 4단계 2/N — 스케일·조·코드 시스템 이식 (베이스/코드/멜로디 패턴 재생의 전제조건).
//
// 웹의 `SCALE`/`KEY`/`CHORD_TYPES`/`TENSIONS`/`applyKey()`/`chordFreqsOf()`/`degRow()`
// (app.html:1566~1699 근방)을 그대로 옮겼다. 값은 손대지 않았다.
//
// 웹은 이걸 두 갈래로 쓴다:
//   1) 일반 모드 — 화면에 보이는 줄(ROW, 0~14)이 곧 스케일 음이다. `degRow()`는 그냥
//      범위를 clamp 할 뿐이고, 실제 음높이는 `BASS_F`/`LEAD_F` 배열(스케일 순서로 미리
//      계산해 둔 주파수 표)에서 그 줄 번호로 찾는다.
//   2) 프로 모드 — 줄이 반음 단위(크로매틱)라 `degRow()`가 실제 변환을 한다.
// 우리 엔진은 아직 피아노롤 UI가 없어서(5단계) "그 줄에 실제로 어떤 소리가 나는가"만
// 있으면 된다 — 그래서 `BASS_F`/`LEAD_F` 배열을 만들지 않고, [degreeFreq]가 그 자리에서
// 직접 계산한다(로직은 웹 `applyKey()`의 non-PRO 분기와 완전히 같다). 프로 모드(크로매틱)는
// 옮기지 않았다 — 5단계 UI 작업에서 피아노롤이 생길 때 같이 볼 것.

import 'dart:math' as math;

/// 스케일 — 웹 `SCALE` 그대로. 반음 오프셋(도=0).
const Map<String, List<int>> kScale = {
  'minor': [0, 2, 3, 5, 7, 8, 10],
  'major': [0, 2, 4, 5, 7, 9, 11],
};

/// 조 이름 → 스케일. **모르는 이름이면 단조로 본다.**
///
/// `kScale[mode]!` 를 그대로 쓰면 저장 파일에 이상한 조가 하나 들어 있는 것만으로
/// **앱이 곡을 열 때마다 터진다.** 그 곡이 마지막에 열던 곡이면 앱 자체가 안 뜬다.
/// 파일이 앱을 못 죽이게 하는 게 먼저다 — 잘못된 조는 소리가 조금 다를 뿐이지만
/// 터지는 것은 아무것도 못 하게 만든다.
List<int> scaleOf(String mode) => kScale[mode] ?? kScale['minor']!;

/// 다이아토닉 7화음 전부 도수 — 웹 `TRIAD_DEGS`.
const List<int> kTriadDegs = [0, 1, 2, 3, 4, 5, 6];

/// 코드 타입 → 루트 기준 반음 오프셋 — 웹 `CHORD_TYPES` 그대로(재즈 코드 포함).
const Map<String, List<int>> kChordTypeIntervals = {
  'maj': [0, 4, 7],
  'min': [0, 3, 7],
  // **파워코드** — 3음이 없다(뿌리 + 5도 + 옥타브). 장·단이 안 정해지므로
  // 배음이 뭉치지 않고, 그래서 왜곡 건 기타에서 유일하게 안 지저분한 화음이다.
  // 록 기타가 이걸 치는 이유이자, 3음을 넣으면 그 자리에서 록이 아니게 되는 이유.
  'five': [0, 7, 12],
  'dom7': [0, 4, 7, 10],
  'maj7': [0, 4, 7, 11],
  'min7': [0, 3, 7, 10],
  'm7b5': [0, 3, 6, 10],
  'dim': [0, 3, 6],
  'dim7': [0, 3, 6, 9],
  'aug': [0, 4, 8],
  'sus2': [0, 2, 7],
  'sus4': [0, 5, 7],
  'six': [0, 4, 7, 9],
  'm6': [0, 3, 7, 9],
  'add9': [0, 4, 7, 14],
  'sixnine': [0, 4, 7, 9, 14],
  'sus47': [0, 5, 7, 10],
  'maj9': [0, 4, 7, 11, 14],
  'min9': [0, 3, 7, 10, 14],
  'mMaj7': [0, 3, 7, 11],
  'aug7': [0, 4, 8, 10],
  'dom7b5': [0, 4, 6, 10],
  'dom9': [0, 4, 7, 10, 14],
  'dom13': [0, 4, 7, 10, 14, 21],
  'min11': [0, 3, 7, 10, 14, 17],
};

/// 코드 칸(노트의 5번째)에 적는 **한 줄 글자** — 종류·텐션·슬래시 베이스를 담는다.
///
/// 자리를 새로 만들지 않고 **이미 있는 칸**을 쓴다. 그 칸은 처음부터 글자였고
/// (`'min7'`), 여기에 규칙만 얹었다:
///
///   `min7`          종류만
///   `min7+t9`       텐션 하나
///   `min7+t9+t11`   텐션 둘
///   `maj7/4`        4도를 밑에 깐 슬래시 코드
///   `min7+t9/2`     둘 다
///
/// 칸을 늘리지 않으니 **저장 형식이 그대로**다 — 옛 파일도, 옛 앱도 그냥 읽는다
/// (모르는 글자는 종류 표에서 못 찾아 `maj` 로 떨어질 뿐이다).
///
/// 슬래시 베이스는 **절대 음이 아니라 도수**(0~6)다. 조를 바꾸면 같이 옮겨 간다.
({String type, List<String> tensions, int? bassDegree}) parseChordText(
  String? text,
) {
  if (text == null || text.isEmpty) {
    return (type: '', tensions: const [], bassDegree: null);
  }
  var body = text;
  int? bass;
  final slash = body.indexOf('/');
  if (slash >= 0) {
    bass = int.tryParse(body.substring(slash + 1));
    if (bass != null) bass = ((bass % 7) + 7) % 7;
    body = body.substring(0, slash);
  }
  final parts = body.split('+');
  return (
    type: parts.first,
    tensions: [
      for (final t in parts.skip(1))
        if (kTensionSemi.containsKey(t)) t,
    ],
    bassDegree: bass,
  );
}

/// [parseChordText] 의 짝. 아무것도 없으면 null 을 돌려준다(칸을 비운다).
String? buildChordText(String? type, List<String> tensions, int? bassDegree) {
  if ((type == null || type.isEmpty) &&
      tensions.isEmpty &&
      bassDegree == null) {
    return null;
  }
  final base = (type == null || type.isEmpty) ? '' : type;
  final buf = StringBuffer(base);
  for (final t in tensions) {
    buf.write('+$t');
  }
  if (bassDegree != null) buf.write('/$bassDegree');
  return buf.toString();
}

/// 텐션 이름표 — 서랍에 적는 말.
const Map<String, String> kTensionLabel = {'t9': '9', 't11': '11', 't13': '13'};

/// **스타일이 정해 주는 코드 종류** — 지금은 록 기타의 파워코드 하나뿐이다.
///
/// 스타일만 보지 않고 **음색을 같이 본다.** 록이어도 피아노가 화음을 맡으면
/// 3음이 있어야 한다 — 파워코드는 「록의 소리」가 아니라 **기타의 손 모양**이다.
/// (왜곡을 걸면 3음의 배음이 5도와 맥놀이를 일으켜 지저분해진다. 그래서 록 기타는
///  3음을 뺀다 — 뺀 자리는 베이스와 보컬이 채운다.)
///
/// 음에 종류를 **직접 적어 둔 것은 안 건드린다**(`buildChordPattern` 의 `plainType`).
String? genreChordType(String genre, String voice) {
  if (genre != 'rock') return null;
  return (voice == 'guitar' || voice == 'nylon') ? 'five' : null;
}

/// 코드 종류 → **악보에 적는 꼬리표**. `Am7` 의 `m7` 자리다.
///
/// 화면에는 종류 키(`min7`)가 아니라 **사람이 아는 코드 이름**이 떠야 한다 —
/// 「min7 로 바꾸시겠어요」는 아무 뜻이 없고 「Am7」 은 바로 안다.
const Map<String, String> kChordSuffix = {
  'maj': '',
  'min': 'm',
  'five': '5', // 파워코드 — 악보에 `C5` 라고 적는다

  'dom7': '7',
  'maj7': 'M7',
  'min7': 'm7',
  'm7b5': 'm7♭5',
  'dim': 'dim',
  'dim7': 'dim7',
  'aug': 'aug',
  'sus2': 'sus2',
  'sus4': 'sus4',
  'six': '6',
  'm6': 'm6',
  'add9': 'add9',
  'sixnine': '6/9',
  'sus47': '7sus4',
  'maj9': 'M9',
  'min9': 'm9',
  'mMaj7': 'mM7',
  'aug7': 'aug7',
  'dom7b5': '7♭5',
  'dom9': '9',
  'dom13': '13',
  'min11': 'm11',
};

/// 코드 서랍에 내놓는 묶음 — (묶음 이름, 종류 키들).
///
/// 스물넷을 한 줄로 늘어놓으면 고를 수가 없다. **무엇을 하고 싶은가**로 묶는다:
/// 셋만 쌓은 것 / 하나 더 얹은 것(7화음) / 달콤한 것 / 색이 진한 것.
const List<(String, List<String>)> kChordGroups = [
  ('기본 (세 음)', ['maj', 'min', 'five', 'sus4', 'sus2', 'dim', 'aug']),
  ('7화음', ['dom7', 'maj7', 'min7', 'm7b5', 'dim7', 'mMaj7', 'sus47']),
  ('달콤한 것', ['six', 'm6', 'add9', 'sixnine']),
  ('색이 진한 것', ['maj9', 'min9', 'dom9', 'dom13', 'min11', 'aug7', 'dom7b5']),
];

/// 텐션(덧붙이는 색깔 음) — 웹 `TENSIONS`. 지금 옮긴 패턴 데이터엔 안 쓰이지만
/// [ChordSpec.tensions]/[chordFreqsOf] 가 참조할 수 있게 표만 같이 옮겨 둔다.
const Map<String, int> kTensionSemi = {
  't9': 14,
  't11': 17,
  't13': 21,
  'tb9': 13,
  'ts9': 15,
  'ts11': 18,
  'tb13': 20,
};

/// 베이스 기준음 C1(24) — 웹 `BASS_BASE`. 예전 C2(36)에서 한 옥타브 내린 값
/// (808/베이스기타 실제 음역에 맞춘 것 — 웹 HANDOFF 참고).
const int kBassBase = 24;

double _mfreq(int midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

/// 조(調) — 12키(0=C) + 장/단조. 웹 `KEY` 그대로(기본값 C단조).
class MusicKey {
  final int root; // 0~11, C=0
  final String mode; // 'minor' | 'major'
  const MusicKey({this.root = 0, this.mode = 'minor'});
}

/// 코드 스펙 — 웹 코드 note 의 `ch` 객체(`{r,t,x,b}`) 대응.
class ChordSpec {
  final int root; // pitch class 0~11 (C 기준)
  final String type; // kChordTypeIntervals 키
  final List<String> tensions; // kTensionSemi 키 목록
  final int? bass; // 슬래시 코드 베이스 (MIDI 노트 번호 오프셋), null=없음
  const ChordSpec({
    required this.root,
    required this.type,
    this.tensions = const [],
    this.bass,
  });
}

/// MIDI 번호 → 주파수. [chordMidiOf] 로 자리를 잡은 뒤 소리로 바꿀 때 쓴다.
double midiFreq(int midi) => _mfreq(midi);

/// 코드 스펙 → **MIDI 노트 번호** 목록 — 웹 `chordFreqsOf()` 와 같은 자리.
/// (코드톤은 미드 레지스터 60=C4 기준, 슬래시 베이스는 한 옥타브 아래 48=C3 기준)
List<int> chordMidiOf(ChordSpec spec) {
  final semis = List<int>.from(
    kChordTypeIntervals[spec.type] ?? kChordTypeIntervals['maj']!,
  );
  for (final tk in spec.tensions) {
    final sm = kTensionSemi[tk];
    if (sm != null && !semis.contains(sm)) semis.add(sm);
  }
  final out = semis.map((sm) => 60 + spec.root + sm).toList();
  if (spec.bass != null) out.insert(0, 48 + spec.bass!);
  return out;
}

/// 코드 스펙 → 주파수 목록 — 웹 `chordFreqsOf()` 그대로.
List<double> chordFreqsOf(ChordSpec spec) => [
  for (final m in chordMidiOf(spec)) _mfreq(m),
];

// ── 기타 보이싱 — 실제 손 모양(바레 코드) ──
//
// 여태는 기타도 다른 코드 악기와 똑같이 [chordMidiOf]+[voiceLead] 를 썼다 —
// 한 옥타브 띠 안에 코드톤을 촘촘히 쌓는 방식(피아노·패드에는 맞다). 그런데
// 기타는 **손 모양이 정해져 있다**: 6줄에 걸쳐 두 옥타브 가까이 퍼지고, 근음·
// 5도가 두 번씩 겹친다(예: 오픈 E장조 = E-B-e-G#-b-e'). 그 모양을 조 옮김
// 없이 프렛만 밀어 올리면 어느 조에서나 똑같이 친다 — **바레 코드**다.
//
// [voiceLead] 는 안 쓴다 — 진행 중 자리바꿈으로 움직임을 줄이는 것은 건반
// 손가락의 버릇이지, 기타는 코드마다 **같은 모양을 프렛만 옮겨** 짚는다.
//
// 근음은 6번줄(낮은 E, MIDI 40) 기준 프렛 자리에 놓는다 — E 코드면 개방현
// (프렛 0), F면 1프렛… 이렇게 두면 실제 바레 코드가 짚는 자리 그대로 나온다.
const int kGuitarLowE = 40; // 6번줄 개방현(낮은 E2)
const int _kEPc = 4; // E 의 음이름 번호(C=0 기준)

/// 코드 종류 → 근음에서부터의 반음 오프셋(바레 코드 손 모양, 낮은 음 순).
/// 여기 없는 종류(9화음 등 손 모양이 복잡한 것)는 [chordMidiOf] 로 되돌아간다.
const Map<String, List<int>> kGuitarChordShape = {
  'maj': [0, 7, 12, 16, 19, 24], // 오픈 E장조 모양
  'min': [0, 7, 12, 15, 19, 24], // 오픈 E단조 모양
  'five': [0, 7, 12], // 파워코드
  'dom7': [0, 7, 10, 16, 19], // E7 모양
  'min7': [0, 7, 10, 15], // Em7 모양
  'maj7': [0, 7, 11, 16], // Emaj7 모양(압축)
  'sus4': [0, 5, 7, 12],
  'sus2': [0, 2, 7, 12],
  'dim': [0, 6, 12, 15],
  'aug': [0, 4, 8, 12],
  'six': [0, 7, 9, 16],
  'm6': [0, 7, 9, 15],
  'add9': [0, 7, 12, 14, 16],
};

/// 코드 스펙 → **기타 바레 코드 모양의** MIDI 노트 목록. 슬래시 코드(베이스
/// 지정)나 목록에 없는 종류는 [chordMidiOf] 로 되돌아간다(자리바꿈 O).
List<int> guitarChordMidi(ChordSpec spec) {
  final shape = kGuitarChordShape[spec.type];
  if (shape == null || spec.bass != null) return chordMidiOf(spec);
  final fret = ((spec.root - _kEPc) % 12 + 12) % 12;
  final root = kGuitarLowE + fret;
  return [for (final iv in shape) root + iv];
}

// ── 자리바꿈(inversion)으로 앞 코드와 잇기 ──
//
// [chordMidiOf] 는 어떤 코드든 **근음 자리**로만 쌓는다. 그래서 i–iv–VI–VII 를
// 치면 밑음이 60→65→68→70 으로 기어오르다가 다음 바퀴에 60 으로 뚝 떨어진다
// (재 보니 코드가 바뀔 때마다 평균 5.3반음씩 움직였다 — 완전4도다).
// 사람은 건반에서 손을 한자리에 두고 **자리바꿈**으로 잇는다. 그 손을 흉내 낸다.
//
// **코드톤 집합은 손대지 않는다** — 옥타브만 옮긴다. 화성은 그대로고 움직임만 준다.
// 근음이 맨 밑에 없어도 된다: 베이스 트랙이 근음을 따로 짚는다.

/// 코드 밑음이 놓일 자리 — 이보다 밑이면 베이스와 엉키고, 위면 멜로디 자리다.
///
/// **띠 폭은 정확히 한 옥타브여야 한다.** [voiceLead] 의 `oct` 는 이 띠를 통째로
/// 12 씩 올려서 층을 나누는데(0 → 55~66, 1 → 67~78), 띠가 12보다 넓으면 이웃한
/// 두 층이 서로 겹친다. 예전 값 55~72 는 폭이 17이라 층 0 과 층 1 이 67~72 에서
/// 겹쳤다 — 그래서 프로그하우스 그루브의 패드(층 0)와 스탭(층 1)이 **완전히 같은
/// 자리**를 골랐다(코드 넷 중 둘이 음까지 동일). 층을 준 의미가 없어진다.
///
/// 66 으로 좁히니 코드 악기 두 줄이 겹치는 최악값이 79% → 38% 로 내려갔고
/// 60% 를 넘는 쌍이 하나도 없어졌다(손 움직임은 1.31 → 1.35 반음, 거의 그대로).
const int kVoiceLow = 55; // G3
const int kVoiceHigh = 66; // F#4 — kVoiceLow + 11, 즉 폭이 딱 한 옥타브

/// [chord](MIDI, 정렬 안 돼 있어도 됨)를 [prev] 와 제일 가깝게 놓는다.
/// [prev] 가 없으면 60(C4) 근처에 앉힌다. **난수를 안 쓴다** — 같은 입력 → 같은 자리.
///
/// [oct] 은 이 줄이 앉을 층이다(0=기본, 1=한 옥타브 위). 한 씬에 코드 악기가
/// 둘이면 **같은 층에 두면 안 된다** — 같은 진행을 같은 자리에서 치면 한쪽이
/// 다른 쪽에 완전히 묻힌다(재즈 비브라폰이 −24.7dB 였던 이유가 이것이다).
List<int> voiceLead(List<int> chord, List<int>? prev, {int oct = 0}) {
  if (chord.length < 2) return chord;
  final center = 60 + 12 * oct;
  final low = kVoiceLow + 12 * oct;
  final high = kVoiceHigh + 12 * oct;
  List<int>? best;
  var bestScore = double.infinity;
  for (var shift = -24 + 12 * oct; shift <= 24 + 12 * oct; shift += 12) {
    var v = [for (final m in chord) m + shift]..sort();
    for (var inv = 0; inv < chord.length; inv++) {
      var score = 0.0;
      if (prev == null) {
        score = (v.first - center).abs().toDouble();
      } else {
        final n = v.length < prev.length ? v.length : prev.length;
        for (var i = 0; i < n; i++) {
          score += (v[i] - prev[i]).abs();
        }
        score /= n;
      }
      // 음역 밖으로 나가면 벌점
      if (v.first < low) score += (low - v.first) * 2.0;
      if (v.first > high) score += (v.first - high) * 2.0;
      // 아래쪽에서 음이 뭉치면 탁해진다 — 반음 붙은 자리는 크게 벌준다
      for (var i = 1; i < v.length; i++) {
        final gap = v[i] - v[i - 1];
        if (gap <= 1) {
          score += 8;
        } else if (gap == 2 && v[i - 1] < 67 + 12 * oct) {
          score += 3;
        }
      }
      if (score < bestScore) {
        bestScore = score;
        best = List<int>.of(v);
      }
      // 맨 밑음을 한 옥타브 올린다 — **올린 뒤 다시 정렬해야 한다.**
      // 9화음처럼 옥타브보다 넓은 코드는 밑음을 12 올려도 맨 위가 안 된다
      // (min9 [60,63,67,70,74] → [63,67,70,74,72]). 정렬을 안 하면 밑에서
      // 두 줄 아래 「반음 붙었나」 검사가 **음수 간격**을 보고 벌점 8을 주고,
      // `v.first` 도 맨 밑음이 아니게 된다. 그래서 넓은 코드는 자리바꿈이
      // 하나도 못 살아남았다 — 재 보니 9화음 720개가 100% 근음 자리였다.
      v = [...v.sublist(1), v.first + 12]..sort();
    }
  }
  return best ?? chord;
}

/// 코드 하나의 성질(장/단/dim) — 웹 `chordQual()`.
String _chordQual(List<int> off) {
  final t3 = off[1] - off[0], f5 = off[2] - off[0];
  return f5 == 6 ? 'dim' : (t3 == 3 ? 'min' : 'maj');
}

/// 도수마다 **어떤 느낌인가** — 옛 앱(뮤직 두들)의 `DEG_MOOD` 그대로.
///
/// 「4도」는 악보를 아는 사람의 말이다. 「활짝」은 아무나 아는 말이고, 고를 때
/// 실제로 도움이 된다 — 이 앱은 **악보를 몰라도 되는 것**이 첫 규칙이다.
const Map<String, List<String>> kDegMood = {
  'major': ['중심', '부드러움', '아련함', '활짝', '이어짐', '쓸쓸함', '긴장'],
  'minor': ['중심', '긴장', '밝음', '차분함', '이어짐', '활짝', '뭉클'],
};

/// 그 조에서 [degree](0~6)가 어떤 느낌인지 한 마디.
String degMood(int degree, String mode) {
  final list = kDegMood[mode] ?? kDegMood['major']!;
  return list[degree.abs() % list.length];
}

/// 다이아토닉 7화음 — 웹 `applyKey()` 안의 `CHORDS` 계산 그대로.
/// 패턴 데이터의 코드 트랙 숫자(0~6)는 이 목록의 인덱스다(0=i, 1=ii, 2=iii, ...).
List<ChordSpec> diatonicChords(MusicKey key) {
  final sc = scaleOf(key.mode);
  return kTriadDegs.map((rd) {
    final off = [
      rd,
      rd + 2,
      rd + 4,
    ].map((x) => sc[x % 7] + 12 * (x ~/ 7)).toList();
    final pc = ((key.root + off[0]) % 12 + 12) % 12;
    final ty = _chordQual(off);
    return ChordSpec(root: pc, type: ty);
  }).toList();
}

/// 스케일 도수(0=으뜸음, 7=한 옥타브 위 …) → 실제 주파수 — 웹 `applyKey()`의 non-PRO
/// 분기 + `degRow()`를 합친 것. [type]이 'bass' 면 웹 `BASS_F`(C1 기준), 그 외(코드/멜로디)는
/// `LEAD_F`(C4 기준)와 같은 식이다.
///
/// 웹은 줄 배열이 15개(2옥타브+1, 도수 0~14)라 그 범위로 clamp 한다(`degRow` 비-PRO 분기,
/// `Math.max(0,Math.min(ROWS-1,d))`) — 옮긴 패턴 데이터도 전부 그 범위 안에 있지만
/// 안전장치로 그대로 유지했다.
/// **반음 줄**(프로 모드)의 음 높이 — 0 = 그 조의 으뜸음, 1 = 그 반음 위…
///
/// 스케일 도수(0~14)는 조에 맞는 음만 낼 수 있다. 프로 모드는 12음 전부를 쓴다.
///
/// 자리를 **절대 음이 아니라 으뜸음에서 몇 반음**으로 잡는다. 옛 앱은 절대 음이라
/// 조를 바꾸면 찍어 둔 것을 통째로 옮기는 코드(`transposeAllClips`)가 따로 있었다 —
/// 여기서는 도수와 똑같이 **조를 따라 저절로 옮겨 간다.**
double semiFreq(int semi, String type, MusicKey key) {
  final s = semi.clamp(0, kProRows - 1);
  final n = s + key.root;
  return type == 'bass' ? _mfreq(kBassBase + n) : _mfreq(60 + n);
}

/// 반음 줄 수 — 2옥타브 + 1(도수 줄이 15인 것과 같은 셈).
const int kProRows = 25;

double degreeFreq(int degree, String type, MusicKey key) {
  final d = degree.clamp(0, 14);
  final sc = scaleOf(key.mode);
  final oct = d ~/ 7;
  final deg = d % 7;
  final semi = sc[deg] + 12 * oct + key.root;
  return type == 'bass' ? _mfreq(kBassBase + semi) : _mfreq(60 + semi);
}
