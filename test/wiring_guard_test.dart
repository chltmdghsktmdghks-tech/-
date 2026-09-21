// **배선이 끊겼는지만 본다.** (소리는 못 본다 — 그건 이 자의 몫이 아니다)
//   flutter test test/wiring_guard_test.dart
//
// 여기 있는 것들은 전부 `AudioClient` 로 나가는 명령인데, 그 클래스는 아이솔레이트
// 포트(`_tx`)를 라이브러리 안에 숨긴 구상 클래스라 **시험용 가짜를 끼울 자리가 없다.**
// 위젯 시험은 전부 `host: null` 로 돌아서 이 경로를 아예 안 밟는다.
//
// 그래서 할 수 있는 것만 한다 — **원본에 그 호출이 남아 있는가.** 약한 자다:
// 호출이 있어도 순서가 틀리거나 값이 틀리면 못 잡는다. 대신 **지워지면** 잡는다.
// 여기 걸린 것들은 전부 「한 번 끊겨서 사용자가 겪었던」 배선이라 그것만으로 값이 있다.
//
// 제대로 잡으려면 `AudioClient` 에 시험용 대역을 낼 자리를 만들어야 한다 — 그건
// 이 자의 범위 밖이다. 그 자리가 생기면 이 파일은 지워도 된다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 여는 괄호에서 짝이 맞는 닫는 괄호까지 — 중첩된 블록을 통째로 잘라 낸다.
String _block(String src, int from, String open, String close) {
  final start = src.indexOf(open, from);
  if (start < 0) return '';
  var depth = 0;
  for (var i = start; i < src.length; i++) {
    if (src[i] == open) depth++;
    if (src[i] == close) {
      depth--;
      if (depth == 0) return src.substring(start, i + 1);
    }
  }
  return '';
}

void main() {
  test('배선 지킴이', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final main = File('lib/main.dart').readAsStringSync();

    // ── 1) 곡을 바꿔 열면 곡마다 다른 채널 값을 다시 싣는가 ──
    //
    // `Store.open()` 은 `master.vol` · `master.chain` · 라이브 버스를 그 곡 것으로
    // 바꾸는데, 엔진에 밀어 주는 자리가 **부팅 한 번과 믹서 페이더**뿐이었다.
    // 그래서 마스터를 내려 둔 곡을 열어도 앞 곡 크기로 울리고, 앞 곡에 꽂은
    // 마스터링이 안 꽂은 곡에도 그대로 걸려 있었다. 화면과 소리가 어긋났다.
    {
      final body = _block(
        main,
        main.indexOf('void _syncSongChannels()'),
        '{',
        '}',
      );
      check(
        '1) _syncSongChannels 가 셋을 다 싣는다',
        body.contains('setMasterVol(') &&
            body.contains("setBus('live'") &&
            body.contains('_pushMasterFx('),
        body.isEmpty ? '함수를 못 찾았다' : '마스터볼륨·라이브버스·마스터인서트',
      );
    }

    // ── 2) 곡을 여는 **두 길** 모두에서 부르는가 ──
    //
    // 「내 곡」은 홈(onSongOpened)과 시험 화면(onOpened) 두 군데서 열 수 있다.
    // 한쪽에만 달면 다른 쪽으로 연 곡은 여전히 어긋난다.
    {
      final n = 'onSongOpened:'.allMatches(main).length;
      final opens = <String>[];
      for (final m in RegExp(r'on(Song)?Opened: \(\) \{').allMatches(main)) {
        opens.add(_block(main, m.start, '{', '}'));
      }
      final all =
          opens.isNotEmpty &&
          opens.every((b) => b.contains('_syncSongChannels()'));
      check(
        '2) 곡 여는 길 전부가 부른다',
        all,
        '곡 여는 콜백 ${opens.length}개 · 부르는 것 '
            '${opens.where((b) => b.contains('_syncSongChannels()')).length}개 (onSongOpened $n곳)',
      );
    }

    // ── 3) 앱을 켤 때도 첫 값을 실었는가 ──
    //
    // 여기가 끊기면 「잔향 18% 로 보이는데 실제로는 0」이 된다.
    {
      final boot = _block(main, main.indexOf('Future<void> _boot()'), '{', '}');
      check(
        '3) 부팅에서 첫 값을 싣는다',
        boot.contains('setMasterVol(') &&
            boot.contains("setBus('live'") &&
            boot.contains('setStyleGain(') &&
            boot.contains('_pushMasterFx('),
        boot.isEmpty ? '_boot 를 못 찾았다' : '넷 다 있다',
      );
    }

    // ── 4) 뒤로 가는 순간 저장하는가 ──
    //
    // 자동 저장은 마지막 손짓에서 0.8초 뒤에 쓴다. 음을 찍고 바로 홈을 누르면
    // 그 0.8초가 안 지나서 **방금 만진 것이 사라진다.** 안드로이드는 `paused`
    // 뒤에 앱을 언제든 죽일 수 있으니 거기가 마지막 기회다.
    //
    // **`host` 검사보다 먼저**여야 한다 — 소리 장치를 못 열었어도 만든 건 남아야 한다.
    {
      final body = _block(
        main,
        main.indexOf('void didChangeAppLifecycleState'),
        '{',
        '}',
      );
      // 주석 안에도 같은 글자가 있다 — **코드 줄**만 골라서 견준다.
      final code = [
        for (final l in body.split('\n'))
          if (!l.trimLeft().startsWith('//')) l,
      ].join('\n');
      final saveAt = code.indexOf('store?.saveNow()');
      final hostAt = code.indexOf('final h = host;');
      check(
        '4) 뒤로 갈 때 저장한다 (소리 장치 검사보다 먼저)',
        saveAt >= 0 && hostAt >= 0 && saveAt < hostAt,
        body.isEmpty
            ? '생명주기 함수를 못 찾았다'
            : '저장 ${saveAt >= 0 ? '있음' : '없음'} · '
                  '순서 ${saveAt >= 0 && saveAt < hostAt ? '먼저' : '나중'}',
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '배선 지킴이 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
