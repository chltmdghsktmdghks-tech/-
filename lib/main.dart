// 1단계 시험 화면 — 악기 소리를 웹 버전과 귀로 맞대 보는 곳.
//
// 확인할 것:
//   1) 악기마다 소리가 '그 악기'로 들리는가 (배음 구조가 옮겨졌는가)
//   2) 음 길이를 길게 잡으면 그만큼 울리는가 (서스테인 — 웹에서 계속 지적됐던 부분)
//   3) 악기를 잔뜩 눌러도 안 찢어지는가 (부하 시험)

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'audio_isolate.dart';
import 'drums.dart';
import 'engine.dart';
import 'genre_mix.dart' show melodicSlotsFor, styleGain;
import 'instruments.dart';
import 'mixer.dart' show kMstEqFreq;
import 'patterns.dart';
import 'presets.dart';
import 'project.dart';
import 'sequencer.dart';
import 'song.dart';
import 'store.dart';
import 'synth.dart' show kPartLive;
import 'ui/home_view.dart';
import 'ui/live_view.dart';
import 'ui/mixer_view.dart';
import 'ui/scene_view.dart';
import 'ui/settings_sheet.dart';
import 'ui/show_view.dart';
import 'ui/song_view.dart';
import 'ui/songs_view.dart';
import 'theory.dart';

/// 시험 화면용 대표 패턴 — (패턴 이름, bpm, 어울리는 키트, 장르 라벨).
/// bpm·키트는 웹 `GENRE_PRESETS` 값 그대로(app.html) — 장르 하나씩 훑어 듣기 위한 것.
const List<(String, double, String, String)> kTestDrumPatterns = [
  ('Lofi Chorus', 78, 'lofi', '로파이'),
  ('House Chorus', 124, 'k909', '하우스'),
  ('Boom Chorus', 88, 'k808', '힙합'),
  ('City Chorus', 106, 'acoustic', '시티팝'),
  ('Ballad Chorus', 68, 'acoustic', '발라드'),
  ('Rock Chorus', 138, 'rock', '록'),
  ('Trap Hook', 140, 'k808', '트랩'),
  ('Prog Drop', 128, 'k909', '프로그하우스'),
  ('Pop Chorus', 104, 'acoustic', '팝'),
  ('Jazz Solo', 116, 'acoustic', '재즈'),
  ('Amb Perc', 72, 'lofi', '엠비언트'),
];

/// 4단계 2/N — 베이스/코드/멜로디까지 합쳐 "한 장르가 실제로 어떻게 들리는가"를 확인하는
/// 시험용 조합. 표 자체는 `presets.dart` 로 옮겼다(씬 화면도 같은 표를 쓴다).
final kTestSongPatterns = kGenrePresets;

/// 4단계 3/N — 곡 전체(인트로~벌스~코러스~브레이크~벌스~코러스~아웃트로)를 이어 재생.
/// `song.dart` 의 배열형 6곡(SONG_FORMS 의 트랙 구조 없는 쪽)만 대상 — bpm·키트는
/// `kTestSongPatterns` 와 같은 값(웹 `GENRE_PRESETS`). (장르 라벨, song.dart 의 키, bpm, 드럼키트).
const List<(String, String, double, String)> kFullSongs = [
  ('로파이', 'lofi', 78, 'lofi'),
  ('하우스', 'house', 124, 'k909'),
  ('힙합', 'hiphop', 88, 'k808'),
  ('시티팝', 'citypop', 106, 'acoustic'),
  ('발라드', 'ballad', 68, 'acoustic'),
  ('록', 'rock', 138, 'rock'),
];

/// 4단계 5/N — 객체형 롱폼(트랙 구조 일반화). 지금은 트랩만(HANDOFF "한 번에 한 덩어리").
/// (표시이름, 장르키, BPM, 드럼키트, 조) — 조는 'minor'|'major'.
/// 팝만 장조다. 안 넘기면 단조로 나와서 완전히 다른 곡이 된다.
const List<(String, String, double, String, String)> kFullSongsObject = [
  ('트랩', 'trap', 140, 'k808', 'minor'),
  ('프로그하우스', 'proghouse', 128, 'k909', 'minor'),
  ('팝', 'pop', 104, 'acoustic', 'major'),
  ('재즈', 'jazz', 116, 'acoustic', 'minor'),
  ('엠비언트', 'ambient', 72, 'lofi', 'minor'),
];

void main() => runApp(const EngineApp());

class EngineApp extends StatelessWidget {
  const EngineApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '음악 낙서장 — 엔진',
      theme: ThemeData.dark(useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  AudioClient? host;
  AudioStats stats = const AudioStats();
  // 빈 캔버스로 시작한다(장르는 나중에 씬 화면에서 고르는 프리셋) — 저장된
  // 곡이 있으면 `Store.start()` 가 `project.loadJson` 으로 이 값을 덮어쓴다.
  final project = Project.blank();

  /// 5단계 — 건반(라이브) 채널. 악기·볼륨·잔향을 믹서와 **같은 객체**로 공유한다.
  /// 아래 `voice` 는 기존 호출부를 그대로 두려고 남긴 통로다.
  final live = LiveChannel();
  final master = MasterChannel();
  final transport = Transport();

  String get voice => live.voice;
  set voice(String v) => live.voice = v;
  int octave = 4; // 건반 왼쪽 끝 옥타브
  double dur = 0.6; // 음 길이(초)
  bool ready = false;
  String kit = 'acoustic';

  // 부하 시험
  int stress = 0;
  late final AnimationController _anim;
  int _frames = 0;
  double _fps = 0, _fpsWorst = 999;
  DateTime _last = DateTime.now();
  static const _stressCounts = [0, 600, 1200];

  /// 뒤로 가면서 소리 장치를 놓았나 — 돌아올 때 다시 열어야 하는지 판단한다.
  bool _audioAsleep = false;

  /// 앱이 앞뒤로 오갈 때 — **소리 장치를 놓았다 다시 연다.**
  ///
  /// 안 놓으면 안드로이드가 `AudioMix` 잠금을 계속 잡아서, 아무 소리도 안 나는데
  /// **CPU 가 안 잔다.** 폰에서 직접 봤다 — 앱을 켜고 홈으로 나간 뒤 2분이 지나도
  /// `dumpsys power` 에 `PARTIAL_WAKE_LOCK 'AudioMix'` 가 그대로였다.
  /// 배터리가 닳는 앱은 그 이유만으로 지워진다.
  ///
  /// **소리가 나는 중이면 안 놓는다** — 듣다가 화면을 나가는 사람이 있다.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // **뒤로 가는 순간 저장한다 — 소리 장치보다 먼저다.**
    //
    // 자동 저장은 마지막 손짓에서 **0.8초 뒤**에 쓴다. 음을 하나 찍고 바로 홈을
    // 누르면 그 0.8초가 안 지나서 **방금 만진 것이 사라진다.** 전화가 와도 같다.
    // 안드로이드는 `paused` 뒤에 앱을 언제든 죽일 수 있으니, 여기가 마지막 기회다.
    //
    // `host` 가 없어도(소리 장치를 못 열었어도) 저장은 해야 한다 — 그래서
    // 아래 `if (h == null) return;` **위**에 둔다. 소리는 못 내도 만든 건 남는다.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      store?.saveNow();
    }
    final h = host;
    if (h == null) return;
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        if (!transport.playing && !_audioAsleep) {
          _audioAsleep = true;
          h.sleep();
        }
      case AppLifecycleState.resumed:
        if (_audioAsleep) {
          _audioAsleep = false;
          h.wake();
        }
      case AppLifecycleState.inactive:
        break; // 알림창을 내린 정도 — 아직 아무것도 안 한다
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();
    _anim.addListener(() {
      _frames++;
      final now = DateTime.now();
      final dt = now.difference(_last).inMilliseconds;
      if (dt >= 400) {
        setState(() {
          _fps = _frames * 1000 / dt;
          if (_fps < _fpsWorst) _fpsWorst = _fps;
          _frames = 0;
          _last = now;
        });
      }
    });
    _boot();
  }

  Store? store;

  /// 소리 장치를 못 열었을 때의 까닭. null 이면 아직 여는 중이거나 잘 열렸다.
  String? audioError;

  Future<void> _boot() async {
    // 저장된 프로젝트가 있으면 먼저 되살린다 — 오디오를 켜기 전에 해야
    // 편성(configureBuses)을 되살린 트랙으로 잡는다.
    final st = Store(
      project: project,
      transport: transport,
      live: live,
      master: master,
      seedSamples: true,
    );
    await st.start();
    st.attach();
    st.addListener(_watchSave);
    if (mounted) setState(() => store = st);
    // 저장해 둔 화면 방향·소리 품질을 켤 때 다시 건다 — 안 걸면 껐다 켤 때마다
    // 자동 회전으로 돌아간다(설정이 「이번 한 번」이 되면 설정이 아니다).
    await applyOrient(st.orient);
    host?.setQuality(st.highQuality);

    // 소리 장치를 못 열 수도 있다. 여태는 여기서 터지면 **동그라미만 영영 돌았다** —
    // 화면은 멀쩡히 움직이는데 ▶를 눌러도 아무 일이 안 난다. 사용자에게는
    // 「앱이 고장 났다」로만 보이고 무엇이 문제인지 알 길이 없다.
    final AudioClient c;
    try {
      c = await AudioClient.start();
    } catch (e) {
      debugPrint('소리 장치 열기 실패: $e');
      if (mounted) setState(() => audioError = '$e');
      return;
    }
    // 라이브 버스·마스터의 첫 값을 엔진에 맞춰 둔다 — 안 그러면 믹서에 보이는 값과
    // 실제 소리가 어긋난 채로 시작한다(잔향 18% 로 보이는데 실제로는 0).
    c.setBus('live', vol: live.vol, rev: live.rev);
    c.setMasterVol(master.vol);
    c.setStyleGain(styleGain(project.genre));
    _pushMasterFx(c);
    _pushLiveFx(c);
    // 곡을 열면 마스터·라이브 인서트도 곡의 것으로 바뀐다
    master.addListener(() => _pushMasterFx(host));
    live.addListener(() => _pushLiveFx(host));
    // 프로젝트 트랙마다 자기 버스를 잡아 둔다(5단계 2/N). 안 잡아 두면 믹서 페이더를
    // 만져도 그 이름의 버스가 없어서 아무 일이 안 일어난다.
    c.configureBuses(SceneSequencer.busNames(project));
    SceneSequencer.pushMix(project, c);
    project.addListener(_syncBuses); // 트랙을 추가·삭제하면 편성을 다시 잡는다
    c.statsStream.listen((s) {
      if (mounted) setState(() => stats = s);
    });
    if (mounted) {
      setState(() {
        host = c;
        ready = true;
      });
    }

    // **여는 동안 이미 뒤로 가 있었을 수 있다.**
    //
    // 소리 장치를 여는 데 시간이 걸리는데(아이솔레이트를 띄우고 버퍼를 채운다),
    // 그 사이에 사용자가 홈을 누르면 `didChangeAppLifecycleState` 가 먼저 오고
    // 그때는 `host` 가 아직 null 이라 **잠들라는 말을 아무도 안 한다.** 그러면
    // 앱이 뒤에 있는 채로 장치만 계속 열려 있다(배터리가 닳는 그 상태 그대로다).
    //
    // 화면이 꺼진 채로 앱이 시작되는 경우에도 같다 — 그때는 `resumed` 가 아예
    // 한 번도 안 온다. 그래서 다 열고 나서 **지금 상태를 한 번 되묻는다.**
    // **`resumed` 가 아니다」가 아니라 「뒤에 있다」로 본다.** `inactive` 는
    // 지나가는 상태라(알림창을 내린 정도) 곧 `resumed` 나 `paused` 로 정해지고
    // 그때 콜백이 온다 — 여기서 성급히 재우면 앞에 있는 앱이 잠깐 조용해진다.
    // 아래 셋은 `didChangeAppLifecycleState` 가 재우는 것과 똑같은 목록이다.
    final now = WidgetsBinding.instance.lifecycleState;
    final away =
        now == AppLifecycleState.paused ||
        now == AppLifecycleState.detached ||
        now == AppLifecycleState.hidden;
    if (away && !transport.playing && !_audioAsleep) {
      _audioAsleep = true;
      c.sleep();
    }
  }

  /// 트랙 편성을 엔진에 다시 잡고 믹서 값을 복구한다.
  /// **데모곡을 틀면 그 곡이 `setGenreMix()` 로 편성을 덮어쓴다** — 그래서 씬을 다시
  /// 틀거나 씬 화면에서 돌아올 때 이걸 불러 준다.
  /// 마스터 인서트를 오디오 쪽으로. 곡을 열 때·꽂을 때마다 부른다.
  void _pushMasterFx(AudioClient? h) {
    h?.setInserts('master', [for (final f in master.chain) f.toJson()]);
  }

  /// 라이브 인서트 — **손으로 치는 소리에만** 걸린다. 곡 트랙은 안 지나간다.
  void _pushLiveFx(AudioClient? h) {
    h?.setInserts('live', [for (final f in live.chain) f.toJson()]);
  }

  void _syncBuses() {
    final h = host;
    if (h == null) return;
    h.configureBuses(SceneSequencer.busNames(project));
    SceneSequencer.pushMix(project, h);
    // 스타일이 바뀌면 소리 크기 보정도 같이 바뀐다(5단계 34/N).
    // `setGenre` 가 `notifyListeners` 를 부르므로 여기가 그 자리다.
    h.setStyleGain(styleGain(project.genre));
  }

  /// **곡을 바꿔 열었을 때** 곡마다 다른 채널 값을 엔진에 다시 싣는다.
  ///
  /// `Store.open()` 은 `master.vol` · `master.chain` · 라이브 버스를 그 곡의 것으로
  /// 바꾸는데, 엔진으로 밀어 주는 자리가 **부팅 한 번**(`_boot`)과 **믹서 페이더**
  /// 뿐이었다. 그래서 곡을 바꾸면 믹서에 보이는 값과 실제로 나는 소리가 어긋났다 —
  /// 마스터를 −6dB 로 해 둔 곡을 열어도 앞 곡의 크기 그대로 울리고, 앞 곡에 꽂아 둔
  /// 마스터링(리미터 등)이 안 꽂은 곡에도 그대로 걸려 있었다.
  ///
  /// `_syncBuses` 에 넣지 않은 이유: 그쪽은 `project` 가 바뀔 때마다 도는데,
  /// `setInserts` 는 인서트를 **새로 만드는** 명령이라 페이더를 만질 때마다
  /// 마스터 이펙트가 매번 초기화된다. 곡을 여는 자리에서만 부른다.
  void _syncSongChannels() {
    final h = host;
    if (h == null) return;
    h.setMasterVol(master.vol);
    h.setBus('live', vol: live.vol, rev: live.rev);
    _pushMasterFx(h);
    _pushLiveFx(h);
  }

  /// **저장이 안 되면 말해 준다.**
  ///
  /// 여태 `saveNow` 는 실패를 삼키고 로그만 찍었다. 저장 공간이 꽉 찼거나 권한이
  /// 사라지면 그때부터 아무것도 안 남는데, 사용자는 **앱을 껐다 켠 뒤에야** 안다.
  /// 그때는 이미 늦었다. 뿌리에서 띄우므로 **어느 화면에 있든** 보인다.
  int _sawSaveFails = 0;
  void _watchSave() {
    final n = store?.saveFails ?? 0;
    if (n == _sawSaveFails) return;
    final wasBad = _sawSaveFails > 0;
    _sawSaveFails = n;
    if (!mounted) return;
    final m = ScaffoldMessenger.maybeOf(context);
    if (m == null) return;
    if (n == 0) {
      if (wasBad) {
        m
          ..clearSnackBars()
          ..showSnackBar(
            const SnackBar(
              content: Text('다시 저장되고 있습니다'),
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 3),
            ),
          );
      }
      return;
    }
    if (wasBad) return; // 이미 알렸다 — 실패할 때마다 띄우면 그게 더 방해다
    m
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: const Text(
            '저장이 안 되고 있습니다 — 저장 공간을 확인해 주세요.\n'
            '지금 만든 것이 안 남을 수 있습니다.',
          ),
          backgroundColor: Colors.red.shade800,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 12),
        ),
      );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store?.removeListener(_watchSave);
    store?.detach();
    project.removeListener(_syncBuses);
    _anim.dispose();
    super.dispose();
  }

  void _play(int midi) {
    host?.setSongMode(false); // 건반은 손가락에 붙어야 한다 — 작은 버퍼로
    host?.noteOn(voice, mfreq(midi), dur, 3);
  }

  /// 화음 — 반주처럼 soft 로 (웹의 playChordAt 과 같다)
  void _chord() {
    host?.setSongMode(true);
    final root = defaultRoot(voice);
    // 8번째 칸 = 라이브 버스 — 건반으로 치는 소리는 곡 트랙과 따로 논다
    host?.batch([
      for (final s in [0, 3, 7, 10])
        [voice, mfreq(root + s), dur * 2, 3, true, 0.0, 0.0, kPartLive],
    ]);
  }

  /// 아르페지오 — 글라이드까지 들어간다
  void _arp() {
    host?.setSongMode(true);
    final root = defaultRoot(voice);
    const seq = [0, 3, 7, 10, 12, 10, 7, 3];
    final out = <List<dynamic>>[];
    var prev = 0.0;
    for (var i = 0; i < seq.length; i++) {
      final f = mfreq(root + seq[i]);
      out.add([voice, f, dur, 3, false, prev, i * 0.16, kPartLive]);
      prev = f;
    }
    host?.batch(out);
  }

  /// 전체 훑기 — 33종을 차례로 한 음씩
  void _sweep() {
    host?.setSongMode(true);
    final out = <List<dynamic>>[];
    var t = 0.0;
    for (final v in ALL_VOICES) {
      final r = defaultRoot(v);
      out.add([v, mfreq(r), 0.9, 3, false, 0.0, t]);
      out.add([v, mfreq(r + 7), 0.9, 3, false, 0.0, t + 0.35]);
      t += 0.85;
    }
    host?.batch(out);
  }

  /// 부하 시험 — 실제 곡보다 훨씬 빽빽하게 쏟아붓는다
  void _flood() {
    host?.setSongMode(true);
    final rnd = math.Random(7);
    host?.batch([
      for (var i = 0; i < 160; i++)
        () {
          final v = ALL_VOICES[rnd.nextInt(ALL_VOICES.length)];
          return <dynamic>[
            v,
            mfreq(defaultRoot(v) + rnd.nextInt(13)),
            0.8,
            2 + rnd.nextInt(2),
            false,
            0.0,
            i * 0.045,
          ];
        }(),
    ]);
  }

  void _drumHit(String inst) {
    host?.setSongMode(false);
    host?.drumOn(kit, inst, 3, tomFreq: inst == 'tom' ? 150 : 180);
  }

  /// 4단계 1/N — 이식한 드럼 패턴 라이브러리를 실제로 들어보는 버튼.
  /// `buildDrumPattern()`(patterns.dart)이 웹 `buildDrum()`/`tileNotes()` 그대로 만든
  /// (lane,step,vel) 목록을 스텝 길이(bpm 기준)로 환산해 한 번에 예약한다.
  void _playPattern(String name, double bpm, String patKit) {
    host?.setSongMode(true); // 예약 재생 — 지연보다 안 끊기는 게 중요하다
    final def = findDrumPattern(name);
    if (def == null) return;
    final stepSec = 60.0 / bpm / 4;
    final hits = buildDrumPattern(def)
        .map<List<dynamic>>(
          (h) => [patKit, h.lane, h.vel, 180.0, h.step * stepSec],
        )
        .toList();
    host?.drumBatch(hits);
  }

  /// 4단계 2/N — 드럼+베이스+코드+멜로디를 한 조에 예약해서 "그 장르로 들리는가"를 확인.
  /// 키/조는 항상 기본값(C단조) — 조 바꾸기 UI는 아직 없다.
  void _playSong(
    String label,
    double bpm,
    String patKit,
    String drumName,
    String bassName,
    String chordName,
    String melodyName,
  ) {
    host?.setSongMode(true);
    // 이 시험은 배열형 6곡 밖의 장르(트랩·재즈 등)도 포함하고, GENRE_MIX 는 배열형 6곡만
    // 지원한다(genre_mix.dart) — `_playFullSong` 이 남겨 둔 믹스가 섞여 들리면 안 되므로
    // 매번 투명하게 되돌리고 시작한다.
    host?.setGenreMix(null);
    const key = MusicKey();
    final stepSec = 60.0 / bpm / 4;

    final drumDef = findDrumPattern(drumName);
    if (drumDef != null) {
      final hits = buildDrumPattern(drumDef)
          .map<List<dynamic>>(
            (h) => [patKit, h.lane, h.vel, 180.0, h.step * stepSec],
          )
          .toList();
      host?.drumBatch(hits);
    }

    final notes = <List<dynamic>>[];
    final bassDef = findBassPattern(bassName);
    if (bassDef != null) {
      for (final h in buildRowsPattern(bassDef, 'bass', key)) {
        notes.add([
          'moogbass',
          h.freq,
          h.len * stepSec,
          h.vel,
          false,
          h.glideFromFreq,
          h.step * stepSec,
          kPartBass,
        ]);
      }
    }
    final chordDef = findChordPattern(chordName);
    if (chordDef != null) {
      for (final h in buildChordPattern(chordDef, key)) {
        for (final f in h.freqs) {
          notes.add([
            'pad',
            f,
            h.len * stepSec,
            h.vel,
            true,
            0.0,
            h.step * stepSec,
            kPartChord,
          ]);
        }
      }
    }
    final melodyDef = findMelodyPattern(melodyName);
    if (melodyDef != null) {
      for (final h in buildRowsPattern(melodyDef, 'melody', key)) {
        notes.add([
          'bell',
          h.freq,
          h.len * stepSec,
          h.vel,
          false,
          h.glideFromFreq,
          h.step * stepSec,
          kPartMelody,
        ]);
      }
    }
    if (notes.isNotEmpty) host?.batch(notes);
  }

  /// 4단계 3/N — `song.dart` 의 `buildSong()` 이 편 곡 전체(인트로~아웃트로)를 한 번에
  /// 예약한다. 섹션이 순서대로 이어지고, 코러스 필인은 곡 전체에서 마지막 등장에만 들어간다
  /// (그 전 코러스는 민짜 버전 — `kPlainDrum`). 키/조는 `_playSong` 과 같이 항상 C단조 기본값.
  ///
  /// 4단계 4/N — 재생 직전에 `genre_mix.dart` 의 GENRE_MIX 를 트랙 버스로 보낸다
  /// (`genre` 가 배열형 6곡 중 하나면 실제로 걸리고, 아니면 조용히 무시된다 — 지금은
  /// 배열형 6곡만 지원). 마스터 EQ/컴프 슬라이더처럼 **다음에 명시적으로 바꾸기 전까지
  /// 그대로 남는다** — "믹스 초기화" 버튼으로 되돌릴 수 있다.
  void _playFullSong(String genre, double bpm, String patKit) {
    host?.setSongMode(true);
    host?.setGenreMix(genre);
    final s = buildSong(genre, bpm: bpm);

    if (s.drums.isNotEmpty) {
      host?.drumBatch(
        s.drums
            .map<List<dynamic>>((h) => [patKit, h.lane, h.vel, 180.0, h.time])
            .toList(),
      );
    }

    final notes = <List<dynamic>>[];
    for (final h in s.bass) {
      notes.add([
        'moogbass',
        h.freq,
        h.len,
        h.vel,
        false,
        h.glideFromFreq,
        h.time,
        kPartBass,
      ]);
    }
    for (final h in s.chord) {
      for (final f in h.freqs) {
        notes.add(['pad', f, h.len, h.vel, true, 0.0, h.time, kPartChord]);
      }
    }
    for (final h in s.melody) {
      notes.add([
        'bell',
        h.freq,
        h.len,
        h.vel,
        false,
        h.glideFromFreq,
        h.time,
        kPartMelody,
      ]);
    }
    if (notes.isNotEmpty) host?.batch(notes);
  }

  /// 4단계 5/N — 객체형 롱폼(트랩 등) 재생. `_playFullSong` 과 같은 얼개지만, 슬롯이
  /// 곡마다 다르므로(트랩은 b808/pad/brass/bell/plk) 노트 하나하나에 태그할 트랙 버스
  /// 인덱스를 `melodicSlotsFor(genre)` 에서 찾고(오디오 아이솔레이트가 `setGenreMix()`
  /// 로 그 순서 그대로 편성을 맞춘다 — audio_isolate.dart `_cGenreMix`), 악기도 슬롯마다
  /// 다른 걸 쓴다(트랩 패드는 analogpad, 브라스는 brass — `ObjectSongTrack.voice`).
  void _playObjectSong(String genre, double bpm, String patKit, String mode) {
    host?.setSongMode(true);
    host?.setGenreMix(genre);
    final form = kObjectSongForms[genre];
    if (form == null) return;
    final s = buildObjectSong(
      genre,
      bpm: bpm,
      key: MusicKey(mode: mode),
    );
    final slotOrder = melodicSlotsFor(genre);
    final trackOf = {for (final t in form.tracks) t.slot: t};

    if (s.drums.isNotEmpty) {
      host?.drumBatch(
        s.drums
            .map<List<dynamic>>((h) => [patKit, h.lane, h.vel, 180.0, h.time])
            .toList(),
      );
    }

    final notes = <List<dynamic>>[];
    s.mono.forEach((slot, hits) {
      final idx = slotOrder.indexOf(slot);
      final voice = trackOf[slot]?.voice ?? 'bell';
      for (final h in hits) {
        notes.add([
          voice,
          h.freq,
          h.len,
          h.vel,
          false,
          h.glideFromFreq,
          h.time,
          idx,
        ]);
      }
    });
    s.chord.forEach((slot, hits) {
      final idx = slotOrder.indexOf(slot);
      final voice = trackOf[slot]?.voice ?? 'pad';
      for (final h in hits) {
        for (final f in h.freqs) {
          notes.add([voice, f, h.len, h.vel, true, 0.0, h.time, idx]);
        }
      }
    });
    if (notes.isNotEmpty) host?.batch(notes);
  }

  /// 드럼 훅 부하 시험 — 0단계 스파이크가 쓴 것과 같은 밀도.
  /// 140 BPM · 킥 · 스네어 · **16분 하이햇** · 8마디. 웹 버전이 정확히 이 밀도(초당
  /// 노드 264개)에서 찢어졌던 구간이라, 여기서 멀쩡해야 이전이 옳다는 뜻이다.
  void _drumFlood() {
    host?.setSongMode(true);
    const bpm = 140.0;
    final step = 60.0 / bpm / 4; // 16분음표 길이
    final hits = <List<dynamic>>[];
    for (var bar = 0; bar < 8; bar++) {
      final base = bar * 16;
      for (var s = 0; s < 16; s++) {
        final t = (base + s) * step;
        hits.add([kit, 'hat', s.isEven ? 2 : 1, 180.0, t]); // 16분 하이햇
        if (s == 0 || s == 8) hits.add([kit, 'kick', 3, 180.0, t]);
        if (s == 4 || s == 12) hits.add([kit, 'snare', 3, 180.0, t]);
        if (s == 14) hits.add([kit, 'crash', 2, 180.0, t]);
      }
    }
    host?.drumBatch(hits);
  }

  /// 앱을 켜면 보이는 첫 화면.
  ///
  /// 예전엔 여기가 **엔진 시험 화면**이었다(악기 33종 · 지연 설정 · 부하 시험).
  /// 만드는 동안에는 그게 맞았지만, 앱을 켠 사람이 제일 먼저 보는 화면으로는 최악이다 —
  /// 음악을 만들러 온 사람에게 계기판을 보여 주는 셈이다. 시험 화면은 맨 아래 작은
  /// 글씨로 내려보내고, 첫 화면은 **내 곡과 네 가지 할 일**만 남겼다.
  @override
  Widget build(BuildContext context) {
    return HomeView(
      project: project,
      transport: transport,
      live: live,
      master: master,
      host: host,
      store: store,
      ready: ready,
      audioError: audioError,
      onSongOpened: () {
        host?.allOff();
        transport.playing = false;
        _syncBuses();
        _syncSongChannels();
      },
      onOpenLab: () => Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => _lab(context)))
          .then((_) => _syncBuses()),
    );
  }

  /// 엔진 시험 화면(예전 첫 화면) — 소리 엔진을 직접 두드려 보는 곳.
  Widget _lab(BuildContext context) {
    final e = stats;
    final torn = e.bufferEmpty > 0;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            if (stress > 0)
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _anim,
                  builder: (c, _) => CustomPaint(
                    painter: _StressPainter(_anim.value, _stressCounts[stress]),
                  ),
                ),
              ),
            Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '악기 시험',
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              ready ? '오디오 켜짐' : '준비 중…',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: ready
                                    ? Colors.green.shade300
                                    : Colors.white38,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // ── 악기 고르기 ──
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: ALL_VOICES.map((v) {
                            final on = v == voice;
                            return GestureDetector(
                              onTap: () => setState(() => voice = v),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: on
                                      ? Colors.amber.shade600
                                      : Colors.white10,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  VOICE_LABEL[v] ?? v,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: on
                                        ? FontWeight.w800
                                        : FontWeight.w400,
                                    color: on ? Colors.black : Colors.white70,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 14),

                        // ── 음 길이 ──
                        const Text(
                          '음 길이 — 길게 잡으면 그만큼 울려야 한다',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.white54,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SegmentedButton<double>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: 0.2, label: Text('16분')),
                            ButtonSegment(value: 0.6, label: Text('4분')),
                            ButtonSegment(value: 1.5, label: Text('2분')),
                            ButtonSegment(value: 3.0, label: Text('온음표')),
                          ],
                          selected: {dur},
                          onSelectionChanged: (v) =>
                              setState(() => dur = v.first),
                        ),
                        const SizedBox(height: 12),

                        // ── 지연 ──
                        Text(
                          '건반 지연 — 우리가 앞질러 만들어 두는 양. '
                          '총 ${(host?.latencyMs ?? 0).toStringAsFixed(0)}ms (장치 버퍼 포함)',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Colors.white54,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SegmentedButton<int>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: 1536, label: Text('짧게')),
                            ButtonSegment(value: 2048, label: Text('권장')),
                            ButtonSegment(value: 3072, label: Text('안전')),
                          ],
                          selected: {host?.aheadFrames ?? 2048},
                          onSelectionChanged: (v) => setState(() {
                            host?.setAhead(v.first);
                            host?.resetStats();
                          }),
                        ),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(child: _btn('화음', _chord)),
                            const SizedBox(width: 8),
                            Expanded(child: _btn('아르페지오', _arp)),
                            const SizedBox(width: 8),
                            Expanded(child: _btn('전체 훑기', _sweep)),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // ── 드럼 ──
                        const SizedBox(height: 4),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: store == null
                                ? null
                                : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => Scaffold(
                                        appBar: AppBar(
                                          title: const Text('내 곡'),
                                        ),
                                        body: SafeArea(
                                          top: false,
                                          child: SongsView(
                                            store: store!,
                                            project: project,
                                            onOpened: () {
                                              host?.allOff();
                                              transport.playing = false;
                                              _syncBuses();
                                              _syncSongChannels();
                                              setState(() {});
                                            },
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                            icon: const Icon(Icons.library_music, size: 18),
                            label: Text(
                              store == null
                                  ? '내 곡'
                                  : '내 곡 (${store!.songs.length}개) — ${project.name}',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.blueGrey.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => Navigator.of(context)
                                .push(
                                  MaterialPageRoute(
                                    builder: (_) => Scaffold(
                                      appBar: AppBar(
                                        title: const Text('씬 (내 트랙 연주)'),
                                      ),
                                      body: SafeArea(
                                        top: false,
                                        child: SceneView(
                                          project: project,
                                          transport: transport,
                                          host: host,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .then((_) => _syncBuses()),
                            icon: const Icon(Icons.grid_view, size: 18),
                            label: const Text('씬 열기 (내 트랙 연주)'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.indigo.shade600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => Navigator.of(context)
                                .push(
                                  MaterialPageRoute(
                                    builder: (_) => Scaffold(
                                      appBar: AppBar(
                                        title: const Text('라이브 (반주 위에 얹어 치기)'),
                                      ),
                                      body: SafeArea(
                                        top: false,
                                        child: LiveView(
                                          project: project,
                                          transport: transport,
                                          live: live,
                                          host: host,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .then((_) => _syncBuses()),
                            icon: const Icon(Icons.piano, size: 18),
                            label: const Text('라이브 (반주 위에 얹어 치기)'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.pink.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => Navigator.of(context)
                                .push(
                                  MaterialPageRoute(
                                    builder: (_) => Scaffold(
                                      appBar: AppBar(
                                        title: const Text('곡 (구간 늘어놓기)'),
                                        actions: [
                                          IconButton(
                                            tooltip: '처음부터 새로 (저장된 것도 지움)',
                                            icon: const Icon(Icons.restart_alt),
                                            onPressed: () async {
                                              host?.allOff();
                                              transport.playing = false;
                                              await store?.resetCurrent();
                                              _syncBuses();
                                            },
                                          ),
                                        ],
                                      ),
                                      body: SafeArea(
                                        top: false,
                                        child: SongView(
                                          project: project,
                                          transport: transport,
                                          host: host,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                                .then((_) => _syncBuses()),
                            icon: const Icon(Icons.view_timeline, size: 18),
                            label: const Text('곡 열기 (구간 늘어놓기)'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.deepPurple.shade500,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => Navigator.of(context)
                                .push(
                                  MaterialPageRoute(
                                    // 쇼는 **전체 화면**이다 — AppBar 를 안 붙인다
                                    builder: (_) => Scaffold(
                                      backgroundColor: Colors.black,
                                      body: ShowView(
                                        project: project,
                                        transport: transport,
                                        host: host,
                                      ),
                                    ),
                                  ),
                                )
                                .then((_) => _syncBuses()),
                            icon: const Icon(Icons.auto_awesome, size: 18),
                            label: const Text('쇼 (보여 주기)'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.amber.shade800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => Scaffold(
                                  appBar: AppBar(title: const Text('믹서')),
                                  // 아래쪽 시스템 내비게이션 바에 M/S 버튼이 가리지 않게
                                  body: SafeArea(
                                    top: false,
                                    child: MixerView(
                                      project: project,
                                      live: live,
                                      master: master,
                                      host: host,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            icon: const Icon(Icons.tune, size: 18),
                            label: const Text('믹서 열기 (5단계 새 UI)'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.teal.shade700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Divider(height: 1, color: Colors.white12),
                        const SizedBox(height: 12),
                        const Text(
                          '드럼 키트',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.white54,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: DRUM_KIT_ORDER.map((k) {
                            final on = k == kit;
                            return GestureDetector(
                              onTap: () => setState(() => kit = k),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: on
                                      ? Colors.cyan.shade600
                                      : Colors.white10,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  DRUM_KITS[k]!.label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: on
                                        ? FontWeight.w800
                                        : FontWeight.w400,
                                    color: on ? Colors.black : Colors.white70,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: DRUM_ORDER.map((d) {
                            return GestureDetector(
                              onTap: () => _drumHit(d),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 9,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.cyan.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.cyan.withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  DRUM_LABEL[d] ?? d,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                        _btn('드럼 훅 부하 시험 (140BPM · 16분 하이햇 · 8마디)', _drumFlood),
                        const SizedBox(height: 12),
                        const Text(
                          '드럼 패턴 재생 (4단계 1/N — 웹 MIDI_LIB 이식분)',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.white54,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: kTestDrumPatterns.map((p) {
                            return GestureDetector(
                              onTap: () => _playPattern(p.$1, p.$2, p.$3),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.deepOrange.withValues(
                                    alpha: 0.16,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.deepOrange.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  '${p.$4} · ${p.$1}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '화성 패턴 재생 (4단계 2/N — 베이스·코드·멜로디 이식분, 드럼과 동시 재생)',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.white54,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: kTestSongPatterns.map((p) {
                            return GestureDetector(
                              onTap: () => _playSong(
                                p.$1,
                                p.$2,
                                p.$3,
                                p.$4,
                                p.$5,
                                p.$6,
                                p.$7,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.purple.withValues(
                                      alpha: 0.45,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  p.$1,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '전체 곡 재생 (4단계 4/N — 인트로~아웃트로 + 장르별 GENRE_MIX 자동 적용, 30~40초)',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => host?.setGenreMix(null),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  '믹스 초기화',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: kFullSongs.map((p) {
                            return GestureDetector(
                              onTap: () => _playFullSong(p.$2, p.$3, p.$4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.teal.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.teal.withValues(alpha: 0.45),
                                  ),
                                ),
                                child: Text(
                                  '▶ ${p.$1} 전체곡',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '완성곡 (4단계 5/N — 트랙 구조 일반화, 슬롯별 GENRE_MIX)',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.white54,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: kFullSongsObject.map((p) {
                            return GestureDetector(
                              onTap: () =>
                                  _playObjectSong(p.$2, p.$3, p.$4, p.$5),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.pink.withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: Colors.pink.withValues(alpha: 0.45),
                                  ),
                                ),
                                child: Text(
                                  '▶ ${p.$1} 전체곡',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),

                        // ── 마스터 버스 (3단계 1차) ──
                        const Divider(height: 1, color: Colors.white12),
                        const SizedBox(height: 12),
                        const Text(
                          '마스터 — 기본은 투명. 움직여서 소리가 바뀌는지 확인',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.white54,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const SizedBox(
                              width: 92,
                              child: Text(
                                'EQ 모드',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                            Expanded(
                              child: SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment(
                                    value: '3',
                                    label: Text(
                                      '3밴드',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: '20',
                                    label: Text(
                                      '20밴드',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ],
                                selected: {host?.eqMode ?? '3'},
                                onSelectionChanged: (s) => setState(() {
                                  host?.eqMode = s.first;
                                  host?.syncMaster();
                                }),
                              ),
                            ),
                          ],
                        ),
                        if ((host?.eqMode ?? '3') == '3') ...[
                          _eqSlider(
                            '저역 (25~100Hz)',
                            host?.eqLoDb ?? 0,
                            (v) => setState(() {
                              host?.eqLoDb = v;
                              host?.syncMaster();
                            }),
                          ),
                          _eqSlider(
                            '중역 (125Hz~1.25kHz)',
                            host?.eqMidDb ?? 0,
                            (v) => setState(() {
                              host?.eqMidDb = v;
                              host?.syncMaster();
                            }),
                          ),
                          _eqSlider(
                            '고역 (2k~16kHz)',
                            host?.eqHiDb ?? 0,
                            (v) => setState(() {
                              host?.eqHiDb = v;
                              host?.syncMaster();
                            }),
                          ),
                        ] else
                          SizedBox(
                            height: 130,
                            child: Row(
                              children: List.generate(
                                20,
                                (i) => _Eq20Band(
                                  key: ValueKey(i),
                                  index: i,
                                  initial: host?.eq20[i] ?? 0,
                                  onChanged: (v) {
                                    // **setState 를 쓰지 않는다.** 여기서 부르면 슬라이더를
                                    // 끄는 내내(초당 60회) 화면 전체가 다시 그려진다 —
                                    // 악기 칩 33개 + 버튼 수십 개 + 건반까지. 그게 '20밴드
                                    // EQ 적용이 느리다'의 원인이었다.
                                    // 슬라이더는 자기 상태만 갱신하고, 값은 여기로 흘려보낸다.
                                    host?.eq20[i] = v;
                                    host?.syncMaster();
                                  },
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const SizedBox(
                              width: 92,
                              child: Text(
                                'EQ/컴프 순서',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                            Expanded(
                              child: SegmentedButton<bool>(
                                segments: const [
                                  ButtonSegment(
                                    value: true,
                                    label: Text(
                                      'EQ→컴프',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: false,
                                    label: Text(
                                      '컴프→EQ',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ],
                                selected: {host?.eqFirst ?? true},
                                onSelectionChanged: (s) => setState(() {
                                  host?.eqFirst = s.first;
                                  host?.syncMaster();
                                }),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            const SizedBox(
                              width: 92,
                              child: Text(
                                '하이패스',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Slider(
                                min: 20,
                                max: 300,
                                divisions: 28,
                                value: host?.hpfFreq ?? 20,
                                label:
                                    '${(host?.hpfFreq ?? 20).toStringAsFixed(0)}Hz',
                                onChanged: (v) => setState(() {
                                  host?.hpfFreq = v;
                                  host?.syncMaster();
                                }),
                              ),
                            ),
                            SizedBox(
                              width: 52,
                              child: Text(
                                '${(host?.hpfFreq ?? 20).toStringAsFixed(0)}Hz',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: SwitchListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  '컴프레서',
                                  style: TextStyle(fontSize: 12.5),
                                ),
                                value: host?.compOn ?? false,
                                onChanged: (v) => setState(() {
                                  host?.compOn = v;
                                  host?.syncMaster();
                                }),
                              ),
                            ),
                          ],
                        ),
                        if (host?.compOn ?? false)
                          Row(
                            children: [
                              const SizedBox(
                                width: 92,
                                child: Text(
                                  '물리는 세기',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.white54,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Slider(
                                  min: -40,
                                  max: 0,
                                  divisions: 40,
                                  value: host?.compThr ?? -14,
                                  label:
                                      '${(host?.compThr ?? -14).toStringAsFixed(0)}dB',
                                  onChanged: (v) => setState(() {
                                    host?.compThr = v;
                                    host?.syncMaster();
                                  }),
                                ),
                              ),
                              SizedBox(
                                width: 52,
                                child: Text(
                                  '${(host?.compThr ?? -14).toStringAsFixed(0)}dB',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        if (host?.compOn ?? false)
                          Row(
                            children: [
                              const SizedBox(
                                width: 92,
                                child: Text(
                                  '메이크업 게인',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.white54,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Slider(
                                  min: 0,
                                  max: 18,
                                  divisions: 36,
                                  value: host?.compMakeupDb ?? 0,
                                  label:
                                      '+${(host?.compMakeupDb ?? 0).toStringAsFixed(1)}dB',
                                  onChanged: (v) => setState(() {
                                    host?.compMakeupDb = v;
                                    host?.syncMaster();
                                  }),
                                ),
                              ),
                              SizedBox(
                                width: 52,
                                child: Text(
                                  '+${(host?.compMakeupDb ?? 0).toStringAsFixed(1)}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 4),
                        _kv(
                          '컴프 감쇠',
                          '${stats.compGrDb.toStringAsFixed(1)}dB',
                          false,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            const SizedBox(
                              width: 92,
                              child: Text(
                                '리버브 종류',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                            Expanded(
                              child: SegmentedButton<String>(
                                segments: const [
                                  ButtonSegment(
                                    value: 'hall',
                                    label: Text(
                                      '홀',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: 'plate',
                                    label: Text(
                                      '플레이트',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                  ButtonSegment(
                                    value: 'room',
                                    label: Text(
                                      '룸',
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ),
                                ],
                                selected: {host?.revKind ?? 'hall'},
                                onSelectionChanged: (s) => setState(() {
                                  host?.revKind = s.first;
                                  host?.syncMaster();
                                }),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            const SizedBox(
                              width: 92,
                              child: Text(
                                '리버브 양',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white54,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Slider(
                                min: 0,
                                max: 0.4,
                                divisions: 40,
                                value: host?.revWet ?? 0,
                                label:
                                    '${(((host?.revWet ?? 0) / 0.4) * 100).toStringAsFixed(0)}%',
                                onChanged: (v) => setState(() {
                                  host?.revWet = v;
                                  host?.syncMaster();
                                }),
                              ),
                            ),
                            SizedBox(
                              width: 52,
                              child: Text(
                                '${(((host?.revWet ?? 0) / 0.4) * 100).toStringAsFixed(0)}%',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // ── 부하 시험 ──
                        const Divider(height: 1, color: Colors.white12),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Text(
                              '부하 시험',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.white54,
                              ),
                            ),
                            const Spacer(),
                            TextButton(
                              onPressed: () => setState(() {
                                host?.resetStats();
                                _fpsWorst = 999;
                              }),
                              child: const Text(
                                '지표 초기화',
                                style: TextStyle(fontSize: 11.5),
                              ),
                            ),
                          ],
                        ),
                        SegmentedButton<int>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: 0, label: Text('화면부하 끔')),
                            ButtonSegment(value: 1, label: Text('보통')),
                            ButtonSegment(value: 2, label: Text('2배')),
                          ],
                          selected: {stress},
                          onSelectionChanged: (v) =>
                              setState(() => stress = v.first),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: _btn('음 쏟아붓기 (160개)', _flood)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _btn('전부 끄기', () => host?.allOff()),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        Container(
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: torn
                                  ? Colors.red.shade400
                                  : Colors.white24,
                              width: torn ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  const Text(
                                    '오디오 여유  ',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.white54,
                                    ),
                                  ),
                                  Text(
                                    '${e.headroom.toStringAsFixed(0)}%',
                                    style: TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w900,
                                      color: e.headroom > 50
                                          ? Colors.green.shade300
                                          : e.headroom > 25
                                          ? Colors.amber.shade300
                                          : Colors.red.shade300,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '최악 ${e.worstHeadroom.toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white54,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _kv('버퍼 바닥', '${e.bufferEmpty}회', torn),
                              _kv('음 부족', '${e.starved}회', e.starved > 0),
                              _kv(
                                '울리는 음',
                                '${e.active} (최대 ${e.maxActive})',
                                false,
                              ),
                              _kv(
                                '울리는 드럼',
                                '${e.drumActive} (최대 ${e.maxActiveDrums})',
                                false,
                              ),
                              _kv(
                                '드럼 음 부족',
                                '${e.drumStarved}회',
                                e.drumStarved > 0,
                              ),
                              _kv(
                                '버퍼 잔량',
                                '${e.aheadFrames}프레임',
                                e.aheadFrames < 64,
                              ),
                              _kv('하드클립', '${e.clipped}회', e.clipped > 0),
                              _kv(
                                '급식 지체',
                                '최대 ${e.maxPollGapMs.toStringAsFixed(0)}ms · 20ms초과 ${e.lateTicks}회',
                                e.lateTicks > 5,
                              ),
                              // 지체를 셋으로 나눠 본다 — "늦었다"만 알면 못 고친다.
                              // 소리 만들기 · 다음 판 예약 · **우리가 안 돌던 시간**.
                              _kv(
                                '  ├ 소리 만들기',
                                '${e.maxRenderMs.toStringAsFixed(1)}ms',
                                e.maxRenderMs > 10,
                              ),
                              _kv(
                                '  ├ 다음 판 예약',
                                '${e.maxSchedMs.toStringAsFixed(1)}ms',
                                e.maxSchedMs > 10,
                              ),
                              _kv(
                                '  └ 안 돌던 시간',
                                '${(e.maxPollGapMs - e.maxRenderMs - e.maxSchedMs).clamp(0, 9999).toStringAsFixed(1)}ms',
                                e.maxPollGapMs - e.maxRenderMs - e.maxSchedMs >
                                    12,
                              ),
                              _kv(
                                '큐 최소 잔량',
                                e.minQueueFrames < 0
                                    ? '-'
                                    : '${e.minQueueFrames}프레임',
                                e.minQueueFrames == 0,
                              ),
                              _kv(
                                '리미터 감쇠',
                                '${e.grDb.toStringAsFixed(1)}dB (최대 ${e.worstGrDb.toStringAsFixed(1)}dB)',
                                e.worstGrDb < -9,
                              ),
                              _kv(
                                '리미터 전 피크',
                                e.peakOut.toStringAsFixed(2),
                                e.peakOut > 2.5,
                              ),
                              _kv(
                                '화면 FPS',
                                '${_fps.toStringAsFixed(0)} (최저 ${_fpsWorst == 999 ? "-" : _fpsWorst.toStringAsFixed(0)})',
                                false,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),

                // ── 건반 ──
                Container(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
                  color: Colors.black38,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: () => setState(
                              () => octave = math.max(1, octave - 1),
                            ),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text(
                            '$octave옥타브  ·  ${VOICE_LABEL[voice] ?? voice}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          IconButton(
                            onPressed: () => setState(
                              () => octave = math.min(7, octave + 1),
                            ),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                      SizedBox(
                        height: 116,
                        child: _Keyboard(octave: octave, onNote: _play),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _btn(String t, VoidCallback f) => FilledButton(
    onPressed: f,
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 13),
      backgroundColor: Colors.white12,
      // 안 잡으면 테마 기본 글씨색(보라)이라 어두운 바탕에서 거의 안 읽힌다
      foregroundColor: Colors.white,
    ),
    child: Text(
      t,
      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
    ),
  );

  Widget _eqSlider(String label, double db, ValueChanged<double> onChanged) =>
      Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11.5, color: Colors.white54),
            ),
          ),
          Expanded(
            child: Slider(
              min: -12,
              max: 12,
              divisions: 48,
              value: db,
              label: '${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)}dB',
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              '${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)}',
              style: const TextStyle(fontSize: 11.5, color: Colors.white70),
            ),
          ),
        ],
      );

  /// 20밴드 EQ 세로 페이더 하나 — `RotatedBox` 로 가로 `Slider` 를 세운다(Flutter 표준 수법).

  Widget _kv(String k, String v, bool danger) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            k,
            style: const TextStyle(fontSize: 12, color: Colors.white60),
          ),
        ),
        Text(
          v,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: danger ? Colors.red.shade300 : Colors.white,
          ),
        ),
      ],
    ),
  );
}

/// 두 옥타브 미니 건반
class _Keyboard extends StatelessWidget {
  final int octave;
  final void Function(int midi) onNote;
  const _Keyboard({required this.octave, required this.onNote});

  static const _white = [0, 2, 4, 5, 7, 9, 11];
  // 검은건반: 흰건반 몇 번째 오른쪽 경계에 붙는가
  static const _black = [
    [0, 1],
    [1, 3],
    [3, 6],
    [4, 8],
    [5, 10],
  ];

  @override
  Widget build(BuildContext context) {
    final base = (octave + 1) * 12; // C{octave}
    return LayoutBuilder(
      builder: (context, c) {
        final wKeys = 14; // 두 옥타브
        final w = c.maxWidth / wKeys;
        return Stack(
          children: [
            Row(
              children: List.generate(wKeys, (i) {
                final midi = base + (i ~/ 7) * 12 + _white[i % 7];
                return SizedBox(
                  width: w,
                  child: Listener(
                    // GestureDetector 는 '탭인지 스크롤인지' 판단하느라 한 박자 늦는다.
                    // 건반은 누른 즉시 나야 하므로 포인터 이벤트를 직접 받는다.
                    onPointerDown: (_) => onNote(midi),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(4),
                        ),
                      ),
                      alignment: Alignment.bottomCenter,
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(
                        noteName(midi),
                        style: const TextStyle(
                          fontSize: 8.5,
                          color: Colors.black54,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
            ...List.generate(2, (oct) {
              return Stack(
                children: _black.map((b) {
                  final left = (oct * 7 + b[0] + 1) * w - w * 0.3;
                  final midi = base + oct * 12 + b[1];
                  return Positioned(
                    left: left,
                    top: 0,
                    width: w * 0.6,
                    height: 70,
                    child: Listener(
                      onPointerDown: (_) => onNote(midi),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade900,
                          border: Border.all(color: Colors.black54),
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              );
            }),
          ],
        );
      },
    );
  }
}

class _StressPainter extends CustomPainter {
  final double t;
  final int count;
  _StressPainter(this.t, this.count);
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..style = PaintingStyle.fill;
    final rnd = math.Random(1);
    for (var i = 0; i < count; i++) {
      final a = (i / count + t) * 2 * math.pi;
      final r = 40.0 + (i % 120) * 1.6;
      final x = size.width / 2 + math.cos(a * (1 + i % 5)) * r;
      final y = size.height / 2 + math.sin(a * (1 + i % 7)) * r;
      p.color = Color.fromARGB(
        30,
        rnd.nextInt(255),
        rnd.nextInt(255),
        rnd.nextInt(255),
      );
      canvas.drawCircle(Offset(x, y), 8 + (i % 9).toDouble(), p);
    }
  }

  @override
  bool shouldRepaint(covariant _StressPainter old) => true;
}

/// 20밴드 EQ 한 밴드. **자기 값을 스스로 들고 있는다.**
///
/// 예전에는 부모(HomePage)가 값을 들고 `setState` 로 갱신했는데, 그러면 슬라이더를
/// 끄는 내내(초당 60회) **화면 전체가 다시 그려진다** — 악기 칩 33개, 패턴 버튼 20여 개,
/// 곡 버튼 11개, 20밴드 슬라이더 전부, 건반까지. 그게 "20밴드 EQ 적용이 느리다"의 원인이었다.
/// (EQ 계산 자체는 문제가 아니다 — mixer.dart `_updateFilters()` 는 값이 바뀐 밴드만
/// 다시 만든다)
///
/// 지금은 움직이는 슬라이더 하나만 다시 그린다. 값은 `onChanged` 로 흘려보내
/// `host.eq20[i]` 에 바로 쓰고 오디오 아이솔레이트로 보낸다.
class _Eq20Band extends StatefulWidget {
  final int index;
  final double initial;
  final ValueChanged<double> onChanged;
  const _Eq20Band({
    super.key,
    required this.index,
    required this.initial,
    required this.onChanged,
  });
  @override
  State<_Eq20Band> createState() => _Eq20BandState();
}

class _Eq20BandState extends State<_Eq20Band> {
  late double _db = widget.initial;

  @override
  void didUpdateWidget(_Eq20Band old) {
    super.didUpdateWidget(old);
    // 바깥에서 값이 바뀐 경우(예: '믹스 초기화')에만 따라간다.
    // 드래그 중에는 initial 이 안 바뀌므로 여기서 되감기지 않는다.
    if (widget.initial != old.initial && widget.initial != _db) {
      _db = widget.initial;
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = kMstEqFreq[widget.index];
    final label = f >= 1000
        ? '${(f / 1000).toStringAsFixed(f % 1000 == 0 ? 0 : 1)}k'
        : f.toStringAsFixed(0);
    return SizedBox(
      width: 27,
      child: Column(
        children: [
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: Slider(
                min: -12,
                max: 12,
                divisions: 48,
                value: _db,
                label: '${_db >= 0 ? '+' : ''}${_db.toStringAsFixed(1)}dB',
                onChanged: (v) {
                  setState(() => _db = v); // 이 슬라이더만 다시 그린다
                  widget.onChanged(v);
                },
              ),
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 8.5, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}
