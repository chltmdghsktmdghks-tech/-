// **질문에 답해서 곡 만들기** — 옛 앱(뮤직 두들)의 첫 화면 머리 항목.
//
// 음악 용어를 **하나도 안 쓴다.** 기분과 장면만 묻는다. 「BPM 을 정하세요」는
// 악보를 아는 사람의 말이고, 「몸이 어떻게 움직였으면 해요?」는 아무나 안다.
//
// ── 0에서 만들지 않는다 ──
// 답을 모아 **어떤 완성곡을 뼈대로 쓸지** 고르고, 그 위에 조성·빠르기·길이·편성·
// 믹스를 바꾼다. 검증된 곡을 변형하는 것이라 **이상한 결과가 안 나온다.**
// 0부터 만들면 「음악이 아닌 것」이 나올 수 있는데, 그건 이 앱에서 제일 나쁜 결과다.
//
// 여기는 **값만 정한다.** 화면은 `ui/ask_sheet.dart`, 실제로 바르는 것은
// [applyAsk] 다 — 시험이 화면 없이 답만 넣어 결과를 잴 수 있어야 한다.

import 'arrange_rec.dart';
import 'genres.dart';
import 'instruments.dart';
import 'project.dart';
import 'sequencer.dart';

/// 질문 하나 — 값·보이는 말·한 줄 설명.
class AskQ {
  final String key;
  final String q;
  final String hint;
  final List<(String, String, String)> answers;
  const AskQ(this.key, this.q, this.hint, this.answers);
}

/// 열 가지를 묻는다. 순서가 뜻이 있다 — **기분이 첫 질문**이다(제일 많이 정한다).
const List<AskQ> kAskQuestions = [
  AskQ('mood', '지금 어떤 기분이에요?', '제일 중요한 질문이에요', [
    ('bright', '밝고 신남', '햇빛, 웃음, 뛰는 심장'),
    ('calm', '차분하고 편안', '숨 고르기, 따뜻한 방'),
    ('blue', '쓸쓸하고 아련', '비, 지나간 것들'),
    ('dark', '어둡고 묵직', '밤, 긴장, 무게'),
  ]),
  AskQ('scene', '어디서 흘러나올 것 같아요?', '그 장소에 어울리는 악기를 고릅니다', [
    ('club', '클럽·파티', '사람 많고 시끄러운 곳'),
    ('drive', '밤 드라이브', '창밖으로 불빛이 지나감'),
    ('cafe', '카페·작업실', '조용히 뭔가 하는 중'),
    ('room', '혼자 있는 방', '불 끄고 누워 있음'),
  ]),
  AskQ('speed', '몸이 어떻게 움직였으면 해요?', '곡의 빠르기가 정해집니다', [
    ('fast', '들썩들썩', '뛰거나 춤추게'),
    ('mid', '고개를 끄덕끄덕', '걷는 속도쯤'),
    ('slow', '천천히 흔들', '느긋하게'),
    ('still', '거의 가만히', '숨만 쉬게'),
  ]),
  AskQ('power', '소리가 얼마나 꽉 찼으면 해요?', '악기 수가 정해집니다', [
    ('huge', '꽉 채워서', '악기를 더 얹어 두껍게'),
    ('mid2', '적당히', '기본 편성'),
    ('thin', '비워서', '악기 몇 개만 · 여백 많이'),
  ]),
  AskQ('lead', '맨 앞에서 노래하는 건 누구였으면 해요?', '가장 잘 들리는 악기예요', [
    ('voice', '사람 목소리 같은 것', '노래하듯이'),
    ('bell', '맑고 반짝이는 것', '벨·종 같은'),
    ('warm', '따뜻한 관·현악기', '색소폰 같은'),
    ('synth', '또렷한 전자음', '신스 리드'),
  ]),
  AskQ('low', '아래쪽 저음은 어땠으면 해요?', '베이스의 성격이에요', [
    ('deep', '묵직하게 쿵', '가슴이 울리는 저음'),
    ('bounce', '통통 튀게', '움직이는 베이스'),
    ('soft', '부드럽게 받쳐만', '있는 듯 없는 듯'),
  ]),
  AskQ('drum', '드럼은 어느 정도로?', '리듬이 곡을 끌지, 뒤에서 받칠지', [
    ('punch', '확실하게 때리는', '드럼이 곡을 끕니다'),
    ('normal', '보통', '같이 갑니다'),
    ('back', '뒤에서 조용히', '거의 안 나서게'),
  ]),
  AskQ('space', '소리가 어떤 공간에 있었으면 해요?', '잔향(에코)의 양이에요', [
    ('dry', '바로 앞에서', '건조하고 또렷하게'),
    ('room2', '작은 방', '자연스러운 울림'),
    ('hall', '넓은 홀', '멀리 퍼지는 울림'),
  ]),
  AskQ('len', '얼마나 길었으면 해요?', '', [
    ('s', '짧게 (2분쯤)', '금방 끝나는'),
    ('m', '보통 (3분쯤)', '노래 한 곡 길이'),
    ('l', '길게 (4분 넘게)', '천천히 쌓이는'),
  ]),
  AskQ('edge', '마지막으로 — 거칠게? 매끈하게?', '', [
    ('rough', '거칠게', '먼지 낀, 눌린'),
    ('clean', '매끈하게', '깨끗하고 또렷한'),
  ]),
];

/// 답 → **뼈대 곡** 점수. 각 완성곡이 어떤 답과 어울리는지.
///
/// 다섯 곡만 뼈대로 쓴다 — 열다섯 스타일을 다 넣으면 점수가 갈리지 않아서
/// 무엇을 골라도 비슷한 것이 나온다. 이 다섯은 서로 **멀리 떨어져** 있다.
const Map<String, Map<String, int>> kAskFit = {
  'pop': {
    'bright': 3,
    'calm': 1,
    'club': 1,
    'drive': 1,
    'cafe': 1,
    'fast': 1,
    'mid': 3,
    'huge': 2,
    'mid2': 2,
    'voice': 3,
    'clean': 2,
  },
  'proghouse': {
    'bright': 2,
    'dark': 1,
    'club': 3,
    'drive': 2,
    'fast': 3,
    'mid': 1,
    'huge': 3,
    'mid2': 1,
    'synth': 3,
    'bell': 1,
    'clean': 2,
  },
  'trap': {
    'dark': 3,
    'blue': 1,
    'club': 2,
    'drive': 2,
    'room': 1,
    'mid': 2,
    'slow': 2,
    'huge': 2,
    'mid2': 1,
    'bell': 3,
    'synth': 1,
    'rough': 2,
  },
  'jazz': {
    'calm': 3,
    'blue': 2,
    'cafe': 3,
    'room': 1,
    'mid': 2,
    'slow': 2,
    'mid2': 2,
    'thin': 1,
    'warm': 3,
    'voice': 1,
    'rough': 1,
  },
  'ambient': {
    'calm': 2,
    'blue': 3,
    'dark': 1,
    'room': 3,
    'cafe': 1,
    'still': 3,
    'slow': 1,
    'thin': 3,
    'bell': 2,
    'warm': 1,
    'clean': 1,
  },
};

/// 기분 → 조성 루트 후보. **같은 곡도 조가 바뀌면 다른 곡처럼 들린다.**
const Map<String, List<int>> kAskRoot = {
  'bright': [0, 7, 5],
  'calm': [5, 0, 10],
  'blue': [9, 2, 7],
  'dark': [0, 3, 10],
};

/// 답을 모아 **무엇을 만들지** 정한 것. 화면도 시험도 이걸 본다.
class AskRecipe {
  final String genre;
  final int root;
  final String mode;
  final double bpm;
  final double targetSec;
  const AskRecipe({
    required this.genre,
    required this.root,
    required this.mode,
    required this.bpm,
    required this.targetSec,
  });
}

/// 답 → 뼈대·조성·빠르기·길이. [pick] 은 조 후보 중 몇 번째를 쓸지(시험은 0).
AskRecipe askRecipe(Map<String, String> a, {int pick = 0}) {
  // 1) 뼈대 곡 — 답과 제일 잘 맞는 완성곡.
  var best = 'pop';
  var bestScore = -1;
  for (final e in kAskFit.entries) {
    var sc = 0;
    for (final v in a.values) {
      sc += e.value[v] ?? 0;
    }
    if (sc > bestScore) {
      bestScore = sc;
      best = e.key;
    }
  }
  final g = genreDef(best);

  // 2) 조성 — 기분이 루트를 고른다.
  final roots = kAskRoot[a['mood']] ?? const [0];
  final root = roots[pick.abs() % roots.length];
  final mode = a['mood'] == 'bright' ? 'major' : g.mode;

  // 3) 빠르기 — 뼈대 곡의 값을 기분에 맞게 당긴다.
  const spd = {'fast': 1.16, 'mid': 1.0, 'slow': 0.86, 'still': 0.72};
  final bpm = (g.bpm * (spd[a['speed']] ?? 1.0)).clamp(60.0, 180.0);

  // 4) 길이 — **초**로 잰다. 마디로 세면 빠르기에 따라 제멋대로가 된다
  //    (느린 곡을 「짧게」로 골랐는데 4분이 나온다).
  const len = {'s': '짧게', 'm': '보통', 'l': '길게'};
  final target = kSongTargets[len[a['len']] ?? '보통'] ?? 205.0;

  return AskRecipe(
    genre: best,
    root: root,
    mode: mode,
    bpm: bpm,
    targetSec: target,
  );
}

/// 뼈대 곡 위에 나머지 답을 바른다. **[askRecipe] 뒤에 부른다.**
void applyAsk(Project p, Transport tr, Map<String, String> a, AskRecipe r) {
  p.setGenre(r.genre);
  tr
    ..root = r.root
    ..mode = r.mode
    ..bpm = r.bpm;

  // 길이 — 구간을 덜거나 더한다. 인트로·아웃트로는 안 건드린다(`fitToLength`).
  final fitted = fitToLength(
    p.song.sections,
    r.targetSec,
    secOf: (scene) => SceneSequencer.sceneLoopSec(p, tr, scene),
    isEnd: (i) => i == 0 || i == p.song.sections.length - 1,
  );
  p.song.restore(fitted);

  // 맨 앞에서 노래하는 악기.
  const leadVoice = {
    'voice': 'vocal',
    'bell': 'bell',
    'warm': 'sax',
    'synth': 'saw',
  };
  final lv = leadVoice[a['lead']];
  if (lv != null) {
    for (final t in p.tracks) {
      if (t.type == 'melody') {
        t.voice = lv;
        break; // **맨 앞 하나만** — 가락이 둘이면 뒤엣것은 그대로 둔다
      }
    }
  }

  // 저음 성격 — 음색·크기·저역 자르기.
  const lowVoice = {
    'deep': 'moogbass',
    'bounce': 'fingerbass',
    'soft': 'upright',
  };
  const lowVol = {'deep': 1.14, 'bounce': 1.0, 'soft': 0.82};
  const lowHpf = {'deep': 20.0, 'bounce': 34.0, 'soft': 44.0};
  for (final t in p.tracks) {
    if (t.type != 'bass') continue;
    final v = lowVoice[a['low']];
    if (v != null && VOICE_LABEL.containsKey(v)) t.voice = v;
    t.vol = t.vol * (lowVol[a['low']] ?? 1.0);
    final h = lowHpf[a['low']];
    if (h != null) t.hpf = h;
  }

  // 드럼 존재감.
  const drumVol = {'punch': 1.22, 'normal': 1.0, 'back': 0.66};
  final dv = drumVol[a['drum']] ?? 1.0;
  for (final t in p.tracks) {
    if (t.type == 'drum') t.vol = t.vol * dv;
  }

  // 공간(잔향) — 전 트랙을 같은 배수로. **0.85 를 넘기지 않는다**(넘으면 뭉갠다).
  const revScale = {'dry': 0.35, 'room2': 1.0, 'hall': 1.7};
  final rs = revScale[a['space']] ?? 1.0;
  for (final t in p.tracks) {
    t.rev = (t.rev * rs).clamp(0.0, 0.85);
  }

  // 거칠게 — 드럼 키트로 표현한다(먼지 낀 소리).
  if (a['edge'] == 'rough') {
    for (final t in p.tracks) {
      if (t.type == 'drum') t.kit = 'lofi';
    }
    for (final s in p.scenes) {
      s.kit = 'lofi';
    }
  }

  // 꽉 채우기 / 비우기 — 악기 수.
  if (a['power'] == 'huge') {
    p.addTrack('chord', voice: 'strings');
  } else if (a['power'] == 'thin') {
    // **마지막 가락 하나만** 뺀다. 드럼·베이스·화음은 곡의 뼈대라 안 건드린다.
    Track? drop;
    for (final t in p.tracks) {
      if (t.type == 'melody') drop = t;
    }
    if (drop != null && p.tracks.length > 3) p.removeTrack(drop);
  }
}
