// 편집기 손끝 판정 — **긴 음의 가운데를 만질 수 있는가.**
//   flutter test test/editor_hit_test.dart
//
// 사용자 신고(2026-09-22): "미디 편집할때 긴 블럭의 중간부분을 길게누르면
// 그 블럭을 잡아야지 왜 새로 생성되니".
//
// 원인: 손끝 판정이 음의 **시작 칸**만 봤다(`_noteAt` = `n[1] == step`).
// 음은 `[도수, 시작칸, 길이, …]` 라 여러 칸에 걸쳐 있는데, 4칸짜리 음의
// 3번째 칸은 "빈 칸"으로 읽혀 **그 위에 새 음이 하나 더 깔렸다.**
// 눈에는 한 덩어리로 보이는데 만질 수 있는 곳은 왼쪽 끝 한 칸뿐이었다.
//
// 화면 위젯을 띄우지 않고 **판정 규칙 자체**를 잰다 — 규칙이 틀리면 꾹 누르기,
// 탭, 지우개, 끌어 깔기 네 곳이 한꺼번에 틀린다.

import 'package:flutter_test/flutter_test.dart';

/// `_EditorViewState._noteCovering` 과 **같은 규칙**.
/// (화면 상태 클래스는 private 이라 여기서 규칙만 그대로 옮겨 잰다 —
///  둘이 어긋나면 이 시험이 뜻을 잃으므로, 저쪽을 고치면 여기도 고친다)
List<Object?>? noteCovering(List<List<Object?>> notes, int degree, int step) {
  // **뒤에서부터** — 그리는 쪽(Stack)이 뒤쪽 음을 위에 그린다.
  for (var i = notes.length - 1; i >= 0; i--) {
    final n = notes[i];
    if (n[0] != degree) continue;
    final s = n[1] as int;
    final len = n[2] as int;
    if (step >= s && step < s + len) return n;
  }
  return null;
}

/// 고치기 전 규칙 — 시작 칸만 본다.
List<Object?>? noteAtStartOnly(
  List<List<Object?>> notes,
  int degree,
  int step,
) {
  for (final n in notes) {
    if (n[0] == degree && n[1] == step) return n;
  }
  return null;
}

void main() {
  // 도수 5, 8칸에서 시작하는 **4칸짜리** 음 하나.
  final notes = <List<Object?>>[
    [5, 8, 4, 2],
  ];

  group('긴 음의 가운데도 그 음이다', () {
    test('덮는 칸 전부에서 찾아진다', () {
      for (final s in [8, 9, 10, 11]) {
        expect(noteCovering(notes, 5, s), isNotNull, reason: '$s칸이 안 잡힌다');
      }
    });

    test('덮지 않는 칸에서는 안 찾아진다', () {
      for (final s in [7, 12, 13]) {
        expect(noteCovering(notes, 5, s), isNull, reason: '$s칸이 잘못 잡힌다');
      }
    });

    test('다른 줄은 안 잡는다 — 화음을 따로 만질 수 있어야 한다', () {
      expect(noteCovering(notes, 4, 9), isNull);
      expect(noteCovering(notes, 6, 9), isNull);
    });

    test('잡으면 **시작 칸**을 돌려준다 — 길이·줄 옮기기가 그걸로 음을 찾는다', () {
      for (final s in [8, 9, 10, 11]) {
        expect(noteCovering(notes, 5, s)![1], 8, reason: '$s칸에서 시작 칸이 틀리다');
      }
    });
  });

  group('고치기 전에는 정말 틀렸다 — 회귀하면 여기가 먼저 걸린다', () {
    test('옛 규칙은 가운데를 빈 칸으로 읽었다', () {
      expect(noteAtStartOnly(notes, 5, 8), isNotNull, reason: '시작 칸만 찾았다');
      for (final s in [9, 10, 11]) {
        expect(noteAtStartOnly(notes, 5, s), isNull,
            reason: '$s칸 — 여기가 비었다고 읽혀서 새 음이 깔렸다');
      }
    });
  });

  group('겹쳐 깔리지 않는다', () {
    test('덮인 칸에는 새로 안 깐다', () {
      // `_paintAt` 이 쓰는 판정. 9·10·11칸에 새 음이 생기면 안 된다.
      var made = 0;
      for (var s = 0; s < 16; s++) {
        if (noteCovering(notes, 5, s) == null) made++;
      }
      expect(made, 12, reason: '16칸 중 4칸은 이미 덮여 있다');
    });
  });

  group('길이가 1인 음도 그대로 동작한다', () {
    final one = <List<Object?>>[
      [3, 4, 1, 2],
    ];
    test('그 한 칸만 잡힌다', () {
      expect(noteCovering(one, 3, 4), isNotNull);
      expect(noteCovering(one, 3, 5), isNull);
      expect(noteCovering(one, 3, 3), isNull);
    });
  });

  group('여러 음이 한 줄에 있어도 제 것을 잡는다', () {
    final many = <List<Object?>>[
      [7, 0, 4, 2],
      [7, 4, 2, 2],
      [7, 8, 8, 2],
    ];
    test('경계가 안 새어 나간다', () {
      expect(noteCovering(many, 7, 3)![1], 0);
      expect(noteCovering(many, 7, 4)![1], 4);
      expect(noteCovering(many, 7, 5)![1], 4);
      expect(noteCovering(many, 7, 6), isNull, reason: '두 음 사이 빈 칸');
      expect(noteCovering(many, 7, 8)![1], 8);
      expect(noteCovering(many, 7, 15)![1], 8);
    });
  });

  group('겹친 자리는 **위에 그려진** 음이 잡힌다', () {
    // 「쫘르륵 깔기」가 만드는 모양 — 이웃끼리 1칸씩 겹친다.
    final lapped = <List<Object?>>[
      [7, 2, 2, 2],
      [7, 3, 2, 2],
    ];
    test('겹친 칸에서는 뒤쪽(위) 음', () {
      expect(noteCovering(lapped, 7, 3)![1], 3,
          reason: '앞쪽을 돌려주면 눈에 보이는 막대와 잡히는 음이 다르다');
    });
    test('안 겹친 칸은 제 것을 잡는다', () {
      expect(noteCovering(lapped, 7, 2)![1], 2);
      expect(noteCovering(lapped, 7, 4)![1], 3);
      expect(noteCovering(lapped, 7, 5), isNull);
    });
  });
}
