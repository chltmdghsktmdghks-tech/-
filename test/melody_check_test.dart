// 5단계 53/N — **멜로디가 멜로디인가** 확인.
//   flutter test test/melody_check_test.dart
//
// 사용자 지적: "멜로디들이 왜 다 아르페지오야 … 코드톤만 쓰지 말라고".
// 실제로 그랬다 — 배열형 6곡의 멜로디가 코드톤 아르페지오였다
// (힙합 벌스 코드톤 92%·도약 91%, 발라드 코러스 **100%/100%**).
//
// 아르페지오와 멜로디를 가르는 것은 '좋다/나쁘다' 같은 취향이 아니라 세 가지 셈이다:
//  · **코드톤 비율** — 100% 면 화음을 풀어 놓은 것이지 선율이 아니다.
//    경과음·보조음(코드 밖 음)이 섞여야 노래가 된다.
//  · **도약 비율** — 아르페지오는 3도씩 뛴다. 사람이 부르는 선율은 순차진행이 많다.
//  · **길이 종류** — 다 같은 길이면 리듬이 없다. 그건 시퀀스지 멜로디가 아니다.
//
// 기준값은 이 프로젝트 안에서 **이미 잘 된 것들**(재즈 색소폰·팝 보컬·프로그 리드)에서
// 가져왔다: 코드톤 40~72% · 도약 20~65% · 길이 3종 이상.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/presets.dart';
import 'package:music_doodle_engine/project.dart';

/// 코드톤 = 3도씩 쌓은 음(1·3·5·8·10·12·15도) → 스케일 도수 0,2,4,7,9,11,14
const _chordTones = {0, 2, 4, 7, 9, 11, 14};

/// **일부러** 아르페지오인 것들 — 여기서 뺀다. 두 종류다:
///
/// 1. 이름부터 도형인 것 — 사용자가 목록에서 「Arp Up」을 고르면 아르페지오가 나와야 한다.
/// 2. **배경 텍스처 슬롯**(plk·arp·harp) — 리드가 아니라 밑에 까는 깔개다.
///    `genre_mix.dart` 에서 볼륨 0.46~0.52 에 하이패스 420~450Hz 로 뒤에 밀어 둔
///    자리라, 16분 아르페지오가 오히려 제 역할이다(프로그하우스가 그렇게 만든 음악이다).
///    멜로디는 그 위의 `lead`/`voc`/`sax`/`bell` 슬롯이 맡는다.
const _byDesign = {
  'Arp Up',
  'Arp Down',
  'Synthpop Arp',
  'Pentatonic',
  'French Chop',
  'Prog Arp',
  'Prog Arp B',
  'Pop Arp',
  'Pop Arp P',
  'Pop Arp C',
  'Trap Pluck H',
  'Amb Harp A',
  'Amb Harp B',
};

(double, double, int) _profile(NotePatternDef d) {
  final degs = [for (final n in d.notes) n[0] as int];
  final ct = degs.where(_chordTones.contains).length / degs.length;
  var leap = 0;
  for (var i = 1; i < degs.length; i++) {
    if ((degs[i] - degs[i - 1]).abs() >= 2) leap++;
  }
  final lp = degs.length > 1 ? leap / (degs.length - 1) : 0.0;
  final lens = <int>{for (final n in d.notes) n[2] as int};
  return (ct, lp, lens.length);
}

void main() {
  test('멜로디', () {
    var fail = 0;
    void check(String name, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $name — $detail');
      if (!ok) fail++;
    }

    // ── 1) 멜로디로 이름 붙은 것은 전부 선율이어야 한다 ──
    final bad = <String>[];
    for (final d in kMelodyPatterns) {
      if (_byDesign.contains(d.name) || d.notes.length < 4) continue;
      final (ct, lp, kinds) = _profile(d);
      // 코드톤만 쓰면서 도약까지 많으면 그건 아르페지오다
      if (ct > 0.85 && lp > 0.6)
        bad.add('${d.name}(코드톤 ${(ct * 100).round()}%)');
      // 길이가 한 종류뿐이면 리듬이 없다
      if (kinds < 2) bad.add('${d.name}(길이 1종)');
    }
    check(
      '1) 아르페지오가 아니다',
      bad.isEmpty,
      bad.isEmpty ? '${kMelodyPatterns.length}개 확인' : bad.join(', '),
    );

    // ── 2) 스타일마다 처음 들리는 멜로디 ──
    // 씬 화면에서 스타일을 고르면 이 패턴이 바로 깔린다 — **첫인상**이라 더 엄격히 본다.
    for (final g in kGenrePresets) {
      final name = g.$7;
      final d = kMelodyPatterns.firstWhere(
        (m) => m.name == name,
        orElse: () => const NotePatternDef('', 0, 0, []),
      );
      if (d.notes.isEmpty) {
        check('2) ${g.$1}', false, '패턴 「$name」을 못 찾음');
        continue;
      }
      final (ct, lp, kinds) = _profile(d);
      check(
        '2) ${g.$1.padRight(6)} $name',
        ct <= 0.80 && kinds >= 3,
        '코드톤 ${(ct * 100).round()}% · 도약 ${(lp * 100).round()}% · 길이 $kinds종',
      );
    }

    // ── 3) 음역 ──
    // 두 옥타브를 헤매면 사람이 못 부른다. 좋은 선율은 대개 한 옥타브 남짓이다.
    for (final d in kMelodyPatterns) {
      if (_byDesign.contains(d.name) || d.notes.isEmpty) continue;
      final degs = [for (final n in d.notes) n[0] as int];
      final span =
          degs.reduce((a, b) => a > b ? a : b) -
          degs.reduce((a, b) => a < b ? a : b);
      if (span > 11) check('3) ${d.name} 음역', false, '$span도 (11도 넘음)');
    }
    check('3) 음역이 한 옥타브 남짓', true, '11도 넘는 것 없음');

    // ── 모티프와 여백 ── (사용자 지적: 「멜로디가 너무너무 구려」)
    //
    // 잰 값이 말해 준 것: 리드 멜로디 여럿이 **모티프 되풀이 0%** 였다.
    // 한 번 나온 말이 다시 안 나오면 아무것도 기억에 안 남는다 — 「구리다」의 실체가 그것이다.
    // (로파이 훅 0% · R&B 벌스 0% · 엠비언트 벨 0% · 드릴 벨 0%)
    //
    // 아르페지오는 뺀다 — **일부러** 코드를 훑는 것이라 이 잣대가 안 맞는다.
    {
      final weak = <String>[];
      final airless = <String>[];
      for (final d in kMelodyPatterns) {
        if (_byDesign.contains(d.name) || d.notes.length < 6) continue;
        final degs = [for (final n in d.notes) n[0] as int];
        final steps = [for (final n in d.notes) n[1] as int];
        final motifs = <String, int>{};
        for (var i = 1; i < degs.length; i++) {
          final k = '${degs[i] - degs[i - 1]}:${steps[i] - steps[i - 1]}';
          motifs[k] = (motifs[k] ?? 0) + 1;
        }
        final again = motifs.values
            .where((v) => v > 1)
            .fold(0, (a, b) => a + b);
        if (again * 100 / (degs.length - 1) < 20) {
          weak.add('${d.name}(${(again * 100 / (degs.length - 1)).round()}%)');
        }
        // 여백 — 판을 꽉 채우면 숨 쉴 자리가 없다
        var filled = 0;
        for (final n in d.notes) {
          filled += n[2] as int;
        }
        final rest = 1 - filled / (d.bars * 16);
        if (rest < 0.03) airless.add('${d.name}(${(rest * 100).round()}%)');
      }
      check(
        '4) 되풀이되는 모티프가 있다',
        weak.isEmpty,
        weak.isEmpty ? '아르페지오 뺀 전 패턴 20% 넘음' : weak.take(5).join(', '),
      );
      check(
        '4-b) 숨 쉴 자리가 있다',
        airless.isEmpty,
        airless.isEmpty ? '전 패턴 여백 3% 넘음' : airless.take(5).join(', '),
      );
    }

    // 5) **코러스는 벌스보다 커져야 한다.**
    //
    // 곡이 「코러스에 왔다」고 느껴지는 이유의 절반은 **음이 올라가는 것**이다.
    // 크기만 커지면 그냥 시끄럽다. 커지는 길은 셋이다 — 높아지거나 · 빽빽해지거나 ·
    // 층이 늘거나. **하나라도** 있으면 된다(트랩의 훅은 벨을 안 올리고 플럭을 얹는다).
    //
    // 가스펠이 그 셋 다 없었다: 벌스도 코러스도 C5~C6 한 옥타브 안이라 코러스에서
    // **더 갈 데가 없었고**, 평균은 오히려 내려갔다(−0.3). 디스코도 +0.8 뿐이었다.
    // 둘 다 벌스를 한 옥타브 내려 고쳤다. 자세한 표는 `lift_meter`.
    {
      const chorusNames = {'코러스', '훅', '드롭'};
      final flat = <String>[];
      var pairs = 0;
      for (final g in kGenres) {
        final p = Project.initial()..setGenre(g.key);
        (double, int, int, int)? v, c;
        for (final sc in p.scenes) {
          final deg = <int>[];
          var layers = 0;
          for (final t in p.tracks.where((x) => x.type == 'melody')) {
            final nm = sc.clips[t.id];
            if (nm == null) continue;
            final nd = p.findNote(t.type, nm);
            if (nd == null || nd.notes.isEmpty) continue;
            layers++;
            for (final e in nd.notes) {
              deg.add(e[0] as int);
            }
          }
          if (deg.isEmpty) continue;
          var sum = 0, hi = -99;
          for (final x in deg) {
            sum += x;
            if (x > hi) hi = x;
          }
          final st = (sum / deg.length, hi, deg.length, layers);
          if (v == null && sc.name == '벌스') v = st;
          if (c == null && chorusNames.contains(sc.name)) c = st;
        }
        if (v == null || c == null) continue; // 벌스/코러스 짝이 없는 얼개는 건너뛴다
        pairs++;
        final grows =
            c.$1 - v.$1 >= 0.5 || // 높아지거나
            c.$2 > v.$2 || // 꼭대기가 올라가거나
            c.$3 > v.$3 * 1.15 || // 빽빽해지거나
            c.$4 > v.$4; // 층이 늘거나
        if (!grows) {
          flat.add(
            '${g.key}(${v.$1.toStringAsFixed(1)}→${c.$1.toStringAsFixed(1)})',
          );
        }
      }
      check(
        '5) 코러스가 벌스보다 커진다',
        flat.isEmpty && pairs >= 8,
        flat.isEmpty ? '$pairs개 스타일' : flat.join(', '),
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '멜로디 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
