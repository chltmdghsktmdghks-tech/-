// 첫 화면 — **프로젝트 고르기** (2026-09, 로직 프로 「프로젝트 초이저」 참고).
//
// 예전엔 "지금 곡" 카드 하나 + 네 가지 할 일(만들기·곡·라이브·쇼) 버튼이었다.
// 그런데 그 넷은 **같은 프로젝트를 보는 네 가지 방식**이지, 서로 다른 목적지가
// 아니다 — 그래서 이제 첫 화면은 "어느 프로젝트를 열까"만 묻고, 연 다음에는
// `ProjectWorkspace` 안에서 네 모드를 탭으로 오간다(뒤로가기 없이).
//
// 짜임은 왼쪽 필터(최근 항목·스타일별) + 오른쪽 카드 그리드 — 좁은 화면에서는
// 필터가 위쪽 가로 줄로 접힌다.
import 'package:flutter/material.dart';

import '../audio_isolate.dart';
import '../genres.dart' show genreDef, kGenres;
import '../presets.dart';
import '../project.dart';
import '../store.dart';
import '../ask_song.dart';
import 'ask_sheet.dart';
import 'doodle_play_view.dart';
import 'settings_sheet.dart';
import 'workspace_view.dart';

String _mmss(double sec) {
  final t = sec.round();
  return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
}

/// 프로젝트 카드에 쓸 고정 악센트 — 장르 문자열을 해시해 팔레트에서 고른다
/// (장르가 늘어도 표를 안 고쳐도 된다).
const List<Color> _kCardPalette = [
  Color(0xFF0A84FF),
  Color(0xFF64D2FF),
  Color(0xFFFF9F0A),
  Color(0xFFBF5AF2),
  Color(0xFF30D158),
  Color(0xFFFF375F),
];
Color _accentOf(String key) =>
    _kCardPalette[key.hashCode.abs() % _kCardPalette.length];

/// 장르 이름 — 빈 캔버스(`meta.genre`/`project.genre` 가 빈 문자열)는
/// `genreDef` 의 "모르는 키는 첫 장르로" 가 그대로 보이면 안 된다
/// (실기기 첫 실행에서 "빈 프로젝트"가 "로파이"로 찍혀 보이던 걸 잡았다).
String _genreLabel(String key) => key.isEmpty ? '빈 프로젝트' : genreDef(key).label;

/// 지금 소리 내는 트랙 수 — 카드 캡션에 "3트랙"처럼 붙인다(사용자 요청,
/// 2026-09-15: "프로젝트 미리보기도 더 디테일하게").
int _trackCountOf(SongMeta meta) =>
    meta.sceneActive?.where((v) => v).length ?? 0;

class HomeView extends StatefulWidget {
  final Project project;
  final Transport transport;
  final LiveChannel live;
  final MasterChannel master;
  final AudioClient? host;
  final Store? store;
  final bool ready;

  /// 소리 장치를 못 열었으면 그 까닭. **동그라미만 도는 것보다 낫다** —
  /// 화면은 멀쩡한데 ▶ 만 안 되면 사용자는 무엇이 문제인지 알 길이 없다.
  final String? audioError;
  final VoidCallback onOpenLab;

  /// 곡을 열고 나서 할 일(재생 정지·버스 다시 잡기) — 첫 화면은 오디오를 직접 안 만진다.
  final VoidCallback onSongOpened;

  const HomeView({
    super.key,
    required this.project,
    required this.transport,
    required this.live,
    required this.master,
    required this.host,
    required this.store,
    required this.ready,
    this.audioError,
    required this.onOpenLab,
    required this.onSongOpened,
  });

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  Project get project => widget.project;
  Transport get transport => widget.transport;
  LiveChannel get live => widget.live;
  MasterChannel get master => widget.master;
  AudioClient? get host => widget.host;
  Store? get store => widget.store;

  /// **간단히 보기인가** (Phase 2). 저장소가 아직 안 읽혔으면 전부 보인다 —
  /// 잠깐 보였다 사라지는 것보다 잠깐 늦게 감추는 쪽이 덜 어지럽다.
  bool get simple => store?.simpleMode ?? false;

  /// 프로 모드(설정) — 편집기가 반음 줄 손잡이를 열지 정한다.
  bool get pro => store?.pro ?? false;

  /// 「샘플곡」 서랍을 접어 뒀는가 — 사용자 요청(2026-09-13)으로 접을 수
  /// 있게 됐다. 기본은 펼침.
  bool get _samplesCollapsed => store?.samplesCollapsed ?? false;
  bool get ready => widget.ready;
  VoidCallback get onOpenLab => widget.onOpenLab;
  VoidCallback get onSongOpened => widget.onSongOpened;

  /// 첫 실행 안내를 이번 실행에서 이미 띄웠는가(같은 화면이 다시 그려져도 두 번 안 뜬다).
  bool _guideShown = false;

  /// null = 전체. 아니면 그 장르만.
  String? _filterGenre;

  @override
  void initState() {
    super.initState();
    // 화면이 다 그려진 **뒤에** 띄운다 — `initState` 에서 바로 열면
    // 아직 Navigator 가 준비되지 않았다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeGuide());
  }

  @override
  void didUpdateWidget(covariant HomeView old) {
    super.didUpdateWidget(old);
    // 저장소는 앱이 켜진 뒤에 읽힌다 — 그때 `guideSeen` 을 알게 된다.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeGuide());
  }

  /// 첫 실행 — **아무것도 저절로 안 띄운다** (사용자 결정, 2026-09).
  Future<void> _maybeGuide() async {
    final s = store;
    if (!mounted || _guideShown || s == null || s.guideSeen) return;
    _guideShown = true;
    // ignore: unawaited_futures
    s.markGuideSeen();
  }

  /// 프로젝트(씬 모드로) 작업 화면을 연다. **뒤로가기로 여기로 돌아온다.**
  void _openWorkspace(BuildContext context, {String initialMode = 'scene'}) {
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => ProjectWorkspace(
              project: project,
              transport: transport,
              live: live,
              master: master,
              host: host,
              store: store,
              simple: simple,
              pro: pro,
              initialMode: initialMode,
            ),
          ),
        )
        .then((_) => onSongOpened());
  }

  Future<void> _openSong(String id) async {
    await store?.open(id);
    if (!mounted) return;
    _openWorkspace(context);
  }

  /// 새 프로젝트를 만들기 **전에** 이름을 지어 볼지 묻는다(사용자 요청,
  /// 2026-09-13) — 여태는 전부 "새 곡 N"으로 남아서 목록이 다 똑같아
  /// 보였다. 다만 억지로 시키진 않는다 — 「나중에 짓기」를 누르면 여태처럼
  /// 자동 이름으로 바로 만든다. 대화상자를 닫아 버리면(바깥 탭·뒤로가기)
  /// 아예 만들지 않는다 — 아직 "만들겠다"고도 안 한 참이라 취소가 맞다.
  Future<void> _newProject() async {
    final typed = await _askNewProjectName(context);
    if (typed == null) return;
    await store?.newSong(name: typed.trim().isEmpty ? null : typed.trim());
    if (!mounted) return;
    _openWorkspace(context);
  }

  Future<String?> _askNewProjectName(BuildContext context) async {
    final ctl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1E),
        title: const Text(
          '새 프로젝트 이름을 지어 볼까요?',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(hintText: '예: 여름밤 로파이'),
          onSubmitted: (s) => Navigator.pop(ctx, s),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Text('나중에 짓기'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  /// **질문에 답해서 곡 만들기** — 옛 앱 첫 화면의 머리 항목.
  ///
  /// 음악 용어를 하나도 안 쓰고 열 가지만 묻는다. 0에서 만들지 않고 **검증된
  /// 완성곡을 뼈대로 삼아 변형**하므로 이상한 결과가 안 나온다(`ask_song.dart`).
  Future<void> _askSong() async {
    await showAskSheet(
      context,
      onDone: (ans) async {
        final r = askRecipe(ans, pick: DateTime.now().second);
        applyAsk(project, transport, ans, r);
        // 새 곡으로 남긴다 — 답해서 만든 것이 지금 곡을 덮으면 그게 제일 나쁘다.
        await store?.saveNow();
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
              content: Text(
                '만들었습니다 — ${askSummary(ans, r)}',
                style: const TextStyle(fontSize: 12.5),
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 5),
            ),
          );
        _openWorkspace(context);
      },
    );
  }

  /// **두드려서 만들기(Doodle Play)** — 사용자 지시서, 2026-09-17.
  ///
  /// "질문에 답해서 곡 만들기"와 달리 완성곡을 통째로 얹지 않는다. 장르만
  /// 고르면(BPM·드럼킷·박자를 정한다) 새 빈 프로젝트를 만들고, 드럼은
  /// 비워 둔 채로 `DoodlePlayView`를 연다 — 거기서 킥·스네어·하이햇을
  /// 사용자가 직접 쳐서 쌓는다.
  Future<void> _doodlePlay() async {
    final genre = await _pickGenreForDoodle();
    if (genre == null || !mounted) return;
    await store?.newSong();
    project.setGenre(genre);
    // `setGenre` 는 `Project` 안의 장르 이름만 바꾼다 — 실제 재생 빠르기·조는
    // `Transport`(딴 객체)에 있어서 따로 옮겨야 한다("질문에 답해서 곡
    // 만들기"의 `applyAsk`도 같은 이유로 이렇게 한다). 안 옮기면 이전 곡의
    // BPM이 그대로 남아 새 장르인데 엉뚱한 빠르기로 두드리게 된다.
    final g = genreDef(genre);
    transport
      ..bpm = g.bpm
      ..mode = g.mode;
    if (!mounted) return;
    await openDoodlePlay(context, project: project, transport: transport, host: host);
    if (!mounted) return;
    await store?.saveNow();
    if (!mounted) return;
    _openWorkspace(context);
  }

  Future<String?> _pickGenreForDoodle() {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Text(
                  '어떤 장르로 만들까요?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  '박자·드럼 소리를 정해요 — 다음 화면에서 킥부터 직접 쳐서 만들어요',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    for (final g in kGenres)
                      ListTile(
                        title: Text(
                          g.label,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          '${g.feel} · ${g.bpm.round()}BPM',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        onTap: () => Navigator.pop(ctx, g.key),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// **샘플곡은 뺀다** — 여긴 내가 만든 것들이다. 샘플곡은 아래 「샘플곡」
  /// 서랍(`_visibleSamples`)에 따로 있다.
  List<SongMeta> _visibleSongs() {
    final s = store;
    if (s == null) return const [];
    final list = [...s.songs.where((m) => !m.sample)]
      ..sort((a, b) => b.updated.compareTo(a.updated));
    if (_filterGenre == null) return list;
    return list.where((m) => m.genre == _filterGenre).toList();
  }

  /// 「샘플곡」 서랍에 보여 줄 것들 — 심어 둔 차례 그대로.
  List<SongMeta> _visibleSamples() {
    final s = store;
    if (s == null) return const [];
    return [
      for (final m in s.songs)
        if (m.sample) m,
    ];
  }

  List<String> _genresInUse() {
    final s = store;
    if (s == null) return const [];
    final set = <String>{};
    for (final m in s.songs) {
      if (m.sample) continue;
      set.add(m.genre);
    }
    final list = set.toList()
      ..sort((a, b) => _genreLabel(a).compareTo(_genreLabel(b)));
    return list;
  }

  /// 프로젝트 삭제 — **확인 창 대신 되돌리기**(이 앱의 삭제는 늘 이 규칙).
  /// 남은 내 프로젝트가 하나뿐이면 막는다(샘플곡은 안 센다 — 그건 늘 있다).
  Future<void> _deleteProject(SongMeta m) async {
    final s = store;
    if (s == null) return;
    final mine = s.songs.where((x) => !x.sample).length;
    final messenger = ScaffoldMessenger.of(context);
    if (mine <= 1) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          const SnackBar(
            content: Text('마지막 프로젝트는 지울 수 없습니다 — 새로 하나 만든 뒤 지우세요'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    final gone = await s.remove(m.id);
    if (!mounted || gone == null) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text('「${gone.meta.name}」 을 지웠습니다'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: '되돌리기',
          onPressed: () async {
            await s.undoRemove(gone);
            if (mounted) setState(() {});
          },
        ),
      ),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: Listenable.merge([project, transport, store]),
          builder: (context, _) {
            final wide = MediaQuery.of(context).size.width >= 720;
            return Column(
              children: [
                _TopBar(
                  ready: ready,
                  audioError: widget.audioError,
                  simple: simple,
                  onToggleSimple: store == null
                      ? null
                      : () => store!.setSimpleMode(!simple),
                  onSettings: store == null
                      ? null
                      : () => showSettingsSheet(context, store!, host),
                  onHelp: () => showFirstGuide(context),
                ),
                Expanded(
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _Sidebar(
                              genres: _genresInUse(),
                              current: _filterGenre,
                              onPick: (g) => setState(() => _filterGenre = g),
                            ),
                            Expanded(child: _mainArea(context, showFilterRow: false)),
                          ],
                        )
                      : _mainArea(context, showFilterRow: true),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _mainArea(BuildContext context, {required bool showFilterRow}) {
    final songs = _visibleSongs();
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      children: [
        _Start(
          icon: '🎼',
          title: '질문에 답해서 곡 만들기',
          desc: '기분·장면 열 가지만 고르면 · 음악 용어 없음',
          onTap: _askSong,
        ),
        const SizedBox(height: 10),
        _Start(
          icon: '👆',
          title: '두드려서 만들기',
          desc: '장르 고르고 킥·스네어·하이햇을 직접 쳐서 · 이론 몰라도 OK',
          onTap: _doodlePlay,
        ),
        const SizedBox(height: 16),
        if (showFilterRow) ...[
          _FilterRow(
            genres: _genresInUse(),
            current: _filterGenre,
            onPick: (g) => setState(() => _filterGenre = g),
          ),
          const SizedBox(height: 14),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              _filterGenre == null ? '최근 프로젝트' : _genreLabel(_filterGenre!),
              style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 8),
            // `store`가 아직 `null`(디스크에서 목록을 불러오는 중)일 때도
            // `_visibleSongs()`는 빈 목록을 돌려준다 — 여기서 "0개"를 그대로
            // 찍으면 실제로 저장된 곡이 있어도 잠깐 "다 사라졌나?"로 보인다
            // (실기기에서 몇 초 걸리는 걸 직접 봤다). 불러오는 중엔 개수 대신
            // 점 세 개로 구분한다.
            if (store == null)
              const Text(
                '불러오는 중…',
                style: TextStyle(fontSize: 11.5, color: Colors.white38),
              )
            else
              Text(
                '${songs.length}개',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Colors.white38,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 230,
            mainAxisExtent: 172,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: songs.length + 1,
          itemBuilder: (context, i) {
            if (i == songs.length) {
              return _NewProjectCard(onTap: _newProject);
            }
            final m = songs[i];
            final isCurrent = m.id == store?.currentId;
            return _ProjectCard(
              meta: m,
              current: isCurrent,
              previewMode: store?.previewMode ?? 'scene',
              onTap: () => _openSong(m.id),
              onDelete: () => _deleteProject(m),
            );
          },
        ),
        if (_visibleSamples().isNotEmpty) ...[
          const SizedBox(height: 22),
          // 접혀 있어도 **몇 개인지·펼치는 길**은 늘 보인다 — 서랍 자체를
          // 없앤 게 아니라 접어 둔 것뿐이라는 걸 알아야 한다.
          InkWell(
            onTap: () => store?.setSamplesCollapsed(!_samplesCollapsed),
            borderRadius: BorderRadius.circular(6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Icon(
                  _samplesCollapsed
                      ? Icons.chevron_right
                      : Icons.expand_more,
                  size: 18,
                  color: Colors.white54,
                ),
                const SizedBox(width: 2),
                const Text(
                  '샘플곡',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_visibleSamples().length}개',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Colors.white38,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
          if (!_samplesCollapsed) ...[
            const SizedBox(height: 4),
            const Text(
              '바로 열어서 만지고 배울 수 있는 완성곡입니다 — 내 프로젝트처럼 직접 고칠 수 있어요.',
              style: TextStyle(fontSize: 11.5, color: Colors.white38),
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 230,
                mainAxisExtent: 172,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: _visibleSamples().length,
              itemBuilder: (context, i) {
                final m = _visibleSamples()[i];
                return _ProjectCard(
                  meta: m,
                  current: m.id == store?.currentId,
                  previewMode: store?.previewMode ?? 'scene',
                  onTap: () => _openSong(m.id),
                );
              },
            ),
          ],
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(
              child: Text(
                // 「사용법」 버튼이 폭을 가져가므로 **한 줄에 들어가는 길이**로
                // 둔다. 두 줄이 되면 둘째 줄이 화면 밖으로 잘렸다(실기기 확인,
                // 2026-09-22 — "…오갈 수 있어" 다음 "요"가 안 보였다).
                '씬·타임라인·라이브·쇼를 오갈 수 있어요.',
                style: TextStyle(fontSize: 12, color: Colors.white38),
              ),
            ),
            TextButton.icon(
              onPressed: () => showFirstGuide(context),
              icon: const Icon(Icons.help_outline, size: 16),
              label: const Text(
                '사용법',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              style: TextButton.styleFrom(
                foregroundColor: Colors.tealAccent.shade200,
              ),
            ),
          ],
        ),
        // 화면 맨 아래에 붙으면 글자가 잘린다 — 여유를 둔다.
        const SizedBox(height: 24),
        if (!simple)
          Center(
            child: TextButton.icon(
              onPressed: onOpenLab,
              icon: const Icon(Icons.science_outlined, size: 16),
              label: const Text('엔진 시험 화면', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: Colors.white38),
            ),
          ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  final bool ready;
  final String? audioError;
  final bool simple;
  final VoidCallback? onToggleSimple;
  final VoidCallback? onSettings;
  final VoidCallback onHelp;
  const _TopBar({
    required this.ready,
    required this.audioError,
    required this.simple,
    required this.onToggleSimple,
    required this.onSettings,
    required this.onHelp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          const Flexible(
            child: Text(
              '음악 낙서장',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 8),
          if (!ready && audioError == null)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (audioError != null)
            Flexible(
              child: Text(
                '소리 장치를 못 열었습니다 — 앱을 다시 켜 보세요',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.red.shade300,
                ),
              ),
            ),
          const Spacer(),
          TextButton(
            onPressed: onToggleSimple,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white54,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              simple ? '더 보기' : '간단히',
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
            ),
          ),
          if (onSettings != null)
            IconButton(
              tooltip: '설정',
              onPressed: onSettings,
              icon: const Icon(Icons.settings_outlined),
            ),
          IconButton(
            tooltip: '사용법',
            onPressed: onHelp,
            icon: const Icon(Icons.help_outline),
          ),
        ],
      ),
    );
  }
}

/// 넓은 화면의 왼쪽 필터 — 로직 「프로젝트 초이저」의 사이드바.
class _Sidebar extends StatelessWidget {
  final List<String> genres;
  final String? current;
  final ValueChanged<String?> onPick;
  const _Sidebar({
    required this.genres,
    required this.current,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 176,
      margin: const EdgeInsets.fromLTRB(14, 14, 0, 14),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      // 장르가 늘면(지금 17개) 세로로 낮은 가로모드에서 이 목록 하나만으로도
      // 화면 높이를 넘겼다 — 스크롤이 없는 `Column`이라 그냥 잘려 나갔다
      // (디버그에서 "BOTTOM OVERFLOWED" 배너로 확인). 목록만 따로 스크롤되게.
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sideItem(context, '전체 프로젝트', current == null, () => onPick(null)),
            if (genres.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 6),
                child: Text(
                  '스타일',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .4,
                    color: Colors.white38,
                  ),
                ),
              ),
              for (final g in genres)
                _sideItem(
                  context,
                  _genreLabel(g),
                  current == g,
                  () => onPick(g),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sideItem(BuildContext context, String label, bool on, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1.5),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: on ? Colors.tealAccent.withValues(alpha: 0.16) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: on ? FontWeight.w700 : FontWeight.w500,
            color: on ? Colors.tealAccent.shade100 : Colors.white70,
          ),
        ),
      ),
    );
  }
}

/// 좁은 화면에서 사이드바 대신 — 가로로 흐르는 칩 줄.
class _FilterRow extends StatelessWidget {
  final List<String> genres;
  final String? current;
  final ValueChanged<String?> onPick;
  const _FilterRow({
    required this.genres,
    required this.current,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    if (genres.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(context, '전체', current == null, () => onPick(null)),
          for (final g in genres)
            _chip(context, _genreLabel(g), current == g, () => onPick(g)),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, bool on, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? Colors.tealAccent.shade400 : Colors.white10,
            borderRadius: BorderRadius.circular(17),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: on ? FontWeight.w800 : FontWeight.w600,
              color: on ? Colors.black : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

/// 프로젝트 카드 — 미리보기 그림 + 이름 + 스타일·BPM·길이.
class _ProjectCard extends StatelessWidget {
  final SongMeta meta;
  final bool current;

  /// 'scene' · 'timeline' · 'show' — 설정의 「카드 미리보기」 값.
  final String previewMode;
  final VoidCallback onTap;

  /// null 이면 지우기 단추 자체가 없다(샘플곡 카드 — 서랍은 늘 그대로 둔다).
  final VoidCallback? onDelete;
  const _ProjectCard({
    required this.meta,
    required this.current,
    required this.previewMode,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final accent = _accentOf(meta.genre);
    final g = songGenreOf(meta.genre);
    // Logic Pro 같은 DAW 의 프로젝트 서랍을 참고해 다시 짰다(사용자 요청,
    // 2026-09-13) — 미리보기가 카드의 **주인공**이 되고, 이름은 그 아래
    // 캡션으로 작게 붙는다. 예전엔 미리보기가 40px짜리 얇은 띠였고 이름이
    // 위로 붙어 정작 "이 곡에 뭐가 들었나"가 안 보였다.
    return Stack(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: current ? accent.withValues(alpha: 0.75) : Colors.white12,
                width: current ? 1.4 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(7, 7, 7, 0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: _CardPreview(
                        mode: previewMode,
                        meta: meta,
                        accent: accent,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 9),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        meta.name,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        // 빈 캔버스로 저장된 곡은 `meta.genre` 가 빈 문자열이다 —
                        // `songGenreOf` 의 "모르는 키는 첫 장르로"가 그대로 보이면
                        // 패턴이 하나도 없는데 "로파이"라고 찍히는 모순이 생긴다
                        // (실기기에서 첫 실행으로 직접 보고 잡은 것 — `home_view.dart`
                        // 다른 자리엔 이미 있던 처리인데 카드에는 빠져 있었다).
                        meta.genre.isEmpty
                            ? '빈 프로젝트'
                            : '${g.$2} · ${g.$3.round()}BPM'
                                  '${meta.sec > 0 ? ' · ${_mmss(meta.sec)}' : ''}'
                                  '${_trackCountOf(meta) > 0 ? ' · ${_trackCountOf(meta)}트랙' : ''}',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10.5, color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // 지우기 — **확인 창 없이 바로 지우고 되돌리기를 준다**(이 앱의
        // 삭제는 늘 이 규칙, `songs_view.dart` 와 같다).
        if (onDelete != null)
          Positioned(
            right: 4,
            top: 4,
            child: InkWell(
              onTap: onDelete,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.close,
                  size: 13,
                  color: Colors.white60,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 악기별 색 — 씬 화면의 악기 줄 색(드럼 초록·베이스 파랑·코드 보라·멜로디
/// 호박)과 맞춘다. `kPreviewTrackTypes` 의 차례와 같다.
const List<Color> _kInstColor = [
  Color(0xFF34C759), // 드럼
  Color(0xFF0A84FF), // 베이스
  Color(0xFFBF5AF2), // 코드
  Color(0xFFFF9F0A), // 멜로디
];

/// 악기 아이콘 — 색만으론 뭔지 외워야 해서(사용자 요청, 2026-09-15: "악기는
/// 아이콘으로 보여주자") 레인 왼쪽에 작게 붙인다. `kPreviewTrackTypes` 순서.
const List<IconData> _kInstIcon = [
  Icons.album, // 드럼
  Icons.graphic_eq, // 베이스
  Icons.piano, // 코드
  Icons.music_note, // 멜로디
];

/// **카드 미리보기** — 씬 구성·타임라인 구간·쇼 무대를 작은 색 블록으로 그린다.
/// 설정(`Store.previewMode`)이 셋 중 무엇을 그릴지 정한다. 곡 파일을 열지
/// 않고도 그릴 수 있게, 필요한 값은 전부 `SongMeta`(저장할 때 같이 적어 둔
/// `sceneActive`·`timelineScenes`)에서 온다 — 목록 화면이 느려지지 않는다.
class _CardPreview extends StatelessWidget {
  final String mode;
  final SongMeta meta;
  final Color accent;
  const _CardPreview({required this.mode, required this.meta, required this.accent});

  @override
  Widget build(BuildContext context) {
    // 어느 모드든 **어두운 무대** 위에 그린다 — 로직 프로 같은 DAW 의 프로젝트
    // 서랍 썸네일이 늘 짙은 배경 위에 트랙 색이 도드라지는 것과 같은 결.
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF101115), Color(0xFF17181D)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: switch (mode) {
        'timeline' => _timelinePreview(),
        'show' => _showPreview(),
        _ => _scenePreview(),
      },
    );
  }

  /// 씬 미리보기 — 악기 넷을 **트랙 레인**처럼 위아래로 쌓는다(Logic 의
  /// 프로젝트 썸네일 참고, 2026-09-13). 여태는 넷을 옆으로 나란히 세운
  /// 좁은 띠라 "악기가 몇 개 있나"는 보여도 "곡처럼" 안 보였다 — 진짜
  /// 타임라인처럼 한 줄에 한 악기, 켠 트랙은 안에 클립 블록 몇 개까지
  /// 그려서 얇은 색 띠가 아니라 작은 곡 화면처럼 읽히게 했다.
  Widget _scenePreview() {
    final active = meta.sceneActive;
    final patterns = meta.scenePatterns;
    return Column(
      children: [
        for (var i = 0; i < kPreviewTrackTypes.length; i++) ...[
          if (i > 0) const SizedBox(height: 3),
          Expanded(
            child: _laneRow(
              on: active != null && i < active.length && active[i],
              color: _kInstColor[i],
              icon: _kInstIcon[i],
              trackType: kPreviewTrackTypes[i],
              patternName: (patterns != null && i < patterns.length)
                  ? patterns[i]
                  : '',
            ),
          ),
        ],
      ],
    );
  }

  /// 트랙 레인 한 줄 — 꺼져 있으면 옅은 빈 띠, 켜져 있으면 왼쪽에 악기
  /// 아이콘 + 클립 블록 2~3개. 길게 누르면(웹은 마우스오버) 실제 패턴
  /// 이름을 툴팁으로 보여 준다.
  Widget _laneRow({
    required bool on,
    required Color color,
    required IconData icon,
    required String trackType,
    required String patternName,
  }) {
    final label = kTrackTypeLabel[trackType] ?? trackType;
    final msg = on
        ? (patternName.isEmpty ? label : '$label — $patternName')
        : '$label — 쉬는 중';
    final chip = Container(
      width: 15,
      height: 15,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: on ? color : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        icon,
        size: 9.5,
        color: on ? Colors.black.withValues(alpha: 0.72) : Colors.white24,
      ),
    );
    if (!on) {
      return Tooltip(
        message: msg,
        child: Row(
          children: [
            chip,
            const SizedBox(width: 4),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(3),
                  color: Colors.white.withValues(alpha: 0.04),
                ),
              ),
            ),
          ],
        ),
      );
    }
    // 클립 자리는 **실제 패턴 이름**을 시드로 흔든다 — 트랙 순서로만 정하면
    // 곡이 달라도 미리보기가 다 똑같이 생긴다(사용자 지적, 2026-09-15:
    // "프로젝트 미리보기도 더 디테일하게"). 이름이 다르면 조각도 달라진다.
    final segs = _segShapeOf(patternName.isEmpty ? trackType : patternName);
    return Tooltip(
      message: msg,
      child: Row(
        children: [
          chip,
          const SizedBox(width: 4),
          Expanded(
            child: Row(
              children: [
                for (var i = 0; i < segs.length; i++) ...[
                  if (i > 0) const SizedBox(width: 2),
                  Expanded(
                    flex: segs[i],
                    child: Container(
                      decoration: BoxDecoration(
                        color: color.withValues(
                          alpha: i.isEven ? 0.85 : 0.5,
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 문자열을 시드로 클립 조각을 2~4개로 나눈 flex 비율표를 만든다 —
  /// 같은 이름이면 늘 같은 모양(재현 가능), 다른 이름이면 다른 모양.
  static List<int> _segShapeOf(String seedText) {
    final h = seedText.hashCode.abs();
    final n = 2 + h % 3; // 2~4 조각
    return [for (var i = 0; i < n; i++) 2 + (h >> (i * 3)) % 7];
  }

  /// 타임라인 미리보기 — 구간 순서를 줄지은 색 막대로(인트로→벌스→코러스…).
  /// 구간마다 다른 자리에 다른 색을 줘서 「몇 마디짜리 곡인가」가 한눈에 온다.
  Widget _timelinePreview() {
    final scenes = meta.timelineScenes ?? const [];
    if (scenes.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white24),
        ),
      );
    }
    return Row(
      children: [
        for (var i = 0; i < scenes.length; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: _accentOf(scenes[i]).withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 쇼 미리보기 — 쇼 화면의 「무대 위 점 켜진 연주자」를 축소한 것. 씬
  /// 미리보기와 같은 값(켜진 악기)을 무대 배경 위 점들로 그린다(무대
  /// 배경 자체는 바깥 `build()` 의 어두운 바탕을 그대로 쓴다).
  Widget _showPreview() {
    final active = meta.sceneActive ?? const [false, false, false, false];
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < kPreviewTrackTypes.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: (i < active.length && active[i])
                    ? _kInstColor[i]
                    : Colors.white24,
                boxShadow: (i < active.length && active[i])
                    ? [BoxShadow(color: _kInstColor[i].withValues(alpha: 0.7), blurRadius: 5)]
                    : null,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NewProjectCard extends StatelessWidget {
  final VoidCallback onTap;
  const _NewProjectCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24, width: 1.4),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                border: Border.fromBorderSide(
                  BorderSide(color: Colors.white38, width: 1.4),
                ),
              ),
              child: const Icon(Icons.add, color: Colors.white54, size: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              '새 프로젝트',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════ 처음 켠 사람 안내 ══════════════════

/// 첫 실행에 한 번 뜨는 안내. 「사용법」 으로 언제든 다시 열 수 있다.
///
/// 왜 필요한가: 첫 화면에 프로젝트 카드가 있어도, **정작 소리를 내려면
/// 무엇을 눌러야 하는지**는 안 적혀 있다. 만들기에 들어가도 패턴이 '없음'
/// 이면 재생해도 조용하다 — 고장으로 보인다. 그래서 안내는 '이 화면은
/// 무엇이다'가 아니라 **'무엇을 누르면 소리가 난다'**를 적는다.
void showFirstGuide(BuildContext context, {VoidCallback? onDone}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF16181C),
    isScrollControlled: true, // 가로로 눕히면 안 그러면 잘린다
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.88,
        ),
        // **「시작하기」는 늘 바닥에 붙어 있는다.**
        // 여태는 설명과 함께 굴러가서, 줄을 한 줄 더 적으면 버튼이 화면 밖으로
        // 밀렸다(시험이 잡았다 — 글자를 키운 폰에서는 더 빨리 밀린다).
        // 안내는 앞으로도 길어질 텐데, **누를 것이 안 보이면 안내가 아니다.**
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '음악 낙서장 쓰는 법',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '악보를 몰라도 됩니다. 순서대로 눌러 보세요.',
                      style: TextStyle(fontSize: 13, color: Colors.white54),
                    ),
                    const SizedBox(height: 18),
                    _Step(
                      n: 1,
                      color: Colors.indigo.shade400,
                      title: '프로젝트 고르기',
                      body:
                          '첫 화면에서 "새 프로젝트"를 누르거나 만들던 것을 고릅니다.\n'
                          '고르면 씬·타임라인·라이브·쇼 네 모드를 위쪽 탭으로 오갈 수 있는 화면이 열려요.',
                    ),
                    _Step(
                      n: 2,
                      color: Colors.deepPurple.shade300,
                      title: '씬 — 한 판 만들기',
                      body:
                          '처음엔 아무 소리도 안 납니다 — 정상입니다.\n'
                          '화면 위 「스타일 고르기」를 누르면 장르에 맞는 판이 한 번에 채워져요.\n'
                          '직접 하나씩 만들려면 악기 줄마다 「패턴」을 눌러 고릅니다.\n'
                          '고르는 순간 그 악기가 들어와요. ▶ 재생을 누르면 멈출 때까지 반복합니다.\n'
                          '「느낌」을 만지면 같은 판이 차분해지거나 신나집니다.\n'
                          '씬 이름 옆 ⋮ → 「코드 진행」에서 코드를 바꾸면 베이스·멜로디도 같이 옮겨져요.',
                    ),
                    _Step(
                      n: 3,
                      color: Colors.pink.shade300,
                      title: '타임라인 — 곡으로 잇기 · 라이브',
                      body:
                          '만든 판을 인트로·벌스·코러스로 늘어놓으면 한 곡이 됩니다.\n'
                          '악기마다 줄이 있어요 — 빈 칸을 누르면 거기만 바뀝니다. 「내보내기」로 소리 파일이 나와요.\n'
                          '라이브 탭은 반주 위에 손으로 얹어 치는 곳 — 틀린 음이 안 나옵니다.',
                    ),
                    _Step(
                      n: 4,
                      color: Colors.amber.shade600,
                      title: '쇼 — 보여 주기',
                      body: '밴드가 연주하는 화면입니다. 남에게 들려줄 때 켜 두세요.',
                      last: true,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.30)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lightbulb_outline, size: 18, color: Colors.amber.shade200),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '만든 것은 저절로 저장돼요 — 첫 화면 카드에서 다시 엽니다.\n'
                              '소리가 안 나면 — 패턴이 전부 「없음」이라 그렇습니다. 「스타일 고르기」로 채우거나 하나씩 골라 보세요.',
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.35,
                                color: Colors.amber.shade100,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onDone?.call();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.teal.shade600,
                    // 안 잡으면 테마 기본색(보라)이라 청록 바탕에서 안 읽힌다
                    // (폰에서 확인 — 다른 화면에서 이미 한 번 겪은 실수다)
                    foregroundColor: Colors.white,
                  ),
                  child: const Text(
                    '시작하기',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ).then((_) => onDone?.call()); // 밖을 눌러 닫아도 본 것으로 친다
}

/// 첫 화면의 **시작하기 한 줄** — 그림글자 · 제목 · 설명.
class _Start extends StatelessWidget {
  final String icon, title, desc;
  final VoidCallback onTap;
  const _Start({
    required this.icon,
    required this.title,
    required this.desc,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.teal.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.teal.withValues(alpha: 0.45)),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 17)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800),
                  ),
                  Text(
                    desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: Colors.white38),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 17, color: Colors.white30),
          ],
        ),
      ),
    );
  }
}

/// 안내 한 단계 — 번호 · 제목 · 두어 줄.
class _Step extends StatelessWidget {
  final int n;
  final Color color;
  final String title, body;
  final bool last;
  const _Step({
    required this.n,
    required this.color,
    required this.title,
    required this.body,
    this.last = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 12 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Text(
              '$n',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(fontSize: 12.5, height: 1.45, color: Colors.white60),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
