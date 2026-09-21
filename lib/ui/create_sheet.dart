// 만들기 시작 — **무슨 음악을 만들지 고르는 한 화면.** (Phase 2 · 개선 계획 4-1·4-2)
//
// 계획이 요구하는 첫 흐름은 이것이다:
//   앱 실행 → 장르 선택 → **기본 음악이 즉시 재생** → 사용자가 바로 조작
//
// 여기서 지킨 것 두 가지:
//
// ① **한 번 누르면 소리가 난다.** 계획의 Create 양식에는 BPM 과 Mood 도 있지만,
//    소리를 듣기 전에 손잡이를 세 개 물어보면 그건 설문지다. 장르마다 검증된
//    템포·조·편성이 이미 있으므로(`kSongGenres` + `setGenre`) 한 번으로 충분하다.
//    템포는 **들으면서** 바꾸는 게 맞다 — 만들기 화면 맨 위에 슬라이더가 있다.
//
// ② **용어를 쓰지 않는다.** 믹서·씬·패턴·스케일은 여기 없다. 장르 이름과
//    "어떤 느낌인지" 한 줄뿐이다. 처음 쓰는 사람에게 개념을 먼저 가르치지 않는다.
import 'package:flutter/material.dart';

import '../genres.dart';
import '../meter.dart';
import '../packs.dart';
import 'show_band.dart' show kStageLights;
import 'text_scale.dart';

/// 장르마다 **한 줄 설명** — 장르 이름만 보고는 뭐가 다른지 모른다.
/// 음악 용어 대신 **들리는 느낌**으로 적는다(계획 4-4 의 방향과 같다).
/// **`kGenres` 에서 뽑아 쓴다** (계획 7-1) — 글은 거기 적혀 있다.
final Map<String, String> kGenreFeel = {for (final g in kGenres) g.key: g.feel};

/// 장르를 고르게 하고 **고른 키**를 돌려준다. 취소하면 null.
Future<String?> showCreateSheet(BuildContext context, {String? current}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF16161A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => CreateSheetBody(
      current: current,
      onPick: (k) => Navigator.of(ctx).pop(k),
    ),
  );
}

/// 시트의 **속**. 따로 뺀 이유: 모달은 그림 도구가 직접 못 그린다.
/// 첫 실행에서 제일 먼저 보는 화면이라 **세로·가로를 눈으로 봐야** 한다.
class CreateSheetBody extends StatefulWidget {
  final String? current;
  final ValueChanged<String> onPick;
  const CreateSheetBody({super.key, this.current, required this.onPick});

  @override
  State<CreateSheetBody> createState() => _CreateSheetBodyState();
}

class _CreateSheetBodyState extends State<CreateSheetBody> {
  /// 「스타일 바꾸기」로 열면 **지금 것이 화면에 보여야** 한다.
  /// 장르가 15개 · 팩이 6개라 가스펠(연주 팩)은 한참 아래에 있다 —
  /// 열면 맨 위(느긋하게)만 보이고 자기가 뭘 쓰는 중인지 알 수 없다.
  final _curKey = GlobalKey();

  /// 지금 걸려 있는 박자 — null 이면 **전부**.
  ///
  /// 5단계 47/N — 왈츠(3/4)·흔들발라드(6/8)가 생기면서 열다섯 장르 사이에
  /// 4/4 가 아닌 것이 섞였다. 스타일 이름만 보고는 박자가 다르다는 걸 모른다 —
  /// 「이 판은 지금 곡과 안 맞다」를 스타일을 **고르기 전에** 걸러서 보여준다.
  /// 숫자(3/4)가 아니라 `MeterDef.feel` 의 앞 토막("세 박")을 쓴다 —
  /// 이 화면은 처음부터 음악 용어를 안 썼다.
  String? _meter;

  @override
  void initState() {
    super.initState();
    if (widget.current == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _curKey.currentContext;
      if (c == null || !mounted) return;
      Scrollable.ensureVisible(
        c,
        alignment: 0.35,
        duration: const Duration(milliseconds: 260),
      );
    });
  }

  @override
  Widget build(BuildContext ctx) {
    final current = widget.current;
    final onPick = widget.onPick;
    // **가로로 누우면 높이가 귀하다.** 세로 목록 그대로 두면 카드가 두 개밖에
    // 안 보인다 — 세 칸으로 접는다(첫 화면이 이미 같은 방식이다).
    final wide = MediaQuery.of(ctx).size.height < 520;
    final maxH = MediaQuery.of(ctx).size.height * (wide ? 0.92 : 0.8);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 2),
              child: Text(
                current == null ? '무슨 음악을 만들까요' : '스타일 바꾸기',
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Text(
                '고르면 바로 소리가 납니다. 나중에 언제든 바꿀 수 있어요.',
                style: TextStyle(fontSize: 12.5, color: Colors.white54),
              ),
            ),
            _MeterFilterRow(
              value: _meter,
              onChanged: (m) => setState(() => _meter = m),
            ),
            // 장르가 13개가 되면서 **한 덩어리로는 어디쯤인지 감이 안 온다.**
            // 팩(계획 7-2)으로 묶어 소제목을 붙였다 — 팩은 「무엇을 만들고 싶은가」로
            // 묶여 있으므로 그대로 길잡이가 된다. 결제·잠금과는 아무 상관이 없다.
            Flexible(
              // **키를 준다** — 박자 칩 줄도 가로로 스크롤되는 `ListView` 라,
              // 키가 없으면 시험의 `find.byType(ListView)` 가 둘을 잡아 헷갈린다.
              child: ListView(
                key: const Key('genreList'),
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
                children: [
                  // **박자로 거른다.** 3/4·6/8 이 섞이면서, 지금 곡 박자와
                  // 안 맞는 스타일을 고르는 순간 편집기 격자가 어긋난다
                  // (5단계 47/N). 여기서 미리 걸러 두면 그 자리 자체가 없다.
                  // 걸러서 **빈 팩**(예: '왈츠' 만 고르면 「비트」 팩은 하나도
                  // 안 남는다)은 소제목째로 건너뛴다 — 빈 칸을 보여주면
                  // "고장났나" 하게 된다.
                  for (final (pack, all) in packedGenres())
                    if (_filterByMeter(all).isNotEmpty)
                      _PackSection(
                        pack: pack,
                        genres: _filterByMeter(all),
                        wide: wide,
                        current: current,
                        curKey: _curKey,
                        onPick: onPick,
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<GenreDef> _filterByMeter(List<GenreDef> genres) => _meter == null
      ? genres
      : [for (final g in genres) if (g.meter == _meter) g];
}

/// 「전부」+ 실제로 스타일이 있는 박자만 칩으로 보여준다.
///
/// 5·7박(`kMeters` 의 5/4·7/8)은 아직 판 라이브러리가 없다(5단계 47/N 「남은 것」) —
/// 그 칩을 보여줘 놓고 고르면 목록이 텅 비면 그게 더 고장처럼 보인다.
/// 박자가 **하나뿐이면**(지금까지 여기가 4/4 전용이었을 때) 칩 자체를 안 그린다 —
/// 고를 게 하나뿐인 손잡이는 손잡이가 아니라 소음이다.
class _MeterFilterRow extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _MeterFilterRow({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final inUse = {for (final g in kGenres) g.meter};
    final metersHere = [for (final m in kMeters) if (inUse.contains(m.key)) m];
    if (metersHere.length <= 1) return const SizedBox.shrink();

    // 「세 박에 빙글빙글 — 춤추듯 도는」의 **앞 토막만** — 숫자(3/4) 대신
    // 들리는 느낌으로, 그리고 칩 한 줄에 다 들어가게 짧게.
    String short(MeterDef m) => m.feel.split(' — ').first;

    // **위아래 여백은 바깥에** 둔다 — `ListView.padding` 은 가로 스크롤일 때
    // 위·아래도 **가로축 크기(cross axis extent)를 깎아 먹는다.** 여기에
    // bottom:10 을 넣었더니 34 짜리 칩이 24 로 눌려서 시험(최소 세로 32)에 걸렸다.
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          children: [
            _MeterChip(
              label: '전부',
              on: value == null,
              onTap: () => onChanged(null),
            ),
            for (final m in metersHere)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: _MeterChip(
                  label: short(m),
                  on: value == m.key,
                  onTap: () => onChanged(m.key),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MeterChip extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _MeterChip({
    required this.label,
    required this.on,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: on ? Colors.tealAccent.withValues(alpha: 0.22) : Colors.white10,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: on ? Colors.tealAccent : Colors.white24,
              width: on ? 1.4 : 1,
            ),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: on ? FontWeight.w800 : FontWeight.w600,
              color: on ? Colors.tealAccent.shade100 : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

class _PackSection extends StatelessWidget {
  final Pack pack;
  final List<GenreDef> genres;
  final bool wide;
  final String? current;
  final GlobalKey curKey;
  final ValueChanged<String> onPick;

  const _PackSection({
    required this.pack,
    required this.genres,
    required this.wide,
    required this.current,
    required this.curKey,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                pack.label,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w900,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pack.blurb,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: Colors.white30),
                ),
              ),
            ],
          ),
        ),
        GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          // **비율(childAspectRatio)이 아니라 높이를 준다.**
          // 비율은 「높이 = 폭 ÷ 비율」이라 **폭이 좁은 폰일수록 카드가
          // 낮아진다** — 그런데 안에 들어갈 두 줄짜리 설명은 그대로다.
          // 320dp 폰에서 1.0배 글자로도 넘쳤다(시험에서 잡았다).
          // 높이는 폭과 상관없어야 한다. 글자 배율만큼만 커진다.
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: wide ? 3 : 1,
            // 78·108 은 딱 맞는 값이 아니라 **몇 픽셀 여유를 둔** 값이다
            // (딱 맞추면 0.4px 씩 넘쳤다). 카드 안 빈자리는 안 보인다.
            mainAxisExtent: scaled(context, wide ? 108 : 78),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          children: [
            for (final g in genres)
              _GenreCard(
                key: g.key == current ? curKey : null,
                genreKey: g.key,
                label: g.label,
                bpm: g.bpm,
                feel: g.feel,
                on: g.key == current,
                onTap: () => onPick(g.key),
              ),
          ],
        ),
      ],
    );
  }
}

class _GenreCard extends StatelessWidget {
  final String genreKey, label, feel;
  final double bpm;
  final bool on;
  final VoidCallback onTap;
  const _GenreCard({
    super.key,
    required this.genreKey,
    required this.label,
    required this.bpm,
    required this.feel,
    required this.on,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 무대 조명 색을 그대로 쓴다 — 쇼 화면에서 보게 될 색과 같아야
    // "내가 고른 것"이 이어진 느낌이 난다.
    final c = (kStageLights[genreKey] ?? const [Colors.teal])[0];
    return Material(
      color: on ? c.withValues(alpha: 0.30) : c.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: on ? c : c.withValues(alpha: 0.35),
              width: on ? 2 : 1.2,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w900,
                        color: c,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      feel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Colors.white60,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 숫자만 있으면 **그게 뭔지 알 수가 없다.** 이 화면은 「들리는 느낌」으로
              // 말하기로 해 놓고 여기만 정체불명의 수가 놓여 있었다.
              // 'BPM' 대신 「빠르기」 — 이 화면의 다른 글과 같은 말투로.
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    '${bpm.round()}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: c.withValues(alpha: 0.75),
                    ),
                  ),
                  Text(
                    '빠르기',
                    style: TextStyle(
                      fontSize: 8.5,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      color: c.withValues(alpha: 0.40),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
