// 곡 재생 중 씬 전환 확인 — 사용자 요청(2026-09-13):
// "씬에서 재생중에 송폼 바꾸면 재생중인 송폼 끝나고 바뀐 송폼으로
//  재생되게해 라이브에서도"
//   flutter test test/song_loop_switch_check_test.dart
//
// 실기기에서 "안 넘어가고 반복되던데"로 잡은 문제 — 「곡 재생」(구간을 전부
// 이어붙인 한 판, 몇 분짜리)이 도는 중에 씬 화면에서 다른 씬을 누르면,
// `refreshLoop` 가 "다음 판부터"를 그 몇 분 뒤로 잡아서 씬을 눌러도 한참
// 동안 아무 일도 안 일어났다. `Transport.songLoop` 로 "지금 도는 게 곡
// 재생인가"를 구분해, 곡 재생 중이면 다음 판을 기다리지 않고 그 자리에서
// 씬 루프로 바로 갈아탄다.
import 'package:music_doodle_engine/project.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Transport.songLoop — 기본은 꺼짐, 씬·곡 재생이 서로 갈아 끼운다', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final tr = Transport();
    check('1) 기본은 꺼짐(씬 루프)', !tr.songLoop, '${tr.songLoop}');

    tr.songLoop = true;
    check('2) 곡 재생 쪽에서 켤 수 있다', tr.songLoop, '${tr.songLoop}');

    tr.songLoop = false;
    check('3) 씬 재생 쪽에서 다시 끌 수 있다', !tr.songLoop, '${tr.songLoop}');

    expect(fail, 0);
  });
}
