// 두들플레이 시작 전 설정 — 장르 + **빠르기·조·마디**를 한 번에 확정한다
// (사용자 지시, 2026-09-29).
//
// 여태는 장르만 고르면 그 장르의 기본 BPM·mode 가 자동으로 정해지고 바로
// `openDoodlePlay()` 로 들어갔다 — 조(root)는 아예 건드리지 않아 이전 곡의
// 조가 그대로 남았고, 판 길이(마디)도 사용자가 못 고르고 씬 길이에서
// 자동으로 갈무리됐다. 이 시트는 장르 고르기 **다음**에 열려 넷을 확정한다:
// 장르(이미 고름) · 빠르기(+/-) · 조(+/-, root+mode) · 마디(2/4/8 선택).
//
// **슬라이더를 안 쓴다** — 사용자 지시. `project_settings_sheet.dart` 의
// `StepButton`(+/- 버튼)을 그대로 재사용한다.
import 'package:flutter/material.dart';

import '../genres.dart' show GenreDef;
import '../project.dart' show keyLabel;
import 'doodle_play_view.dart' show kDoodleBarChoices;
import 'project_settings_sheet.dart' show StepButton;

/// 이 시트가 확정해 돌려주는 값 — 호출부가 그대로 `transport`·`openDoodlePlay`
/// 에 넘긴다.
class DoodleSetup {
  final double bpm;
  final int root;
  final String mode;
  final int bars;
  const DoodleSetup({
    required this.bpm,
    required this.root,
    required this.mode,
    required this.bars,
  });
}

/// 빠르기 -/+ 범위 — `project_settings_sheet.dart` 의 `_BpmEditor` 와 같은 값
/// (40~240). 여기서만 다른 범위를 쓰면 시작할 때 정한 빠르기와 나중에
/// 프로젝트 설정에서 만질 때의 한계가 달라 보여 혼란스럽다.
const double kDoodleBpmMin = 40, kDoodleBpmMax = 240;

/// 두들플레이 시작 전에 장르 기본값을 보여주고 빠르기·조·마디를 고르게 한다.
/// 취소하면 null.
Future<DoodleSetup?> showDoodleSetupSheet(
  BuildContext context, {
  required GenreDef genre,
  required int initialRoot,
}) {
  return showModalBottomSheet<DoodleSetup>(
    context: context,
    backgroundColor: const Color(0xFF1A1A1E),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => _DoodleSetupBody(genre: genre, initialRoot: initialRoot),
  );
}

class _DoodleSetupBody extends StatefulWidget {
  final GenreDef genre;
  final int initialRoot;
  const _DoodleSetupBody({required this.genre, required this.initialRoot});

  @override
  State<_DoodleSetupBody> createState() => _DoodleSetupBodyState();
}

class _DoodleSetupBodyState extends State<_DoodleSetupBody> {
  late double _bpm = widget.genre.bpm;
  late int _root = ((widget.initialRoot % 12) + 12) % 12;
  late String _mode = widget.genre.mode;

  /// 기본값은 4마디 — `kDoodleBarChoices`(2·4·8) 가운데. 너무 짧지도
  /// (2마디는 한 코드도 못 굴려 본다) 너무 길지도(8마디는 첫 판부터 오래
  /// 기다린다) 않은 중간값이다.
  int _bars = 4;

  void _setBpm(double v) =>
      setState(() => _bpm = v.clamp(kDoodleBpmMin, kDoodleBpmMax));

  void _stepRoot(int by) =>
      setState(() => _root = ((_root + by) % 12 + 12) % 12);

  void _confirm() => Navigator.of(
    context,
  ).pop(DoodleSetup(bpm: _bpm, root: _root, mode: _mode, bars: _bars));

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        // 스크롤 영역 + **바닥에 고정한** 취소/시작 줄. 작은 폰(320×568)에서
        // 버튼이 접힌 화면 밖으로 밀려 스크롤해야 보이던 것을 막는다.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.genre.label} — 빠르기·조·마디를 정해요',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '장르 기본값에서 바로 조절해요 — 다음 화면에서 킥부터 두드립니다',
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                    const SizedBox(height: 20),

                    const _RowLabel('빠르기'),
                    Row(
                      children: [
                        // 큰 걸음(±10) — 40→240 을 200번 누르지 않게. ±1 은 그대로.
                        StepButton(
                          icon: Icons.keyboard_double_arrow_left,
                          label: '-10',
                          onTap: _bpm > kDoodleBpmMin
                              ? () => _setBpm(_bpm - 10)
                              : null,
                        ),
                        StepButton(
                          icon: Icons.remove,
                          onTap: _bpm > kDoodleBpmMin
                              ? () => _setBpm(_bpm - 1)
                              : null,
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              '${_bpm.round()} BPM',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        StepButton(
                          icon: Icons.add,
                          onTap: _bpm < kDoodleBpmMax
                              ? () => _setBpm(_bpm + 1)
                              : null,
                        ),
                        StepButton(
                          icon: Icons.keyboard_double_arrow_right,
                          label: '+10',
                          onTap: _bpm < kDoodleBpmMax
                              ? () => _setBpm(_bpm + 10)
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    const _RowLabel('조'),
                    Row(
                      children: [
                        StepButton(
                          icon: Icons.remove,
                          onTap: () => _stepRoot(-1),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              keyLabel(_root, _mode),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        StepButton(icon: Icons.add, onTap: () => _stepRoot(1)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _PickChip(
                          text: '장조 (밝다)',
                          on: _mode == 'major',
                          onTap: () => setState(() => _mode = 'major'),
                        ),
                        const SizedBox(width: 6),
                        _PickChip(
                          text: '단조 (어둡다)',
                          on: _mode == 'minor',
                          onTap: () => setState(() => _mode = 'minor'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    const _RowLabel('마디 (한 판 길이)'),
                    Row(
                      children: [
                        for (final b in kDoodleBarChoices) ...[
                          _PickChip(
                            text: '$b마디',
                            on: _bars == b,
                            onTap: () => setState(() => _bars = b),
                          ),
                          const SizedBox(width: 6),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: _buildActions(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        // 취소 — 바깥을 탭해야만 닫히던 것을 눈에 보이는 버튼으로.
        // 아무것도 확정하지 않고 null 로 닫는다(바깥 탭과 같은 결과).
        Expanded(
          flex: 2,
          child: OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Colors.white24),
              minimumSize: const Size(0, 48),
            ),
            child: const Text(
              '취소',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 5,
          child: FilledButton(
            onPressed: _confirm,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.tealAccent.shade400,
              foregroundColor: Colors.black,
              minimumSize: const Size(0, 48),
            ),
            child: const Text(
              '이 설정으로 시작',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

class _RowLabel extends StatelessWidget {
  final String text;
  const _RowLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: Colors.white54,
      ),
    ),
  );
}

/// 마디·장조/단조처럼 **고르는**(조절이 아니라 선택하는) 값에 쓰는 칩 —
/// `project_settings_sheet.dart` 의 `_Chip` 과 같은 생김새다.
///
/// **`GestureDetector`였다 — 눌러도 아무 반응이 없었다**(디자인 감사,
/// 2026-09-29: "탭 가능한 것은 탭처럼 보이고, 눌리면 반응해야 한다"). 색이
/// 바뀌는 건 상태가 정해진 *뒤*고, 누르는 그 순간엔 손끝에 아무 신호가
/// 없어 눌렸는지 되짚어야 했다. `InkWell` 물결로 바꾼다 — 이 파일의
/// `StepButton`(`project_settings_sheet.dart`)도 이미 InkWell을 쓴다.
class _PickChip extends StatelessWidget {
  final String text;
  final bool on;
  final VoidCallback onTap;
  const _PickChip({required this.text, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: on ? Colors.tealAccent.shade400 : Colors.white10,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          // 세로 10 이었을 땐 전체 높이가 ~36dp 로 44dp 최소 터치 타깃에
          // 못 미쳤다 — 14로 올려 ~44dp 를 채운다.
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: on ? FontWeight.w800 : FontWeight.w500,
              color: on ? Colors.black : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}
