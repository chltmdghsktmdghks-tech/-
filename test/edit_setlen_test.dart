// 길이 바꾸기가 **뒷 음을 덮지 않는가.**
//   flutter test test/edit_setlen_test.dart
//
// 덮으면 그 음이 화면에서 가려지고, 편집기의 손끝 판정은 **위에 그려진 음**을
// 잡으므로 덮인 음은 손으로 만질 수 없게 된다 — 지울 수도 고를 수도 없는데
// 소리로는 계속 난다. "왜 이 소리가 나지"가 되는 종류다.
//
// 다만 「끌면 쫘르륵 깔린다」가 **일부러 이웃끼리 1칸씩 겹쳐** 놓으므로
// (`editor_ui_test.dart` 10번), 무턱대고 자르면 그렇게 깐 줄의 음을 만지는
// 순간 전부 1칸으로 쪼그라든다. 그래서 **늘리는 쪽만** 막는다.

import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/edit_ops.dart';

void main() {
  group('뒷 음을 안 덮는다', () {
    test('다음 음 직전까지만 늘어난다', () {
      // 4번에서 시작하는 음, 8번에서 다음 음 → 길이는 최대 4칸.
      final out = NoteOps.setLen(
        const [
          [5, 4, 2, 2],
          [5, 8, 2, 2],
        ],
        5,
        4,
        8, // 8칸을 달라고 해도
        steps: 32,
      );
      final me = out.firstWhere((n) => n[1] == 4);
      // ignore: avoid_print
      print('8칸 요청 → ${me[2]}칸 (다음 음이 8번에서 시작)');
      expect(me[2], 4, reason: '다음 음 시작 칸을 넘으면 그 음이 가려진다');
      expect(out.firstWhere((n) => n[1] == 8)[2], 2, reason: '뒷 음은 그대로');
    });

    test('다음 음이 없으면 판 끝까지', () {
      final out = NoteOps.setLen(
        const [
          [5, 28, 1, 2],
        ],
        5,
        28,
        16,
        steps: 32,
      );
      expect(out.single[2], 4, reason: '28번에서 판 끝(32)까지 4칸');
    });

    test('다른 도수는 안 막는다 — 화음은 따로다', () {
      final out = NoteOps.setLen(
        const [
          [5, 4, 2, 2],
          [6, 6, 2, 2], // 위 줄의 음 — 막을 이유가 없다
        ],
        5,
        4,
        8,
        steps: 32,
      );
      expect(out.firstWhere((n) => n[0] == 5)[2], 8);
    });
  });

  group('이미 겹쳐 있는 것은 안 줄인다', () {
    // 「쫘르륵 깔기」가 만드는 모양 — 칸마다 길이 2, 이웃끼리 1칸 겹침.
    const lapped = [
      [7, 0, 2, 2],
      [7, 1, 2, 2],
      [7, 2, 2, 2],
    ];

    test('만진다고 1칸으로 쪼그라들지 않는다', () {
      // 0번 음의 다음 음은 1번 → room = 1. 그래도 지금 길이 2는 지킨다.
      final out = NoteOps.setLen(lapped, 7, 0, 2, steps: 32);
      // ignore: avoid_print
      print('겹친 줄에서 길이 유지 → ${out.firstWhere((n) => n[1] == 0)[2]}칸');
      expect(out.firstWhere((n) => n[1] == 0)[2], 2);
    });

    test('그래도 **더 늘리지는** 못한다', () {
      final out = NoteOps.setLen(lapped, 7, 0, 6, steps: 32);
      expect(out.firstWhere((n) => n[1] == 0)[2], 2,
          reason: '이미 겹친 만큼은 두되 더 덮지는 않는다');
    });

    test('줄이는 것은 언제나 된다', () {
      final out = NoteOps.setLen(lapped, 7, 0, 1, steps: 32);
      expect(out.firstWhere((n) => n[1] == 0)[2], 1);
    });
  });

  group('고치기 전에는 덮었다 — 회귀하면 여기가 걸린다', () {
    test('옛 규칙이면 8칸이 그대로 들어간다', () {
      // `_fitLen` 만 걸던 시절의 계산: 판 끝과 kMaxNoteLen 만 본다.
      const step = 4, steps = 32, want = 8;
      final oldLen = want.clamp(1, (steps - step).clamp(1, kMaxNoteLen));
      expect(oldLen, 8, reason: '옛 규칙은 뒷 음을 안 봤다');
    });
  });
}
