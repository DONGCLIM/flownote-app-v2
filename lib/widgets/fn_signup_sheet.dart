import 'package:flutter/material.dart';

import '../design/fn_controls_ds.dart';
import '../screens/ds/legal_doc_ds_screen.dart';
import '../screens/ds/splash_ds_screen.dart';
import '../theme/fn_ds.dart';
import 'fn_inquiry_parts.dart';

/// 게스트가 잠긴 기능을 눌렀을 때 뜨는 **공용 가입 안내 바텀시트**. (#195)
///
/// ## 왜 하나로 모았나
///
/// 잠긴 자리가 열 곳이 넘는다(월별 인사이트·품목별 분석·사입 리스트·
/// 원가 계산기·PDF 저장…). 자리마다 안내를 따로 그리면 문구와 버튼이
/// 금세 어긋난다. 그래서 **한 줄 설명만 자리별로 받고** 나머지(버튼·
/// 로그인 링크)는 여기 한 곳에서 그린다.
///
/// ## 지금 단계에서 버튼이 하는 일
///
/// 🔴 `[카카오로 가입]` `[구글로 가입]` `이미 가입하셨나요? 로그인` —
///    셋 다 **기존 로그인 화면([SplashDsScreen])으로 보낸다.** 게스트
///    계정을 그대로 들고 가입하는 계정 연결은 ⑤단계
///    일이라 아직 없다. 지금 버튼마다 다른 길을 뚫어 두면 ⑤에서 전부
///    다시 뜯어야 해서, 한 길로 모아 뒀다.
///
/// 🔴 이 바텀시트는 **게스트일 때만** 뜬다. 부르는 쪽에서
///    `GuestService.instance.isGuest` 를 먼저 보고 부른다. 회원 흐름은
///    이 파일을 지나지 않는다.
const String kSignUpSheetTitle = '가입하면 쓸 수 있어요';

/// 가입 안내 바텀시트를 띄운다.
///
/// [feature] 는 **기능 한 줄 설명**이다. 예: '지난달과 이번 달 지출을
/// 한눈에 비교해 드려요'. 비워 두면 기본 문구가 나간다.
Future<void> showFnSignUpSheet(
  BuildContext context, {
  String feature = '',
}) {
  final line = feature.trim().isEmpty
      ? '가입하시면 바로 쓰실 수 있어요'
      : feature.trim();
  return showFnDsBottomSheet<void>(
    context,
    title: kSignUpSheetTitle,
    child: _SignUpSheetBody(line: line),
  );
}

class _SignUpSheetBody extends StatelessWidget {
  const _SignUpSheetBody({required this.line});

  final String line;

  /// 세 버튼이 모두 같은 곳으로 간다. 바텀시트를 먼저 닫고 보낸다.
  ///
  /// 🔴 닫기와 이동에 쓰는 `Navigator` 가 서로 다르다. 바텀시트는 자기
  ///    라우트를 닫아야 하고(`Navigator.of(context)`), 화면 이동은 그
  ///    바깥 라우트에 쌓아야 한다. 그래서 바깥 것을 **닫기 전에** 미리
  ///    받아 둔다.
  void _toSignIn(BuildContext context) {
    final outer = Navigator.of(context, rootNavigator: true);
    Navigator.of(context).pop();
    outer.push(MaterialPageRoute<void>(
      builder: (_) => const SplashDsScreen(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          line,
          style: const TextStyle(
            fontFamily: FnDs.font,
            fontSize: FnDs.fontM,
            height: 1.45,
            color: FnDs.body,
          ),
        ),
        const SizedBox(height: FnDs.gapL),
        FnPrimaryButton(
          label: '카카오로 가입',
          onTap: () => _toSignIn(context),
        ),
        const SizedBox(height: FnDs.gapS),
        FnOutlineButton(
          label: '구글로 가입',
          onTap: () => _toSignIn(context),
        ),
        const SizedBox(height: FnDs.gapM),
        Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _toSignIn(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: FnDs.gap2xs),
              child: Text(
                '이미 가입하셨나요? 로그인',
                style: TextStyle(
                  fontFamily: FnDs.font,
                  fontSize: FnDs.fontS,
                  fontWeight: FontWeight.w600,
                  color: FnDs.sub,
                  decoration: TextDecoration.underline,
                  decorationColor: FnDs.sub,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 첫 스캔 전 안내 · 첫 스캔 성공 안내 (#195)
// ─────────────────────────────────────────────────────────────

/// 첫 스캔 **전에 한 번** 띄우는 안내. 동의해야 스캔으로 넘어간다.
const String kTrialConsentTitle = '체험으로 찍어 보기 전에';

/// 첫 스캔이 **성공한 직후 한 번** 띄우는 안내. 그냥 닫을 수 있다.
const String kFirstScanDoneTitle = '잘 읽혔나요?';

/// 체험 영수증 보관 안내 + 개인정보 처리방침 링크.
///
/// 🔴 돌려주는 값은 **동의했는가**다. 시트를 쓸어 내려 닫으면 false 가
///    되고, 부르는 쪽에서 스캔을 시작하지 않는다. 동의 없이 찍게 두면
///    안내를 한 뜻이 없다.
///
/// 🔴 게스트일 때만 부른다. 회원은 가입할 때 이미 동의를 받았다.
Future<bool> showFnTrialConsentSheet(BuildContext context) async {
  final ok = await showFnDsBottomSheet<bool>(
    context,
    title: kTrialConsentTitle,
    child: const _TrialConsentBody(),
  );
  return ok ?? false;
}

class _TrialConsentBody extends StatelessWidget {
  const _TrialConsentBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '체험으로 찍은 영수증은 가입하지 않으면 30일 뒤 삭제돼요',
          style: TextStyle(
            fontFamily: FnDs.font,
            fontSize: FnDs.fontM,
            height: 1.45,
            color: FnDs.body,
          ),
        ),
        const SizedBox(height: FnDs.gapS),
        Align(
          alignment: Alignment.centerLeft,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const LegalDocDsScreen(kind: LegalDocKind.privacy),
              ),
            ),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: FnDs.gap2xs),
              child: Text(
                '개인정보 처리방침 보기',
                style: TextStyle(
                  fontFamily: FnDs.font,
                  fontSize: FnDs.fontS,
                  fontWeight: FontWeight.w600,
                  color: FnDs.coral,
                  decoration: TextDecoration.underline,
                  decorationColor: FnDs.coral,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: FnDs.gapL),
        FnPrimaryButton(
          label: '확인하고 찍기',
          // 🔴 `pop(true)` 여야 부르는 쪽이 스캔을 시작한다.
          onTap: () => Navigator.of(context).pop(true),
        ),
      ],
    );
  }
}

/// 첫 스캔이 성공한 직후 한 번. 가입을 권하되 **닫을 수 있다.**
///
/// 🔴 여기서 길을 막으면 방금 잘 된 경험이 바로 광고로 바뀐다.
///    닫기를 먼저 둔 이유다.
Future<void> showFnFirstScanDoneSheet(BuildContext context) {
  return showFnDsBottomSheet<void>(
    context,
    title: kFirstScanDoneTitle,
    child: const _FirstScanDoneBody(),
  );
}

class _FirstScanDoneBody extends StatelessWidget {
  const _FirstScanDoneBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '가입하면 계속 저장돼요',
          style: TextStyle(
            fontFamily: FnDs.font,
            fontSize: FnDs.fontM,
            height: 1.45,
            color: FnDs.body,
          ),
        ),
        const SizedBox(height: FnDs.gapL),
        FnPrimaryButton(
          label: '가입하고 계속 쓰기',
          onTap: () {
            final outer = Navigator.of(context, rootNavigator: true);
            Navigator.of(context).pop();
            outer.push(MaterialPageRoute<void>(
              builder: (_) => const SplashDsScreen(),
            ));
          },
        ),
        const SizedBox(height: FnDs.gapS),
        FnOutlineButton(
          label: '나중에',
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
