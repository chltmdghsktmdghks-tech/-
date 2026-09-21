// 씬의 **코드 진행**을 한자리에서 보고 고치는 서랍.
//
// 여태 화성을 바꾸려면 코드 패턴을 열어 고치고, 베이스를 열어 같은 만큼 옮기고,
// 멜로디도 다시 맞춰야 했다 — 세 군데를 손으로 맞추는 일이다. 여기서는 코드
// 하나를 누르면 그 구간의 베이스·멜로디가 **도수 차만큼 같이** 옮겨진다
// (셈은 `prog_ops.dart` 와 `Project.changeChord` 가 한다).
//
// 고를 수 있는 것은 **그 조의 다이아토닉 7개뿐**이다. 스물넷을 다 내놓으면
// 「무엇을 눌러야 하지」가 되고, 일곱은 아무거나 눌러도 어울린다 —
// 옛 앱이 「조에 맞는 7개 — 아무거나 눌러도 어울립니다」라고 적어 둔 그 자리다.

import 'package:flutter/material.dart';

import '../audio_isolate.dart';
import '../engine.dart' show noteNameIn;
import '../prog_ops.dart';
import '../project.dart';
import '../synth.dart' show kPartLive;
import '../theory.dart';

/// 다이아토닉 번호 → 사람이 읽는 코드 이름(`Am`·`F`·`Bdim`).
///
/// [type] 을 주면 그 조의 **뿌리음은 그대로 두고 종류만 갈아** 이름을 짓는다 —
/// 편집기의 코드 종류 서랍이 「이걸 고르면 무슨 코드가 되나」를 보여 줄 때 쓴다.
String chordNameOf(int degree, MusicKey key, {String? type}) {
  final list = diatonicChords(key);
  if (degree < 0 || degree >= list.length) return '?';
  final spec = list[degree];
  // 음이름에는 옥타브 번호가 붙어 온다(`A3`) — 코드 이름에는 필요 없다.
  final base = noteNameIn(
    spec.root + 60,
    key.root,
    key.mode,
  ).replaceAll(RegExp(r'-?\d+$'), '');
  return base + (kChordSuffix[type ?? spec.type] ?? '');
}

/// 미리 들려줄 때 쓸 **음색** — 코드 트랙 것이다.
///
/// 패드로 만든 곡에서 피아노가 나면 **딴 곡 소리**다. 견주려고 눌러 보는 것인데
/// 견줄 수가 없어진다. 코드 트랙이 없으면(드럼만 있는 씬) 패드로 낸다.
String chordVoiceOf(Project p) {
  for (final t in p.tracks) {
    if (t.type == 'chord') return t.voice;
  }
  return 'pad';
}

Future<void> showProgSheet(
  BuildContext context, {
  required Project project,
  required Transport transport,
  required AudioClient? host,
  required VoidCallback onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1A1A1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => _ProgBody(
      project: project,
      transport: transport,
      host: host,
      onChanged: onChanged,
    ),
  );
}

class _ProgBody extends StatefulWidget {
  final Project project;
  final Transport transport;
  final AudioClient? host;
  final VoidCallback onChanged;
  const _ProgBody({
    required this.project,
    required this.transport,
    required this.host,
    required this.onChanged,
  });

  @override
  State<_ProgBody> createState() => _ProgBodyState();
}

class _ProgBodyState extends State<_ProgBody> {
  /// 되돌릴 것들 — **서랍 안에** 둔다.
  ///
  /// 처음엔 씬 지우기처럼 스낵바로 냈다. 그런데 서랍이 열려 있는 동안 스낵바는
  /// 서랍의 **막(barrier) 아래**에 깔린다 — 「되돌리기」를 눌러도 서랍이 닫힐 뿐
  /// 아무 일도 안 일어났다(시험이 잡았다). 닿지 않는 되돌리기는 없는 것과 같다.
  final List<(ProgUndo, String)> _undos = [];

  /// 그 코드를 **한 번 들려준다.**
  ///
  /// 「4도가 뭐지」를 글자로는 못 안다 — 눌러서 소리가 나야 고를 수 있다.
  /// 코드 트랙의 음색으로 낸다(패드로 만든 곡에서 피아노가 나면 딴 곡 같다).
  void _hear(int degree) {
    final h = widget.host;
    if (h == null) return;
    final key = MusicKey(
      root: widget.transport.root,
      mode: widget.transport.mode,
    );
    h.batch([
      for (final f in chordFreqsOf(diatonicChords(key)[degree % 7]))
        [chordVoiceOf(widget.project), f, 0.9, 3, true, 0.0, 0.0, kPartLive],
    ]);
  }

  void _pick(ProgSlot slot) {
    _hear(slot.degree); // 지금 걸린 코드부터 들려준다 — 견줄 것이 있어야 고른다
    final key = MusicKey(
      root: widget.transport.root,
      mode: widget.transport.mode,
    );
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${slot.label} 코드',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                '조에 맞는 7개 — 아무거나 눌러도 어울립니다',
                style: TextStyle(fontSize: 11.5, color: Colors.white54),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (var d = 0; d < 7; d++)
                    _Cell(
                      top: '${d + 1}도',
                      big: chordNameOf(d, key),
                      picked: d == slot.degree,
                      onTap: () {
                        Navigator.pop(ctx);
                        _hear(d);
                        _apply(slot, d);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _apply(ProgSlot slot, int to) {
    if (to == slot.degree) return;
    final key = MusicKey(
      root: widget.transport.root,
      mode: widget.transport.mode,
    );
    final was = chordNameOf(slot.degree, key);
    final now = chordNameOf(to, key);
    final undo = widget.project.changeChord(
      slot,
      to,
      mode: widget.transport.mode,
    );
    if (undo == null) return;
    widget.onChanged(); // 다음 판부터 새 화성으로 — 안 부르면 화면만 바뀐다
    setState(() => _undos.add((undo, '${slot.label} $was → $now')));
  }

  void _undo() {
    if (_undos.isEmpty) return;
    final (u, _) = _undos.removeLast();
    widget.project.undoChangeChord(u);
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final key = MusicKey(
      root: widget.transport.root,
      mode: widget.transport.mode,
    );
    final (slots, _) = widget.project.readSceneProg();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '코드 진행 — ${widget.project.scene.name}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              slots.isEmpty
                  ? '이 씬에는 화음이 없습니다. 화음 악기(피아노·패드…)에 판을 하나 골라 주세요.'
                  : '하나를 누르면 베이스·멜로디도 같이 옮겨집니다.',
              style: const TextStyle(fontSize: 11.5, color: Colors.white54),
            ),
            if (_undos.isNotEmpty) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _undo,
                child: Container(
                  height: 34, // 손가락 바닥선
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.undo, size: 15, color: Colors.white70),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '되돌리기 — ${_undos.last.$2}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (slots.isNotEmpty)
              ConstrainedBox(
                // 가로로 누운 폰에서도 서랍이 화면을 안 넘게 한다.
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final s in slots)
                        _Cell(
                          top: s.label,
                          big: chordNameOf(s.degree, key),
                          sub: '${s.degree + 1}도',
                          picked: false,
                          onTap: () => _pick(s),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String top;
  final String big;
  final String? sub;
  final bool picked;
  final VoidCallback onTap;
  const _Cell({
    required this.top,
    required this.big,
    this.sub,
    required this.picked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 78,
        height: 62, // 손가락 바닥선을 넉넉히 넘긴다
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: picked ? Colors.indigo.shade400 : Colors.white10,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: picked ? Colors.white70 : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              top,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9.5, color: Colors.white38),
            ),
            Text(
              big,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: picked ? Colors.white : Colors.white,
              ),
            ),
            if (sub != null)
              Text(
                sub!,
                maxLines: 1,
                style: const TextStyle(fontSize: 9.5, color: Colors.white38),
              ),
          ],
        ),
      ),
    );
  }
}
