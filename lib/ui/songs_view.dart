// 내 곡 목록 — **곡을 여러 개 만들고 오갈 수 있게.**
//
// 곡이 하나뿐이면 새로 만드는 순간 앞 곡이 사라진다. 그러면 사람은 두 번째 곡을
// 시작하지 않는다("망칠까 봐"). 목록이 생기면 마음 놓고 새로 만들고, 복제해서 실험한다.
//
// 목록은 `index.json` 하나만 읽어서 그린다 — 곡이 20개여도 파일 하나다.

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../presets.dart';
import '../project.dart';
import '../store.dart';

/// 정렬 기준 — 곡이 늘면 "언제 만든 거였지"로는 못 찾는다.
enum SongSort { recent, name, length }

class SongsView extends StatefulWidget {
  final Store store;
  final Project project;

  /// 곡을 열고 나서 할 일(재생 정지·버스 다시 잡기 등).
  final VoidCallback onOpened;

  const SongsView({
    super.key,
    required this.store,
    required this.project,
    required this.onOpened,
  });

  @override
  State<SongsView> createState() => _SongsViewState();
}

class _SongsViewState extends State<SongsView> {
  SongSort _sort = SongSort.recent;

  /// **화면에 있는 동안 줄 순서를 얼려 둔다.**
  ///
  /// 「최근」 정렬은 곡을 열 때마다 바뀐다 — 곡을 열면 앞 곡이 저장되면서
  /// 그 곡의 시각이 갱신되고, 목록이 손가락 밑에서 다시 늘어선다.
  /// 두어 번 오가면 누르려던 곡이 딴 자리에 가 있어서 **엉뚱한 곡을 연다.**
  /// 그래서 자리는 들어올 때(그리고 정렬을 바꿀 때)만 정하고, 그 뒤로는
  /// 새로 생긴 곡만 뒤에 붙이고 없어진 곡만 뺀다.
  List<String>? _order;

  Store get store => widget.store;
  VoidCallback get onOpened => widget.onOpened;

  /// 원본 순서는 안 건드린다 — 저장 파일의 순서는 그대로 두고 보기만 정렬한다.
  List<SongMeta> _freshSort() {
    final list = [...store.songs];
    switch (_sort) {
      case SongSort.recent:
        list.sort((a, b) => b.updated.compareTo(a.updated));
      case SongSort.name:
        list.sort((a, b) => a.name.compareTo(b.name));
      case SongSort.length:
        list.sort((a, b) => b.sec.compareTo(a.sec));
    }
    return list;
  }

  List<SongMeta> get _sorted {
    final by = {for (final s in store.songs) s.id: s};
    var order = _order;
    if (order == null) {
      order = [for (final s in _freshSort()) s.id];
      _order = order;
      return [for (final id in order) by[id]!];
    }
    // 없어진 곡은 빼고, 새로 생긴 곡은 **맨 앞**에 (방금 만들거나 가져온 것이다).
    order.removeWhere((id) => !by.containsKey(id));
    final seen = order.toSet();
    for (final s in _freshSort().reversed) {
      if (!seen.contains(s.id)) order.insert(0, s.id);
    }
    return [for (final id in order) by[id]!];
  }

  void _resort(SongSort v) => setState(() {
    _sort = v;
    _order = null; // 정렬을 바꿀 때는 다시 세운다
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) => Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white12)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '곡 ${store.songs.length}개',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                // 정렬 — 곡이 서너 개만 넘어도 "이름이 뭐였더라"가 시작된다
                if (store.songs.length > 2) ...[
                  _SortChip(
                    label: '최근',
                    on: _sort == SongSort.recent,
                    onTap: () => _resort(SongSort.recent),
                  ),
                  _SortChip(
                    label: '이름',
                    on: _sort == SongSort.name,
                    onTap: () => _resort(SongSort.name),
                  ),
                  _SortChip(
                    label: '길이',
                    on: _sort == SongSort.length,
                    onTap: () => _resort(SongSort.length),
                  ),
                  const SizedBox(width: 8),
                ],
                FilledButton.icon(
                  onPressed: () async {
                    await store.newSong();
                    onOpened();
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text(
                    '새 곡',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.indigo.shade500,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
              itemCount: _sorted.length,
              itemBuilder: (context, i) {
                final s = _sorted[i];
                final on = s.id == store.currentId;
                final g = songGenreOf(s.genre);
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: on ? 0.09 : 0.04),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: on ? Colors.indigo.shade300 : Colors.white12,
                    ),
                  ),
                  // ListTile 은 **가장 가까운 Material** 위에 눌린 표시를 그린다.
                  // 색 있는 상자 안에 그냥 넣으면 그 표시가 가려져 **눌러도 반응이 없어
                  // 보인다**(Flutter 가 경고로 알려 준다).
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      onTap: on
                          ? null
                          : () async {
                              await store.open(s.id);
                              onOpened();
                            },
                      title: Text(
                        s.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: on ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '${g.$2} ${g.$3.round()}BPM'
                        '${s.sec > 0 ? ' · ${_mmss(s.sec)}' : ''}'
                        ' · ${_ago(s.updated)}'
                        '${on ? ' · 지금 열려 있음' : ''}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.white38,
                        ),
                      ),
                      // 이름 바꾸기는 **밖으로 꺼냈다** — ⋮ 안에 있으면 있는 줄도 모른다.
                      // 곡 이름이 전부 '새 곡 2' 로 남는 이유가 그거다.
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.drive_file_rename_outline,
                              size: 19,
                            ),
                            color: Colors.white38,
                            tooltip: '이름 바꾸기',
                            onPressed: () => _rename(context, s),
                          ),
                          IconButton(
                            icon: const Icon(Icons.more_vert, size: 20),
                            color: Colors.white38,
                            onPressed: () => _menu(context, s),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // ── 파일에서 가져오기 ──
          //
          // 「파일로 꺼내기」의 **짝**. 꺼내기만 있으면 백업이 반쪽이다 —
          // 폰을 바꾼 사람이 카톡에 보관해 둔 곡 파일을 다시 열 길이 없었다.
          //
          // 위 줄(정렬 칩 + 「새 곡」)에 넣지 않는다 — 320dp 폰에서 자리를 다툰다.
          // 목록 아래에 한 줄로 두면 늘 보이고 넓이도 넉넉하다.
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: SizedBox(
              width: double.infinity,
              height: 44, // 손가락 바닥선
              child: OutlinedButton.icon(
                onPressed: _importSong,
                icon: const Icon(Icons.file_open_outlined, size: 18),
                label: const Text(
                  '파일에서 가져오기',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _menu(BuildContext context, SongMeta s) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1A1A1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit, size: 20),
              title: const Text('이름 바꾸기', style: TextStyle(fontSize: 14)),
              onTap: () {
                Navigator.pop(ctx);
                _rename(context, s);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy, size: 20),
              title: const Text('복제', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                '망칠 걱정 없이 실험해 보세요',
                style: TextStyle(fontSize: 11, color: Colors.white38),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                await store.duplicate(s.id);
              },
            ),
            // ── 파일로 꺼내기 ──
            //
            // 곡은 앱 전용 폴더에만 있다. **앱을 지우거나 폰을 바꾸면 전곡이
            // 사라진다.** 만든 걸 잃는 것보다 나쁜 건 없다는 게 이 앱의 첫 규칙인데,
            // 정작 제일 크게 잃는 길이 열려 있었다.
            //
            // 카톡·드라이브 아무 데나 보내 두면 그게 백업이다.
            ListTile(
              leading: const Icon(Icons.save_alt, size: 20),
              title: const Text('파일로 꺼내기', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                '카톡·드라이브에 보관해 두면 폰을 바꿔도 남습니다',
                style: TextStyle(fontSize: 11, color: Colors.white38),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                await _exportSong(context, s);
              },
            ),
            if (store.songs.length > 1)
              ListTile(
                leading: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: Colors.red.shade300,
                ),
                title: Text(
                  '삭제',
                  style: TextStyle(fontSize: 14, color: Colors.red.shade300),
                ),
                // **지우고 나서 되돌릴 거리를 준다.** 확인 창을 하나 더 띄우는
                // 쪽이 아니라 이쪽을 골랐다 — 확인 창은 제대로 누른 사람까지
                // 매번 붙잡으면서, 정작 「누르고 나서 아차 싶은」 경우는 못 막는다.
                onTap: () async {
                  Navigator.pop(ctx);
                  final messenger = ScaffoldMessenger.of(context);
                  final gone = await store.remove(s.id);
                  onOpened();
                  if (gone == null) return;
                  messenger.clearSnackBars();
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('「${gone.meta.name}」 을 지웠습니다'),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 6),
                      action: SnackBarAction(
                        label: '되돌리기',
                        onPressed: () async {
                          await store.undoRemove(gone);
                          onOpened();
                        },
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  /// 곡 하나를 `.json` 으로 꺼내 공유 시트를 연다.
  ///
  /// **지금 열려 있는 곡이면 먼저 저장한다**(`exportJson` 이 한다) — 마지막 저장
  /// 이후에 만진 것이 빠진 파일은 백업이 아니다.
  ///
  /// 파일 이름은 곡 이름을 딴다. 「새 곡 2.json」 이 여러 개면 받은 쪽에서
  /// 무엇이 무엇인지 알 수 없다 — 그래서 만든 날짜를 붙인다.
  /// 밖에서 받은 곡 파일을 들여온다. ([_exportSong] 의 짝)
  ///
  /// 고르는 창은 **아무 파일이나** 고를 수 있게 열어 둔다. 확장자로 거르면
  /// 카톡·드라이브를 거쳐 온 파일이 목록에서 아예 안 보이는 일이 생긴다
  /// (앱마다 확장자를 떼거나 바꿔 붙인다). 대신 **내용을 보고** 거른다.
  Future<void> _importSong() async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String m) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(m, style: const TextStyle(fontSize: 12.5)),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
    }

    try {
      final picked = await FilePicker.platform.pickFiles();
      final path = picked?.files.single.path;
      if (path == null) return; // 취소 — 아무 말도 안 한다
      final raw = await File(path).readAsString();
      final meta = await store.importJson(raw);
      if (meta == null) {
        say('곡 파일이 아닙니다 — 「파일로 꺼내기」로 만든 것을 골라 주세요');
        return;
      }
      onOpened();
      say('「${meta.name}」 을 가져와서 열었습니다');
    } catch (e) {
      // **말해 준다.** 조용히 실패하면 가져온 줄 알고 지나간다.
      say('가져오지 못했습니다 — $e');
    }
  }

  Future<void> _exportSong(BuildContext context, SongMeta s) async {
    final messenger = ScaffoldMessenger.of(context);
    void say(String m) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(m, style: const TextStyle(fontSize: 12.5)),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }

    try {
      final raw = await store.exportJson(s.id);
      if (raw == null) {
        say('아직 저장된 내용이 없습니다');
        return;
      }
      final dir = await getTemporaryDirectory();
      final stem = _fileStem(s);
      final f = File('${dir.path}/$stem.json');
      await f.writeAsString(raw);
      await Share.shareXFiles(
        [XFile(f.path, mimeType: 'application/json')],
        subject: '${s.name} — 음악 낙서장 곡 파일',
        text: '「${s.name}」 곡 파일입니다. 이 앱에서 다시 열 수 있어요.',
      );
    } catch (e) {
      // **말해 준다.** 조용히 실패하면 백업한 줄 알고 지나간다.
      say('꺼내지 못했습니다 — $e');
    }
  }

  /// 파일 이름 — 곡 이름 + 날짜. 파일 이름에 못 쓰는 글자는 밑줄로 바꾼다.
  static String _fileStem(SongMeta s) {
    final safe = s.name
        .trim()
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');
    final name = safe.isEmpty ? '곡' : safe;
    final d = s.updated;
    final ymd =
        '${d.year}${d.month.toString().padLeft(2, '0')}'
        '${d.day.toString().padLeft(2, '0')}';
    return '$name-$ymd';
  }

  Future<void> _rename(BuildContext context, SongMeta s) async {
    final ctl = TextEditingController(text: s.name);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1E),
        title: const Text('곡 이름', style: TextStyle(fontSize: 16)),
        content: TextField(
          controller: ctl,
          autofocus: true,
          onSubmitted: (t) => Navigator.pop(ctx, t),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    if (v != null && v.trim().isNotEmpty) await store.rename(s.id, v.trim());
  }
}

/// 초 → 2:40. 목록에서 **얼마나 긴 곡인지**가 스타일만큼 중요한 단서다
/// (30초짜리 스케치인지 3분짜리 곡인지).
class _SortChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _SortChip({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 5),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? Colors.indigo.shade400 : Colors.white10,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: on ? Colors.white : Colors.white54,
            ),
          ),
        ),
      ),
    );
  }
}

String _mmss(double sec) {
  final t = sec.round();
  return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return '방금';
  if (d.inHours < 1) return '${d.inMinutes}분 전';
  if (d.inDays < 1) return '${d.inHours}시간 전';
  if (d.inDays < 30) return '${d.inDays}일 전';
  return '${t.year}.${t.month}.${t.day}';
}
