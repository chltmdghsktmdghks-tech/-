// 프로젝트 설정 — **스타일·느낌·조를 한곳에 모았다** (2026-09).
//
// 여태는 씬 화면 위쪽에 "스타일 고르기"·"느낌"·"조" 칩이 늘 떠 있었다
// (타임라인에는 스타일 줄이 따로 하나 더 있었다) — 정작 만드는 동안 늘
// 만지는 값이 아닌데도 화면을 늘 차지했다. 여기 한 곳에 모아 톱니바퀴
// 뒤로 접어 둔다. 박자는 따로 없다 — 스타일이 정하는 값이라
// (`showCreateSheet` 의 박자 필터가 그 자리다) 스타일 고르기 안에 이미
// 들어 있다.
//
// **스타일 고르기가 편성은 안 건드린다(2026-09).** 처음엔 `setGenre` 를
// 그대로 불러 트랙·씬·패턴까지 통째로 갈아치웠다 — 그런데 여기는 이미 만든
// 곡을 잠깐 다른 느낌으로 들어 보려고 여는 자리다. 편성까지 날아가면
// "구경만 하려던" 손짓이 곡을 갈아엎는 사고가 된다. 그래서 **박자(빠르기·
// 시간표기)와 마스터링(장르별 자동 마스터링, `fx.dart`)만** 바꾸고, 트랙·씬·
// 패턴은 손대지 않는다.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../fx.dart' show masterPresetForGenre;
import '../genres.dart' show genreDef;
import '../presets.dart' show songGenreOf;
import '../project.dart';
import 'create_sheet.dart';
import 'feel_sheet.dart';

/// 프로젝트 설정을 연다. **재생 중이어도 그 자리에서 바로 들린다.**
void showProjectSettingsSheet(
  BuildContext context, {
  required Project project,
  required Transport transport,
  required MasterChannel master,
  required VoidCallback onChanged,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF16181C),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => _ProjectSettingsBody(
      project: project,
      transport: transport,
      master: master,
      onChanged: onChanged,
    ),
  );
}

class _ProjectSettingsBody extends StatelessWidget {
  final Project project;
  final Transport transport;
  final MasterChannel master;
  final VoidCallback onChanged;
  const _ProjectSettingsBody({
    required this.project,
    required this.transport,
    required this.master,
    required this.onChanged,
  });

  /// 스타일 고르기 — **편성(트랙·씬·패턴)은 그대로 두고, 박자(빠르기·시간
  /// 표기)와 마스터링만** 그 스타일 것으로 바꾼다. 조(key)도 안 건드린다 —
  /// 그건 아래 「조」 항목의 몫이다.
  Future<void> _pickStyle(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await showCreateSheet(context, current: project.genre);
    if (picked == null || picked == project.genre) return;

    // 되돌리기용 — 편성은 안 바뀌니 이 넷만 있으면 충분하다.
    final prevGenre = project.genre;
    final prevMeter = project.meter;
    final prevBpm = transport.bpm;
    final prevMasterChain = [
      for (final f in master.chain)
        FxSlot(f.type, on: f.on, params: Map<String, double>.from(f.p)),
    ];
    final prevMasterAuto = master.fxAuto;

    final gd = genreDef(picked);
    final g = songGenreOf(picked);
    project.genre = picked;
    project.meter = gd.meter;
    transport.bpm = g.$3;
    master.fxAuto = true;
    master.applyGenrePreset(masterPresetForGenre(picked));
    onChanged();

    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '스타일을 ${g.$2}로 바꿨습니다 — 박자·마스터링만 바뀌고 편성은 그대로입니다',
          style: const TextStyle(fontSize: 12.5),
        ),
        duration: const Duration(milliseconds: 3000),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '되돌리기',
          onPressed: () {
            project.genre = prevGenre;
            project.meter = prevMeter;
            transport.bpm = prevBpm;
            master.chain
              ..clear()
              ..addAll(prevMasterChain);
            master.fxAuto = prevMasterAuto;
            onChanged();
          },
        ),
      ),
    );
  }

  /// 느낌 만지기 — `showFeelSheet` 는 자기 시트라 이 시트 위에 겹쳐 연다.
  /// **만지는 대로 바로 들린다**(닫아야 반영되면 무슨 소리인지 못 듣는다).
  Future<void> _pickFeel(BuildContext context) async {
    await showFeelSheet(
      context,
      value: project.feel,
      onChanged: (f) {
        project.setFeel(f);
        onChanged();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([project, transport]),
      builder: (context, _) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '프로젝트 설정',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 16),

              const _Head('스타일', '박자·빠르기·편성까지 한 번에 바뀝니다'),
              _SettingRow(
                label: project.genre.isEmpty
                    ? '빈 프로젝트'
                    : songGenreOf(project.genre).$2,
                onTap: () => _pickStyle(context),
              ),
              const SizedBox(height: 18),

              const _Head('빠르기', '-/+ 로 밀거나 숫자를 눌러 바로 입력합니다'),
              _BpmEditor(
                transport: transport,
                project: project,
                onChanged: onChanged,
              ),
              const SizedBox(height: 18),

              const _Head('느낌', '신남·빽빽함 같은 결과를 손잡이 다섯 개로 만집니다'),
              _SettingRow(
                label: project.feel.chipWord,
                onTap: () => _pickFeel(context),
              ),
              const SizedBox(height: 18),

              const _Head('조', '바꾸면 모든 악기가 같이 옮겨 갑니다 — 곡은 그대로입니다'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < kKeyNames.length; i++)
                    _Chip(
                      text: transport.mode == 'minor'
                          ? kMinorKeyNames[i]
                          : kMajorKeyNames[i],
                      on: transport.root == i,
                      onTap: () {
                        transport.root = i;
                        onChanged();
                      },
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _Chip(
                    text: '단조 (어둡다)',
                    on: transport.mode == 'minor',
                    onTap: () {
                      transport.mode = 'minor';
                      onChanged();
                    },
                  ),
                  const SizedBox(width: 6),
                  _Chip(
                    text: '장조 (밝다)',
                    on: transport.mode == 'major',
                    onTap: () {
                      transport.mode = 'major';
                      onChanged();
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
}

class _Head extends StatelessWidget {
  final String title, sub;
  const _Head(this.title, this.sub);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          Text(sub, style: const TextStyle(fontSize: 11.5, color: Colors.white38)),
        ],
      ),
    );
  }
}

/// 빠르기 — 손가락으로 미는 슬라이더 대신 **-/+ 버튼과 직접 입력 칸**.
/// 슬라이더는 정확히 원하는 값(예: 92)에 맞추기 어렵다 — 숫자를 직접 치는 게
/// 더 빠르고 정확하다.
class _BpmEditor extends StatefulWidget {
  final Transport transport;
  final Project project;
  final VoidCallback onChanged;
  const _BpmEditor({
    required this.transport,
    required this.project,
    required this.onChanged,
  });

  @override
  State<_BpmEditor> createState() => _BpmEditorState();
}

class _BpmEditorState extends State<_BpmEditor> {
  late final TextEditingController _ctrl;
  late final FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.transport.bpm.round().toString());
    _focus = FocusNode()..addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _set(num v) {
    final clamped = v.clamp(40, 240).roundToDouble();
    widget.project.setBpm(widget.transport, clamped);
    _ctrl.text = clamped.round().toString();
    widget.onChanged();
  }

  /// 입력칸에서 포커스를 뗄 때(또는 완료를 누를 때) 적는다 — 매 글자마다
  /// 반영하면 "92" 를 치는 중간에 "9" 로 한 번 재생되다 튄다.
  void _commit() {
    final v = int.tryParse(_ctrl.text);
    if (v == null) {
      _ctrl.text = widget.transport.bpm.round().toString();
      return;
    }
    _set(v);
  }

  @override
  Widget build(BuildContext context) {
    // 스타일 바꾸기가 빠르기를 같이 바꿀 수 있다 — 지금 타이핑 중이 아닐 때만
    // 바깥 값을 따라간다(타이핑 도중 덮어쓰면 커서가 튄다).
    if (!_focus.hasFocus) {
      final want = widget.transport.bpm.round().toString();
      if (_ctrl.text != want) _ctrl.text = want;
    }
    return Row(
      children: [
        _StepButton(
          icon: Icons.remove,
          onTap: () => _set(widget.transport.bpm - 1),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 72,
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => _commit(),
          ),
        ),
        const SizedBox(width: 8),
        const Text('BPM', style: TextStyle(fontSize: 12, color: Colors.white38)),
        const SizedBox(width: 10),
        _StepButton(
          icon: Icons.add,
          onTap: () => _set(widget.transport.bpm + 1),
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _StepButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white10,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 18, color: Colors.tealAccent.shade400),
    ),
  );
}

/// 한 줄짜리 손잡이 — 지금 값 + 눌러서 고르러 가기.
class _SettingRow extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SettingRow({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final bool on;
  final VoidCallback onTap;
  const _Chip({required this.text, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: on ? Colors.tealAccent.shade400 : Colors.white10,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
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
