// 새 프로젝트를 만들 때 **어떻게 시작할지** 고르는 시트 (사용자 지시, 2026-09-29).
//
// 이름을 지은 다음에 뜬다. 고르기 전에는 프로젝트가 만들어지지 않는다 — 닫으면
// (바깥 탭·뒤로가기) null 이고 아무것도 안 남는다.
import 'package:flutter/material.dart';

enum NewProjectMode { ask, doodle, scratch }

Future<NewProjectMode?> showNewProjectChoiceSheet(BuildContext context) {
  return showModalBottomSheet<NewProjectMode>(
    context: context,
    backgroundColor: const Color(0xFF1A1A1E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(
                '어떻게 시작할까요?',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
            _tile(ctx, '질문에 답해서 만들기', '기분·장면 열 가지만 고르면 곡이 나와요',
                NewProjectMode.ask, const Key('newProject.ask')),
            _tile(ctx, '두드려서 플레이', '장르 고르고 킥·스네어·하이햇을 직접 쳐서',
                NewProjectMode.doodle, const Key('newProject.doodle')),
            _tile(ctx, '처음부터 직접 만들기', '빈 씬·빈 타임라인에서 하나씩',
                NewProjectMode.scratch, const Key('newProject.scratch')),
          ],
        ),
      ),
    ),
  );
}

Widget _tile(
  BuildContext ctx,
  String title,
  String sub,
  NewProjectMode mode,
  Key key,
) {
  return ListTile(
    key: key,
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(sub, style: const TextStyle(fontSize: 11.5)),
    onTap: () => Navigator.pop(ctx, mode),
  );
}
