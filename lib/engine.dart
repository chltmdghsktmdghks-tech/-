// 오디오 엔진 — 음 배분 · 합산 · 진단
//
// 스파이크에서 확인된 구조 그대로다. 노드가 없다.
// 오디오 장치가 "샘플 더 줘" 하고 부를 때마다 그 구간을 계산해 채운다.
// A17(보급형)에서 악기 64종·화면부하 2배로 오디오 여유 87% 를 확인했다.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dsp.dart';
import 'fx.dart';
import 'drums.dart';
import 'instruments.dart';
import 'mixer.dart';
import 'synth.dart';

export 'dsp.dart' show kSampleRate;
export 'synth.dart' show kPartBass, kPartChord, kPartMelody;

const int kChannels = 2; // 스테레오 — 유니즌 폭·악기 위치가 들려야 한다
const int kPolyphony = 96;

const int kDrumPolyphony = 24; // 드럼은 한 순간에 훨씬 적게 겹친다 (16분 하이햇 + 킥/스네어 정도)

class Engine {
  // 매 샘플 96개를 훑으면 낭비다. 켜져 있는 음만 _live 에 들고 다닌다.
  final List<SynthNote> _free = List.generate(kPolyphony, (_) => SynthNote());
  final List<SynthNote> _live = [];

  // 드럼은 신호 흐름이 완전히 달라서(배음이 아니라 레이어 합) 별도 풀을 쓴다.
  final List<DrumVoice> _freeDrums = List.generate(
    kDrumPolyphony,
    (_) => DrumVoice(),
  );
  final List<DrumVoice> _liveDrums = [];
  int drumStarved = 0;

  bool highQuality = true;

  // ── 진단 ──
  int callbacks = 0;
  int maxActive = 0;
  int maxActiveDrums = 0;
  int starved = 0;
  int bufferEmpty = 0;
  double loadAvg = 0, loadPeak = 0;
  double peakOut = 0; // 리미터 **전** 최대 출력 — 얼마나 넘쳤는지
  int clipped = 0;

  /// 음이 여러 개 겹칠 여유를 미리 비워 둔다. 웹의 MIX_HEADROOM 과 같은 역할 —
  /// 트랙별 페이더가 생기기 전까지는 이 고정값이 헤드룸을 대신한다.
  double masterGain = 0.55;

  /// 5단계 — 믹서의 **마스터 페이더**. 위 [masterGain](고정 헤드룸)에 곱해서 쓴다.
  /// 1.0 이면 곱해도 값이 한 비트도 안 바뀐다(0.55×1.0 = 0.55) — 기존 스모크 기준값 유지.
  double userGain = 1.0;

  /// 5단계 34/N — **스타일 보정**. 스타일마다 GENRE_MIX 값이 따로라서 곡 크기가
  /// 10dB 넘게 벌어졌다(트랩 −7.7 vs 재즈 −17.9 dBFS). 곡을 바꿀 때마다 볼륨을
  /// 만져야 하면 그게 고장이다. 사용자 페이더([userGain])와 **따로** 곱한다 —
  /// 섞어 두면 믹서에 뜨는 숫자와 실제 소리가 어긋난다.
  /// 값은 `genre_mix.dart` 의 `kStyleGain`.
  double styleGain = 1.0;

  /// **킥이 칠 때 나머지가 잠깐 비켜 준다** (Phase 4 · 계획 6-5).
  ///
  /// 0 이면 아무 일도 안 한다(재즈·발라드·록이 그렇다).
  /// 값은 `kGenreDuck` 에서 온다 — 장르마다 다르고, 데이터로 둔다.
  double duckAmount = 0;

  double _duck = 1.0;
  // 되돌아오는 시간 — 기본 160ms(너무 빠르면 딸꾹질처럼, 너무 느리면 늘
  // 눌린 채로 들린다). 예전엔 이 값이 고정이었다 — 이제 `duckRelSec` 로
  // 사용자가 만질 수 있다(마스터 믹서의 "비켜주기" 손잡이, `mixer_view.dart`).
  double _duckRel = math.exp(-1 / (0.16 * kSampleRate));
  double _duckRelSec = 0.16;
  double get duckRelSec => _duckRelSec;
  set duckRelSec(double sec) {
    _duckRelSec = sec;
    _duckRel = math.exp(-1 / (sec.clamp(0.02, 1.0) * kSampleRate));
  }

  /// 지금 사이드체인 덕 값 — 1 이면 안 눌림, 작을수록 세게 눌림.
  /// **진단·시험용.** `clipped`·`starved`처럼 내부 상태를 밖에서 확인하는 자리다 —
  /// 목소리를 못 얻은 킥도 덕은 걸어야 한다는 약속을 시험이 지킨다.
  double get duckLevel => _duck;

  /// 5단계 47/N — **마스터 인서트.** 마스터 버스 뒤, 리미터 앞에 낀다.
  /// 마스터링 플러그인(그래픽 EQ·컴프·리미터)이 여기 꽂힌다.
  /// 엔진 맨 끝의 룩어헤드 리미터는 그대로 둔다 — 그건 **안전장치**지 도구가 아니다
  /// (사용자가 리미터를 빼도 소리가 깨지면 안 된다).
  final List<Fx> masterInserts = [];

  /// 3단계 — 마스터 버스(HPF/LPF·3밴드 EQ·컴프). masterGain **뒤** · 리미터 **앞**에 낀다.
  /// 기본값은 전부 투명이라 손대지 않으면 1·2단계 소리가 그대로 나간다.
  final MasterBus masterBus = MasterBus();

  /// 4단계 4/N — 드럼/베이스/코드/멜로디 트랙 버스(`GENRE_MIX` 를 걸 자리).
  /// 4단계 5/N — 멀로딕 버스가 3개 고정에서 N개(곡마다 다름)로 일반화됐다.
  /// 기본값은 전부 투명이라 손대지 않으면 이전 단계 소리가 그대로 나간다.
  final TrackMixSet trackMix = TrackMixSet();

  // 파트별 합산 버퍼 — 매 샘플 트랙 버스 개수만큼 쓴다. 렌더 핫패스에서 매번 새로
  // 할당하지 않도록 넉넉히(8개) 미리 잡아 두고, trackMix.slots 가 그보다 커지면
  // 그때만 다시 늘린다(거의 안 일어난다 — 지금까지 가장 큰 편성이 5개).
  Float64List _accL = Float64List(8);
  Float64List _accR = Float64List(8);

  /// 컴프가 지금 몇 dB 깎고 있나 (진단용, 화면 표시)
  double get compGrDb => masterBus.compGrDb;

  // ── 룩어헤드 리미터 ──
  // 어택만 빠르게 해서는 못 막는다. 실측: 리미터 앞 피크 1.57 인데 감쇠는 -1.5dB 뿐이라,
  // 어택 1ms 사이로 샌 만큼이 하드클립으로 잘렸다. 그게 지직거림이다.
  //
  // 소리를 4ms 늦춰서 내보내고, 게인은 **늦추지 않은** 신호를 보고 미리 내린다.
  // 그러면 큰 파형이 출구에 도착할 때는 이미 게인이 내려가 있어서 잘릴 일이 없다.
  static const int _look = 192; // 4ms @48k
  final Float64List _dl = Float64List(_look * 2);
  int _dlIdx = 0;
  static final double _atkCoef = math.exp(
    -1 / (0.0008 * kSampleRate),
  ); // 0.8ms — 룩어헤드 안에서 다 내려간다
  static final double _relCoef = math.exp(-1 / (0.12 * kSampleRate)); // 120ms
  static const double _ceil = 0.95;
  double _gr = 1.0;
  double _peak = 0; // 최근 최대값 (엔벨로프 팔로워)
  double minGain = 1.0; // 가장 많이 눌렀던 정도 (1.0 = 안 눌림)

  /// 리미터가 지금 몇 dB 깎고 있나
  double get grDb => _gr >= 1.0 ? 0 : 20 * math.log(_gr) / math.ln10;
  double get worstGrDb =>
      minGain >= 1.0 ? 0 : 20 * math.log(minGain) / math.ln10;

  double get headroomPct => ((1 - loadAvg) * 100).clamp(0, 100);
  double get worstHeadroomPct => ((1 - loadPeak) * 100).clamp(0, 100);
  int get activeCount => _live.length;

  /// 버스 이름 → 마지막으로 읽은 뒤의 봉우리. **읽으면 비워진다.**
  /// 믹서의 트랙별 미터가 이걸 읽는다.
  Map<String, double> takeBusPeaks() => {
    'drum': trackMix.drum.takePeak(),
    'live': trackMix.live.takePeak(),
    for (var i = 0; i < trackMix.slotNames.length; i++)
      if (i < trackMix.slots.length)
        trackMix.slotNames[i]: trackMix.slots[i].takePeak(),
  };
  int get drumActiveCount => _liveDrums.length;

  void resetStats() {
    callbacks = 0;
    maxActive = 0;
    maxActiveDrums = 0;
    starved = 0;
    drumStarved = 0;
    bufferEmpty = 0;
    loadAvg = 0;
    loadPeak = 0;
    peakOut = 0;
    clipped = 0;
    minGain = 1.0;
  }

  /// 음 하나를 켠다. 웹의 pitched() 와 같은 인자.
  /// [part] — 4단계 4/N, 5/N 에서 일반화. `trackMix.slots` 의 인덱스(어느 트랙 버스로
  /// 갈지). 배열형 6곡은 kPartBass(0)/Chord(1)/Melody(2) 그대로 쓰면 되고, 객체형
  /// 롱폼(트랩 등)은 그 곡의 슬롯 순서(`genre_mix.dart` `melodicSlotsFor()`)에서 구한
  /// 인덱스를 넘긴다. 범위를 벗어나면 렌더 루프에서 마지막 슬롯으로 클램프한다(방어적 —
  /// 트랙 편성이 바뀌는 도중에 남아 있던 음이 있어도 죽지 않게).
  void noteOn(
    String voice,
    double freq,
    double dur,
    int vel, {
    bool soft = false,
    double glideF = 0,
    int part = kPartMelody,
  }) {
    if (_free.isEmpty) {
      starved++;
      return;
    }
    final adsr = _adsrOf(part);
    final n = _free.removeLast();
    n.noteOn(
      voice,
      freq,
      dur,
      vel,
      soft: soft,
      glideF: glideF,
      highQuality: highQuality,
      part: part,
      atkOverride: adsr?.adsrAttack,
      decOverride: adsr?.adsrDecay,
      susOverride: adsr?.adsrSustain,
      relOverride: adsr?.adsrRelease,
      uniOverride: adsr?.uniCents,
    );
    _live.add(n);
    if (_live.length > maxActive) maxActive = _live.length;
  }

  /// [part] 자리 트랙의 ADSR 손잡이 — 드럼(-1) 이거나 트랙 밖이면 없음.
  /// 사용자 요청, 2026-09-15: "악기들 ADSR 필요한 악기들은 악기 설정에
  /// 넣어 놓자" — 값은 `mixer_view.dart` 에서 `TrackMix` 에 얹어 두고,
  /// 여기서 노트가 실제로 켜질 때 그 자리 것을 그대로 읽는다.
  TrackMix? _adsrOf(int part) =>
      (part >= 0 && part < trackMix.slots.length) ? trackMix.slots[part] : null;

  /// **꾹 누르는 동안 계속 나는 소리.**
  ///
  /// 여태 `noteOn` 은 길이를 미리 받아 그만큼만 울렸다(fire-and-forget). 그래서
  /// 라이브 패드는 어떻게 만지든 「짧게/보통/길게」 중 미리 고른 길이로만 났다 —
  /// **라이브인데 표현이 없었다.**
  ///
  /// [id] 는 부르는 쪽이 정하는 손가락 번호다(포인터 id). 같은 id 로 다시 부르면
  /// 앞의 것을 먼저 놓는다 — 손가락 하나가 두 소리를 물고 있을 수는 없다.
  /// 길이는 [maxSec] 까지만 잡는다(손을 안 떼도 언젠가는 놓는다 — 화면이 죽거나
  /// 메시지를 놓쳐도 목소리가 영영 물려 있으면 안 된다).
  void noteHold(
    int id,
    String voice,
    double freq,
    int vel, {
    bool soft = false,
    double glideF = 0,
    int part = kPartMelody,
    double maxSec = 12.0,
  }) {
    noteRelease(id);
    if (_free.isEmpty) {
      starved++;
      return;
    }
    final adsr = _adsrOf(part);
    final n = _free.removeLast();
    n.noteOn(
      voice,
      freq,
      maxSec,
      vel,
      soft: soft,
      glideF: glideF,
      highQuality: highQuality,
      part: part,
      atkOverride: adsr?.adsrAttack,
      decOverride: adsr?.adsrDecay,
      susOverride: adsr?.adsrSustain,
      relOverride: adsr?.adsrRelease,
      uniOverride: adsr?.uniCents,
    );
    _live.add(n);
    _held[id] = n;
    if (_live.length > maxActive) maxActive = _live.length;
  }

  /// 잡아 둔 소리를 놓는다. 모르는 [id] 면 아무 일도 안 한다.
  void noteRelease(int id) {
    final n = _held.remove(id);
    if (n == null) return;
    n.release();
  }

  /// 잡고 있는 것 전부 놓는다 — 화면을 나가거나 멈출 때.
  void releaseAllHeld() {
    for (final n in _held.values) {
      n.release();
    }
    _held.clear();
  }

  /// 지금 잡고 있는 소리 수 — 시험이 본다.
  int get heldCount => _held.length;

  /// 손가락 번호 → 잡고 있는 목소리([SynthNote]).
  ///
  /// **회수 루프가 여기서도 지워 준다** — 안 그러면 `maxSec` 이 지나 저절로 끝난
  /// 목소리를 계속 가리키고 있다가, 그 자리에 들어온 **다른 음**을 놓아 버린다.
  final Map<int, SynthNote> _held = {};

  /// 드럼 타격 하나. [inst] 는 kick/snare/hat/tom/crash/ride/rim/clap/shake/cow.
  void drumOn(String kitName, String inst, int vel, {double tomFreq = 180}) {
    // 킥이 치는 순간 나머지가 비켜 준다(사이드체인). 목소리를 못 얻어도
    // **비켜 주는 것은 한다** — 킥이 났다는 사실은 변함이 없다.
    //
    // 그래서 **목소리 바닥남으로 돌아가기 전에** 먼저 적용한다. 예전엔 이 줄이
    // 아래 `return` 뒤에 있어서, 정작 목소리가 바닥나 실제로 소리가 안 나는
    // 순간에는(붐빈 트랩 구간에서 실제로 일어난다) 정작 이 주석이 약속하는 일이
    // 일어나지 않고 있었다 — 소리는 안 나는데 나머지도 안 비켜 준 채였다.
    if (duckAmount > 0 && inst == 'kick') _duck = 1 - duckAmount;
    if (_freeDrums.isEmpty) {
      drumStarved++;
      return;
    }
    // 하이햇은 **하나뿐인 악기**다 — 닫으면 열려 있던 소리가 멎는다(초킹).
    // 이게 없으면 열린 하이햇이 다음 박까지 겹쳐 울려서 드럼이 아니라 심벌 뭉치가 된다.
    if (inst == 'hat') {
      for (final d in _liveDrums) {
        if (d.inst == 'hat') d.choke();
      }
    }
    final kit = DRUM_KITS[kitName] ?? DRUM_KITS['acoustic']!;
    final d = _freeDrums.removeLast();
    d.trigger(inst, kit, vel, tomFreq: tomFreq, highQuality: highQuality);
    _liveDrums.add(d);
    if (_liveDrums.length > maxActiveDrums) maxActiveDrums = _liveDrums.length;
  }

  void allOff() {
    for (final n in _live) {
      n.reset();
      _free.add(n);
    }
    _live.clear();
    _held.clear(); // 다 껐으니 잡고 있는 것도 없다
    for (final d in _liveDrums) {
      d.reset();
      _freeDrums.add(d);
    }
    _liveDrums.clear();
  }

  // ── 예약 재생 (시퀀서용) ──
  //
  // 예전에는 `at` 이 '몇 샘플 뒤'(상대값)였고, 렌더 루프가 매 구간마다
  //   ① 큐 전체를 훑어 가장 이른 예약을 찾고  ② 큐 전체의 at 을 chunk 만큼 빼고
  //   ③ 발사한 항목을 removeAt() 으로 중간에서 제거했다 — 전부 O(예약 개수).
  // 트랩 전체곡은 예약이 3700개(드럼 2040 + 멜로딕 1666)라 이게 초당 수십만 번 돌았다.
  // 평균 CPU 는 견뎌도(여유 71%) **순간 스파이크**가 생겨 버퍼가 바닥났다.
  // (A17 실측: 조작 없이 60초에 언더런 3166회, '최악 여유 0%')
  //
  // 그래서 **절대 시각**으로 바꿨다. `_now` 는 지금까지 렌더한 총 샘플 수다.
  // 큐를 시각 순으로 정렬해 두면 다음 예약은 맨 앞 하나만 보면 되고(O(1)),
  // 발사는 앞에서부터 인덱스만 밀면 된다(제거 비용 0).
  int _now = 0;

  /// 지금까지 **만들어 낸** 프레임 수(절대 시각). 예약이 이 시계를 쓴다.
  /// 귀에 들리는 지점은 이보다 큐에 쌓인 만큼 뒤다 — 위치 표시는 그걸 빼고 봐야 한다.
  int get nowFrames => _now;
  int _seq = 0; // 예약 순서 — 같은 시각일 때 순서를 못 박는다
  final List<_Sched> _queue = [];
  int _qHead = 0;
  bool _qDirty = false;

  void schedule(
    double delaySec,
    String voice,
    double freq,
    double dur,
    int vel, {
    bool soft = false,
    double glideF = 0,
    int part = kPartMelody,
  }) {
    _queue.add(
      _Sched(
        // 사람처럼 조금 흔든다 — `Human.setLevel(0)` 이면 아무것도 안 한다
        _now + (humanNudge(delaySec) * kSampleRate).round(),
        _seq++,
        voice,
        freq,
        dur,
        vel,
        soft,
        glideF,
        part,
      ),
    );
    _qDirty = true;
  }

  final List<_DrumSched> _drumQueue = [];
  int _dHead = 0;
  bool _dDirty = false;

  void scheduleDrum(
    double delaySec,
    String kitName,
    String inst,
    int vel, {
    double tomFreq = 180,
  }) {
    _drumQueue.add(
      _DrumSched(
        // 드럼도 흔든다 — **드러머가 제일 안 기계 같아야 한다.**
        // (그루브·스윙은 일부러 미는 것이고 이건 매번 조금씩 다른 흔들림이다)
        _now + (humanNudge(delaySec) * kSampleRate).round(),
        _seq++,
        kitName,
        inst,
        vel,
        tomFreq,
      ),
    );
    _dDirty = true;
  }

  void clearSchedule() {
    _queue.clear();
    _drumQueue.clear();
    _qHead = 0;
    _dHead = 0;
    _qDirty = false;
    _dDirty = false;
  }

  /// 이미 발사한 앞부분을 버리고 시각 순으로 정렬한다. 렌더 진입 때 한 번만 부른다
  /// (샘플 루프 안이 아니다 — 그게 이 구조의 핵심이다).
  void _tidyQueues() {
    if (_qDirty) {
      if (_qHead > 0) {
        _queue.removeRange(0, _qHead);
        _qHead = 0;
      }
      _queue.sort((a, b) => a.at != b.at ? a.at - b.at : a.seq - b.seq);
      _qDirty = false;
    }
    if (_dDirty) {
      if (_dHead > 0) {
        _drumQueue.removeRange(0, _dHead);
        _dHead = 0;
      }
      _drumQueue.sort((a, b) => a.at != b.at ? a.at - b.at : a.seq - b.seq);
      _dDirty = false;
    }
  }

  int get pendingCount =>
      (_queue.length - _qHead) + (_drumQueue.length - _dHead);

  /// 부하 측정용 — **매 호출 새로 만들면 그것도 쓰레기다**(3ms 마다 부른다).
  final Stopwatch _sw = Stopwatch();

  /// 스테레오 인터리브(LRLR…) 로 채운다. frames = 한 채널당 샘플 수.
  ///
  /// 편의용 겉껍질이다 — **버퍼를 새로 만든다.** 내보내기·시험처럼 한 번씩 부르는
  /// 곳에서 쓴다. 실시간 급식 루프는 [renderInto] 로 버퍼를 재사용해야 한다.
  Int16List render(int frames) {
    final out = Int16List(frames * 2);
    renderInto(out, frames);
    return out;
  }

  /// 받아 온 버퍼에 채운다 — **할당이 없다.**
  ///
  /// 급식 루프는 3ms 마다 이걸 부른다. 여기서 `Int16List` 를 새로 만들면
  /// 1024프레임 기준 4KB × 초당 수백 번 = **초당 몇 MB 의 쓰레기**가 되고,
  /// 그 청소(GC)가 곧 급식 지체다. 실시간 경로에서 할당을 없애는 것은
  /// 이 프로젝트가 DSP 안쪽에서 이미 지키고 있는 규칙이다(Fx.step 이 그래서 outL/outR 을 쓴다).
  ///
  /// [out] 은 최소 `frames * 2` 길이여야 한다. 더 길어도 앞부분만 쓴다.
  void renderInto(Int16List out, int frames) {
    assert(out.length >= frames * 2, '버퍼가 짧다: ${out.length} < ${frames * 2}');
    final sw = _sw
      ..reset()
      ..start();

    _tidyQueues();

    var i = 0;
    while (i < frames) {
      // 이 구간 안에서 켜질 음이 있으면 거기까지만 처리한다.
      // 큐가 시각 순이라 맨 앞 하나만 보면 된다.
      var chunk = frames - i;
      if (_qHead < _queue.length) {
        final d = _queue[_qHead].at - _now;
        if (d < chunk) chunk = d;
      }
      if (_dHead < _drumQueue.length) {
        final d = _drumQueue[_dHead].at - _now;
        if (d < chunk) chunk = d;
      }
      if (chunk <= 0) {
        // 지금 켤 음들 — 앞에서부터 인덱스만 민다
        while (_qHead < _queue.length && _queue[_qHead].at <= _now) {
          final s = _queue[_qHead++];
          noteOn(
            s.voice,
            s.freq,
            s.dur,
            s.vel,
            soft: s.soft,
            glideF: s.glide,
            part: s.part,
          );
        }
        while (_dHead < _drumQueue.length && _drumQueue[_dHead].at <= _now) {
          final s = _drumQueue[_dHead++];
          drumOn(s.kit, s.inst, s.vel, tomFreq: s.tomFreq);
        }
        continue;
      }

      final nSlots = trackMix.slots.length;
      if (_accL.length < nSlots) {
        _accL = Float64List(nSlots);
        _accR = Float64List(nSlots);
      }
      final accL = _accL, accR = _accR;
      // 청크마다 한 번만 — 샘플마다 곱셈 세 번 안 하게
      final mg = masterGain * userGain * styleGain;

      for (var k = 0; k < chunk; k++) {
        // 4단계 4/N·5/N — 슬롯별로 따로 합산한 뒤 트랙 버스(TrackMix)를 태운다.
        // 기본값(투명)이면 예전의 "전부 한 번에 합산"과 같은 값이 된다.
        for (var s = 0; s < nSlots; s++) {
          accL[s] = 0;
          accR[s] = 0;
        }
        double lvL = 0, lvR = 0; // 라이브(건반) 버스로 갈 몫
        for (var vi = 0; vi < _live.length; vi++) {
          final n = _live[vi];
          n.next();
          var si = n.part;
          if (si == kPartLive) {
            lvL += n.outL;
            lvR += n.outR;
            continue;
          }
          if (si < 0 || si >= nSlots) si = nSlots - 1; // 편성 바뀌는 도중 남은 음 방어
          accL[si] += n.outL;
          accR[si] += n.outR;
        }
        double dL = 0, dR = 0;
        for (var vi = 0; vi < _liveDrums.length; vi++) {
          final d = _liveDrums[vi];
          d.next();
          dL += d.outL;
          dR += d.outR;
        }

        // 슬롯 순서대로 합산 — 예전 (bl+cl+ml+dl) 과 정확히 같은 덧셈 순서를 유지한다
        // (기본 3슬롯일 때 부동소수점 결과가 한 비트도 안 달라야 스모크 테스트 기준값이
        // 그대로 유지된다).
        var l = 0.0, r = 0.0, sendL = 0.0, sendR = 0.0;
        for (var s = 0; s < nSlots; s++) {
          final (pl, pr) = trackMix.slots[s].process(accL[s], accR[s]);
          l += pl;
          r += pr;
          sendL += trackMix.slots[s].rev * pl;
          sendR += trackMix.slots[s].rev * pr;
        }
        // 라이브(건반) 버스 — 슬롯 뒤·드럼 앞에 더한다. 건반을 안 치면 lv 가 정확히 0 이라
        // 더해도 값이 안 바뀐다(기존 곡 스모크 기준값 유지).
        final (ll, lr) = trackMix.live.process(lvL, lvR);
        l += ll;
        r += lr;
        sendL += trackMix.live.rev * ll;
        sendR += trackMix.live.rev * lr;

        // ── 비켜 주기 ── 드럼을 더하기 **전**에 건다.
        // 즉 "드럼 빼고 전부"가 눌린다 — 킥은 그대로 뚫고 나온다.
        if (duckAmount > 0) {
          l *= _duck;
          r *= _duck;
          sendL *= _duck;
          sendR *= _duck;
          _duck += (1 - _duck) * (1 - _duckRel);
        }

        final (dl, dr) = trackMix.drum.process(dL, dR);
        l = (l + dl) * mg;
        r = (r + dr) * mg;
        sendL = (sendL + trackMix.drum.rev * dl) * mg;
        sendR = (sendR + trackMix.drum.rev * dr) * mg;

        final mb = masterBus.process(l, r, sendL: sendL, sendR: sendR);
        l = mb.$1;
        r = mb.$2;

        // 마스터 인서트 — 꽂은 순서대로 (5단계 47/N)
        for (var i = 0; i < masterInserts.length; i++) {
          final fx = masterInserts[i];
          if (!fx.on) continue;
          fx.step(l, r);
          l = fx.outL;
          r = fx.outR;
        }
        final a = l.abs() > r.abs() ? l.abs() : r.abs();
        if (a > peakOut) peakOut = a;

        // ── 마스터 리미터 (룩어헤드) ──
        // 파형을 그 자리에서 구부리면(s/(1+|s|-0.85)) 그건 리미팅이 아니라 **왜곡**이다.
        // 여기서는 파형은 그대로 두고 크기만 움직인다.
        // 게인 판단은 지금 들어온 신호로 하고, 실제로 내보내는 건 4ms 전 신호다.
        // 순간값 하나만 보고 목표를 정하면 안 된다.
        // 뾰족한 피크는 몇 샘플 만에 지나가 버려서 게인이 조금 내려가다 만다.
        // 그런데 그 피크는 룩어헤드만큼 뒤에 출구에 도착하고, 그때는 게인이 이미 복구돼 있다.
        // (실측: 피크 1.48 인데 감쇠는 -1.9dB 뿐 → 하드클립 152회)
        // 그래서 '최근 최대값'을 들고 있는다 — 올라갈 땐 즉시, 내려갈 땐 천천히.
        if (a > _peak) {
          _peak = a;
        } else {
          _peak = a + (_peak - a) * _relCoef;
        }
        final target = _peak > _ceil ? _ceil / _peak : 1.0;
        if (target < _gr) {
          _gr = target + (_gr - target) * _atkCoef; // 빠르게 내려감
        } else {
          _gr = target + (_gr - target) * _relCoef; // 천천히 올라옴 (펌핑 방지)
        }
        if (_gr < minGain) minGain = _gr;

        final di = _dlIdx * 2;
        var ol = _dl[di] * _gr;
        var or_ = _dl[di + 1] * _gr;
        _dl[di] = l;
        _dl[di + 1] = r;
        _dlIdx++;
        if (_dlIdx >= _look) _dlIdx = 0;

        // 여기까지 왔는데도 넘치면 룩어헤드가 모자란 것 — 세면 알 수 있다
        if (ol > 0.999) {
          ol = 0.999;
          clipped++;
        } else if (ol < -0.999) {
          ol = -0.999;
          clipped++;
        }
        if (or_ > 0.999) {
          or_ = 0.999;
          clipped++;
        } else if (or_ < -0.999) {
          or_ = -0.999;
          clipped++;
        }
        l = ol;
        r = or_;
        out[(i + k) * 2] = (l * 32767).round();
        out[(i + k) * 2 + 1] = (r * 32767).round();
      }

      // 끝난 음 회수
      for (var vi = _live.length - 1; vi >= 0; vi--) {
        if (!_live[vi].active) {
          final n = _live[vi];
          // 잡고 있던 것이면 손잡이도 같이 뗀다 — 안 떼면 그 번호가 **다음에
          // 그 자리에 들어온 음**을 가리키게 되고, 손을 뗄 때 엉뚱한 소리가 꺼진다.
          if (_held.isNotEmpty) {
            _held.removeWhere((_, v) => identical(v, n));
          }
          n.reset();
          _free.add(n);
          _live.removeAt(vi);
        }
      }
      for (var vi = _liveDrums.length - 1; vi >= 0; vi--) {
        if (!_liveDrums[vi].active) {
          final d = _liveDrums[vi];
          d.reset();
          _freeDrums.add(d);
          _liveDrums.removeAt(vi);
        }
      }
      _now += chunk; // 예약이 절대 시각이라 큐를 훑어 내릴 필요가 없다
      i += chunk;
    }

    sw.stop();
    final audioMicros = frames / kSampleRate * 1e6;
    if (audioMicros > 0) {
      final inst = sw.elapsedMicroseconds / audioMicros;
      loadAvg = loadAvg == 0 ? inst : (loadAvg * 0.88 + inst * 0.12);
      if (inst > loadPeak) loadPeak = inst;
    }
    callbacks++;
  }
}

class _Sched {
  final int at;

  /// 같은 시각 예약의 순서를 못 박는 일련번호.
  /// Dart 의 List.sort 는 안정 정렬을 보장하지 않는다. 순서가 흔들리면 전역 RNG
  /// (휴머나이즈)를 소비하는 차례가 달라져서 **같은 곡인데 렌더 결과가 매번 미세하게 달라진다.**
  final int seq;
  final String voice;
  final double freq, dur;
  final int vel;
  final bool soft;
  final double glide;
  final int part;
  _Sched(
    this.at,
    this.seq,
    this.voice,
    this.freq,
    this.dur,
    this.vel,
    this.soft,
    this.glide,
    this.part,
  );
}

class _DrumSched {
  final int at;
  final int seq;
  final String kit, inst;
  final int vel;
  final double tomFreq;
  _DrumSched(this.at, this.seq, this.kit, this.inst, this.vel, this.tomFreq);
}

// ───────────────────────── 음이름 ↔ 주파수 ─────────────────────────
const List<String> kNoteNames = [
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

/// ♭ 쪽 음이름. **♯ 로만 적으면 단조가 틀린 이름으로 보인다** —
/// C단조는 Eb·Ab·Bb 인데 라이브 패드에 D#·G#·A# 로 찍혀 있었다.
/// 소리는 같지만 악보를 읽는 사람에게는 **다른 음**이다.
const List<String> kNoteNamesFlat = [
  'C',
  'Db',
  'D',
  'Eb',
  'E',
  'F',
  'Gb',
  'G',
  'Ab',
  'A',
  'Bb',
  'B',
];

/// 이 조가 ♯ 쪽인가. 단조는 **나란한 장조**(+3반음)로 판단한다.
/// ♯ 조 = C·G·D·A·E·B·F♯ 장조. 나머지는 ♭ 쪽이다.
bool keyUsesSharps(int root, String mode) {
  final major = ((mode == 'minor' ? root + 3 : root) % 12 + 12) % 12;
  return const {0, 7, 2, 9, 4, 11, 6}.contains(major);
}

/// MIDI 번호 → 주파수 (69 = A4 = 440Hz)
double mfreq(int midi) => 440 * math.pow(2, (midi - 69) / 12).toDouble();

String noteName(int midi) => '${kNoteNames[midi % 12]}${midi ~/ 12 - 1}';

/// 그 조에 맞는 음이름 — 라이브 패드처럼 **사람이 읽는 자리**에 쓴다.
String noteNameIn(int midi, int root, String mode) {
  final names = keyUsesSharps(root, mode) ? kNoteNames : kNoteNamesFlat;
  return '${names[((midi % 12) + 12) % 12]}${midi ~/ 12 - 1}';
}

/// 악기 계열에 맞는 기본 옥타브 — 베이스는 낮게, 벨은 높게 들려야 비교가 된다
int defaultRoot(String voice) {
  if (BASS_VOICE[voice] == true || voice == 'upright') return 36; // C2
  if (voice == 'bell' || voice == 'marimba' || voice == 'chip') return 72; // C5
  if (voice == 'pad' ||
      voice == 'analogpad' ||
      voice == 'strings' ||
      voice == 'jpstrings') {
    return 48; // C3
  }
  return 60; // C4
}
