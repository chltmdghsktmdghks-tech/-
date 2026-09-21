// Phase 5 — **장르 하나가 빠짐없이 갖춰졌는가.** (개선 계획 7-1)
//   flutter test test/genre_check_test.dart
//
// 장르를 더하려면 예전엔 6개 파일의 8개 표를 고쳐야 했다. 하나만 빠뜨려도
// **조용히 반쪽짜리 장르**가 된다 — 소리는 나는데 펌핑이 없거나, 스윙이 안 걸리거나,
// 무대가 파랗기만 하거나, 고르는 화면에 설명이 비어 있다. **오류도 안 난다.**
//
// 얇은 값들은 `kGenres` 한 표로 모았고, 덩치 큰 둘(구간 구성·믹스 편성)은 제자리에
// 뒀다. 그 둘까지 빠짐없는지는 **여기서** 지킨다. 표를 합치는 게 목적이 아니라
// **빠뜨림을 못 하게 막는 것**이 목적이다.
import 'package:flutter_test/flutter_test.dart';
import 'package:music_doodle_engine/arrange.dart';
import 'package:music_doodle_engine/drums.dart';
import 'package:music_doodle_engine/genre_mix.dart';
import 'package:music_doodle_engine/mixer.dart';
import 'package:music_doodle_engine/genres.dart';
import 'package:music_doodle_engine/instruments.dart'
    show ALL_VOICES, VOICE_LABEL, kVoiceFamily, INSTRUMENTS;
import 'package:music_doodle_engine/patterns.dart';
import 'package:music_doodle_engine/presets.dart';
import 'package:music_doodle_engine/project.dart';
import 'package:music_doodle_engine/sequencer.dart';
import 'package:music_doodle_engine/song.dart';
import 'package:music_doodle_engine/ui/create_sheet.dart';
import 'package:music_doodle_engine/ui/show_band.dart';

void main() {
  test('장르가 빠짐없이 갖춰졌는가', () {
    var fail = 0;
    void check(String what, bool ok, String detail) {
      // ignore: avoid_print
      print('${ok ? '  OK' : '실패'} $what — $detail');
      if (!ok) fail++;
    }

    final keys = [for (final g in kGenres) g.key];
    check(
      '0) 장르 ${keys.length}개',
      keys.toSet().length == keys.length,
      keys.join(' · '),
    );

    // ── 1) 큰 구조 둘: 구간 구성 · 믹스 편성 ──
    {
      final noForm = [
        for (final k in keys)
          if (!kSongForms.containsKey(k) && !kObjectSongForms.containsKey(k)) k,
      ];
      check(
        '1) 구간 구성이 있다',
        noForm.isEmpty,
        noForm.isEmpty ? '전부' : '없음: ${noForm.join(', ')}',
      );

      final noMix = [
        for (final k in keys)
          if (!kGenreMix.containsKey(k)) k,
      ];
      check(
        '1-b) 믹스 편성이 있다',
        noMix.isEmpty,
        noMix.isEmpty ? '전부' : '없음: ${noMix.join(', ')}',
      );
    }

    // ── 2) 얇은 값들 ──
    {
      final bad = <String>[];
      for (final g in kGenres) {
        if (g.label.isEmpty) bad.add('${g.key} 이름');
        if (g.feel.isEmpty) bad.add('${g.key} 설명');
        if (g.bpm < 40 || g.bpm > 220) bad.add('${g.key} 템포 ${g.bpm}');
        if (!DRUM_KITS.containsKey(g.kit)) bad.add('${g.key} 키트 ${g.kit}');
        if (g.mode != 'minor' && g.mode != 'major')
          bad.add('${g.key} 조 ${g.mode}');
        if (g.duck < 0 || g.duck > 1) bad.add('${g.key} 비켜주기 ${g.duck}');
        if (g.swingGrid != 8 && g.swingGrid != 16) {
          bad.add('${g.key} 스윙격자 ${g.swingGrid}');
        }
        if (g.lights.length != 3) bad.add('${g.key} 조명 ${g.lights.length}색');
      }
      // 2-b) **고르는 화면의 카드 색**(lights[0]) 이 겹치면 두 장르가 같은 것으로 보인다.
      // 값이 다 「제정신」이어도 두 장르가 같은 색이면 조용히 반쪽짜리다.
      {
        final byColor = <int, List<String>>{};
        for (final g in kGenres) {
          (byColor[g.lights[0]] ??= []).add(g.key);
        }
        final same = [
          for (final e in byColor.entries)
            if (e.value.length > 1) e.value.join('='),
        ];
        check(
          '2-b) 카드 색이 안 겹친다',
          same.isEmpty,
          same.isEmpty ? '${byColor.length}가지 색' : same.join(' / '),
        );
      }

      check(
        '2) 값이 다 제정신이다',
        bad.isEmpty,
        bad.isEmpty ? '${kGenres.length}개 × 8항목' : bad.take(4).join(', '),
      );
    }

    // ── 3) 대표 패턴 넷이 실제로 있다 ──
    {
      final missing = <String>[];
      for (final g in kGenres) {
        if (findDrumPattern(g.drumPat) == null)
          missing.add('${g.key} 드럼 ${g.drumPat}');
        for (final e in {
          'bass': g.bassPat,
          'chord': g.chordPat,
          'melody': g.melodyPat,
        }.entries) {
          final lib = e.key == 'bass'
              ? kBassPatterns
              : (e.key == 'chord' ? kChordPatterns : kMelodyPatterns);
          if (!lib.any((d) => d.name == e.value)) {
            missing.add('${g.key} ${e.key} ${e.value}');
          }
        }
      }
      check(
        '3) 대표 패턴이 라이브러리에 있다',
        missing.isEmpty,
        missing.isEmpty
            ? '${kGenres.length}개 × 4개'
            : missing.take(4).join(', '),
      );
    }

    // ── 4) 파생 표가 전부 같은 키를 덮는다 ──
    {
      final gaps = <String>[];
      void cover(String name, Iterable<String> got) {
        final miss = [
          for (final k in keys)
            if (!got.contains(k)) k,
        ];
        if (miss.isNotEmpty) gaps.add('$name: ${miss.join(',')}');
      }

      cover('비켜주기', kGenreDuck.keys);
      cover('스윙격자', kGenreSwingGrid.keys);
      cover('한줄설명', kGenreFeel.keys);
      cover('무대조명', kStageLights.keys);
      cover('곡스타일', [for (final g in kSongGenres) g.$1]);
      check(
        '4) 파생 표가 빠짐없다',
        gaps.isEmpty,
        gaps.isEmpty ? '5개 표 전부' : gaps.join(' · '),
      );
      check(
        '4-b) 대표 패턴 표도 같은 수',
        kGenrePresets.length == kGenres.length,
        '${kGenrePresets.length}/${kGenres.length}',
      );
    }

    // ── 5) **실제로 소리가 나는가** ── 표만 채우고 안 울리면 소용없다
    {
      final silent = <String>[];
      final short = <String>[];
      final long = <String>[];
      for (final k in keys) {
        final p = Project.initial()..setGenre(k);
        final tr = Transport()
          ..bpm = genreDef(k).bpm
          ..mode = genreDef(k).mode;
        final b = SceneSequencer.buildSong(p, tr);
        if (b.notes.isEmpty && b.drums.isEmpty) silent.add(k);
        if (b.totalSec < 30) short.add('$k ${b.totalSec.round()}초');
        // **너무 길어도 안 된다.** 낙서장이지 앨범이 아니다 —
        // 가스펠을 78BPM 에 16마디 구간으로 짜니 5분 45초가 나왔다.
        // 다 듣기 전에 화면을 닫는 길이는 만들면 안 된다.
        if (b.totalSec > 270) {
          long.add(
            '$k ${b.totalSec ~/ 60}:'
            '${(b.totalSec.round() % 60).toString().padLeft(2, '0')}',
          );
        }
        // 씬 하나만 틀어도 소리가 나야 한다
        final one = SceneSequencer.build(p, tr, reps: 1);
        if (one.notes.isEmpty && one.drums.isEmpty) silent.add('$k(씬)');
      }
      // 5-d) 곡이 쓰는 **음색**이 네 표에 빠짐없이 들었는가.
      //
      // 'vocal' 이 실제로 그랬다 — 소리는 나는데 `VOICE_LABEL`·`ALL_VOICES`·
      // `kVoiceFamily` 셋에서 빠져 있었다. 그래서 화면이 전부 한국어인데
      // 그 트랙만 「vocal」로 나왔고, **고르는 목록에 없어서 한 번 바꾸면
      // 되돌릴 수 없었다.** 오류는 안 났다 — 그런 게 제일 오래 남는다.
      {
        final used = <String>{};
        for (final f in kObjectSongForms.values) {
          for (final t in f.tracks) {
            if (t.type != 'drum') used.add(t.voice);
          }
        }
        final gaps = <String>[];
        for (final v in used) {
          if (!VOICE_LABEL.containsKey(v)) {
            gaps.add('$v(이름)');
          }
          if (!ALL_VOICES.contains(v)) {
            gaps.add('$v(목록)');
          }
          if (!kVoiceFamily.values.any((l) => l.contains(v))) {
            gaps.add('$v(묶음)');
          }
          // **소리를 정하는 표**. 위 셋을 채우고도 여기가 비어 있어서
          // 'vocal' 이 `kInstDefault`(삼각파)로 울고 있었다 — 이름은 「보컬」인데
          // 짝수 배음이 −118dB 였다. 목록에 있는데 정의가 없는 것이 제일 안 보인다.
          if (!INSTRUMENTS.containsKey(v)) {
            gaps.add('$v(음색)');
          }
        }
        check(
          '5-d) 곡이 쓰는 음색이 표에 다 있다',
          gaps.isEmpty,
          gaps.isEmpty ? '${used.length}종 × 4개 표' : gaps.join(', '),
        );
      }

      // 5-e) **붙박이 필인이 있는 드럼 판은 민짜 짝이 있어야 한다.**
      //
      // 같은 코러스가 곡 안에서 두세 번 나오는데 끝마디 마무리가 매번 돌면
      // 지겨워진다. `kPlainDrum` 이 그걸 막는데, 프로그·팝은 표에서 빠져 있어서
      // **매번 돌고 있었다.** 오류가 안 나니 귀로만 알 수 있는 종류다.
      //
      // ── 재는 법을 바꿨다 (2026-09-04) ──
      // 예전엔 「끝마디에 **탐·크래시**가 몰렸나」로 봤다. 그런데 드릴은 필인이
      // **하이햇**이다(두 마디짜리 무늬인데 마지막 마디만 16분 뭉치가 더 붙어
      // 악구를 닫는다). 탐이 아예 없으니 옛 자로는 0 개라 안 걸렸고, 드릴 훅이
      // 곡에서 세 번 도는 동안 그 마무리가 매번 돌고 있었다.
      //
      // 이제 레인을 안 가리고 **「끝마디가 이 판 자신의 되풀이 주기를 깨는가」**
      // 로 본다. 필인이란 원래 그것이다 — 두 마디 무늬면 끝마디를 **두 마디 전**과
      // 견준다(앞마디 전부와 견주면 드릴처럼 1·3마디에 같은 무늬가 있는 판을
      // 통째로 놓친다).
      //
      // **코러스·훅·드롭에서만 본다.** 빌드업·프리는 끝으로 갈수록 촘촘해지는
      // 것이 그 구간의 목적이라(그래서 매번 돌아야 맞다), 같은 자로 재면
      // 전부 걸린다. `kPlainDrum` 이 막으려는 건 「되풀이되는 고조 구간이
      // 매번 같은 마무리로 닫히는 것」이다 — 그 구간만 잰다.
      {
        final noPlain = <String>[];
        final seen = <String>{};
        for (final k in keys) {
          final p = Project.initial()..setGenre(k);
          for (final sc in p.scenes) {
            if (roleOf(sc.name) != SectionRole.drop) continue;
            for (final t in p.tracks.where((t) => t.type == 'drum')) {
              final c = sc.clips[t.id];
              if (c == null || !seen.add(c)) continue;
              final d = findDrumPattern(c);
              if (d == null || d.bars < 2) continue;
              // 레인별로 마디 안 자리(0~15)를 모은다
              final byBar = <String, List<Set<int>>>{};
              d.hits.forEach((lane, steps) {
                final bars = List.generate(d.bars, (_) => <int>{});
                for (final st in steps) {
                  final b = st ~/ kStepsPerBar;
                  if (b < d.bars) bars[b].add(st % kStepsPerBar);
                }
                byBar[lane] = bars;
              });
              // **레인마다 따로 잰다.** 한꺼번에 재면 구간 첫 박 크래시(0마디에만
              // 있는 문패) 때문에 「0마디와 2마디가 다르다」가 되어 주기를 못 찾는다.
              var extra = 0;
              byBar.forEach((lane, bars) {
                // 첫 마디에만 있는 레인 = 구간 문패(크래시). 되풀이 무늬가 아니다.
                final onlyFirst = bars.sublist(1).every((b) => b.isEmpty);
                if (onlyFirst) return;
                bool eq(int a, int b) =>
                    bars[a].difference(bars[b]).isEmpty &&
                    bars[b].difference(bars[a]).isEmpty;
                // 끝마디를 뺀 앞부분이 몇 마디마다 되풀이되는가(1 또는 2)
                int? period;
                for (final cand in [1, 2]) {
                  if (cand > d.bars - 1) continue;
                  var ok = true;
                  for (var b = cand; b < d.bars - 1; b++) {
                    if (!eq(b, b - cand)) ok = false;
                  }
                  if (ok) {
                    period = cand;
                    break;
                  }
                }
                if (period == null) return; // 주기를 못 찾으면 판단하지 않는다
                // 되풀이대로라면 끝마디는 「한 주기 전 마디」와 같아야 한다
                final want = d.bars - 1 - period;
                if (want < 0) return;
                extra += bars.last.difference(bars[want]).length;
              });
              if (extra >= 2 && !kPlainDrum.containsKey(c)) {
                noPlain.add('$c(끝마디에 $extra타 더 붙음)');
              }
            }
          }
        }
        check(
          '5-e) 필인 든 판에는 민짜 짝이 있다',
          noPlain.isEmpty,
          noPlain.isEmpty ? '코러스·훅·드롭 ${seen.length}개 판' : noPlain.join(', '),
        );
      }

      // 5-f) **크기 보정이 장르마다 있어야 한다.**
      //
      // `styleGain` 은 모르는 장르에 1.0 을 준다 — 오류가 안 난다. 그래서 드릴·R&B·
      // 디스코·가스펠이 표에서 빠진 채로 −8dB 까지 튀어 있었다. 곡을 바꿀 때마다
      // 볼륨을 만져야 하면 그게 고장이다.
      {
        final noGain = [
          for (final k in keys)
            if (!kStyleGain.containsKey(k)) k,
        ];
        check(
          '5-f) 크기 보정이 다 있다',
          noGain.isEmpty,
          noGain.isEmpty ? '${kStyleGain.length}개' : noGain.join(', '),
        );
      }

      // 5-f2) **표에 적힌 믹스가 실제로 트랙까지 닿는가.**
      //
      // 이름이 다 맞아도 **얹는 코드가 없으면** 아무 일도 안 일어난다.
      // 실제로 그랬다: 객체형(트랩·팝·재즈…)만 얹고 **배열형 6종
      // (로파이·하우스·힙합·시티팝·발라드·록)은 안 얹었다.** 재생 경로가 버스 쪽
      // 장르 몫을 `setGenreMix(null)` 로 걷어내므로(사용자 믹서를 살리려고),
      // 트랙에 안 얹으면 어디에도 안 얹힌다 — 그 여섯 줄이 통째로 죽어 있었다.
      // 여섯 스타일이 전부 vol 1.0 · pan 0 으로 똑같이 났고, 오류는 안 났다.
      {
        final dead = <String>[];
        for (final k in keys) {
          final spec = kGenreMix[k];
          if (spec == null) continue;
          final p = Project.initial()..setGenre(k);
          // 슬롯 → 트랙. 객체형은 곡 표가 슬롯 이름을 들고 있고(트랙 순서가 같다),
          // 배열형은 **트랙 타입이 곧 슬롯**이다.
          final obj = kObjectSongForms[k];
          final bySlot = <String, Track>{};
          if (obj != null) {
            for (var i = 0; i < obj.tracks.length && i < p.tracks.length; i++) {
              bySlot[obj.tracks[i].slot] = p.tracks[i];
            }
          } else {
            for (final t in p.tracks) {
              bySlot[t.type] = t;
            }
          }
          var hit = 0, miss = 0;
          spec.parts.forEach((slot, ps) {
            final t = bySlot[slot];
            if (t == null) return; // 편성에 없는 슬롯은 5-g 가 본다
            // **필터·움직임까지 본다.** 볼륨만 보면 hpf 52군데가 죽어 있어도
            // 통과한다 — 실제로 그랬다(보컬 200Hz 고역통과, 엠비언트 패드 LFO).
            final same =
                (t.vol - ps.vol).abs() < 1e-9 &&
                (t.pan - ps.pan).abs() < 1e-9 &&
                (t.rev - ps.rev).abs() < 1e-9 &&
                (t.hpf - (ps.hpf ?? 20)).abs() < 1e-9 &&
                (t.lpf - (ps.lpf ?? 20000)).abs() < 1e-9 &&
                (t.lfoHz - ps.lfoHz).abs() < 1e-9 &&
                (t.lfoDepth - ps.lfoDepth).abs() < 1e-9;
            same ? hit++ : miss++;
          });
          if (hit == 0 || miss > 0) dead.add('$k($hit닿음/$miss어긋남)');
        }
        // 필터를 실제로 쓰는 슬롯이 **몇 군데인지**도 같이 찍는다 —
        // 0 이 되면 표에서 사라진 것이고, 그건 조용히 일어난다.
        var filtered = 0;
        for (final spec in kGenreMix.values) {
          for (final ps in spec.parts.values) {
            if (ps.hpf != null || ps.lpf != null || ps.lfoHz != 0) filtered++;
          }
        }
        check(
          '5-f2) 적어 둔 믹스가 트랙까지 닿는다',
          dead.isEmpty && filtered > 0,
          dead.isEmpty
              ? '${keys.length}개 스타일 · 필터 쓰는 슬롯 $filtered군데'
              : dead.join(', '),
        );
      }

      // 5-f3) **드럼 버스는 씬 사이에 살아남는다 — 이전 장르의 필터가 남으면 안 된다.**
      //
      // `mixes.drum` 은 `TrackMixSet.configure` 가 절대 새로 안 만드는 자리다
      // (드럼은 항상 고정 버스 하나). hpf 를 거는 장르(트랩)를 들었다가 안 거는
      // 장르(로파이)로 넘어가도 `_apply` 가 `s.hpf == null` 이면 값을 안 건드리는
      // 바람에, 트랩의 30Hz 하이패스가 로파이에도 그대로 남아 있었다 — 소리가
      // **재생 이력**에 따라 달라졌다(같은 로파이인데 방금 튼 곡에 따라 다르게
      // 들린다). `Project.setGenre`(위 5-f2)는 트랙 필드에 직접 쓰는 다른 길이라
      // 이 자리를 못 잡는다 — 실제 오디오 아이솔레이트가 쓰는
      // `TrackMixSet`/`applyGenreMixTo` 를 직접 불러야 잡힌다.
      {
        final mixes = TrackMixSet();
        mixes.configure(melodicSlotsFor('trap'));
        applyGenreMixTo(mixes, 'trap');
        final trapHpf = mixes.drum.hpfFreq;
        check('5-f3) 트랩은 드럼에 hpf 를 건다', trapHpf > 20, '$trapHpf (30 이어야 함)');

        mixes.configure(melodicSlotsFor('lofi'));
        applyGenreMixTo(mixes, 'lofi');
        check(
          '5-f3) 로파이로 넘어가면 트랩의 hpf 가 안 남는다',
          mixes.drum.hpfFreq == 20,
          '${mixes.drum.hpfFreq} (바라는 값 20=투명 · 이전 장르 값 $trapHpf 가 새면 안 된다)',
        );
      }

      // 5-g) **믹스 편성의 슬롯 이름이 곡의 슬롯 이름과 같아야 한다.**
      //
      // 이름이 하나만 어긋나면 그 트랙은 조용히 **기본 믹스**(투명)로 남는다.
      // 페이더도 팬도 리버브도 안 걸린 채로 소리만 난다 — 오류는 안 난다.
      // (엠비언트의 드럼 슬롯이 'perc' 인 것은 `GenreMixSpec.drumSlot` 이 안다.)
      {
        final bad = <String>[];
        for (final e in kObjectSongForms.entries) {
          final spec = kGenreMix[e.key];
          if (spec == null) continue;
          for (final t in e.value.tracks) {
            final want = t.type == 'drum' ? spec.drumSlot : t.slot;
            if (!spec.parts.containsKey(want)) bad.add('${e.key}/$want(믹스없음)');
          }
          final slots = {
            for (final t in e.value.tracks)
              t.type == 'drum' ? spec.drumSlot : t.slot,
          };
          for (final k in spec.parts.keys) {
            if (!slots.contains(k)) bad.add('${e.key}/$k(곡에없음)');
          }
        }
        check(
          '5-g) 믹스 슬롯 이름이 곡과 맞는다',
          bad.isEmpty,
          bad.isEmpty ? '${kObjectSongForms.length}곡 전부' : bad.join(', '),
        );
      }

      // 5-h) **트랙 이름표가 슬롯마다 있어야 한다.**
      //
      // 없으면 슬롯 키가 그대로 이름이 된다 — 화면이 전부 한국어인데 그 줄만
      // 「org」 로 나온다. 가스펠 오르간이 실제로 그랬다. 오류는 안 난다.
      {
        final noLabel = <String>{};
        for (final f in kObjectSongForms.values) {
          for (final t in f.tracks) {
            if (!kSlotLabel.containsKey(t.slot)) noLabel.add(t.slot);
          }
        }
        check(
          '5-h) 트랙 이름표가 다 있다',
          noLabel.isEmpty,
          noLabel.isEmpty ? '${kSlotLabel.length}개' : noLabel.join(', '),
        );
      }

      // 5-i) **곡이 가리키는 패턴 이름이 라이브러리에 다 있는가.**
      //
      // 없으면 `findBassPattern` 이 null 을 돌려주고 그 파트는 **통째로 안 실린다.**
      // 오류는 안 난다. 실제로 `RnB Bass P` 를 **코드 목록에** 잘못 넣어 놔서
      // R&B 프리 구간에 베이스가 없었다 — 소리가 나니까 아무도 몰랐다.
      // 슬롯 이름·키트 이름·구간 순서도 같은 이유로 같이 본다.
      {
        final bad = <String>[];
        bool has(String type, String name) => switch (type) {
          'drum' => findDrumPattern(name) != null,
          'bass' => findBassPattern(name) != null,
          'chord' => findChordPattern(name) != null,
          _ => findMelodyPattern(name) != null,
        };
        kSongForms.forEach((g, secs) {
          for (final s in secs) {
            for (final e in {
              'drum': s.drum,
              'bass': s.bass,
              'chord': s.chord,
              'melody': s.melody,
            }.entries) {
              final n = e.value;
              if (n != null && !has(e.key, n)) {
                bad.add('$g/${s.name} ${e.key}「$n」');
              }
            }
          }
        });
        kObjectSongForms.forEach((g, f) {
          final type = {for (final t in f.tracks) t.slot: t.type};
          for (final s in f.sections) {
            s.parts.forEach((slot, n) {
              if (!type.containsKey(slot)) {
                bad.add('$g/${s.name} 슬롯「$slot」이 트랙에 없음');
              } else if (!has(type[slot]!, n)) {
                bad.add('$g/${s.name}/$slot「$n」');
              }
            });
          }
          for (final i in f.order) {
            if (i < 0 || i >= f.sections.length) bad.add('$g 순서 $i 범위 밖');
          }
        });
        for (final g in kGenres) {
          if (!DRUM_KITS.containsKey(g.kit)) bad.add('${g.key} 키트「${g.kit}」');
        }
        check(
          '5-i) 곡이 가리키는 것이 다 실재한다',
          bad.isEmpty,
          bad.isEmpty ? '패턴·슬롯·키트·순서 전부' : bad.take(4).join(' · '),
        );
      }

      // 5-j) **패턴 목록에서 그 장르 것이 위로 올라오는가.**
      //
      // `kStylePrefixes` 에 장르가 빠지면 두 가지가 조용히 망가진다:
      //   ① 그 장르 것이 목록 위로 안 올라온다 — 208개 중에서 찾아야 한다
      //   ② `patternIsBasic` 이 그 이름들을 「기본 패턴」으로 봐서
      //      **다른 모든 장르의 목록에 섞여 나온다**
      // 드릴·R&B·디스코·가스펠 넷이 그 상태였다(장르를 더하며 표를 빠뜨렸다).
      {
        final bad = <String>[];
        for (final g in kGenres) {
          if (!kStylePrefixes.containsKey(g.key)) {
            bad.add('${g.key}(표에 없음)');
            continue;
          }
          final names = <String>{};
          for (final s in kSongForms[g.key] ?? const <SongSection>[]) {
            for (final n in [s.drum, s.bass, s.chord, s.melody]) {
              if (n != null) names.add(n);
            }
          }
          final o = kObjectSongForms[g.key];
          if (o != null) {
            for (final s in o.sections) {
              names.addAll(s.parts.values);
            }
          }
          for (final n in names) {
            if (!patternIsStyle(n, g.key)) bad.add('${g.key}:「$n」');
          }
        }
        check(
          '5-j) 곡이 쓰는 패턴이 제 스타일로 묶인다',
          bad.isEmpty,
          bad.isEmpty
              ? '${kStylePrefixes.length}개 스타일'
              : bad.take(4).join(' · '),
        );
      }

      check(
        '5) 곡이 실제로 울린다',
        silent.isEmpty,
        silent.isEmpty ? '${keys.length}개 전부' : silent.join(', '),
      );
      check(
        '5-c) 곡 길이가 4분 30초를 안 넘는다',
        long.isEmpty,
        long.isEmpty ? '${keys.length}개 전부' : long.join(', '),
      );
      check(
        '5-b) 곡 길이가 30초 넘는다',
        short.isEmpty,
        short.isEmpty ? '전부' : short.join(', '),
      );
    }

    // ── 6) 키는 저장 파일에 남는다 — 함부로 바꾸면 옛 곡이 안 열린다 ──
    {
      // 이 목록이 줄거나 이름이 바뀌면 **일부러 그런 것인지** 여기서 멈춰 생각하게 한다.
      const shipped = [
        'lofi',
        'house',
        'hiphop',
        'citypop',
        'ballad',
        'rock',
        'trap',
        'proghouse',
        'pop',
        'jazz',
        'ambient',
      ];
      final lost = [
        for (final k in shipped)
          if (!isKnownGenre(k)) k,
      ];
      check(
        '6) 내보낸 적 있는 키가 안 사라졌다',
        lost.isEmpty,
        lost.isEmpty ? '${shipped.length}개 그대로' : '사라짐: ${lost.join(', ')}',
      );
    }

    // ignore: avoid_print
    print(fail == 0 ? '장르 확인 통과' : '실패 $fail건');
    expect(fail, 0);
  });
}
