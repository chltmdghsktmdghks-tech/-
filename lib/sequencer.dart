// 씬 재생 — **프로젝트의 트랙들**(믹서에 보이는 그 트랙들)을 실제로 연주한다.
//
// 5단계 2/N 전까지 프로젝트 트랙은 소리와 아무 연결이 없었다. 곡 재생은 `song.dart` 에
// 박혀 있는 데모곡만 돌았고, 트랙의 음색·패턴은 화면 글씨였다. 여기서 이어 붙인다:
//
//   트랙 목록 → 타입별 패턴(patterns.dart) → 음/타격 → 엔진 예약(batch/drumBatch)
//
// ── 버스 배정 ──
// 드럼 아닌 트랙은 **각자 자기 버스**를 갖는다(버스 이름 = 트랙 id). 그래야 멜로디
// 트랙을 두 개 만들어도 페이더가 따로 논다. 드럼은 엔진에 버스가 하나뿐이라
// (`TrackMixSet.drum`) 드럼 트랙 여러 개는 그 하나를 같이 쓴다.
//
// ── 재생 방식 두 가지 ──
// [playLoop] — **무한 반복**(5단계 3/N, 기본). 한 판 분량만 보내고, 다음 판 예약은
//   오디오 아이솔레이트가 **엔진 시계 기준**으로 알아서 한다. 그래서 판이 안 밀린다.
//   돌고 있는 중에 패턴·음색을 바꾸면 [refreshLoop] 로 **다음 판부터** 반영된다.
// [play] — 정해진 횟수만 예약하고 끝(데모곡 재생과 같은 길). 시험·비교용으로 남겼다.

import 'dart:math' as math;

import 'arrange.dart';
import 'audio_isolate.dart';
import 'feel.dart';
import 'genre_mix.dart';
import 'fill.dart';
import 'patterns.dart';
import 'project.dart';
import 'theory.dart';
import 'variation.dart';

/// 한 번 만든 결과 — 화면에 "몇 개 예약했는지" 보여 주고, 시험에서 검사한다.
class SceneBuild {
  final List<List<dynamic>>
  notes; // [voice, freq, durSec, vel, soft, glide, delaySec, part]
  final List<List<dynamic>> drums; // [kit, lane, vel, tomFreq, delaySec]
  final List<String> busNames;
  final int loopBars;
  final double loopSec;
  final double totalSec;
  const SceneBuild({
    required this.notes,
    required this.drums,
    required this.busNames,
    required this.loopBars,
    required this.loopSec,
    required this.totalSec,
  });
}

class SceneSequencer {
  /// 드럼이 아닌 트랙의 id 순서 = 엔진 슬롯(버스) 편성.
  static List<String> busNames(Project p) => [
    for (final t in p.tracks)
      if (t.type != 'drum') t.id,
  ];

  /// 트랙 → 엔진 버스 이름. 믹서(`setBus`)와 여기가 **같은 규칙**을 써야 한다.
  static String busOf(Track t) => t.type == 'drum' ? 'drum' : t.id;

  /// 타입에 맞는 패턴 목록. [spb] 를 주면 **그 박자의 판만** 걸러 낸다
  /// (5단계 47/N) — 안 주면 여태처럼 전부(주로 시험이 쓴다).
  static List<String> patternNames(String type, {int? spb}) {
    bool fit(int s) => spb == null || s == spb;
    switch (type) {
      case 'drum':
        return [for (final d in kDrumPatterns) if (fit(d.spb)) d.name];
      case 'bass':
        return [for (final d in kBassPatterns) if (fit(d.spb)) d.name];
      case 'chord':
        return [for (final d in kChordPatterns) if (fit(d.spb)) d.name];
      default:
        return [for (final d in kMelodyPatterns) if (fit(d.spb)) d.name];
    }
  }

  /// 타입에 맞는 패턴 목록 — **내가 만든 패턴이 앞에** 온다.
  ///
  /// `userNote` 는 베이스·코드·멜로디가 **한 표를 같이 쓴다**(이름만으로 구분).
  /// 그래서 여기서 타입을 안 걸러 내면 베이스 트랙에서 만든 패턴이 코드·멜로디
  /// 고르기에도 그대로 떴다 — 골라도 오류는 안 나고 소리만 틀렸다. 타입을
  /// 모르는 이름(옛 곡)은 그대로 통과시킨다(`Project.userNoteType` 참고).
  ///
  /// **박자가 다른 판은 안 보여준다** — 3/4 곡의 고르기 화면에 4/4 판이 뜨면
  /// 골랐을 때 격자가 12칸인데 음이 16칸 셈으로 찍혀 있어 뒤가 넘친다
  /// (홀수 박자를 넣으며 처음부터 막아 둔다 — `lib/meter.dart` 참고).
  static List<String> patternNamesFor(Project p, String type) => [
    ...(type == 'drum'
        ? p.userDrum.entries
              .where((e) => e.value.spb == p.spb)
              .map((e) => e.key)
        : p.userNote.entries
              .where((e) {
                final ty = p.userNoteType[e.key];
                return (ty == null || ty == type) && e.value.spb == p.spb;
              })
              .map((e) => e.key)),
    ...patternNames(type, spb: p.spb),
  ];

  /// 씬 한 판을 만든다. 소리를 내지 않으므로 시험에서도 그대로 쓴다.
  ///
  /// [reps] 를 주면 트랜스포트 값 대신 그만큼 반복한다(루프 재생은 1판만 만든다).
  /// [from] 을 주면 **트랙에 실린 값 대신 그 씬의 클립**으로 만든다 — 곡(타임라인)이
  /// 여러 씬을 이어 붙일 때 쓴다. 이때 트랙을 건드리지 않는 게 중요하다(화면에 보이는
  /// '지금 씬'이 곡 재생 때문에 바뀌면 안 된다).
  /// [bpm] 도 마찬가지로 구간마다 다를 수 있다.
  /// [at] 은 전체 곡에서 이 구간이 시작하는 시각(초).
  /// [arrange] 를 끄면 구간 성격(빌드업·드롭·브레이크)을 안 건다 — **개수를 세는
  /// 시험**이 쓴다(성격은 타격을 더하고 뺀다).
  ///
  /// [barsBefore] 는 이 구간 앞에 이미 지나간 마디 수 — **변형이 곡 내내 이어지게**
  /// 한다. 안 주면 구간마다 원본부터 다시 시작해서, 두 번째 벌스가 첫 번째와
  /// 한 음도 안 다르다(로파이·시티팝은 벌스가 두 번 나온다).
  /// 클립 하나를 **한 번** 소리 목록에 얹는다.
  ///
  /// 씬 클립(되풀이되는 것)과 타임라인 트랙 클립(놓인 자리에서 한 번)이 **같은
  /// 코드를 쓴다.** 두 벌을 들고 맞추면 언젠가 한쪽만 고쳐진다 — 이 저장소에서
  /// 제일 자주 나온 병이다.
  ///
  /// [baseStep] 은 구간 안에서 이 클립이 시작하는 스텝, [limitStep] 은 여기까지만
  /// (넘는 음은 버린다). [skip] 이 참이면 그 스텝의 음을 안 넣는다 —
  /// 트랙 줄이 가져간 마디에서 씬 것을 걷어낼 때 쓴다.
  static void _emitClip(
    Project p,
    Track t,
    String clip,
    MusicKey key, {
    required List<List<dynamic>> notes,
    required List<List<dynamic>> drums,
    required double at,
    required double stepSec,
    required int baseStep,
    required int part,
    required String kit,
    required int v,
    required int limitStep,
    bool Function(int stepInSection)? skip,
  }) {
    if (t.type == 'drum') {
      final def = p.findDrum(clip);
      if (def == null) return;
      for (final h in varyDrums(buildDrumPattern(def), v, spb: def.spb)) {
        final st = baseStep + h.step;
        if (st >= limitStep) continue;
        if (skip != null && skip(st)) continue;
        drums.add([kit, h.lane, h.vel, 180.0, at + st * stepSec]);
      }
      return;
    }
    if (t.type == 'chord') {
      final def = p.findNote('chord', clip);
      if (def == null) return;
      // **덧줄** — 화음 판에 얹은 낱음. 같은 트랙·같은 음색으로 같이 울린다.
      if (def.also.isNotEmpty) {
        for (final h in varyMelodic(
          buildRowsPattern(def.alsoDef, 'melody', key),
          'melody',
          v,
          spb: def.spb,
        )) {
          final st = baseStep + h.step;
          if (st >= limitStep) continue;
          if (skip != null && skip(st)) continue;
          notes.add([
            t.voice,
            h.freq,
            h.len * stepSec,
            h.vel,
            false,
            h.glideFromFreq,
            at + st * stepSec,
            part,
          ]);
        }
      }
      // **록 기타는 파워코드를 친다** (`genreChordType`). 종류를 직접 적어 둔
      // 음은 안 건드린다 — 고른 것을 스타일이 덮으면 고를 이유가 없다.
      for (final h in varyChord(
        buildChordPattern(
          def,
          key,
          plainType: genreChordType(p.genre, t.voice),
          voice: t.voice,
        ),
        v,
        spb: def.spb,
      )) {
        final st = baseStep + h.step;
        if (st >= limitStep) continue;
        if (skip != null && skip(st)) continue;
        for (final f in h.freqs) {
          notes.add([
            t.voice,
            f,
            h.len * stepSec,
            h.vel,
            true,
            0.0,
            at + st * stepSec,
            part,
          ]);
        }
      }
      return;
    }
    final def = p.findNote(t.type, clip);
    if (def == null) return;
    // **덧줄** — 가락 판에 얹은 화음. 같은 트랙·같은 음색으로 같이 울린다.
    if (def.also.isNotEmpty) {
      for (final h in varyChord(
        buildChordPattern(def.alsoDef, key, voice: t.voice),
        v,
        spb: def.spb,
      )) {
        final st = baseStep + h.step;
        if (st >= limitStep) continue;
        if (skip != null && skip(st)) continue;
        for (final f in h.freqs) {
          notes.add([
            t.voice,
            f,
            h.len * stepSec,
            h.vel,
            true,
            0.0,
            at + st * stepSec,
            part,
          ]);
        }
      }
    }
    for (final h in varyMelodic(
      buildRowsPattern(def, t.type, key),
      t.type,
      v,
      spb: def.spb,
    )) {
      final st = baseStep + h.step;
      if (st >= limitStep) continue;
      if (skip != null && skip(st)) continue;
      notes.add([
        t.voice,
        h.freq,
        h.len * stepSec,
        h.vel,
        false,
        h.glideFromFreq,
        at + st * stepSec,
        part,
      ]);
    }
  }

  static SceneBuild build(
    Project p,
    Transport tr, {
    int? reps,
    Scene? from,
    double? bpm,
    double at = 0,
    int barsBefore = 0,
    bool afterFill = false,
    bool arrange = true,
    Map<String, List<LaneClip>>? lanes,
  }) {
    final n = reps ?? tr.reps;
    final key = MusicKey(root: tr.root, mode: tr.mode);
    final buses = busNames(p);
    final stepSec = 60.0 / (bpm ?? tr.bpm) / 4; // 16분음표 하나
    String? clipOf(Track t) => from == null ? t.pattern : from.clips[t.id];
    String kitOf(Track t) => from?.kit ?? t.kit;
    final playable = [
      for (final t in p.tracks)
        if (p.audible(t) && clipOf(t) != null) t,
    ];

    // 루프 길이 = 가장 긴 패턴. 짧은 패턴은 그 안에서 자기 길이만큼 반복한다
    // (2마디 패턴 + 4마디 패턴을 같이 틀면 2마디짜리가 두 번 돈다).
    var loopBars = 0;
    for (final t in playable) {
      final b = p.barsOf(t.type, clipOf(t));
      if (b > loopBars) loopBars = b;
    }
    if (loopBars <= 0) loopBars = 4;
    // **마디 길이는 곡의 박자가 정한다** (5단계 47/N). 칸은 늘 16분음표라
    // `stepSec` 은 그대로고, 한 마디에 그 칸이 몇 개인지만 달라진다.
    final spb = p.spb;
    final loopSteps = loopBars * spb;
    final loopSec = loopSteps * stepSec;

    final notes = <List<dynamic>>[];
    final drums = <List<dynamic>>[];
    // 변형 — **되풀이되는 바퀴만** 바꾼다 (Phase 4 · 계획 6-1).
    // 판을 다 만든 뒤에는 어느 타격이 몇 바퀴째 것인지 알 수 없으므로,
    // 필·느낌과 달리 **만드는 중에** 건다.
    final vary = VarySpec(amount: p.feel.vary);

    // 타임라인 트랙 줄이 **가져간 마디**인가 — 그 마디에서는 씬 것이 빠진다.
    // (옛 앱의 규칙 그대로: 트랙에 클립이 놓여 있으면 그것이 씬 블록을 이긴다)
    bool taken(Track t, int stepInSection) {
      final mine = lanes?[t.id];
      if (mine == null || mine.isEmpty) return false;
      final bar = stepInSection ~/ spb;
      for (final c in mine) {
        final cb = p.barsOf(t.type, c.pattern);
        if (cb > 0 && bar >= c.bar && bar < c.bar + cb) return true;
      }
      return false;
    }

    for (final t in playable) {
      final clip = clipOf(t)!;
      final bars = p.barsOf(t.type, clip);
      if (bars <= 0) continue;
      // 자기 길이만큼 되풀이해서 루프를 채운다
      final inner = (loopBars + bars - 1) ~/ bars;
      final part = t.type == 'drum' ? -1 : buses.indexOf(t.id);

      for (var rep = 0; rep < n; rep++) {
        for (var k = 0; k < inner; k++) {
          final baseStep = rep * loopSteps + k * bars * spb;
          // 판 안의 되풀이(k)와 판 자체의 되풀이(rep)를 **합쳐** 센다 —
          // 2마디 패턴은 4마디 판 안에서 이미 두 바퀴를 돌기 때문이다.
          // 앞 구간에서 이 클립이 몇 바퀴 돌았는지도 더한다(곡 전체로 이어진다).
          final v = varyIndex(barsBefore ~/ bars + rep * inner + k, vary);
          _emitClip(
            p,
            t,
            clip,
            key,
            notes: notes,
            drums: drums,
            at: at,
            stepSec: stepSec,
            baseStep: baseStep,
            part: part,
            kit: kitOf(t),
            v: v,
            limitStep: (rep + 1) * loopSteps,
            skip: lanes == null ? null : (st) => taken(t, st),
          );
        }
      }
    }

    // 트랙 줄에 놓인 클립 — 씬 것을 걷어낸 자리에 이걸 채운다.
    // 씬 클립과 달리 **되풀이하지 않는다**: 놓은 자리에서 제 길이만큼만 친다
    // (옛 앱과 같다 — 2마디 클립을 5마디에 놓으면 5·6마디만 그것이다).
    if (lanes != null) {
      for (final t in p.tracks) {
        if (!p.audible(t)) continue;
        final mine = lanes[t.id];
        if (mine == null) continue;
        final part = t.type == 'drum' ? -1 : buses.indexOf(t.id);
        for (final c in mine) {
          final cb = p.barsOf(t.type, c.pattern);
          if (cb <= 0) continue;
          final baseStep = c.bar * spb;
          if (baseStep >= loopSteps * n) continue; // 구간 밖 — 판 수를 줄인 자리
          _emitClip(
            p,
            t,
            c.pattern,
            key,
            notes: notes,
            drums: drums,
            at: at,
            stepSec: stepSec,
            baseStep: baseStep,
            part: part,
            kit: kitOf(t),
            v: varyIndex((barsBefore + c.bar) ~/ cb, vary),
            limitStep: math.min(loopSteps * n, (c.bar + cb) * spb),
          );
        }
      }
    }

    // 필 — **한 판이 끝나는 자리를 표시한다** (Phase 4 · 계획 6-2).
    // 느낌보다 **먼저** 건다: 필로 깔린 타격도 스윙·세기를 같이 받아야
    // 나머지와 한 몸으로 들린다.
    final drumTrack = playable.where((t) => t.type == 'drum');
    if (p.feel.fill > 0 && drumTrack.isNotEmpty) {
      applyFill(
        drums,
        kitOf(drumTrack.first),
        stepSec,
        loopBars,
        n,
        FillSpec(amount: p.feel.fill),
        at: at,
        totalSec: loopSec * n,
        crashOnStart: afterFill,
        spb: spb,
      );
    }

    // 구간 성격 — **이름이 소리를 바꾼다** (Phase 4 · 계획 6-3).
    //
    // 필 **뒤**에 건다. 빌드업은 마지막 마디의 킥을 비우는데, 필이 그 자리에
    // 킥을 남겨 두기 때문이다(필은 「킥은 발이라 계속 밟는다」가 규칙이다).
    // 빌드업에서는 그 발이 멎어야 다음 구간이 터진다 — 그래서 필 다음이다.
    if (arrange) {
      applyArrange(
        notes,
        drums,
        roleOf(from?.name ?? p.scene.name),
        stepSec,
        at: at,
        totalSec: loopSec * n,
        spb: spb,
      );
    }

    // 결과 손잡이 — **맨 마지막에 한 번** (Phase 2 · 계획 4-4).
    // 재생도 내보내기도 이 목록을 그대로 쓰므로, 여기서 바꾸면 둘이 저절로 같다.
    applyFeel(notes, drums, p.feel, stepSec, genre: p.genre);

    return SceneBuild(
      notes: notes,
      drums: drums,
      busNames: buses,
      loopBars: loopBars,
      loopSec: loopSec,
      totalSec: loopSec * n,
    );
  }

  /// 믹서 값을 **내보내기용**으로 모은다 — 버스 이름 → [vol, pan, rev, lo, mid, hi].
  /// 재생과 같은 규칙(`pushMix`)을 써야 파일이 들리던 것과 같은 소리로 나온다.
  static Map<String, List<double>> mixSnapshot(Project p) {
    final out = <String, List<double>>{};
    for (final t in p.tracks) {
      final on = p.audible(t);
      out[busOf(t)] = [
        on ? t.vol : 0.0,
        t.pan,
        t.rev,
        t.eq.lo,
        t.eq.mid,
        t.eq.hi,
        // **재생과 같은 것을 담아야 파일이 들리던 소리로 나온다** —
        // 뒤 넷은 장르가 정한 필터·움직임이다
        t.hpf,
        t.lpf,
        t.lfoHz,
        t.lfoDepth,
      ];
    }
    return out;
  }

  /// 인서트를 내보내기용으로 모은다 — 버스 이름 → 꽂은 순서.
  /// 내보낼 때 마스터에 걸 배수 — **스타일 보정 × 사용자 마스터 페이더.**
  ///
  /// 재생은 엔진이 둘을 따로 곱한다(`Engine.styleGain` × `Engine.userGain`).
  /// 내보내기는 곱할 자리가 `ExportJob.masterVol` 하나뿐이라 여기서 곱해 준다.
  ///
  /// 예전엔 **스타일 보정만** 실었다. 그래서 믹서에서 마스터를 −6dB 로 내려도
  /// 내보낸 파일은 그대로였다 — 마스터 **인서트**(마스터링)는 실리는데 페이더만
  /// 안 실렸다. 들은 것과 파일이 다르면 그건 앱이 거짓말을 한 것이다. (2026-08-30)
  static double exportMasterVol(Project p, MasterChannel? m) =>
      styleGain(p.genre) * (m?.vol ?? 1.0);

  static Map<String, List<Map<String, dynamic>>> insertSnapshot(Project p) => {
    for (final t in p.tracks) busOf(t): [for (final f in t.chain) f.toJson()],
  };

  /// 믹서에서 맞춰 둔 값을 전부 버스로 보낸다.
  /// **편성을 바꾼 직후에는 반드시 이걸 불러야 한다** — `configure()` 는 버스를 새
  /// 객체(투명 기본값)로 다시 만들기 때문에, 안 부르면 ▶를 누를 때마다 믹서 설정이
  /// 초기화된 것처럼 들린다.
  static void pushMix(Project p, AudioClient host) {
    for (final t in p.tracks) {
      // 인서트도 같이 보낸다 — 편성을 다시 잡으면 버스가 새 객체라 비어 있다.
      // 안 보내면 곡을 다시 틀 때마다 꽂아 둔 게 사라진다.
      host.setInserts(busOf(t), [for (final f in t.chain) f.toJson()]);
      // ADSR 도 같이 보낸다 — 인서트와 같은 이유(편성을 다시 잡으면 버스가
      // 새 객체라 비어 있다). 표본 악기 트랙은 값이 null 이라도 무해하다
      // (`synth.dart` 가 표본 경로에서는 아예 안 본다).
      host.setAdsr(
        busOf(t),
        attack: t.adsrAttack,
        decay: t.adsrDecay,
        sustain: t.adsrSustain,
        release: t.adsrRelease,
      );
      // 유니즌도 같이 — ADSR과 같은 이유(편성을 다시 잡으면 버스가 새
      // 객체라 비어 있다).
      host.setUni(busOf(t), t.uniCents);
      final on = p.audible(t);
      host.setBus(
        busOf(t),
        vol: on ? t.vol : 0.0,
        pan: t.pan,
        rev: t.rev,
        lo: t.eq.lo,
        mid: t.eq.mid,
        hi: t.eq.hi,
        // 장르가 정한 필터·움직임도 같이 — 이게 빠져서 `kGenreMix` 의
        // hpf·lpf·lfo 52군데가 통째로 죽어 있었다
        hpf: t.hpf,
        lpf: t.lpf,
        lfoHz: t.lfoHz,
        lfoDepth: t.lfoDepth,
      );
    }
  }

  /// 무한 반복 재생을 시작한다. 순서가 중요하다:
  ///   ① 데모곡이 걸어 둔 장르 몫 걷어내기 → ② 내 트랙으로 편성 → ③ 믹서 값 복구 → ④ 루프
  static SceneBuild playLoop(Project p, Transport tr, AudioClient host) {
    // 루프는 **자기 자신 뒤에 온다** — 앞 판이 필로 끝났으니 첫 박에 크래시가 맞다
    final b = build(p, tr, reps: _loopReps(p), afterFill: true);
    host.setGenreMix(null);
    // 비켜 주기는 장르 성격이라 따로 보낸다 (계획 6-5)
    // 세기는 사용자가 만졌으면(`duckAmountOverride`) 그 값이 장르 기본값을
    // 이긴다 — 복귀 시간은 처음부터 장르 몫이 아니라 사용자 손잡이다.
    host.setDuck(
      p.duckAmountOverride ?? kGenreDuck[p.genre] ?? 0,
      relSec: p.duckRelSec,
    );
    host.configureBuses(b.busNames);
    pushMix(p, host);
    host.setSongMode(true);
    host.setLoop(
      b.notes,
      b.drums,
      b.totalSec,
      restart: true,
      unitSec: b.loopSec,
    );
    return b;
  }

  /// 씬 루프는 **변형 한 주기만큼**을 한 판으로 돌린다 (계획 6-1).
  ///
  /// 한 바퀴만 만들어 무한 반복하면 변형이 들어갈 자리가 없다 — 늘 같은 바퀴다.
  /// 변형을 끄면 1 이라 예전과 완전히 같다.
  ///
  /// 돌려주는 `SceneBuild` 의 `loopBars`/`loopSec` 은 **한 바퀴** 값 그대로다.
  /// 화면 격자와 라이브 녹음이 그 값을 쓰기 때문이다 — 그래서 `setLoop` 에는
  /// 판 길이(`totalSec`)와 눈금(`loopSec`)을 따로 준다.
  static int _loopReps(Project p) => VarySpec(amount: p.feel.vary).cycle;

  /// 돌고 있는 루프의 **내용만** 갈아 끼운다(박자는 안 건드린다).
  /// 재생 중에 패턴·음색·조·템포를 바꿨을 때 부른다 → 다음 판부터 새 소리.
  ///
  /// 주의: 템포를 바꾸면 한 판 길이도 바뀌므로 그 다음 판부터 새 길이로 돈다.
  static SceneBuild refreshLoop(Project p, Transport tr, AudioClient host) {
    final b = build(p, tr, reps: _loopReps(p), afterFill: true);
    host.configureBuses(b.busNames);
    pushMix(p, host);
    host.setLoop(
      b.notes,
      b.drums,
      b.totalSec,
      restart: false,
      unitSec: b.loopSec,
    );
    return b;
  }

  /// 곡 전체 길이(초)만 — **음을 만들지 않고** 셈으로 낸다 (5단계 15/N).
  ///
  /// 곡 목록에 길이를 보여주려고 만들었다. 목록 한 줄 그리자고 곡 전체를 만들면
  /// (`buildSong` 은 2~3분짜리 음 수천 개를 만든다) 곡이 스무 개일 때 목록이 멈춘다.
  /// 길이는 마디·템포·판 수만 알면 나온다.
  ///
  /// `build` 와 **같은 규칙**으로 판 길이를 잡아야 한다 — 안 그러면 목록에 적힌 길이와
  /// 실제 재생 길이가 다르다(뮤트한 트랙은 판 길이에 안 들어간다).
  static double songSeconds(Project p, Transport tr) {
    final s = songSpans(p, tr);
    return s.isEmpty ? 0 : s.last.$1 + s.last.$2;
  }

  /// 구간마다 (시작 초, 길이 초). 재생 위치를 구간에 대응시키는 모든 화면이 쓴다
  /// (곡 화면의 자, 쇼 화면의 구간 이름).
  ///
  /// **여기도 음을 안 만든다.** 예전엔 곡 화면이 화면을 다시 그릴 때마다 구간마다
  /// `build` 를 돌렸다 — 3분짜리 곡이면 한 프레임에 음 수천 개를 만든 셈이다.
  /// 그 씬 **한 판**이 몇 초인가. 씬마다 패턴 길이도 템포도 다르다.
  ///
  /// `songSpans` 가 구간마다 하던 셈을 밖에서도 쓸 수 있게 뺐다 — 두 곳에서 따로
  /// 세면 반드시 어긋난다(이 저장소에서 이미 여러 번 겪었다).
  /// 그 씬 **한 판이 몇 마디**인가 — 가장 긴 패턴이 판 길이를 정한다.
  ///
  /// 타임라인이 마디 자리를 잡을 때와 [sceneLoopSec] 이 초를 잴 때가 **같은 셈**을
  /// 써야 한다. 두 곳에서 따로 세면 반드시 어긋난다(이 저장소에서 여러 번 겪었다).
  static int sceneLoopBars(Project p, int scene) {
    if (scene < 0 || scene >= p.scenes.length) return 4;
    final s = p.scenes[scene];
    var loopBars = 0;
    for (final t in p.tracks) {
      final clip = s.clips[t.id];
      if (clip == null || !p.audible(t)) continue;
      final b = p.barsOf(t.type, clip);
      if (b > loopBars) loopBars = b;
    }
    return loopBars <= 0 ? 4 : loopBars;
  }

  static double sceneLoopSec(Project p, Transport tr, int scene) {
    if (scene < 0 || scene >= p.scenes.length) return 0;
    final s = p.scenes[scene];
    final stepSec = 60.0 / (s.bpm ?? tr.bpm) / 4;
    return sceneLoopBars(p, scene) * p.spb * stepSec;
  }

  static List<(double, double)> songSpans(Project p, Transport tr) {
    final out = <(double, double)>[];
    var at = 0.0;
    for (final sec in p.song.sections) {
      if (sec.scene < 0 || sec.scene >= p.scenes.length) {
        out.add((at, 0));
        continue;
      }
      final dur = sceneLoopSec(p, tr, sec.scene) * sec.reps;
      out.add((at, dur));
      at += dur;
    }
    return out;
  }

  /// 곡(타임라인) 전체를 만든다 — 구간마다 그 씬의 클립·템포·키트로.
  ///
  /// **구간마다 템포가 다를 수 있다.** 그래서 시각을 초로 누적한다(마디로 세면 구간
  /// 경계에서 어긋난다). 각 구간은 그 씬의 판 길이 × 판 수만큼 차지한다.
  ///
  /// 결과의 `loopSec` 은 **곡 전체 길이**다 — 그대로 `setLoop` 에 넣으면 곡이 통째로
  /// 무한 반복된다(루프 장치를 그대로 재활용한다).
  /// [from] 은 **몇 번째 구간부터** 만들 것인가. 3분짜리 곡의 뒷부분을 고칠 때
  /// 처음부터 다 듣지 않아도 되게 하는 손잡이다(곡 화면의 「여기부터」).
  /// 앞 구간은 통째로 건너뛰고 시각을 0 으로 다시 잡는다.
  static SceneBuild buildSong(Project p, Transport tr, {int from = 0}) =>
      _buildSong(p, tr, from: from);

  static SceneBuild _buildSong(
    Project p,
    Transport tr, {
    bool arrange = true,
    int from = 0,
  }) {
    final notes = <List<dynamic>>[];
    final drums = <List<dynamic>>[];
    var at = 0.0;
    var bars = 0;
    final start = from.clamp(0, p.song.sections.length);
    for (var si = start; si < p.song.sections.length; si++) {
      final sec = p.song.sections[si];
      if (sec.scene < 0 || sec.scene >= p.scenes.length) continue;
      final s = p.scenes[sec.scene];
      // 타임라인 트랙 줄 — 이 구간 것만 골라 넘긴다. 없으면 null 이라
      // **여태와 똑같은 길**로 간다(놓은 클립이 없는 곡은 소리가 한 톨도 안 바뀐다).
      Map<String, List<LaneClip>>? lanes;
      for (final c in p.song.lanes) {
        if (c.section != si) continue;
        (lanes ??= {}).putIfAbsent(c.trackId, () => []).add(c);
      }
      final b = build(
        p,
        tr,
        reps: sec.reps,
        from: s,
        bpm: s.bpm,
        at: at,
        barsBefore: bars,
        lanes: lanes,
        // 첫 구간 빼고는 **앞 구간이 필로 끝났다** — 그 크래시를 여기 첫 박에 얹는다
        afterFill: at > 0,
        arrange: arrange,
      );
      notes.addAll(b.notes);
      drums.addAll(b.drums);
      at += b.totalSec;
      bars += b.loopBars * sec.reps;
    }
    return SceneBuild(
      notes: notes,
      drums: drums,
      busNames: busNames(p),
      loopBars: bars,
      loopSec: at,
      totalSec: at,
    );
  }

  /// 구간 성격(계획 6-3)을 **안 걸고** 만든 곡 — 성격이 무엇을 바꾸는지 견주려고
  /// 시험이 쓴다. 재생 경로는 이걸 안 쓴다.
  static SceneBuild buildSongPlain(Project p, Transport tr) =>
      _buildSong(p, tr, arrange: false);

  /// 곡을 재생한다. [loop] 이면 끝나고 처음부터 다시(구간 전체가 한 판이 된다).
  static SceneBuild playSong(
    Project p,
    Transport tr,
    AudioClient host, {
    bool loop = true,
    int from = 0,
  }) {
    final b = buildSong(p, tr, from: from);
    host.setGenreMix(null);
    // 세기는 사용자가 만졌으면(`duckAmountOverride`) 그 값이 장르 기본값을
    // 이긴다 — 복귀 시간은 처음부터 장르 몫이 아니라 사용자 손잡이다.
    host.setDuck(
      p.duckAmountOverride ?? kGenreDuck[p.genre] ?? 0,
      relSec: p.duckRelSec,
    );
    host.configureBuses(b.busNames);
    pushMix(p, host);
    host.setSongMode(true);
    if (loop && b.totalSec > 0) {
      host.setLoop(b.notes, b.drums, b.totalSec, restart: true);
    } else {
      host.allOff();
      if (b.drums.isNotEmpty) host.drumBatch(b.drums);
      if (b.notes.isNotEmpty) host.batch(b.notes);
    }
    return b;
  }

  /// 만들어서 바로 보낸다. 순서가 중요하다:
  ///   ① 데모곡이 걸어 둔 장르 몫 걷어내기 → ② 내 트랙으로 편성 → ③ 믹서 값 복구 → ④ 예약
  /// 슬롯 개수가 안 맞은 채로 예약하면 엔진이 마지막 슬롯으로 몰아 버린다(방어 코드).
  static SceneBuild play(Project p, Transport tr, AudioClient host) {
    final b = build(p, tr);
    host.setGenreMix(null);
    host.configureBuses(b.busNames);
    pushMix(p, host);
    host.setSongMode(true);
    if (b.drums.isNotEmpty) host.drumBatch(b.drums);
    if (b.notes.isNotEmpty) host.batch(b.notes);
    return b;
  }
}
