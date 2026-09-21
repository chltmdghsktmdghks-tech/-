import 'genres.dart';
import 'meter.dart';
import 'patterns.dart';
import 'theory.dart';

// 4단계 3/N — 시퀀서/클립 구조: SONG_FORMS(배열형 6곡) + FORM_ORDER + 필인 로직.
//
// 지금까지는 패턴 하나를 버튼 눌러 한 번 예약해 보는 시험 화면 수준이었다(main.dart
// `_playSong`). 여기서는 웹 `applySongForm()` 이 하던 일 — 섹션을 순서대로 이어붙이고,
// 섹션 안에서 패턴을 제 길이만큼 반복하고, 시간 오프셋을 계산하는 것 — 을 그대로 옮겼다.
//
// 배열형 6곡(lofi/house/hiphop/citypop/ballad/rock)은 타입 하나당 트랙 하나(드럼/베이스/
// 코드/멜로디)라 위 [SongSection]/[buildSong] 로 충분하다.
//
// 4단계 5/N — **객체형 롱폼**(트랙 구조 일반화, mixer.dart `TrackMixSet.configure` 참고)
// 은 파일 맨 아래 [ObjectSongForm]/[buildObjectSong] 로 따로 옮긴다. 이쪽은 슬롯별
// 트랙 편성(같은 타입 트랙 여러 개 — 예: 트랩의 패드+브라스가 둘 다 chord)과 곡 자체의
// `order`/`tracks` 를 쓴다. 이번엔 트랩 하나만 옮겼다(HANDOFF "한 번에 한 덩어리") —
// proghouse/pop/jazz/ambient 는 다음 세션에 같은 구조에 데이터만 더 얹으면 된다.

/// ── 스윙(셔플) ──
/// 재즈를 정박으로 치면 아무리 화성이 맞아도 재즈로 안 들린다. 웹 버전에도 없던 것이라
/// 이식이 아니라 **여기서 새로 넣은 것**이다.
///
/// 한 박(4스텝=16분음표 4개) 안에서 뒷 8분(스텝 2)을 뒤로 민다.
/// [swing] 0.5 = 정박, 0.62 = 재즈 셔플, 0.667 = 완전 셋잇단.
/// 8분만 민다 — 16분(스텝 1·3)까지 건드리면 오히려 비틀거린다.
double swingStep(double step, double swing) {
  if (swing <= 0.5) return step;
  final beat = step ~/ 4;
  final within = step - beat * 4;
  // 뒷 8분(2)만 이동. 0·1·3 은 그대로.
  final moved = (within == 2) ? 4 * swing : within;
  return beat * 4 + moved;
}

/// 장르별 스윙. 없으면 정박.
const Map<String, double> kSwing = {
  'jazz': 0.62, // 재즈 셔플 — 정석에 가까운 값
};

/// 섹션 하나 — 웹 SONG_FORMS 배열형의 원소. 타입별로 쉬는 파트는 null.
class SongSection {
  final String name;
  final int bars;
  final String? drum, bass, chord, melody;
  const SongSection(
    this.name,
    this.bars, {
    this.drum,
    this.bass,
    this.chord,
    this.melody,
  });
}

/// 웹 SONG_FORMS 의 배열형 6곡 — app.html 그대로(값 하나 안 바꿈).
/// 객체형 롱폼(trap 등)은 트랙 구조가 생긴 뒤 다음 덩어리에서.
const Map<String, List<SongSection>> kSongForms = {
  'lofi': [
    SongSection('인트로', 4, chord: 'Lofi Keys V', melody: 'Lofi Sub'),
    SongSection(
      '벌스',
      8,
      drum: 'Lofi Verse',
      bass: 'Lofi Walk V',
      chord: 'Lofi Keys V',
      melody: 'Lofi Sub',
    ),
    SongSection(
      '코러스',
      8,
      drum: 'Lofi Chorus',
      bass: 'Lofi Walk C',
      chord: 'Lofi Keys C',
      melody: 'Lofi Hook',
    ),
    SongSection('브레이크', 4, drum: 'Lofi Break', chord: 'Lofi Keys C'),
    SongSection('아웃트로', 4, chord: 'Lofi Keys V', melody: 'Lofi Sub'),
  ],
  'house': [
    SongSection('인트로', 4, drum: 'House Verse', chord: 'House Stab V'),
    SongSection(
      '벌스',
      8,
      drum: 'House Verse',
      bass: 'House Off V',
      chord: 'House Stab V',
      melody: 'House Pluck V',
    ),
    SongSection(
      '코러스',
      8,
      drum: 'House Chorus',
      bass: 'House Off C',
      chord: 'House Stab C',
      melody: 'House Lead C',
    ),
    SongSection(
      '브레이크',
      4,
      drum: 'House Break',
      chord: 'House Stab C',
      melody: 'House Lead C',
    ),
    SongSection('아웃트로', 4, drum: 'House Verse', bass: 'House Off V'),
  ],
  'hiphop': [
    SongSection('인트로', 4, chord: 'Dusty Keys V', melody: 'Hip Riff V'),
    SongSection(
      '벌스',
      8,
      drum: 'Boom Verse',
      bass: '808 Verse',
      chord: 'Dusty Keys V',
    ),
    SongSection(
      '코러스',
      8,
      drum: 'Boom Chorus',
      bass: '808 Chorus',
      chord: 'Dusty Keys C',
      melody: 'Hip Riff C',
    ),
    SongSection(
      '브레이크',
      4,
      drum: 'Boom Break',
      bass: '808 Verse',
      melody: 'Hip Riff V',
    ),
    SongSection('아웃트로', 4, chord: 'Dusty Keys V', melody: 'Hip Riff V'),
  ],
  'citypop': [
    SongSection('인트로', 4, chord: 'City Maj V', melody: 'City Hook V'),
    SongSection(
      '벌스',
      8,
      drum: 'City Verse',
      bass: 'City Slap V',
      chord: 'City Maj V',
    ),
    SongSection(
      '코러스',
      8,
      drum: 'City Chorus',
      bass: 'City Slap C',
      chord: 'City Maj C',
      melody: 'City Hook C',
    ),
    SongSection(
      '브레이크',
      4,
      drum: 'City Break',
      bass: 'City Slap V',
      chord: 'City Maj V',
    ),
    SongSection('아웃트로', 4, chord: 'City Maj C', melody: 'City Hook C'),
  ],
  'ballad': [
    SongSection('인트로', 4, drum: 'Ballad Intro', chord: 'Ballad Keys V'),
    SongSection(
      '벌스',
      8,
      drum: 'Ballad Verse',
      bass: 'Ballad Long V',
      chord: 'Ballad Keys V',
      melody: 'Ballad Line V',
    ),
    SongSection(
      '코러스',
      8,
      drum: 'Ballad Chorus',
      bass: 'Ballad Long C',
      chord: 'Ballad Keys C',
      melody: 'Ballad Line C',
    ),
    SongSection('브레이크', 4, drum: 'Ballad Intro', chord: 'Ballad Keys C'),
    SongSection('아웃트로', 4, chord: 'Ballad Keys V', melody: 'Ballad Line V'),
  ],
  'rock': [
    SongSection(
      '인트로',
      4,
      drum: 'Rock Verse',
      chord: 'Rock Power V',
      melody: 'Rock Riff V',
    ),
    SongSection(
      '벌스',
      8,
      drum: 'Rock Verse',
      bass: 'Rock Drive V',
      chord: 'Rock Power V',
      melody: 'Rock Riff V',
    ),
    SongSection(
      '코러스',
      8,
      drum: 'Rock Chorus',
      bass: 'Rock Drive C',
      chord: 'Rock Power C',
      melody: 'Rock Riff C',
    ),
    SongSection('브레이크', 4, drum: 'Rock Break', chord: 'Rock Power C'),
    SongSection(
      '아웃트로',
      4,
      drum: 'Rock Verse',
      bass: 'Rock Drive V',
      chord: 'Rock Power V',
    ),
  ],
  // 5단계 47/N — 왈츠(3/4). 판 하나씩만 있어 구간마다 같은 이름을 쓴다
  // (편성이 얇은 것이 왈츠다 — 발라드처럼 벌스/코러스를 갈라 짤 필요가 없다).
  'waltz': [
    SongSection('인트로', 4, chord: 'Waltz Keys', melody: 'Waltz Line'),
    SongSection(
      '벌스',
      8,
      drum: 'Waltz Chorus',
      bass: 'Waltz Walk',
      chord: 'Waltz Keys',
    ),
    SongSection(
      '코러스',
      8,
      drum: 'Waltz Chorus',
      bass: 'Waltz Walk',
      chord: 'Waltz Keys',
      melody: 'Waltz Line',
    ),
    SongSection('브레이크', 4, drum: 'Waltz Chorus', chord: 'Waltz Keys'),
    SongSection('아웃트로', 4, chord: 'Waltz Keys', melody: 'Waltz Line'),
  ],
  // 5단계 47/N — 흔들발라드(6/8). 왈츠와 같은 얼개, 판만 「Sway」.
  'ballad68': [
    SongSection('인트로', 4, chord: 'Sway Keys', melody: 'Sway Line'),
    SongSection(
      '벌스',
      8,
      drum: 'Sway Chorus',
      bass: 'Sway Walk',
      chord: 'Sway Keys',
    ),
    SongSection(
      '코러스',
      8,
      drum: 'Sway Chorus',
      bass: 'Sway Walk',
      chord: 'Sway Keys',
      melody: 'Sway Line',
    ),
    SongSection('브레이크', 4, drum: 'Sway Chorus', chord: 'Sway Keys'),
    SongSection('아웃트로', 4, chord: 'Sway Keys', melody: 'Sway Line'),
  ],
};

/// 웹 FORM_ORDER — 송폼 순서(반복 포함): 인트로-벌스-코러스-브레이크-벌스-코러스-아웃트로.
const List<int> kFormOrder = [0, 1, 2, 3, 1, 2, 4];

/// 장르마다 얼개를 다르게 갈 수 있다.
///
/// 마디 수가 같아도 **빠른 곡은 훨씬 짧게 끝난다.** 기본 얼개(44마디)로
/// 록(137BPM)은 1분 17초, 하우스(124BPM)는 1분 25초였다 — 같은 표를 쓰는
/// 발라드가 2분 35초인데. 「곡」이 아니라 루프로 들리는 길이다.
/// 그 둘만 브레이크–코러스를 한 번 더 돌게 했다(56마디 → 1분 40초 남짓).
/// **새 패턴은 안 만든다** — 이미 있는 구간을 한 번 더 지날 뿐이고,
/// 변형(`variation.dart`)이 바퀴마다 다르게 만든다.
const Map<String, List<int>> kFormOrderBy = {
  'rock': [0, 1, 2, 3, 1, 2, 3, 2, 4],
  'house': [0, 1, 2, 3, 1, 2, 3, 2, 4],
};

/// 이 장르의 얼개. 따로 정한 게 없으면 [kFormOrder].
List<int> formOrderOf(String genre) => kFormOrderBy[genre] ?? kFormOrder;

/// 웹 PLAIN_DRUM — 필인 있는 패턴 → 필인 없는 버전. 같은 패턴이 곡 안에서 여러 번(섹션
/// 반복 + 섹션 안 타일링) 나올 때 필인이 매번 돌면 지겨워지므로, **곡 전체에서 가장
/// 마지막 등장 한 번에만** 필인을 쓰고 나머지는 민짜(Plain) 버전을 쓴다.
/// 배열형 6곡 + 객체형(지금은 트랩만 옮김 — `Trap Hook`) 전부 여기 한 표에 같이 둔다.
/// 패턴 이름이 곡을 가리지 않고 유일하므로 키가 겹칠 걱정이 없다.
const Map<String, String> kPlainDrum = {
  'Lofi Chorus': 'Lofi Chorus Plain',
  'House Chorus': 'House Chorus Plain',
  'Boom Chorus': 'Boom Chorus Plain',
  'City Chorus': 'City Chorus Plain',
  'Ballad Chorus': 'Ballad Chorus Plain',
  'Rock Chorus': 'Rock Chorus Plain',
  'Trap Hook': 'Trap Hook Plain',
  // 아래 넷은 표에서 빠져 있어서 **붙박이 필인이 코러스마다 돌고 있었다** (2026-08-29).
  'Prog Drop': 'Prog Drop Plain',
  'Pop Chorus': 'Pop Chorus Plain',
  'Disco Chorus': 'Disco Chorus Plain',
  'Gospel Chorus': 'Gospel Chorus Plain',
  // 드릴도 같은 자리였다 — 훅이 곡에서 세 번 도는데 하이햇 마무리가 매번 돌았다
  // (2026-09-04). **R&B 코러스는 일부러 안 넣는다** — 네 마디가 한 글자도 안 다르다
  // (크래시는 구간 첫 박이라 민짜에서도 남긴다). 뺄 필인이 아예 없으므로
  // 민짜 판을 만들면 원본과 똑같은 판이 하나 더 생길 뿐이다.
  'Drill Hook': 'Drill Hook Plain',
};

/// 재생 직전 형태 — 시간(초)까지 계산된 드럼 타격.
class SongDrumHit {
  final String lane;
  final int vel;
  final double time;
  const SongDrumHit(this.lane, this.vel, this.time);
}

/// 재생 직전 형태 — 시간(초)까지 계산된 단선율(베이스/멜로디) 음.
class SongMelodicHit {
  final double time, len, glideFromFreq;
  final int vel;
  final double freq;
  const SongMelodicHit(
    this.time,
    this.len,
    this.vel,
    this.freq,
    this.glideFromFreq,
  );
}

/// 재생 직전 형태 — 시간(초)까지 계산된 코드(동시에 울리는 여러 음).
class SongChordHit {
  final double time, len;
  final int vel;
  final List<double> freqs;
  const SongChordHit(this.time, this.len, this.vel, this.freqs);
}

/// 곡 하나를 처음부터 끝까지 편 결과 — `host.batch()`/`host.drumBatch()` 로 그대로 보낼 수
/// 있는 형태.
class SongSchedule {
  final List<SongDrumHit> drums;
  final List<SongMelodicHit> bass;
  final List<SongChordHit> chord;
  final List<SongMelodicHit> melody;
  final int totalBars;
  final double totalSeconds;
  const SongSchedule(
    this.drums,
    this.bass,
    this.chord,
    this.melody,
    this.totalBars,
    this.totalSeconds,
  );
}

/// 웹 `applySongForm()` 의 타이밍 계산 부분을 그대로 옮긴 것.
///
/// 섹션 안에서 패턴은 **제 길이(`pattern.bars`)만큼 반복**된다(웹
/// `for(let b=cur;b+base.bars<=end;b+=base.bars)`) — 예를 들어 8마디 섹션에 2마디짜리
/// 패턴을 넣으면 4번 반복된다. `buildDrumPattern`/`buildRowsPattern`/`buildChordPattern`
/// 자체도 내부적으로 `bars`/`src` 로 한 번 타일링하므로(patterns.dart), 이건 **타일링의
/// 타일링**이다 — 웹의 `genreClip()` 이 이미 타일링된 패턴을 돌려주고 그걸 다시 섹션
/// 안에서 반복 배치하는 것과 정확히 같은 이중 구조다.
SongSchedule buildSong(
  String genre, {
  required double bpm,
  MusicKey key = const MusicKey(),
}) {
  final form = kSongForms[genre];
  if (form == null) throw ArgumentError('알 수 없는 장르: $genre');
  final stepSec = 60.0 / bpm / 4;
  // **마디 길이는 스타일의 박자가 정한다** (5단계 47/N). 칸은 늘 16분음표라
  // `stepSec` 은 그대로고, 한 마디에 그 칸이 몇 개인지만 달라진다.
  final spb = meterStepsOf(genreMeter(genre));

  // 1단계 — 필인 있는 드럼 패턴이 곡 전체에서 마지막으로 등장하는 마디를 미리 구한다.
  // (뒤에서 덮어쓰므로 순서대로 훑으면 최종값 = 가장 마지막 등장.)
  final fillAt = <String, int>{};
  {
    var scan = 0;
    for (final si in formOrderOf(genre)) {
      final sec = form[si];
      final end = scan + sec.bars;
      final pname = sec.drum;
      if (pname != null && kPlainDrum.containsKey(pname)) {
        final base = findDrumPattern(pname);
        if (base != null) {
          int? last;
          for (var b = scan; b + base.bars <= end; b += base.bars) {
            last = b;
          }
          if (last != null) fillAt[pname] = last;
        }
      }
      scan = end;
    }
  }

  final drums = <SongDrumHit>[];
  final bass = <SongMelodicHit>[];
  final chord = <SongChordHit>[];
  final melody = <SongMelodicHit>[];

  var cur = 0;
  for (final si in formOrderOf(genre)) {
    final sec = form[si];
    final end = cur + sec.bars;

    final dName = sec.drum;
    if (dName != null) {
      final base = findDrumPattern(dName);
      final plainName = kPlainDrum[dName];
      final flat = plainName != null ? findDrumPattern(plainName) : null;
      if (base != null) {
        for (var b = cur; b + base.bars <= end; b += base.bars) {
          final useFill = flat == null || fillAt[dName] == b;
          final def = useFill ? base : flat;
          final barSteps = b * spb;
          for (final h in buildDrumPattern(def)) {
            drums.add(
              SongDrumHit(h.lane, h.vel, (barSteps + h.step) * stepSec),
            );
          }
        }
      }
    }

    final bName = sec.bass;
    if (bName != null) {
      final base = findBassPattern(bName);
      if (base != null) {
        for (var b = cur; b + base.bars <= end; b += base.bars) {
          final barSteps = b * spb;
          for (final h in buildRowsPattern(base, 'bass', key)) {
            bass.add(
              SongMelodicHit(
                (barSteps + h.step) * stepSec,
                h.len * stepSec,
                h.vel,
                h.freq,
                h.glideFromFreq,
              ),
            );
          }
        }
      }
    }

    final cName = sec.chord;
    if (cName != null) {
      final base = findChordPattern(cName);
      if (base != null) {
        for (var b = cur; b + base.bars <= end; b += base.bars) {
          final barSteps = b * spb;
          for (final h in buildChordPattern(base, key)) {
            chord.add(
              SongChordHit(
                (barSteps + h.step) * stepSec,
                h.len * stepSec,
                h.vel,
                h.freqs,
              ),
            );
          }
        }
      }
    }

    final mName = sec.melody;
    if (mName != null) {
      final base = findMelodyPattern(mName);
      if (base != null) {
        for (var b = cur; b + base.bars <= end; b += base.bars) {
          final barSteps = b * spb;
          for (final h in buildRowsPattern(base, 'melody', key)) {
            melody.add(
              SongMelodicHit(
                (barSteps + h.step) * stepSec,
                h.len * stepSec,
                h.vel,
                h.freq,
                h.glideFromFreq,
              ),
            );
          }
        }
      }
    }

    cur = end;
  }

  return SongSchedule(
    drums,
    bass,
    chord,
    melody,
    cur,
    cur * spb * stepSec,
  );
}

// ═══════════════════ 4단계 5/N — 객체형 롱폼(트랙 구조 일반화) ═══════════════════
//
// 배열형과 다른 점은 딱 하나: 섹션의 `parts` 키가 **타입이 아니라 슬롯 이름**이다.
// 그래서 같은 타입(chord) 트랙을 여러 개(pad/brass) 둘 수 있다. 그 나머지 — 패턴을
// 찾고 타일링하고 시간을 계산하는 로직 — 는 [buildSong] 과 완전히 같다(그래서 아래
// [buildObjectSong] 은 사실상 그 로직을 슬롯 맵 위에서 반복한 것뿐이다).

/// 트랙 하나 — 웹 SONG_FORMS 객체형의 `tracks[i]`. [type] 은 drum/bass/chord/melody
/// 중 하나로 **어느 패턴 표에서 찾고 어떤 빌더를 쓸지**를 정한다(믹서 라우팅과는 무관 —
/// 라우팅은 [slot] 이름으로 한다, genre_mix.dart `melodicSlotsFor()` 참고).
/// [voice] 는 신스 악기 이름(synth.dart INSTRUMENTS) — 슬롯마다 다르다(패드 vs 브라스).
class ObjectSongTrack {
  final String slot, type;
  final String voice;
  const ObjectSongTrack(this.slot, this.type, this.voice);
}

/// 섹션 하나 — 웹 객체형 SONG_FORMS 원소. `parts` 키가 슬롯 이름이라(타입이 아니다)
/// 같은 타입 트랙 여러 개를 가를 수 있다. 없는 슬롯은 그냥 안 들어 있다(그 섹션에서 쉼).
class ObjectSongSection {
  final String name;
  final int bars;
  final Map<String, String> parts;
  const ObjectSongSection(this.name, this.bars, this.parts);
}

class ObjectSongForm {
  final List<ObjectSongTrack> tracks;
  final List<ObjectSongSection> sections;
  final List<int> order;
  const ObjectSongForm(this.tracks, this.sections, this.order);
}

/// 웹 SONG_FORMS 의 객체형 롱폼 — app.html 7764줄~, 값 그대로.
/// 트랩 · 프로그하우스 · 팝 이식 완료. jazz/ambient 는 다음 덩어리.
/// (jazz 는 **7화음**을 쓰므로 코드 패턴 다섯째 값을 확인하고 옮길 것 — 웹 주석 참고)
const Map<String, ObjectSongForm> kObjectSongForms = {
  // 「새벽 네 시」 140 BPM · C단조 · 120마디 ≈ 3분 26초.
  // 벌스 i–VI–VII–v 로 자리를 비우고, 프리훅에서 VI–VII 로 밀어올린 뒤 훅은 iv 로
  // 시작해 i 로 착지한다. 브리지만 III 로 열어 잠깐 숨통을 틔운다.
  'trap': ObjectSongForm(
    [
      ObjectSongTrack('drum', 'drum', 'k808'), // voice 는 drum 타입엔 안 쓰임(자리만)
      ObjectSongTrack('b808', 'bass', 'sine'),
      ObjectSongTrack('pad', 'chord', 'analogpad'),
      ObjectSongTrack('brass', 'chord', 'brass'),
      ObjectSongTrack('bell', 'melody', 'bell'),
      ObjectSongTrack('plk', 'melody', 'pluck'),
    ],
    [
      ObjectSongSection('인트로', 8, {
        'drum': 'Trap Intro',
        'pad': 'Trap Pad V',
        'bell': 'Trap Bell I',
      }),
      ObjectSongSection('벌스', 16, {
        'drum': 'Trap Verse',
        'b808': 'Trap 808 V',
        'pad': 'Trap Pad V',
        'bell': 'Trap Bell V',
      }),
      ObjectSongSection('프리훅', 8, {
        'drum': 'Trap Pre',
        'b808': 'Trap 808 P',
        'pad': 'Trap Pad P',
        'brass': 'Trap Brass P',
      }),
      ObjectSongSection('훅', 16, {
        'drum': 'Trap Hook',
        'b808': 'Trap 808 H',
        'pad': 'Trap Pad H',
        'brass': 'Trap Brass H',
        'bell': 'Trap Bell H',
        'plk': 'Trap Pluck H',
      }),
      ObjectSongSection('브리지', 8, {
        'drum': 'Trap Bridge',
        'b808': 'Trap 808 B',
        'pad': 'Trap Pad B',
        'bell': 'Trap Bell B',
      }),
      ObjectSongSection('아웃트로', 8, {
        'drum': 'Trap Outro',
        'pad': 'Trap Pad V',
        'bell': 'Trap Bell I',
      }),
    ],
    [0, 1, 2, 3, 1, 2, 3, 4, 3, 5],
  ),

  // 「밤을 건너」 128 BPM · C단조 · 112마디 ≈ 3분 30초.
  // 브레이크다운으로 한 번 비웠다가 빌드업에서 밀어 올리고 드롭에서 터뜨린다.
  // order 에 브레이크(2)→빌드(3)→드롭(4)이 두 번 도는 게 이 장르의 뼈대다.
  'proghouse': ObjectSongForm(
    [
      ObjectSongTrack('drum', 'drum', 'k909'),
      ObjectSongTrack('bass', 'bass', 'bass'),
      ObjectSongTrack('pad', 'chord', 'analogpad'),
      ObjectSongTrack('stab', 'chord', 'stab'),
      ObjectSongTrack('arp', 'melody', 'pluck'),
      ObjectSongTrack('lead', 'melody', 'saw'),
    ],
    [
      ObjectSongSection('인트로', 8, {'drum': 'Prog Intro', 'pad': 'Prog Pad I'}),
      ObjectSongSection('그루브', 8, {
        'drum': 'Prog Groove',
        'bass': 'Prog Bass G',
        'pad': 'Prog Pad I',
        'stab': 'Prog Stab G',
      }),
      ObjectSongSection('브레이크다운', 16, {
        'drum': 'Prog Break',
        'pad': 'Prog Pad Bk',
        'arp': 'Prog Arp',
      }),
      ObjectSongSection('빌드업', 8, {
        'drum': 'Prog Build',
        'bass': 'Prog Bass B',
        'pad': 'Prog Pad B',
        // 빌드업은 화성이 VI–VI–VII–VII 라 일반 'Prog Arp'(i–VI–III–VII)를 쓰면
        // Eb 가 Bb 의 D 와 부딪힌다. 웹에서 그 충돌을 잡으려고 따로 만든 게 'Prog Arp B'.
        'arp': 'Prog Arp B',
        'lead': 'Prog Lead B',
      }),
      ObjectSongSection('드롭', 16, {
        'drum': 'Prog Drop',
        'bass': 'Prog Bass D',
        'pad': 'Prog Pad D',
        'stab': 'Prog Stab D',
        'arp': 'Prog Arp',
        'lead': 'Prog Lead D',
      }),
      ObjectSongSection('브레이크2', 16, {
        'drum': 'Prog Break',
        'pad': 'Prog Pad Bk',
        'arp': 'Prog Arp',
        'lead': 'Prog Lead D',
      }),
      ObjectSongSection('아웃트로', 8, {
        'drum': 'Prog Outro',
        'bass': 'Prog Bass G',
        'pad': 'Prog Pad I',
      }),
    ],
    [0, 1, 2, 3, 4, 1, 5, 3, 4, 6],
  ),

  // 「여름이 오면」 104 BPM · **C장조** · 96마디 ≈ 3분 41초.
  // 재생할 때 `MusicKey(mode:'major')` 를 넘겨야 한다 — 안 넘기면 단조로 나온다.
  // 벌스 I–V–vi–IV, 프리코러스 vi–IV–I–V 로 밀어올리고 코러스는 IV 로 시작해 vi 로 여운.
  // 트랙이 7개로 지금까지 중 가장 많다(스트링이 코러스·브리지에만 들어온다).
  'pop': ObjectSongForm(
    [
      ObjectSongTrack('drum', 'drum', 'acoustic'),
      ObjectSongTrack('bass', 'bass', 'fingerbass'),
      ObjectSongTrack('piano', 'chord', 'piano'),
      ObjectSongTrack('gtr', 'chord', 'guitar'),
      ObjectSongTrack('voc', 'melody', 'vocal'),
      ObjectSongTrack('plk', 'melody', 'pluck'),
      ObjectSongTrack('str', 'chord', 'strings'),
    ],
    [
      ObjectSongSection('인트로', 8, {
        'drum': 'Pop Intro',
        'piano': 'Pop Keys V',
        'plk': 'Pop Arp',
      }),
      ObjectSongSection('벌스', 16, {
        'drum': 'Pop Verse',
        'bass': 'Pop Bass V',
        'piano': 'Pop Keys V',
        'voc': 'Pop Voc V',
      }),
      ObjectSongSection('프리', 8, {
        'drum': 'Pop Pre',
        'bass': 'Pop Bass P',
        'piano': 'Pop Keys P',
        'gtr': 'Pop Gtr P',
        'plk': 'Pop Arp P',
      }),
      ObjectSongSection('코러스', 16, {
        'drum': 'Pop Chorus',
        'bass': 'Pop Bass C',
        'piano': 'Pop Keys C',
        'gtr': 'Pop Gtr C',
        'voc': 'Pop Voc C',
        'plk': 'Pop Arp C',
        'str': 'Pop Str C',
      }),
      // 브리지만 드럼이 통째로 빠진다(웹도 parts 에 drum 이 없다) — 일부러 비운 것.
      ObjectSongSection('브리지', 8, {
        'bass': 'Pop Bass B',
        'piano': 'Pop Keys B',
        'voc': 'Pop Voc B',
        'str': 'Pop Str B',
      }),
      ObjectSongSection('아웃트로', 8, {
        'drum': 'Pop Intro',
        'piano': 'Pop Keys V',
        'plk': 'Pop Arp',
      }),
    ],
    [0, 1, 2, 3, 1, 3, 4, 5],
  ),

  // 「새벽 두 시」 116 BPM · C단조 · 96마디 ≈ 3분 19초.
  // iim7♭5–V7–im7–VImaj7 (재즈 단조의 기본). B섹션은 ivm7–VII7–IIImaj7–VImaj7.
  // **3화음이 아니라 7화음**을 쓴다 — 코드 패턴(patterns.dart)의 다섯째 값이 그걸 지정하고,
  // 그건 4단계 2/N 에서 이미 옮겨져 있다. 여기서는 패턴 이름만 엮으면 된다.
  // 아웃트로에 드럼이 없다(웹도 parts 에 drum 이 빠져 있다) — 색소폰으로 끝난다.
  'jazz': ObjectSongForm(
    [
      ObjectSongTrack('drum', 'drum', 'acoustic'),
      ObjectSongTrack('bass', 'bass', 'upright'),
      ObjectSongTrack('piano', 'chord', 'epiano'),
      ObjectSongTrack('vib', 'chord', 'marimba'),
      ObjectSongTrack('sax', 'melody', 'sax'),
      ObjectSongTrack('gtr', 'melody', 'nylon'),
    ],
    [
      ObjectSongSection('인트로', 8, {
        'drum': 'Jazz Intro',
        'bass': 'Jazz Bass I',
        'piano': 'Jazz Keys I',
      }),
      ObjectSongSection('헤드', 16, {
        'drum': 'Jazz Head',
        'bass': 'Jazz Walk H',
        'piano': 'Jazz Keys H',
        'sax': 'Jazz Sax H',
      }),
      ObjectSongSection('B', 8, {
        'drum': 'Jazz B',
        'bass': 'Jazz Walk B',
        'piano': 'Jazz Keys B',
        'vib': 'Jazz Vib B',
        'sax': 'Jazz Sax B',
      }),
      ObjectSongSection('솔로', 16, {
        'drum': 'Jazz Solo',
        'bass': 'Jazz Walk H',
        'piano': 'Jazz Keys H',
        'vib': 'Jazz Vib H',
        'gtr': 'Jazz Gtr S',
      }),
      ObjectSongSection('헤드2', 16, {
        'drum': 'Jazz Head',
        'bass': 'Jazz Walk H',
        'piano': 'Jazz Keys H',
        'vib': 'Jazz Vib H',
        'sax': 'Jazz Sax H',
      }),
      ObjectSongSection('아웃트로', 8, {
        'bass': 'Jazz Bass I',
        'piano': 'Jazz Keys I',
        'sax': 'Jazz Sax O',
      }),
    ],
    [0, 1, 2, 3, 1, 2, 4, 5],
  ),

  // 「긴 겨울」 72 BPM · C단조 · 64마디 ≈ 3분 33초.
  // 코드가 사실상 두 개뿐이다(i(9) ↔ VImaj7, IIImaj7 ↔ VIIsus2).
  // 화성이 아니라 **질감**으로 끌고 가는 곡이라 섹션이 악기 층으로 구분된다.
  //
  // ⚠️ 드럼 트랙의 슬롯 이름이 'drum' 이 아니라 **'perc'** 다(웹 그대로).
  //    `melodicSlotsFor`/`applyGenreMixTo` 가 슬롯 이름을 박아 두면 이 곡의 퍼커션이
  //    멀로딕 버스로 잘못 가고 드럼 버스는 투명하게 남는다 — 그래서 `GenreMixSpec.drumSlot`
  //    으로 곡마다 지정하게 바꿨다.
  'ambient': ObjectSongForm(
    [
      ObjectSongTrack('pad', 'chord', 'analogpad'),
      ObjectSongTrack('str', 'chord', 'jpstrings'),
      ObjectSongTrack('sub', 'bass', 'sine'),
      ObjectSongTrack('bell', 'melody', 'bell'),
      ObjectSongTrack('harp', 'melody', 'harp'),
      ObjectSongTrack('perc', 'drum', 'lofi'),
      ObjectSongTrack('str2', 'chord', 'strings'),
    ],
    [
      ObjectSongSection('여명', 8, {'pad': 'Amb Pad A', 'sub': 'Amb Sub'}),
      ObjectSongSection('안개', 16, {
        'pad': 'Amb Pad A',
        'str': 'Amb Str A',
        'sub': 'Amb Sub',
        'bell': 'Amb Bell A',
      }),
      ObjectSongSection('눈', 16, {
        'pad': 'Amb Pad B',
        'str': 'Amb Str B',
        'sub': 'Amb Sub2',
        'bell': 'Amb Bell B',
        'harp': 'Amb Harp B',
        'perc': 'Amb Perc',
      }),
      ObjectSongSection('정적', 8, {'pad': 'Amb Pad A', 'harp': 'Amb Harp A'}),
      ObjectSongSection('해질녘', 16, {
        'pad': 'Amb Pad A',
        'str': 'Amb Str A',
        'sub': 'Amb Sub',
        'bell': 'Amb Bell A',
        'harp': 'Amb Harp A',
        'str2': 'Amb Str2 A',
      }),
    ],
    [0, 1, 2, 3, 4],
  ),

  // ── 드릴 (Phase 5) — 142 BPM · C단조 ──
  // 「스네어는 3박에만」이 이 장르의 표식이다. 벌스는 i–VI 로 눕히고,
  // 프리훅에서 VI–VII 로 밀어 올린 뒤 훅은 i 로 떨어진다.
  'drill': ObjectSongForm(
    [
      ObjectSongTrack('drum', 'drum', 'k808'),
      ObjectSongTrack('b808', 'bass', 'sine'),
      ObjectSongTrack('pad', 'chord', 'analogpad'),
      ObjectSongTrack('bell', 'melody', 'bell'),
      ObjectSongTrack('plk', 'melody', 'pluck'),
    ],
    [
      ObjectSongSection('인트로', 8, {
        'drum': 'Drill Intro',
        'pad': 'Drill Pad V',
        'bell': 'Drill Bell I',
      }),
      ObjectSongSection('벌스', 16, {
        'drum': 'Drill Verse',
        'b808': 'Drill 808 V',
        'pad': 'Drill Pad V',
        'bell': 'Drill Bell V',
      }),
      ObjectSongSection('프리훅', 8, {
        'drum': 'Drill Pre',
        'b808': 'Drill 808 P',
        'pad': 'Drill Pad P',
      }),
      ObjectSongSection('훅', 16, {
        'drum': 'Drill Hook',
        'b808': 'Drill 808 H',
        'pad': 'Drill Pad H',
        'bell': 'Drill Bell H',
        'plk': 'Drill Pluck H',
      }),
      ObjectSongSection('브레이크', 8, {
        'drum': 'Drill Break',
        'pad': 'Drill Pad V',
        'bell': 'Drill Bell I',
      }),
      ObjectSongSection('아웃트로', 8, {
        'drum': 'Drill Intro',
        'pad': 'Drill Pad V',
        'bell': 'Drill Bell I',
      }),
    ],
    [0, 1, 2, 3, 1, 2, 3, 4, 3, 5],
  ),

  // ── R&B (Phase 5) — 92 BPM · C단조 ──
  // 7화음이 이 장르의 소리다. 벌스 i–VI, 코러스 iv–VII–VI–i(min9 로 착지).
  //
  // **마디 수는 템포를 보고 정한다.** 처음엔 트랩의 얼개(벌스 16마디)를 그대로 베꼈는데,
  // 트랩은 140BPM 이라 16마디가 27초지만 여기는 92BPM 이라 **42초**다.
  // 곡 전체가 5분 13초 — 다른 장르(1분 17초~3분 42초)에서 혼자 튀었다.
  // 끝까지 렌더해 보고 알았다(`long_run_test`).
  // 디스코 — 네 박에 킥, 16분 건반 컷, 위층 스트링, 브라스 리프. (2026-08-29)
  'disco': ObjectSongForm(
    [
      ObjectSongTrack('drum', 'drum', 'acoustic'),
      ObjectSongTrack('bass', 'bass', 'fingerbass'),
      ObjectSongTrack('keys', 'chord', 'epiano'),
      ObjectSongTrack('str', 'chord', 'strings'),
      ObjectSongTrack('lead', 'melody', 'brass'),
    ],
    [
      ObjectSongSection('인트로', 8, {
        'drum': 'Disco Intro',
        'keys': 'Disco Keys V',
      }),
      ObjectSongSection('벌스', 16, {
        'drum': 'Disco Verse',
        'bass': 'Disco Bass V',
        'keys': 'Disco Keys V',
        'lead': 'Disco Line V',
      }),
      ObjectSongSection('프리', 8, {
        'drum': 'Disco Pre',
        'bass': 'Disco Bass P',
        'keys': 'Disco Keys P',
        'str': 'Disco Str P',
      }),
      ObjectSongSection('코러스', 16, {
        'drum': 'Disco Chorus',
        'bass': 'Disco Bass C',
        'keys': 'Disco Keys C',
        'str': 'Disco Str C',
        'lead': 'Disco Line C',
      }),
      ObjectSongSection('브레이크', 8, {
        'drum': 'Disco Break',
        'keys': 'Disco Keys V',
        'str': 'Disco Str V',
      }),
      ObjectSongSection('아웃트로', 8, {
        'drum': 'Disco Intro',
        'keys': 'Disco Keys V',
      }),
    ],
    [0, 1, 2, 3, 1, 2, 3, 4, 5],
  ),

  // 가스펠 — 피아노가 앞, 오르간이 뒤. 셔플로 흔들린다. (2026-08-29)
  'gospel': ObjectSongForm(
    [
      ObjectSongTrack('drum', 'drum', 'acoustic'),
      ObjectSongTrack('bass', 'bass', 'fingerbass'),
      ObjectSongTrack('keys', 'chord', 'piano'),
      ObjectSongTrack('org', 'chord', 'vintorgan'),
      ObjectSongTrack('voc', 'melody', 'vocal'),
    ],
    [
      ObjectSongSection('인트로', 8, {
        'drum': 'Gospel Intro',
        'keys': 'Gospel Keys V',
      }),
      ObjectSongSection('벌스', 12, {
        'drum': 'Gospel Verse',
        'bass': 'Gospel Bass V',
        'keys': 'Gospel Keys V',
        'voc': 'Gospel Line V',
      }),
      ObjectSongSection('프리', 8, {
        'drum': 'Gospel Pre',
        'bass': 'Gospel Bass P',
        'keys': 'Gospel Keys P',
      }),
      ObjectSongSection('코러스', 12, {
        'drum': 'Gospel Chorus',
        'bass': 'Gospel Bass C',
        'keys': 'Gospel Keys C',
        'org': 'Gospel Org C',
        'voc': 'Gospel Line C',
      }),
      ObjectSongSection('브릿지', 8, {
        'drum': 'Gospel Break',
        'bass': 'Gospel Bass B',
        'keys': 'Gospel Keys B',
        'org': 'Gospel Org B',
      }),
      ObjectSongSection('아웃트로', 8, {
        'drum': 'Gospel Intro',
        'keys': 'Gospel Keys V',
        'org': 'Gospel Org V',
      }),
    ],
    // 인트로–벌스–프리–코러스–브릿지–벌스–코러스–아웃트로.
    // 78BPM 에 16마디 구간이면 5분 45초가 나왔다 — 낙서장에 쓰기엔 너무 길다.
    [0, 1, 2, 3, 4, 1, 3, 5],
  ),

  'rnb': ObjectSongForm(
    [
      ObjectSongTrack('drum', 'drum', 'acoustic'),
      ObjectSongTrack('bass', 'bass', 'fingerbass'),
      ObjectSongTrack('keys', 'chord', 'epiano'),
      ObjectSongTrack('pad', 'chord', 'analogpad'),
      ObjectSongTrack('voc', 'melody', 'vocal'),
    ],
    [
      ObjectSongSection('인트로', 8, {'drum': 'RnB Intro', 'keys': 'RnB Keys V'}),
      ObjectSongSection('벌스', 12, {
        'drum': 'RnB Verse',
        'bass': 'RnB Bass V',
        'keys': 'RnB Keys V',
        'voc': 'RnB Line V',
      }),
      ObjectSongSection('프리', 8, {
        'drum': 'RnB Pre',
        'bass': 'RnB Bass P',
        'keys': 'RnB Keys P',
        'pad': 'RnB Pad P',
      }),
      ObjectSongSection('코러스', 12, {
        'drum': 'RnB Chorus',
        'bass': 'RnB Bass C',
        'keys': 'RnB Keys C',
        'pad': 'RnB Pad C',
        'voc': 'RnB Line C',
      }),
      ObjectSongSection('브레이크', 8, {
        'drum': 'RnB Break',
        'keys': 'RnB Keys V',
        'voc': 'RnB Line V',
      }),
      ObjectSongSection('아웃트로', 8, {'drum': 'RnB Intro', 'keys': 'RnB Keys V'}),
    ],
    // 브레이크 뒤 마지막 코러스는 남긴다 — 그게 이 얼개의 매듭이다
    [0, 1, 2, 3, 1, 3, 4, 3, 5],
  ),
};

/// 곡 하나를 처음부터 끝까지 편 결과(객체형) — 슬롯 이름별로 갈라서 들고 있는다.
/// [mono] 는 bass/melody 타입 슬롯(단선율), [chord] 는 chord 타입 슬롯(화음).
class ObjectSongSchedule {
  final List<SongDrumHit> drums;
  final Map<String, List<SongMelodicHit>> mono;
  final Map<String, List<SongChordHit>> chord;
  final int totalBars;
  final double totalSeconds;
  const ObjectSongSchedule(
    this.drums,
    this.mono,
    this.chord,
    this.totalBars,
    this.totalSeconds,
  );
}

/// [buildSong] 의 객체형 버전 — 로직은 완전히 같고(섹션 이어붙이기·패턴 자기 반복·
/// 마지막 등장에만 필인), `parts` 를 타입 필드 대신 슬롯 맵으로 훑는 것만 다르다.
ObjectSongSchedule buildObjectSong(
  String genre, {
  required double bpm,
  MusicKey key = const MusicKey(),
}) {
  final form = kObjectSongForms[genre];
  if (form == null) throw ArgumentError('알 수 없는 장르(객체형): $genre');
  final stepSec = 60.0 / bpm / 4;
  // 마디 길이는 스타일의 박자가 정한다 — `buildSong` 과 같은 규칙.
  final spb = meterStepsOf(genreMeter(genre));
  final swing = kSwing[genre] ?? 0.5;
  // 스윙은 **마디 안에서만** 민다 — 마디 시작(barSteps)은 그대로여야 박자가 안 밀린다.
  double t(int barSteps, num step) =>
      (barSteps + swingStep(step.toDouble(), swing)) * stepSec;
  final trackOf = {for (final t in form.tracks) t.slot: t};

  // 필인 있는 드럼 패턴이 곡 전체에서 마지막으로 등장하는 마디 — drum 슬롯만 본다
  // (웹 PLAIN_DRUM 자체가 드럼 전용이라 배열형 [buildSong] 과 같은 이유).
  // 드럼 슬롯 이름은 곡마다 다를 수 있다(엠비언트는 'perc'). 이름이 아니라 **타입**으로 찾는다.
  final drumSlot = form.tracks
      .where((t) => t.type == 'drum')
      .map((t) => t.slot)
      .firstOrNull;
  final fillAt = <String, int>{};
  {
    var scan = 0;
    for (final si in form.order) {
      final sec = form.sections[si];
      final end = scan + sec.bars;
      final pname = drumSlot == null ? null : sec.parts[drumSlot];
      if (pname != null && kPlainDrum.containsKey(pname)) {
        final base = findDrumPattern(pname);
        if (base != null) {
          int? last;
          for (var b = scan; b + base.bars <= end; b += base.bars) {
            last = b;
          }
          if (last != null) fillAt[pname] = last;
        }
      }
      scan = end;
    }
  }

  final drums = <SongDrumHit>[];
  final mono = <String, List<SongMelodicHit>>{
    for (final t in form.tracks)
      if (t.type == 'bass' || t.type == 'melody') t.slot: <SongMelodicHit>[],
  };
  final chordMap = <String, List<SongChordHit>>{
    for (final t in form.tracks)
      if (t.type == 'chord') t.slot: <SongChordHit>[],
  };

  var cur = 0;
  for (final si in form.order) {
    final sec = form.sections[si];
    final end = cur + sec.bars;

    sec.parts.forEach((slot, patName) {
      final track = trackOf[slot];
      if (track == null) return;
      switch (track.type) {
        case 'drum':
          final base = findDrumPattern(patName);
          final plainName = kPlainDrum[patName];
          final flat = plainName != null ? findDrumPattern(plainName) : null;
          if (base == null) return;
          for (var b = cur; b + base.bars <= end; b += base.bars) {
            final useFill = flat == null || fillAt[patName] == b;
            final def = useFill ? base : flat;
            final barSteps = b * spb;
            for (final h in buildDrumPattern(def)) {
              drums.add(SongDrumHit(h.lane, h.vel, t(barSteps, h.step)));
            }
          }
          break;
        case 'bass':
        case 'melody':
          final base = track.type == 'bass'
              ? findBassPattern(patName)
              : findMelodyPattern(patName);
          if (base == null) return;
          for (var b = cur; b + base.bars <= end; b += base.bars) {
            final barSteps = b * spb;
            for (final h in buildRowsPattern(base, track.type, key)) {
              mono[slot]!.add(
                SongMelodicHit(
                  t(barSteps, h.step),
                  h.len * stepSec,
                  h.vel,
                  h.freq,
                  h.glideFromFreq,
                ),
              );
            }
          }
          break;
        case 'chord':
          final base = findChordPattern(patName);
          if (base == null) return;
          for (var b = cur; b + base.bars <= end; b += base.bars) {
            final barSteps = b * spb;
            for (final h in buildChordPattern(base, key)) {
              chordMap[slot]!.add(
                SongChordHit(
                  t(barSteps, h.step),
                  h.len * stepSec,
                  h.vel,
                  h.freqs,
                ),
              );
            }
          }
          break;
      }
    });

    cur = end;
  }

  return ObjectSongSchedule(
    drums,
    mono,
    chordMap,
    cur,
    cur * spb * stepSec,
  );
}
