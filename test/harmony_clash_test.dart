// **한 씬 안에서 코드 트랙끼리·베이스와 코드가 같은 진행을 치는가.** (작곡 품질)
//   flutter test test/harmony_clash_test.dart
//
// 객체형 장르는 코드 트랙이 둘 이상이다(패드 + 스탭, 패드 + 브라스).
// 둘이 다른 진행을 치면 **부딪친다** — 3마디째에 패드는 i, 스탭은 III 를 치는 식이다.
// 소리로는 「뭔가 탁하다」로만 들리고 어디가 문제인지 알 수 없다. 숫자로 못 박는다.
//
// 베이스가 코드와 다른 근음을 짚으면 그게 제일 크게 어긋난다.
//
// ── 예전 판이 못 보던 것 ──
// 처음 쓴 판은 패턴의 **원본 노트**만 견줬다. 그래서 **2마디 베이스가 4마디 진행 밑에
// 깔린 자리**를 통째로 못 봤다 — 3·4마디는 아무도 검사하지 않았다.
// 실제로 그런 자리가 열세 곳이었다(하우스·록·드릴 벌스 등).
// 지금은 두 패턴을 **씬 길이만큼 펴 놓고** 견준다(시퀀서가 실제로 그렇게 재생한다).
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/project.dart';

/// 일부러 코드를 안 따라가는 줄 — **그게 그 소리인 것**만 적는다.
///
/// 엠비언트 서브는 두 마디를 통째로 끄는 **페달 톤**이다. 코드가 그 위를 지나가는
/// 것이 이 장르의 소리다 — 코드마다 따라 움직이면 오히려 안개가 걷힌다.
const _pedal = {'Amb Sub', 'Amb Sub2'};

/// 패턴을 씬 길이만큼 펴서 **마디마다 첫 도수**를 낸다. 없는 마디는 null.
/// (시퀀서와 같은 규칙 — 짧은 클립은 씬 안에서 자기 길이만큼 되풀이된다.)
List<int?> barDegrees(NotePatternDef d, int loopBars) {
  final own = d.bars * kStepsPerBar;
  final srcSteps = (d.src > 0 ? d.src : d.bars) * kStepsPerBar;
  final reps = d.src > 0 ? (d.bars ~/ d.src).clamp(1, 64) : 1;
  final out = List<int?>.filled(loopBars, null);
  if (own <= 0) return out;
  for (var c = 0; c * own < loopBars * kStepsPerBar; c++) {
    for (var r = 0; r < reps; r++) {
      for (final n in d.notes) {
        final b = ((n[1] as int) + r * srcSteps + c * own) ~/ kStepsPerBar;
        if (b >= loopBars) continue;
        out[b] ??= ((n[0] as int) % 7 + 7) % 7;
      }
    }
  }
  return out;
}

void main() {
  test('화성 충돌', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final clash = <String>[];
    final off = <String>[];
    var pairs = 0, basses = 0;

    for (final g in kGenres) {
      final p = Project.initial()..setGenre(g.key);
      for (final sc in p.scenes) {
        var loopBars = 0;
        for (final t in p.tracks) {
          final clip = sc.clips[t.id];
          if (clip == null) continue;
          final b = p.barsOf(t.type, clip);
          if (b > loopBars) loopBars = b;
        }
        if (loopBars <= 0) continue;

        // ── 코드 트랙끼리 ──
        final chords = <String, List<int?>>{};
        for (final t in p.tracks.where((t) => t.type == 'chord')) {
          final clip = sc.clips[t.id];
          if (clip == null) continue;
          final def = p.findNote('chord', clip);
          if (def == null || def.notes.isEmpty) continue;
          chords[clip] = barDegrees(def, loopBars);
        }
        final names = chords.keys.toList();
        for (var i = 0; i < names.length; i++) {
          for (var j = i + 1; j < names.length; j++) {
            pairs++;
            final a = chords[names[i]]!, b = chords[names[j]]!;
            final bad = <int>[];
            for (var k = 0; k < loopBars; k++) {
              if (a[k] != null && b[k] != null && a[k] != b[k]) bad.add(k + 1);
            }
            if (bad.isNotEmpty) {
              clash.add(
                '${g.key}/${sc.name} ${names[i]}↔${names[j]} '
                '${bad.join(',')}마디',
              );
            }
          }
        }

        // ── 베이스가 코드를 따라가는가 ──
        if (names.isEmpty) continue;
        final ch = chords[names.first]!;
        for (final t in p.tracks.where((t) => t.type == 'bass')) {
          final clip = sc.clips[t.id];
          if (clip == null || _pedal.contains(clip)) continue;
          final d = p.findNote('bass', clip);
          if (d == null || d.notes.isEmpty) continue;
          final bs = barDegrees(d, loopBars);
          final bad = <int>[];
          for (var k = 0; k < loopBars; k++) {
            if (ch[k] != null && bs[k] != null && ch[k] != bs[k])
              bad.add(k + 1);
          }
          basses++;
          if (bad.isNotEmpty) {
            off.add('${g.key}/${sc.name} $clip ${bad.join(',')}마디');
          }
        }
      }
    }

    check(
      '1) 같은 씬의 코드 트랙끼리 안 부딪친다',
      clash.isEmpty,
      clash.isEmpty ? '$pairs쌍 전부' : clash.take(4).join(' · '),
    );
    check(
      '2) 베이스가 코드를 마디마다 따라간다',
      off.isEmpty,
      off.isEmpty
          ? '$basses개 줄 (페달 톤 ${_pedal.length}개 제외)'
          : off.take(5).join(' · '),
    );

    // ignore: avoid_print
    print(fail == 0 ? '화성 충돌 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
