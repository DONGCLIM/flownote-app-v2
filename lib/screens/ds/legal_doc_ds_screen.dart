import 'package:flutter/material.dart';

import '../../design/fn_shell.dart';
import '../../design/fn_tokens.dart';
import '../../services/legal_documents.dart';

/// 약관 / 개인정보 처리방침 전문 보기.
enum LegalDocKind { terms, privacy, marketing }

class LegalDocDsScreen extends StatelessWidget {
  const LegalDocDsScreen({super.key, required this.kind});

  final LegalDocKind kind;

  String get _title => switch (kind) {
        LegalDocKind.terms => '서비스 이용약관',
        LegalDocKind.privacy => '개인정보 처리방침',
        LegalDocKind.marketing => '마케팅 정보 수신 동의',
      };

  String get _version => switch (kind) {
        LegalDocKind.terms => LegalDocs.termsVersion,
        LegalDocKind.privacy => LegalDocs.privacyVersion,
        LegalDocKind.marketing => LegalDocs.privacyVersion,
      };

  String get _body => switch (kind) {
        LegalDocKind.terms => LegalDocs.terms,
        LegalDocKind.privacy => LegalDocs.privacy,
        LegalDocKind.marketing => LegalDocs.marketing,
      };

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: _title,
      onBack: () => Navigator.of(context).pop(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: FnColors.rose99,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '버전 $_version',
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: FnColors.rose50,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 본문 — 마크다운 없이 순수 텍스트 렌더링 (##/### 헤더만 강조)
            ..._render(_body),
          ],
        ),
      ),
    );
  }

  /// 한국식 법령 문서 문단 렌더러.
  /// - 첫 줄 (`FlowNote ... (v1.0)`)        → 문서 타이틀
  /// - `제N조 (...)`                        → 조 제목 (굵게)
  /// - 그 외                                 → 본문
  List<Widget> _render(String src) {
    final out = <Widget>[];
    final lines = src.split('\n');
    final article = RegExp(r'^제\s?\d+\s?조');
    var seenTitle = false;

    for (final raw in lines) {
      final line = raw.trimRight();

      if (line.trim().isEmpty) {
        out.add(const SizedBox(height: 10));
        continue;
      }

      // 문서 제목 (본문 첫 유효 줄)
      if (!seenTitle) {
        seenTitle = true;
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            line,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: FnColors.labelNormal,
              height: 1.4,
            ),
          ),
        ));
        continue;
      }

      if (article.hasMatch(line.trimLeft())) {
        out.add(Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 2),
          child: Text(
            line,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: FnColors.labelNormal,
              height: 1.5,
            ),
          ),
        ));
        continue;
      }

      out.add(Text(
        line,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: FnColors.labelNeutral,
          height: 1.65,
        ),
      ));
    }
    return out;
  }
}
