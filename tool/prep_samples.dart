// 원본 표본을 앱에 넣을 형태로 다듬는다 — 일회성 스크립트(자산 준비용, 앱 코드가 아니다).
// 36초짜리 감쇄 꼬리를 5초로 자르고 끝에 150ms 페이드를 걸어 클릭을 없앤다.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

(Uint8List, int, int) readWav(String path) {
  final bytes = File(path).readAsBytesSync();
  final bd = ByteData.sublistView(bytes);
  var pos = 12; // "RIFF"+size+"WAVE"
  int sampleRate = 0, bitsPerSample = 0, channels = 0;
  Uint8List? data;
  while (pos < bytes.length - 8) {
    final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
    final size = bd.getUint32(pos + 4, Endian.little);
    final body = pos + 8;
    if (id == 'fmt ') {
      channels = bd.getUint16(body + 2, Endian.little);
      sampleRate = bd.getUint32(body + 4, Endian.little);
      bitsPerSample = bd.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      data = bytes.sublist(body, body + size);
    }
    pos = body + size + (size.isOdd ? 1 : 0);
  }
  if (data == null || sampleRate == 0) {
    throw 'bad wav: $path';
  }
  if (channels != 1 || bitsPerSample != 16) {
    throw 'expected mono 16-bit, got ch=$channels bits=$bitsPerSample: $path';
  }
  return (data, sampleRate, channels);
}

void writeWav(String path, Int16List samples, int sampleRate) {
  final dataBytes = samples.length * 2;
  final out = BytesBuilder();
  void u32(int v) {
    out.add([v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff]);
  }

  void u16(int v) {
    out.add([v & 0xff, (v >> 8) & 0xff]);
  }

  out.add('RIFF'.codeUnits);
  u32(36 + dataBytes);
  out.add('WAVE'.codeUnits);
  out.add('fmt '.codeUnits);
  u32(16);
  u16(1); // PCM
  u16(1); // mono
  u32(sampleRate);
  u32(sampleRate * 2); // byte rate (mono 16-bit)
  u16(2); // block align
  u16(16); // bits
  out.add('data'.codeUnits);
  u32(dataBytes);
  final bd = ByteData(dataBytes);
  for (var i = 0; i < samples.length; i++) {
    bd.setInt16(i * 2, samples[i], Endian.little);
  }
  out.add(bd.buffer.asUint8List());
  File(path).writeAsBytesSync(out.toBytes());
}

/// 진짜 소리가 시작하는 자리(피크의 3%) — 20ms 앞부터 살린다.
/// **University of Iowa 원본은 최대 0.58초짜리 무음 프리롤이 있다** — 안
/// 잘라 내면 귀한 5초 중 십 분의 1이 넘게 무음으로 날아간다(실제로 겪은 값).
int _findOnset(Int16List i16) {
  var peak = 0;
  for (final s in i16) {
    final a = s.abs();
    if (a > peak) peak = a;
  }
  final thresh = (peak * 0.03).round();
  for (var i = 0; i < i16.length; i++) {
    if (i16[i].abs() >= thresh) return i;
  }
  return 0;
}

/// `assets/samples/<악기>/*.raw.wav` 를 같은 자리에 `*.wav` 로 다듬는다
/// (afconvert 로 만든 22.05kHz 모노 중간 파일 → 자산으로 쓸 최종 wav).
/// 여러 악기 폴더를 한 번에 훑는다.
void main() {
  const defaultMaxSec = 5.0;
  // 기본팩(늘 번들) 악기는 용량이 더 아프다 — 뜯고 치는 소리라 어차피
  // 자연 감쇄가 3초 안에 거의 다 죽는다(원본이 24비트 긴 꼬리를 담고 있어도
  // 실제 재생은 `SynthNote._startSample` 이 음 길이(`dur`)에 맞춰 릴리스로
  // 끊는다 — 꼬리를 다 갖고 있어봤자 대부분 안 쓰인다).
  const maxSecOverride = {
    'guitar': 3.0,
    'fingerbass': 3.0,
    // 드럼 — 대부분 자연 감쇄가 1초 안에 거의 끝난다(닫힌 하이햇은 훨씬
    // 빠르다). 크래시·라이드만 울림이 길어서 더 준다.
    'drum_kick': 1.0,
    'drum_snare': 1.0,
    'drum_hatClosed': 0.3,
    'drum_hatOpen': 1.2,
    'drum_tom': 1.5,
    'drum_crash': 2.5,
    'drum_ride': 2.5,
  };
  const fadeSec = 0.15;
  const preRollSec = 0.02;
  final samplesDir = Directory('assets/samples');
  final instDirs = samplesDir.listSync().whereType<Directory>();
  for (final instDir in instDirs) {
    final name = instDir.path.split('/').last;
    final maxSec = maxSecOverride[name] ?? defaultMaxSec;
    final outDir = instDir.path;
    final files = instDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.raw.wav'));
    for (final f in files) {
      final (data, sr, _) = readWav(f.path);
      final i16 = Int16List.sublistView(data);
      final onset = _findOnset(i16);
      final start = math.max(0, onset - (preRollSec * sr).round());
      final maxN = (maxSec * sr).round().clamp(0, i16.length - start);
      final trimmed = Int16List.fromList(i16.sublist(start, start + maxN));
      final fadeN = (fadeSec * sr).round().clamp(0, trimmed.length);
      for (var i = 0; i < fadeN; i++) {
        final g = 1.0 - i / fadeN;
        final idx = trimmed.length - fadeN + i;
        trimmed[idx] = (trimmed[idx] * g).round();
      }
      final outName = f.path.split('/').last.replaceAll('.raw.wav', '.wav');
      writeWav('$outDir/$outName', trimmed, sr);
      final kb = (trimmed.length * 2 / 1024).toStringAsFixed(0);
      // ignore: avoid_print
      print(
        '[$name] $outName (프리롤 ${(onset / sr).toStringAsFixed(2)}s 잘림, '
        '${(trimmed.length / sr).toStringAsFixed(2)}s, ${kb}KB)',
      );
    }
  }
}
