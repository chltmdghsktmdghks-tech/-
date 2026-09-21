// 프로젝트 작업 화면 — **씬·타임라인·라이브·쇼를 탭으로 오간다** (2026-09).
//
// 예전엔 이 넷이 첫 화면에서 각각 따로 push 되는 화면이었다 — 라이브 치다가
// 씬으로 돌아가려면 뒤로 → 첫 화면 → 만들기, 세 걸음이었다. 그런데 이 넷은
// **같은 프로젝트를 보는 네 가지 방식**이라, 로직·큐베이스 같은 DAW 는 이걸
// 다 한 창 안의 탭(또는 창 전환)으로 둔다. 여기서도 그렇게 바꿨다: 뒤로가기
// 없이 탭만 누르면 넘어간다. 「뒤로」는 프로젝트 자체를 나가 첫 화면으로.
import 'package:flutter/material.dart';

import '../audio_isolate.dart';
import '../project.dart';
import '../sequencer.dart';
import '../store.dart';
import 'home_view.dart' show showFirstGuide;
import 'live_view.dart';
import 'mixer_view.dart';
import 'project_settings_sheet.dart';
import 'scene_view.dart';
import 'show_view.dart';
import 'song_view.dart';

const _kModes = ['scene', 'timeline', 'live', 'show'];
const _kModeLabel = {
  'scene': '씬',
  'timeline': '타임라인',
  'live': '라이브',
  'show': '쇼',
};
const _kModeIcon = {
  'scene': Icons.grid_view,
  'timeline': Icons.view_timeline,
  'live': Icons.piano,
  'show': Icons.auto_awesome,
};

class ProjectWorkspace extends StatefulWidget {
  final Project project;
  final Transport transport;
  final LiveChannel live;
  final MasterChannel master;
  final AudioClient? host;
  final Store? store;
  final bool simple;
  final bool pro;
  final String initialMode;

  const ProjectWorkspace({
    super.key,
    required this.project,
    required this.transport,
    required this.live,
    required this.master,
    required this.host,
    required this.store,
    required this.simple,
    required this.pro,
    this.initialMode = 'scene',
  });

  @override
  State<ProjectWorkspace> createState() => _ProjectWorkspaceState();
}

class _ProjectWorkspaceState extends State<ProjectWorkspace> {
  late String _mode = widget.initialMode;

  /// `SongView` 의 안(구간 목록 ↔ 타임라인) 보기 — 저장소에 남기는 값과
  /// 별개다(그건 "list"/"timeline", 이건 이 화면의 네 모드 중 하나).
  String? _songViewMode;

  Project get project => widget.project;
  Transport get transport => widget.transport;
  AudioClient? get host => widget.host;
  Store? get store => widget.store;

  void _setMode(String m) {
    if (m == _mode) return;
    setState(() => _mode = m);
  }

  /// 타임라인에서 "이 씬 고치기" — **화면을 나가지 않고 탭만 바꾼다.**
  void _editScene(int i) {
    project.launchScene(i);
    _setMode('scene');
  }

  void _openMixer(BuildContext context) {
    if (host == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('믹서')),
          body: SafeArea(
            top: false,
            child: MixerView(
              project: project,
              live: widget.live,
              master: widget.master,
              host: host,
            ),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_mode) {
      case 'scene':
        return SceneView(
          project: project,
          transport: transport,
          host: host,
          simple: widget.simple,
          pro: widget.pro,
        );
      case 'timeline':
        return SongView(
          project: project,
          transport: transport,
          host: host,
          master: widget.master,
          mode: _songViewMode ?? store?.songMode ?? 'list',
          onMode: (m) {
            setState(() => _songViewMode = m);
            store?.setSongMode(m);
          },
          onEditScene: _editScene,
        );
      case 'live':
        return LiveView(
          project: project,
          transport: transport,
          live: widget.live,
          host: host,
          beginner: store?.beginner ?? true,
        );
      case 'show':
        return ShowView(project: project, transport: transport, host: host);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 쇼 모드는 **검게, 꽉 차게** 보여 준다(발표용 — 옛 「바로」 화면과 같은
    // 뜻). 그래도 탭 줄은 남긴다 — 안 그러면 여기서 빠져나갈 길이 뒤로가기
    // 뿐이라, 라이브로 넘어가려다 프로젝트를 통째로 나가게 된다.
    final isShow = _mode == 'show';
    return Scaffold(
      backgroundColor: isShow ? Colors.black : null,
      body: SafeArea(
        child: Column(
          children: [
            _ModeBar(
              project: project,
              mode: _mode,
              onPick: _setMode,
              onHelp: () => showFirstGuide(context),
              onMixer: host == null ? null : () => _openMixer(context),
              onSettings: () => showProjectSettingsSheet(
                context,
                project: project,
                transport: transport,
                master: widget.master,
                onChanged: () {
                  final h = host;
                  if (h == null || !transport.playing) return;
                  if (transport.songLoop) {
                    // 곡 재생 중이면 refreshLoop 로는 몇 분 뒤에나 반영된다
                    // — 바뀐 설정을 바로 들으려고 곡을 처음부터 다시 건다.
                    SceneSequencer.playSong(project, transport, h, loop: true);
                  } else {
                    SceneSequencer.refreshLoop(project, transport, h);
                  }
                },
              ),
            ),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }
}

class _ModeBar extends StatelessWidget {
  final Project project;
  final String mode;
  final ValueChanged<String> onPick;
  final VoidCallback onHelp;
  final VoidCallback? onMixer;

  /// 프로젝트 설정(스타일·조) 열기 — 씬/타임라인 화면에 늘 떠 있던 칩들을
  /// 여기 한 곳으로 모았다.
  final VoidCallback onSettings;
  const _ModeBar({
    required this.project,
    required this.mode,
    required this.onPick,
    required this.onHelp,
    required this.onMixer,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    // **탭 네 개가 스크롤 없이 늘 다 보여야 한다.** 처음엔 가로 스크롤 줄로
    // 짰는데, 좁은 폰(400dp)에서 뒤로가기·곡 이름·탭 넷·사용법을 다 넣으면
    // 넘쳐서 "쇼" 탭이 화면 밖으로 밀렸다 — 스크롤해서 찾아야 하는 탭은
    // 탭이 아니다. 좁을 땐 곡 이름을 감추고, 탭 넷을 `Expanded` 로 똑같이
    // 나눠 늘 다 보이게 한다.
    final compact = MediaQuery.of(context).size.width < 600;
    return AnimatedBuilder(
      animation: project,
      builder: (context, _) => Container(
        padding: const EdgeInsets.fromLTRB(6, 8, 10, 8),
        decoration: const BoxDecoration(
          color: Color(0xFF17181B),
          border: Border(bottom: BorderSide(color: Colors.white12)),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: '첫 화면으로',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back, size: 20),
            ),
            if (!compact)
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    project.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            Expanded(
              child: Row(
                children: [
                  for (final m in _kModes)
                    Expanded(
                      child: _ModeTab(
                        label: _kModeLabel[m]!,
                        icon: _kModeIcon[m]!,
                        on: mode == m,
                        compact: compact,
                        onTap: () => onPick(m),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: '프로젝트 설정',
              onPressed: onSettings,
              icon: const Icon(Icons.settings_outlined, size: 20),
            ),
            if (onMixer != null)
              IconButton(tooltip: '믹서', onPressed: onMixer, icon: const Icon(Icons.tune, size: 20)),
            IconButton(tooltip: '사용법', onPressed: onHelp, icon: const Icon(Icons.help_outline, size: 20)),
          ],
        ),
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool on;
  final bool compact;
  final VoidCallback onTap;
  const _ModeTab({
    required this.label,
    required this.icon,
    required this.on,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    // **좁은 화면에서는 아이콘만.** 글자를 억지로 넣었더니 "타임라인"이
    // "타…" 로 잘려 실기기에서 확인해 보니 거의 못 읽었다(back·탭 넷·믹서·
    // 사용법이 360dp 안에 다 들어가야 해서 탭 하나에 남는 폭이 14dp도
    // 안 됐다) — 잘린 두 글자보다 또렷한 아이콘 하나가 낫다. 선택된 탭은
    // 배경·색으로 이미 표시되니 아이콘만으로도 지금 뭘 보고 있는지 안다.
    final content = compact
        ? Icon(icon, size: 19, color: on ? Colors.tealAccent.shade100 : Colors.white54)
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: on ? Colors.tealAccent.shade100 : Colors.white54),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                    color: on ? Colors.tealAccent.shade100 : Colors.white54,
                  ),
                ),
              ),
            ],
          );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 12, vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? Colors.white.withValues(alpha: 0.08) : null,
              borderRadius: BorderRadius.circular(9),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}
