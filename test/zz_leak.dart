import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/dsp.dart';
import 'package:music_doodle_engine/engine.dart';
import 'package:music_doodle_engine/synth.dart';

void main() {
  test('엔진을 여러 번 만들면', () {
    Human.setLevel(0);
    // ignore: avoid_print
    void pr(String s) => print(s);
    for (final n in [20, 40, 80]) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < n; i++) {
        final e = Engine()..trackMix.configure(['a', 'b', 'c']);
        e.scheduleDrum(0.0, 'acoustic', 'kick', 3);
        e.schedule(0.0, 'epiano', 261.63, 0.5, 2, part: kPartChord);
        // 1초만 돌린다
        var done = 0;
        while (done < kSampleRate) {
          e.render(1024);
          done += 1024;
        }
      }
      pr(
        '엔진 $n개: ${sw.elapsedMilliseconds}ms '
        '(개당 ${(sw.elapsedMilliseconds / n).toStringAsFixed(1)}ms)',
      );
    }
  });
}
