// **질문에 답해서 곡 만들기** 화면 — 옛 앱의 첫 화면 머리 항목.
//
// 한 번에 **질문 하나**만 보여 준다. 열 개를 한 화면에 늘어놓으면 설문지가 되고,
// 설문지는 아무도 끝까지 안 한다. 답은 큰 칸으로 — 누르면 바로 다음이다
// (「다음」 버튼이 없다: 고르는 것이 곧 넘기는 것이다).
//
// 위에 **얼마나 왔는지** 막대를 둔다. 끝이 안 보이면 사람은 중간에 나간다.
// 「← 이전」은 첫 질문 빼고 늘 있다 — 되돌아갈 길 없는 열 걸음은 무섭다.

import 'package:flutter/material.dart';

import '../ask_song.dart';
import '../genres.dart';

/// 답을 다 받으면 [onDone] 으로 **답 모음**을 준다. 곡을 만드는 것은 부르는 쪽이다
/// (화면을 닫고 어디로 갈지는 집이 안다).
Future<void> showAskSheet(
  BuildContext context, {
  required ValueChanged<Map<String, String>> onDone,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF16181C),
    isScrollControlled: true, // 가로로 눕히면 안 그러면 잘린다
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => _AskBody(onDone: onDone),
  );
}

class _AskBody extends StatefulWidget {
  final ValueChanged<Map<String, String>> onDone;
  const _AskBody({required this.onDone});

  @override
  State<_AskBody> createState() => _AskBodyState();
}

class _AskBodyState extends State<_AskBody> {
  final Map<String, String> _ans = {};
  int _step = 0;

  void _pick(String key, String value) {
    _ans[key] = value;
    if (_step + 1 >= kAskQuestions.length) {
      Navigator.pop(context);
      widget.onDone(Map<String, String>.from(_ans));
      return;
    }
    setState(() => _step++);
  }

  @override
  Widget build(BuildContext context) {
    final q = kAskQuestions[_step];
    final total = kAskQuestions.length;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // **얼마나 왔나** — 끝이 안 보이면 중간에 나간다.
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: _step / total,
                      minHeight: 5,
                      backgroundColor: Colors.white12,
                      valueColor: AlwaysStoppedAnimation(Colors.teal.shade300),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    q.q,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${_step + 1} / $total${q.hint.isEmpty ? '' : ' · ${q.hint}'}',
                    style: const TextStyle(fontSize: 12, color: Colors.white38),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  children: [
                    for (final (v, label, desc) in q.answers)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GestureDetector(
                          onTap: () => _pick(q.key, v),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14, // 손가락 바닥선을 넉넉히 넘긴다
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                if (desc.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    desc,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white38,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // 「← 이전」은 첫 질문 빼고 늘 있다 — 되돌아갈 길 없는 열 걸음은 무섭다.
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
              child: Row(
                children: [
                  if (_step > 0)
                    TextButton.icon(
                      onPressed: () => setState(() => _step--),
                      icon: const Icon(Icons.chevron_left, size: 18),
                      label: const Text('이전', style: TextStyle(fontSize: 13.5)),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white54,
                      ),
                    ),
                  const Spacer(),
                  Text(
                    '음악 용어는 하나도 안 나옵니다',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.25),
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

/// 답 모음을 **한 줄로** 적는다 — 곡을 만든 뒤 「이렇게 만들었어요」로 보여 준다.
String askSummary(Map<String, String> a, AskRecipe r) {
  final words = <String>[];
  for (final q in kAskQuestions) {
    final v = a[q.key];
    if (v == null) continue;
    for (final (val, label, _) in q.answers) {
      if (val == v) {
        words.add(label);
        break;
      }
    }
  }
  final g = genreDef(r.genre).label;
  return '$g · ${r.bpm.round()}BPM · ${words.take(3).join(' · ')}';
}
