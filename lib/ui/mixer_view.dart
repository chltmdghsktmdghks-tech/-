// 믹서 화면 — 5단계 UI 이식 1/N (2차: 가로 전면 재작성 · 라이브 · 마스터 추가).
//
// 웹 `renderMixer()`(app.html 6444줄~)의 구성을 옮겼다:
//   트랙 스트립들 → ＋악기 → **라이브 채널** → **마스터 채널**
//
// ── 가로 모드를 왜 통째로 다시 짰나 ──
// 1차 버전은 세로·가로 모두 "세로 페이더가 달린 스트립"이었다. 그런데 이 폰의 가로
// 화면은 **높이가 384dp 뿐**이고(앱바·상태바 빼면 300dp), 거기서 세로 페이더에 남는
// 높이는 사실상 0 이었다 — 실제로 화면에는 **페이더 손잡이(동그라미)만 찍히고 트랙이
// 아예 안 보였다.** 믹서에서 제일 중요한 볼륨을 못 끄는 상태였다.
// 게다가 오른쪽 절반이 통째로 비어 있었다(폭 832dp 를 스트립 106dp 로만 썼으니).
//
// → 가로는 **채널당 한 줄(가로 페이더)** 로 바꿨다. 폭을 전부 쓰고, 모든 컨트롤이
//   손가락으로 끌 만한 크기가 되고, 한 화면에 4~5채널이 보인다.
//   세로는 스트립 그대로(그게 믹서의 모양이다) — 대신 페이더를 줄이고 나머지를 키웠다.
//
// ── 다시 그리는 범위 ──
// 스트립/행 하나가 `AnimatedBuilder` 로 **자기 채널만** 듣는다. 볼륨을 끌면 그 채널만
// 다시 그려진다. (시험 화면에서 20밴드 EQ 가 느렸던 원인이 전체 재빌드였다)

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../audio_isolate.dart';
import '../drums.dart';
import '../genre_mix.dart' show kGenreDuck;
import '../instrument_tone.dart';
import '../instruments.dart';
import '../project.dart';
import '../sequencer.dart';
import 'fx_rack.dart';

const _kLiveColor = Color(0xFF4DD0A8);
const _kMasterColor = Color(0xFFFFC107);

class MixerView extends StatefulWidget {
  final Project project;
  final LiveChannel live;
  final MasterChannel master;
  final AudioClient? host;

  const MixerView({
    super.key,
    required this.project,
    required this.live,
    required this.master,
    required this.host,
  });

  @override
  State<MixerView> createState() => _MixerViewState();
}

/// **솔로 하나 때문에 State 가 됐다.**
///
/// 스트립은 저마다 `AnimatedBuilder(animation: track)` 으로 **자기 트랙만** 듣는다
/// (페이더를 끌 때마다 화면 전체가 다시 그려지면 안 되기 때문이다 — 그 판단은 맞다).
/// 그런데 흐림 조건은 `track.mute || (anySolo && !track.solo)` 라서, **남의 트랙**
/// 값에 달려 있다. 드럼의 S 를 켜면 베이스 스트립이 흐려져야 하는데 베이스는
/// 드럼을 안 듣는다 — 소리는 바뀌는데 화면은 그대로였고, 「왜 갑자기 안 들리지」가
/// 화면 어디에도 안 나왔다.
///
/// `Track` 알림을 중계해 주는 곳이 없다(Project 는 트랙을 구독하지 않고, Store 의
/// 리스너는 자동 저장 타이머만 건다). 그래서 M/S 를 누르는 자리에서만 한 번
/// 다시 그린다 — 페이더 경로(`_push`)는 그대로 두어 끌 때의 전체 재빌드를 막는다.
class _MixerViewState extends State<MixerView> {
  // 아래 본문이 쓰던 이름을 그대로 살려 둔다.
  Project get project => widget.project;
  LiveChannel get live => widget.live;
  MasterChannel get master => widget.master;
  AudioClient? get host => widget.host;

  void _push(Track t) {
    // 뮤트/솔로는 볼륨으로 반영한다 — 엔진에 뮤트 개념이 따로 없다.
    // 버스 이름 규칙은 시퀀서와 **한 곳에서** 정한다(SceneSequencer.busOf) —
    // 둘이 어긋나면 페이더가 엉뚱한 트랙을 만지게 된다.
    final on = project.audible(t);
    final bus = SceneSequencer.busOf(t);
    host?.setBus(
      bus,
      vol: on ? t.vol : 0.0,
      pan: t.pan,
      rev: t.rev,
      lo: t.eq.lo,
      mid: t.eq.mid,
      hi: t.eq.hi,
      // 로우컷·하이컷(사용자 요청, 2026-09-16) — 안 보내면 손잡이를 만져도
      // 다음 씬 전환까지 안 들린다(EQ 와 같은 이유).
      hpf: t.hpf,
      lpf: t.lpf,
      // 필터 움직임(사용자 요청, 2026-09-17) — 같은 이유로 즉시 반영에도 실어야 한다.
      lfoHz: t.lfoHz,
      lfoDepth: t.lfoDepth,
    );
    // ADSR 도 같이 보낸다 — 안 그러면 손잡이를 만져도 다음 씬 전환까지
    // 안 들린다(사용자 요청, 2026-09-15).
    host?.setAdsr(
      bus,
      attack: t.adsrAttack,
      decay: t.adsrDecay,
      sustain: t.adsrSustain,
      release: t.adsrRelease,
    );
    // 유니즌도 같이(사용자 요청, 2026-09-17) — ADSR과 같은 이유.
    host?.setUni(bus, t.uniCents);
  }

  /// 솔로는 **다른 트랙까지** 들리고 안 들리고를 바꾸므로 전부 다시 보낸다.
  void _pushAll() {
    final h = host;
    if (h != null) SceneSequencer.pushMix(project, h);
    // 소리만 바꾸면 안 된다 — 흐림 표시도 남의 스트립까지 바뀐다.
    // (되돌리기 알림에서 늦게 불릴 수 있어 `mounted` 를 본다)
    if (mounted) setState(() {});
  }

  /// 트랙을 지우고 **되돌릴 길을 띄운다.**
  ///
  /// 트랙 하나에 모든 씬의 클립이 달려 있어서, 이 한 번이 곡 전체에서 그 악기를
  /// 지운다 — 이 앱에서 한 손짓으로 제일 많이 잃는 자리다. 알림이 사라질 때까지
  /// 되돌릴 수 있고, 사라지면 그때 치운다([RemovedTrack.drop]).
  void _removeTrack(BuildContext context, Track t) {
    final messenger = ScaffoldMessenger.of(context);
    final name = t.name;
    final clips = project.scenes
        .where((s) => (s.clips[t.id] ?? '').isNotEmpty)
        .length;
    final gone = project.removeTrack(t);
    if (gone == null) return;
    messenger.clearSnackBars();
    messenger
        .showSnackBar(
          SnackBar(
            content: Text(
              clips > 1
                  ? '「$name」 트랙을 지웠습니다 · 씬 $clips군데의 음도 같이 빠졌어요'
                  : '「$name」 트랙을 지웠습니다',
            ),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: '되돌리기',
              onPressed: () {
                project.undoRemoveTrack(gone);
                _pushAll(); // 되돌린 트랙의 믹서 값을 엔진에 다시 실어 준다
              },
            ),
          ),
        )
        .closed
        .then((_) {
          // 알림이 사라졌으면 이제 정말 안 쓴다 — 되돌렸으면 [drop] 이 알아서 비켜 준다.
          if (project.tracks.contains(gone.track)) return;
          gone.drop();
        });
  }

  void _pushLive() => host?.setBus('live', vol: live.vol, rev: live.rev);
  void _pushMaster() => host?.setMasterVol(master.vol);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= c.maxHeight;
        return AnimatedBuilder(
          // 트랙 목록 구조(추가·삭제·순서)만 여기서 듣는다. 값 변화는 채널이 각자 듣는다.
          animation: project,
          builder: (context, _) => wide
              ? _buildLandscape(context, c)
              : _PortraitSwitcher(
                  count: project.tracks.length,
                  strips: (ctx) => _buildPortrait(ctx, c),
                  rowsView: (ctx) => _buildLandscape(ctx, c),
                ),
        );
      },
    );
  }

  // ══════════════════ 세로 — 채널 스트립 ══════════════════

  Widget _buildPortrait(BuildContext context, BoxConstraints c) {
    // 페이더 말고 위아래로 자리를 꼭 차지하는 것들의 합(대략):
    //   바깥 여백 12 + 머리 54 + 값 24 + 노브 4개 232 + M/S 46 + 삭제 30
    // 남는 만큼을 페이더에 준다. 상한을 260 으로 잡은 게 "페이더 길이 줄이고" 다 —
    // 예전엔 Flexible 이라 남는 높이를 전부(400dp 넘게) 먹었다.
    // 작은 노브 넷을 시트로 옮겼으니 그만큼 **페이더가 길어진다**(잡기 쉬워진다).
    final faderH = (c.maxHeight - 250).clamp(140.0, 420.0);
    // 스트립 너비는 **화면에 맞춘다.** 100dp 로 못 박아 두면 폰에서 세 줄밖에 안 보인다 —
    // 「트랙 4개」라고 적혀 있는데 셋만 보이면 나머지가 있는 줄을 모른다(그림으로 확인).
    // 넷은 들어가게 줄이되 76dp 아래로는 안 내려간다(손끝으로 잡는 자리다).
    final stripW = ((c.maxWidth - 78) / 4).clamp(76.0, 100.0);
    // 다 안 들어가면 오른쪽 끝을 흐려 준다 — **더 있다는 표시**.
    final strips = project.tracks.length + 2; // 라이브 + 추가
    final overflow = strips * stripW > c.maxWidth - 78;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Stack(
            children: [
              Scrollbar(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  // 스트립 높이를 꽉 채워 두면 **빈 공간을 잡아도 가로로 움직인다**
                  // (웹에서 "맨 밑 빈 공간으로도 옆으로 움직이게" 라고 지적됐던 것)
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: c.maxHeight),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final t in project.tracks)
                          _Strip(
                            key: ValueKey(t.id),
                            host: host,
                            track: t,
                            width: stripW,
                            faderH: faderH,
                            anySolo: project.tracks.any((x) => x.solo),
                            onChanged: () => _push(t),
                            onSolo: _pushAll,
                            onRemove: project.tracks.length > 1
                                ? () => _removeTrack(context, t)
                                : null,
                          ),
                        _LiveStrip(
                          host: host,
                          live: live,
                          width: stripW,
                          faderH: faderH,
                          onChanged: _pushLive,
                        ),
                        _AddTrack(width: stripW, onAdd: project.addTrack),
                      ],
                    ),
                  ),
                ),
              ),
              if (overflow)
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 18,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            const Color(0xFF0E0E12).withValues(alpha: 0),
                            const Color(0xFF0E0E12).withValues(alpha: 0.85),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // 마스터는 **맨 옆에 붙박이**다 — 스크롤을 어디까지 밀어 놨든 항상 보인다.
        // (하드웨어 콘솔도 마스터 섹션은 늘 오른쪽 끝에 고정되어 있다)
        _MasterStrip(
          project: project,
          master: master,
          host: host,
          width: 78,
          faderH: faderH,
          onChanged: _pushMaster,
        ),
      ],
    );
  }

  // ══════════════════ 가로 — 채널당 한 줄 ══════════════════

  Widget _buildLandscape(BuildContext context, BoxConstraints c) {
    // 진짜 가로(눕힌 폰)일 때만 한 줄로 붙인다. 세로의 '한눈에' 보기는
    // 폭이 400dp 뿐이라 두 줄이 맞다.
    final wide = c.maxWidth >= c.maxHeight;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            children: [
              for (final t in project.tracks)
                _TrackRow(
                  key: ValueKey(t.id),
                  host: host,
                  wide: wide,
                  track: t,
                  anySolo: project.tracks.any((x) => x.solo),
                  onChanged: () => _push(t),
                  onSolo: _pushAll,
                  onRemove: project.tracks.length > 1
                      ? () => _removeTrack(context, t)
                      : null,
                ),
              _LiveRow(
                live: live,
                host: host,
                onChanged: _pushLive,
                wide: wide,
              ),
              _AddRow(onAdd: project.addTrack),
            ],
          ),
        ),
        // 마스터는 맨 아래 붙박이 — 세로에서 맨 오른쪽에 고정한 것과 같은 자리다.
        _MasterRow(
          project: project,
          master: master,
          host: host,
          onChanged: _pushMaster,
        ),
      ],
    );
  }
}

/// 세로 화면에서 **스트립 ↔ 줄** 을 고르게 하는 껍데기.
///
/// 스트립(세로 페이더)은 100dp 씩 먹어서 세로 화면에 **세 개밖에 안 보인다.**
/// 재즈·팝처럼 6~7트랙인 곡은 밸런스를 맞추려면 계속 좌우로 밀어야 한다.
/// 줄 모양은 한 채널이 한 줄이라 **전부 한 화면에** 들어온다(가로에서 쓰던 그 모양).
/// 처음 값은 트랙 수로 정한다 — **5개가 넘으면 줄 모양**(그때부터 스트립이 안 맞는다).
class _PortraitSwitcher extends StatefulWidget {
  final int count;
  final WidgetBuilder strips, rowsView;
  const _PortraitSwitcher({
    required this.count,
    required this.strips,
    required this.rowsView,
  });

  @override
  State<_PortraitSwitcher> createState() => _PortraitSwitcherState();
}

class _PortraitSwitcherState extends State<_PortraitSwitcher> {
  bool? _rows;

  @override
  Widget build(BuildContext context) {
    final rows = _rows ?? widget.count > 5;
    return Column(
      children: [
        _ViewBar(
          rows: rows,
          count: widget.count,
          onPick: (v) => setState(() => _rows = v),
        ),
        Expanded(
          child: rows ? widget.rowsView(context) : widget.strips(context),
        ),
      ],
    );
  }
}

/// 보기 바꾸기 — 스트립(자세히) ↔ 줄(한눈에).
class _ViewBar extends StatelessWidget {
  final bool rows;
  final int count;
  final ValueChanged<bool> onPick;
  const _ViewBar({
    required this.rows,
    required this.count,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46, // 칩이 36 이 되게 (예전엔 38 안에 26 짜리 칩)
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          Text(
            '트랙 $count개',
            style: const TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
          const Spacer(),
          _ViewChip(
            label: '한눈에',
            icon: Icons.view_list,
            on: rows,
            onTap: () => onPick(true),
          ),
          const SizedBox(width: 6),
          _ViewChip(
            label: '자세히',
            icon: Icons.view_column,
            on: !rows,
            onTap: () => onPick(false),
          ),
        ],
      ),
    );
  }
}

class _ViewChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool on;
  final VoidCallback onTap;
  const _ViewChip({
    required this.label,
    required this.icon,
    required this.on,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36, // 26 은 손가락에 비해 작다
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: on ? Colors.teal.shade600 : Colors.white10,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: on ? Colors.white : Colors.white54),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: on ? Colors.white : Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════ 채널 상세 — 큰 손잡이로 하나씩 ══════════════════

/// 슬라이더 하나 — **화면 폭을 다 쓴다.** 손잡이도 크다.
///
/// 예전엔 한 줄에 다섯 개를 늘어놨다(볼륨·좌우·잔향·저음·고음). 400dp 화면에서
/// 하나가 60dp 남짓이라 **잡히지도, 원하는 값에 세우지도 못했다**(사용자 지적).
/// 자주 만지는 건 볼륨 하나뿐이니 줄에는 볼륨만 두고, 나머지는 이 시트로 옮겼다.
class BigSlider extends StatelessWidget {
  final String label, display;
  final double value, min, max;
  final Color color;
  final ValueChanged<double> onChanged;
  final VoidCallback? onReset;

  const BigSlider({
    super.key,
    required this.label,
    required this.display,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.onChanged,
    this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                display,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              if (onReset != null) ...[
                const SizedBox(width: 10),
                // 되돌리기 — 손으로 가운데를 정확히 맞추기는 어렵다
                GestureDetector(
                  onTap: onReset,
                  child: const Icon(
                    Icons.restart_alt,
                    size: 17,
                    color: Colors.white38,
                  ),
                ),
              ],
            ],
          ),
          SizedBox(
            height: 40,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 6,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
                activeTrackColor: color,
                thumbColor: color,
                inactiveTrackColor: Colors.white24,
              ),
              child: Slider(
                min: min,
                max: max,
                value: value.clamp(min, max),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 채널 시트를 접었다 펼 수 있는 서랍 하나 — 사용자 요청(2026-09-17):
/// "설정들 서랍형식으로 정리". 자주 만지는 것(볼륨 등)은 [initiallyExpanded]
/// 를 true 로 열어 두고, 나머지(ADSR·질감·이펙트 등)는 접어서 시작한다 —
/// 안 그러면 손잡이가 많은 악기에서 시트가 너무 길어져 스크롤만 하다 끝난다.
class _Drawer extends StatefulWidget {
  final String title;
  final String? subtitle;
  final bool initiallyExpanded;
  final Widget child;
  const _Drawer({
    required this.title,
    this.subtitle,
    required this.child,
    this.initiallyExpanded = false,
  });

  @override
  State<_Drawer> createState() => _DrawerState();
}

class _DrawerState extends State<_Drawer> {
  late bool _open = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  _open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                  size: 20,
                  color: Colors.white54,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (widget.subtitle != null)
                        Text(
                          widget.subtitle!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white38,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: widget.child,
          ),
      ],
    );
  }
}

/// 채널 하나를 **크게** 손보는 시트 — 줄·스트립 어디서든 여기로 온다.
void showChannelSheet(
  BuildContext context, {
  required Track track,
  required Color color,
  required VoidCallback onChanged,
  required VoidCallback onSolo,
  VoidCallback? onRemove,
  AudioClient? host,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF16181C),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => AnimatedBuilder(
      animation: track,
      builder: (ctx, _) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.85,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(width: 5, height: 26, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _trackName(track),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            _voiceName(track),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white38,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // `_Toggle` 은 폭을 안 정하면 글자만 해진다 — 여기서도 못 박는다
                    SizedBox(
                      width: 38,
                      child: _Toggle(
                        text: 'M',
                        height: 34,
                        on: track.mute,
                        onColor: Colors.red.shade400,
                        onTap: () {
                          track.mute = !track.mute;
                          onSolo();
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 38,
                      child: _Toggle(
                        text: 'S',
                        height: 34,
                        on: track.solo,
                        onColor: Colors.amber.shade500,
                        onTap: () {
                          track.solo = !track.solo;
                          onSolo();
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // ── 서랍 정리(사용자 요청, 2026-09-17) ──
                // 자주 만지는 볼륨·팬·울림·EQ 는 "기본" 서랍 하나로 묶어 늘 펴
                // 둔다. 악기 설정·ADSR·질감·이펙트처럼 만질 때만 여는 것들은
                // 접어 둬서 시트가 한눈에 안 들어올 만큼 길어지지 않게 한다.
                _Drawer(
                  title: '기본',
                  initiallyExpanded: true,
                  child: Column(
                    children: [
                      BigSlider(
                        label: '볼륨',
                        display: '${(track.vol * 100).round()}%',
                        value: track.vol,
                        min: 0,
                        max: 1.4,
                        color: color,
                        onReset: () {
                          track.vol = 1.0;
                          onChanged();
                        },
                        onChanged: (v) {
                          track.vol = v;
                          onChanged();
                        },
                      ),
                      BigSlider(
                        label: '좌우',
                        display: _panText(track.pan),
                        value: track.pan,
                        min: -1,
                        max: 1,
                        color: color,
                        onReset: () {
                          track.pan = 0;
                          onChanged();
                        },
                        onChanged: (v) {
                          track.pan = v;
                          onChanged();
                        },
                      ),
                      BigSlider(
                        // 라이브 화면은 「울림」, 여기는 「잔향」이었다 — 같은
                        // 손잡이에 두 이름이 붙어 있었다. 「울림」으로 맞춘다.
                        // (인서트 플러그인 이름 「리버브」는 그대로 둔다 —
                        // 보내기가 아니라 다른 물건이다.)
                        label: '울림',
                        display: '${(track.rev * 100).round()}%',
                        value: track.rev,
                        min: 0,
                        max: 1,
                        color: color,
                        onChanged: (v) {
                          track.rev = v;
                          onChanged();
                        },
                      ),
                      BigSlider(
                        label: '저음',
                        display: _eqText(track.eq.lo),
                        value: track.eq.lo,
                        min: -12,
                        max: 12,
                        color: color,
                        onReset: () {
                          track.eq.lo = 0;
                          track.eqChanged(); // 손으로 만진 EQ — 스타일이 덮지 않게
                          onChanged();
                        },
                        onChanged: (v) {
                          track.eq.lo = v;
                          track.eqChanged(); // 손으로 만진 EQ — 스타일이 덮지 않게
                          onChanged();
                        },
                      ),
                      BigSlider(
                        label: '고음',
                        display: _eqText(track.eq.hi),
                        value: track.eq.hi,
                        min: -12,
                        max: 12,
                        color: color,
                        onReset: () {
                          track.eq.hi = 0;
                          track.eqChanged(); // 손으로 만진 EQ — 스타일이 덮지 않게
                          onChanged();
                        },
                        onChanged: (v) {
                          track.eq.hi = v;
                          track.eqChanged(); // 손으로 만진 EQ — 스타일이 덮지 않게
                          onChanged();
                        },
                      ),
                      // ── 로우컷·하이컷(사용자 요청, 2026-09-16) ──
                      // DSP 는 이미 있었다(`TrackMix.hpfFreq`/`lpfFreq`, 장르
                      // 믹스가 조용히 쓰던 값) — 손잡이가 없었을 뿐이라 EQ 와
                      // 같은 자리에 슬라이더만 얹는다. 기본값(20Hz·20000Hz)이
                      // "꺼짐"이다.
                      BigSlider(
                        label: '로우컷',
                        display: track.hpf <= 20
                            ? '꺼짐'
                            : '${track.hpf.round()}Hz',
                        value: track.hpf,
                        min: 20,
                        max: 500,
                        color: color,
                        onReset: () {
                          track.hpf = 20;
                          track.eqChanged();
                          onChanged();
                        },
                        onChanged: (v) {
                          track.hpf = v;
                          track.eqChanged();
                          onChanged();
                        },
                      ),
                      BigSlider(
                        label: '하이컷',
                        display: track.lpf >= 20000
                            ? '꺼짐'
                            : '${track.lpf.round()}Hz',
                        value: track.lpf,
                        min: 2000,
                        max: 20000,
                        color: color,
                        onReset: () {
                          track.lpf = 20000;
                          track.eqChanged();
                          onChanged();
                        },
                        onChanged: (v) {
                          track.lpf = v;
                          track.eqChanged();
                          onChanged();
                        },
                      ),
                    ],
                  ),
                ),
                // ── 악기 설정 — 기타 본체·픽업, 피아노 모델·에이징 ──
                if (hasInstrumentTone(track.voice)) ...[
                  const Divider(color: Colors.white12, height: 20),
                  _Drawer(
                    title: '악기 설정',
                    child: _InstrumentToneSection(
                      track: track,
                      color: color,
                      onChanged: onChanged,
                    ),
                  ),
                ],
                // ── 질감 — 유니즌·필터 움직임(사용자 요청, 2026-09-17:
                // "유니즌/디투리즈로 두꺼워지게, 필터/움직임 추가") ──
                if (hasAdsr(track.voice)) ...[
                  const Divider(color: Colors.white12, height: 20),
                  _Drawer(
                    title: '질감',
                    subtitle: '두께(유니즌)·시간에 따른 필터 움직임',
                    child: _TextureSection(
                      track: track,
                      color: color,
                      onChanged: onChanged,
                    ),
                  ),
                ],
                // ── ADSR — 신스 계열 악기만(사용자 요청, 2026-09-15) ──
                if (hasAdsr(track.voice)) ...[
                  const Divider(color: Colors.white12, height: 20),
                  _Drawer(
                    title: 'ADSR',
                    subtitle: '소리가 나고 사그라드는 모양',
                    child: _AdsrSection(
                      track: track,
                      color: color,
                      onChanged: onChanged,
                    ),
                  ),
                ],
                // ── 인서트 (5단계 46/N) — 로직의 플러그인 자리 ──
                const Divider(color: Colors.white12, height: 20),
                _Drawer(
                  title: '이펙트',
                  child: FxRack.forTrack(track: track, host: host, color: color),
                ),
                const Divider(color: Colors.white12, height: 20),

                // 지우기는 **화면 맨 아래 끝**이다. 작은 글자 버튼을 오른쪽 구석에
                // 붙여 놨더니 안드로이드 내비게이션 바에 딱 붙어서 손가락으로
                // 누르기 어려웠다(폰에서 두 번 눌렀는데 안 먹었다).
                // 폭을 다 쓰는 46px 버튼으로 키우고, 아래 여백도 늘렸다.
                if (onRemove != null) ...[
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmRemove(ctx, track, onRemove),
                      icon: const Icon(Icons.delete_outline, size: 19),
                      // 「지우기」는 **비운다**(편집기의 판 비우기), 「삭제」는
                      // **없앤다**(곡·씬·트랙). 트랙은 없애는 쪽이다.
                      label: const Text(
                        '이 트랙 삭제',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red.shade300,
                        side: BorderSide(
                          color: Colors.red.shade300.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// **악기 설정** — 기타는 본체·픽업, 피아노는 모델·에이징(`instrument_tone.dart`).
/// 표본을 새로 못 구하니 이미 있는 트랙 EQ 를 그 악기 성격으로 채워 넣는
/// 것뿐이지만, 고르는 쪽에서는 "픽업을 바꿨다"로 보이면 된다.
class _InstrumentToneSection extends StatelessWidget {
  final Track track;
  final Color color;
  final VoidCallback onChanged;
  const _InstrumentToneSection({
    required this.track,
    required this.color,
    required this.onChanged,
  });

  static const _kBassVoices = {'bass', 'fingerbass', 'moogbass', 'upright'};
  static const _kStringsVoices = {'strings', 'jpstrings', 'violin', 'cello'};
  static const _kBrassVoices = {
    'brass',
    'analogbrass',
    'trumpet',
    'sax',
    'clarinet',
    'flute',
  };

  @override
  Widget build(BuildContext context) {
    final isGuitar = track.voice == 'guitar';
    final isPiano = track.voice == 'piano';
    final isBass = _kBassVoices.contains(track.voice);
    final isStrings = _kStringsVoices.contains(track.voice);
    final isBrass = _kBrassVoices.contains(track.voice);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isBass) ...[
          const Text(
            '바디',
            style: TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final k in kBassBodyLabel.keys)
                _ToneChip(
                  label: kBassBodyLabel[k]!,
                  on: track.bassBody == k,
                  color: color,
                  onTap: () {
                    track.setBassBody(track.bassBody == k ? null : k);
                    onChanged();
                  },
                ),
            ],
          ),
          if (track.bassBody != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                kBassBodyDesc[track.bassBody] ?? '',
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ),
        ] else if (isStrings) ...[
          const Text(
            '편성',
            style: TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final k in kStringsEnsembleLabel.keys)
                _ToneChip(
                  label: kStringsEnsembleLabel[k]!,
                  on: track.stringsEnsemble == k,
                  color: color,
                  onTap: () {
                    track.setStringsEnsemble(
                      track.stringsEnsemble == k ? null : k,
                    );
                    onChanged();
                  },
                ),
            ],
          ),
          if (track.stringsEnsemble != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                kStringsEnsembleDesc[track.stringsEnsemble] ?? '',
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ),
        ] else if (isBrass) ...[
          const Text(
            '뮤트',
            style: TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final k in kBrassMuteLabel.keys)
                _ToneChip(
                  label: kBrassMuteLabel[k]!,
                  on: track.brassMute == k,
                  color: color,
                  onTap: () {
                    track.setBrassMute(track.brassMute == k ? null : k);
                    onChanged();
                  },
                ),
            ],
          ),
          if (track.brassMute != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                kBrassMuteDesc[track.brassMute] ?? '',
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ),
        ] else if (isGuitar) ...[
          const Text(
            '본체',
            style: TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final k in kGuitarBodyLabel.keys)
                _ToneChip(
                  label: kGuitarBodyLabel[k]!,
                  on: track.guitarBody == k,
                  color: color,
                  onTap: () {
                    track.setGuitarBody(track.guitarBody == k ? null : k);
                    onChanged();
                  },
                ),
            ],
          ),
          if (track.guitarBody != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                kGuitarBodyDesc[track.guitarBody] ?? '',
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ),
          const SizedBox(height: 14),
          const Text(
            '픽업',
            style: TextStyle(fontSize: 11.5, color: Colors.white38),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final k in kGuitarPickupLabel.keys)
                _ToneChip(
                  label: kGuitarPickupLabel[k]!,
                  on: track.guitarPickup == k,
                  color: color,
                  onTap: () {
                    track.setGuitarPickup(track.guitarPickup == k ? null : k);
                    onChanged();
                  },
                ),
            ],
          ),
          if (track.guitarPickup != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                kGuitarPickupDesc[track.guitarPickup] ?? '',
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ),
        ] else ...[
          if (isPiano) ...[
            const Text(
              '모델',
              style: TextStyle(fontSize: 11.5, color: Colors.white38),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final k in kPianoModelLabel.keys)
                  _ToneChip(
                    label: kPianoModelLabel[k]!,
                    on: track.pianoModel == k,
                    color: color,
                    onTap: () {
                      track.setPianoModel(track.pianoModel == k ? null : k);
                      onChanged();
                    },
                  ),
              ],
            ),
            if (track.pianoModel != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  kPianoModelDesc[track.pianoModel] ?? '',
                  style: const TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ),
            const SizedBox(height: 8),
          ],
          BigSlider(
            label: '에이징',
            display: '${(track.pianoAging * 100).round()}%',
            value: track.pianoAging,
            min: 0,
            max: 1,
            color: color,
            onReset: () {
              track.setPianoAging(0);
              onChanged();
            },
            onChanged: (v) {
              track.setPianoAging(v);
              onChanged();
            },
          ),
        ],
      ],
    );
  }
}

/// **질감** — 유니즌(두께)·필터 움직임. ADSR과 같은 대상(신스 계열,
/// [hasAdsr])에만 뜻이 있다. 사용자 요청, 2026-09-17: "유니즌/디투리즈로
/// 두꺼워지게, 필터/움직임 추가 — 악기별로 설정 가능하게".
///
/// 유니즌은 새 손잡이(`Track.uniCents`, null=악기 기본값)지만, 필터
/// 움직임은 **이미 있던 손잡이**(`Track.lfoHz`/`lfoDepth`)를 화면에 처음
/// 꺼내는 것뿐이다 — 엠비언트 장르가 패드에 조용히 걸던 "숨 쉬는" 필터를
/// 사용자가 직접 잡을 수 있게 열었다. 하이컷이 열려 있으면(기본 20000Hz)
/// 필터가 움직여도 안 들리므로 안내 문구를 같이 보여 준다.
class _TextureSection extends StatelessWidget {
  final Track track;
  final Color color;
  final VoidCallback onChanged;
  const _TextureSection({
    required this.track,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BigSlider(
          label: '유니즌',
          display: (track.uniCents ?? 0) <= 0.5
              ? '꺼짐'
              : '${(track.uniCents ?? 0).round()}cent',
          value: track.uniCents ?? 0,
          min: 0,
          max: 30,
          color: color,
          onReset: () {
            track.setUniCents(null);
            onChanged();
          },
          onChanged: (v) {
            track.setUniCents(v);
            onChanged();
          },
        ),
        BigSlider(
          label: '움직임 속도',
          display: track.lfoHz <= 0 ? '꺼짐' : '${track.lfoHz.toStringAsFixed(2)}Hz',
          value: track.lfoHz,
          min: 0,
          max: 0.5,
          color: color,
          onReset: () {
            track.lfoHz = 0;
            track.eqChanged();
            onChanged();
          },
          onChanged: (v) {
            track.lfoHz = v;
            track.eqChanged();
            onChanged();
          },
        ),
        BigSlider(
          label: '움직임 폭',
          display: '${(track.lfoDepth * 100).round()}%',
          value: track.lfoDepth,
          min: 0,
          max: 1,
          color: color,
          onReset: () {
            track.lfoDepth = 0;
            track.eqChanged();
            onChanged();
          },
          onChanged: (v) {
            track.lfoDepth = v;
            track.eqChanged();
            onChanged();
          },
        ),
        if (track.lfoHz > 0 && track.lfoDepth > 0 && track.lpf >= 20000)
          const Padding(
            padding: EdgeInsets.only(top: 2, bottom: 4),
            child: Text(
              '하이컷이 꺼져 있으면 필터 움직임이 안 들려요 — "기본" 서랍에서 하이컷을 낮춰 보세요.',
              style: TextStyle(fontSize: 11, color: Colors.amber),
            ),
          ),
      ],
    );
  }
}

/// **ADSR** — 신스 계열 악기만(사용자 요청, 2026-09-15: "악기들 ADSR 필요한
/// 악기들은 악기 설정에 넣어 놓자"). 표본 악기·뜯는 계열은 [hasAdsr] 가
/// 걸러서 애초에 이 위젯이 안 뜬다.
///
/// 넷 다 **null 이 기본**(악기 고유의 소리 그대로) — 손잡이를 만지는 순간만
/// 값이 생기고, 리셋(단위 글자 누르기)하면 다시 null 로 돌아간다. 값이
/// 없을 때 슬라이더에 보여 줄 자리는 흔한 신스 기본값(어택 50ms·디케이
/// 150ms·서스테인 70%·릴리스 300ms)이다 — 실제로 그 값이 적용 중이라는
/// 뜻이 아니라 "여기서부터 만져 보라"는 출발점일 뿐이다.
class _AdsrSection extends StatelessWidget {
  final Track track;
  final Color color;
  final VoidCallback onChanged;
  const _AdsrSection({
    required this.track,
    required this.color,
    required this.onChanged,
  });

  static String _ms(double sec) => '${(sec * 1000).round()}ms';
  static String _pct(double v) => '${(v * 100).round()}%';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BigSlider(
          label: '어택',
          display: _ms(track.adsrAttack ?? 0.05),
          value: track.adsrAttack ?? 0.05,
          min: 0.001,
          max: 1.0,
          color: color,
          onReset: () {
            track.setAdsrAttack(null);
            onChanged();
          },
          onChanged: (v) {
            track.setAdsrAttack(v);
            onChanged();
          },
        ),
        BigSlider(
          label: '디케이',
          display: _ms(track.adsrDecay ?? 0.15),
          value: track.adsrDecay ?? 0.15,
          min: 0.01,
          max: 1.0,
          color: color,
          onReset: () {
            track.setAdsrDecay(null);
            onChanged();
          },
          onChanged: (v) {
            track.setAdsrDecay(v);
            onChanged();
          },
        ),
        BigSlider(
          label: '서스테인',
          display: _pct(track.adsrSustain ?? 0.7),
          value: track.adsrSustain ?? 0.7,
          min: 0.0,
          max: 1.0,
          color: color,
          onReset: () {
            track.setAdsrSustain(null);
            onChanged();
          },
          onChanged: (v) {
            track.setAdsrSustain(v);
            onChanged();
          },
        ),
        BigSlider(
          label: '릴리스',
          display: _ms(track.adsrRelease ?? 0.3),
          value: track.adsrRelease ?? 0.3,
          min: 0.02,
          max: 2.0,
          color: color,
          onReset: () {
            track.setAdsrRelease(null);
            onChanged();
          },
          onChanged: (v) {
            track.setAdsrRelease(v);
            onChanged();
          },
        ),
      ],
    );
  }
}

class _ToneChip extends StatelessWidget {
  final String label;
  final bool on;
  final Color color;
  final VoidCallback onTap;
  const _ToneChip({
    required this.label,
    required this.on,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: on ? color : Colors.white10,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: on ? FontWeight.w800 : FontWeight.w500,
            color: on ? Colors.black : Colors.white70,
          ),
        ),
      ),
    );
  }
}

// ══════════════════ 공용 ══════════════════

const _typeColor = {
  'drum': Color(0xFF7CB342),
  'bass': Color(0xFF42A5F5),
  'chord': Color(0xFFAB47BC),
  'melody': Color(0xFFFFA726),
};

/// 음색 이름 — 드럼 트랙은 음색표가 아니라 **키트**를 쓴다.
String _voiceName(Track t) => t.type == 'drum'
    ? (DRUM_KITS[t.kit]?.label ?? '드럼 키트')
    : (VOICE_LABEL[t.voice] ?? t.voice);

/// 트랙을 지우면 **모든 씬에서 그 악기가 사라진다.** 되돌릴 수는 있지만
/// (`_removeTrack` 의 알림) 크게 잃는 자리라 한 번 묻는다.
void _confirmRemove(BuildContext ctx, Track track, VoidCallback onRemove) {
  showDialog<void>(
    context: ctx,
    builder: (d) => AlertDialog(
      backgroundColor: const Color(0xFF1A1D22),
      title: Text(
        '「${track.name}」 트랙을 지울까요?',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
      ),
      content: const Text(
        '모든 씬에서 이 악기가 사라집니다. 바로 되돌릴 수 있어요.',
        style: TextStyle(fontSize: 13, color: Colors.white70),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d),
          child: const Text('취소', style: TextStyle(fontSize: 14)),
        ),
        FilledButton(
          onPressed: () {
            Navigator.pop(d);
            Navigator.pop(ctx); // 채널 시트도 닫는다
            onRemove();
          },
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          child: const Text(
            '지우기',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

String _trackName(Track t) => t.name;

String _panText(double v) => v.abs() < 0.02
    ? '가운데'
    : (v < 0 ? 'L${(-v * 100).round()}' : 'R${(v * 100).round()}');

/// 마스터 값은 웹과 같이 dB 로 보여 준다(1.0 = 0.0dB).
String _dbText(double v) {
  if (v <= 0.001) return '−∞';
  final db = 20 * math.log(v) / math.ln10;
  return '${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)}dB';
}

/// 라이브 악기 고르기 — 웹 `openLiveVoiceSheet()`.
Future<void> _pickVoice(
  BuildContext context,
  LiveChannel live,
  VoidCallback after,
) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1A1A1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '라이브 악기',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              '건반으로 치는 소리입니다. 곡 트랙과는 따로 놉니다.',
              style: TextStyle(fontSize: 11.5, color: Colors.white38),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                // **계열별 서랍**으로 나눠 보여 준다(`instruments.dart` 의
                // `kVoiceFamily`) — 33개를 한 줄에 늘어놓으면 원하는 걸 찾으려고
                // 계속 밀어야 한다. 사람은 "기타 비슷한 거"를 찾지 'nylon' 을
                // 찾지 않는다.
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in kVoiceFamily.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 8, bottom: 6),
                        child: Row(
                          children: [
                            Icon(
                              kVoiceFamilyIcon[e.key] ?? Icons.piano,
                              size: 13,
                              color: Colors.white54,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              e.key,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white54,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final v in e.value)
                            GestureDetector(
                              onTap: () {
                                live.voice = v;
                                after();
                                Navigator.pop(ctx);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 11,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: v == live.voice
                                      ? _kLiveColor
                                      : Colors.white10,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  VOICE_LABEL[v] ?? v,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: v == live.voice
                                        ? FontWeight.w800
                                        : FontWeight.w400,
                                    color: v == live.voice
                                        ? Colors.black
                                        : Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ══════════════════ 세로 — 스트립들 ══════════════════

/// 채널 스트립 하나. **자기 트랙만 듣는다** — 다른 트랙을 만져도 여기는 안 그려진다.
class _Strip extends StatelessWidget {
  /// 인서트를 오디오 쪽에 밀어 주려면 필요하다(플러그인 창이 값을 바로 보낸다).
  final AudioClient? host;
  final Track track;
  final double width, faderH;
  final bool anySolo;
  final VoidCallback onChanged;
  final VoidCallback onSolo;
  final VoidCallback? onRemove;

  const _Strip({
    super.key,
    required this.host,
    required this.track,
    required this.width,
    required this.faderH,
    required this.anySolo,
    required this.onChanged,
    required this.onSolo,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: track,
      builder: (context, _) {
        final c = _typeColor[track.type] ?? Colors.grey;
        // 솔로가 켜진 트랙이 있는데 나는 솔로가 아니면 흐리게 — 왜 안 들리는지 보이게
        final dimmed = track.mute || (anySolo && !track.solo);
        return _StripShell(
          width: width,
          color: c,
          dimmed: dimmed,
          title: _trackName(track),
          subtitle: _voiceName(track),
          children: [
            // 페이더 **옆에** 미터를 붙인다 — 폰 스피커로는 저음이 거의 안 들려서
            // **베이스가 두 배로 커도 귀로는 모른다.** 눈이 있으면 바로 보인다.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _VFader(
                  height: faderH,
                  value: track.vol,
                  max: 1.4,
                  color: c,
                  onChanged: (v) {
                    track.vol = v;
                    onChanged();
                  },
                ),
                const SizedBox(width: 5),
                _LevelMeter(
                  host: host,
                  vertical: true,
                  length: faderH,
                  bus: SceneSequencer.busOf(track),
                ),
              ],
            ),
            _Readout('${(track.vol * 100).round()}%'),
            const Spacer(),
            // 음소거·솔로 — 믹싱 중에 제일 자주 누른다(빼면 안 된다).
            //
            // 그런데 **29×34 였다** — 스트립이 80dp 인데 양옆 여백 8+8 과 사이 5 를
            // 빼면 하나에 29 밖에 안 남았다. M 과 S 는 붙어 있고 뜻이 반대라
            // (안 들리게 / 이것만 들리게) 잘못 누르면 제일 헷갈리는 짝이다.
            // 여백을 줄여 35×40 으로 넓혔다 — 보이는 것도 같이 커진다.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Row(
                children: [
                  Expanded(
                    child: _Toggle(
                      text: 'M',
                      height: 40,
                      on: track.mute,
                      onColor: Colors.red.shade400,
                      onTap: () {
                        track.mute = !track.mute;
                        onSolo();
                      },
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _Toggle(
                      text: 'S',
                      height: 40,
                      on: track.solo,
                      onColor: Colors.amber.shade500,
                      onTap: () {
                        track.solo = !track.solo;
                        onSolo();
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // 좌우·잔향·저음·고음은 **여기 넣지 않는다.** 100dp 폭에 작은 슬라이더
            // 넷을 욱여넣으면 하나도 제대로 못 잡는다(사용자 지적) → 시트에서 크게.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: GestureDetector(
                onTap: () => showChannelSheet(
                  context,
                  track: track,
                  color: c,
                  onChanged: onChanged,
                  onSolo: onSolo,
                  onRemove: onRemove,
                  host: host,
                ),
                child: Container(
                  height: 40, // 34 는 손가락에 비해 작다
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  // 스트립 폭이 100dp 라 글자가 아슬아슬하다 — 넘치면 **작아지게** 한다
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.tune, size: 14, color: Colors.white60),
                        SizedBox(width: 4),
                        Text(
                          '좌우·울림·EQ',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

String _eqText(double v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(0)}';

/// 라이브(건반) 스트립 — 트랙이 아니라 **내가 손으로 치는 소리** 채널이다.
class _LiveStrip extends StatelessWidget {
  final LiveChannel live;
  final AudioClient? host;
  final double width, faderH;
  final VoidCallback onChanged;
  const _LiveStrip({
    required this.live,
    required this.host,
    required this.width,
    required this.faderH,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: live,
      builder: (context, _) => _StripShell(
        width: width,
        color: _kLiveColor,
        dimmed: false,
        title: '🎹 라이브',
        subtitle: VOICE_LABEL[live.voice] ?? live.voice,
        onTapHead: () => _pickVoice(context, live, onChanged),
        children: [
          _VFader(
            height: faderH,
            value: live.vol,
            max: 1.4,
            color: _kLiveColor,
            onChanged: (v) {
              live.vol = v;
              onChanged();
            },
          ),
          _Readout('${(live.vol * 100).round()}%'),
          Expanded(
            child: _MiniSlider(
              label: '울림',
              display: '${(live.rev * 100).round()}%',
              value: live.rev,
              min: 0,
              max: 1,
              color: _kLiveColor,
              onChanged: (v) {
                live.rev = v;
                onChanged();
              },
            ),
          ),
          // 이펙트와 건반을 **한 줄에** 놓는다. 위아래로 쌓으면 320dp 폰에서
          // 글자를 키웠을 때 스트립이 16px 넘친다(시험이 잡았다).
          Padding(
            padding: const EdgeInsets.fromLTRB(5, 2, 5, 8),
            child: SizedBox(
              height: 42, // 34 는 손가락에 비해 작다
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => showLiveSheet(context, live, host),
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: _kLiveColor.withValues(alpha: 0.14),
                        foregroundColor: _kLiveColor,
                      ),
                      child: FittedBox(
                        child: Text(
                          live.chain.isEmpty
                              ? '이펙트'
                              : 'FX ${live.chain.length}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: _kLiveColor.withValues(alpha: 0.22),
                        foregroundColor: _kLiveColor,
                      ),
                      child: const FittedBox(
                        child: Text(
                          '건반',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
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

class _MasterStrip extends StatelessWidget {
  final Project project;
  final MasterChannel master;
  final AudioClient? host;
  final double width, faderH;
  final VoidCallback onChanged;
  const _MasterStrip({
    required this.project,
    required this.master,
    required this.host,
    required this.width,
    required this.faderH,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: master,
      builder: (context, _) => _StripShell(
        width: width,
        color: _kMasterColor,
        dimmed: false,
        title: 'MASTER',
        subtitle: '전체 출력',
        children: [
          // 마스터링 — 세로에서도 열 수 있어야 한다(가로에만 두면 못 찾는다)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: SizedBox(
              width: double.infinity,
              height: 40, // 32 는 손가락에 비해 작다
              child: FilledButton(
                onPressed: () => showMasterSheet(context, project, master, host),
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: _kMasterColor.withValues(alpha: 0.2),
                  foregroundColor: _kMasterColor,
                ),
                child: Text(
                  master.chain.isEmpty ? '마스터링' : '마스터링 ${master.chain.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
          // 페이더 **옆에** 미터를 붙인다 — 크기를 만지면서 결과가 바로 보여야 한다.
          // (따로 떨어뜨려 놓으면 눈이 두 군데를 오간다)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _VFader(
                height: faderH,
                value: master.vol,
                max: 1.6,
                color: _kMasterColor,
                onChanged: (v) {
                  master.vol = v;
                  onChanged();
                },
              ),
              const SizedBox(width: 6),
              _LevelMeter(host: host, vertical: true, length: faderH),
            ],
          ),
          _Readout(_dbText(master.vol)),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(5, 0, 5, 8),
            child: SizedBox(
              // 손가락만 하게 — 보이는 글자는 그대로고 눌리는 자리만 넓어진다
              height: 40,
              child: TextButton(
                onPressed: () {
                  master.vol = 1.0;
                  onChanged();
                },
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                child: const Text(
                  '0dB',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 스트립 껍데기 — 테두리·머리(이름/음색)까지. 세 종류 스트립이 같은 모양을 쓴다.
class _StripShell extends StatelessWidget {
  final double width;
  final Color color;
  final bool dimmed;
  final String title, subtitle;
  final VoidCallback? onTapHead;
  final List<Widget> children;

  const _StripShell({
    required this.width,
    required this.color,
    required this.dimmed,
    required this.title,
    required this.subtitle,
    required this.children,
    this.onTapHead,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: dimmed ? 0.03 : 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: dimmed ? 0.25 : 0.6)),
      ),
      child: Opacity(
        opacity: dimmed ? 0.55 : 1,
        child: Column(
          children: [
            GestureDetector(
              onTap: onTapHead,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.22),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(9),
                  ),
                ),
                child: Column(
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: onTapHead != null ? color : Colors.white54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 세로 페이더. 길이를 **밖에서 정해 준다** — 남는 높이를 전부 먹으면
/// 팬·잔향·M/S 가 아래로 밀려 잘린다(1차 버전이 그랬다).
class _VFader extends StatelessWidget {
  final double height, value, max;
  final Color color;
  final ValueChanged<double> onChanged;
  const _VFader({
    required this.height,
    required this.value,
    required this.max,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: RotatedBox(
        quarterTurns: 3,
        child: SliderTheme(
          data: SliderThemeData(
            trackHeight: 6,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
            activeTrackColor: color,
            thumbColor: color,
            inactiveTrackColor: Colors.white24,
          ),
          child: Slider(
            min: 0,
            max: max,
            value: value.clamp(0.0, max),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  final String text;
  const _Readout(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(
      text,
      maxLines: 1,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
  );
}

/// 라벨 + 값 + 짧은 슬라이더. 스트립이 좁아서 노브 그림보다 이게 읽기 쉽다.
class _MiniSlider extends StatelessWidget {
  final String label, display;
  final double value, min, max;
  final Color color;
  final ValueChanged<double> onChanged;
  const _MiniSlider({
    required this.label,
    required this.display,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 글자를 키우면 「울림」+값이 100dp 칸을 넘는다 — 이름 쪽이 줄어든다
              // (값은 숫자라 잘리면 뜻이 없어진다).
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, color: Colors.white38),
                ),
              ),
              Text(
                display,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
            ],
          ),
          // **줄어들 수 있어야 한다.** 이 슬라이더는 `Expanded` 안에 들어가는데,
          // 글자를 키운 작은 폰에서는 이름 줄이 커져서 30 을 다 못 준다(2px 넘쳤다).
          Flexible(
            child: SizedBox(
              height: 30,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3.5,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 16,
                  ),
                  activeTrackColor: color,
                  thumbColor: color,
                  inactiveTrackColor: Colors.white24,
                ),
                child: Slider(
                  min: min,
                  max: max,
                  value: value.clamp(min, max),
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  final String text;
  final bool on;
  final Color onColor;
  final VoidCallback onTap;
  final double height;
  const _Toggle({
    required this.text,
    required this.on,
    required this.onColor,
    required this.onTap,
    this.height = 40,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? onColor : Colors.white10,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w900,
            color: on ? Colors.black : Colors.white54,
          ),
        ),
      ),
    );
  }
}

class _AddTrack extends StatelessWidget {
  final double width;
  final ValueChanged<String> onAdd;
  const _AddTrack({required this.width, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            '＋악기',
            style: TextStyle(fontSize: 12.5, color: Colors.white70),
          ),
          const SizedBox(height: 10),
          for (final t in kTrackTypes)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
              child: SizedBox(
                width: double.infinity,
                height: 40, // 32 는 손가락에 비해 작다
                child: FilledButton.icon(
                  onPressed: () => onAdd(t),
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.white10,
                    foregroundColor: Colors.white, // 1차엔 보라색 글씨라 거의 안 보였다
                  ),
                  icon: Icon(kTrackTypeIcon[t] ?? Icons.music_note, size: 16),
                  label: Text(
                    kTrackTypeLabel[t] ?? t,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
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

// ══════════════════ 가로 — 채널당 한 줄 ══════════════════

const double _kRowH = 62;

/// 가로 한 줄의 공통 껍데기: [색 막대][이름/음색][가운데 컨트롤들]
class _RowShell extends StatelessWidget {
  final Color color;
  final String title, subtitle;
  final List<Widget> children;
  final double height;

  /// 트랙·라이브 줄은 각자 자기 모양을 그린다(볼륨을 크게 놓느라) — 이제 이 껍데기는
  /// **마스터 줄만** 쓴다. 남은 건 그 하나에 필요한 것뿐이다.
  const _RowShell({
    required this.color,
    required this.title,
    required this.subtitle,
    required this.children,
    this.height = _kRowH,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: height - 2,
            color: color.withValues(alpha: 0.9),
          ),
          SizedBox(
            width: 116,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Colors.white38,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

/// 가로 페이더 — 라벨 위, 슬라이더 아래. 세로 페이더와 달리 **길이가 넉넉하다**.
class _HControl extends StatelessWidget {
  final String label, display;
  final double value, min, max;
  final Color color;
  final int flex;
  final bool big;
  final ValueChanged<double> onChanged;

  const _HControl({
    required this.label,
    required this.display,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.onChanged,
    this.flex = 2,
    this.big = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 라벨과 값을 **붙여서 왼쪽에** 둔다. 양끝 정렬로 두면 값(100%)이 옆 칸의
            // 라벨(좌우) 바로 옆에 붙어서 어느 슬라이더의 값인지 헷갈린다.
            // 좁아지면 **글자가 작아진다**(잘리지 않는다). 줄 모양을 세로 화면에서도
            // 쓰게 하면서 칸이 400dp 를 5~6 등분한 폭이 됐다 — 원래는 800dp 기준이라
            // '볼륨 100%' 가 그대로 넘쳤다(시험이 42px 넘침으로 잡았다).
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 10, color: Colors.white38),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    display,
                    style: TextStyle(
                      fontSize: big ? 12.5 : 11,
                      fontWeight: FontWeight.w700,
                      color: big ? Colors.white : Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 26,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: big ? 5 : 3.5,
                  thumbShape: RoundSliderThumbShape(
                    enabledThumbRadius: big ? 10 : 8,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 16,
                  ),
                  activeTrackColor: color,
                  thumbColor: color,
                  inactiveTrackColor: Colors.white24,
                ),
                child: Slider(
                  min: min,
                  max: max,
                  value: value.clamp(min, max),
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 가로에서 한 줄로 붙일 때 이름·버튼 묶음은 **고정 폭**, 볼륨은 남는 폭을 다 쓴다.
/// 세로(한눈에)에서는 그대로 두 줄이다.
Widget _wrapHead(bool wide, Widget child) =>
    wide ? SizedBox(width: 280, child: child) : child;
Widget _wrapVol(bool wide, Widget child) =>
    wide ? Expanded(child: child) : child;

class _TrackRow extends StatelessWidget {
  /// 인서트를 오디오 쪽에 밀어 주려면 필요하다.
  final AudioClient? host;

  /// **가로로 누웠나.** 세로의 '한눈에' 보기도 같은 줄 위젯을 쓰므로
  /// 화면 크기를 여기서 재면 안 된다 — 부르는 쪽이 정해서 넘긴다.
  final bool wide;
  final Track track;
  final bool anySolo;
  final VoidCallback onChanged, onSolo;
  final VoidCallback? onRemove;

  const _TrackRow({
    super.key,
    required this.host,
    required this.wide,
    required this.track,
    required this.anySolo,
    required this.onChanged,
    required this.onSolo,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: track,
      builder: (context, _) {
        final c = _typeColor[track.type] ?? Colors.grey;
        final dimmed = track.mute || (anySolo && !track.solo);
        return Opacity(
          opacity: dimmed ? 0.6 : 1,
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(0, 6, 10, 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: dimmed ? 0.03 : 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: c.withValues(alpha: dimmed ? 0.22 : 0.5),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 5,
                  height: wide ? 34 : 62,
                  color: c.withValues(alpha: 0.9),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Flex(
                    // 가로로 누우면 폭이 남는다 → **이름·버튼·볼륨을 한 줄에**.
                    // 두 줄로 두면 줄 하나가 84dp 라 400dp 화면에 세 줄밖에 안 들어간다
                    // (그림으로 뽑아 보고 잡았다).
                    direction: wide ? Axis.horizontal : Axis.vertical,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 첫 줄 — 이름과 켜고 끄기
                      _wrapHead(
                        wide,
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => showChannelSheet(
                                  context,
                                  track: track,
                                  color: c,
                                  onChanged: onChanged,
                                  onSolo: onSolo,
                                  onRemove: onRemove,
                                  host: host,
                                ),
                                behavior: HitTestBehavior.opaque,
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        _trackName(track),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        _voiceName(track),
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
                              ),
                            ),
                            // **폭을 못 박는다.** 안 그러면 글자만 해서(14dp) 못 누른다.
                            SizedBox(
                              width: 34,
                              child: _Toggle(
                                text: 'M',
                                height: 30,
                                on: track.mute,
                                onColor: Colors.red.shade400,
                                onTap: () {
                                  track.mute = !track.mute;
                                  onSolo();
                                },
                              ),
                            ),
                            const SizedBox(width: 5),
                            SizedBox(
                              width: 34,
                              child: _Toggle(
                                text: 'S',
                                height: 30,
                                on: track.solo,
                                onColor: Colors.amber.shade500,
                                onTap: () {
                                  track.solo = !track.solo;
                                  onSolo();
                                },
                              ),
                            ),
                            const SizedBox(width: 5),
                            // 나머지 값(좌우·잔향·저음·고음)은 여기서 **크게** 만진다
                            GestureDetector(
                              onTap: () => showChannelSheet(
                                context,
                                track: track,
                                color: c,
                                onChanged: onChanged,
                                onSolo: onSolo,
                                onRemove: onRemove,
                                host: host,
                              ),
                              child: Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: const Icon(
                                  Icons.tune,
                                  size: 16,
                                  color: Colors.white60,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (wide) const SizedBox(width: 12),
                      // 둘째 줄 — **볼륨만** 큼직하게. 믹서에서 열에 아홉은 이것만 만진다.
                      _wrapVol(
                        wide,
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 30,
                                child: SliderTheme(
                                  data: SliderThemeData(
                                    trackHeight: 5,
                                    thumbShape: const RoundSliderThumbShape(
                                      enabledThumbRadius: 11,
                                    ),
                                    overlayShape: const RoundSliderOverlayShape(
                                      overlayRadius: 20,
                                    ),
                                    activeTrackColor: c,
                                    thumbColor: c,
                                    inactiveTrackColor: Colors.white24,
                                  ),
                                  child: Slider(
                                    min: 0,
                                    max: 1.4,
                                    value: track.vol.clamp(0, 1.4),
                                    onChanged: (v) {
                                      track.vol = v;
                                      onChanged();
                                    },
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 46,
                              child: Text(
                                '${(track.vol * 100).round()}%',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            // 줄 모양에서도 크기가 보여야 한다.
                            // 고정 폭을 주면 320dp 폰에서 줄이 넘친다 — 나눠 갖게 둔다.
                            Expanded(
                              flex: 2,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: _LevelMeter(
                                  host: host,
                                  vertical: false,
                                  length: double.infinity,
                                  bus: SceneSequencer.busOf(track),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LiveRow extends StatelessWidget {
  final LiveChannel live;
  final AudioClient? host;
  final VoidCallback onChanged;

  /// 트랙 줄과 같은 규칙 — 가로면 세 줄을 한 줄로 붙인다.
  final bool wide;
  const _LiveRow({
    required this.live,
    required this.host,
    required this.onChanged,
    required this.wide,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: live,
      builder: (context, _) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(0, 6, 10, 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _kLiveColor.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            Container(width: 5, height: wide ? 34 : 92, color: _kLiveColor),
            const SizedBox(width: 8),
            Expanded(
              child: Flex(
                direction: wide ? Axis.horizontal : Axis.vertical,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _wrapHead(
                    wide,
                    Row(
                      children: [
                        const Text(
                          '🎹 라이브',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            VOICE_LABEL[live.voice] ?? live.voice,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Colors.white38,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 30,
                          child: FilledButton(
                            onPressed: () =>
                                _pickVoice(context, live, onChanged),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              backgroundColor: _kLiveColor.withValues(
                                alpha: 0.2,
                              ),
                              foregroundColor: _kLiveColor,
                            ),
                            child: const Text(
                              '악기',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        SizedBox(
                          height: 30,
                          child: FilledButton(
                            onPressed: () => showLiveSheet(context, live, host),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              backgroundColor: _kLiveColor.withValues(
                                alpha: 0.14,
                              ),
                              foregroundColor: _kLiveColor,
                            ),
                            child: Text(
                              live.chain.isEmpty
                                  ? '이펙트'
                                  : '이펙트 ${live.chain.length}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (wide) const SizedBox(width: 12),
                  // 라이브는 만지는 값이 둘뿐이다 — **둘 다 큼직하게** 놓을 수 있다
                  _wrapVol(
                    wide,
                    _RowSlider(
                      label: '볼륨',
                      display: '${(live.vol * 100).round()}%',
                      value: live.vol,
                      max: 1.4,
                      color: _kLiveColor,
                      onChanged: (v) {
                        live.vol = v;
                        onChanged();
                      },
                    ),
                  ),
                  if (wide) const SizedBox(width: 12),
                  _wrapVol(
                    wide,
                    _RowSlider(
                      label: '울림',
                      display: '${(live.rev * 100).round()}%',
                      value: live.rev,
                      max: 1,
                      color: _kLiveColor,
                      onChanged: (v) {
                        live.rev = v;
                        onChanged();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 줄 안에 놓는 슬라이더 — 라벨(작게) + 손잡이 큰 슬라이더 + 값.
class _RowSlider extends StatelessWidget {
  final String label, display;
  final double value, max;
  final Color color;
  final ValueChanged<double> onChanged;
  const _RowSlider({
    required this.label,
    required this.display,
    required this.value,
    required this.max,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 30,
          child: Text(
            label,
            style: const TextStyle(fontSize: 10.5, color: Colors.white38),
          ),
        ),
        Expanded(
          child: SizedBox(
            height: 28,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
                activeTrackColor: color,
                thumbColor: color,
                inactiveTrackColor: Colors.white24,
              ),
              child: Slider(
                max: max,
                value: value.clamp(0, max),
                onChanged: onChanged,
              ),
            ),
          ),
        ),
        SizedBox(
          width: 46,
          child: Text(
            display,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

/// 라이브 이펙트 시트 — **손으로 치는 소리에만** 걸리는 플러그인 자리.
///
/// 엔진은 처음부터 되어 있었다(`live` 는 붙박이 버스라 인서트를 들고 있다).
/// 없던 것은 **꽂을 자리**뿐이었다 — 트랙·마스터에는 랙이 있는데 라이브만
/// 볼륨·울림 둘로 끝이었다. 반주 위에 얹어 치는 소리라 딜레이 하나로 달라진다.
void showLiveSheet(BuildContext context, LiveChannel live, AudioClient? host) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF16181C),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 5, height: 26, color: _kLiveColor),
                  const SizedBox(width: 8),
                  const Text(
                    '라이브 이펙트',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                '손으로 치는 소리에만 걸린다 — 반주는 안 지나간다.',
                style: TextStyle(fontSize: 12, color: Colors.white38),
              ),
              const SizedBox(height: 14),
              FxRack(owner: live, bus: 'live', host: host, color: _kLiveColor),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 마스터링 시트 — 마스터 인서트(그래픽 EQ · 컴프 · 리미터 …)를 꽂는 자리.
///
/// 트랙 시트와 같은 랙을 쓴다(`FxRack`). 다른 건 버스 이름뿐이다.
void showMasterSheet(
  BuildContext context,
  Project project,
  MasterChannel master,
  AudioClient? host,
) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF16181C),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(width: 5, height: 26, color: _kMasterColor),
                  const SizedBox(width: 8),
                  const Text(
                    '마스터링',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                '곡 전체에 걸린다 — 맨 마지막에 지나가는 자리다.',
                style: TextStyle(fontSize: 12, color: Colors.white38),
              ),
              const SizedBox(height: 14),
              FxRack(
                owner: master,
                bus: 'master',
                host: host,
                color: _kMasterColor,
              ),
              const SizedBox(height: 18),
              _DuckSection(project: project, host: host),
            ],
          ),
        ),
      ),
    ),
  );
}

/// **비켜주기(사이드체인 덕킹)** — 킥이 칠 때 나머지가 잠깐 눌린다.
///
/// 예전엔 장르가 정하는 고정값이었다(`kGenreDuck`) — 하우스·트랩은 세게,
/// 록·재즈는 0. 여기서 처음으로 **사용자가 직접 만지는 손잡이**가 된다.
/// 세기를 만지면 장르가 나중에 바뀌어도(스타일 바꾸기) 이 값이 이긴다
/// (`Project.duckAmountOverride`) — 복귀 시간은 처음부터 장르 몫이
/// 아니었다(`Project.duckRelSec`).
///
/// `FxRack` 의 플러그인처럼은 안 만들었다 — 이건 트랙 하나에 꽂는 인서트가
/// 아니라 **마스터 버스 전체의 사이드체인 라우팅**이라 자리가 다르다
/// (`Engine` 안에서 드럼을 뺀 나머지 버스에만 걸린다, `engine.dart` 참고).
class _DuckSection extends StatefulWidget {
  final Project project;
  final AudioClient? host;
  const _DuckSection({required this.project, required this.host});

  @override
  State<_DuckSection> createState() => _DuckSectionState();
}

class _DuckSectionState extends State<_DuckSection> {
  void _push() {
    final p = widget.project;
    widget.host?.setDuck(
      p.duckAmountOverride ?? (kGenreDuck[p.genre] ?? 0),
      relSec: p.duckRelSec,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.project;
    final genreDefault = kGenreDuck[p.genre] ?? 0;
    final amount = p.duckAmountOverride ?? genreDefault;
    final usingDefault = p.duckAmountOverride == null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 5, height: 20, color: _kMasterColor),
            const SizedBox(width: 8),
            const Text(
              '비켜주기(사이드체인)',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 2),
        const Text(
          '킥이 칠 때 나머지가 잠깐 눌린다 — 하우스·트랩에서 많이 쓰는 「펌핑」 느낌.',
          style: TextStyle(fontSize: 11.5, color: Colors.white38),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Text(
              '세기',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(
              usingDefault ? '${(amount * 100).round()}% (장르 기본)' : '${(amount * 100).round()}%',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _kMasterColor,
              ),
            ),
            const SizedBox(width: 10),
            // 되돌리기 — 사용자가 만졌던 값을 지우고 장르 기본값을 따르게.
            GestureDetector(
              onTap: usingDefault
                  ? null
                  : () => setState(() {
                      p.duckAmountOverride = null;
                      _push();
                    }),
              child: Icon(
                Icons.restart_alt,
                size: 17,
                color: usingDefault ? Colors.white12 : Colors.white38,
              ),
            ),
          ],
        ),
        SizedBox(
          height: 40,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
              activeTrackColor: _kMasterColor,
              thumbColor: _kMasterColor,
              inactiveTrackColor: Colors.white24,
            ),
            child: Slider(
              min: 0,
              max: 1,
              value: amount.clamp(0.0, 1.0),
              onChanged: (v) => setState(() {
                p.duckAmountOverride = v;
                _push();
              }),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            const Text(
              '복귀 시간',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            Text(
              '${(p.duckRelSec * 1000).round()}ms',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: _kMasterColor,
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: p.duckRelSec == 0.16
                  ? null
                  : () => setState(() {
                      p.duckRelSec = 0.16;
                      _push();
                    }),
              child: Icon(
                Icons.restart_alt,
                size: 17,
                color: p.duckRelSec == 0.16 ? Colors.white12 : Colors.white38,
              ),
            ),
          ],
        ),
        SizedBox(
          height: 40,
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
              activeTrackColor: _kMasterColor,
              thumbColor: _kMasterColor,
              inactiveTrackColor: Colors.white24,
            ),
            child: Slider(
              // 40ms 보다 짧으면 딸꾹질처럼 들리고, 400ms 보다 길면 늘 눌린
              // 채로 들린다(`Engine.duckRelSec` 문서와 같은 범위 감각).
              min: 0.04,
              max: 0.4,
              value: p.duckRelSec.clamp(0.04, 0.4),
              onChanged: (v) => setState(() {
                p.duckRelSec = v;
                _push();
              }),
            ),
          ),
        ),
      ],
    );
  }
}

class _MasterRow extends StatelessWidget {
  final Project project;
  final MasterChannel master;
  final AudioClient? host;
  final VoidCallback onChanged;
  const _MasterRow({
    required this.project,
    required this.master,
    required this.host,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: master,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        child: _RowShell(
          color: _kMasterColor,
          title: 'MASTER',
          subtitle: '전체 출력',
          height: 58,
          children: [
            // 마스터링 — 곡 전체에 거는 플러그인 자리
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                height: 34,
                child: FilledButton(
                  onPressed: () => showMasterSheet(context, project, master, host),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    backgroundColor: _kMasterColor.withValues(alpha: 0.2),
                    foregroundColor: _kMasterColor,
                  ),
                  child: Text(
                    master.chain.isEmpty
                        ? '마스터링'
                        : '마스터링 ${master.chain.length}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
            _HControl(
              label: '전체 볼륨',
              display: _dbText(master.vol),
              value: master.vol,
              min: 0,
              max: 1.6,
              color: _kMasterColor,
              flex: 8,
              big: true,
              onChanged: (v) {
                master.vol = v;
                onChanged();
              },
            ),
            // 줄 모양에서도 크기가 보여야 한다 — 「왜 찌그러지지」를 귀로만
            // 알아내게 두면 안 된다.
            // **고정 폭을 주면 안 된다** — 320dp 폰에서 줄이 50px 넘쳤다.
            // 자리를 나눠 갖게 두면 좁은 화면에서는 미터가 좁아질 뿐 안 잘린다.
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _LevelMeter(
                  host: host,
                  vertical: false,
                  length: double.infinity,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                height: 40,
                child: TextButton(
                  onPressed: () {
                    master.vol = 1.0;
                    onChanged();
                  },
                  child: const Text(
                    '0dB',
                    style: TextStyle(fontSize: 11.5, color: Colors.white38),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddRow extends StatelessWidget {
  final ValueChanged<String> onAdd;
  const _AddRow({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Text(
            '＋악기',
            style: TextStyle(fontSize: 12.5, color: Colors.white70),
          ),
          const SizedBox(width: 12),
          for (final t in kTrackTypes)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: FilledButton(
                  onPressed: () => onAdd(t),
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.white10,
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    kTrackTypeLabel[t] ?? t,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

/// 크기 → 막대 길이(0~1). **dB 로 그린다** — 소리는 배수가 아니라 dB 로 들린다.
///
/// 배수로 그리면 조용한 곡이 늘 바닥에 붙어 보인다(절반 크기 = −6dB 인데 막대는
/// 절반이 된다). −36dB 아래는 안 그린다 — 거기는 사실상 무음이다.
/// 0dB(1.0)는 36/42 자리라, 넘치면 눈금 위로 올라간다.
///
/// 화면에서 떼어 놔야 시험할 수 있어 여기에 둔다.
double meterFrac(double v) {
  if (v <= 0) return 0;
  final db = 20 * (math.log(v) / math.ln10);
  return ((db + 36) / 42).clamp(0.0, 1.0); // −36dB ~ +6dB
}

/// 마스터 레벨 미터 — **지금 얼마나 크게 나가고 있는가.**
///
/// 믹서에 페이더만 있고 소리 크기를 알려 주는 것이 하나도 없었다. 그러면
/// 「왜 찌그러지지」·「왜 작지」를 **귀로만** 알아내야 한다. 값은 처음부터
/// 엔진이 보내고 있었다(`AudioStats.peakOut`) — 개발용 시험 화면에만 있었을 뿐이다.
///
/// `peakOut` 은 **리미터 전** 봉우리다. 1.0(0dB)을 넘으면 리미터가 붙잡고 있다는
/// 뜻이고, 그게 계속되면 소리가 눌려서 답답해진다. 그래서 1.0 자리에 눈금을 긋는다.
class _LevelMeter extends StatefulWidget {
  final AudioClient? host;

  /// 세로 스트립이면 true — 가로 줄에서는 눕혀 그린다.
  final bool vertical;
  final double length;

  /// 어느 버스를 볼 것인가. null 이면 **마스터**(리미터 전 봉우리).
  /// 트랙 이름은 `SceneSequencer.busOf` 가 정하는 그것이다.
  final String? bus;
  const _LevelMeter({
    required this.host,
    required this.vertical,
    required this.length,
    this.bus,
  });

  @override
  State<_LevelMeter> createState() => _LevelMeterState();
}

class _LevelMeterState extends State<_LevelMeter> {
  StreamSubscription<AudioStats>? _sub;
  double _peak = 0;

  /// **봉우리는 천천히 내려온다.** 지표는 250ms 마다 오는데 그때마다 값이 확 떨어지면
  /// 눈으로 읽을 수가 없다(깜빡이는 막대는 안 보는 것과 같다).
  double _hold = 0;

  @override
  void initState() {
    super.initState();
    _sub = widget.host?.statsStream.listen((s) {
      if (!mounted) return;
      final v = widget.bus == null ? s.peakOut : (s.busPeaks[widget.bus] ?? 0);
      setState(() {
        _peak = v;
        _hold = _peak > _hold ? _peak : _hold * 0.72;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = meterFrac(_peak);
    final h = meterFrac(_hold);
    // 1.0(0dB) 자리 — 여기를 넘으면 리미터가 붙잡는다
    const zero = 36 / 42;
    final over = _hold > 1.0;
    final bar = LayoutBuilder(
      builder: (context, c) {
        final len = widget.vertical ? c.maxHeight : c.maxWidth;
        Widget fill(double frac, Color color, {double thick = 0}) => Positioned(
          left: widget.vertical ? 0 : 0,
          bottom: 0,
          child: Container(
            width: widget.vertical ? c.maxWidth : len * frac,
            height: widget.vertical ? len * frac : c.maxHeight,
            color: color,
          ),
        );
        return Stack(
          children: [
            fill(f, over ? Colors.orange.shade400 : Colors.tealAccent.shade400),
            // 봉우리 자국 — 지나간 제일 큰 값
            Positioned(
              left: widget.vertical ? 0 : len * h - 1,
              bottom: widget.vertical ? len * h - 1 : 0,
              child: Container(
                width: widget.vertical ? c.maxWidth : 2,
                height: widget.vertical ? 2 : c.maxHeight,
                color: over ? Colors.red.shade300 : Colors.white70,
              ),
            ),
            // 0dB 눈금
            Positioned(
              left: widget.vertical ? 0 : len * zero,
              bottom: widget.vertical ? len * zero : 0,
              child: Container(
                width: widget.vertical ? c.maxWidth : 1,
                height: widget.vertical ? 1 : c.maxHeight,
                color: Colors.white24,
              ),
            ),
          ],
        );
      },
    );
    return Container(
      width: widget.vertical ? 7 : widget.length,
      height: widget.vertical ? widget.length : 7,
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(3),
      ),
      clipBehavior: Clip.hardEdge,
      child: bar,
    );
  }
}
