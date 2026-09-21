// 인서트 랙 · 플러그인 창 (5단계 46/N) — 로직의 플러그인 방식.
//
// ── 화면을 열넷 그리지 않는다 ──
// 플러그인마다 손잡이 화면을 따로 만들면 화면 열네 개를 따로 관리하게 된다.
// 그래서 **플러그인이 자기 손잡이를 설명하고**(`fx.dart` 의 `FxParam`) 이 화면이
// 그 설명을 읽어 손잡이를 만든다. 새 플러그인을 더해도 여기 코드는 안 는다.
//
// ── 로직과 같은 규칙 ──
//   · 칸을 누르면 그 플러그인 창이 열린다
//   · 전원 버튼으로 끈다(빼는 게 아니라 지나가게만 한다 — 켜고 끄며 비교한다)
//   · 끌어서 순서를 바꾼다. **순서가 곧 소리다**

import 'package:flutter/material.dart';

import '../audio_isolate.dart';
import '../fx.dart';
import '../project.dart';
import '../sequencer.dart';

/// 채널 하나의 인서트 목록. 채널 시트 안에 들어간다.
class FxRack extends StatefulWidget {
  /// 트랙이든 마스터든 — 화면은 [FxChainOwner] 만 안다.
  final FxChainOwner owner;

  /// 오디오 쪽 버스 이름. 마스터는 'master'.
  final String bus;
  final AudioClient? host;
  final Color color;
  const FxRack({
    super.key,
    required this.owner,
    required this.bus,
    required this.host,
    required this.color,
  });

  /// 트랙용 — 버스 이름을 시퀀서 규칙에서 가져온다.
  factory FxRack.forTrack({
    Key? key,
    required Track track,
    required AudioClient? host,
    required Color color,
  }) => FxRack(
    key: key,
    owner: track,
    bus: SceneSequencer.busOf(track),
    host: host,
    color: color,
  );

  @override
  State<FxRack> createState() => _FxRackState();
}

class _FxRackState extends State<FxRack> {
  FxChainOwner get t => widget.owner;
  String get bus => widget.bus;

  /// 목록이 바뀌면 **통째로** 다시 보낸다(순서가 바뀌었을 수 있다).
  void _push() {
    widget.host?.setInserts(bus, [for (final f in t.chain) f.toJson()]);
    setState(() {});
  }

  Future<void> _add() async {
    final type = await showFxPicker(context);
    if (type == null) return;
    t.addFx(type);
    _push();
    if (!mounted) return;
    // 꽂자마자 창을 연다 — 꽂고 나서 다시 찾아 누르게 하면 두 번 일이다
    await showFxWindow(
      context,
      t,
      bus,
      t.chain.length - 1,
      widget.host,
      widget.color,
    );
    _push();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t as Listenable,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '인서트',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              const SizedBox(width: 8),
              Text(
                '${t.chain.length}개 · 위에서 아래 순서로 지나갑니다',
                style: const TextStyle(fontSize: 11, color: Colors.white38),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // ── 원탭 프리셋 ──
          //
          // 목록을 열면 amp·delay·reverb·geq·limiter·drive·bassamp·comp 여덟 개다.
          // **무엇을 왜 꽂아야 하는지 모르면 아무것도 못 꽂는다.** 이 앱을 쓰는
          // 사람은 대개 그쪽이고, 대신 「노래하듯」·「따뜻하게」는 안다.
          // 꽂고 나면 손잡이는 그대로 다 있으니 만져 보며 배울 수도 있다.
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final ps
                    in bus == 'master' ? kMasterFxPresets : kTrackFxPresets)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _PresetChip(
                      preset: ps,
                      color: widget.color,
                      onTap: () {
                        applyFxPreset(t, ps);
                        _push();
                        ScaffoldMessenger.of(context)
                          ..clearSnackBars()
                          ..showSnackBar(
                            SnackBar(
                              content: Text(
                                ps.chain.isEmpty
                                    ? '전부 뺐습니다'
                                    : '「${ps.name}」 — ${ps.desc}',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                              behavior: SnackBarBehavior.floating,
                              duration: const Duration(seconds: 3),
                            ),
                          );
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (t.chain.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                '아직 아무것도 안 꽂았습니다.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            )
          else
            ReorderableListView(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              onReorderItem: (from, to) {
                t.moveFx(from, to);
                _push();
              },
              children: [
                for (var i = 0; i < t.chain.length; i++)
                  _Slot(
                    key: ObjectKey(t.chain[i]),
                    index: i,
                    slot: t.chain[i],
                    color: widget.color,
                    onOpen: () async {
                      await showFxWindow(
                        context,
                        t,
                        bus,
                        i,
                        widget.host,
                        widget.color,
                      );
                      _push();
                    },
                    onToggle: () {
                      t.setFxOn(i, !t.chain[i].on);
                      widget.host?.setFxOn(bus, i, t.chain[i].on);
                      setState(() {});
                    },
                    onRemove: () {
                      t.removeFx(i);
                      _push();
                    },
                  ),
              ],
            ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: OutlinedButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add, size: 19),
              label: const Text(
                '인서트 꽂기',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: widget.color,
                side: BorderSide(color: widget.color.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 인서트 한 칸 — 전원 · 이름 · 손잡이 · 빼기.
class _Slot extends StatelessWidget {
  final int index;
  final FxSlot slot;
  final Color color;
  final VoidCallback onOpen, onToggle, onRemove;
  const _Slot({
    super.key,
    required this.index,
    required this.slot,
    required this.color,
    required this.onOpen,
    required this.onToggle,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final def = kFxCatalog[slot.type];
    final on = slot.on;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          // 전원 — 끄면 지나가기만 한다(빼는 게 아니다). 켜고 끄며 비교하는 게 믹싱이다.
          GestureDetector(
            onTap: onToggle,
            child: Container(
              width: 38,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? color.withValues(alpha: 0.25) : Colors.white10,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(8),
                ),
              ),
              child: Icon(
                Icons.power_settings_new,
                size: 17,
                color: on ? color : Colors.white24,
              ),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: GestureDetector(
              onTap: onOpen,
              behavior: HitTestBehavior.opaque,
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                alignment: Alignment.centerLeft,
                color: Colors.white10,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        def?.name ?? slot.type,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: on ? Colors.white : Colors.white38,
                        ),
                      ),
                    ),
                    Text(
                      _summary(slot, def),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.white38,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          // 끌어서 순서 바꾸기 — 순서가 곧 소리다
          ReorderableDragStartListener(
            index: index,
            child: Container(
              width: 34,
              height: 42,
              alignment: Alignment.center,
              color: Colors.white10,
              child: const Icon(
                Icons.drag_indicator,
                size: 18,
                color: Colors.white38,
              ),
            ),
          ),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 34,
              height: 42,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Colors.white10,
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(8),
                ),
              ),
              child: Icon(Icons.close, size: 17, color: Colors.red.shade300),
            ),
          ),
        ],
      ),
    );
  }

  /// 칸에 한 줄로 보일 요약 — 창을 안 열어도 지금 무엇으로 걸려 있는지 안다.
  static String _summary(FxSlot s, FxDef? def) {
    if (def == null) return '';
    // 고르는 손잡이(성향·방식)가 있으면 그걸 보여 준다 — 제일 큰 차이라서.
    for (final p in def.params) {
      if (p.choices != null) {
        return p.show(s.p[p.key] ?? p.def);
      }
    }
    final first = def.params.first;
    return first.show(s.p[first.key] ?? first.def);
  }
}

/// 플러그인 묶음(`FxDef.group`) 아이콘 — 이름만 죽 늘어놓으면 뭐가 뭔지
/// 훑어보기 어렵다(사용자 요청, 2026-09-16: "플러그인 아이콘표기").
const Map<String, IconData> _kFxGroupIcon = {
  '밴드': Icons.bolt,
  '공간': Icons.blur_on,
  'EQ': Icons.equalizer,
  '다이내믹': Icons.compress,
  '두께': Icons.layers,
  '모듈레이션': Icons.waves,
  '로파이': Icons.grain,
  '마스터링': Icons.tune,
};

/// 꽂을 플러그인 고르기 — 묶음별로 보여 준다.
Future<String?> showFxPicker(BuildContext context) {
  final groups = <String, List<FxDef>>{};
  for (final d in kFxCatalog.values) {
    (groups[d.group] ??= []).add(d);
  }
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: const Color(0xFF16181C),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '무엇을 꽂을까요',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 14),
              for (final g in groups.entries) ...[
                Row(
                  children: [
                    Icon(
                      _kFxGroupIcon[g.key] ?? Icons.tune,
                      size: 13,
                      color: Colors.white38,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      g.key,
                      style: const TextStyle(fontSize: 12, color: Colors.white38),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final d in g.value)
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx, d.type),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            d.name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// 플러그인 창 — 손잡이는 **플러그인 설명을 읽어** 만든다.
Future<void> showFxWindow(
  BuildContext context,
  FxChainOwner track,
  String bus,
  int index,
  AudioClient? host,
  Color color,
) {
  final slot = track.chain[index];
  final def = kFxCatalog[slot.type];
  if (def == null) return Future.value();

  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF16181C),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.88,
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
                      child: Text(
                        def.name,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    // 창 안에서도 끄고 켠다 — 걸기 전후를 바로 견준다
                    GestureDetector(
                      onTap: () {
                        track.setFxOn(index, !slot.on);
                        host?.setFxOn(bus, index, slot.on);
                        setSheet(() {});
                      },
                      child: Container(
                        width: 44,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: slot.on
                              ? color.withValues(alpha: 0.25)
                              : Colors.white10,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.power_settings_new,
                          size: 18,
                          color: slot.on ? color : Colors.white24,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final p in def.params)
                  _Knob(
                    param: p,
                    value: slot.p[p.key] ?? p.def,
                    color: color,
                    onChanged: (v) {
                      track.setFxParam(index, p.key, v);
                      host?.setFxParam(bus, index, p.key, v);
                      setSheet(() {});
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// 손잡이 하나 — 고르는 것이면 칩, 아니면 큰 슬라이더.
class _Knob extends StatelessWidget {
  final FxParam param;
  final double value;
  final Color color;
  final ValueChanged<double> onChanged;
  const _Knob({
    required this.param,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final choices = param.choices;
    if (choices != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              param.label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < choices.length; i++)
                  GestureDetector(
                    onTap: () => onChanged(i.toDouble()),
                    // `alignment` 를 주면 **최대 폭으로 늘어난다** — 칩 셋이
                    // 한 줄에 하나씩 늘어졌다(이 프로젝트에서 세 번째 겪는 함정이다).
                    // 가운데 정렬은 Row(mainAxisSize: min) 로 한다.
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: value.round() == i
                            ? color.withValues(alpha: 0.30)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(9),
                        border: value.round() == i
                            ? Border.all(color: color.withValues(alpha: 0.7))
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            choices[i],
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: value.round() == i
                                  ? Colors.white
                                  : Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                param.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                param.show(value),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(width: 10),
              // 되돌리기 — 손으로 기본값을 정확히 맞추기는 어렵다
              GestureDetector(
                onTap: () => onChanged(param.def),
                child: const Icon(
                  Icons.restart_alt,
                  size: 17,
                  color: Colors.white38,
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
                activeTrackColor: color,
                thumbColor: color,
                inactiveTrackColor: Colors.white24,
              ),
              child: Slider(
                min: param.min,
                max: param.max,
                value: value.clamp(param.min, param.max),
                onChanged: onChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 프리셋 칩 하나 — **결과의 이름**으로 부른다(플러그인 이름이 아니라).
class _PresetChip extends StatelessWidget {
  final FxPresetDef preset;
  final Color color;
  final VoidCallback onTap;
  const _PresetChip({
    required this.preset,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final off = preset.chain.isEmpty;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34, // 손가락 바닥선
        padding: const EdgeInsets.symmetric(horizontal: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: off ? Colors.white10 : color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: off ? Colors.white24 : color.withValues(alpha: 0.55),
          ),
        ),
        child: Text(
          preset.name,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: off ? Colors.white38 : color,
          ),
        ),
      ),
    );
  }
}
