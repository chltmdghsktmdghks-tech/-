// 곡 화면(타임라인) — **구간을 시간 순서로 늘어놓아 곡을 만든다.**
//
// 씬 화면이 "지금 이 한 판"이라면 여기는 "처음부터 끝까지"다.
// 구간 하나 = (어느 씬 = 곡의 구간, 몇 판).
//
// ── 스타일은 곡 전체에 하나다 ──
// 처음엔 구간마다 장르를 다르게 넣었다(로파이→하우스→힙합). **그건 곡이 아니라
// 짜깁기다**(사용자 지적). 곡은 스타일 하나 안에서 인트로→벌스→코러스→…로 흘러야 한다.
// 그래서 위에 스타일 줄을 두고, 구간은 그 스타일의 송폼(`song.dart kSongForms`)으로 채운다.
//
// ── 길이 단위를 마디가 아니라 '판' 으로 잡은 이유 ──
// 씬마다 패턴 길이가 다르다(2마디짜리도 4마디짜리도 있다). 마디로 자르면 패턴이
// 중간에 잘려서 어색해진다. 판 단위면 프레이즈가 항상 온전히 끝난다.
//
// ── 재생은 루프 장치를 그대로 쓴다 ──
// 곡 전체를 **한 판**으로 보고 `setLoop` 에 넣는다. 그러면 곡이 끝나고 처음부터 다시
// 도는 것까지 공짜로 얻는다(오디오 아이솔레이트가 엔진 시계로 이어 붙인다).

import 'dart:io';

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../audio_isolate.dart';
import '../export.dart';
import 'text_scale.dart';
import '../arrange.dart';
import '../arrange_rec.dart';
import '../genre_mix.dart';
import '../pattern_names.dart';
import '../presets.dart';
import '../patterns.dart';
import '../project.dart';
import '../sequencer.dart';
import '../show_ops.dart';
import '../synth.dart' show Human;
import 'cover.dart';
import 'critters.dart';
import 'editor_view.dart' show followTarget;
import 'mixer_view.dart' show showChannelSheet;
import 'scene_view.dart' show pickPatternSheet;
import 'play_head.dart';

/// 스타일을 바꾼 뒤 **손으로 고친 판이 어떻게 됐는지** 한 줄로 말해 준다.
///
/// **둘 다 0 이 아닐 수 있다** — 일부는 새 얼개에서 자리를 찾고 일부는 못 찾는다.
/// 예전엔 지킨 쪽만 말하고 **빠진 쪽은 입을 다물었다.** 하필 사용자가 걱정하는
/// 것은 빠진 쪽이다("내가 만든 게 날아갔나"). 화면에서 떼어 놔야 시험할 수 있어
/// 여기에 둔다.
String? genreChangeNote(int kept, int parked) {
  final gone = parked > 0
      ? '$parked개는 자리가 없어 빠졌습니다 — 편집기 패턴 목록 맨 위에 그대로 있어요'
      : null;
  if (kept > 0) {
    return gone == null
        ? '손으로 고친 판 $kept개는 그대로 뒀습니다'
        : '손으로 고친 판 $kept개는 그대로 두고, $gone';
  }
  return gone == null ? null : '편성이 바뀌어 손으로 고친 판 $gone';
}

class SongView extends StatefulWidget {
  final Project project;
  final Transport transport;
  final AudioClient? host;

  /// 내보낼 때 **마스터링까지 파일에 담으려면** 필요하다.
  final MasterChannel? master;

  /// 곡을 보는 방식 — `'list'`(구간 목록) 또는 `'timeline'`(타임라인).
  ///
  /// **둘은 같은 자료를 본다.** 구간표(`Arrangement.sections`) 하나뿐이고,
  /// 타임라인은 그 목록에서 마디 자리를 셈으로 뽑아 그린다. 그래서 어느 쪽에서
  /// 고쳐도 다른 쪽에 그대로 있다 — 옮겨 담는 코드가 없으니 어긋날 수가 없다.
  /// (두 벌을 따로 들고 맞추는 길이 흔한데, 그건 반드시 한쪽만 고치는 날이 온다)
  final String mode;
  final ValueChanged<String>? onMode;

  /// **이 씬 고치기** — 타임라인에서 구간을 고르면 바로 그 씬의 만들기 화면으로.
  ///
  /// 여태는 뒤로 → 만들기 → 씬 고르기 세 걸음이었다. 곡을 만들다 보면 「이 대목
  /// 패드를 좀 바꾸자」가 계속 나오는데, 그때마다 세 걸음이면 안 고치게 된다.
  /// 화면을 여는 일은 이 화면이 못 한다(집이 안다) — 그래서 부탁만 한다.
  final ValueChanged<int>? onEditScene;
  const SongView({
    super.key,
    required this.project,
    required this.transport,
    required this.host,
    this.master,
    this.mode = 'list',
    this.onMode,
    this.onEditScene,
  });

  @override
  State<SongView> createState() => _SongViewState();
}

class _SongViewState extends State<SongView> {
  SceneBuild? _built;
  bool _loop = true;
  bool _exporting = false;
  double _exportPct = 0;

  /// 타임라인에서 고른 구간(−1 = 없음). 그 자리에 손잡이 줄이 뜬다.
  int _sel = -1;

  /// 타임라인에서 **복사해 둔 클립** — 화면에 있는 동안만 산다.
  /// 옛 앱의 `tlClip9` 자리다: 하나 만들어 두고 여러 자리에 붙이는 것이
  /// 트랙 줄을 쓰는 제일 흔한 손짓이다.
  String? _copied;
  String? _copiedTrack;

  /// **어디부터 틀었는가.** 자와 재생 막대는 곡 전체를 기준으로 그리는데,
  /// 중간부터 틀면 엔진이 주는 위치는 **그 자리부터 0** 이다. 이 값이 없으면
  /// 막대가 늘 맨 앞에서 다시 기어 나온다.
  int _from = 0;

  Arrangement get song => widget.project.song;

  /// 구간마다 (시작 초, 길이 초) — 계산은 `SceneSequencer.songSpans` 한 곳에만 둔다.
  /// (예전엔 여기서 구간마다 `build` 를 돌렸다 — 화면을 다시 그릴 때마다 곡 전체 음을
  /// 새로 만든 셈이다. 셈으로 내는 것과 결과는 같고 값은 시험이 맞춰 본다.)
  List<(double, double)> _spans() =>
      SceneSequencer.songSpans(widget.project, widget.transport);

  /// [from] 은 **몇 번째 구간부터** 틀 것인가. 3분짜리 곡의 뒷부분을 고칠 때
  /// 처음부터 다 듣지 않아도 된다.
  void _play({int from = 0}) {
    final host = widget.host;
    if (host == null) return;
    // **여기서 템포·조를 장르 기본값으로 되돌리면 안 된다.**
    //
    // 「곡 재생」은 **듣기**지 고치기가 아니다. 그런데 이 두 줄이 사용자가 맞춰 둔
    // 빠르기와 조를 누를 때마다 장르 기본값으로 되돌렸고, `Transport` 의 setter 가
    // `notifyListeners` 를 부르니 0.8초 뒤 그 값이 **파일에 저장까지** 됐다.
    // 조는 소리도 실제로 바뀐다(`build` 가 `MusicKey(root:, mode:)` 를 그대로 쓴다).
    //
    // 이 두 줄이 덮어 주던 진짜 구멍은 `Store.newSong`/`resetCurrent` 였다 —
    // `project.reset()` 이 스타일만 갈아입히고 Transport 는 안 맞춰서, 장조 곡에서
    // 새 곡을 만들면 로파이가 장조를 물려받았다. 그쪽을 막았으므로 여기는 뺀다.
    final b = SceneSequencer.playSong(
      widget.project,
      widget.transport,
      host,
      loop: _loop,
      from: from,
    );
    widget.transport.playing = true;
    // 씬 화면이 "다른 씬으로 갈아탈지"를 이걸로 가른다 — 곡 재생은 한 판이
    // 몇 분짜리라, 씬 칩을 눌러도 그 몇 분이 지나야 반영되는 것처럼 보였다.
    widget.transport.songLoop = true;
    setState(() {
      _built = b;
      _from = from;
    });
  }

  void _stop() {
    widget.host?.allOff();
    widget.host?.setSongMode(false);
    widget.transport.playing = false;
    widget.transport.songLoop = false;
    setState(() {});
  }

  /// 곡을 고쳤을 때 — **처음부터 다시** 튼다.
  ///
  /// 씬(한 판 10초)에서는 '다음 판부터'가 자연스럽지만, 곡은 한 바퀴가 1분이 넘는다.
  /// 그대로 두면 판 수를 바꾸고도 1분 넘게 옛 구성이 계속 흘러서 **"설정한 대로 안
  /// 흐른다"** 가 된다(사용자 지적). 고쳤으면 바로 그 구성으로 들려야 한다.
  void _refresh() {
    final host = widget.host;
    if (host == null || !widget.transport.playing) return;
    // 고치기 전에 「여기부터」로 틀어 뒀으면 **그 자리를 그대로 이어 간다** —
    // 뒷부분을 고치는 중인데 매번 곡 처음으로 돌아가면 고칠 수가 없다.
    final b = SceneSequencer.playSong(
      widget.project,
      widget.transport,
      host,
      loop: _loop,
      from: _from.clamp(0, song.sections.length),
    );
    setState(() => _built = b);
  }

  /// 곡을 WAV 파일로 뽑아서 공유 시트를 연다.
  ///
  /// 재생을 멈추고 뽑는다 — 렌더는 다른 아이솔레이트에서 돌지만, 폰 성능을 재생과
  /// 나눠 쓰면 재생 쪽이 끊긴다(이 앱에서 끊김은 제일 큰 흠이다).
  Future<void> _export() async {
    if (_exporting) return;
    // **빈 얼개는 빈 파일이 된다.** 구간을 다 지운 채로 누르면 44바이트짜리 WAV 가
    // 공유 시트로 나갔다 — 받은 사람은 「소리가 안 나요」를 겪고, 보낸 사람은
    // 무엇이 잘못됐는지 알 길이 없다. 나가기 전에 여기서 막는다.
    if (song.sections.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              '아직 구간이 없어요 — 아래에서 씬을 붙이고 다시 눌러 주세요',
              style: TextStyle(fontSize: 12.5),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    setState(() {
      _exporting = true;
      _exportPct = 0;
    });
    _stop();
    try {
      final b = SceneSequencer.buildSong(widget.project, widget.transport);
      final wav = await renderWavInIsolate(
        onProgress: (v) {
          if (mounted) setState(() => _exportPct = v);
        },
        ExportJob(
          notes: b.notes,
          drums: b.drums,
          busNames: b.busNames,
          buses: SceneSequencer.mixSnapshot(widget.project),
          inserts: {
            ...SceneSequencer.insertSnapshot(widget.project),
            if (widget.master != null)
              'master': [for (final f in widget.master!.chain) f.toJson()],
          },
          // 내보낸 파일도 **들리던 것과 같은 크기**여야 한다(5단계 34/N).
          // 스타일 보정 **× 마스터 페이더** — 페이더를 빠뜨리면 믹서에서 내려 놓고
          // 내보낸 파일만 그대로다(2026-08-30 에 잡았다).
          masterVol: SceneSequencer.exportMasterVol(
            widget.project,
            widget.master,
          ),
          // 재생과 같은 값 — 안 실으면 파일만 안 비켜 준다
          duck: kGenreDuck[widget.project.genre] ?? 0,
          seconds: b.totalSec,
          // 렌더는 **다른 아이솔레이트**에서 돈다 — `Human` 은 static 이라 거기서는
          // 기본값으로 시작한다. 지금 걸린 값을 실어 보낸다(안 실으면 「끔」으로
          // 해 놓아도 파일에는 흔들림이 들어간다).
          human: Human.level,
        ),
      );
      final dir = await getTemporaryDirectory();
      final g = songGenreOf(widget.project.genre);
      final title = widget.project.name.trim().isEmpty
          ? '새 곡'
          : widget.project.name.trim();
      final stem = exportStem(title, g.$2);
      final f = File('${dir.path}/$stem.wav');
      await f.writeAsBytes(wav);

      // ── 표지와 곡 정보 (계획 8-1) ──
      //
      // 예전엔 WAV 하나만 나갔다 — 받은 사람 화면에는 **회색 네모에 파일 이름**뿐이라
      // 무슨 곡인지 아무것도 안 보인다. 표지 한 장이면 그게 달라지고, 나중에 영상으로
      // 갈 때도 **그 프레임의 바탕**이 그대로 이것이다.
      //
      // 표지가 실패해도 곡은 나가야 한다 — 그림 때문에 음악을 못 보내면 본말전도다.
      final files = <XFile>[XFile(f.path, mimeType: 'audio/wav')];
      try {
        final sc = ShowScore.from(widget.project, widget.transport);
        final png = await renderCoverPng(
          CoverInfo(
            title: title,
            genreLabel: g.$2,
            genreKey: widget.project.genre,
            bpm: widget.transport.bpm,
            keyLabel: keyLabel(widget.transport.root, widget.transport.mode),
            seconds: b.totalSec,
            sections: [
              for (var i = 0; i < sc.spans.length; i++)
                (sc.sectionNames[i], sc.spans[i].$2),
            ],
          ),
        );
        final cf = File('${dir.path}/$stem.png');
        await cf.writeAsBytes(png);
        files.add(XFile(cf.path, mimeType: 'image/png'));
      } catch (_) {
        // 표지는 못 만들어도 그만 — 곡만 보낸다
      }

      final mm = b.totalSec ~/ 60, ss = (b.totalSec % 60).round();
      if (!mounted) return;
      await Share.shareXFiles(
        files,
        text:
            '$title — ${g.$2} · ${widget.transport.bpm.round()} BPM · '
            '$mm:${ss.toString().padLeft(2, '0')}\n음악 낙서장으로 만들었어요',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('내보내기 실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// 곡 길이 맞추기 줄 — 세로에서는 제 줄, 가로에서는 보기 줄 옆에 붙는다.
  Widget _lengthBar(BuildContext context, double total) => _LengthBar(
    total: total,
    onFit: (target) {
      final before = [...song.sections];
      final made = fitToLength(
        song.sections,
        target,
        secOf: (i) =>
            SceneSequencer.sceneLoopSec(widget.project, widget.transport, i),
        // 인트로·아웃트로는 자리를 지켜야 하는 것이라 안 건드린다
        isEnd: (i) {
          final sc = song.sections[i].scene;
          if (sc < 0 || sc >= widget.project.scenes.length) {
            return true;
          }
          final r = roleOf(widget.project.scenes[sc].name);
          return r == SectionRole.intro || r == SectionRole.outro;
        },
      );
      song.restore(made);
      _refresh();
      final now = SceneSequencer.songSeconds(widget.project, widget.transport);
      final m = ScaffoldMessenger.of(context);
      m.clearSnackBars();
      m.showSnackBar(
        SnackBar(
          content: Text(
            '${_mmss(now)} 짜리로 맞췄습니다',
            style: const TextStyle(fontSize: 12.5),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: '되돌리기',
            onPressed: () {
              song.restore(before);
              _refresh();
            },
          ),
        ),
      );
    },
  );
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([song, widget.project, widget.transport]),
      builder: (context, _) {
        final spans = _spans();
        final total = spans.isEmpty ? 0.0 : spans.last.$1 + spans.last.$2;
        return Column(
          children: [
            _Bar(
              playing: widget.transport.playing,
              total: total,
              built: _built,
              loop: _loop,
              exporting: _exporting,
              exportPct: _exportPct,
              onExport: _export,
              onPlay: _play,
              onStop: _stop,
              onLoop: (v) {
                setState(() => _loop = v);
                if (widget.transport.playing) _play();
              },
            ),
            LoopPosBuilder(
              host: widget.host,
              loopSec: total,
              builder: (context, pos, looping) => _Ruler(
                spans: spans,
                total: total,
                pos: pos,
                looping: looping,
                scenes: widget.project.scenes,
                sections: song.sections,
                bpm: widget.transport.bpm,
              ),
            ),
            // 가로로 누우면 높이가 귀하다 — 길이 줄과 보기 줄을 **한 줄로 붙인다**
            // (따로 두면 42px 이 더 들어 곡 목록이 화면 밖으로 밀린다).
            if (MediaQuery.of(context).size.height < 520)
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: _ModeBar(
                        mode: widget.mode,
                        onPick: (m) => widget.onMode?.call(m),
                      ),
                    ),
                    Expanded(flex: 5, child: _lengthBar(context, total)),
                  ],
                ),
              )
            else ...[
              _lengthBar(context, total),
              // 보는 방식 — **같은 구간표를 두 가지로 본다.** 옮겨 담지 않는다.
              _ModeBar(
                mode: widget.mode,
                onPick: (m) => widget.onMode?.call(m),
              ),
            ],
            if (widget.mode == 'timeline')
              Expanded(
                child: _Timeline(
                  onEditScene: widget.onEditScene,
                  copied: _copied,
                  copiedTrack: _copiedTrack,
                  onCopy: (trackId, pattern) => setState(() {
                    _copied = pattern;
                    _copiedTrack = trackId;
                  }),
                  song: song,
                  scenes: widget.project.scenes,
                  project: widget.project,
                  spans: spans,
                  total: total,
                  sel: _sel,
                  host: widget.host,
                  onSelect: (i) => setState(() => _sel = i),
                  onChanged: _refresh,
                  onPlayFrom: (i) => _play(from: i),
                ),
              )
            else
              // 구간은 **끌어서 순서를 바꾼다**(줄마다 ↑↓ 버튼을 두면 7~10개 구간에서
              // 한 칸씩 눌러 옮겨야 한다). 손잡이를 잡거나 줄을 길게 누르면 집힌다.
              Expanded(
                child: ReorderableListView(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                  buildDefaultDragHandles: false, // 손잡이는 우리가 놓는다
                  // `onReorderItem` 은 **이미 보정된** 새 자리를 준다(옛 `onReorder` 는
                  // 빼기 전 기준이라 직접 -1 해야 했다 — 한 칸씩 밀리는 흔한 버그).
                  onReorderItem: (oldIndex, newIndex) {
                    song.move(oldIndex, newIndex);
                    _refresh();
                  },
                  children: [
                    for (var i = 0; i < song.sections.length; i++)
                      _SectionRow(
                        // 키는 **자리가 아니라 그 구간 자체**를 가리켜야 한다.
                        // 자리 기반 키(`'$i-...'`)면 끌어서 옮길 때 키까지 같이 바뀌어
                        // Flutter 가 "같은 줄이 남아 있다"고 착각한다 → 순서가 안 바뀐다.
                        key: ObjectKey(song.sections[i]),
                        index: i,
                        section: song.sections[i],
                        scenes: widget.project.scenes,
                        seconds: i < spans.length ? spans[i].$2 : 0,
                        onChanged: _refresh,
                        song: song,
                        project: widget.project,
                        roll: sectionRoll(
                          widget.project,
                          song.sections[i].scene,
                        ),
                        onPlayFrom: () => _play(from: i),
                      ),
                  ],
                ),
              ),
            // 붙이기 줄은 **아래 고정** — 구간이 많아지면 맨 아래까지 스크롤해야 했다.
            // 가로로 누우면 높이가 귀하니 인라인 칩 대신 눌러야 뜨는 시트로 뺀다
            // (위 길이·보기 줄 합치기와 같은 문턱).
            _AddSection(
              scenes: widget.project.scenes,
              compact: MediaQuery.of(context).size.height < 520,
              onAdd: (i) {
                song.add(i);
                _refresh();
              },
            ),
          ],
        );
      },
    );
  }
}

String _mmss(double sec) {
  final s = sec.round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// 트랙 종류별 색 — 구간 줄·타임라인 블록에 「무엇이 들어 있나」를 띠로 보여 준다.
/// (쇼 화면과 같은 색을 쓴다 — 한 곡을 두 화면에서 다른 색으로 보면 헷갈린다)
const _typeColor = {
  'drum': Color(0xFF7CB342),
  'bass': Color(0xFF42A5F5),
  'chord': Color(0xFFAB47BC),
  'melody': Color(0xFFFFA726),
};

/// 그 씬에서 **소리 나는 트랙 종류**들 — 순서는 늘 드럼·베이스·코드·멜로디.
///
/// 이름이 다 「벌스」여도 어느 쪽이 두꺼운지 눈으로 갈린다. 재료는 이미 다 있다
/// (`Scene.clips` + `Project.audible`) — 안 보여 주고 있었을 뿐이다.
/// [section] 을 주면 **타임라인 트랙 줄에 놓은 클립**까지 센다 — 씬에서는 쉬는
/// 악기라도 그 구간에만 넣어 뒀으면 그 구간에서는 **소리가 난다.**
/// 안 세면 「드럼뿐」이라고 적어 놓고 기타가 나온다.
List<String> sectionTypes(Project p, int sceneIndex, {int? section}) {
  if (sceneIndex < 0 || sceneIndex >= p.scenes.length) return const [];
  final sc = p.scenes[sceneIndex];
  final seen = <String>{};
  final byId = {for (final t in p.tracks) t.id: t};
  if (section != null) {
    for (final c in p.song.lanes) {
      if (c.section != section) continue;
      final t = byId[c.trackId];
      if (t != null && p.audible(t)) seen.add(t.type);
    }
  }
  for (final t in p.tracks) {
    final clip = sc.clips[t.id];
    if (clip == null || clip.isEmpty) continue;
    if (!p.audible(t)) continue;
    seen.add(t.type);
  }
  return [
    for (final k in ['drum', 'bass', 'chord', 'melody'])
      if (seen.contains(k)) k,
  ];
}

/// 그 씬의 **가락 한 줄**을 뽑아 온다 — 미리보기에 그릴 재료.
///
/// 멜로디를 먼저 본다(귀에 제일 크게 남는 줄이다). 없으면 코드, 그것도 없으면 베이스.
/// `[도수, 스텝, 길이, ...]` 목록과 그 판의 칸 수를 같이 준다.
(List<List<Object?>>, int)? sectionRoll(Project p, int sceneIndex) {
  if (sceneIndex < 0 || sceneIndex >= p.scenes.length) return null;
  final sc = p.scenes[sceneIndex];
  for (final want in ['melody', 'chord', 'bass']) {
    for (final t in p.tracks) {
      if (t.type != want) continue;
      final clip = sc.clips[t.id];
      if (clip == null || clip.isEmpty) continue;
      if (!p.audible(t)) continue;
      final d = p.findNote(t.type, clip);
      if (d == null || d.notes.isEmpty) continue;
      return (
        tileNoteList(d.notes, d.src, d.bars, spb: d.spb),
        d.bars * d.spb,
      );
    }
  }
  return null;
}

/// **미니 피아노롤** — 그 구간이 어떤 가락인지 한 눈에.
///
/// 색 띠(`_TypeStrip`)는 「무엇이 들어 있나」를 말해 주지만 **어떤 곡인지**는
/// 말해 주지 않는다. 벌스가 둘이면 둘 다 「드럼·베이스·코드·멜로디」다.
/// 음을 점으로 찍어 두면 올라가는 가락인지 한 자리를 맴도는지가 그냥 보인다.
class _MiniRoll extends StatelessWidget {
  final List<List<Object?>> notes;
  final int steps;
  final Color color;
  final Size size;
  const _MiniRoll({
    required this.notes,
    required this.steps,
    required this.color,
    required this.size,
  });

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: size, painter: _RollPainter(notes, steps, color));
}

class _RollPainter extends CustomPainter {
  final List<List<Object?>> notes;
  final int steps;
  final Color color;
  _RollPainter(this.notes, this.steps, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (steps <= 0 || notes.isEmpty) return;
    // 도수 범위를 실제 쓰는 만큼만 편다 — 15줄로 고정하면 좁은 가락이 한 줄에 뭉친다
    var lo = 99, hi = -99;
    for (final n in notes) {
      final d = (n[0] as num).toInt();
      if (d < lo) lo = d;
      if (d > hi) hi = d;
    }
    final span = (hi - lo) < 2 ? 2 : (hi - lo);
    final p = Paint()..color = color;
    for (final n in notes) {
      final d = (n[0] as num).toInt();
      final st = (n[1] as num).toInt();
      final len = n.length > 2 ? (n[2] as num).toInt() : 1;
      final x = st / steps * size.width;
      final w = (len / steps * size.width).clamp(1.2, size.width);
      // 위가 높은 음 — 악보와 같은 방향
      final y = size.height - (d - lo) / span * (size.height - 1.6) - 1.6;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, 1.6),
          const Radius.circular(0.8),
        ),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_RollPainter old) =>
      old.notes != notes || old.steps != steps || old.color != color;
}

/// 구간에 무엇이 들어 있는지 보여 주는 작은 띠 줄.
class _TypeStrip extends StatelessWidget {
  final List<String> types;
  static const double height = 4;
  const _TypeStrip({required this.types});

  @override
  Widget build(BuildContext context) {
    if (types.isEmpty) {
      return SizedBox(
        height: height,
        child: const Text(
          '비어 있음',
          style: TextStyle(fontSize: 9, color: Colors.white24),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final t in types)
          Container(
            // 320dp 폰에서는 넷을 늘어놓으면 줄이 9px 넘친다 — 띠를 좁힌다.
            // 여기서 읽는 것은 「무엇이 몇 개」지 길이가 아니라 좁혀도 뜻이 안 준다.
            width: 10,
            height: height,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: _typeColor[t] ?? Colors.white30,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ],
    );
  }
}

/// 보는 방식 고르기 — **구간 목록 ↔ 타임라인.**
///
/// 두 화면이 **같은 구간표 하나**를 본다. 타임라인은 목록에서 마디 자리를 셈으로
/// 뽑아 그릴 뿐이라, 어느 쪽에서 고쳐도 다른 쪽에 그대로 있다.
class _ModeBar extends StatelessWidget {
  final String mode;
  final ValueChanged<String> onPick;
  const _ModeBar({required this.mode, required this.onPick});

  @override
  Widget build(BuildContext context) {
    Widget chip(String key, IconData icon, String label) {
      final on = mode == key;
      return Expanded(
        child: GestureDetector(
          onTap: () => onPick(key),
          child: Container(
            height: 38, // 손가락만 하게
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? Colors.indigo.shade400 : Colors.white10,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 15, color: on ? Colors.white : Colors.white38),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: on ? Colors.white : Colors.white38,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
      child: Row(
        children: [
          chip('list', Icons.reorder, '구간 목록'),
          const SizedBox(width: 6),
          chip('timeline', Icons.view_timeline, '타임라인'),
        ],
      ),
    );
  }
}

/// 타임라인 — 곡 전체를 **한 줄로 늘어놓아** 본다.
///
/// 목록은 「무엇이 몇 판인가」를 읽기 좋고, 타임라인은 「전체에서 어디쯤이고
/// 무엇이 긴가」가 한눈에 보인다. 3분짜리 곡에서 코러스가 짧다는 것은 목록으로는
/// 숫자를 더해 봐야 알고, 여기서는 그냥 보인다.
///
/// **자료는 구간표 하나뿐이다** — 폭은 `songSpans` 의 초를 그대로 쓴다.
/// 타임라인 — **마디 눈금 + 씬 줄 + 악기별 트랙 줄.** (옛 앱 타임라인 뷰)
///
/// 구간 목록과 **같은 구간표 하나**를 본다. 여기서 더해지는 것은 트랙 줄이다:
/// 칸을 누르면 그 마디부터 그 악기가 씬 것 대신 고른 패턴을 친다
/// (`Arrangement.lanes` · 재생 규칙은 `SceneSequencer._emitClip` 참고).
///
/// 칸마다 위젯을 만들지 않는다. 120마디 × 7줄이면 840개다 — 옛 앱이 보급형 폰에서
/// 그걸로 밀렸다. **격자는 그림 하나로 그리고, 줄마다 손잡이 하나만** 두고
/// 눌린 x 로 마디를 센다.
/// 곡 화면 맨 위 줄 — 재생 · 길이 · 반복 · 소리 파일로 내보내기.
///
/// **두 줄로 나눈다.** 넷을 한 줄에 넣었더니 폰에서 가운데 설명이 두 줄로 깨졌다.
/// 첫 줄은 큰 재생 버튼과 길이·내보내기, 둘째 줄은 설명 한 줄이다.
class _Bar extends StatelessWidget {
  final bool playing, loop, exporting;
  final double exportPct;
  final double total;
  final SceneBuild? built;
  final VoidCallback onPlay, onStop, onExport;
  final ValueChanged<bool> onLoop;
  const _Bar({
    required this.playing,
    required this.total,
    required this.built,
    required this.loop,
    required this.exporting,
    required this.exportPct,
    required this.onPlay,
    required this.onStop,
    required this.onExport,
    required this.onLoop,
  });

  @override
  Widget build(BuildContext context) {
    final b = built;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 재생 버튼은 **화면 절반보다 크게.** 이 화면에서 제일 자주 누르는 것이다.
              Expanded(
                flex: 5,
                child: SizedBox(
                  height: 44,
                  child: FilledButton.icon(
                    onPressed: playing ? onStop : onPlay,
                    icon: Icon(
                      playing ? Icons.stop : Icons.play_arrow,
                      size: 20,
                    ),
                    label: Text(
                      playing ? '정지' : '곡 재생',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: playing
                          ? Colors.red.shade600
                          : Colors.teal.shade600,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _mmss(total),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    b == null ? '곡 길이' : '${b.loopBars}마디',
                    maxLines: 1,
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: Colors.white38,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              // 반복 — 남에게 들려줄 때 곡이 끝나고 조용해지면 끝난 줄 모른다.
              GestureDetector(
                onTap: () => onLoop(!loop),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 40,
                  height: 44,
                  child: Icon(
                    Icons.repeat,
                    size: 19,
                    color: loop ? Colors.teal.shade300 : Colors.white24,
                  ),
                ),
              ),
              // 내보내기 — 만드는 동안은 몇 %인지 보여 준다(멈춘 것처럼 보이면 안 된다).
              GestureDetector(
                onTap: exporting ? null : onExport,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: exporting
                      ? Center(
                          child: Text(
                            '${(exportPct * 100).round()}%',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.white70,
                            ),
                          ),
                        )
                      : const Icon(
                          Icons.ios_share,
                          size: 19,
                          color: Colors.white54,
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            '구간을 늘어놓고 ▶ 를 누르면 한 곡으로 이어 흐릅니다.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: Colors.white38),
          ),
        ],
      ),
    );
  }
}

const _sceneColors = [
  Color(0xFF7E8CE0),
  Color(0xFF4DB6AC),
  Color(0xFFE0857E),
  Color(0xFFB39DDB),
  Color(0xFF9CCC65),
  Color(0xFFFFB74D),
];
Color _sceneColor(int i) => _sceneColors[i.abs() % _sceneColors.length];

/// 고른 구간에 대고 하는 일들 — 여기부터 재생 · 판 수 · 한 벌 더 · 좌우로 옮기기 · 지우기.
///
/// **고르기 전에는 안 나온다.** 늘 띄우면 구간을 안 고른 사람에게도 자리만 먹는다.
class _BlockBar extends StatelessWidget {
  final int index;
  final Section section;
  final Arrangement song;
  final VoidCallback onChanged;
  final VoidCallback onPlay;

  /// 이 씬 고치러 가기. 못 가면 null — 흐린 손잡이가 된다.
  final VoidCallback? onEdit;
  final VoidCallback onDone;
  const _BlockBar({
    required this.index,
    required this.section,
    required this.song,
    required this.onChanged,
    required this.onPlay,
    required this.onEdit,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          // **이름이 먼저 줄고, 그래도 모자라면 손잡이 줄이 옆으로 흐른다.**
          // 손잡이가 아홉이라 320dp 폰에서는 어차피 다 못 놓는다 — 잘라 버리면
          // 작은 폰에서만 못 쓰는 손잡이가 생긴다.
          //
          // 이 줄은 **구간을 골라야 나온다.** 그래서 화면 넘침 검사가 여태 여기를
          // 못 봤다(안 고르면 줄이 없으니까) — 고른 채로 재는 검사를 따로 뒀다.
          Flexible(
            child: Text(
              '${index + 1}번 구간',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: Colors.white54,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _SmallBtn(icon: Icons.play_arrow, onTap: onPlay),
                  // **이 씬 고치러 가기.** 여태는 뒤로 → 만들기 → 씬 고르기 세 걸음이었다.
                  _SmallBtn(icon: Icons.edit_note, onTap: onEdit),
                  // 판 수 — 여기가 곧 구간 길이다(타임라인에서 블록이 그만큼 길어진다).
                  _SmallBtn(
                    icon: Icons.remove,
                    onTap: section.reps > 1
                        ? () {
                            song.setReps(index, section.reps - 1);
                            onChanged();
                          }
                        : null,
                  ),
                  SizedBox(
                    width: 34,
                    child: Text(
                      '${section.reps}판',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _SmallBtn(
                    icon: Icons.add,
                    onTap: () {
                      song.setReps(index, section.reps + 1);
                      onChanged();
                    },
                  ),
                  _SmallBtn(
                    icon: Icons.chevron_left,
                    onTap: index > 0
                        ? () {
                            song.move(index, index - 1);
                            onChanged();
                          }
                        : null,
                  ),
                  _SmallBtn(
                    icon: Icons.chevron_right,
                    onTap: index < song.sections.length - 1
                        ? () {
                            song.move(index, index + 1);
                            onChanged();
                          }
                        : null,
                  ),
                  // 한 벌 더 — 코러스를 두 번 돌리려고 맨 뒤에 붙였다 끌어올릴 일이 없다.
                  _SmallBtn(
                    icon: Icons.content_copy,
                    onTap: () {
                      song.duplicateAt(index);
                      onChanged();
                    },
                  ),
                  _SmallBtn(
                    icon: Icons.delete_outline,
                    onTap: () {
                      song.removeAt(index);
                      onDone();
                      onChanged();
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  /// 이 씬 고치기 — 없으면 손잡이를 안 낸다(§15: 못 하는 것은 안 내놓는다).
  final ValueChanged<int>? onEditScene;

  /// 복사해 둔 클립 — 빈 칸을 **꾹 누르면** 여기에 붙는다.
  /// 트랙 종류가 달라도 붙게 두면 엉뚱한 판이 실린다 —
  /// **같은 트랙에서 복사한 것만** 붙인다.
  final String? copied, copiedTrack;
  final void Function(String trackId, String pattern) onCopy;
  final Arrangement song;
  final List<Scene> scenes;
  final Project project;
  final List<(double, double)> spans;
  final double total;
  final int sel;
  final AudioClient? host;
  final ValueChanged<int> onSelect;
  final VoidCallback onChanged;
  final ValueChanged<int> onPlayFrom;

  const _Timeline({
    required this.onEditScene,
    required this.copied,
    required this.copiedTrack,
    required this.onCopy,
    required this.song,
    required this.scenes,
    required this.project,
    required this.spans,
    required this.total,
    required this.sel,
    required this.host,
    required this.onSelect,
    required this.onChanged,
    required this.onPlayFrom,
  });

  /// 마디 하나의 폭(px). 손가락으로 칸을 짚어야 하므로 너무 좁히지 않는다.
  static const double _barW = kTimelineBarW;
  static const double _rulerH = 20.0;
  static const double _sceneH = 54.0;
  static const double _laneH = 38.0;
  static const double _labelW = 76.0;

  /// 구간마다 (시작 마디, 마디 수). 초가 아니라 **마디**로 잰다 —
  /// 타임라인의 자리는 마디가 정한다.
  List<(int, int)> _bars() {
    final out = <(int, int)>[];
    var at = 0;
    for (final sec in song.sections) {
      final n = SceneSequencer.sceneLoopBars(project, sec.scene) * sec.reps;
      out.add((at, n));
      at += n;
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    if (song.sections.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '아직 구간이 없습니다\n아래에서 씬을 눌러 붙여 보세요',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.white38),
          ),
        ),
      );
    }
    final bars = _bars();
    final totalBars = bars.isEmpty ? 0 : bars.last.$1 + bars.last.$2;
    final width = (totalBars * _barW).clamp(_barW, 1 << 20).toDouble();
    final selOk = sel >= 0 && sel < song.sections.length;
    final tracks = project.tracks;

    Widget label(
      String text,
      double h, {
      Color? dot,
      bool head = false,
      VoidCallback? onTap,
    }) {
      final body = SizedBox(
        height: h,
        child: Padding(
          padding: const EdgeInsets.only(left: 6, right: 4),
          child: Row(
            children: [
              if (dot != null) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: dot,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: head ? 10 : 11.5,
                    fontWeight: head ? FontWeight.w400 : FontWeight.w700,
                    color: head ? Colors.white24 : Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      // 악기 줄 이름을 누르면 **그 트랙의 믹서·설정**이 바로 뜬다 — 타임라인
      // 에서 소리·톤을 만지러 씬 화면까지 오갈 필요가 없다.
      return onTap == null ? body : InkWell(onTap: onTap, child: body);
    }

    return Column(
      children: [
        // **한 번만 가르친다.** 클립을 하나라도 놓으면 사라진다 —
        // 이미 아는 사람에게 계속 자리를 뺏을 이유가 없다.
        if (song.lanes.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
            child: Row(
              children: [
                const Icon(Icons.touch_app, size: 13, color: Colors.white24),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '악기 줄의 빈 칸을 누르면 그 자리에만 다른 판이 들어갑니다.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: Colors.white.withValues(alpha: 0.32),
                    ),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 왼쪽 이름 칸은 **안 흐른다** — 옆으로 밀어도 어느 줄인지 보여야 한다.
                SizedBox(
                  width: _labelW,
                  child: Column(
                    children: [
                      label('마디', _rulerH, head: true),
                      label('씬', _sceneH),
                      for (final t in tracks)
                        label(
                          t.name,
                          _laneH,
                          dot: _typeColor[t.type] ?? Colors.grey,
                          onTap: () => showChannelSheet(
                            context,
                            track: t,
                            color: _typeColor[t.type] ?? Colors.grey,
                            onChanged: onChanged,
                            onSolo: onChanged,
                            host: host,
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: _LaneScroll(
                    host: host,
                    total: total,
                    xOf: (now) => _headX(spans, bars, now, _barW),
                    child: SizedBox(
                      width: width,
                      child: Stack(
                        children: [
                          Column(
                            children: [
                              _Ruler2(
                                totalBars: totalBars,
                                barW: _barW,
                                height: _rulerH,
                              ),
                              _SceneLane(
                                song: song,
                                scenes: scenes,
                                project: project,
                                bars: bars,
                                barW: _barW,
                                height: _sceneH,
                                sel: sel,
                                onSelect: onSelect,
                                onChanged: onChanged,
                              ),
                              for (final t in tracks)
                                _TrackLane(
                                  track: t,
                                  song: song,
                                  project: project,
                                  bars: bars,
                                  barW: _barW,
                                  height: _laneH,
                                  onTapBar: (secIndex, barInSec) =>
                                      _putClip(context, t, secIndex, barInSec),
                                  onTapClip: (c) => _clipMenu(context, t, c),
                                  // 꾹 = 복사해 둔 것 붙이기(같은 트랙 것만).
                                  // 없으면 고르기와 똑같다 — 빈손으로 꾹 눌렀을 때
                                  // 아무 일도 안 일어나면 고장으로 보인다.
                                  onHoldBar: (secIndex, barInSec) {
                                    if (copied != null && copiedTrack == t.id) {
                                      song.putLane(
                                        secIndex,
                                        barInSec,
                                        t.id,
                                        copied!,
                                      );
                                      onChanged();
                                    } else {
                                      _putClip(context, t, secIndex, barInSec);
                                    }
                                  },
                                ),
                              const SizedBox(height: 6),
                            ],
                          ),
                          // **재생선.** 타임라인인데 지금 어디를 지나는지 안 보이면
                          // 줄만 늘어놓은 표다. 자기 위젯이라 이것만 다시 그려진다.
                          Positioned.fill(
                            child: IgnorePointer(
                              child: LoopPosBuilder(
                                host: host,
                                loopSec: total,
                                builder: (context, pos, looping) => !looping
                                    ? const SizedBox.shrink()
                                    : CustomPaint(
                                        painter: _HeadPainter(
                                          _xOf(pos * total, bars),
                                          _rulerH,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // 고른 구간의 손잡이 — **고르기 전에는 안 나온다**(늘 띄우면 자리만 먹는다)
        if (selOk)
          _BlockBar(
            index: sel,
            section: song.sections[sel],
            song: song,
            onChanged: onChanged,
            onPlay: () => onPlayFrom(sel),
            onEdit: onEditScene == null
                ? null
                : () => onEditScene!(song.sections[sel].scene),
            onDone: () => onSelect(-1),
          ),
      ],
    );
  }

  double _xOf(double now, List<(int, int)> bars) =>
      _headX(spans, bars, now, _barW);

  Future<void> _putClip(
    BuildContext context,
    Track t,
    int section,
    int bar,
  ) async {
    final picked = await pickPatternSheet(
      context,
      title: '${t.name} — ${section + 1}번 구간 ${bar + 1}마디',
      names: SceneSequencer.patternNamesFor(project, t.type),
      current: null,
      color: _typeColor[t.type] ?? Colors.teal,
      genre: project.genre,
      isMine: project.isMine,
      meterHint: _meterHint(),
      allowDraw: false,
    );
    if (picked == null) return;
    song.putLane(section, bar, t.id, picked);
    onChanged();
  }

  // 4/4 가 아니면 **왜 목록이 줄었는지** 한 줄 적어 준다(5단계 47/N).
  String? _meterHint() {
    final m = project.meterDef;
    return m.isFour
        ? null
        : '${m.feel.split(' — ').first} 곡이라 그 박자의 판만 보여요.';
  }

  Future<void> _clipMenu(BuildContext context, Track t, LaneClip c) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.swap_horiz, size: 20),
              title: Text(
                // 여기도 **보여 주는 이름**이다 — 줄에는 한글, 메뉴에는 영어면
                // 같은 것인 줄 모른다.
                '패턴 바꾸기 — ${patternLabel(c.pattern)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final picked = await pickPatternSheet(
                  context,
                  title: t.name,
                  names: SceneSequencer.patternNamesFor(project, t.type),
                  current: c.pattern,
                  color: _typeColor[t.type] ?? Colors.teal,
                  genre: project.genre,
                  isMine: project.isMine,
                  meterHint: _meterHint(),
                  allowDraw: false,
                );
                if (picked == null) return;
                song.putLane(c.section, c.bar, c.trackId, picked);
                onChanged();
              },
            ),
            // 한 칸씩 옮기기 — 지웠다 다시 놓는 것보다 훨씬 빠르다.
            // 구간 밖으로는 못 나간다(나가면 소리가 안 나므로 옮긴 뜻이 없다).
            ListTile(
              leading: const Icon(
                Icons.swap_horizontal_circle_outlined,
                size: 20,
              ),
              title: const Text('한 칸씩 옮기기', style: TextStyle(fontSize: 14)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SmallBtn(
                    icon: Icons.chevron_left,
                    onTap: c.bar > 0
                        ? () {
                            song.lanes.remove(c);
                            song.putLane(
                              c.section,
                              c.bar - 1,
                              c.trackId,
                              c.pattern,
                            );
                            Navigator.pop(ctx);
                            onChanged();
                          }
                        : null,
                  ),
                  _SmallBtn(
                    icon: Icons.chevron_right,
                    onTap: () {
                      song.lanes.remove(c);
                      song.putLane(c.section, c.bar + 1, c.trackId, c.pattern);
                      Navigator.pop(ctx);
                      onChanged();
                    },
                  ),
                ],
              ),
            ),
            // 복사 — 하나 만들어 두고 여러 자리에 붙이는 것이 트랙 줄을 쓰는
            // 제일 흔한 손짓이다(옛 앱의 `tlClip9` 자리).
            ListTile(
              leading: const Icon(Icons.content_copy, size: 20),
              title: const Text(
                '복사 — 빈 칸을 꾹 누르면 붙습니다',
                style: TextStyle(fontSize: 14),
              ),
              onTap: () {
                Navigator.pop(ctx);
                onCopy(c.trackId, c.pattern);
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                        '「${patternLabel(c.pattern)}」 복사 — '
                        '${t.name} 줄의 빈 칸을 꾹 누르면 붙습니다',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_outline,
                size: 20,
                color: Colors.red.shade300,
              ),
              title: Text(
                '이 자리 지우기 — 씬 것으로 돌아갑니다',
                style: TextStyle(fontSize: 14, color: Colors.red.shade300),
              ),
              onTap: () {
                Navigator.pop(ctx);
                song.removeLane(c);
                onChanged();
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 마디 하나의 폭(px) — 타임라인이 자리를 잡는 자. 시험도 같은 값을 써야 한다.
const double kTimelineBarW = 30.0;

/// 지금 몇 초인가 → 타임라인에서 **몇 px 자리**인가. 곡 밖이면 −1.
///
/// 초와 마디는 씬마다 빠르기가 달라 딱 비례하지 않는다 — 그래서 **구간을 찾아
/// 그 안에서만** 비례로 나눈다(구간 안에서는 빠르기가 하나다).
double _headX(
  List<(double, double)> spans,
  List<(int, int)> bars,
  double now,
  double barW,
) {
  for (var i = 0; i < spans.length && i < bars.length; i++) {
    final (st, du) = spans[i];
    if (du <= 0 || now < st || now >= st + du) continue;
    return (bars[i].$1 + bars[i].$2 * (now - st) / du) * barW;
  }
  return -1;
}

/// 시험이 재는 자리 — 화면을 안 세우고도 재생선 셈을 확인할 수 있다.
double timelineHeadX(Project p, List<(double, double)> spans, double now) {
  final bars = <(int, int)>[];
  var at = 0;
  for (final sec in p.song.sections) {
    final n = SceneSequencer.sceneLoopBars(p, sec.scene) * sec.reps;
    bars.add((at, n));
    at += n;
  }
  return _headX(spans, bars, now, kTimelineBarW);
}

/// 옆으로 흐르는 줄들 — **재생선을 따라간다.**
///
/// 3분짜리 곡은 마디가 100을 넘는다. 재생선이 화면 밖으로 나가면 타임라인은
/// 「지금 어디」를 말해 주지 못한다.
///
/// 편집기와 **같은 규칙**을 쓴다(`followTarget`): 보이는 폭을 벗어날 때만,
/// 왼쪽 15% 자리로 끌어온다. 그리고 **손으로 민 뒤 5초는 가만히 있는다** —
/// 뒷부분을 보려고 민 사람을 계속 앞으로 끌어오면 아무것도 못 본다.
class _LaneScroll extends StatefulWidget {
  final AudioClient? host;
  final double total;
  final double Function(double now) xOf;
  final Widget child;
  const _LaneScroll({
    required this.host,
    required this.total,
    required this.xOf,
    required this.child,
  });

  @override
  State<_LaneScroll> createState() => _LaneScrollState();
}

class _LaneScrollState extends State<_LaneScroll>
    with SingleTickerProviderStateMixin {
  final _hs = ScrollController();
  final _clock = LoopClock();
  late final AnimationController _tick;
  int _holdUntilMs = 0;
  bool _moving = false;

  @override
  void initState() {
    super.initState();
    _tick = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    _clock.attach(
      widget.host,
      onLooping: (on) {
        if (!mounted) return;
        if (on) {
          _tick.repeat();
        } else {
          _tick.stop();
        }
      },
    );
    _tick.addListener(_follow);
  }

  @override
  void dispose() {
    _tick.removeListener(_follow);
    _clock.dispose();
    _tick.dispose();
    _hs.dispose();
    super.dispose();
  }

  void _follow() {
    if (!mounted || !_hs.hasClients || _moving || !_clock.looping) return;
    if (DateTime.now().millisecondsSinceEpoch < _holdUntilMs) return;
    if (widget.total <= 0) return;
    final x = widget.xOf(_clock.pos(widget.total) * widget.total);
    if (x < 0) return;
    final p = _hs.position;
    final want = followTarget(
      x: x,
      offset: _hs.offset,
      viewport: p.viewportDimension,
      maxScroll: p.maxScrollExtent,
    );
    if (want == null) return;
    _moving = true;
    _hs
        .animateTo(
          want,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        )
        .whenComplete(() => _moving = false);
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      // 손으로 민 것만 잡는다 — 우리가 `animateTo` 로 옮긴 것은 `dragDetails` 가
      // 없어서 구분된다(안 그러면 스스로를 막는다).
      onNotification: (n) {
        if ((n is ScrollStartNotification && n.dragDetails != null) ||
            (n is ScrollUpdateNotification && n.dragDetails != null)) {
          _holdUntilMs = DateTime.now().millisecondsSinceEpoch + 5000;
        }
        return false;
      },
      child: SingleChildScrollView(
        controller: _hs,
        scrollDirection: Axis.horizontal,
        child: widget.child,
      ),
    );
  }
}

/// 재생선 — 눈금 아래부터 맨 아래까지 한 줄.
class _HeadPainter extends CustomPainter {
  final double x;
  final double top;
  const _HeadPainter(this.x, this.top);

  @override
  void paint(Canvas c, Size size) {
    if (x < 0) return;
    c.drawRect(
      Rect.fromLTWH(x, top, 1.6, size.height - top),
      Paint()..color = Colors.tealAccent.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(_HeadPainter old) => old.x != x || old.top != top;
}

/// 마디 눈금. 4마디마다 숫자를 적는다 — 마디마다 적으면 30px 폭에서 다 못 읽는다.
class _Ruler2 extends StatelessWidget {
  final int totalBars;
  final double barW, height;
  const _Ruler2({
    required this.totalBars,
    required this.barW,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          for (var b = 0; b < totalBars; b += 4)
            Positioned(
              left: b * barW + 2,
              top: 2,
              child: Text(
                '${b + 1}',
                style: const TextStyle(fontSize: 9.5, color: Colors.white30),
              ),
            ),
        ],
      ),
    );
  }
}

/// 격자 — 마디마다 옅은 줄, 4마디마다 진한 줄, 구간이 바뀌는 자리는 더 진하게.
class _GridPainter extends CustomPainter {
  final int totalBars;
  final double barW;
  final Set<int> sectionStarts;
  const _GridPainter(this.totalBars, this.barW, this.sectionStarts);

  @override
  void paint(Canvas c, Size size) {
    final thin = Paint()..color = Colors.white.withValues(alpha: 0.05);
    final quad = Paint()..color = Colors.white.withValues(alpha: 0.11);
    final edge = Paint()..color = Colors.white.withValues(alpha: 0.28);
    for (var b = 0; b <= totalBars; b++) {
      final x = b * barW;
      final p = sectionStarts.contains(b) ? edge : (b % 4 == 0 ? quad : thin);
      c.drawRect(Rect.fromLTWH(x, 0, 1, size.height), p);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.totalBars != totalBars ||
      old.barW != barW ||
      // **개수만 견주면 안 된다** — 구간 길이를 바꾸면 경계 자리는 옮겨지는데
      // 개수는 그대로다. 그러면 진한 줄이 옛 자리에 남는다.
      !setEquals(old.sectionStarts, sectionStarts);
}

/// 씬 줄 — 구간표를 마디 자리로 편 것. **여기가 곧 구간표다**(옮겨 담지 않는다).
class _SceneLane extends StatefulWidget {
  final Arrangement song;
  final List<Scene> scenes;
  final Project project;
  final List<(int, int)> bars;
  final double barW, height;
  final int sel;
  final ValueChanged<int> onSelect;

  /// 끌어서 순서·길이를 바꾼 뒤 — 재생 중이면 그 자리에서 다시 잇는다.
  final VoidCallback onChanged;
  const _SceneLane({
    required this.song,
    required this.scenes,
    required this.project,
    required this.bars,
    required this.barW,
    required this.height,
    required this.sel,
    required this.onSelect,
    required this.onChanged,
  });

  @override
  State<_SceneLane> createState() => _SceneLaneState();
}

class _SceneLaneState extends State<_SceneLane> {
  Arrangement get song => widget.song;
  List<Scene> get scenes => widget.scenes;
  Project get project => widget.project;
  List<(int, int)> get bars => widget.bars;
  double get barW => widget.barW;
  double get height => widget.height;
  int get sel => widget.sel;

  /// **구간 카드를 끌어서 순서 바꾸기.** 손가락이 옆 구간의 절반을 넘는
  /// 순간 `song.move` 를 부른다 — `ReorderableListView` 와 같은 「넘으면
  /// 바로 자리를 바꾼다」 느낌을, 마디 비율대로 늘어선 이 줄에서도 낸다.
  int? _dragI; // 지금 끌고 있는 구간의 자리(끌면서 바뀐다)
  double _dragDx = 0; // 그 구간이 제자리에서 얼마나 밀렸나(px)

  /// **구간 오른쪽 모서리를 끌어서 길이(판 수) 바꾸기.** 씬 한 판 너비만큼
  /// 끌 때마다 1판씩 늘거나 준다 — 버튼(±)을 여러 번 누르지 않아도 된다.
  int? _resizeI;
  double _resizeDx = 0;

  void _dragStart(int i) {
    setState(() {
      _dragI = i;
      _dragDx = 0;
    });
  }

  void _dragUpdate(DragUpdateDetails d) {
    final i = _dragI;
    if (i == null) return;
    setState(() => _dragDx += d.delta.dx);
    final w = bars[i].$2 * barW;
    // 내 너비의 반을 넘어 옆으로 갔으면 그 옆과 자리를 바꾼다.
    if (_dragDx > w / 2 && i < song.sections.length - 1) {
      final nextW = bars[i + 1].$2 * barW;
      song.move(i, i + 1);
      widget.onChanged();
      setState(() {
        _dragI = i + 1;
        _dragDx -= nextW;
      });
      if (sel == i) widget.onSelect(i + 1);
    } else if (_dragDx < -w / 2 && i > 0) {
      final prevW = bars[i - 1].$2 * barW;
      song.move(i, i - 1);
      widget.onChanged();
      setState(() {
        _dragI = i - 1;
        _dragDx += prevW;
      });
      if (sel == i) widget.onSelect(i - 1);
    }
  }

  void _dragEnd() => setState(() {
    _dragI = null;
    _dragDx = 0;
  });

  void _resizeStart(int i) {
    setState(() {
      _resizeI = i;
      _resizeDx = 0;
    });
  }

  void _resizeUpdate(int i, DragUpdateDetails d) {
    setState(() => _resizeDx += d.delta.dx);
    // 씬 한 판(반복 하나)의 너비 — 이만큼 끌 때마다 1판.
    final oneRepBars = SceneSequencer.sceneLoopBars(
      project,
      song.sections[i].scene,
    );
    final oneRepW = oneRepBars * barW;
    if (oneRepW <= 0) return;
    final steps = (_resizeDx / oneRepW).truncate();
    if (steps == 0) return;
    final cur = song.sections[i].reps;
    final next = (cur + steps).clamp(1, 32);
    if (next != cur) {
      song.setReps(i, next);
      widget.onChanged();
      setState(() => _resizeDx -= steps * oneRepW);
    }
  }

  void _resizeEnd() => setState(() {
    _resizeI = null;
    _resizeDx = 0;
  });

  @override
  Widget build(BuildContext context) {
    final totalBars = bars.isEmpty ? 0 : bars.last.$1 + bars.last.$2;
    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _GridPainter(totalBars, barW, {
                for (final b in bars) b.$1,
              }),
            ),
          ),
          for (var i = 0; i < bars.length && i < song.sections.length; i++)
            Positioned(
              left: bars[i].$1 * barW + 1 + (i == _dragI ? _dragDx : 0),
              top: 3,
              width:
                  bars[i].$2 * barW -
                  3 +
                  (i == _resizeI ? _resizeDx.clamp(-(bars[i].$2 * barW - 8), 1e9) : 0),
              height: height - 6,
              child: GestureDetector(
                key: ValueKey('secblk-$i'), // 시험이 이름 겹침 없이 자리로 찾게
                onTap: () => onSelect(sel == i ? -1 : i),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: _sceneColor(
                      song.sections[i].scene,
                    ).withValues(alpha: i == _dragI ? 0.6 : (sel == i ? 0.42 : 0.2)),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _sceneColor(
                        song.sections[i].scene,
                      ).withValues(alpha: sel == i || i == _dragI ? 1 : 0.5),
                      width: sel == i || i == _dragI ? 1.6 : 1,
                    ),
                    boxShadow: i == _dragI
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Stack(
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.sections[i].scene >= 0 &&
                                    song.sections[i].scene < scenes.length
                                ? scenes[song.sections[i].scene].name
                                : '(없는 씬)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            '${song.sections[i].reps}판 · ${bars[i].$2}마디',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white38,
                            ),
                          ),
                          // 색 띠는 「무엇이 들어 있나」만 말한다 — 벌스가 둘이면
                          // 둘 다 같다. 가락을 점으로 찍어야 어느 구간인지 보인다.
                          // 좁은 블록에서는 접는다(1마디짜리에 그려 봐야 뭉갠다).
                          if (bars[i].$2 * barW >= 96)
                            Builder(
                              builder: (_) {
                                final r = sectionRoll(
                                  project,
                                  song.sections[i].scene,
                                );
                                if (r == null) return const SizedBox.shrink();
                                return Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: _MiniRoll(
                                    notes: r.$1,
                                    steps: r.$2,
                                    color: _sceneColor(
                                      song.sections[i].scene,
                                    ).withValues(alpha: 0.9),
                                    size: Size(bars[i].$2 * barW - 16, 11),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                      // **왼쪽 모서리 — 끌면 순서가 바뀐다.** 카드 전체를 끌게
                      // 하면 타임라인이 통째로 옆으로 스크롤되는 것(가로로 긴
                      // 줄이라 이 줄 자체가 가로로 밀린다)과 손짓이 겹쳐서,
                      // 실기기에서 시험해 보니 스크롤이 항상 이겼다(카드가 하나도
                      // 안 옮겨졌다). 손잡이 하나로 **그 손짓만 먼저 채간다**
                      // (`ImmediateMultiDragGestureRecognizer` — `Draggable` 이
                      // 리스트 안에서 쓰는 것과 같은 길).
                      if (bars[i].$2 * barW >= 30)
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: 16,
                          child: _ClaimDrag(
                            key: ValueKey('secreorder-$i'),
                            onStart: () => _dragStart(i),
                            onUpdate: _dragUpdate,
                            onEnd: _dragEnd,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 3),
                                child: _ResizeGrip(
                                  on: i == _dragI,
                                  label: '구간 순서 손잡이',
                                ),
                              ),
                            ),
                          ),
                        ),
                      // **오른쪽 모서리 — 끌면 길이(판 수)가 바뀐다.** 눈에 보이는
                      // 손잡이(세로 선 둘)를 안 그리면 "여기가 끌리는 자리"인 줄
                      // 아무도 모른다. 왼쪽과 같은 이유로 같은 길을 쓴다.
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        width: 16,
                        child: _ClaimDrag(
                          key: ValueKey('secresize-$i'),
                          onStart: () => _resizeStart(i),
                          onUpdate: (d) => _resizeUpdate(i, d),
                          onEnd: _resizeEnd,
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 3),
                              child: _ResizeGrip(
                                on: i == _resizeI,
                                label: '구간 길이 손잡이',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void onSelect(int i) => widget.onSelect(i);
}

/// **가로로 스크롤하는 줄 안에서 손짓을 먼저 채가는 손잡이.**
///
/// 타임라인 자체가 가로로 길어서 `_LaneScroll`(안의 `SingleChildScrollView`)
/// 이 가로 끌기를 듣고 있다 — 평범한 `GestureDetector.onHorizontalDrag*`
/// 를 손잡이에 달면 그 스크롤과 같은 손짓을 다투게 되는데, 실기기에서
/// 시험해 보니 **스크롤이 늘 이겼다**(카드가 하나도 안 옮겨졌다). `Draggable`
/// 이 리스트 안에서도 잘 끌리는 것과 같은 길 — `ImmediateMultiDragGestureRecognizer`
/// 는 손을 대는 순간 바로 손짓을 받아 가서, 뒤에 있는 스크롤이 경합할 틈이
/// 없다.
class _ClaimDrag extends StatefulWidget {
  final VoidCallback onStart;
  final void Function(DragUpdateDetails) onUpdate;
  final VoidCallback onEnd;
  final Widget child;
  const _ClaimDrag({
    super.key,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.child,
  });

  @override
  State<_ClaimDrag> createState() => _ClaimDragState();
}

/// **손수 recognizer 를 붙인다** — `RawGestureDetector.gestures` 맵으로
/// 짜면(선언형) 실기기에서 `onStart` 가 한 번도 안 불렸다(로그로 확인—
/// `Listener.onPointerDown` 은 불렸는데 recognizer 는 안 물렸다). 원인은
/// 못 밝혔지만, `Draggable` 이 안에서 쓰는 것과 같은 **저수준** 길로
/// 바꾸니(눌리는 순간 `recognizer.addPointer(event)` 를 직접 부른다)
/// 확실히 물렸다 — 이 길이 더 널리 검증된 길이기도 하다.
class _ClaimDragState extends State<_ClaimDrag> {
  late final ImmediateMultiDragGestureRecognizer _recognizer;

  @override
  void initState() {
    super.initState();
    _recognizer = ImmediateMultiDragGestureRecognizer()
      ..onStart = (_) {
        widget.onStart();
        return _GripDrag(onUpdate: widget.onUpdate, onEnd: widget.onEnd);
      };
  }

  @override
  void dispose() {
    _recognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _recognizer.addPointer,
      child: widget.child,
    );
  }
}

/// [_ClaimDrag] 이 리듬을 넘겨주는 자리 — 업데이트·끝을 그대로 전달만 한다.
class _GripDrag extends Drag {
  final void Function(DragUpdateDetails) onUpdate;
  final VoidCallback onEnd;
  _GripDrag({required this.onUpdate, required this.onEnd});

  @override
  void update(DragUpdateDetails details) => onUpdate(details);

  @override
  void end(DragEndDetails details) => onEnd();

  @override
  void cancel() => onEnd();
}

/// 타임라인 구간 오른쪽 모서리의 **길이 손잡이** — 세로 선 둘로 "여기를
/// 끌면 늘어난다"는 뜻을 낸다. `Icons.drag_indicator`(점 여섯)는 구간
/// 목록의 순서 손잡이가 이미 쓰고 있어서, 시험이 개수로 구분할 수 있게
/// 일부러 다른 모양을 그린다(아이콘이 아니라 `Semantics` 라벨로 찾는다).
class _ResizeGrip extends StatelessWidget {
  final bool on;

  /// 왼쪽(순서 손잡이)과 오른쪽(길이 손잡이)이 모양은 같고 뜻만 다르다 —
  /// 시험이 `Semantics` 라벨로 구분한다(모양은 아이콘 겹침을 피하려고
  /// 일부러 `Icons.drag_indicator` 대신 직접 그린다).
  final String label;
  const _ResizeGrip({required this.on, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = Colors.white.withValues(alpha: on ? 0.9 : 0.35);
    return Semantics(
      label: label,
      // `container: true` 가 없으면 이 라벨이 카드 전체의 시맨틱 노드에
      // 다른 글자들과 합쳐져 "인트로\n1판 · 4마디\n구간 순서 손잡이…"
      // 처럼 뭉친다 — 시험이 정확한 문구로 못 찾는다(직접 겪었다).
      container: true,
      child: SizedBox(
        width: 6,
        height: 16,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(width: 1.4, color: color),
            Container(width: 1.4, color: color),
          ],
        ),
      ),
    );
  }
}

/// 악기 한 줄. 빈 칸을 누르면 패턴을 놓고, 놓인 클립을 누르면 바꾸거나 지운다.
class _TrackLane extends StatelessWidget {
  /// **눌린 마디**를 잠깐 적어 두는 상자. 탭이냐 꾹이냐는 손을 떼야 알 수 있으므로
  /// 누른 자리를 먼저 적어 둬야 한다(상태 없는 위젯이라 상자에 담는다).
  final _down = ValueNotifier<int>(0);

  final Track track;
  final Arrangement song;
  final Project project;
  final List<(int, int)> bars;
  final double barW, height;
  final void Function(int section, int bar) onTapBar;
  final void Function(int section, int bar) onHoldBar;
  final ValueChanged<LaneClip> onTapClip;
  _TrackLane({
    required this.track,
    required this.song,
    required this.project,
    required this.bars,
    required this.barW,
    required this.height,
    required this.onTapBar,
    required this.onHoldBar,
    required this.onTapClip,
  });

  /// 절대 마디 → (구간, 구간 안 마디). 구간 밖이면 null.
  (int, int)? _at(int absBar) {
    for (var i = 0; i < bars.length; i++) {
      if (absBar >= bars[i].$1 && absBar < bars[i].$1 + bars[i].$2) {
        return (i, absBar - bars[i].$1);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final totalBars = bars.isEmpty ? 0 : bars.last.$1 + bars.last.$2;
    final color = _typeColor[track.type] ?? Colors.grey;
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          // 줄 전체에 손잡이 **하나**. 칸마다 위젯을 두면 긴 곡에서 밀린다.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // 꾹 누르기를 같이 달면 **탭이 300ms 늦어진다**(Flutter 가 두 번째
              // 손짓을 기다린다) — 눌린 자리는 `onTapDown` 이 적어 두고,
              // 무엇을 할지는 `onTap`/`onLongPress` 가 정한다.
              onTapDown: (d) =>
                  _down.value = (d.localPosition.dx / barW).floor(),
              onTap: () {
                final at = _at(_down.value);
                if (at != null) onTapBar(at.$1, at.$2);
              },
              onLongPress: () {
                final at = _at(_down.value);
                if (at != null) onHoldBar(at.$1, at.$2);
              },
              child: CustomPaint(
                painter: _GridPainter(totalBars, barW, {
                  for (final x in bars) x.$1,
                }),
              ),
            ),
          ),
          for (final c in song.lanes)
            if (c.trackId == track.id &&
                c.section >= 0 &&
                c.section < bars.length)
              // **구간 밖으로 안 삐져나가게 자른다.** 판 수를 줄이면 클립이
              // 구간보다 길어지는데, 그대로 그리면 **다음 구간 위에** 그려진다 —
              // 소리는 안 나는데 화면에는 있으니 그것만큼 헷갈리는 게 없다.
              // 아예 밖으로 나간 것은 흐리게 남긴다(지우는 건 사용자 몫이다).
              Builder(
                builder: (_) {
                  final secBars = bars[c.section].$2;
                  final clipBars = project
                      .barsOf(track.type, c.pattern)
                      .clamp(1, 64);
                  final outside = c.bar >= secBars;
                  final drawBars = outside
                      ? 1
                      : (c.bar + clipBars > secBars
                            ? secBars - c.bar
                            : clipBars);
                  final atBar = outside ? secBars - 1 : c.bar;
                  return Positioned(
                    left: (bars[c.section].$1 + atBar) * barW + 1,
                    top: 3,
                    width: (drawBars * barW - 3).toDouble(),
                    height: height - 6,
                    child: Opacity(
                      opacity: outside ? 0.35 : 1,
                      child: GestureDetector(
                        onTap: () => onTapClip(c),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          alignment: Alignment.centerLeft,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: color),
                          ),
                          child: Text(
                            // **고를 때 본 이름 그대로** 적는다. 서랍은
                            // 「발라드 코러스」라 해 놓고 줄에는 `Ballad Chorus`
                            // 가 뜨면 같은 것인 줄 모른다(폰에서 보고 잡았다).
                            outside ? '판 밖' : patternLabel(c.pattern),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
        ],
      ),
    );
  }
}

/// 곡 전체를 한 줄로 — 구간이 길이 비율대로 늘어서고, 지나온 만큼 밝아진다.
class _Ruler extends StatelessWidget {
  final List<(double, double)> spans;
  final double total, pos;
  final bool looping;

  /// **지금 흐르는 구간의 캐릭터**를 시계 옆에 세운다.
  ///
  /// 구간 줄마다 춤추게 하면 구간 수만큼 시계가 돌고, 무엇보다 「지금 어디를
  /// 지나는지」가 오히려 안 보인다. 여기는 이미 매 프레임 다시 그려지는 자리라
  /// 시계를 하나도 더 안 만든다.
  final List<Scene> scenes;
  final List<Section> sections;
  final double bpm;
  const _Ruler({
    required this.spans,
    required this.total,
    required this.pos,
    required this.looping,
    required this.scenes,
    required this.sections,
    required this.bpm,
  });

  (String, double)? _nowCritter(double now) =>
      looping ? critterAt(scenes, sections, spans, now, bpm) : null;

  @override
  Widget build(BuildContext context) {
    if (total <= 0) return const SizedBox(height: 30);
    final now = pos * total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Text(
              looping ? _mmss(now) : '멈춤',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: looping ? Colors.indigo.shade200 : Colors.white24,
              ),
            ),
          ),
          if (_nowCritter(now) case (final v, final beat))
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: CritterIcon(value: v, size: 24, beat: beat),
            ),
          for (var i = 0; i < spans.length; i++)
            Expanded(
              flex: (spans[i].$2 * 100).round().clamp(1, 1 << 20),
              child: Container(
                height: 20,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(4),
                ),
                child:
                    !looping ||
                        now < spans[i].$1 ||
                        now >= spans[i].$1 + spans[i].$2 ||
                        spans[i].$2 <= 0
                    ? null
                    : FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: ((now - spans[i].$1) / spans[i].$2).clamp(
                          0.0,
                          1.0,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade300,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  final int index;
  final Section section;
  final List<Scene> scenes;
  final double seconds;
  final Arrangement song;
  final Project project;

  /// 미리보기에 그릴 가락 — (음 목록, 판 칸 수). 없으면 null.
  final (List<List<Object?>>, int)? roll;
  final VoidCallback onChanged;

  /// 이 구간부터 듣기 — 번호 칸을 누르면 여기부터 흐른다.
  final VoidCallback onPlayFrom;

  const _SectionRow({
    super.key,
    required this.index,
    required this.section,
    required this.scenes,
    required this.seconds,
    required this.song,
    required this.project,
    required this.roll,
    required this.onChanged,
    required this.onPlayFrom,
  });

  @override
  Widget build(BuildContext context) {
    final ok = section.scene >= 0 && section.scene < scenes.length;
    final c = _sceneColor(section.scene);
    return GestureDetector(
      // **길게 누르면 나머지 손잡이.** 320dp 폰에서는 줄에 아이콘을 하나만 더 놓아도
      // 63px 이 넘친다(글자를 키우면 더). 자주 쓰는 것만 줄에 두고 나머지는 여기로.
      // (타임라인 쪽에는 자리가 넓어서 버튼으로 그대로 있다)
      onLongPress: () => _sectionMenu(context),
      child: Container(
        // 글자를 키운 폰에서는 칸도 같이 커진다 — 안 그러면 두 줄이 58 을 넘는다.
        height: scaled(context, 58),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: c.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 5,
              height: scaled(context, 56),
              color: c.withValues(alpha: 0.9),
            ),
            // 번호 칸이 곧 **여기부터 재생**이다 — 3분짜리 곡의 뒷부분을 고칠 때
            // 처음부터 다 듣지 않아도 된다. (버튼을 따로 더하면 줄이 넘친다)
            SizedBox(
              width: 34,
              child: InkWell(
                onTap: onPlayFrom,
                borderRadius: BorderRadius.circular(6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.play_arrow,
                      size: 15,
                      color: Colors.white38,
                    ),
                    Text(
                      '${index + 1}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white24,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 캐릭터는 **이름 줄 안에** 넣는다. 줄에 칸을 하나 더 만들면
                  // 320dp 폰에서 아래 띠 줄이 9px 넘쳤다 — 여기 넣으면 자리가
                  // 모자랄 때 이름과 같이 줄어들 뿐 넘치지 않는다.
                  Text.rich(
                    TextSpan(
                      children: [
                        if (ok &&
                            (scenes[section.scene].critter ?? '').isNotEmpty)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: CritterIcon(
                                value: scenes[section.scene].critter!,
                                size: 22,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        TextSpan(
                          text: ok ? scenes[section.scene].name : '(없는 씬)',
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Row(
                    children: [
                      // 무엇이 들어 있는지 — 이름이 다 「벌스」여도 여기서 갈린다
                      _TypeStrip(
                        types: sectionTypes(
                          project,
                          section.scene,
                          section: index,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '${_mmss(seconds)} · ${ok ? '${scenes[section.scene].bpm?.round() ?? '-'}BPM' : ''}',
                          // 좁은 폰에서는 이 한 줄이 두 줄로 접혀 칸을 넘겼다.
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10.5,
                            color: Colors.white38,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 판 수 — 숫자를 누르면 자주 쓰는 값(1·2·4·8)이 바로 나온다.
            // −/+ 만 있으면 8판으로 늘리는 데 일곱 번 눌러야 한다.
            _Step(
              label: '${section.reps}판',
              onMinus: section.reps > 1
                  ? () {
                      song.setReps(index, section.reps - 1);
                      onChanged();
                    }
                  : null,
              onPlus: () {
                song.setReps(index, section.reps + 1);
                onChanged();
              },
              onPick: (v) {
                song.setReps(index, v);
                onChanged();
              },
            ),
            // 순서 바꾸기 — 잡고 끈다
            ReorderableDragStartListener(
              index: index,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(
                  Icons.drag_indicator,
                  size: 20,
                  color: Colors.white38,
                ),
              ),
            ),
            IconButton(
              onPressed: () {
                song.removeAt(index);
                onChanged();
              },
              iconSize: 18,
              color: Colors.white24,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }

  /// 줄을 길게 눌렀을 때 — 줄에 안 들어가는 것들.
  void _sectionMenu(BuildContext context) {
    final name = section.scene >= 0 && section.scene < scenes.length
        ? scenes[section.scene].name
        : '(없는 씬)';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF16181C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 6),
              child: Row(
                children: [
                  Container(
                    width: 5,
                    height: 20,
                    color: _sceneColor(section.scene),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${index + 1}. $name',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: const Text('여기부터 재생'),
              onTap: () {
                Navigator.pop(ctx);
                onPlayFrom();
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_copy),
              title: const Text('바로 뒤에 한 벌 더'),
              subtitle: const Text(
                '맨 뒤에 붙였다가 끌어 올릴 필요가 없다',
                style: TextStyle(fontSize: 11.5),
              ),
              onTap: () {
                Navigator.pop(ctx);
                song.duplicateAt(index);
                onChanged();
              },
            ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('이 구간 지우기'),
              onTap: () {
                Navigator.pop(ctx);
                song.removeAt(index);
                onChanged();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final String label;
  final VoidCallback? onMinus, onPlus;
  final ValueChanged<int>? onPick;
  const _Step({required this.label, this.onMinus, this.onPlus, this.onPick});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SmallBtn(icon: Icons.remove, onTap: onMinus),
        SizedBox(
          width: 38,
          // **누를 것은 손가락만 해야 한다.** 이 글자는 눌러서 1·2·4·8 을 고르는
          // 자리인데 높이가 **19dp**였다(3mm 남짓). 줄 자체가 58 높이라
          // 세로로 넓히는 건 공짜다 — 보이는 것은 그대로고 눌리는 데만 커진다.
          height: 40,
          child: onPick == null
              ? Center(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : PopupMenuButton<int>(
                  tooltip: '판 수',
                  padding: EdgeInsets.zero,
                  color: const Color(0xFF20242B),
                  onSelected: onPick,
                  itemBuilder: (context) => [
                    for (final v in [1, 2, 4, 8, 16])
                      PopupMenuItem(
                        value: v,
                        height: 38,
                        child: Text(
                          '$v판',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      decoration: TextDecoration.underline,
                      decorationColor: Colors.white24,
                    ),
                  ),
                ),
        ),
        _SmallBtn(icon: Icons.add, onTap: onPlus),
      ],
    );
  }
}

class _SmallBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _SmallBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    // 보이는 네모는 30×30 그대로 두고 **눌리는 자리만** 38×44 로 넓힌다.
    // 네모를 키우면 줄이 복잡해 보이는데, 여백은 어차피 비어 있다.
    // (`opaque` 가 없으면 여백은 안 눌린다 — 자식이 없는 자리라서.)
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onTap == null ? Colors.white10 : Colors.white24,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 16,
            color: onTap == null ? Colors.white24 : Colors.white70,
          ),
        ),
      ),
    );
  }
}

class _AddSection extends StatelessWidget {
  final List<Scene> scenes;
  final ValueChanged<int> onAdd;
  /// 가로로 누워 높이가 귀할 때 — 칩 줄을 인라인으로 안 두고 눌러야만 뜨는
  /// 시트로 뺀다(지시 없이도 계속 화면 아래를 차지하던 92px+를 되찾는다).
  final bool compact;
  const _AddSection({
    required this.scenes,
    required this.onAdd,
    this.compact = false,
  });

  Widget _chips(BuildContext context) => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: [
      for (var i = 0; i < scenes.length; i++)
        GestureDetector(
          onTap: () => onAdd(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            // 긴 이름 하나가 한 줄을 통째로 먹지 않게 — 잘려도 색과
            // 자리로 어느 씬인지 안다.
            constraints: const BoxConstraints(maxWidth: 150),
            decoration: BoxDecoration(
              color: _sceneColor(i).withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _sceneColor(i).withValues(alpha: 0.6)),
            ),
            child: Text(
              scenes[i].name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return GestureDetector(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          backgroundColor: const Color(0xFF1a1a1a),
          builder: (sheetContext) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '＋구간 붙이기',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  _chips(sheetContext),
                ],
              ),
            ),
          ),
        ),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: Colors.white24),
          ),
          child: const Row(
            children: [
              Text(
                '＋구간 붙이기',
                style: TextStyle(fontSize: 12.5, color: Colors.white70),
              ),
              Spacer(),
              Icon(Icons.chevron_right, size: 18, color: Colors.white38),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '＋구간 붙이기',
            style: TextStyle(fontSize: 12.5, color: Colors.white70),
          ),
          const SizedBox(height: 8),
          // 이 줄은 **화면 아래에 못 박혀 있다.** 그런데 씬이 많거나 이름이 길면
          // `Wrap` 이 끝없이 높아져서 위쪽 구간 목록을 밀어내고 화면을 넘겼다
          // (긴 이름으로 재 보고 잡았다 — 가로에서 13px). 두어 줄에서 멈추고
          // 그 안에서 굴린다.
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: scaled(context, 92)),
            child: SingleChildScrollView(child: _chips(context)),
          ),
        ],
      ),
    );
  }
}

/// 곡 길이 맞추기 줄 — 「짧게 · 보통 · 길게」.
///
/// 구간을 손으로 하나씩 더하고 빼서 3분을 맞추는 것은 **셈이지 음악이 아니다.**
/// 목표를 고르면 가운데 대목의 판 수로 맞춘다(없던 대목을 지어내지는 않는다 —
/// 그러면 사용자가 만든 곡이 아니게 된다).
class _LengthBar extends StatelessWidget {
  final double total;
  final ValueChanged<double> onFit;
  const _LengthBar({required this.total, required this.onFit});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        children: [
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Center(
              child: Text(
                '길이',
                style: TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ),
          ),
          for (final e in kSongTargets.entries)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => onFit(e.value),
                child: Container(
                  height: 34, // 손가락 바닥선
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    // 지금 길이에 제일 가까운 것을 켜 둔다 — 「지금 어디쯤인가」가 보인다
                    color: _nearest(total) == e.key
                        ? Colors.deepPurple.shade400
                        : Colors.white10,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text(
                    '${e.key} ${_mmss(e.value)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _nearest(total) == e.key
                          ? Colors.white
                          : Colors.white54,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 지금 길이에 제일 가까운 목표. 곡이 비어 있으면(0초) 아무것도 안 켠다.
  static String? _nearest(double sec) {
    if (sec <= 0) return null;
    String? best;
    var gap = double.infinity;
    kSongTargets.forEach((k, v) {
      final d = (sec - v).abs();
      if (d < gap) {
        gap = d;
        best = k;
      }
    });
    return best;
  }
}
