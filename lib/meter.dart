// 박자 — **마디 하나가 몇 칸인가.** (5단계 47/N)
//
// 여태 이 앱의 마디는 늘 16칸(4/4)이었다. `kStepsPerBar = 16` 이 상수라 그럴 수밖에
// 없었다. 홀수 박자를 넣는다는 것은 그 상수를 **값에서 성질로** 바꾸는 일이다.
//
// ── 옛 앱을 그대로 옮기지 않는 이유 ──
// 옛 앱에도 `meterSteps()` 가 있었다(app.html:2991). 그런데 **절반만 되어 있었다**:
// 격자는 12칸이 되는데 판 라이브러리는 16칸 그대로라, 3/4 에서 판을 고르면 12~15칸이
// 다음 마디로 넘쳤다. 그래서 박자를 바꾸면 **곡을 통째로 지웠다**(`P.sceneClips={}`).
// 고장을 옮길 수는 없다.
//
// ── 그래서 판이 제 박자를 들고 다닌다 ──
// `NotePatternDef.spb` · `DrumPatternDef.spb`. 옛 판은 전부 16이라 그대로 돌고,
// 3/4 판은 12 로 적힌다. 한 앱 안에 둘이 같이 있어도 안 어긋나고, 고르는 화면은
// **지금 곡의 박자와 맞는 판만** 보여 준다. 박자를 바꿔도 곡이 안 사라진다.

/// 박자 하나가 아는 모든 것.
class MeterDef {
  /// 저장 파일에 남는 키 — **절대 바꾸지 말 것**(옛 곡이 안 열린다).
  final String key;

  /// 한 마디에 몇 박(분자).
  final int beats;

  /// 한 박이 몇 분음표(분모). 4 = 4분음표, 8 = 8분음표.
  final int unit;

  /// 고르는 화면의 한 줄 — **음악 용어 대신 들리는 느낌으로.**
  final String feel;

  /// 메트로놈이 **몇 칸마다** 치나.
  ///
  /// /4 박자는 4분음표마다(4칸), /8 박자는 8분음표마다(2칸) 친다.
  /// 6/8 을 「둘」로만 치면(6칸마다) 초보가 그 사이를 못 채운다 — 느긋한 곡에서는
  /// 1초에 한 번 울리고 그 사이가 깜깜하다. **여섯 번 치고 1·4 를 세게** 해서
  /// 두 갈래로 느껴지는 것은 살리고, 짚을 자리는 남긴다.
  final int clickSteps;

  /// 세게 치는 칸 — 여기가 「하나」다.
  ///
  /// 7/8 은 2+2+3 으로 묶인다(0·4·8). 일곱을 고르게 세면 어디가 마디 머리인지
  /// 영영 안 들린다 — 홀수 박자에서 제일 먼저 잃는 것이 그것이다.
  final List<int> strongAt;

  const MeterDef({
    required this.key,
    required this.beats,
    required this.unit,
    required this.feel,
    required this.clickSteps,
    required this.strongAt,
  });

  /// 한 마디가 몇 칸인가. 칸은 늘 **16분음표**다 — 그 자를 바꾸면 스윙·그루브·
  /// 두드려 넣기가 전부 따라 움직여야 한다. 분모만 칸 수로 환산한다.
  /// (옛 앱 `meterSteps()` 와 같은 셈: `beats * (16 / unit)`)
  int get stepsPerBar => beats * (16 ~/ unit);

  /// 메트로놈이 한 마디에 몇 번 치나.
  int get clicksPerBar => stepsPerBar ~/ clickSteps;

  /// 화면에 적는 이름 — '3/4'.
  String get label => '$beats/$unit';

  /// 4/4 인가 — 여태와 똑같이 굴러야 하는 자리가 많아 따로 묻는다.
  bool get isFour => key == '4/4';
}

/// **이 목록의 순서가 화면 순서다.** 4/4 가 늘 처음이다.
const List<MeterDef> kMeters = [
  MeterDef(
    key: '4/4',
    beats: 4,
    unit: 4,
    feel: '네 박 — 거의 모든 노래가 이것',
    clickSteps: 4,
    strongAt: [0],
  ),
  MeterDef(
    key: '3/4',
    beats: 3,
    unit: 4,
    feel: '세 박 — 왈츠처럼 빙글빙글 도는',
    clickSteps: 4,
    strongAt: [0],
  ),
  MeterDef(
    key: '6/8',
    beats: 6,
    unit: 8,
    feel: '여섯 박 — 흔들흔들 걷는, 옛날 발라드',
    clickSteps: 2,
    // 6/8 은 셋씩 두 갈래다 — 1 과 4 가 기둥이다
    strongAt: [0, 6],
  ),
  MeterDef(
    key: '5/4',
    beats: 5,
    unit: 4,
    feel: '다섯 박 — 한 박 더 있어 묘하게 안 맞는',
    clickSteps: 4,
    strongAt: [0],
  ),
  MeterDef(
    key: '7/8',
    beats: 7,
    unit: 8,
    feel: '일곱 박 — 자꾸 걸려 넘어지는 듯한',
    clickSteps: 2,
    // 2+2+3 — 발칸·프로그레시브가 이렇게 센다
    strongAt: [0, 4, 8],
  ),
];

/// 4/4 — 못 찾았을 때 돌아갈 자리. **`kMeters` 의 첫 항목과 같은 값**이어야 한다
/// (시험이 맞대 본다 — 두 표가 말없이 어긋나는 그 모양이다).
const MeterDef kMeterFour = MeterDef(
  key: '4/4',
  beats: 4,
  unit: 4,
  feel: '네 박 — 거의 모든 노래가 이것',
  clickSteps: 4,
  strongAt: [0],
);

/// 키로 찾는다. 모르는 키(옛 파일·깨진 값)는 **4/4 로 본다** —
/// 여기서 null 을 돌려주면 부르는 쪽마다 `?? 4/4` 를 적게 되고, 언젠가 한 곳을 빠뜨린다.
MeterDef meterOf(String? key) {
  if (key == null) return kMeterFour;
  for (final m in kMeters) {
    if (m.key == key) return m;
  }
  return kMeterFour;
}

/// 그 박자의 한 마디가 몇 칸인가 — 제일 많이 묻는 것이라 지름길을 둔다.
int meterStepsOf(String? key) => meterOf(key).stepsPerBar;

/// 메트로놈이 [step] 칸에서 **세게** 쳐야 하는가.
///
/// 마디 안 자리로 접어서 본다 — 판이 몇 마디든 마디마다 「하나」가 들려야 한다.
bool meterStrongAt(MeterDef m, int step) {
  final spb = m.stepsPerBar;
  if (spb <= 0) return false;
  final inBar = ((step % spb) + spb) % spb;
  return m.strongAt.contains(inBar);
}

/// [step] 이 마디 안에서 **몇 번째 박**인가(1부터). 화면에 「2마디 3박」을 적을 때 쓴다.
///
/// /8 박자는 8분음표를 센다 — 6/8 에서 「6박」까지 나온다. 그게 그 박자를 세는 방식이다.
int meterBeatAt(MeterDef m, int step) {
  final spb = m.stepsPerBar;
  if (spb <= 0 || m.clickSteps <= 0) return 1;
  final inBar = ((step % spb) + spb) % spb;
  return inBar ~/ m.clickSteps + 1;
}
