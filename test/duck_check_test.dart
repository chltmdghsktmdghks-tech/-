// 비켜주기(사이드체인 덕킹) — 장르 고정값에서 **사용자 손잡이**로 바뀐 부분.
//   flutter test test/duck_check_test.dart
//
// `Engine.duckAmount`/`duckRelSec` 은 이미 있었다(엔진 DSP·아이솔레이트
// 메시지까지) — 이번에 새로 생긴 건 `Project.duckAmountOverride`(저장·
// 장르보다 우선) 와 `Engine.duckRelSec` 을 사용자가 바꿀 수 있게 한 것.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/engine.dart';
import 'package:music_doodle_engine/genre_mix.dart';
import 'package:music_doodle_engine/project.dart';

void main() {
  test('Engine.duckRelSec — 복귀 시간을 바꾸면 실제로 더 빨리/느리게 돌아온다', () {
    var fail = 0;
    void check(String name, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $name — $detail');
      if (!ok) fail++;
    }

    // 몇 프레임(`render`) 안에 거의 다(0.99) 돌아오는지 잰다 — 킥 하나를
    // 치면 `drumOn` 이 그 자리에서 곧바로 `_duck = 1 - duckAmount` 로
    // 누른다(`engine_guard_test.dart` 의 4-c 와 같은 트리거 방식).
    int framesToRecover(double relSec) {
      final e = Engine()..trackMix.configure(['a']);
      e.duckAmount = 1.0;
      e.duckRelSec = relSec;
      e.drumOn('acoustic', 'kick', 3);
      var frames = 0;
      while (e.duckLevel < 0.99 && frames < 20000) {
        e.render(64);
        frames += 64;
      }
      return frames;
    }

    check('0) 기본값(0.16초)이 그대로 살아있다', Engine().duckRelSec == 0.16, '');

    final fast = framesToRecover(0.05);
    final slow = framesToRecover(0.35);
    check(
      '1) 복귀 시간을 늘리면 돌아오는 데 더 걸린다',
      slow > fast,
      '빠름 $fast 프레임 · 느림 $slow 프레임',
    );

    // ignore: avoid_print
    print(fail == 0 ? '덕킹 복귀 시간 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });

  test('Project — duckAmountOverride/duckRelSec 저장·불러오기 왕복', () {
    var fail = 0;
    void check(String name, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $name — $detail');
      if (!ok) fail++;
    }

    final p = Project.initial();
    check(
      '0) 기본은 override 없음(장르 기본값 따름)',
      p.duckAmountOverride == null && p.duckRelSec == 0.16,
      'override=${p.duckAmountOverride} · rel=${p.duckRelSec}',
    );

    p.duckAmountOverride = 0.62;
    p.duckRelSec = 0.22;
    final j = p.toJson();
    check('1) 만졌으면 저장 파일에 적힌다', j['duck'] == 0.62 && j['duckRel'] == 0.22, '$j');

    final p2 = Project.initial();
    p2.loadJson(j);
    check(
      '2) 불러오면 그대로 돌아온다',
      p2.duckAmountOverride == 0.62 && p2.duckRelSec == 0.22,
      'override=${p2.duckAmountOverride} · rel=${p2.duckRelSec}',
    );

    // 안 만진 프로젝트는 저장 파일에 아예 안 적힌다(옛 앱 호환 — 다른 필드와
    // 같은 규칙, `project.dart` 문서 참고).
    final p3 = Project.initial();
    final j3 = p3.toJson();
    check(
      '3) 기본값이면 저장 파일에 안 남는다',
      !j3.containsKey('duck') && !j3.containsKey('duckRel'),
      '${j3.keys}',
    );

    // 옛 저장 파일(이 칸이 없음)을 불러와도 기본값으로 안전하게 떨어진다.
    final p4 = Project.initial();
    p4.duckAmountOverride = 0.9; // 불러오기 전에 뭔가 있었다는 걸 보이려고
    p4.loadJson({...j3, 'name': '옛 파일'});
    check(
      '4) 옛 파일엔 이 칸이 없어도 기본값으로 떨어진다',
      p4.duckAmountOverride == null && p4.duckRelSec == 0.16,
      'override=${p4.duckAmountOverride} · rel=${p4.duckRelSec}',
    );

    check(
      '5) kGenreDuck 표는 그대로 있다(장르 기본값의 원천)',
      kGenreDuck.isNotEmpty,
      '${kGenreDuck.length}개 장르',
    );

    // ignore: avoid_print
    print(fail == 0 ? 'Project 덕킹 저장 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
