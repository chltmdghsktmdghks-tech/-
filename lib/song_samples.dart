// 샘플곡 — 처음 켰을 때부터 홈 화면 아래 「샘플곡」 서랍에 들어 있는 완성곡들.
//
// **씬 프리셋(`setGenre`)을 안 쓴다.** 씬은 전부 이름·마디수만 있는 빈 자리로
// 두고, 소리는 전부 **타임라인 레인**(`Arrangement.lanes`/`putLane`)에 직접
// 놓는다 — 사람이 타임라인 화면에서 악기 줄마다 클립을 하나씩 끌어다 놓은
// 것과 똑같은 자료 모양이다(2026-09, 사용자 요청). 씬 화면을 열면 트랙마다
// 패턴이 "없음"으로 보인다 — 그게 맞다, 여기서 만든 곡은 씬이 아니라
// 타임라인이 주인이다.
//
// 레인은 **되풀이하지 않는다**(`sequencer.dart` — 씬 클립과 다른 점). 그래서
// 구간이 판 길이보다 길면(예: 8마디 벌스에 4마디 판) [_lane] 이 그 판 길이
// 간격으로 여러 번 놓아 채운다 — 사람이 같은 클립을 복사해 이어 붙인 것과
// 결과가 같다.
//
// 멜로디(노래·리드) 트랙은 간주(인트로·브레이크·아웃트로)에서만 놓고,
// 벌스·코러스·프리 등 "노래가 있어야 할" 자리에는 아예 안 놓는다 — 부를
// 자리를 비워 두는 것도 곡 짜기의 일부라서다. 그 간주 멜로디는 라이브러리
// 판을 안 쓰고 여기서 새로 썼다 — 코드톤(0·2·4도)만 짚으면 심심하다.
// 지나가는음(1·3·5·6도)을 섞어 스텝으로 움직이는 대목을 넣었다.
import 'fx.dart' show masterPresetForGenre;
import 'genres.dart';
import 'patterns.dart';
import 'presets.dart';
import 'project.dart';

/// 샘플곡 하나 — 이름·장르·그리고 빈 [Project] 를 채우는 손짓.
class SampleSong {
  final String name;
  final String genre;
  final void Function(Project p) customize;
  const SampleSong(this.name, this.genre, this.customize);
}

// ── 간주 멜로디 — 장르마다 새로 씀(코드톤 0·2·4도 + 지나가는음 1·3·5·6도) ──

const _lofiLine = NotePatternDef('샘플 간주 · 로파이', 4, 4, [
  [0, 0, 3, 2],
  [4, 4, 3, 1],
  [2, 8, 2, 2],
  [1, 11, 2, 1],
  [0, 14, 2, 2],
  [2, 17, 3, 1],
  [5, 21, 3, 2],
  [4, 25, 3, 1],
  [2, 29, 3, 2],
  [0, 33, 3, 1],
  [1, 37, 2, 2],
  [2, 40, 4, 1],
  [4, 45, 3, 2],
  [6, 49, 3, 1],
  [5, 53, 3, 2],
  [4, 57, 3, 1],
  [2, 61, 3, 2],
]);

const _houseLine = NotePatternDef('샘플 간주 · 하우스', 4, 4, [
  [0, 0, 2, 2],
  [2, 2, 2, 1],
  [4, 4, 2, 2],
  [2, 6, 2, 1],
  [0, 8, 2, 2],
  [2, 10, 2, 1],
  [4, 12, 2, 2],
  [5, 14, 2, 3],
  [4, 16, 2, 2],
  [2, 18, 2, 1],
  [0, 20, 2, 2],
  [2, 22, 2, 1],
  [4, 24, 2, 2],
  [6, 26, 2, 1],
  [5, 28, 2, 2],
  [4, 30, 2, 3],
  [2, 32, 2, 2],
  [4, 34, 2, 1],
  [5, 36, 2, 2],
  [4, 38, 2, 1],
  [2, 40, 2, 2],
  [0, 42, 2, 1],
  [2, 44, 2, 2],
  [4, 46, 2, 1],
  [5, 48, 2, 2],
  [7, 50, 2, 3],
  [6, 52, 2, 1],
  [5, 54, 2, 2],
  [4, 56, 4, 2],
  [2, 60, 4, 3],
]);

const _hiphopLine = NotePatternDef('샘플 간주 · 힙합', 4, 4, [
  [0, 3, 3, 2],
  [2, 8, 2, 1],
  [3, 11, 2, 2],
  [2, 15, 2, 1],
  [0, 19, 3, 2],
  [2, 26, 2, 1],
  [4, 29, 3, 2],
  [3, 33, 2, 1],
  [2, 36, 3, 2],
  [0, 42, 3, 1],
  [2, 49, 2, 2],
  [4, 52, 2, 1],
  [6, 55, 3, 2],
  [4, 59, 3, 1],
  [2, 62, 2, 2],
]);

const _balladLine = NotePatternDef('샘플 간주 · 발라드', 4, 4, [
  [0, 0, 6, 2],
  [2, 6, 2, 1],
  [4, 8, 6, 2],
  [3, 14, 2, 1],
  [2, 16, 8, 2],
  [4, 24, 4, 1],
  [5, 28, 4, 2],
  [7, 32, 6, 3],
  [6, 38, 2, 1],
  [5, 40, 4, 2],
  [4, 44, 4, 1],
  [2, 48, 6, 2],
  [1, 54, 2, 1],
  [0, 56, 8, 2],
]);

const _popLine = NotePatternDef('샘플 간주 · 팝', 4, 4, [
  [0, 0, 2, 2],
  [2, 2, 2, 2],
  [4, 4, 2, 3],
  [2, 6, 2, 2],
  [0, 8, 2, 2],
  [2, 10, 2, 2],
  [4, 12, 2, 3],
  [5, 14, 2, 2],
  [4, 16, 2, 2],
  [2, 18, 2, 2],
  [0, 20, 2, 3],
  [2, 22, 2, 2],
  [4, 24, 4, 3],
  [2, 28, 4, 2],
  [0, 32, 2, 2],
  [2, 34, 2, 2],
  [4, 36, 2, 3],
  [2, 38, 2, 2],
  [0, 40, 2, 2],
  [2, 42, 2, 2],
  [4, 44, 2, 3],
  [6, 46, 2, 2],
  [5, 48, 2, 2],
  [4, 50, 2, 2],
  [2, 52, 2, 3],
  [0, 54, 2, 2],
  [2, 56, 4, 3],
  [4, 60, 4, 3],
]);

/// 트랙 하나에 [pattern] 을 [section](타임라인 구간 차례)의 0마디부터 놓는다.
/// 레인은 안 되풀이하므로(사람이 클립을 놓은 것과 같다), 구간이 그 판보다
/// 길면 판 길이 간격으로 여러 번 이어 놓아 채운다.
void _lane(Project p, int section, int sectionBars, Track t, String? pattern) {
  if (pattern == null) return;
  final pb = p.barsOf(t.type, pattern);
  if (pb <= 0) return;
  for (var bar = 0; bar < sectionBars; bar += pb) {
    p.song.putLane(section, bar, t.id, pattern);
  }
}

/// 장르 하나를 **씬 없이** 타임라인 레인으로 손수 짠다.
/// [form] = (구간 이름, 마디 수, {트랙 → 그 구간에서 칠 판(없으면 null)}) 목록 —
/// 이 순서가 곧 타임라인 얼개다. 씬은 이름·마디수만 있는 빈 자리로만 쓴다.
void _buildTimeline(
  Project p,
  List<(String, int, Map<Track, String?>)> form,
) {
  p.scenes
    ..clear()
    ..addAll([for (final s in form) Scene(s.$1)]);
  p.song.sections
    ..clear()
    ..addAll([
      for (var i = 0; i < form.length; i++)
        // 씬이 빈 채라 `loopBarsOf` 는 늘 4(기본값)로 떨어진다 — 구간이
        // 원하는 마디 수(`form[i].$2`)가 되도록 판 수를 직접 맞춘다.
        // (이걸 1로 고정해 뒀다가 8마디짜리 벌스·코러스가 전부 4마디로
        // 잘려 나온 걸 실기기에서 보고 잡았다 — 곡 길이가 2:15 대신 1:26.)
        Section(i, reps: (form[i].$2 / p.loopBarsOf(i)).round().clamp(1, 32)),
    ]);
  p.song.lanes.clear();
  for (var i = 0; i < form.length; i++) {
    final (_, bars, parts) = form[i];
    parts.forEach((t, pattern) => _lane(p, i, bars, t, pattern));
  }
  p.launchScene(0);
}

/// 처음 켤 때 홈 화면 「샘플곡」 서랍에 넣을 것들 — 대표 장르 5개 + 연주곡 1개.
/// [Project.initial] (드럼·베이스·화음·멜로디 4트랙)에서 시작해 — 팝은 밴드
/// 편성이라 트랙 셋을 더 만든다 — 씬·구간·레인을 전부 새로 짠다.
List<SampleSong> buildSampleSongs() => [
  SampleSong('로파이 샘플', 'lofi', (p) {
    p.genre = 'lofi';
    final drum = p.tracks.firstWhere((t) => t.type == 'drum');
    final bass = p.tracks.firstWhere((t) => t.type == 'bass');
    final chord = p.tracks.firstWhere((t) => t.type == 'chord');
    final melody = p.tracks.firstWhere((t) => t.type == 'melody');
    drum.kit = genreDef('lofi').kit;
    // 장르 소리 성격(인서트·좌우·잔향)을 얹는다 — `genre` 필드만 직접 넣고
    // 씬 프리셋을 안 쓰는 샘플곡은 이걸 부르지 않으면 그 장르의 인서트가
    // 하나도 안 걸린다(사용자 요청, 2026-09-13: "플러그인 사용하고").
    p.applyGenreTone();
    p.userNote[_lofiLine.name] = _lofiLine;
    p.userNoteType[_lofiLine.name] = 'melody';
    _buildTimeline(p, [
      ('인트로', 4, {chord: 'Lofi Keys V', melody: _lofiLine.name}),
      ('벌스', 8, {drum: 'Lofi Verse', bass: 'Lofi Walk V', chord: 'Lofi Keys V'}),
      (
        '코러스',
        8,
        {drum: 'Lofi Chorus', bass: 'Lofi Walk C', chord: 'Lofi Keys C'},
      ),
      ('브레이크', 4, {drum: 'Lofi Break', chord: 'Lofi Keys C', melody: _lofiLine.name}),
      ('벌스', 8, {drum: 'Lofi Verse', bass: 'Lofi Walk V', chord: 'Lofi Keys V'}),
      (
        '코러스',
        8,
        {drum: 'Lofi Chorus', bass: 'Lofi Walk C', chord: 'Lofi Keys C'},
      ),
      ('아웃트로', 4, {chord: 'Lofi Keys V', melody: _lofiLine.name}),
    ]);
  }),
  SampleSong('하우스 샘플', 'house', (p) {
    p.genre = 'house';
    final drum = p.tracks.firstWhere((t) => t.type == 'drum');
    final bass = p.tracks.firstWhere((t) => t.type == 'bass');
    final chord = p.tracks.firstWhere((t) => t.type == 'chord');
    final melody = p.tracks.firstWhere((t) => t.type == 'melody');
    drum.kit = genreDef('house').kit;
    p.applyGenreTone();
    p.userNote[_houseLine.name] = _houseLine;
    p.userNoteType[_houseLine.name] = 'melody';
    _buildTimeline(p, [
      ('인트로', 4, {drum: 'House Verse', chord: 'House Stab V', melody: _houseLine.name}),
      (
        '벌스',
        8,
        {drum: 'House Verse', bass: 'House Off V', chord: 'House Stab V'},
      ),
      (
        '코러스',
        8,
        {drum: 'House Chorus', bass: 'House Off C', chord: 'House Stab C'},
      ),
      ('브레이크', 4, {drum: 'House Break', chord: 'House Stab C', melody: _houseLine.name}),
      (
        '벌스',
        8,
        {drum: 'House Verse', bass: 'House Off V', chord: 'House Stab V'},
      ),
      (
        '코러스',
        8,
        {drum: 'House Chorus', bass: 'House Off C', chord: 'House Stab C'},
      ),
      ('아웃트로', 4, {drum: 'House Verse', bass: 'House Off V', melody: _houseLine.name}),
    ]);
  }),
  SampleSong('힙합 샘플', 'hiphop', (p) {
    p.genre = 'hiphop';
    final drum = p.tracks.firstWhere((t) => t.type == 'drum');
    final bass = p.tracks.firstWhere((t) => t.type == 'bass');
    final chord = p.tracks.firstWhere((t) => t.type == 'chord');
    final melody = p.tracks.firstWhere((t) => t.type == 'melody');
    drum.kit = genreDef('hiphop').kit;
    p.applyGenreTone();
    p.userNote[_hiphopLine.name] = _hiphopLine;
    p.userNoteType[_hiphopLine.name] = 'melody';
    _buildTimeline(p, [
      ('인트로', 4, {chord: 'Dusty Keys V', melody: _hiphopLine.name}),
      ('벌스', 8, {drum: 'Boom Verse', bass: '808 Verse', chord: 'Dusty Keys V'}),
      (
        '코러스',
        8,
        {drum: 'Boom Chorus', bass: '808 Chorus', chord: 'Dusty Keys C'},
      ),
      ('브레이크', 4, {drum: 'Boom Break', bass: '808 Verse', melody: _hiphopLine.name}),
      ('벌스', 8, {drum: 'Boom Verse', bass: '808 Verse', chord: 'Dusty Keys V'}),
      (
        '코러스',
        8,
        {drum: 'Boom Chorus', bass: '808 Chorus', chord: 'Dusty Keys C'},
      ),
      ('아웃트로', 4, {chord: 'Dusty Keys V', melody: _hiphopLine.name}),
    ]);
  }),
  SampleSong('발라드 샘플', 'ballad', (p) {
    p.genre = 'ballad';
    final drum = p.tracks.firstWhere((t) => t.type == 'drum');
    final bass = p.tracks.firstWhere((t) => t.type == 'bass');
    final chord = p.tracks.firstWhere((t) => t.type == 'chord');
    final melody = p.tracks.firstWhere((t) => t.type == 'melody');
    drum.kit = genreDef('ballad').kit;
    p.applyGenreTone();
    p.userNote[_balladLine.name] = _balladLine;
    p.userNoteType[_balladLine.name] = 'melody';
    _buildTimeline(p, [
      ('인트로', 4, {drum: 'Ballad Intro', chord: 'Ballad Keys V', melody: _balladLine.name}),
      (
        '벌스',
        8,
        {drum: 'Ballad Verse', bass: 'Ballad Long V', chord: 'Ballad Keys V'},
      ),
      (
        '코러스',
        8,
        {drum: 'Ballad Chorus', bass: 'Ballad Long C', chord: 'Ballad Keys C'},
      ),
      ('브레이크', 4, {drum: 'Ballad Intro', chord: 'Ballad Keys C', melody: _balladLine.name}),
      (
        '벌스',
        8,
        {drum: 'Ballad Verse', bass: 'Ballad Long V', chord: 'Ballad Keys V'},
      ),
      (
        '코러스',
        8,
        {drum: 'Ballad Chorus', bass: 'Ballad Long C', chord: 'Ballad Keys C'},
      ),
      ('아웃트로', 4, {chord: 'Ballad Keys V', melody: _balladLine.name}),
    ]);
  }),
  SampleSong('팝 샘플', 'pop', (p) {
    p.genre = 'pop';
    final drum = p.tracks.firstWhere((t) => t.type == 'drum');
    final bass = p.tracks.firstWhere((t) => t.type == 'bass');
    final piano = p.tracks.firstWhere((t) => t.type == 'chord');
    final voc = p.tracks.firstWhere((t) => t.type == 'melody');
    piano.voice = 'piano';
    voc.voice = 'vocal';
    drum.voice = 'acoustic';
    bass.voice = 'fingerbass';
    drum.kit = genreDef('pop').kit;
    // 팝은 트랙이 7개다(밴드 편성) — 여기서 나머지 셋을 더 만든다.
    p.addTrack('chord', voice: 'guitar');
    p.addTrack('melody', voice: 'pluck'); // 아르페지오 — 노래가 아니라 반주
    p.addTrack('chord', voice: 'strings');
    final gtr = p.tracks.firstWhere((t) => t.voice == 'guitar');
    final plk = p.tracks.firstWhere((t) => t.voice == 'pluck');
    final str = p.tracks.firstWhere((t) => t.voice == 'strings');
    p.applyGenreTone();
    p.userNote[_popLine.name] = _popLine;
    p.userNoteType[_popLine.name] = 'melody';
    _buildTimeline(p, [
      (
        '인트로',
        8,
        {drum: 'Pop Intro', piano: 'Pop Keys V', plk: 'Pop Arp', voc: _popLine.name},
      ),
      (
        '벌스',
        16,
        {drum: 'Pop Verse', bass: 'Pop Bass V', piano: 'Pop Keys V'},
      ),
      (
        '프리',
        8,
        {
          drum: 'Pop Pre',
          bass: 'Pop Bass P',
          piano: 'Pop Keys P',
          gtr: 'Pop Gtr P',
          plk: 'Pop Arp P',
        },
      ),
      (
        '코러스',
        16,
        {
          drum: 'Pop Chorus',
          bass: 'Pop Bass C',
          piano: 'Pop Keys C',
          gtr: 'Pop Gtr C',
          plk: 'Pop Arp C',
          str: 'Pop Str C',
        },
      ),
      (
        '벌스',
        16,
        {drum: 'Pop Verse', bass: 'Pop Bass V', piano: 'Pop Keys V'},
      ),
      (
        '코러스',
        16,
        {
          drum: 'Pop Chorus',
          bass: 'Pop Bass C',
          piano: 'Pop Keys C',
          gtr: 'Pop Gtr C',
          plk: 'Pop Arp C',
          str: 'Pop Str C',
        },
      ),
      (
        '브리지',
        8,
        {bass: 'Pop Bass B', piano: 'Pop Keys B', str: 'Pop Str B'},
      ),
      (
        '아웃트로',
        8,
        {drum: 'Pop Intro', piano: 'Pop Keys V', plk: 'Pop Arp', voc: _popLine.name},
      ),
    ]);
  }),
  SampleSong('연주곡 샘플', 'citypop', (p) {
    p.genre = 'citypop';
    final drum = p.tracks.firstWhere((t) => t.type == 'drum');
    final bass = p.tracks.firstWhere((t) => t.type == 'bass');
    final chord = p.tracks.firstWhere((t) => t.type == 'chord');
    // 연주곡 — 멜로디 트랙은 그대로 두되(있어도 된다) 어디에도 안 놓는다.
    drum.kit = genreDef('citypop').kit;
    p.applyGenreTone();
    _buildTimeline(p, [
      ('인트로', 4, {chord: 'City Maj V'}),
      ('벌스', 8, {drum: 'City Verse', bass: 'City Slap V', chord: 'City Maj V'}),
      (
        '코러스',
        8,
        {drum: 'City Chorus', bass: 'City Slap C', chord: 'City Maj C'},
      ),
      ('브레이크', 4, {drum: 'City Break', chord: 'City Maj C'}),
      ('벌스', 8, {drum: 'City Verse', bass: 'City Slap V', chord: 'City Maj V'}),
      (
        '코러스',
        8,
        {drum: 'City Chorus', bass: 'City Slap C', chord: 'City Maj C'},
      ),
      ('아웃트로', 4, {chord: 'City Maj V'}),
    ]);
  }),
];

/// [Store] 가 곡 파일에 쓰는 것과 같은 모양의 스냅샷 — 빠르기·조·라이브·마스터
/// 몫까지 채워서, 이 샘플곡도 저장했다 연 곡과 한 톨도 다르지 않게 돈다.
Map<String, dynamic> sampleSnapshot(Project p) {
  final g = genreDef(p.genre);
  final sg = songGenreOf(p.genre);
  final preset = masterPresetForGenre(p.genre);
  return {
    ...p.toJson(),
    'bpm': sg.$3,
    'root': 0,
    'mode': sg.$5,
    'live': {
      'voice': g.liveVoice,
      'vol': 1.0,
      'rev': 0.18,
      'auto': true,
      'fx': [],
    },
    'masterVol': 1.0,
    // 장르별 자동 마스터링 — 이 샘플곡도 저장했다 연 곡과 같은 마스터링을 얹는다.
    'masterFx': [
      for (final (type, params) in preset.chain)
        {'type': type, 'on': true, 'p': params},
    ],
    'masterFxAuto': true,
  };
}
