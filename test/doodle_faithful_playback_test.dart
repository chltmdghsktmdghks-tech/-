// 두들 재생 충실도 (2026-09-30) — 친 대로 나와야 한다:
// 자동 필인(크래시)이 안 붙고, 하이햇 개수가 바퀴가 돌아도 그대로.
//   flutter test test/doodle_faithful_playback_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/edit_ops.dart';
import 'package:music_doodle_engine/feel.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';

const _bars = 4;

Project _doodle({required bool faithful}) {
  final p = Project.blank()..setGenreBare('rock');
  if (faithful) p.setFeel(Feel.none.copyWith(fill: 0, vary: 0)); // home_view 와 같은 줄
  final ops = DrumOps.read(null);
  for (var b = 0; b < _bars; b++) {
    for (var s = 0; s < 16; s++) {
      ops.steps['hat']!.add(b * 16 + s);
      ops.vels['hat']!.add(2);
    }
    ops.steps['kick']!.add(b * 16);
    ops.vels['kick']!.add(2);
    ops.steps['snare']!.add(b * 16 + 8);
    ops.vels['snare']!.add(2);
  }
  p.putUserPattern('drum', 'd', drum: ops.toDef('d', _bars));
  p.setClip(p.tracks.firstWhere((t) => t.type == 'drum'), 'd');
  return p;
}

int _count(SceneBuild b, String lane) =>
    b.drums.where((d) => d[1] == lane).length;

void main() {
  test('두들 곡: 크래시(자동 필인) 없음, 하이햇·킥·스네어 개수 그대로', () {
    final tr = Transport();
    final b = SceneSequencer.build(_doodle(faithful: true), tr);
    final n = tr.reps * (b.loopBars ~/ _bars);
    expect(b.loopBars, _bars);
    expect(_count(b, 'crash'), 0, reason: '치지 않은 크래시');
    expect(_count(b, 'hat'), 64 * tr.reps);
    expect(_count(b, 'kick'), _bars * tr.reps);
    expect(_count(b, 'snare'), _bars * tr.reps);
    expect(n, tr.reps);
  });

  test('대조: 손잡이를 안 끄면 옛 버그(크래시 붙음 또는 하이햇 변함)가 재현된다', () {
    final tr = Transport();
    final b = SceneSequencer.build(_doodle(faithful: false), tr);
    final broken = _count(b, 'crash') > 0 || _count(b, 'hat') != 64 * tr.reps;
    expect(broken, isTrue);
  });
}
