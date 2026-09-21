// 저장·불러오기 + **곡 여러 개**.
//
// 5단계 8/N 은 `project.json` 하나였다 — 새 곡을 만들면 앞 곡이 사라진다.
// 만들다 만 걸 못 남기면 사람은 두 번째 곡을 시작하지 않는다.
//
// ── 파일 구조 ──
//   documents/
//     index.json        {current: "s3", songs:[{id,name,genre,updated}]}
//     songs/s1.json     곡 하나 = 파일 하나
//
// 목록(index)을 따로 두는 이유: 곡이 20개여도 **목록 화면은 index 하나만 읽으면 된다.**
// 곡 파일을 전부 열어서 이름을 꺼내는 방식은 곡이 늘수록 느려진다.
//
// ── 버튼이 아니라 자동 저장 ──
// 무언가 바뀌면 0.8초 조용해질 때 지금 곡 파일에 쓴다(슬라이더 끄는 동안 초당 60번
// 쓰지 않으려고 모은다). 앱을 켜면 마지막에 열었던 곡을 되살린다.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'fx.dart' show masterPresetForGenre;
import 'pattern_names.dart' show patternShort;
import 'presets.dart';
import 'project.dart';
import 'song_samples.dart';
import 'synth.dart' show Human;
import 'theory.dart';
import 'sequencer.dart';

/// 목록에 보이는 한 줄 — 곡 파일을 안 열고도 그릴 수 있는 만큼만.
/// 지운 곡을 **되돌릴 수 있게** 통째로 들고 있는 것.
/// 파일 내용(raw)·목록 항목(meta)·목록에서의 자리(at)·열려 있었는지(wasCurrent).
class RemovedSong {
  final String raw;
  final SongMeta meta;
  final int at;
  final bool wasCurrent;
  const RemovedSong({
    required this.raw,
    required this.meta,
    required this.at,
    required this.wasCurrent,
  });
}

class SongMeta {
  final String id;
  String name;
  String genre;
  DateTime updated;

  /// 곡 길이(초). 목록에 보여 주려고 **저장할 때 적어 둔다** — 목록을 그릴 때
  /// 곡마다 파일을 열어 계산하면 곡이 늘수록 목록이 느려진다(그러려고 목록을
  /// 따로 둔 것이다). 0 이면 아직 모르는 것(옛 파일).
  double sec;

  /// **카드 미리보기용** — 마지막 저장 때 지금 씬에서 켜져 있던 악기
  /// (드럼·베이스·코드·멜로디 순, `kPreviewTrackTypes` 와 같은 차례).
  /// null 이면 아직 못 구했다(옛 곡 — `_fillMissingLengths` 가 한 번 채운다).
  List<bool>? sceneActive;

  /// **카드 미리보기 툴팁용** — `sceneActive` 와 같은 차례로, 그 악기에
  /// 실제로 실려 있던 패턴의 **보여 주는 이름**(한국어, `patternShort`).
  /// 꺼져 있던 자리는 빈 문자열. 사용자 요청(2026-09-13) — "미리보기가
  /// 색만 보이고 무슨 소리인지는 열어야 안다"는 점을 길게 눌러 바로 알게.
  List<String>? scenePatterns;

  /// **카드 미리보기용** — 마지막 저장 때 타임라인 구간 이름들(순서대로).
  /// null 이면 아직 못 구했다.
  List<String>? timelineScenes;

  /// **샘플곡**인가 — 홈 화면 맨 위 「최근 프로젝트」 격자가 아니라 아래쪽
  /// 「샘플곡」 서랍에 뜬다. 열면 진짜 프로젝트라 직접 만지고 고칠 수 있다
  /// (구경 전용이 아니다) — 다만 원본이라 고치면 그 자리에서 바뀐다.
  bool sample;

  SongMeta({
    required this.id,
    required this.name,
    required this.genre,
    required this.updated,
    this.sec = 0,
    this.sceneActive,
    this.scenePatterns,
    this.timelineScenes,
    this.sample = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'genre': genre,
    'updated': updated.toIso8601String(),
    if (sec > 0) 'sec': sec,
    if (sceneActive != null) 'sa': sceneActive,
    if (scenePatterns != null) 'sp': scenePatterns,
    if (timelineScenes != null) 'tl': timelineScenes,
    if (sample) 'sample': true,
  };

  factory SongMeta.fromJson(Map<String, dynamic> j) => SongMeta(
    id: j['id'] as String,
    name: j['name'] as String? ?? '새 곡',
    genre: j['genre'] as String? ?? 'lofi',
    updated: DateTime.tryParse(j['updated'] as String? ?? '') ?? DateTime(2020),
    sec: (j['sec'] as num?)?.toDouble() ?? 0,
    sceneActive: (j['sa'] as List?)?.map((e) => e as bool).toList(),
    scenePatterns: (j['sp'] as List?)?.map((e) => e as String).toList(),
    timelineScenes: (j['tl'] as List?)?.map((e) => e as String).toList(),
    sample: j['sample'] as bool? ?? false,
  );
}

/// 카드 미리보기의 악기 차례 — `SongMeta.sceneActive` 의 인덱스와 같다.
/// 씬 화면 악기 줄 색(드럼 초록·베이스 파랑·코드 보라·멜로디 호박)과 맞춘다.
const List<String> kPreviewTrackTypes = ['drum', 'bass', 'chord', 'melody'];

class Store extends ChangeNotifier {
  final Project project;
  final Transport transport;
  final LiveChannel live;
  final MasterChannel master;

  /// 시험에서 임시 폴더를 넣으려고 열어 둔 구멍. 앱에서는 안 쓴다.
  final Directory? overrideDir;

  /// 처음 켤 때 「샘플곡」 서랍을 심을 것인가. **진짜 앱(`main.dart`)만 켠다** —
  /// 시험은 다들 "빈 저장소에서 시작하면 곡이 하나(또는 0개)"를 전제로 짜여
  /// 있어서, 여기 기본값을 켜 두면 시험 수십 개가 엉뚱한 개수를 본다.
  final bool seedSamples;

  Store({
    required this.project,
    required this.transport,
    required this.live,
    required this.master,
    this.overrideDir,
    this.seedSamples = false,
  });

  final List<SongMeta> songs = [];
  String? currentId;

  /// 첫 실행 안내를 본 적이 있는가. `index.json` 에 같이 적는다
  /// (곡과 달리 값 하나뿐이라 파일을 따로 두지 않는다).
  bool guideSeen = false;

  /// 샘플곡을 이미 심어 놨는가 — **한 번만** 한다. 안 그러면 열 때마다
  /// 「샘플곡」 서랍이 계속 늘어난다. `index.json` 에 같이 적는다.
  bool _samplesSeeded = false;

  /// **간단히 보기** — 화면에 내놓는 것을 줄인다 (Phase 2).
  ///
  /// 기능을 **없애는 게 아니라 진입점을 감춘다.** 믹서·편집기 화면은 그대로 있고,
  /// 버튼만 안 보인다. 처음 쓰는 사람에게 믹서·EQ·인서트를 한꺼번에 보여 주면
  /// 그건 도움이 아니라 벽이다.
  ///
  /// 기본값은 **처음 쓰는 사람만** 켠다 — 이미 쓰던 사람에게서 갑자기 기능을
  /// 뺏으면 그건 개선이 아니라 고장이다. `guideSeen` 으로 가른다.
  /// 기본값이 **true 인 이유**: 파일이 아예 없는 첫 설치가 곧 '처음 쓰는 사람'이다.
  /// (파일이 있으면 아래 `start()` 에서 `guideSeen` 을 보고 다시 정한다 —
  ///  쓰던 사람에게서 기능을 뺏지 않으려고.)
  /// 폰에 새로 깔아 보고서야 알았다 — 파일이 없으면 이 줄이 그대로 남는다.
  bool simpleMode = true;

  /// 곡 화면을 **어떻게 볼 것인가** — `'list'`(구간 목록) 또는 `'timeline'`.
  ///
  /// 자료는 구간표 하나뿐이고 이건 **보는 방식**이라 곡이 아니라 앱에 남긴다
  /// (곡마다 다르게 두면 곡을 옮길 때마다 화면이 바뀌어 더 헷갈린다).
  String songMode = 'list';

  /// 화면 방향 — `'auto'` · `'portrait'` · `'landscape'`.
  ///
  /// 눕혀 놓고 라이브를 치거나 쇼를 틀어 둘 때 화면이 제멋대로 돌면 그것만으로
  /// 연주가 끊긴다. 옛 웹 판에는 있었는데 네이티브 판으로 옮기며 빠졌다.
  String orient = 'auto';

  /// 소리 품질 — `true` 면 배음·유니즌·디테일을 다 쓴다(기본).
  ///
  /// 엔진에는 `setQuality` 가 처음부터 있었는데 **부르는 데가 한 곳도 없었다.**
  /// 무거운 곡에서 소리가 끊기면 사용자가 할 수 있는 일이 하나도 없었다는 뜻이다.
  bool highQuality = true;

  /// **프로 모드** — 편집기에서 반음 줄로 찍을 수 있게 한다.
  ///
  /// 도수 줄은 조에 맞는 음만 낼 수 있다. 블루 노트도, 지나가는 반음도 못 찍는다.
  /// 다만 대부분은 그 제약 덕에 「아무거나 눌러도 어울린다」를 얻는다 —
  /// 그래서 **기본은 꺼짐**이고, 켠 사람에게만 손잡이가 보인다(§15).
  bool pro = false;

  /// **초보 모드** — 라이브 반음 건반에서 지금 조에 안 맞는 건반을 흐리게
  /// 하고 눌러도 소리가 안 나게 한다. 기본은 켜짐(다이아토닉 패드와 같은
  /// 「틀린 음이 안 나온다」 약속을 반음 건반에서도 지킨다) — 끄면 12음
  /// 전부 소리가 난다.
  bool beginner = true;

  /// **카드 미리보기 모드** — 첫 화면 프로젝트 카드가 씬·타임라인·쇼 중
  /// 무엇을 작은 그림으로 그릴지. 카드마다 따로가 아니라 **앱 전체 하나**
  /// (설정 화면). 기본은 씬 — "이 프로젝트에 지금 뭐가 들어있나"가 가장
  /// 먼저 궁금한 것이라서.
  String previewMode = 'scene';

  /// **연주 흔들림** — 0 끔 · 1 자연스럽게(기본) · 2 많이.
  ///
  /// 음정·세기·**타이밍**을 매번 조금씩 다르게 한다. 여태 타이밍은 안 흔들렸다
  /// (`Human.t` 가 선언만 되고 죽어 있었다) — 그래서 박이 자로 잰 듯 딱 맞았다.
  /// 사람이 친 것과 기계가 친 것의 차이는 대개 거기서 난다.
  ///
  /// 끌 수 있어야 한다 — 딱 맞는 쪽을 좋아하는 사람도 있고, 시험은 늘 0 을 쓴다.
  int human = 1;

  /// 첫 화면의 「샘플곡」 서랍을 접어 뒀는가 — 기본은 **펼침**(처음 보는
  /// 사람은 샘플이 있는 줄 알아야 한다). 한 번 접으면 다음에 열어도 그대로
  /// 접혀 있다 — 매번 다시 접어야 하면 접은 게 아니다.
  bool samplesCollapsed = false;

  Future<void> setOrient(String v) async {
    final m = (v == 'portrait' || v == 'landscape') ? v : 'auto';
    if (orient == m) return;
    orient = m;
    await _writeIndex();
    notifyListeners();
  }

  Future<void> setHuman(int v) async {
    final lv = v.clamp(0, 2);
    if (human == lv) return;
    human = lv;
    Human.setLevel(lv);
    await _writeIndex();
    notifyListeners();
  }

  Future<void> setHighQuality(bool v) async {
    if (highQuality == v) return;
    highQuality = v;
    await _writeIndex();
    notifyListeners();
  }

  Future<void> setPro(bool v) async {
    if (pro == v) return;
    pro = v;
    await _writeIndex();
    notifyListeners();
  }

  Future<void> setBeginner(bool v) async {
    if (beginner == v) return;
    beginner = v;
    await _writeIndex();
    notifyListeners();
  }

  Future<void> setPreviewMode(String v) async {
    final m = (v == 'timeline' || v == 'show') ? v : 'scene';
    if (previewMode == m) return;
    previewMode = m;
    await _writeIndex();
    notifyListeners();
  }

  Future<void> setSongMode(String v) async {
    final m = v == 'timeline' ? 'timeline' : 'list';
    if (songMode == m) return;
    songMode = m;
    await _writeIndex();
    notifyListeners();
  }

  Future<void> setSimpleMode(bool v) async {
    if (simpleMode == v) return;
    simpleMode = v;
    await _writeIndex();
    notifyListeners();
  }

  Future<void> setSamplesCollapsed(bool v) async {
    if (samplesCollapsed == v) return;
    samplesCollapsed = v;
    await _writeIndex();
    notifyListeners();
  }

  /// 안내를 봤다고 적어 둔다 — 다시 켰을 때 또 뜨면 성가시다.
  Future<void> markGuideSeen() async {
    if (guideSeen) return;
    guideSeen = true;
    await _writeIndex();
    notifyListeners();
  }

  Directory? _dir;
  Timer? _debounce;
  bool _loading = false;

  Future<Directory> _root() async =>
      _dir ??= overrideDir ?? await getApplicationDocumentsDirectory();

  Future<File> _indexFile() async => File('${(await _root()).path}/index.json');

  // ── 저장이 안 될 때 ──
  //
  // 여태 `saveNow` 는 실패를 **삼키고 로그만 찍었다.** 저장 공간이 꽉 찼거나
  // 권한이 사라지면 그때부터 아무것도 안 남는데, 사용자는 **앱을 껐다 켠 뒤에야**
  // 안다. 그때는 이미 늦었다. 만든 걸 잃는 것보다 나쁜 건 없다.
  //
  // 화면이 이걸 보고 알려 준다. 다시 성공하면 스스로 0 으로 돌아간다.
  int saveFails = 0;
  String? lastSaveError;

  /// 지금 저장 한 판에서 **한 번이라도** 실패했나.
  ///
  /// 한 판은 파일을 둘 쓴다 — 곡 파일과 목록(`index.json`). 예전엔 `_write` 가
  /// 성공할 때마다 `saveFails` 를 0 으로 되돌려서, **곡 저장이 실패해도 뒤이은
  /// 목록 저장이 성공하면 경고가 지워졌다.** 하필 제일 중요한 실패(곡이 안 남았다)가
  /// 안 보이고, 덜 중요한 실패(목록)만 보였다. 판이 끝날 때 한 번만 셈한다.
  bool _passFailed = false;

  /// 파일에 쓴다 — **실패를 삼키지 않고, 반쯤 쓰다 마는 일도 없다.**
  ///
  /// ── 왜 곧장 안 쓰나 ──
  /// `writeAsString` 은 **먼저 파일을 비우고** 새 내용을 채운다. 그 사이에 앱이
  /// 죽거나(안드로이드는 메모리가 모자라면 뒤에 있는 앱을 그냥 죽인다) 사용자가
  /// 최근앱에서 밀어 버리면 **반만 쓰인 JSON** 이 남는다. 그 파일은 못 읽는다 —
  /// 곡이 통째로 날아간다.
  ///
  /// 이 앱은 만지는 족족 저장한다(`_debounce`). 그러니 「쓰는 중」인 시간이 길고,
  /// 하필 그때 죽을 확률도 그만큼 높다.
  ///
  /// ── 그래서 옆에 쓰고 갈아 끼운다 ──
  /// 임시 파일에 다 쓰고 나서 `rename` 으로 제자리에 넣는다. 같은 저장소 안의
  /// rename 은 **한 번에 일어난다**(중간이 없다) — 죽어도 남는 건 옛 파일 아니면
  /// 새 파일이고, 둘 다 온전하다.
  ///
  /// `bad_file_test` 가 「망가진 파일이 앱을 못 죽인다」를 지키고, 여기는 애초에
  /// **망가진 파일이 생기지 않게** 한다. 둘 다 필요하다.
  Future<bool> _write(File f, String data) async {
    final tmp = File('${f.path}.tmp');
    try {
      await tmp.writeAsString(data, flush: true);
      await tmp.rename(f.path);
      return true;
    } catch (e) {
      // 임시 파일이 남아 있으면 치운다 — 다음 저장이 또 이 이름을 쓴다.
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {
        // 치우는 것까지 실패해도 저장 실패를 알리는 게 먼저다
      }
      _passFailed = true;
      lastSaveError = '$e';
      debugPrint('저장 실패: $e');
      return false;
    }
  }

  /// 저장 한 판이 끝났다 — 그때 **한 번만** 세고 알린다.
  /// 모든 저장 경로가 마지막에 `_writeIndex()` 를 부르므로 거기서 부른다.
  void _endPass() {
    if (_passFailed) {
      _passFailed = false;
      saveFails++;
      debugPrint('저장 실패($saveFails번째): $lastSaveError');
      notifyListeners();
    } else if (saveFails != 0) {
      saveFails = 0;
      lastSaveError = null;
      notifyListeners();
    }
  }

  Future<File> _songFile(String id) async {
    final d = Directory('${(await _root()).path}/songs');
    if (!await d.exists()) await d.create(recursive: true);
    return File('${d.path}/$id.json');
  }

  SongMeta? get current {
    for (final s in songs) {
      if (s.id == currentId) return s;
    }
    return null;
  }

  // ── 시작 ──

  /// 앱 시작 때 한 번. 목록을 읽고 마지막에 열었던 곡을 되살린다.
  /// 저장된 게 하나도 없으면 지금 화면에 있는 기본 프로젝트를 첫 곡으로 만든다.
  Future<void> start() async {
    try {
      await _migrateOldSingleFile();
      final f = await _indexFile();
      if (await f.exists()) {
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        songs
          ..clear()
          ..addAll([
            for (final s in (j['songs'] as List))
              SongMeta.fromJson(Map<String, dynamic>.from(s as Map)),
          ]);
        currentId = j['current'] as String?;
        guideSeen = j['guideSeen'] as bool? ?? false;
        // 없으면(옛 파일) 처음 쓰는 사람만 간단히 — 쓰던 사람은 그대로 전부 보인다
        simpleMode = j['simple'] as bool? ?? !guideSeen;
        songMode = j['songMode'] == 'timeline' ? 'timeline' : 'list';
        final o = j['orient'] as String?;
        orient = (o == 'portrait' || o == 'landscape') ? o! : 'auto';
        highQuality = j['hq'] as bool? ?? true;
        pro = j['pro'] as bool? ?? false;
        beginner = j['beginner'] as bool? ?? true;
        final pm = j['previewMode'] as String?;
        previewMode = (pm == 'timeline' || pm == 'show') ? pm! : 'scene';
        human = (j['human'] as int? ?? 1).clamp(0, 2);
        samplesCollapsed = j['samplesCollapsed'] as bool? ?? false;
        Human.setLevel(human); // 저장해 둔 값을 켤 때 바로 건다
        _samplesSeeded = j['samplesSeeded'] as bool? ?? false;
      }
      if (seedSamples && !_samplesSeeded) {
        // **한 번만** — 있던 곡을 전부 새 것(샘플곡 서랍 + 빈 테스트 곡)으로
        // 간다(사용자 요청, 2026-09-12). 그다음부터는 이 분기를 다시 안 탄다.
        await _seedSamples();
      } else if (songs.isEmpty) {
        await _createFrom(project, name: project.name);
      } else {
        await open(currentId ?? songs.first.id, saveCurrent: false);
        await _fillMissingLengths();
      }
    } catch (e) {
      debugPrint('시작 실패: $e'); // 저장이 깨졌다고 앱이 죽으면 안 된다
    }
    notifyListeners();
  }

  /// **한 번만** — 있던 곡을 전부 지우고 「샘플곡」 서랍(`song_samples.dart`)과
  /// 빈 테스트 곡 하나로 다시 시작한다(사용자 요청, 2026-09-12). 되돌릴 수
  /// 없는 손짓이라 [start] 에서 `_samplesSeeded` 가 없을 때 딱 한 번만 부른다.
  Future<void> _seedSamples() async {
    for (final s in songs) {
      final f = await _songFile(s.id);
      if (await f.exists()) await f.delete();
    }
    songs.clear();

    for (final def in buildSampleSongs()) {
      final p = Project.initial();
      def.customize(p);
      // **곡 파일 안의 이름표도 맞춰 둔다** — 안 그러면 `Project.initial()`
      // 의 기본값('새 곡')이 그대로 남아 있다가, 열어서 한 번만 저장돼도
      // (`saveNow` 가 `meta.name = project.name` 으로 되돌린다) 목록 이름이
      // "새 곡"으로 덮어써진다(실기기에서 직접 열어 보고서야 잡았다).
      p.name = def.name;
      final id = _newId();
      songs.add(
        SongMeta(
          id: id,
          name: def.name,
          genre: p.genre,
          updated: DateTime.now(),
          sceneActive: sceneActiveOf(p),
          scenePatterns: scenePatternsOf(p),
          timelineScenes: timelineScenesOf(p),
          sample: true,
        ),
      );
      await _write(await _songFile(id), jsonEncode(sampleSnapshot(p)));
    }

    // 테스트용 새 프로젝트 — 사용자가 바로 만지기 시작할 빈 곡.
    project.reset(newName: '테스트');
    _syncTransportToGenre();
    _resetChannels();
    final meta = await _createFrom(project, name: project.name);
    currentId = meta.id;

    _samplesSeeded = true;
    await _writeIndex();
  }

  /// 길이 칸이 비어 있는 곡을 한 번만 채운다 (5단계 15/N 전에 저장된 곡들).
  ///
  /// 목록은 곡 파일을 안 열려고 만든 것이지만, **한 번은 열어야** 옛 곡에 길이가 붙는다.
  /// 안 하면 예전부터 쓰던 사람은 길이가 영영 안 보인다(고쳐서 저장할 때까지).
  /// 딱 한 번이고, 실패해도 그냥 넘어간다(길이는 없어도 되는 정보다).
  Future<void> _fillMissingLengths() async {
    final todo = [
      for (final s in songs)
        if (s.sec <= 0 ||
            s.sceneActive == null ||
            s.scenePatterns == null ||
            s.timelineScenes == null)
          s,
    ];
    if (todo.isEmpty) return;
    final scratch = Project.initial();
    for (final m in todo) {
      try {
        final f = await _songFile(m.id);
        if (!await f.exists()) continue;
        final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        scratch.loadJson(j);
        if (m.sec <= 0) m.sec = SceneSequencer.songSeconds(scratch, transport);
        m.sceneActive ??= sceneActiveOf(scratch);
        m.scenePatterns ??= scenePatternsOf(scratch);
        m.timelineScenes ??= timelineScenesOf(scratch);
      } catch (e) {
        debugPrint('길이 채우기 실패(${m.id}): $e');
      }
    }
    await _writeIndex();
  }

  /// 5단계 8/N 이 쓰던 `project.json` 하나짜리를 첫 곡으로 옮긴다.
  /// **먼저 만든 것을 잃지 않게** — 업데이트 한 번에 곡이 사라지면 최악이다.
  Future<void> _migrateOldSingleFile() async {
    final old = File('${(await _root()).path}/project.json');
    if (!await old.exists()) return;
    if (await (await _indexFile()).exists()) return;
    final raw = await old.readAsString();
    final j = jsonDecode(raw) as Map<String, dynamic>;
    // 곡 하나 시절 파일에는 이름 칸이 없다. **파일 안에 이름을 박아 둔다** —
    // 목록에만 넣어 두면 첫 자동 저장 때 파일에서 읽은 기본 이름('새 곡')으로
    // 덮어써진다(폰에서 그렇게 나왔다).
    final name = (j['name'] as String?) ?? '내 곡';
    j['name'] = name;
    final id = _newId();
    await _write(await _songFile(id), jsonEncode(j));
    songs.add(
      SongMeta(
        id: id,
        name: name,
        genre: j['genre'] as String? ?? 'lofi',
        updated: DateTime.now(),
      ),
    );
    currentId = id;
    await _writeIndex();
    await old.rename('${old.path}.bak'); // 지우지 않는다
  }

  // ── 곡 다루기 ──

  String _newId() =>
      's${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  Future<void> _writeIndex() async {
    final f = await _indexFile();
    await _write(
      f,
      jsonEncode({
        'current': currentId,
        'guideSeen': guideSeen,
        'simple': simpleMode,
        'songMode': songMode,
        'orient': orient,
        'hq': highQuality,
        'pro': pro,
        'beginner': beginner,
        'previewMode': previewMode,
        'human': human,
        'samplesCollapsed': samplesCollapsed,
        'samplesSeeded': _samplesSeeded,
        'songs': [for (final s in songs) s.toJson()],
      }),
    );
    _endPass();
  }

  Map<String, dynamic> _snapshot() => {
    ...project.toJson(),
    'bpm': transport.bpm,
    'root': transport.root,
    'mode': transport.mode,
    // `auto` 를 같이 남긴다 — 이게 없으면 불러올 때마다 「사용자가 골랐다」로
    // 읽혀서 장르별 라이브 기본 음색이 죽는다.
    'live': {
      'voice': live.voice,
      'vol': live.vol,
      'rev': live.rev,
      'auto': live.voiceAuto,
      // 라이브 인서트도 곡마다 따로 남는다(마스터와 같은 자리)
      'fx': [for (final f in live.chain) f.toJson()],
    },
    'masterVol': master.vol,
    // 마스터 인서트(마스터링 플러그인) — 곡마다 따로 남는다
    'masterFx': [for (final f in master.chain) f.toJson()],
    // 지금 마스터 인서트가 장르 자동인지(§장르별 자동 마스터링) — 없으면
    // (옛 파일) 사용자가 꽂은 것으로 본다(트랙 fxAuto 와 같은 규칙).
    if (master.fxAuto) 'masterFxAuto': true,
  };

  Future<SongMeta> _createFrom(Project p, {required String name}) async {
    final id = _newId();
    project.name = name;
    final meta = SongMeta(
      id: id,
      name: name,
      genre: p.genre,
      updated: DateTime.now(),
      sceneActive: sceneActiveOf(p),
      scenePatterns: scenePatternsOf(p),
      timelineScenes: timelineScenesOf(p),
    );
    songs.insert(0, meta);
    currentId = id;
    await _write(await _songFile(id), jsonEncode(_snapshot()));
    await _writeIndex();
    return meta;
  }

  /// 곡을 연다. **열기 전에 지금 곡을 먼저 저장한다** — 안 그러면 방금 만진 게 날아간다.
  ///
  /// [saveCurrent] 는 앱 시작 때만 false 다. 시작 시점의 화면 속 프로젝트는 아직
  /// 아무것도 아닌 **빈 기본값**인데, 그걸 저장해 버리면 방금 되살리려던 곡 파일을
  /// 덮어쓴다(시험 5번에서 잡았다 — 앱 업데이트 한 번에 곡이 날아갈 뻔했다).
  Future<void> open(String id, {bool saveCurrent = true}) async {
    if (saveCurrent) await saveNow();
    final f = await _songFile(id);
    if (!await f.exists()) return;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      _loading = true;
      project.loadJson(j);
      // 없는 값은 **그 곡의 스타일 기본값**으로 떨어뜨린다 — 지금 열려 있던 곡의
      // 값을 물려받으면 안 된다. 특히 조성: 장조 곡(팝·가스펠)을 단조로 열면
      // 코드가 전부 딴 것이 된다(소리는 나므로 오류로는 안 잡힌다).
      final gd = songGenreOf(project.genre);
      // **파일이 앱을 못 죽이게 한다.** 값이 이상하면 그 장르의 기본값으로 돌린다 —
      // 조(mode)가 모르는 값이면 소리 내는 쪽이 `kScale[mode]!` 에서 터진다.
      // 그 곡이 마지막에 열던 곡이면 **앱 자체가 안 뜬다.**
      final rawMode = j['mode'] as String?;
      final rawBpm = (j['bpm'] as num?)?.toDouble();
      transport
        ..bpm =
            (rawBpm != null && rawBpm.isFinite && rawBpm >= 20 && rawBpm <= 300)
            ? rawBpm
            : gd.$3
        ..root = (j['root'] as int? ?? transport.root) % 12
        ..mode = kScale.containsKey(rawMode) ? rawMode! : gd.$5;
      final l = j['live'] as Map?;
      if (l != null) {
        // **setter 를 쓰면 안 된다** — `voice=` 는 「사용자가 골랐다」는 뜻이라
        // 불러오는 것만으로 voiceAuto 가 꺼진다(그래서 기본 음색이 죽어 있었다).
        // 옛 파일은 `auto` 가 없다 → **true 로 본다.** 여태 이 기능이 죽어 있었으니
        // 「고른 적 없다」가 맞을 확률이 높고, 한 번 고르면 그때 다시 꺼진다.
        live.restore(
          voice: l['voice'] as String?,
          vol: (l['vol'] as num?)?.toDouble(),
          rev: (l['rev'] as num?)?.toDouble(),
          auto: l['auto'] as bool? ?? true,
        );
      }
      // **없으면 비운다** — 앞 곡에 꽂아 둔 것이 남으면 안 꽂은 곡에도 걸린다.
      // (마스터가 겪은 그 자리다 — 그래서 `l == null` 일 때도 지나가야 한다)
      live.chain
        ..clear()
        ..addAll([
          for (final raw in ((l?['fx'] as List?) ?? const []))
            FxSlot.fromJson(Map<String, dynamic>.from(raw as Map)),
        ]);
      master.vol = (j['masterVol'] as num?)?.toDouble() ?? master.vol;
      master.chain
        ..clear()
        ..addAll([
          for (final raw in (j['masterFx'] as List? ?? const []))
            FxSlot.fromJson(Map<String, dynamic>.from(raw as Map)),
        ]);
      master.fxAuto = j['masterFxAuto'] as bool? ?? false;
      _loading = false;
      currentId = id;
      await _writeIndex();
      notifyListeners();
    } catch (e) {
      _loading = false;
      debugPrint('곡 열기 실패: $e');
    }
  }

  /// 새 곡 — 기본 구성(로파이 송폼)으로 시작한다.
  /// `Project.reset()` 은 **스타일만** 갈아입힌다. 빠르기·조는 [Transport] 가 들고
  /// 있어서 여기서 안 맞추면 **앞 곡의 조가 새 곡에 그대로 남는다** — 팝(장조)에서
  /// 새 곡을 만들면 로파이가 장조로 시작한다. 소리는 나므로 오류로는 안 잡힌다.
  ///
  /// 곡을 **열 때**는 [open] 이 파일의 값을 되살리니 여기와 겹치지 않는다.
  void _syncTransportToGenre() {
    final gd = songGenreOf(project.genre);
    transport
      ..bpm = gd.$3
      ..mode = gd.$5;
  }

  /// **새 곡은 깨끗한 채널로 시작한다.**
  ///
  /// `Project.reset()` 은 씬·트랙·패턴만 되돌린다. 마스터와 라이브는 [Store] 가
  /// 들고 있어서(곡 파일에 같이 저장되는 값이다) 여기서 안 비우면 **앞 곡에 꽂아
  /// 둔 리미터·딜레이가 새 곡에 그대로 걸린 채** 저장된다. 사용자는 아무것도 안
  /// 꽂았는데 소리가 다르다 — 어디서 왔는지 찾을 길이 없는 종류다.
  ///
  /// 값은 `MasterChannel()`·`LiveChannel()` 을 새로 만들었을 때와 같게 둔다.
  void _resetChannels() {
    master.chain.clear();
    master.vol = 1.0;
    // 장르별 자동 마스터링 — 새 곡이니 그 장르가 정하는 마스터링부터 얹는다.
    master.fxAuto = true;
    master.applyGenrePreset(masterPresetForGenre(project.genre));
    live.chain.clear();
    // 음색은 **장르가 다시 정해 주게** 되돌린다(`voiceAuto`) — 새 곡이니 맞다.
    live.restore(vol: 1.0, rev: 0.18, auto: true);
  }

  Future<void> newSong({String? name}) async {
    await saveNow();
    project.reset(newName: name ?? '새 곡 ${songs.length + 1}');
    _syncTransportToGenre();
    _resetChannels();
    await _createFrom(project, name: project.name);
    notifyListeners();
  }

  /// 지금 곡을 그대로 복제한다(만든 걸 망칠까 봐 못 만지는 게 제일 아깝다).
  Future<void> duplicate(String id) async {
    if (id == currentId) await saveNow();
    final src = await _songFile(id);
    if (!await src.exists()) return;
    final raw = await src.readAsString();
    final meta = songs.firstWhere((s) => s.id == id);
    final nid = _newId();
    await _write(await _songFile(nid), raw);
    songs.insert(
      songs.indexOf(meta) + 1,
      SongMeta(
        id: nid,
        name: '${meta.name} 복사',
        genre: meta.genre,
        updated: DateTime.now(),
      ),
    );
    await _writeIndex();
    notifyListeners();
  }

  Future<void> rename(String id, String name) async {
    for (final s in songs) {
      if (s.id == id) s.name = name;
    }
    if (id == currentId) project.name = name;
    await _writeIndex();
    if (id == currentId) await saveNow();
    notifyListeners();
  }

  /// 곡 하나의 저장 내용을 **글자 그대로** 꺼낸다 — 백업·기기 이동용.
  ///
  /// 지금 열려 있는 곡이면 **먼저 저장한다.** 안 그러면 마지막 저장 이후에 만진
  /// 것이 빠진 파일이 나간다 — 백업인데 지금 것과 다르면 백업이 아니다.
  ///
  /// 곡 파일이 아직 없으면(막 만든 곡) null.
  Future<String?> exportJson(String id) async {
    if (currentId == id) await saveNow();
    final f = await _songFile(id);
    if (!await f.exists()) return null;
    return f.readAsString();
  }

  /// 밖에서 받은 곡 파일을 **새 곡으로** 들여온다. ([exportJson] 의 짝)
  ///
  /// 꺼내기만 있으면 백업이 반쪽이다 — 폰을 바꾼 사람이 카톡에 보관해 둔 파일을
  /// 다시 열 길이 없었다.
  ///
  /// 규칙 셋:
  ///  · **절대 덮어쓰지 않는다.** 이름이 같아도 늘 새로 만든다 —
  ///    「가져왔더니 내 곡이 없어졌다」보다 나쁜 결과는 없다.
  ///  · **이름이 겹치면 번호를 붙인다.** 목록에 같은 이름 둘이면 어느 것이
  ///    방금 가져온 것인지 모른다.
  ///  · **곡 파일이 아니면 그냥 null.** 고르는 창에서는 아무 파일이나 고를 수 있다 —
  ///    사진을 골라도 앱이 죽으면 안 되고, 빈 곡이 생겨도 안 된다.
  Future<SongMeta?> importJson(String raw) async {
    Map<String, dynamic> j;
    try {
      final v = jsonDecode(raw);
      if (v is! Map) return null;
      j = Map<String, dynamic>.from(v);
    } catch (_) {
      return null;
    }
    // 곡 파일인가 — 씬과 트랙이 있어야 곡이다.
    if (j['scenes'] is! List || j['tracks'] is! List) return null;

    final base = (j['name'] as String?)?.trim();
    var name = (base == null || base.isEmpty) ? '가져온 곡' : base;
    if (songs.any((s) => s.name == name)) {
      var i = 2;
      while (songs.any((s) => s.name == '$name $i')) {
        i++;
      }
      name = '$name $i';
    }
    j['name'] = name;

    await saveNow(); // 지금 열려 있는 곡을 흘리지 않는다
    final id = _newId();
    if (!await _write(await _songFile(id), jsonEncode(j))) return null;
    songs.insert(
      0,
      SongMeta(
        id: id,
        name: name,
        genre: j['genre'] as String? ?? 'lofi',
        updated: DateTime.now(),
      ),
    );
    await _writeIndex();
    // 방금 저장했으니 또 저장하지 않는다(그 사이 아무것도 안 바뀌었다).
    await open(id, saveCurrent: false);
    // 열자마자 한 번 저장한다 — 목록에 보여 줄 **길이**(`sec`)는 여기서 채워진다.
    await saveNow();
    notifyListeners();
    return songs.firstWhere(
      (s) => s.id == id,
      orElse: () =>
          SongMeta(id: id, name: name, genre: 'lofi', updated: DateTime.now()),
    );
  }

  /// 곡을 지운다. **마지막 하나는 안 지운다** — 빈 목록은 사용자가 뭘 해야 할지 모른다.
  ///
  /// **되돌릴 거리를 들고 나온다.** 여태는 지우면 그걸로 끝이었다 —
  /// 목록의 「⋮」에서 「복제」 바로 아래가 「삭제」인데, 한 번 잘못 누르면
  /// 확인도 없이 곡이 사라졌다. 만든 걸 잃는 것보다 나쁜 건 없다.
  /// 파일 내용과 목록에서의 자리를 통째로 들고 나오므로
  /// [undoRemove] 로 **있던 자리에 그대로** 되돌릴 수 있다.
  Future<RemovedSong?> remove(String id) async {
    if (songs.length <= 1) return null;
    // **지금 열려 있는 곡이면 먼저 저장한다.**
    //
    // 아래에서 되돌릴 거리를 **파일에서** 읽는데, 지금 곡은 화면 쪽이 더 최신일
    // 수 있다(자동 저장은 0.8초 뒤에 쓴다). 저장 없이 지우면 마지막 저장 이후에
    // 만진 것 — 스타일·볼륨·씬 — 이 되돌리기로도 안 돌아온다.
    // 여기서는 `currentId` 가 아직 지울 곡이라 제 파일에 제대로 들어간다.
    if (currentId == id) await saveNow();
    final f = await _songFile(id);
    // 지우기 전에 읽는다 — 지운 뒤엔 읽을 것이 없다.
    final raw = await f.exists() ? await f.readAsString() : null;
    final at = songs.indexWhere((s) => s.id == id);
    final meta = at < 0 ? null : songs[at];
    final wasCurrent = currentId == id;
    if (await f.exists()) await f.delete();
    songs.removeWhere((s) => s.id == id);
    if (wasCurrent) {
      // **다음 곡을 열 때 「지금 곡」을 저장하면 안 된다.**
      //
      // [open] 은 기본으로 지금 곡을 먼저 저장하는데, 여기서는 그 「지금 곡」이
      // 방금 지운 곡이다. `currentId` 를 먼저 다음 곡으로 바꿔 두면
      // [saveNow] 가 그 새 id 를 읽고 **메모리에 남아 있는 지운 곡**을 그 파일에
      // 써 버린다 — 이름·장르·길이까지 목록째 덮인다. 곡 둘일 때 열린 쪽을
      // 지우면 남은 한 곡이 지운 곡으로 바뀌어 있었다(되돌리기로도 못 살렸다).
      //
      // 지운 곡의 파일은 바로 위에서 이미 지웠으니 저장할 것 자체가 없다.
      // 여는 데 실패하면 `currentId` 를 null 로 둔다 — 그래야 0.8초 뒤
      // 자동 저장이 지운 곡을 엉뚱한 파일에 쓰지 않는다([saveNow] 가 그냥 빠진다).
      currentId = null;
      await open(songs.first.id, saveCurrent: false);
    }
    await _writeIndex();
    notifyListeners();
    if (raw == null || meta == null) return null;
    return RemovedSong(raw: raw, meta: meta, at: at, wasCurrent: wasCurrent);
  }

  /// [remove] 를 되돌린다 — 파일도, 목록의 자리도, 열려 있었으면 열린 것까지.
  Future<void> undoRemove(RemovedSong r) async {
    if (songs.any((s) => s.id == r.meta.id)) return; // 이미 돌아와 있다
    await _write(await _songFile(r.meta.id), r.raw);
    songs.insert(r.at.clamp(0, songs.length), r.meta);
    await _writeIndex();
    if (r.wasCurrent) {
      await saveNow(); // 대신 열려 있던 곡을 흘리지 않는다
      await open(r.meta.id);
    }
    notifyListeners();
  }

  // ── 자동 저장 ──

  Future<void> saveNow() async {
    final id = currentId;
    if (id == null || _loading) return;
    try {
      await _write(await _songFile(id), jsonEncode(_snapshot()));
      for (final s in songs) {
        if (s.id == id) {
          s.name = project.name;
          s.genre = project.genre;
          s.updated = DateTime.now();
          s.sec = SceneSequencer.songSeconds(project, transport);
          s.sceneActive = sceneActiveOf(project);
          s.scenePatterns = scenePatternsOf(project);
          s.timelineScenes = timelineScenesOf(project);
        }
      }
      await _writeIndex();
    } catch (e) {
      debugPrint('저장 실패: $e');
    }
  }

  /// 트랙 타입별로 **미리보기에 보여 줄 패턴 이름**(키 그대로, 아직 한국어로
  /// 안 옮김)을 고른다. 보통은 지금 씬에 실린 패턴(`t.pattern`)을 쓰지만,
  /// 그게 **전부 다** 비어 있으면(타임라인 레인으로 지은 샘플곡들이 그렇다
  /// — 씬은 늘 빈 채로 두고 소리는 레인에서만 온다) 첫 구간(0번)의 레인
  /// 에서 대신 찾는다. 안 그러면 그 곡들의 미리보기가 늘 텅 비어 보인다
  /// (사용자 요청, 2026-09-13: "샘플곡 카드에도 실제 미리보기").
  /// 트랙 타입당 하나만 고른다(같은 타입 트랙이 둘이면 먼저 찾은 것).
  static Map<String, String> _previewPatternByType(Project p) {
    final byType = <String, String>{};
    for (final t in p.tracks) {
      final pat = t.pattern;
      if (pat != null && !byType.containsKey(t.type)) byType[t.type] = pat;
    }
    if (byType.isEmpty && p.song.sections.isNotEmpty) {
      for (final t in p.tracks) {
        if (byType.containsKey(t.type)) continue;
        final clips = p.song.lanesIn(0, t.id);
        if (clips.isNotEmpty) byType[t.type] = clips.first.pattern;
      }
    }
    return byType;
  }

  /// 지금 씬에서 악기별(드럼·베이스·코드·멜로디)로 패턴이 있는가 —
  /// **카드 미리보기**가 그리는 색 블록의 켜짐/꺼짐.
  static List<bool> sceneActiveOf(Project p) {
    final byType = _previewPatternByType(p);
    return [for (final ty in kPreviewTrackTypes) byType.containsKey(ty)];
  }

  /// 악기별로 **실제로 실린 패턴 이름**(보여 주는 한국어) — 미리보기
  /// 레인을 길게 눌렀을 때 뜨는 툴팁이 쓴다.
  static List<String> scenePatternsOf(Project p) {
    final byType = _previewPatternByType(p);
    return [
      for (final ty in kPreviewTrackTypes)
        byType[ty] == null ? '' : patternShort(byType[ty]!),
    ];
  }

  /// 타임라인 구간 이름들(순서대로) — **카드 미리보기**의 타임라인 줄이 그린다.
  static List<String> timelineScenesOf(Project p) => [
    for (final s in p.scenes) s.name,
  ];

  /// 바뀔 때마다 부른다 — 0.8초 조용해지면 실제로 쓴다.
  void touch() {
    if (_loading) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), saveNow);
  }

  /// 바뀌면 자동 저장되게 걸어 둔다.
  /// **트랙 하나하나에도, 얼개에도 건다** — 그것들은 `Project` 가 아니라 자기가 알린다.
  /// (얼개를 빠뜨렸다가 "구간 판 수만 저장이 안 되는" 버그를 폰에서 잡았다)
  void attach() {
    project.addListener(_onProject);
    project.song.addListener(touch);
    transport.addListener(touch);
    live.addListener(touch);
    master.addListener(touch);
    _wireTracks();
  }

  final _wired = <Track>{};

  void _wireTracks() {
    for (final t in project.tracks) {
      if (_wired.add(t)) t.addListener(touch);
    }
    _wired.removeWhere((t) => !project.tracks.contains(t));
  }

  void _onProject() {
    _wireTracks(); // 트랙이 새로 생겼을 수 있다
    touch();
  }

  void detach() {
    _debounce?.cancel();
    project.removeListener(_onProject);
    project.song.removeListener(touch);
    transport.removeListener(touch);
    live.removeListener(touch);
    master.removeListener(touch);
    for (final t in _wired) {
      t.removeListener(touch);
    }
    _wired.clear();
  }

  /// 지금 곡만 처음 상태로 되돌린다(다른 곡은 그대로).
  Future<void> resetCurrent() async {
    project.reset(newName: project.name);
    _syncTransportToGenre();
    _resetChannels();
    await saveNow();
    notifyListeners();
  }
}
