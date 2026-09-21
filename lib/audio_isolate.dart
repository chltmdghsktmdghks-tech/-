// 오디오를 **별도 아이솔레이트**에서 돌린다.
//
// 왜 옮기는가 — 실측으로 확정된 이유:
//   화면부하 끔 · 오디오 여유 98% · 리미터 감쇠 -1.5dB 인데도 **버퍼 바닥 538회**.
//   CPU 도 음량도 문제가 아니었다. 소리를 *만드는* 게 아니라 *넘기는* 길이 막힌 것이다.
//
//   원래 구조: flutter_pcm_sound 의 feed 콜백은 **루트(UI) 아이솔레이트로** 온다.
//   그 아이솔레이트는 위젯을 다시 그리는 일도 한다. 건반을 누르면 setState → 화면 재빌드,
//   그 몇 ms 동안 feed 가 밀린다. 버퍼가 얇으면 그대로 소리가 끊긴다.
//   → 웹(WebView)에서 도망쳐 나온 것과 **같은 종류의 문제**가 작게 남아 있던 것.
//
// 그래서 여기서는 콜백을 아예 안 쓴다. 백그라운드 아이솔레이트가 **스스로** 시계를 보고
// "지금 얼마나 앞질러 있나"를 계산해 모자란 만큼 채운다. UI 가 아무리 바빠도 상관없다.
//
// 주의: 백그라운드 아이솔레이트에서 플랫폼 채널을 쓰려면
// `BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken)` 가 먼저다.
// (플러그인이 보내오는 콜백은 여전히 루트로 가므로 받을 수 없다. 그래서 '스스로' 하는 것)

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_pcm_sound/flutter_pcm_sound.dart';

import 'engine.dart';
import 'fx.dart';
import 'genre_mix.dart';
import 'mixer.dart';
import 'synth.dart' show kPartLive;

/// 이름으로 버스 하나. 'drum'·'live' 는 붙박이, 나머지는 트랙 슬롯이다.
/// `_cBus` 가 쓰던 삼항 연산을 인서트 명령 셋이 같이 쓰려고 함수로 뺐다.
TrackMix? _busOf(Engine engine, String name) => name == 'drum'
    ? engine.trackMix.drum
    : name == 'live'
    ? engine.trackMix.live
    : engine.trackMix.bus(name);

/// 이름으로 인서트 목록 하나. 'master' 만 TrackMix 가 아니다.
List<Fx>? _fxListOf(Engine engine, String name) =>
    name == 'master' ? engine.masterInserts : _busOf(engine, name)?.inserts;

/// 화면에 보여줄 지표 묶음
class AudioStats {
  final double headroom, worstHeadroom, grDb, worstGrDb, peakOut;
  final int bufferEmpty, starved, active, maxActive, clipped, aheadFrames;
  final int drumActive, maxActiveDrums, drumStarved;
  final double compGrDb;

  /// 급식 루프가 한 바퀴 도는 데 걸린 **최대** 시간(ms). 3ms 를 노렸는데 이게 크면
  /// 그 사이 버퍼가 그만큼 더 빠진 것이다 = 언더런의 직접 원인.
  final double maxPollGapMs;

  /// 플러그인 큐에 남았던 **최소** 프레임 수. 0 에 닿으면 쓰기 스레드가 굶은 것이다.
  final int minQueueFrames;

  /// 20ms 넘게 지체된 횟수. 1~2 면 곡 시작 때 한 번(예약 3700개 처리)이고,
  /// 계속 늘면 상시 문제(GC 등)다 — 이 둘은 고치는 방법이 완전히 다르다.
  final int lateTicks;

  /// **지체를 셋으로 나눠 본다** (Phase 1 후속).
  ///
  /// `maxPollGapMs` 하나만 보면 "늦었다"는 것만 알지 **왜** 늦었는지를 모른다.
  /// 52/N 에서 20ms 초과가 630회 잡혔는데 원인을 못 짚은 이유가 이것이다.
  ///  · [maxRenderMs] — 소리를 만드는 데 쓴 시간 (우리 잘못)
  ///  · [maxSchedMs]  — 다음 판을 예약하는 데 쓴 시간 (한 판이 클수록 튄다)
  ///  · 나머지(gap − render − sched) — **우리가 안 돌고 있던 시간**
  ///    (타이머 정밀도 · GC · 시스템이 뺏어 감)
  final double maxRenderMs, maxSchedMs;

  /// 5단계 3/N — 씬 루프가 도는 중인가, 지금 한 판의 어디쯤인가(0~1).
  /// **귀에 들리는 지점** 기준이다(만들어 둔 앞부분은 빼고 센다).
  final bool looping;
  final double loopPos;

  /// 버스 이름 → 그 사이의 봉우리. 믹서의 **트랙별 미터**가 읽는다.
  /// 지표가 올 때마다 엔진에서 비워지므로 「이 250ms 동안의 제일 큰 값」이다.
  final Map<String, double> busPeaks;
  final int loopCount;

  const AudioStats({
    this.headroom = 100,
    this.worstHeadroom = 100,
    this.grDb = 0,
    this.worstGrDb = 0,
    this.peakOut = 0,
    this.bufferEmpty = 0,
    this.starved = 0,
    this.active = 0,
    this.maxActive = 0,
    this.clipped = 0,
    this.aheadFrames = 0,
    this.drumActive = 0,
    this.maxActiveDrums = 0,
    this.drumStarved = 0,
    this.compGrDb = 0,
    this.maxPollGapMs = 0,
    this.minQueueFrames = -1,
    this.lateTicks = 0,
    this.maxRenderMs = 0,
    this.maxSchedMs = 0,
    this.looping = false,
    this.loopPos = 0,
    this.loopCount = 0,
    this.busPeaks = const <String, double>{},
  });

  static AudioStats _fromList(List<dynamic> m) => AudioStats(
    headroom: m[0] as double,
    worstHeadroom: m[1] as double,
    grDb: m[2] as double,
    worstGrDb: m[3] as double,
    peakOut: m[4] as double,
    bufferEmpty: m[5] as int,
    starved: m[6] as int,
    active: m[7] as int,
    maxActive: m[8] as int,
    clipped: m[9] as int,
    aheadFrames: m[10] as int,
    drumActive: m[11] as int,
    maxActiveDrums: m[12] as int,
    drumStarved: m[13] as int,
    compGrDb: m[14] as double,
    maxPollGapMs: m[15] as double,
    minQueueFrames: m[16] as int,
    lateTicks: m[17] as int,
    looping: m[18] as bool,
    loopPos: m[19] as double,
    loopCount: m[20] as int,
    maxRenderMs: m[21] as double,
    maxSchedMs: m[22] as double,
    // 옛 판(짧은 메시지)에서도 안 죽는다 — 없으면 빈 표다
    busPeaks: m.length > 23
        ? Map<String, double>.from(m[23] as Map)
        : const <String, double>{},
  );
}

// 명령 종류 — 리스트 첫 칸에 넣는다. 문자열보다 싸다.
const int _cNote = 0;
const int _cBatch = 1;
const int _cOff = 2;
const int _cAhead = 3;
const int _cReset = 4;
const int _cQuality = 5;
const int _cDrum = 6;
const int _cDrumBatch = 7;
const int _cMaster = 8;
const int _cGenreMix = 9;
const int _cBus = 10;
const int _cMasterVol = 11;
const int _cSlots = 12;
const int _cLoop = 13;
const int _cStyleGain = 14;
const int _cInserts = 15; // 인서트 목록 갈아 끼우기
const int _cFxParam = 16; // 인서트 손잡이 하나
const int _cFxOn = 17; // 인서트 켜고 끄기
const int _cDuck = 18; // 킥이 칠 때 나머지가 비켜 주는 세기
// 아래 둘은 **`handleAudioMessage` 가 아니라 아이솔레이트 본체**가 받는다 —
// 급식 루프의 지역 변수(시계·먹인 양)를 되돌려야 해서다.
const int _cSleep = 19; // 화면을 나갔다 — 장치를 놓는다
const int _cWake = 20;
const int _cHoldOn = 21; // 꾹 눌러 소리 유지 — 손가락 번호로 잡는다
const int _cHoldOff = 22; // 그 손가락을 놓는다 (번호 −1 = 전부) // 돌아왔다 — 장치를 다시 연다
const int _cAdsr = 23; // 그 버스의 ADSR 손잡이(신스 악기만) 갈아 끼우기
const int _cUni = 24; // 그 버스의 유니즌 폭(신스 악기만) 갈아 끼우기

/// 메인(UI) 쪽에서 쓰는 손잡이
class AudioClient {
  late final SendPort _tx;
  final _statsCtl = StreamController<AudioStats>.broadcast();
  AudioStats stats = const AudioStats();

  /// 앞질러 만들어 두는 **총량**(프레임). 이게 곧 건반 지연이다.
  /// 플러그인 큐 + AudioTrack 내부 버퍼를 합친 값이라, AudioTrack 크기(약 1024)보다
  /// 넉넉히 커야 한다. 작게 잡으면 AudioTrack 이 늘 굶어서 계속 끊긴다.
  /// 건반을 칠 때 쓰는 값(화면의 '건반 지연' 선택). 손가락에 붙어야 하므로 작다.
  int aheadFrames = 3072;

  /// 곡을 재생할 때 쓰는 값. **실측으로 정한 수**다:
  /// 급식 루프가 상시 20~36ms 씩 밀리는데(초당 1.2회), 36ms 면 48000×0.036 = 1728프레임이
  /// 빠진다. 거기에 AudioTrack 몫(1024)과 지체가 겹칠 여유까지 얹었다.
  /// 곡 재생에는 128ms 지연이 아무 문제가 안 된다 — 시작이 그만큼 늦을 뿐이다.
  /// (건반은 다르다. 그래서 나눠 쓴다 — 실제 DAW 도 이렇게 한다)
  static const int kAheadSong = 6144;

  bool _songMode = false;
  double get latencyMs => aheadFrames / 48000 * 1000;

  /// 곡 재생 진입/이탈. 재생 중엔 큰 버퍼로, 건반을 누르면 작은 버퍼로 돌아간다.
  /// **큐를 비우지 않는다** — 목표만 바꾸면 자연히 채워지거나 줄어든다.
  void setSongMode(bool on) {
    if (_songMode == on) return;
    _songMode = on;
    _tx.send([
      _cAhead,
      on ? (aheadFrames > kAheadSong ? aheadFrames : kAheadSong) : aheadFrames,
    ]);
  }

  // ── 마스터 버스 — 이 아이솔레이트 쪽 거울(UI 슬라이더가 읽고 쓴다).
  // 실제 계산은 오디오 아이솔레이트의 MasterBus 가 한다. 여기 값이 진실이 아니라
  // 저쪽으로 보낸 값이 진실이다 — 이건 화면에 슬라이더 위치를 보여주기 위한 거울일 뿐.
  double eqLoDb = 0, eqMidDb = 0, eqHiDb = 0;
  double hpfFreq = 20;
  bool compOn = false;
  double compThr = -14;
  double compMakeupDb = 0; // 컴프가 줄인 만큼 다시 올려 받는 양 — 손으로 맞춘다(자동 보정 아님)
  double revWet = 0; // 웹 UI 범위 0~0.4, 필드는 0~1 허용
  String revKind = 'hall';
  String eqMode = '3'; // '3' | '20' — 3단계 3/N
  final List<double> eq20 = List<double>.filled(20, 0.0); // 20밴드 모드 밴드별 dB
  bool eqFirst = true; // 웹 MASTER.order[0]==='eq'

  /// 지금 거울 값을 오디오 아이솔레이트로 보낸다. 슬라이더를 바꿀 때마다 부른다.
  void syncMaster() {
    _tx.send([
      _cMaster,
      eqLoDb, eqMidDb, eqHiDb,
      hpfFreq, 20000.0, // lpf 는 아직 UI 가 없어 고정
      compOn ? 1.0 : 0.0, compThr, 3.0, 0.004, 0.2, 8.0, compMakeupDb,
      revWet, revKind,
      eqMode, List<double>.from(eq20), eqFirst, // 맨 뒤에 붙여서 기존 순서 안 깼다 — 3단계 3/N
    ]);
  }

  Stream<AudioStats> get statsStream => _statsCtl.stream;

  static Future<AudioClient> start() async {
    final c = AudioClient();
    final rx = ReceivePort();
    final ready = Completer<SendPort>();
    await Isolate.spawn(_audioMain, [
      rx.sendPort,
      RootIsolateToken.instance!,
    ], debugName: 'audio');
    rx.listen((msg) {
      if (msg is SendPort) {
        ready.complete(msg);
      } else if (msg is List) {
        c.stats = AudioStats._fromList(msg);
        c._statsCtl.add(c.stats);
      }
    });
    c._tx = await ready.future;
    return c;
  }

  /// 5단계 — [part] 기본값이 **라이브 버스**다. 이 함수는 건반(손으로 치는 음) 전용이고,
  /// 곡 재생은 전부 [batch] 로 슬롯을 지정해서 보낸다.
  void noteOn(
    String voice,
    double freq,
    double dur,
    int vel, {
    bool soft = false,
    double glideF = 0,
    int part = kPartLive,
  }) {
    _tx.send([_cNote, voice, freq, dur, vel, soft, glideF, 0.0, part]);
  }

  /// 5단계 — 믹서의 마스터 페이더(0~1.6). 엔진의 고정 헤드룸에 곱해진다.
  void setMasterVol(double v) => _tx.send([_cMasterVol, v]);

  /// 5단계 34/N — 스타일 보정(스타일마다 곡 크기가 달라 붙여 준다).
  /// 사용자 마스터 페이더와 **따로** 간다 — 믹서 숫자를 안 건드린다.
  void setStyleGain(double v) => _tx.send([_cStyleGain, v]);

  // ── 인서트 (5단계 46/N) ──

  /// 그 버스의 인서트를 **통째로** 갈아 끼운다. [types] 는 꽂은 순서.
  /// 순서가 곧 소리라서 목록 그대로 보낸다.
  ///
  /// 손잡이 값도 같이 보낸다 — 꽂자마자 값이 기본값으로 튀면 안 된다
  /// (저장해 둔 곡을 열 때가 그렇다).
  /// **꾹 누르는 동안 계속 나는 소리.** [id] 는 손가락(포인터) 번호다.
  ///
  /// 라이브 패드가 여태 「짧게/보통/길게」 중 미리 고른 길이로만 났다 —
  /// 어떻게 만지든 같았다. 누르고 있는 동안 나야 라이브다.
  void holdOn(
    int id,
    String voice,
    double freq,
    int vel, {
    bool soft = false,
    double glideF = 0,
    int part = kPartLive,
  }) => _tx.send([_cHoldOn, id, voice, freq, vel, soft, glideF, part]);

  /// 그 손가락을 놓는다. `id: -1` 이면 잡고 있는 것 **전부**.
  void holdOff(int id) => _tx.send([_cHoldOff, id]);

  void setInserts(String bus, List<Map<String, dynamic>> slots) =>
      _tx.send([_cInserts, bus, slots]);

  /// 그 버스에 실릴 ADSR — 신스 악기만 뜻이 있다(표본 악기는 표본 자체의
  /// 소리 모양이라 무시된다). null 이면 그 자리는 악기 기본값 그대로.
  /// (사용자 요청, 2026-09-15: "악기들 ADSR 필요한 악기들은 악기 설정에
  /// 넣어 놓자")
  void setAdsr(
    String bus, {
    double? attack,
    double? decay,
    double? sustain,
    double? release,
  }) => _tx.send([_cAdsr, bus, attack, decay, sustain, release]);

  /// 유니즌 폭(cent) 손잡이. null 이면 악기 기본값(`Inst.uni`) 그대로.
  void setUni(String bus, double? cents) => _tx.send([_cUni, bus, cents]);

  /// 손잡이 하나만. 끄는 동안 초당 수십 번 오므로 **제일 가벼운 길**로 보낸다.
  void setFxParam(String bus, int index, String key, double v) =>
      _tx.send([_cFxParam, bus, index, key, v]);

  void setFxOn(String bus, int index, bool on) =>
      _tx.send([_cFxOn, bus, index, on]);

  /// 5단계 2/N — **트랙마다 자기 버스**. [names] 는 드럼이 아닌 트랙의 id 순서.
  /// 곡(데모) 재생은 `setGenreMix()` 로 자기 편성을 덮어쓰므로, 프로젝트 화면으로
  /// 돌아올 때 이걸 다시 불러 줘야 한다(main.dart `_syncBuses`).
  void configureBuses(List<String> names) => _tx.send([_cSlots, names]);

  /// 5단계 3/N — 씬을 **무한 반복**한다. [notes]/[drums] 는 한 판 분량,
  /// [loopSec] 은 한 판 길이. 다음 판 예약은 오디오 아이솔레이트가 알아서 한다.
  ///
  /// [restart] 가 false 면 **박자를 안 건드리고 내용만 갈아 끼운다** — 돌고 있는 중에
  /// 패턴·음색을 바꾸면 다음 판부터 새 내용이 나온다. 정지는 [allOff].
  /// [unitSec] 은 **화면 눈금 한 칸의 길이**다. 보통은 판 길이와 같아서 안 준다.
  /// 다른 경우가 하나 있다 — 변형(계획 6-1)을 켜면 씬 루프가 여러 바퀴를 **한 판으로**
  /// 돌린다(바퀴마다 내용이 달라야 하므로). 그때도 화면 격자는 한 바퀴짜리이므로,
  /// 재생 위치는 한 바퀴 안의 위치로 돌려줘야 머리가 안 튄다.
  void setLoop(
    List<List<dynamic>> notes,
    List<List<dynamic>> drums,
    double loopSec, {
    bool restart = true,
    double unitSec = 0,
  }) => _tx.send([_cLoop, notes, drums, loopSec, restart, unitSec]);

  /// 여러 음을 한 번에 예약한다. 한 개씩 보내면 아이솔레이트 사이 왕복이 그만큼 늘어난다.
  /// 각 항목: [voice, freq, dur, vel, soft, glide, delaySec, part?]
  /// [part] 는 4단계 4/N 도입, 5/N 에서 일반화 — `trackMix.slots` 의 인덱스(어느 트랙
  /// 버스로 갈지, GENRE_MIX 를 걸 자리). 배열형 6곡은 kPartBass(0)/Chord(1)/Melody(2),
  /// 객체형 롱폼(트랩 등)은 그 곡의 슬롯 순서(`genre_mix.dart` `melodicSlotsFor()`)에서
  /// 구한 인덱스. 8번째 칸이 없으면 melody(투명 기본값)로 간주해서, 이 필드를 안 쓰던
  /// 기존 호출부(건반 화음/아르페지오/훑기/부하시험)는 그대로 둬도 된다.
  void batch(List<List<dynamic>> notes) {
    _tx.send([_cBatch, notes]);
  }

  void drumOn(String kit, String inst, int vel, {double tomFreq = 180}) {
    _tx.send([_cDrum, kit, inst, vel, tomFreq]);
  }

  /// 여러 타격을 한 번에 예약한다. 각 항목: [kit, inst, vel, tomFreq, delaySec]
  void drumBatch(List<List<dynamic>> hits) {
    _tx.send([_cDrumBatch, hits]);
  }

  /// 4단계 4/N — 장르 몫 GENRE_MIX 를 트랙 버스로 보낸다. [genre] 가 null 이거나 지원하지
  /// 않는 장르(genre_mix.dart 의 kGenreMix 에 없음)면 전부 투명한 기본값으로 되돌린다.
  void setGenreMix(String? genre) => _tx.send([_cGenreMix, genre]);

  /// 킥↔베이스 비켜 주기 (계획 6-5). **장르 믹스와 따로 보낸다** —
  /// 씬 재생은 `setGenreMix(null)` 로 장르 몫을 걷어내는데(사용자 믹서 값을
  /// 살리려고), 비켜 주기는 슬롯별 값이 아니라 그 장르의 성격이라 남아야 한다.
  /// [relSec] 는 킥이 지나간 뒤 되돌아오는 시간(초) — 생략하면 지금 값을
  /// 그대로 둔다(장르 바뀔 때 세기만 갈고 복귀 시간은 사용자가 맞춘 대로
  /// 두려고, `sequencer.dart`).
  void setDuck(double amount, {double? relSec}) =>
      _tx.send([_cDuck, amount, relSec]);

  /// 5단계 — 믹서 화면이 트랙 버스 하나를 직접 조절한다.
  /// [name] 이 'drum' 이면 드럼 버스, 아니면 그 이름의 멀로딕 버스.
  /// GENRE_MIX 가 걸어 둔 값 위에 사용자가 덮어쓰는 구조다(곡을 다시 틀면 다시 덮인다).
  /// 트랙 버스 하나를 맞춘다. **뒤에 붙은 넷(hpf·lpf·lfo)은 장르가 정하는 값**이다 —
  /// 사용자 UI 는 없지만 `kGenreMix` 가 슬롯마다 적어 둔 것이라 소리에 실려야 한다.
  void setBus(
    String name, {
    double? vol,
    double? pan,
    double? rev,
    double? lo,
    double? mid,
    double? hi,
    double? hpf,
    double? lpf,
    double? lfoHz,
    double? lfoDepth,
  }) {
    _tx.send([
      _cBus,
      name,
      vol,
      pan,
      rev,
      lo,
      mid,
      hi,
      hpf,
      lpf,
      lfoHz,
      lfoDepth,
    ]);
  }

  void allOff() => _tx.send([_cOff]);
  void resetStats() => _tx.send([_cReset]);
  void setQuality(bool high) => _tx.send([_cQuality, high]);

  /// 앱이 뒤로 갔다 — **소리 장치를 놓는다.**
  ///
  /// 안 놓으면 안드로이드가 `AudioMix` 잠금을 계속 잡고 있어서 **화면을 끄고
  /// 다른 앱을 써도 CPU 가 안 잔다.** 폰에서 직접 봤다 — 앱을 켜고 홈으로 나간 뒤
  /// 2분이 지나도 잠금이 그대로였다(`dumpsys power` 의 `PARTIAL_WAKE_LOCK 'AudioMix'`).
  /// 아무 소리도 안 나는데 배터리만 닳는다.
  ///
  /// **소리가 나는 중이면 부르지 않는다** — 듣다가 화면을 나가는 사람도 있다.
  void sleep() => _tx.send([_cSleep]);

  /// 돌아왔다 — 장치를 다시 연다. [sleep] 뒤에만 뜻이 있다.
  void wake() => _tx.send([_cWake]);

  void setAhead(int frames) {
    aheadFrames = frames;
    if (!_songMode) _tx.send([_cAhead, frames]);
  }
}

// ══════════════ 여기서부터는 백그라운드 아이솔레이트 ══════════════

/// 씬 루프 (5단계 3/N) — 한 판 분량의 프로그램만 들고 있다가, 재생 위치가 다가오면
/// 다음 판을 예약한다. **엔진 시계(`Engine.nowFrames`)로 계산**하는 게 핵심이다.
/// UI 쪽 타이머로 하면 시계가 어긋나서 판마다 조금씩 밀린다(그리고 그 밀림이 쌓인다).
///
/// 아이솔레이트 안에 있던 코드를 클래스로 뺐다 — 이래야 시험에서 진짜로 돌려 볼 수 있다
/// (베낀 코드를 시험하면 시험을 통과해도 실물이 맞는지는 모른다).
class LoopState {
  List<dynamic>? notes;
  List<dynamic>? drums;
  int frames = 0; // 한 판 길이(프레임). 0 = 루프 꺼짐
  int unitFrames = 0; // 화면 눈금 한 칸(프레임). 보통 frames 와 같다
  int nextAt = 0; // 다음 판을 시작할 절대 프레임
  int startAt = 0; // 가장 최근에 예약한 판의 시작(위치 표시 기준)
  int count = 0;

  bool get on => frames > 0 && notes != null;

  void clear() {
    notes = null;
    drums = null;
    frames = 0;
    unitFrames = 0;
  }

  /// 프로그램을 넣는다. [restart] 가 false 면 **박자를 안 건드리고 내용만** 바꾼다
  /// (돌고 있는 중에 패턴을 갈아 끼우는 길 — 다음 판부터 새 내용).
  void set(
    List<dynamic> n,
    List<dynamic> d,
    double sec,
    bool restart,
    Engine engine, {
    double unitSec = 0,
  }) {
    final wasOff = !on;
    notes = n;
    drums = d;
    frames = (sec * kSampleRate).round();
    // 눈금을 안 주면 판 전체가 한 칸 — 예전과 똑같이 돈다.
    unitFrames = unitSec > 0 ? (unitSec * kSampleRate).round() : frames;
    if (unitFrames <= 0 || unitFrames > frames) unitFrames = frames;
    if (frames <= 0) {
      clear();
      return;
    }
    if (wasOff || restart) {
      engine.clearSchedule();
      nextAt = engine.nowFrames;
      startAt = engine.nowFrames;
      count = 0;
    }
  }

  /// 렌더보다 **앞서서** 예약해 둔다. 렌더가 이미 지나간 자리에 넣으면 그 판은 통째로
  /// 안 들린다. [guard] 만큼(앞질러 만드는 양 + 여유) 미리 넣는다.
  /// [maxPerTick] 은 템포가 아주 빠를 때 한 바퀴에 몰려 들어가는 걸 막는 안전장치.
  void topUp(Engine engine, int guard, {int maxPerTick = 8}) {
    if (!on) return;
    var made = 0;
    while (nextAt - engine.nowFrames < guard && made < maxPerTick) {
      var delay = (nextAt - engine.nowFrames) / kSampleRate;
      if (delay < 0) delay = 0; // 밀렸으면 지금 바로
      final ds = drums;
      if (ds != null) {
        for (final d in ds) {
          final e = d as List;
          engine.scheduleDrum(
            delay + (e[4] as double),
            e[0] as String,
            e[1] as String,
            e[2] as int,
            tomFreq: e[3] as double,
          );
        }
      }
      for (final n in notes!) {
        final e = n as List;
        engine.schedule(
          delay + (e[6] as double),
          e[0] as String,
          e[1] as double,
          e[2] as double,
          e[3] as int,
          soft: e[4] as bool,
          glideF: e[5] as double,
          part: e[7] as int,
        );
      }
      startAt = nextAt;
      nextAt += frames;
      count++;
      made++;
    }
  }

  /// 들리는 지점([head] 프레임)이 **눈금 한 칸**의 어디쯤인가 — 0~1.
  /// 눈금을 따로 안 줬으면 칸 = 판이라 예전과 같다.
  double posOf(int head) {
    if (frames <= 0) return 0;
    var d = head - startAt;
    // 아직 **이전 판**을 듣고 있을 수 있다(예약은 앞질러 가 있으므로). 그때는 뒤로 돌린다.
    while (d < 0) {
      d += frames;
    }
    final u = unitFrames > 0 ? unitFrames : frames;
    return ((d % frames) % u) / u;
  }
}

/// 한 번에 만드는 덩어리(상한). 3ms 폴링에서는 보통 ~144프레임이라 한 번에 끝난다.
const int _kChunk = 1024;

/// 몇 ms 마다 "지금 앞질러 있는 양"을 확인할까.
///
/// **자주 볼수록 좋다.** 8ms 로 늘려 봤더니 오히려 나빠졌다(언더런 초당 23회 → 92회).
/// 이유: `Future.delayed` 는 정확하지 않고, 폴링 사이에 렌더가 끼면 실제 간격이 더 벌어진다.
/// 그동안 버퍼는 계속 빠지므로 파이는 깊이가 그만큼 커진다.
/// 채널 왕복 횟수보다 **버퍼가 얼마나 깊이 파이느냐**가 훨씬 중요하다.
const int _kPollMs = 3;

/// 이만큼 모자라기 전엔 채우지 않는다. 자잘한 호출을 막는다.
const int _kMinTopUp = 32;

/// 시계 드리프트 보정 주기 — 우리 시계와 오디오 장치 시계는 아주 조금씩 어긋난다.
const int _kSyncEveryMs = 1500;

/// AudioTrack 이 자기 안에 들고 있는 양(프레임). 플러그인의 잔량 조회에는 안 잡힌다.
/// A17 실측 1024. 다른 폰에서 다르면 드리프트 보정이 알아서 흡수한다.
const int kDeviceBuffer = 1024;

void _audioMain(List<dynamic> args) async {
  final SendPort tx = args[0] as SendPort;
  final RootIsolateToken token = args[1] as RootIsolateToken;

  // 이게 있어야 백그라운드 아이솔레이트에서 플랫폼 채널을 쓸 수 있다
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);

  // 표본팩 로드는 여기서 안 건다 — `synth.dart` 의 `noteOn` 이 그 악기를
  // **처음 만났을 때** 스스로 트리거한다(`sampler.dart`). 곡이 표본 악기를
  // 하나도 안 쓰면 표본을 아예 안 읽는다(악기 넷을 다 미리 읽던 전과 다름).

  final engine = Engine();
  var ahead = 3072;

  // ── 진단: 급식 루프가 실제로 얼마나 촘촘히 도는가 ──
  // `Future.delayed(3ms)` 는 약속이 아니다. 이 아이솔레이트가 렌더 중이거나 메시지를
  // 처리 중이면 그만큼 늦게 돈다. 늦은 만큼 버퍼가 더 빠지므로 이게 언더런의 직접 원인이다.
  var lastTickUs = 0;
  var maxGapMs = 0.0;
  // 지체를 나눠 재려고 — 렌더에 쓴 시간, 예약에 쓴 시간 (Phase 1 후속)
  var maxRenderMs = 0.0, maxSchedMs = 0.0;
  var minQueue = -1;
  var lastQueueProbe = 0;
  var probing = false;
  var lateTicks = 0;

  final loop = LoopState();

  final rx = ReceivePort();
  tx.send(rx.sendPort);
  // 장치를 놓았다 / 다시 열어 달라 — **여기서 받는다.**
  // `handleAudioMessage` 로 넘기지 않는 까닭은 되돌려야 할 것이 아래 급식 루프의
  // 지역 변수(시계·먹인 양·드리프트 보정)라서다. 함수 밖에서는 못 만진다.
  var asleep = false;
  var wakeWanted = false;

  rx.listen((msg) {
    final m = msg as List;
    if (m.isNotEmpty && m[0] == _cSleep) {
      asleep = true;
      return;
    }
    if (m.isNotEmpty && m[0] == _cWake) {
      wakeWanted = true;
      return;
    }
    ahead = handleAudioMessage(m, engine, loop, ahead, () {
      maxGapMs = 0;
      maxRenderMs = 0;
      maxSchedMs = 0;
      minQueue = -1;
      lateTicks = 0;
    });
  });

  FlutterPcmSound.setLogLevel(LogLevel.error);
  await FlutterPcmSound.setup(sampleRate: kSampleRate, channelCount: kChannels);
  // 콜백은 루트 아이솔레이트로만 가므로 쓰지 않는다. 임계값도 의미 없어 크게 둔다.
  await FlutterPcmSound.setFeedThreshold(0);

  // ── 급식 버퍼 ── **한 개만 만들어 계속 돌려쓴다.**
  //
  // 예전엔 `engine.render(n)` 이 부를 때마다 `Int16List` 를 새로 만들었다.
  // 3ms 마다 부르니 1024프레임 기준 4KB × 초당 수백 번 = **초당 몇 MB 의 쓰레기**다.
  // 그 청소(GC)가 급식 루프를 멈춰 세우고, 그게 '급식 지체'로 잡혔다
  // (52/N 실측: 20ms 초과 630회).
  //
  // 플러그인 쪽 `feed` 도 같이 고쳤다 — 뷰의 offset/length 를 지키게.
  // 안 그러면 버퍼 앞부분만 담아 보내도 뒤쪽 쓰레기까지 재생된다.
  final feedBuf = Int16List(_kChunk * 2);
  void feedFrames(int n) {
    engine.renderInto(feedBuf, n);
    // ignore: unawaited_futures
    FlutterPcmSound.feed(
      PcmArrayInt16(bytes: ByteData.view(feedBuf.buffer, 0, n * 4)),
    );
  }

  // 빈 채로 start 하면 바로 바닥나므로 미리 채워 둔다
  var fed = 0;
  Future<void> primeAndStart() async {
    fed = 0;
    final prime = ahead;
    while (fed < prime) {
      final n = _kChunk < prime - fed ? _kChunk : prime - fed;
      engine.renderInto(feedBuf, n);
      await FlutterPcmSound.feed(
        PcmArrayInt16(bytes: ByteData.view(feedBuf.buffer, 0, n * 4)),
      );
      fed += n;
    }
    FlutterPcmSound.start();
  }

  await primeAndStart();
  // 위의 '미리 채우기'는 재생 전에 몰아서 만드는 구간이라 CPU 점유가 100% 로 잡힌다.
  // 그대로 두면 '오디오 여유 최악 0%' 로 보여서 한계에 닿은 것처럼 오해하게 된다.
  engine.resetStats();

  final clock = Stopwatch()..start();
  var lastSync = 0;
  var lastStats = 0;
  // 5단계 3/N — 씬 루프. 한 판 분량만 들고 있다가 **엔진 시계 기준**으로 미리미리
  // 다음 판을 예약한다. UI 쪽 타이머로 하면 시계가 어긋나서 판마다 조금씩 밀린다.
  var driftFix = 0; // 실제 잔량과 우리 계산의 차이를 메우는 보정값
  var syncing = false;

  var released = false;

  while (true) {
    // ── 잠들기 / 깨기 ──
    //
    // 앱이 뒤로 가면 장치를 놓는다. 안 놓으면 안드로이드가 `AudioMix` 잠금을
    // 계속 잡아서 **아무 소리도 안 나는데 CPU 가 안 잔다**(폰에서 2분 뒤에도
    // 잡혀 있는 걸 봤다). 배터리가 닳는 앱은 그 이유만으로 지워진다.
    //
    // 깰 때는 **시계와 셈을 처음으로 되돌린다.** 급식량은 「흐른 시간 × 48000 −
    // 먹인 양」으로 재는데, 자는 동안에도 시계는 흐른다. 그대로 두면 깨는 순간
    // 「몇 분 치가 밀렸다」로 읽혀서 한꺼번에 쏟아붓는다.
    if (asleep) {
      if (!released) {
        loop.clear();
        engine.allOff();
        engine.clearSchedule();
        released = true;
        try {
          await FlutterPcmSound.release();
        } catch (e) {
          debugPrint('오디오 장치 놓기 실패(무시): $e');
        }
      }
      if (wakeWanted) {
        wakeWanted = false;
        asleep = false;
        released = false;
        try {
          await FlutterPcmSound.setup(
            sampleRate: kSampleRate,
            channelCount: kChannels,
          );
          await FlutterPcmSound.setFeedThreshold(0);
          await primeAndStart();
          clock
            ..reset()
            ..start();
          lastTickUs = 0;
          lastSync = 0;
          lastStats = 0;
          lastQueueProbe = 0;
          driftFix = 0;
          minQueue = -1;
          engine.resetStats();
        } catch (e) {
          // 다시 못 열었다 — 앱은 살아 있어야 한다. 다음 깨우기에서 또 해 본다.
          debugPrint('오디오 장치 다시 열기 실패: $e');
          asleep = true;
          released = true;
        }
      }
      // 자는 동안은 100ms 마다만 깨우는지 본다 — CPU 를 거의 안 쓴다
      await Future<void>.delayed(const Duration(milliseconds: 100));
      continue;
    }

    final elapsedUs = clock.elapsedMicroseconds;
    if (lastTickUs != 0) {
      final gap = (elapsedUs - lastTickUs) / 1000.0;
      if (gap > maxGapMs) maxGapMs = gap;
      if (gap > 20) lateTicks++;
    }
    lastTickUs = elapsedUs;

    // 씬 루프 — 앞질러 만드는 양(ahead) + 0.25초 여유를 두고 다음 판을 미리 예약한다.
    final schedStart = clock.elapsedMicroseconds;
    loop.topUp(engine, ahead + kSampleRate ~/ 4);
    final schedMs = (clock.elapsedMicroseconds - schedStart) / 1000.0;
    if (schedMs > maxSchedMs) maxSchedMs = schedMs;

    // 장치가 지금까지 재생했을 프레임 수 (우리 시계 기준)
    final played = elapsedUs * kSampleRate ~/ 1000000;
    var buffered = fed - played + driftFix;

    if (buffered <= 0) {
      engine.bufferEmpty++;
      buffered = 0;
    }

    // 모자란 만큼 채운다
    var need = ahead - buffered;
    if (need >= _kMinTopUp) {
      // 한 번에 너무 많이 만들면 그 렌더가 길어져서 **그것 자체가 지체가 된다**
      // (곡 재생 진입에서 목표가 3072→6144 로 뛸 때가 정확히 그 상황이다).
      // 조금씩 여러 바퀴에 걸쳐 채운다.
      //
      // 1536 → 768 (Phase 1 후속). 폰 실측에서 급식 지체 최대 20ms 중
      // **15.7ms 가 이 렌더 한 번**이었다(계기를 나눠 달고서야 보였다).
      // 절반으로 줄여도 따라잡는 속도는 넉넉하다 —
      // 768프레임 ÷ 한 바퀴 약 8ms = 초당 9만 프레임, 필요한 4.8만의 두 배다.
      if (need > 768) need = 768;
      final renderStart = clock.elapsedMicroseconds;
      var made = 0;
      while (made < need) {
        final n = _kChunk < need - made ? _kChunk : need - made;
        feedFrames(n);
        made += n;
      }
      fed += made;
      final renderMs = (clock.elapsedMicroseconds - renderStart) / 1000.0;
      if (renderMs > maxRenderMs) maxRenderMs = renderMs;
    }

    final nowMs = elapsedUs ~/ 1000;

    // 진짜 큐 잔량을 이따금 훔쳐본다(50ms 마다). await 하면 그 사이 급식이 멈추므로
    // 던져 놓고 결과만 받는다. 0 에 닿으면 쓰기 스레드가 굶었다는 직접 증거다.
    if (nowMs - lastQueueProbe >= 50 && !probing) {
      lastQueueProbe = nowMs;
      probing = true;
      FlutterPcmSound.remainingFrames().then(
        (q) {
          if (minQueue < 0 || q < minQueue) minQueue = q;
          probing = false;
        },
        onError: (_) {
          probing = false;
        },
      );
    }

    // 시계 드리프트 보정.
    // 우리 시계(Stopwatch)와 오디오 장치 시계는 아주 조금씩 어긋난다. 그냥 두면
    // 큐가 서서히 불어나(지연 증가) 거나 줄어든다(끊김).
    //
    // 두 가지를 지킨다:
    //  ① **await 하지 않는다.** 이 왕복이 10ms 넘게 걸리는 순간이 있는데 그동안 급식이 멈춘다.
    //     (실측: await 로 두었더니 주기적으로 언더런이 뭉텅이로 늘었다)
    //  ② **한 번에 조금씩만 고친다.** 한 번에 확 맞추면 그 순간 급식량이 튀어서
    //     오히려 버퍼가 출렁인다. 실측에서 지연이 19~31ms 사이를 오갔던 이유가 이것이다.
    //
    // 플러그인이 알려 주는 `real` 은 **플러그인 큐만** 센다. AudioTrack 안에 든 몫은
    // 여기 안 잡히므로, 그 차이는 상수로 보고 목표치(ahead)에 이미 포함시켜 둔다.
    if (nowMs - lastSync >= _kSyncEveryMs && !syncing) {
      lastSync = nowMs;
      syncing = true;
      final mineQueue = buffered - kDeviceBuffer;
      FlutterPcmSound.remainingFrames().then(
        (real) {
          var d = real - mineQueue;
          if (d > 64) d = 64;
          if (d < -64) d = -64;
          driftFix += d;
          syncing = false;
        },
        onError: (_) {
          syncing = false;
        },
      );
    }

    if (nowMs - lastStats >= 250) {
      lastStats = nowMs;
      tx.send(<dynamic>[
        engine.headroomPct,
        engine.worstHeadroomPct,
        engine.grDb,
        engine.worstGrDb,
        engine.peakOut,
        engine.bufferEmpty,
        engine.starved,
        engine.activeCount,
        engine.maxActive,
        engine.clipped,
        buffered,
        engine.drumActiveCount,
        engine.maxActiveDrums,
        engine.drumStarved,
        engine.compGrDb,
        maxGapMs,
        minQueue,
        lateTicks,
        loop.on,
        loop.posOf(engine.nowFrames - buffered),
        loop.count,
        maxRenderMs,
        maxSchedMs,
        // 트랙별 봉우리 — 믹서의 트랙 미터가 읽는다. **읽으면 비워진다.**
        engine.takeBusPeaks(),
      ]);
    }

    await Future<void>.delayed(const Duration(milliseconds: _kPollMs));
  }
}

/// 오디오 아이솔레이트가 받은 메시지 **한 통**을 처리한다.
///
/// **던지지 않는다.** `Isolate.spawn` 은 기본이 `errorsAreFatal: true` 라,
/// 여기서 예외가 하나 새면 **아이솔레이트가 통째로 죽는다** — 앱은 멀쩡히
/// 살아 있는데 그때부터 소리만 영영 안 난다. 오류 창도 안 뜬다.
/// 메시지 규약이 늘어날수록(이번에 `_cBus` 에 넷을 더했다) 그 위험이 커진다.
/// 한 통이 잘못 왔으면 그 한 통만 버린다.
///
/// [ahead] 는 이 안에서 바뀔 수 있으므로 새 값을 돌려준다.
int handleAudioMessage(
  List m,
  Engine engine,
  LoopState loop,
  int ahead,
  void Function() resetDiag,
) {
  try {
    switch (m[0] as int) {
      case _cNote:
        engine.noteOn(
          m[1] as String,
          m[2] as double,
          m[3] as double,
          m[4] as int,
          soft: m[5] as bool,
          glideF: m[6] as double,
          part: m[8] as int,
        );
        break;
      case _cHoldOn:
        engine.noteHold(
          m[1] as int,
          m[2] as String,
          m[3] as double,
          m[4] as int,
          soft: m[5] as bool,
          glideF: m[6] as double,
          part: m[7] as int,
        );
      case _cHoldOff:
        final id = m[1] as int;
        if (id < 0) {
          engine.releaseAllHeld();
        } else {
          engine.noteRelease(id);
        }
      case _cBatch:
        for (final n in (m[1] as List)) {
          final e = n as List;
          final delay = e[6] as double;
          final part = e.length > 7 ? e[7] as int : kPartMelody;
          if (delay <= 0) {
            engine.noteOn(
              e[0] as String,
              e[1] as double,
              e[2] as double,
              e[3] as int,
              soft: e[4] as bool,
              glideF: e[5] as double,
              part: part,
            );
          } else {
            engine.schedule(
              delay,
              e[0] as String,
              e[1] as double,
              e[2] as double,
              e[3] as int,
              soft: e[4] as bool,
              glideF: e[5] as double,
              part: part,
            );
          }
        }
        break;
      case _cOff:
        // 루프도 같이 끈다 — 안 그러면 '정지'를 눌러도 다음 판이 또 예약된다.
        loop.clear();
        engine.allOff();
        engine.clearSchedule();
        break;
      case _cLoop:
        loop.set(
          m[1] as List,
          m[2] as List,
          m[3] as double,
          m[4] as bool,
          engine,
          unitSec: m.length > 5 ? (m[5] as num).toDouble() : 0,
        );
        break;
      case _cAhead:
        ahead = m[1] as int;
        break;
      case _cReset:
        engine.resetStats();
        resetDiag(); // 진단 계수기는 급식 루프가 들고 있다
        break;
      case _cDuck:
        engine.duckAmount = (m[1] as num).toDouble();
        if (m.length > 2 && m[2] != null) {
          engine.duckRelSec = (m[2] as num).toDouble();
        }
        break;
      case _cQuality:
        engine.highQuality = m[1] as bool;
        break;
      case _cDrum:
        engine.drumOn(
          m[1] as String,
          m[2] as String,
          m[3] as int,
          tomFreq: m[4] as double,
        );
        break;
      case _cDrumBatch:
        for (final h in (m[1] as List)) {
          final e = h as List;
          final delay = e[4] as double;
          if (delay <= 0) {
            engine.drumOn(
              e[0] as String,
              e[1] as String,
              e[2] as int,
              tomFreq: e[3] as double,
            );
          } else {
            engine.scheduleDrum(
              delay,
              e[0] as String,
              e[1] as String,
              e[2] as int,
              tomFreq: e[3] as double,
            );
          }
        }
        break;
      case _cMaster:
        {
          final b = engine.masterBus;
          b.eqLoDb = m[1] as double;
          b.eqMidDb = m[2] as double;
          b.eqHiDb = m[3] as double;
          b.hpfFreq = m[4] as double;
          b.lpfFreq = m[5] as double;
          b.compWet = m[6] as double;
          b.compThr = m[7] as double;
          b.compRatio = m[8] as double;
          b.compAtk = m[9] as double;
          b.compRel = m[10] as double;
          b.compKnee = m[11] as double;
          b.compMakeupDb = m[12] as double;
          b.revWet = m[13] as double;
          b.revKind = m[14] as String;
          b.eqMode = m[15] as String;
          final incoming = m[16] as List;
          for (var i = 0; i < 20 && i < incoming.length; i++) {
            b.eq20[i] = incoming[i] as double;
          }
          b.eqFirst = m[17] as bool;
          b.markDirty();
        }
        break;
      case _cBus:
        {
          final name = m[1] as String;
          final b = name == 'drum'
              ? engine.trackMix.drum
              : name == 'live'
              ? engine.trackMix.live
              : engine.trackMix.bus(name);
          if (b != null) {
            if (m[2] != null) b.vol = m[2] as double;
            if (m[3] != null) b.pan = m[3] as double;
            if (m[4] != null) b.rev = m[4] as double;
            if (m[5] != null) b.eqLoDb = m[5] as double;
            if (m[6] != null) b.eqMidDb = m[6] as double;
            if (m[7] != null) b.eqHiDb = m[7] as double;
            // 길이가 짧은 옛 메시지도 받는다(길이를 먼저 본다)
            if (m.length > 8 && m[8] != null) b.hpfFreq = m[8] as double;
            if (m.length > 9 && m[9] != null) b.lpfFreq = m[9] as double;
            if (m.length > 10 && m[10] != null) b.lfoHz = m[10] as double;
            if (m.length > 11 && m[11] != null) b.lfoDepth = m[11] as double;
            b.markDirty();
          }
        }
        break;
      case _cMasterVol:
        engine.userGain = m[1] as double;
        break;
      case _cStyleGain:
        engine.styleGain = m[1] as double;
        break;
      case _cInserts:
        {
          final name = m[1] as String;
          // 'master' 는 TrackMix 가 아니다 — 엔진이 따로 들고 있다
          final list = name == 'master'
              ? engine.masterInserts
              : _busOf(engine, name)?.inserts;
          if (list != null) {
            list.clear();
            for (final raw in (m[2] as List)) {
              final j = Map<String, dynamic>.from(raw as Map);
              final fx = makeFx(j['type'] as String);
              if (fx == null) continue; // 모르는 종류는 조용히 건너뛴다
              fx.on = j['on'] as bool? ?? true;
              final ps = j['p'];
              if (ps is Map) {
                ps.forEach(
                  (k, v) => fx.set(k as String, (v as num).toDouble()),
                );
              }
              list.add(fx);
            }
          }
        }
        break;
      case _cAdsr:
        {
          final bus = _busOf(engine, m[1] as String);
          if (bus != null) {
            bus.adsrAttack = m[2] as double?;
            bus.adsrDecay = m[3] as double?;
            bus.adsrSustain = m[4] as double?;
            bus.adsrRelease = m[5] as double?;
          }
        }
        break;
      case _cUni:
        {
          final bus = _busOf(engine, m[1] as String);
          if (bus != null) bus.uniCents = m[2] as double?;
        }
        break;
      case _cFxParam:
        {
          final list = _fxListOf(engine, m[1] as String);
          final i = m[2] as int;
          if (list != null && i >= 0 && i < list.length) {
            list[i].set(m[3] as String, m[4] as double);
          }
        }
        break;
      case _cFxOn:
        {
          final list = _fxListOf(engine, m[1] as String);
          final i = m[2] as int;
          if (list != null && i >= 0 && i < list.length) {
            list[i].on = m[3] as bool;
          }
        }
        break;
      case _cSlots:
        engine.trackMix.configure(List<String>.from(m[1] as List));
        break;
      case _cGenreMix:
        {
          // 4단계 5/N — 값 적용 전에 편성부터 그 곡의 슬롯 이름으로 맞춘다. 배열형
          // 6곡은 melodicSlotsFor 가 기본값(['bass','chord','melody'])을 돌려주므로
          // configure() 가 대부분 no-op(이름이 이미 같으면 아무것도 안 바꾼다).
          final genre = m[1] as String?;
          if (genre != null && kGenreMix.containsKey(genre)) {
            engine.trackMix.configure(melodicSlotsFor(genre));
            applyGenreMixTo(engine.trackMix, genre);
            // 킥↔베이스 비켜 주기도 장르 값이다 (계획 6-5)
            engine.duckAmount = kGenreDuck[genre] ?? 0;
          } else {
            engine.trackMix.configure(const ['bass', 'chord', 'melody']);
            resetGenreMix(engine.trackMix);
            engine.duckAmount = 0;
          }
        }
        break;
    }
  } catch (e, st) {
    debugPrint('오디오 메시지 처리 실패(무시하고 계속): $e\n$st');
  }
  return ahead;
}
