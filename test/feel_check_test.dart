// Phase 2 — **느낌 손잡이가 실제로 무엇을 바꾸는가.** (개선 계획 4-4)
//   flutter test test/feel_check_test.dart
//
// 손잡이는 **그럴듯하게 틀리기 쉽다.** 슬라이더는 움직이는데 소리는 그대로여도
// "뭔가 달라진 것 같다"고 넘어간다. 그래서 목록을 직접 세어 본다.
//
// 지키는 것 넷:
//  1. 가운데면 **한 글자도 안 바뀐다** — 기본값이 곧 예전 소리여야 한다
//  2. 기운 — 세기가 오르내린다
//  3. 빽빽함 — 왼쪽은 덜어 내고 오른쪽은 하이햇을 쪼갠다. **골격(킥·스네어)은 남는다**
//  4. 그루브 — 뒷박만 뒤로 밀린다. 앞박은 제자리
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/feel.dart';
import 'package:music_doodle_engine/fill.dart';

/// 16분음표 하나 (120BPM 기준)
const _step = 60.0 / 120 / 4;

/// 한 마디 — 킥 4개(강박) · 하이햇 8분 8개 · 멜로디 16분 8개
(List<List<dynamic>>, List<List<dynamic>>) _bar() {
  final notes = <List<dynamic>>[
    for (var i = 0; i < 8; i++)
      ['lead', 440.0, 0.2, 2, false, 0.0, i * _step * 2, 2],
  ];
  final drums = <List<dynamic>>[
    for (var i = 0; i < 4; i++) ['acoustic', 'kick', 3, 180.0, i * _step * 4],
    for (var i = 0; i < 2; i++)
      ['acoustic', 'snare', 3, 180.0, _step * 4 + i * _step * 8],
    for (var i = 0; i < 8; i++) ['acoustic', 'hat', 2, 180.0, i * _step * 2],
  ];
  return (notes, drums);
}

void main() {
  test('느낌 손잡이', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $what — $detail');
      if (!ok) fail++;
    }

    // ── 1) 가운데면 아무것도 안 한다 ──
    {
      final (n, d) = _bar();
      final before =
          '${n.map((e) => '${e[3]}@${e[6]}').join()}'
          '${d.map((e) => '${e[1]}${e[2]}@${e[4]}').join()}';
      applyFeel(n, d, Feel.none, _step);
      final after =
          '${n.map((e) => '${e[3]}@${e[6]}').join()}'
          '${d.map((e) => '${e[1]}${e[2]}@${e[4]}').join()}';
      check(
        '1) 가운데면 그대로',
        before == after,
        '음 ${n.length}개 · 타격 ${d.length}개 · 글자 하나 안 바뀜',
      );
    }

    // ── 2) 기운 ──
    {
      final (nUp, dUp) = _bar();
      applyFeel(nUp, dUp, const Feel(energy: 1.0), _step);
      final (nDn, dDn) = _bar();
      applyFeel(nDn, dDn, const Feel(energy: 0.0), _step);
      final up = nUp.map((e) => e[3] as int).reduce((a, b) => a + b);
      final dn = nDn.map((e) => e[3] as int).reduce((a, b) => a + b);
      final base = 8 * 2;
      check(
        '2) 신남 쪽은 세지고 차분 쪽은 여려진다',
        up > base && dn < base,
        '차분 $dn ← 보통 $base → 신남 $up (음 8개 합)',
      );
      // 세기는 1~3 을 벗어나면 안 된다
      final ok =
          [
            ...nUp,
            ...nDn,
          ].every((e) => (e[3] as int) >= 1 && (e[3] as int) <= 3) &&
          [
            ...dUp,
            ...dDn,
          ].every((e) => (e[2] as int) >= 1 && (e[2] as int) <= 3);
      check('2-b) 세기가 1~3 을 안 벗어난다', ok, '');
    }

    // ── 3) 빽빽함 ──
    {
      final (nS, dS) = _bar();
      applyFeel(nS, dS, const Feel(density: 0.0), _step);
      final kick = dS.where((e) => e[1] == 'kick').length;
      final snare = dS.where((e) => e[1] == 'snare').length;
      check(
        '3) 단순 쪽 — 덜어 낸다',
        nS.length < 8 && dS.length < 14,
        '음 8→${nS.length}개 · 타격 14→${dS.length}개',
      );
      // **골격은 남아야 한다** — 킥·스네어까지 빼면 곡이 아니라 정적이 된다
      check(
        '3-b) 단순해져도 킥·스네어는 남는다',
        kick == 4 && snare == 2,
        '킥 $kick/4 · 스네어 $snare/2',
      );

      final (nB, dB) = _bar();
      applyFeel(nB, dB, const Feel(density: 1.0), _step);
      final hats = dB.where((e) => e[1] == 'hat').length;
      check('3-c) 빽빽 쪽 — 하이햇이 쪼개진다', hats > 8, '하이햇 8→$hats개');
      // 끼워 넣은 것은 **약해야** 한다 — 같은 세기면 기계로 들린다
      final weakAdded = dB
          .where((e) => e[1] == 'hat')
          .any((e) => (e[2] as int) < 2);
      check('3-d) 끼워 넣은 하이햇은 약하다', weakAdded, '세기가 낮은 것이 섞여 있다');

      // 3-e) **카우벨도 잔가지다.** 한때 이 목록에 카우벨 대신 아무 타격과도 안
      // 맞는 'shake'(소리 낼 때만 쓰는 내부 별명)가 들어 있어서, 카우벨은
      // 밀도를 아무리 올려도 쪼개지지 않는 죽은 자리였다.
      final (nCow, dCow) = _bar();
      dCow.add(['acoustic', 'cowbell', 2, 180.0, _step * 8]);
      dCow.add(['acoustic', 'cowbell', 2, 180.0, _step * 24]);
      applyFeel(nCow, dCow, const Feel(density: 1.0), _step);
      final cows = dCow.where((e) => e[1] == 'cowbell').length;
      check('3-e) 카우벨도 쪼개진다', cows > 2, '카우벨 2→$cows개');
    }

    // ── 4) 그루브 ──
    {
      final (n, d) = _bar();
      final beforeOn = (d[0][4] as num).toDouble(); // 첫 킥(앞박)
      applyFeel(n, d, const Feel(groove: 1.0), _step);
      final hats = d.where((e) => e[1] == 'hat').toList()
        ..sort((a, b) => (a[4] as num).compareTo(b[4] as num));
      // 8분 하이햇 8개 중 홀수 번째(뒷박)만 밀려야 한다
      final onBeat = hats[0][4] as double, offBeat = hats[1][4] as double;
      final eighth = _step * 2;
      check(
        '4) 앞박은 제자리',
        (onBeat - 0).abs() < 1e-9,
        '${onBeat.toStringAsFixed(4)}초',
      );
      check(
        '4-b) 뒷박이 뒤로 밀린다',
        offBeat > eighth + 1e-6 && offBeat < eighth * 1.4,
        '${(eighth * 1000).toStringAsFixed(0)}ms → ${(offBeat * 1000).toStringAsFixed(0)}ms '
            '(셋잇단이면 ${(eighth * 4 / 3 * 1000).toStringAsFixed(0)}ms)',
      );
      check(
        '4-c) 킥 앞박도 제자리',
        ((d.firstWhere((e) => e[1] == 'kick')[4] as num) - beforeOn).abs() <
            1e-9,
        '',
      );
      // 시간 순서가 지켜져야 한다
      var sorted = true;
      for (var i = 1; i < d.length; i++) {
        if ((d[i][4] as num) < (d[i - 1][4] as num)) sorted = false;
      }
      check('4-d) 시간 순서가 지켜진다', sorted, '');
    }

    // ── 4-e) **격자를 판에 맞춘다** ──
    //
    // 처음엔 무조건 8분에 걸었다. 그런데 로파이·힙합·트랩은 16분 기반이라
    // 8분 자리에 있는 타격이 몇 개 안 된다 — 슬라이더를 끝까지 올려도
    // **"스윙 모르겠음"**(사용자 지적) 이었다. 616개 중 88개(14%)만 밀렸다.
    {
      // 16분으로 촘촘한 판 — 16분 셔플이 걸려야 한다
      final d16 = <List<dynamic>>[
        for (var i = 0; i < 16; i++) ['acoustic', 'hat', 2, 180.0, i * _step],
      ];
      applyFeel([], d16, const Feel(groove: 1.0), _step);
      final moved16 = d16
          .where(
            (e) =>
                ((e[4] as double) / _step - ((e[4] as double) / _step).round())
                    .abs() >
                0.01,
          )
          .length;
      check(
        '4-e) 16분 판은 16분 셔플',
        moved16 >= 7,
        '16개 중 $moved16개 밀림 (홀수 자리 8개가 목표)',
      );

      // 8분만 있는 판 — 8분 스윙이 걸려야 한다
      final d8 = <List<dynamic>>[
        for (var i = 0; i < 8; i++)
          ['acoustic', 'hat', 2, 180.0, i * _step * 2],
      ];
      final before8 = [for (final e in d8) e[4] as double];
      applyFeel([], d8, const Feel(groove: 1.0), _step);
      var moved8 = 0;
      for (var i = 0; i < d8.length; i++) {
        if (((d8[i][4] as double) - before8[i]).abs() > 1e-9) moved8++;
      }
      check('4-f) 8분 판은 8분 스윙', moved8 >= 3, '8개 중 $moved8개 밀림 (홀수 자리 4개가 목표)');
    }

    // ── 4-g) **격자는 장르가 정한다** ──
    //
    // 세는 방식으로는 두 장르를 같이 만족시킬 수 없었다. 재즈는 라이드가 16분이라
    // 16분 격자가 뽑히고, 그러면 8분 위의 멜로디가 **한 음도 안 밀린다.**
    // 사용자가 「스윙 느낌이 하나도 안 난다」고 한 자리가 여기다.
    {
      // 8분 위의 음만 있는 멜로디 — 재즈면 밀려야 하고, 로파이(16분 셔플)면 안 밀린다
      List<List<dynamic>> mel() => [
        for (var i = 0; i < 8; i++)
          ['lead', 440.0, 0.2, 2, false, 0.0, i * _step * 2, 2],
      ];
      final jz = mel();
      applyFeel(jz, [], const Feel(groove: 1.0), _step, genre: 'jazz');
      var movedJz = 0;
      for (var i = 0; i < jz.length; i++) {
        if (((jz[i][6] as double) - i * _step * 2).abs() > 1e-9) movedJz++;
      }
      check(
        '4-g) 재즈 — 8분 멜로디가 밀린다',
        movedJz >= 3,
        '8음 중 $movedJz음 (예전엔 92음 중 0음이었다)',
      );

      final lf = mel();
      applyFeel(lf, [], const Feel(groove: 1.0), _step, genre: 'lofi');
      var movedLf = 0;
      for (var i = 0; i < lf.length; i++) {
        if (((lf[i][6] as double) - i * _step * 2).abs() > 1e-9) movedLf++;
      }
      check(
        '4-h) 로파이 — 8분 멜로디는 그대로(16분 셔플)',
        movedLf == 0,
        '8음 중 $movedLf음 밀림',
      );
    }

    // ── 4-i) **워프는 한 쌍의 길이를 안 바꾼다** ──
    //
    // 앞칸을 늘인 만큼 뒷칸을 줄인다. 안 그러면 판이 통째로 길어져서 박이 밀린다.
    {
      final d = <List<dynamic>>[
        for (var i = 0; i < 8; i++) ['acoustic', 'hat', 2, 180.0, i * _step],
      ];
      applyFeel([], d, const Feel(groove: 1.0), _step, genre: 'lofi');
      final t = [for (final e in d) e[4] as double]..sort();
      // 짝수 칸(쌍의 시작)은 제자리여야 한다
      var anchored = true;
      for (var i = 0; i < t.length; i += 2) {
        if ((t[i] - i * _step).abs() > 1e-9) anchored = false;
      }
      check(
        '4-i) 쌍의 시작은 제자리',
        anchored,
        '${t.map((v) => (v / _step).toStringAsFixed(2)).join(' ')}',
      );

      // 뒷칸 잔가지는 여려진다 — 「따-단」의 '단'
      final soft = <List<dynamic>>[
        for (var i = 0; i < 8; i++) ['acoustic', 'hat', 3, 180.0, i * _step],
      ];
      applyFeel([], soft, const Feel(groove: 1.0), _step, genre: 'lofi');
      soft.sort((a, b) => (a[4] as num).compareTo(b[4] as num));
      final onV = soft[0][2] as int, offV = soft[1][2] as int;
      check('4-j) 뒷칸이 여려진다', offV < onV, '앞 $onV · 뒤 $offV');

      // 4-k) 카우벨도 뒷칸이 여려진다 — 4-j 와 같은 자리, 레인만 다르다
      final softCow = <List<dynamic>>[
        for (var i = 0; i < 8; i++)
          ['acoustic', 'cowbell', 3, 180.0, i * _step],
      ];
      applyFeel([], softCow, const Feel(groove: 1.0), _step, genre: 'lofi');
      softCow.sort((a, b) => (a[4] as num).compareTo(b[4] as num));
      final onVc = softCow[0][2] as int, offVc = softCow[1][2] as int;
      check('4-k2) 카우벨도 뒷칸이 여려진다', offVc < onVc, '앞 $onVc · 뒤 $offVc');
    }

    // ── 4-g) 칩에 뭘 만졌는지 뜬다 ──
    // 그루브만 만졌는데 칩에 「보통」(기운)이 뜨면 뭘 만졌는지 알 수가 없다.
    check(
      '4-k) 칩은 제일 많이 움직인 것을 보여 준다',
      const Feel(groove: 0.9).chipWord == '많이 스윙' &&
          const Feel(energy: 1.0).chipWord == '아주 신남' &&
          Feel.none.chipWord == '느낌',
      '그루브만 만지면 「${const Feel(groove: 0.9).chipWord}」',
    );

    // ── 6) 필 ── (계획 6-2)
    //
    // 2분짜리 곡이 **똑같은 4마디의 되풀이**면 아무리 음색이 좋아도 루프로 들린다.
    // 사람이 만든 음악은 매듭을 짓는다.
    //
    // 사용자 지적으로 규칙을 한 번 바꿨다 — 「필인은 송폼이 넘어갈 때나 송폼이 많이
    // 반복되면 넣어야지」. 4마디마다 기계처럼 넣으면 매듭이 너무 잦아서 아무것도
    // 매듭이 아니게 된다. 지금은 **구간 끝**에 넣고, 구간이 길 때만 안쪽에도 넣는다.
    {
      // 4마디 × 2판 = 8마디. 하이햇 8분 + **뒷박 스네어·탐**.
      //
      // 예전 픽스처는 킥·하이햇뿐이었다. 필이 **그 판이 쓰는 악기**로 치게 바꾸면서
      // 그 픽스처는 「스네어가 없는 판」이 됐고, 필도 하이햇으로 굴렀다.
      // 실제 드럼 판에는 뒷박이 있다 — 픽스처를 현실에 맞춘다.
      List<List<dynamic>> bars8() => [
        for (var bar = 0; bar < 8; bar++) ...[
          for (var i = 0; i < 4; i++)
            ['acoustic', 'kick', 3, 180.0, (bar * 16 + i * 4) * _step],
          for (var i = 0; i < 8; i++)
            ['acoustic', 'hat', 2, 180.0, (bar * 16 + i * 2) * _step],
          for (final st in [4, 12])
            ['acoustic', 'snare', 3, 180.0, (bar * 16 + st) * _step],
          ['acoustic', 'tom', 2, 180.0, (bar * 16 + 8) * _step],
        ],
      ];

      final d = bars8();
      final before = d.length;
      final hatBefore = d.where((e) => e[1] == 'hat').length;
      applyFill(d, 'acoustic', _step, 4, 2, const FillSpec(amount: 0.6));

      // 구간 첫 박의 크래시 — 앞 구간이 필로 끝났을 때 부르는 쪽이 켠다
      final withCrash = bars8();
      applyFill(
        withCrash,
        'acoustic',
        _step,
        4,
        2,
        const FillSpec(amount: 0.6),
        crashOnStart: true,
      );
      final crash = withCrash.where((e) => e[1] == 'crash').length;
      final crashAt0 = withCrash.any(
        (e) => e[1] == 'crash' && (e[4] as num).toDouble().abs() < 1e-9,
      );
      check(
        '6) 매듭의 크래시는 다음 구간 첫 박',
        crash >= 1 && crashAt0,
        '$crash개 · 첫 박 ${crashAt0 ? '있음' : '없음'}',
      );

      // 필 자리 = **구간의 마지막 마디**(8마디 구간이면 8마디째)의 마지막 박
      final winFrom = (7 * 16 + 12) * _step, winTo = 8 * 16 * _step;
      final inWin = d.where((e) {
        final t = (e[4] as num).toDouble();
        return t >= winFrom - 1e-9 && t < winTo - 1e-9;
      }).toList();
      final lanes = {for (final e in inWin) e[1] as String};
      check(
        '6-b) 필 자리는 갈아엎는다',
        !lanes.contains('hat') &&
            (lanes.contains('snare') || lanes.contains('tom')),
        '남은 것 ${lanes.join('·')} (하이햇 없음 · 스네어/탐 있음)',
      );

      // **킥은 남는다** — 발이라 필 중에도 계속 밟는다
      check('6-c) 킥은 남는다', lanes.contains('kick'), '');

      // 세기가 **올라가며** 밀어 준다
      final vels = [
        for (final e in inWin)
          if (e[1] != 'kick') e[2] as int,
      ];
      check(
        '6-d) 세기가 올라간다',
        vels.length >= 2 && vels.last >= vels.first,
        vels.join('·'),
      );

      // 하이햇 총수는 줄고, 타격 총수는 늘어난다(필이 더 촘촘하다)
      final hatAfter = d.where((e) => e[1] == 'hat').length;
      check(
        '6-e) 하이햇은 걷히고 타격은 는다',
        hatAfter < hatBefore && d.length > before,
        '하이햇 $hatBefore→$hatAfter · 타격 $before→${d.length}',
      );

      // **가끔은 구간 끝에만.** 8마디 구간에 매듭이 하나여야 한다
      final rare = bars8();
      applyFill(rare, 'acoustic', _step, 4, 2, const FillSpec(amount: 0.3));
      // 필은 **마디의 마지막 4스텝**에 깔린다. 판이 원래 갖고 있는 뒷박 스네어와
      // 섞이지 않게 그 창 안만 센다(예전 픽스처엔 스네어가 없어서 그냥 셌다).
      int fillWindows(List<List<dynamic>> x) {
        final bars = <int>{};
        for (final e in x) {
          if (e[1] != 'snare' && e[1] != 'tom') continue;
          final step = ((e[4] as num).toDouble() / _step).round();
          // 필은 12~15칸에 깔린다. 12칸은 판이 원래 갖고 있는 뒷박 자리라
          // **13칸부터**만 센다 — 원래 있던 것과 안 섞인다.
          if (step % 16 < 13) continue;
          bars.add(step ~/ 16);
        }
        return bars.length;
      }

      check(
        '6-g) 가끔 = 구간 끝에만',
        fillWindows(rare) == 1,
        '매듭 ${fillWindows(rare)}군데 (8마디 구간)',
      );

      // **자주면 안쪽에도.** 16마디 구간이면 4마디마다
      final long = <List<dynamic>>[
        for (var bar = 0; bar < 16; bar++) ...[
          for (var i = 0; i < 4; i++)
            ['acoustic', 'kick', 3, 180.0, (bar * 16 + i * 4) * _step],
          for (var i = 0; i < 8; i++)
            ['acoustic', 'hat', 2, 180.0, (bar * 16 + i * 2) * _step],
          for (final st in [4, 12])
            ['acoustic', 'snare', 3, 180.0, (bar * 16 + st) * _step],
        ],
      ];
      applyFill(long, 'acoustic', _step, 4, 4, const FillSpec(amount: 1.0));
      check(
        '6-h) 자주 = 안쪽에도',
        fillWindows(long) >= 3,
        '매듭 ${fillWindows(long)}군데 (16마디 구간)',
      );

      // 6-i) **그 판에 없는 악기로는 안 친다.**
      //
      // 엠비언트 타악기 판(`Amb Perc`)에는 크래시·림·셰이커만 있다 — 곡 전체에
      // 스네어도 탐도 없는데 **필에서만 나왔다.** 그 장르에 없는 악기가 매듭에서만
      // 튀어나오면 그건 매듭이 아니라 사고다.
      final soft = <List<dynamic>>[
        for (var bar = 0; bar < 8; bar++) ...[
          ['lofi', 'shaker', 2, 180.0, (bar * 16) * _step],
          ['lofi', 'rim', 2, 180.0, (bar * 16 + 8) * _step],
        ],
      ];
      applyFill(soft, 'lofi', _step, 4, 2, const FillSpec(amount: 0.6));
      final softLanes = {for (final e in soft) e[1] as String};
      check(
        '6-i) 없는 악기로는 안 친다',
        !softLanes.contains('snare') && !softLanes.contains('tom'),
        '쓴 것 ${(softLanes.toList()..sort()).join('·')}',
      );

      // 끄면 **한 글자도 안 바뀐다**
      final off = bars8();
      final sig = off.map((e) => '${e[1]}${e[4]}').join();
      applyFill(off, 'acoustic', _step, 4, 2, FillSpec.none);
      check('6-f) 끄면 그대로', off.map((e) => '${e[1]}${e[4]}').join() == sig, '');
    }

    // ── 5) 저장 왕복 ──
    {
      const f = Feel(energy: 0.8, density: 0.2, groove: 0.6);
      final back = Feel.fromJson(f.toJson());
      check(
        '5) 저장·되살리기',
        back.energy == 0.8 && back.density == 0.2 && back.groove == 0.6,
        '${back.energy}/${back.density}/${back.groove}',
      );
      check('5-b) 없으면 가운데', Feel.fromJson(null).isDefault, '옛 파일도 안전');
    }

    // ignore: avoid_print
    print(fail == 0 ? '느낌 손잡이 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
