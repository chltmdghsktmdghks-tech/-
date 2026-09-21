// Phase 4 — **구간 이름이 소리를 바꾸는가.** (개선 계획 6-3)
//   flutter test test/arrange_check_test.dart
//
// 곡에는 이미 인트로·빌드업·드롭·브레이크·아웃트로가 이름으로 붙어 있었다.
// 그런데 그 이름이 아무 일도 안 했다 — 빌드업이 벌스와 똑같이 들리면 이름표일 뿐이다.
//
// 지키는 것:
//  1. 모르는 이름(normal)이면 **한 글자도 안 바뀐다**
//  2. 빌드업 — 뒤로 갈수록 세지고 촘촘해진다. 마지막 마디는 발이 멎는다
//  3. 드롭 — **골격만** 세진다(전부 올리면 강약이 사라진다)
//  4. 브레이크 — 잔가지가 걷히고 **골격은 남는다**
//  5. 아웃트로 — 잦아든다
//  6. 실제 곡에서 코러스가 벌스보다 세다
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/arrange.dart';
import 'package:music_doodle_engine/genre_mix.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';

const _step = 60.0 / 120 / 4; // 16분음표
const _bar = _step * 16;
const _twigs = {'hat', 'shaker', 'cowbell', 'ride'};

/// 4마디 — 킥 4개/마디 · 하이햇 8분 · 스네어 2개/마디
(List<List<dynamic>>, List<List<dynamic>>) _bars(int n) {
  final notes = <List<dynamic>>[];
  final drums = <List<dynamic>>[];
  for (var b = 0; b < n; b++) {
    final t0 = b * _bar;
    for (var i = 0; i < 4; i++) {
      drums.add(['acoustic', 'kick', 3, 180.0, t0 + i * _step * 4]);
    }
    for (var i = 0; i < 2; i++) {
      drums.add([
        'acoustic',
        'snare',
        3,
        180.0,
        t0 + _step * 4 + i * _step * 8,
      ]);
    }
    for (var i = 0; i < 8; i++) {
      drums.add(['acoustic', 'hat', 2, 180.0, t0 + i * _step * 2]);
    }
    for (var i = 0; i < 4; i++) {
      notes.add(['lead', 440.0, 0.2, 2, false, 0.0, t0 + i * _step * 4, 2]);
    }
  }
  drums.sort((a, b) => (a[4] as num).compareTo(b[4] as num));
  return (notes, drums);
}

double _avgVel(List<List<dynamic>> d, int idx, bool Function(List<dynamic>) f) {
  var s = 0, n = 0;
  for (final e in d) {
    if (!f(e)) continue;
    s += e[idx] as int;
    n++;
  }
  return n == 0 ? 0 : s / n;
}

void main() {
  test('구간 성격', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    // ── 1) 이름 → 성격 ──
    {
      final want = {
        '빌드업': SectionRole.build,
        '프리훅': SectionRole.build,
        '프리': SectionRole.build,
        '드롭': SectionRole.drop,
        '코러스': SectionRole.drop,
        '훅': SectionRole.drop,
        '브레이크': SectionRole.breakDown,
        '브레이크다운': SectionRole.breakDown,
        '브레이크2': SectionRole.breakDown,
        '정적': SectionRole.breakDown,
        '인트로': SectionRole.intro,
        '여명': SectionRole.intro,
        '아웃트로': SectionRole.outro,
        '해질녘': SectionRole.outro,
        '벌스': SectionRole.normal,
        '헤드': SectionRole.normal,
        '내가 지은 이름': SectionRole.normal,
      };
      final bad = [
        for (final e in want.entries)
          if (roleOf(e.key) != e.value) '${e.key}→${roleOf(e.key).name}',
      ];
      check(
        '1) 이름이 성격을 정한다',
        bad.isEmpty,
        bad.isEmpty ? '${want.length}개 전부' : bad.join(', '),
      );
    }

    // ── 2) 모르는 이름이면 그대로 ──
    {
      final (n, d) = _bars(4);
      final sig =
          '${n.map((e) => '${e[3]}@${e[6]}').join()}'
          '${d.map((e) => '${e[1]}${e[2]}@${e[4]}').join()}';
      applyArrange(n, d, SectionRole.normal, _step, totalSec: _bar * 4);
      final after =
          '${n.map((e) => '${e[3]}@${e[6]}').join()}'
          '${d.map((e) => '${e[1]}${e[2]}@${e[4]}').join()}';
      check('2) 보통 구간은 한 글자도 안 바뀐다', sig == after, '');
    }

    // ── 3) 빌드업 ──
    {
      final (n, d) = _bars(4);
      final hatBefore = d.where((e) => e[1] == 'hat').length;
      applyArrange(n, d, SectionRole.build, _step, totalSec: _bar * 4);
      final half = _bar * 2;
      final front = _avgVel(d, 2, (e) => (e[4] as num) < half);
      final back = _avgVel(d, 2, (e) => (e[4] as num) >= half);
      check(
        '3) 빌드업 — 뒤가 더 세다',
        back > front,
        '앞 ${front.toStringAsFixed(2)} → 뒤 ${back.toStringAsFixed(2)}',
      );

      final hatAfter = d.where((e) => e[1] == 'hat').length;
      check(
        '3-b) 뒤에서 촘촘해진다',
        hatAfter > hatBefore,
        '하이햇 $hatBefore → $hatAfter',
      );

      final lastBar = _bar * 3;
      final kickLast = d
          .where((e) => e[1] == 'kick' && (e[4] as num) >= lastBar)
          .length;
      check('3-c) 마지막 마디는 발이 멎는다', kickLast == 0, '킥 $kickLast개');

      // 짧은 구간에서는 안 한다 — 2마디짜리에서 절반이 발 없이 가면 곤란하다
      final (n2, d2) = _bars(2);
      applyArrange(n2, d2, SectionRole.build, _step, totalSec: _bar * 2);
      check(
        '3-d) 짧은 빌드업은 발을 안 뺀다',
        d2.any((e) => e[1] == 'kick' && (e[4] as num) >= _bar),
        '2마디 구간 · 뒷마디 킥 ${d2.where((e) => e[1] == 'kick' && (e[4] as num) >= _bar).length}개',
      );
    }

    // ── 4) 드롭 — 골격만 ──
    {
      final (n, d) = _bars(4);
      final hatBefore = _avgVel(d, 2, (e) => e[1] == 'hat');
      // 골격이 이미 3이면 못 오르니 2로 낮춰 놓고 본다
      for (final e in d) {
        if (e[1] == 'kick' || e[1] == 'snare') e[2] = 2;
      }
      applyArrange(n, d, SectionRole.drop, _step, totalSec: _bar * 4);
      final hatAfter = _avgVel(d, 2, (e) => e[1] == 'hat');
      final kickAfter = _avgVel(d, 2, (e) => e[1] == 'kick');
      check('4) 드롭 — 골격이 세진다', kickAfter > 2, '킥 2 → $kickAfter');
      check(
        '4-b) 잔가지는 그대로 — 강약이 살아 있다',
        hatAfter == hatBefore,
        '하이햇 $hatBefore → $hatAfter (전부 올리면 3으로 몰려 납작해진다)',
      );
    }

    // ── 5) 브레이크 ──
    {
      final (n, d) = _bars(4);
      applyArrange(n, d, SectionRole.breakDown, _step, totalSec: _bar * 4);
      final twig = d.where((e) => _twigs.contains(e[1] as String)).length;
      final kick = d.where((e) => e[1] == 'kick').length;
      final snare = d.where((e) => e[1] == 'snare').length;
      check('5) 브레이크 — 잔가지가 걷힌다', twig == 0, '남은 잔가지 $twig개');
      check('5-b) 골격은 남는다', kick == 16 && snare == 8, '킥 $kick · 스네어 $snare');
      check(
        '5-c) 여려진다',
        _avgVel(d, 2, (e) => e[1] == 'kick') < 3,
        '킥 ${_avgVel(d, 2, (e) => e[1] == 'kick')}',
      );
    }

    // ── 6) 아웃트로 ──
    {
      final (n, d) = _bars(4);
      applyArrange(n, d, SectionRole.outro, _step, totalSec: _bar * 4);
      final front = _avgVel(d, 2, (e) => (e[4] as num) < _bar);
      final back = _avgVel(d, 2, (e) => (e[4] as num) >= _bar * 3);
      check(
        '6) 아웃트로 — 잦아든다',
        back < front,
        '앞 ${front.toStringAsFixed(2)} → 뒤 ${back.toStringAsFixed(2)}',
      );
    }

    // ── 7) 인트로 ──
    {
      final (n, d) = _bars(4);
      final hatBefore = d.where((e) => e[1] == 'hat').length;
      applyArrange(n, d, SectionRole.intro, _step, totalSec: _bar * 4);
      check(
        '7) 인트로 — 잔가지가 준다',
        d.where((e) => e[1] == 'hat').length < hatBefore,
        '하이햇 $hatBefore → ${d.where((e) => e[1] == 'hat').length}',
      );
      check(
        '7-b) 골격 세기는 그대로 — 들어오는 자리는 들려야 한다',
        _avgVel(d, 2, (e) => e[1] == 'kick') == 3,
        '',
      );
    }

    // ── 8) 실제 곡에서 ──
    //
    // **구간끼리 견주지 않는다.** 발라드는 코러스 패턴이 벌스보다 드럼이 성긴데,
    // 그건 패턴 데이터가 그렇게 쓰인 것이지 편곡이 못 한 게 아니다(내용은 Phase 5 몫).
    // 여기서 물어야 할 것은 **「성격을 걸면 안 걸었을 때보다 그쪽으로 가는가」** 다.
    {
      final bad = <String>[];
      for (final g in kGenreDuck.keys) {
        final tr = Transport();
        final on = Project.initial()..setGenre(g);
        final off = Project.initial()..setGenre(g);
        final bOn = SceneSequencer.buildSong(on, tr);
        final bOff = SceneSequencer.buildSongPlain(off, tr);
        final spans = SceneSequencer.songSpans(on, tr);

        /// 초당 세기 총량. [drum] 이 false 면 음(멜로디·베이스) 쪽을 본다.
        double energy(SceneBuild b, SectionRole r, {bool drum = true}) {
          var s = 0;
          var sec = 0.0;
          for (var i = 0; i < spans.length; i++) {
            if (roleOf(on.scenes[on.song.sections[i].scene].name) != r)
              continue;
            final (st, du) = spans[i];
            sec += du;
            for (final e in drum ? b.drums : b.notes) {
              final t = (e[drum ? 4 : 6] as num).toDouble();
              if (t < st || t >= st + du) continue;
              s += e[drum ? 2 : 3] as int;
            }
          }
          return sec <= 0 ? -1 : s / sec;
        }

        // **드롭은 드럼으로 못 잰다.** 라이브러리 패턴의 킥·스네어는 이미 세기 3 이라
        // 올릴 데가 없다 — 드롭에서 실제로 달라지는 건 멜로디·베이스다.
        // 드롭의 대비는 앞의 빌드업과 낮춰 놓은 다른 구간에서 나온다.
        {
          final a = energy(bOff, SectionRole.drop, drum: false);
          final b = energy(bOn, SectionRole.drop, drum: false);
          if (a > 0 && b <= a * 1.02) bad.add('$g drop 음이 안 세짐');
        }

        for (final e in {
          SectionRole.breakDown: -1,
          SectionRole.intro: -1,
          SectionRole.outro: -1,
        }.entries) {
          final a = energy(bOff, e.key), b = energy(bOn, e.key);
          if (a < 0 || a == 0) continue; // 그 성격이 없거나 드럼이 없는 곡
          final up = b > a * 1.02, down = b < a * 0.98;
          if (e.value > 0 && !up) bad.add('$g ${e.key.name} 안 세짐');
          if (e.value < 0 && !down) bad.add('$g ${e.key.name} 안 여려짐');
        }
      }
      check(
        '8) 성격을 걸면 그쪽으로 간다',
        bad.isEmpty,
        bad.isEmpty ? '11개 장르 × 드롭(음)·브레이크·인트로·아웃트로' : bad.take(5).join(', '),
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '구간 성격 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
