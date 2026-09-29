// 두들플레이 레인별 킷 — 킥·스네어·하이햇이 각자 다른 킷을 가질 수 있어야 하고,
// 덮어쓰기가 없으면 옛 동작(세 레인 다 트랙 킷)이 그대로여야 한다.
//   flutter test test/doodle_lane_kit_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';

void main() {
  Set<String> kitsOf(SceneBuild b, String lane) => {
    for (final d in b.drums)
      if (d[1] == lane) d[0] as String,
  };

  test('드럼킷 고르기: 덮어쓰기 없으면 전 레인이 기본 킷 (옛 동작)', () {
    expect(drumKitFor('acoustic', const {}, 'kick'), 'acoustic');
    expect(drumKitFor('acoustic', const {}, 'hatopen'), 'acoustic');
    expect(drumKitFor('acoustic', {'hat': '808'}, 'hat'), '808');
    expect(drumKitFor('acoustic', {'hat': '808'}, 'hatopen'), '808');
    expect(drumKitFor('acoustic', {'hat': '808'}, 'kick'), 'acoustic');
    expect(drumKitFor('acoustic', {'hat': '808'}, 'crash'), 'acoustic');
  });

  test('씬 재생: 덮어쓰기 없으면 모든 타격이 트랙 킷 하나', () {
    final p = Project.initial()..setGenre('lofi');
    final tr = Transport();
    final b = SceneSequencer.build(p, tr);
    expect(b.drums, isNotEmpty);
    final kit = p.tracks.firstWhere((t) => t.type == 'drum').kit;
    expect({for (final d in b.drums) d[0]}, {kit});
  });

  test('씬 재생: 하이햇만 덮으면 하이햇만 다른 킷, 킥·스네어는 그대로', () {
    final p = Project.initial()..setGenre('lofi');
    final tr = Transport();
    final kit = p.tracks.firstWhere((t) => t.type == 'drum').kit;
    final other = kit == '808' ? 'acoustic' : '808';
    p.scene.laneKits['hat'] = other;
    final b = SceneSequencer.build(p, tr);
    expect(kitsOf(b, 'hat'), {other});
    for (final lane in ['kick', 'snare']) {
      final k = kitsOf(b, lane);
      if (k.isNotEmpty) expect(k, {kit}, reason: lane);
    }
  });

  test('Scene.laneKits: 저장/복원·복제 (빈 값은 JSON 에 안 나온다)', () {
    final s = Scene('a');
    expect(s.toJson().containsKey('laneKits'), isFalse);
    s.laneKits['kick'] = 'rock';
    final back = Scene.fromJson(Map<String, dynamic>.from(s.toJson()));
    expect(back.laneKits, {'kick': 'rock'});
    s.copyWith('b').laneKits['kick'] = 'x';
    expect(s.laneKits['kick'], 'rock', reason: '복제본이 원본을 건드리면 안 된다');
    // 옛 파일(laneKits 없음)
    expect(Scene.fromJson({'name': 'o', 'clips': <String, dynamic>{}}).laneKits, isEmpty);
  });
}
