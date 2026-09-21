// **한 통이 잘못 왔다고 소리가 영영 안 나면 안 된다.**
//   flutter test test/isolate_msg_test.dart
//
// 오디오는 별도 아이솔레이트에서 돈다. `Isolate.spawn` 은 기본이
// `errorsAreFatal: true` 라 **메시지 처리에서 예외가 하나 새면 그 아이솔레이트가
// 통째로 죽는다** — 앱은 멀쩡히 살아 있는데 그때부터 소리만 안 난다. 오류 창도
// 안 뜬다. 사용자에게는 「갑자기 소리가 안 남」으로만 보인다.
//
// 메시지 규약은 계속 는다(이번에 `_cBus` 에 넷을 더했다). 보내는 쪽과 받는 쪽이
// 한 번 어긋나는 순간 위의 일이 벌어진다. 그래서 **일부러 망가뜨려 던져 본다.**
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/audio_isolate.dart';
import 'package:music_doodle_engine/engine.dart';

void main() {
  test('망가진 메시지', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    // 처리기가 실패를 로그로 찍는다 — 여기서는 **일부러** 망가뜨리므로
    // 그 줄이 열넷씩 쏟아진다. 시험 출력이 안 읽히게 잠깐 막는다.
    final sawLog = <String>[];
    final keep = debugPrint;
    debugPrint = (String? s, {int? wrapWidth}) => sawLog.add(s ?? '');
    addTearDown(() => debugPrint = keep);

    final engine = Engine()..trackMix.configure(['a', 'b']);
    final loop = LoopState();
    var resets = 0;
    int send(List m, [int ahead = 3072]) =>
        handleAudioMessage(m, engine, loop, ahead, () => resets++);

    // 말이 되는 것부터 — 이게 안 되면 아래가 다 무의미하다
    var ok = true;
    try {
      send([0, 'piano', 440.0, 0.5, 3, false, 0.0, 0.0, 0]); // _cNote
      send([2]); // _cOff
      send([4]); // _cReset
      send([18, 0.3]); // _cDuck
      // 19·20(잠들기/깨기)은 아이솔레이트 본체가 가로채므로 여기까지 안 온다.
      // 그래도 흘러들었을 때 **조용히 넘어가야** 한다 — 던지면 소리가 영영 끊긴다.
      send([19]); // _cSleep
      send([20]); // _cWake
    } catch (e) {
      ok = false;
    }
    check('1) 멀쩡한 메시지는 그대로 돈다', ok && resets == 1, '리셋 $resets번');

    // 망가진 것들 — **하나도 던지면 안 된다**
    final broken = <(String, List)>[
      ('빈 목록', <dynamic>[]),
      ('모르는 번호', [999]),
      ('음수 번호', [-1]),
      ('칸이 모자람', [0, 'piano']), // _cNote 인데 인자 두 개
      ('형이 다름', [0, 123, 'x', null, 'vel', 0, 0, 0, 0]),
      ('버스 이름이 숫자', [10, 42, 1.0]),
      ('버스 값이 문자', [10, 'a', 'loud']),
      ('루프에 목록 아님', [13, 'x', 'y', 1.0, true]),
      ('슬롯이 목록 아님', [12, 'nope']),
      ('마스터가 짧음', [8, 0.0]),
      ('인서트가 이상함', [15, 'a', 'not-a-list']),
      ('앞당김이 문자', [3, 'far']),
      ('장르가 숫자', [9, 7]),
      ('null 만', [null]),
    ];
    final threw = <String>[];
    for (final (name, m) in broken) {
      try {
        send(m);
      } catch (e) {
        threw.add('$name($e)');
      }
    }
    check(
      '2) 망가진 메시지에도 안 던진다',
      threw.isEmpty,
      threw.isEmpty ? '${broken.length}가지 다 견딤' : threw.join(', '),
    );

    // **그 뒤에도 멀쩡히 돈다** — 죽지 않았다는 것을 이걸로 확인한다
    var after = true;
    try {
      send([0, 'piano', 440.0, 0.5, 3, false, 0.0, 0.0, 0]);
      send([3, 4096]);
      send([4]);
    } catch (e) {
      after = false;
    }
    check('3) 망가진 것을 받고도 그다음이 돈다', after && resets == 2, '리셋 $resets번');

    // 앞당김 값은 제대로 돌아와야 한다(안 그러면 급식이 어긋난다)
    check(
      '4) 바뀐 값이 돌아온다',
      send([3, 5120]) == 5120 && send([2]) == 3072,
      '_cAhead → 5120 · 그 외 → 그대로',
    );

    // 조용히 넘어간 게 아니라 **로그에는 남는지**까지 본다 —
    // 삼키기만 하면 다음 사람이 왜 이상한지 알 길이 없다.
    check('5) 버린 메시지는 로그에 남는다', sawLog.length >= 10, '${sawLog.length}줄');

    // ignore: avoid_print
    print(fail == 0 ? '망가진 메시지 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
