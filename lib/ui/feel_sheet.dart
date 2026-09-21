// 느낌 손잡이 — **결과를 만지는 화면.** (Phase 2 · 개선 계획 4-4)
//
// 여기 있는 말은 전부 결과다. 벨로시티·스텝·스윙 비율 같은 말은 안 쓴다.
// 값도 숫자로 안 보여 준다 — 0.73 은 아무 뜻도 없다. 「신남」이라고 적는다.
import 'package:flutter/material.dart';

import '../feel.dart';

/// 다섯 손잡이를 만지게 한다. 만질 때마다 [onChanged] 가 온다
/// (닫아야 반영되면 "이게 무슨 소리인지"를 못 듣는다).
Future<void> showFeelSheet(
  BuildContext context, {
  required Feel value,
  required ValueChanged<Feel> onChanged,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF16161A),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => FeelSheetBody(value: value, onChanged: onChanged),
  );
}

/// 시트의 **속**. 그림 도구가 직접 그릴 수 있게 따로 뺐다.
class FeelSheetBody extends StatefulWidget {
  final Feel value;
  final ValueChanged<Feel> onChanged;
  const FeelSheetBody({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  State<FeelSheetBody> createState() => _FeelSheetBodyState();
}

class _FeelSheetBodyState extends State<FeelSheetBody> {
  late Feel _f = widget.value;

  void _set(Feel f) {
    setState(() => _f = f);
    widget.onChanged(f);
  }

  @override
  Widget build(BuildContext context) {
    // 가로로 누우면 높이가 귀하다 — 줄 간격을 줄이고 **두 칸으로** 놓는다.
    //
    // 손잡이가 다섯이 되면서 한 줄로는 안 들어간다(누웠을 때 높이 400, 손잡이 한 줄
    // 146). 스크롤은 되지만 **맨 아래 손잡이는 있는 줄도 모른다** — 스크롤바가
    // 안 보이는 시트에서는 화면 밖이 곧 없는 것이다.
    final tight = MediaQuery.of(context).size.height < 520;
    final gap = tight ? 6.0 : 14.0;
    final knobs = <Widget>[
      _Knob(
        title: '기운',
        left: '차분',
        right: '신남',
        word: Feel.energyWord(_f.energy),
        value: _f.energy,
        color: const Color(0xFFFFB74D),
        onChanged: (v) => _set(_f.copyWith(energy: v)),
      ),
      _Knob(
        title: '빽빽함',
        left: '단순',
        right: '빽빽',
        word: Feel.densityWord(_f.density),
        value: _f.density,
        color: const Color(0xFF4FC3F7),
        onChanged: (v) => _set(_f.copyWith(density: v)),
      ),
      _Knob(
        title: '그루브',
        left: '반듯',
        right: '스윙',
        word: Feel.grooveWord(_f.groove),
        value: _f.groove,
        color: const Color(0xFFCE93D8),
        onChanged: (v) => _set(_f.copyWith(groove: v)),
      ),
      _Knob(
        title: '매듭',
        left: '없음',
        right: '자주',
        word: Feel.fillWord(_f.fill),
        value: _f.fill,
        color: const Color(0xFF80CBC4),
        onChanged: (v) => _set(_f.copyWith(fill: v)),
      ),
      _Knob(
        title: '변화',
        left: '늘 똑같이',
        right: '자주',
        word: Feel.varyWord(_f.vary),
        value: _f.vary,
        color: const Color(0xFFF48FB1),
        onChanged: (v) => _set(_f.copyWith(vary: v)),
      ),
    ];
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(18, tight ? 10 : 16, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '느낌',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 2),
            const Text(
              '만지면 바로 바뀝니다. 곡은 그대로 두고 분위기만 손봅니다.',
              style: TextStyle(fontSize: 12.5, color: Colors.white54),
            ),
            SizedBox(height: gap),
            if (tight)
              // 누웠을 때 — 두 칸. 마지막 한 개는 한 칸을 차지한다.
              for (var i = 0; i < knobs.length; i += 2) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: knobs[i]),
                    const SizedBox(width: 18),
                    Expanded(
                      child: i + 1 < knobs.length
                          ? knobs[i + 1]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
                SizedBox(height: gap),
              ]
            else
              for (final k in knobs) ...[k, SizedBox(height: gap)],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _set(Feel.none),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text(
                  '처음으로',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                style: TextButton.styleFrom(foregroundColor: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Knob extends StatelessWidget {
  final String title, left, right, word;
  final double value;
  final Color color;
  final ValueChanged<double> onChanged;
  const _Knob({
    required this.title,
    required this.left,
    required this.right,
    required this.word,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Spacer(),
            // **지금 어떤 상태인지를 말로.** 숫자를 보여 주면 그걸 맞추려 들게 된다.
            Text(
              word,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            thumbColor: color,
            inactiveTrackColor: Colors.white12,
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
          ),
          child: Slider(value: value, onChanged: onChanged),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              left,
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
            Text(
              right,
              style: const TextStyle(fontSize: 11, color: Colors.white38),
            ),
          ],
        ),
      ],
    );
  }
}
