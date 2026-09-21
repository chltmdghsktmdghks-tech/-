// 악기 콘텐츠팩 분리(2단계)가 맞게 나뉘었는지 — 기본팩/추가팩이 겹치거나
// 빠뜨린 악기가 없는지만 본다. 표본 재생 자체는 `sampler_check_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/instrument_packs.dart';
import 'package:music_doodle_engine/instruments.dart';

void main() {
  test('악기 콘텐츠팩 — 기본팩·추가팩이 정확히 전부를 나눠 갖는다', () {
    var fail = 0;
    void check(String name, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '  X '} $name — $detail');
      if (!ok) fail++;
    }

    final all = INSTRUMENTS.keys.toSet();
    final base = kBaseInstrumentKeys.toSet();
    final addon = kAddonInstrumentKeys.toSet();

    check(
      '1) 기본팩·추가팩이 안 겹친다',
      base.intersection(addon).isEmpty,
      '겹침: ${base.intersection(addon)}',
    );
    check(
      '2) 둘을 합치면 전체 악기와 같다(빠진 것 없음)',
      base.union(addon).difference(all).isEmpty &&
          all.difference(base.union(addon)).isEmpty,
      '빠짐: ${all.difference(base.union(addon))} · 남는 것: ${base.union(addon).difference(all)}',
    );
    check(
      '3) 표본 악기(피아노·바이올린·트럼펫·첼로)가 추가팩에 있다',
      addon.containsAll({'piano', 'violin', 'trumpet', 'cello'}),
      '실제: $addon',
    );
    check(
      '4) 악기마다 속한 팩이 정확히 하나다',
      all.every((k) => instrumentPackOf(k) != null),
      '못 찾은 악기: ${all.where((k) => instrumentPackOf(k) == null)}',
    );

    // ignore: avoid_print
    print(fail == 0 ? '악기팩 분리 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
