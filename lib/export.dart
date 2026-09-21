// 곡 내보내기 — **만든 곡을 앱 밖으로 꺼낸다.**
//
// 왜 이게 중요한가: 앱 안에만 있는 음악은 아무도 못 듣는다. 사람이 곡을 만들고 나서
// 제일 먼저 하고 싶은 건 "들려주기"다. 꺼낼 수 없으면 만들 이유가 절반으로 준다.
//
// ── 실시간이 아니라 **오프라인 렌더** ──
// 재생은 초당 48000샘플을 제때 만들어야 하지만, 파일로 뽑을 때는 **최대한 빨리** 만들면
// 된다. 같은 `Engine` 을 그냥 쉬지 않고 돌린다(시험에서 하던 것과 같은 방식).
// 2분 40초짜리가 몇 초면 끝난다.
//
// ── 반드시 **다른 아이솔레이트**에서 ──
// UI 아이솔레이트에서 돌리면 그 몇 초 동안 화면이 완전히 얼어붙는다. 오디오 아이솔레이트
// 에서 돌려도 안 된다 — 그쪽은 재생을 먹여야 한다. 그래서 렌더 전용으로 하나 더 띄운다.
//
// ── 왜 WAV 인가 ──
// MP3/AAC 로 만들려면 인코더(네이티브 의존)가 필요하다. WAV 는 헤더 44바이트 + 그대로
// 쓰면 끝이고, 어디서나 재생된다. 2분 40초 ≈ 30MB — 공유하기에 아직 무리 없는 크기다.

import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart'
    show BackgroundIsolateBinaryMessenger, RootIsolateToken;

import 'drum_sampler.dart' show ensureDrumPieceLoaded;
import 'engine.dart';
import 'sampler.dart' show ensureInstrumentLoaded, kSampleInstrumentKeys;
import 'synth.dart' show Human;
import 'fx.dart';
import 'mixer.dart';

/// 렌더에 필요한 것 전부 — 아이솔레이트로 넘어가야 하므로 **평범한 값**만 담는다.
class ExportJob {
  final List<List<dynamic>>
  notes; // [voice, freq, durSec, vel, soft, glide, at, part]
  final List<List<dynamic>> drums; // [kit, lane, vel, tomFreq, at]
  final List<String> busNames;

  /// 버스별 [vol, pan, rev, lo, mid, hi] — 믹서에서 맞춰 둔 값 그대로 나가야 한다.
  /// 키는 버스 이름('drum' 또는 트랙 id).
  final Map<String, List<double>> buses;

  /// 버스 이름 → 꽂아 둔 인서트(순서대로). **내보낸 파일이 들리던 것과 같아야 한다** —
  /// 인서트를 빼먹으면 앰프를 걸어 놓고 뽑았는데 깨끗한 소리가 나온다.
  final Map<String, List<Map<String, dynamic>>> inserts;

  final double masterVol;

  /// 킥↔베이스 비켜 주기 세기 — 재생 쪽 `kGenreDuck` 과 같은 값이어야 한다.
  final double duck;
  final double seconds;

  /// **연주 흔들림 단계** — 0 끔 · 1 자연스럽게 · 2 많이.
  ///
  /// 렌더는 **다른 아이솔레이트**에서 돈다. `Human` 은 static 이라 거기서는 늘
  /// 기본값(1)으로 시작한다 — 사용자가 「끔」으로 해 놓아도 파일에는 흔들림이
  /// 실렸을 것이다. **들은 것과 파일이 다르면 그건 앱이 거짓말을 한 것이다**
  /// (마스터 페이더가 정확히 이 이유로 한 번 빠졌었다).
  final int human;

  const ExportJob({
    required this.notes,
    required this.drums,
    required this.busNames,
    required this.buses,
    this.inserts = const {},
    required this.masterVol,
    this.duck = 0,
    required this.seconds,
    this.human = 1,
  });
}

/// 통째로 렌더해서 WAV 바이트를 돌려준다. **아이솔레이트 안에서 돌린다.**
/// [onProgress] 는 0~1. 폰에서 2분 40초짜리가 **1분 가까이** 걸린다 — 진행률 없이
/// 동그라미만 돌면 사용자는 멈춘 줄 안다(실제로 그렇게 보였다).
Uint8List renderWav(ExportJob job, {void Function(double)? onProgress}) {
  // 흔들림을 **먼저** 건다 — 예약할 때 걸리는 값이라 나중에 걸면 이미 늦다.
  //
  // `Human` 은 static 이라 **빌리는 것**이다. 렌더가 끝나면 되돌려 놓는다 —
  // 안 되돌리면 같은 아이솔레이트에서 뒤에 도는 것(시험이 그렇다)이 남의 설정을
  // 물려받는다. 실제로 「재생 = 내보내기」 시험이 그것 때문에 깨졌다.
  final humanWas = Human.level;
  Human.setLevel(job.human);
  final e = Engine();
  e.trackMix.configure(job.busNames);
  e.userGain = job.masterVol;
  // **들은 것과 파일이 같아야 한다** — 비켜 주기도 같이 실린다 (계획 6-5)
  e.duckAmount = job.duck;

  void applyInserts(TrackMix? b, List<Map<String, dynamic>>? slots) {
    if (b == null || slots == null) return;
    b.inserts.clear();
    for (final j in slots) {
      final fx = makeFx(j['type'] as String);
      if (fx == null) continue;
      fx.on = j['on'] as bool? ?? true;
      final ps = j['p'];
      if (ps is Map) {
        ps.forEach((k, v) => fx.set(k as String, (v as num).toDouble()));
      }
      b.inserts.add(fx);
    }
  }

  void apply(TrackMix? b, List<double>? v) {
    if (b == null || v == null) return;
    b.vol = v[0];
    b.pan = v[1];
    b.rev = v[2];
    b.eqLoDb = v[3];
    b.eqMidDb = v[4];
    b.eqHiDb = v[5];
    // 뒤 넷은 나중에 붙었다 — 길이를 먼저 본다(옛 스냅샷도 그대로 돈다)
    if (v.length > 6) b.hpfFreq = v[6];
    if (v.length > 7) b.lpfFreq = v[7];
    if (v.length > 8) b.lfoHz = v[8];
    if (v.length > 9) b.lfoDepth = v[9];
    b.markDirty();
  }

  apply(e.trackMix.drum, job.buses['drum']);
  applyInserts(e.trackMix.drum, job.inserts['drum']);
  // 마스터 인서트 — 마스터링까지 파일에 담긴다
  final mfx = job.inserts['master'];
  if (mfx != null) {
    for (final j in mfx) {
      final fx = makeFx(j['type'] as String);
      if (fx == null) continue;
      fx.on = j['on'] as bool? ?? true;
      final ps = j['p'];
      if (ps is Map) {
        ps.forEach((k, v) => fx.set(k as String, (v as num).toDouble()));
      }
      e.masterInserts.add(fx);
    }
  }
  for (final name in job.busNames) {
    apply(e.trackMix.bus(name), job.buses[name]);
    applyInserts(e.trackMix.bus(name), job.inserts[name]);
  }

  for (final d in job.drums) {
    e.scheduleDrum(
      d[4] as double,
      d[0] as String,
      d[1] as String,
      d[2] as int,
      tomFreq: d[3] as double,
    );
  }
  for (final n in job.notes) {
    e.schedule(
      n[6] as double,
      n[0] as String,
      n[1] as double,
      n[2] as double,
      n[3] as int,
      soft: n[4] as bool,
      glideF: n[5] as double,
      part: n[7] as int,
    );
  }

  // 끝에 꼬리(리버브·긴 음)를 위해 2초를 더 준다 — 안 그러면 마지막 음이 잘린다.
  final frames = ((job.seconds + 2.0) * kSampleRate).round();
  final pcm = Int16List(frames * 2);
  var got = 0;
  var lastPct = -1;
  while (got < frames) {
    final n = 4096 < frames - got ? 4096 : frames - got;
    pcm.setRange(got * 2, (got + n) * 2, e.render(n));
    got += n;
    if (onProgress != null) {
      final pct = got * 100 ~/ frames;
      if (pct != lastPct) {
        lastPct = pct;
        onProgress(pct / 100);
      }
    }
  }
  Human.setLevel(humanWas); // 빌린 것을 되돌린다
  return _wav(pcm, kSampleRate, 2);
}

/// 아이솔레이트로 넘겨서 렌더한다. UI 는 그동안 멀쩡히 돈다.
/// 진행률을 받으려면 `Isolate.run` 으로는 안 된다(돌려주는 값만 받을 수 있다) —
/// 포트를 직접 열어서 중간 보고를 받는다.
///
/// **`RootIsolateToken` 을 같이 넘긴다** — 표본 악기(피아노·기타·드럼 등)
/// 는 `rootBundle.load` 로 자산을 읽는데, 그건 플랫폼 채널이 있어야 한다.
/// 이 토큰 없이는 렌더 아이솔레이트에서 그 채널이 안 열려 있어서
/// `rootBundle.load` 가 조용히 실패하고(표본 로더의 try/catch 가 삼킨다),
/// **내보낸 파일이 표본 악기까지 전부 합성으로 나갔었다** — 사용자 지적
/// ("샘플 쓰고 있는거 맞아?") 으로 찾은 버그. 실제 재생(`audio_isolate.dart`)
/// 은 처음부터 이 토큰을 받고 있어서 안 걸렸다.
Future<Uint8List> renderWavInIsolate(
  ExportJob job, {
  void Function(double)? onProgress,
}) async {
  final rx = ReceivePort();
  final done = Completer<Uint8List>();
  final token = RootIsolateToken.instance;
  await Isolate.spawn(
    _renderEntry,
    [rx.sendPort, job, token],
    debugName: 'export',
  );
  rx.listen((m) {
    if (m is double) {
      onProgress?.call(m);
    } else if (m is Uint8List) {
      if (!done.isCompleted) done.complete(m);
      rx.close();
    } else if (m is String) {
      if (!done.isCompleted) done.completeError(m);
      rx.close();
    }
  });
  return done.future;
}

/// [job] 이 쓰는 표본 악기·표본 드럼 킷을 **다 읽어서 끝날 때까지 기다린다.**
///
/// `_renderEntry` 에서 분리해 둔 이유: `renderWav` 자체는 중간에 한 번도
/// `await` 하지 않는 동기 루프라서(파일로 최대한 빨리 뽑으려고 일부러
/// 그렇게 짰다, 이 파일 위쪽 문서 참고) 그 루프 도중에 비동기로 표본을
/// 불러오면 이벤트 루프에 넘어갈 틈이 없어 영영 안 끝난다 — 반드시
/// **렌더를 시작하기 전에, 기다려서** 끝내야 한다. (시험이 이 함수만
/// 따로 불러서 "그 job 이 실제로 표본을 읽어 들이는지" 확인한다 —
/// `export_sample_check_test.dart`.)
Future<void> preloadExportSamples(ExportJob job) async {
  final voices = <String>{
    for (final n in job.notes) n[0] as String,
  }.where(kSampleInstrumentKeys.contains);
  for (final v in voices) {
    await ensureInstrumentLoaded(v);
  }
  final kits = <String>{for (final d in job.drums) d[0] as String};
  if (kits.contains('acoustic') || kits.contains('rock')) {
    for (final piece in [
      'kick',
      'snare',
      'hatClosed',
      'hatOpen',
      'crash',
      'ride',
      'tom',
    ]) {
      await ensureDrumPieceLoaded(piece);
    }
  }
}

void _renderEntry(List<dynamic> a) async {
  final tx = a[0] as SendPort;
  final job = a[1] as ExportJob;
  final token = a[2] as RootIsolateToken?;
  try {
    if (token != null) {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
      await preloadExportSamples(job);
    }
    tx.send(renderWav(job, onProgress: tx.send));
  } catch (e) {
    tx.send('$e');
  }
}

/// RIFF/WAVE 헤더 44바이트 + PCM16 그대로.
Uint8List _wav(Int16List pcm, int rate, int channels) {
  final dataBytes = pcm.length * 2;
  final out = Uint8List(44 + dataBytes);
  final b = ByteData.view(out.buffer);
  void tag(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      out[at + i] = s.codeUnitAt(i);
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 36 + dataBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little); // PCM 청크 길이
  b.setUint16(20, 1, Endian.little); // 1 = PCM
  b.setUint16(22, channels, Endian.little);
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * channels * 2, Endian.little); // 초당 바이트
  b.setUint16(32, channels * 2, Endian.little); // 한 프레임 바이트
  b.setUint16(34, 16, Endian.little); // 비트 깊이
  tag(36, 'data');
  b.setUint32(40, dataBytes, Endian.little);
  out.setRange(44, 44 + dataBytes, pcm.buffer.asUint8List());
  return out;
}

/// 내보낼 파일의 이름 몸통 — **곡 이름을 쓴다.**
///
/// 예전엔 `음악낙서장_팝` 처럼 **장르만** 썼다. 그러면 팝으로 만든 곡 셋이 전부
/// 같은 파일 이름이다 — 받은 사람 화면에서도, 내 다운로드 폴더에서도 구별이 안 되고,
/// 같은 이름끼리 덮어쓴다. 곡에 이름을 붙이는 자리를 만들어 놓고 정작 파일에는
/// 안 쓰고 있었다.
///
/// 파일 이름에 못 쓰는 글자(`/ \ : * ? " < > |` · 제어문자)는 걷어 낸다.
/// 걷어 내고 나서 남는 게 없으면(이름이 「///」 같은 것뿐이면) 장르 이름으로 돌아간다 —
/// 이름 없는 파일을 만드느니 예전 방식이 낫다.
String exportStem(String title, String genreLabel) {
  const bad = r'/\:*?"<>|';
  final buf = StringBuffer();
  for (final r in title.trim().runes) {
    // 제어문자(줄바꿈·탭 포함)와 못 쓰는 글자를 뺀다. 점으로 시작하면 숨김 파일이 된다.
    if (r < 0x20 || r == 0x7f) continue;
    final c = String.fromCharCode(r);
    if (bad.contains(c)) continue;
    buf.write(c);
  }
  // 여러 칸 띄어쓰기를 하나로, 앞뒤 점·공백을 걷어 낸다.
  var s = buf.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  while (s.startsWith('.')) {
    s = s.substring(1).trim();
  }
  while (s.endsWith('.')) {
    s = s.substring(0, s.length - 1).trim();
  }
  // 너무 길면 자른다 — 파일 이름 길이 제한(대개 255바이트)에 한글은 3바이트씩이다.
  if (s.runes.length > 30) s = String.fromCharCodes(s.runes.take(30)).trim();
  return '음악낙서장_${s.isEmpty ? genreLabel : s}';
}
