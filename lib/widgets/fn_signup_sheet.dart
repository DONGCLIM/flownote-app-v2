import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../design/fn_controls_ds.dart';
import '../design/fn_feedback.dart';
import '../design/fn_sheet.dart';
import '../providers/auth_provider.dart';
import '../providers/receipt_provider.dart';
import '../screens/ds/add_to_home_sheet.dart';
import '../screens/ds/legal_doc_ds_screen.dart';
import '../screens/ds/splash_ds_screen.dart';
import '../services/guest_migration.dart';
import '../services/guest_service.dart';
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
/// ## 버튼이 하는 일 (#195 ⑤ 에서 갈라졌다)
///
/// 🔴 `[구글로 가입]` — 체험 계정에 구글을 **붙인다**(`linkWithCredential`).
///    uid 가 그대로라 찍어 둔 영수증이 남는다. 로그인이 아니다.
/// 🔴 `[카카오로 가입]` — 기존 로그인 화면으로 보낸다. 카카오는 커스텀
///    토큰이라 uid 가 바뀐다. 영수증 옮기기는 **서버 함수가 필요해서**
///    다음 작업으로 미뤘다. 지금 붙이면 영수증이 사라진 것처럼 보인다.
/// 🔴 `이미 가입하셨나요? 로그인` — 기존 로그인 화면(카카오 포함).
///
/// 🔴 이 바텀시트는 **게스트일 때만** 뜬다. 부르는 쪽에서
///    `GuestService.instance.isGuest` 를 먼저 보고 부른다. 회원 흐름은
///    이 파일을 지나지 않는다.
const String kSignUpSheetTitle = '가입하면 쓸 수 있어요';

/// 가입·로그인 버튼이 **모두** 가는 곳. (#195)
///
/// 🔴 지금은 카카오·구글·로그인 셋 다 같은 화면으로 간다. 버튼마다 다른
///    길을 뚫어 두면 ⑤단계(계정 연결)에서 전부 다시 뜯어야 한다. 바꿀
///    때도 이 한 곳만 고치면 된다.
void fnOpenSignIn(BuildContext context) {
  Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(builder: (_) => const SplashDsScreen()),
  );
}

/// 체험 계정을 정식 계정으로 **전환**한다. 게스트 가입 버튼이 모두 여기로.
///
/// 🔴 **게스트일 때만 부른다.** 회원이 들어오면 첫 줄에서 그냥 돌아가므로,
///    가입하신 분의 로그인·가입 흐름은 이 함수를 지나지 않는다.
///
/// 하는 일:
///   1. `AuthProvider.linkGuestTo()` — 연결 + (기존과 같은) 동의 기록 ·
///      `users/{uid}` 문서 생성
///   2. 성공하면 체험 카운터를 치우고 '가입 완료' 안내 → 바탕화면 설치 안내
///   3. 이미 가입된 계정이면 **여쭙고** 고르실 때만 로그인
Future<void> fnLinkGuestAccount(
  BuildContext context,
  GuestLinkMethod method, {
  String email = '',
  String password = '',
  String displayName = '',
}) async {
  if (!GuestService.instance.isGuest) return;   // 🔴 회원은 여기 안 온다

  final auth = context.read<AuthProvider>();
  final r = await auth.linkGuestTo(
    method,
    email: email,
    password: password,
    displayName: displayName,
  );
  if (!context.mounted) return;

  switch (r) {
    case GuestLinkResult.ok:
      // 체험 카운터는 이제 뜻이 없다. 영수증은 그대로 남는다.
      GuestService.instance.clearAfterSignUp();
      await _afterSignUp(context);

    case GuestLinkResult.conflict:
      await _askSignInInstead(context, auth);

    case GuestLinkResult.cancelled:
      break;                                     // 조용히 — 사장님이 닫으셨다

    case GuestLinkResult.failed:
      final msg = auth.error;
      if (msg != null) {
        showFnToast(context, msg, type: FnToastType.error);
        auth.clearError();
      }
  }
}

/// 가입이 끝났다. 영수증이 남았다는 걸 먼저 알리고 설치로 이어 준다.
Future<void> _afterSignUp(BuildContext context) async {
  await showFnAlert(
    context,
    title: '가입 완료! 찍어둔 영수증이 저장됐어요',
    message: '바탕화면에 설치해 두면 다음부터 앱처럼 바로 열려요.',
    confirmLabel: '설치 안내 보기',
    cancelLabel: '나중에',
    icon: Icons.check_circle_rounded,
  ).then((go) async {
    if (!go || !context.mounted) return;
    await AddToHomeSheet.open(context);
  });
}

// ─────────────────────────────────────────────────────────────
//  체험 데이터 옮기기 (#195 ⑤-d)
//
//  🔴 **게스트일 때만** 이 길로 들어온다. 회원은 [fnRememberGuest] 가
//     아무것도 맡아 두지 않으므로, [fnRunGuestMigration] 이 첫 줄에서
//     조용히 끝난다. 기존 로그인 함수는 한 줄도 고치지 않았다.
// ─────────────────────────────────────────────────────────────

/// 로그인 **시작 전에** — 체험 계정의 ID 토큰을 맡아 둔다.
///
/// 카카오는 커스텀 토큰이라 로그인하는 순간 uid 가 바뀐다. 그 전에 받아
/// 두지 않으면 체험 계정을 증명할 길이 영영 사라진다.
///
/// 🔴 회원이 부르면 `false` 만 돌려주고 아무 일도 하지 않는다.
Future<bool> fnRememberGuest() => GuestMigration.instance.rememberGuest();

/// 로그인 **끝난 뒤에** — 맡아 둔 것이 있으면 서버에 옮겨 달라고 하고,
/// 결과에 따라 사장님께 알린다.
///
/// 세 갈래다.
///   · 옮김 — 기기 상자까지 옮기고 클라우드로 올린 뒤 '가입 완료' 안내
///   · 기존 회원 — 아무것도 옮기지 않았다고 알린다(체험 데이터는 보존)
///   · 실패 — 로그인은 그대로 두고 [다시 시도] 를 드린다(체험 데이터 보존)
Future<void> fnRunGuestMigration(BuildContext context) async {
  if (!GuestMigration.instance.hasPending) {
    // 웹 카카오는 페이지가 통째로 갔다 오므로 기억이 메모리에 없을 수 있다.
    await GuestMigration.instance.load();
    if (!GuestMigration.instance.hasPending) return;   // 🔴 회원은 여기서 끝
  }
  final guestUid = GuestMigration.instance.pendingGuestUid ?? '';
  final receipts = context.read<ReceiptProvider>();

  final r = await GuestMigration.instance.runIfPending();
  if (!context.mounted) return;

  switch (r.status) {
    case GuestMigrateStatus.none:
      return;

    case GuestMigrateStatus.moved:
      // ① 기기 안 상자부터 옮긴다. 화면에 바로 보여야 안심이 되신다.
      if (guestUid.isNotEmpty) await receipts.adoptGuestBox(guestUid);
      // ② 옮겨 담은 것을 클라우드로 올린다. 실패해도 기기에는 남는다.
      try {
        await receipts.pushAllToCloud();
      } catch (_) {/* 다음 실행의 자동 동기화가 마저 한다 */}
      // ③ 체험 카운터는 이제 뜻이 없다.
      GuestService.instance.clearAfterSignUp();
      if (!context.mounted) return;
      await _afterSignUpWithCount(context, r.receipts);

    case GuestMigrateStatus.skippedExisting:
      // 🔴 Hive 복사도 하지 않는다. 남의 장부에 체험 영수증이 섞인다.
      await showFnAlert(
        context,
        title: '기존 계정으로 로그인했어요',
        message: '체험으로 찍은 영수증 ${r.guestReceipts}장은 '
            '기존 계정에 옮기지 않았어요. 필요하면 다시 찍어 주세요.',
        confirmLabel: '확인',
        icon: Icons.info_outline_rounded,
      );

    case GuestMigrateStatus.failed:
      final again = await showFnAlert(
        context,
        title: '체험 영수증을 옮기지 못했어요.',
        message: '로그인은 그대로예요. 체험으로 찍은 영수증도 지우지 않았어요.',
        confirmLabel: '다시 시도',
        cancelLabel: '나중에',
        icon: Icons.error_outline_rounded,
      );
      if (!again || !context.mounted) return;
      await fnRunGuestMigration(context);               // 한 번 더
  }
}

/// 옮긴 장수를 넣은 '가입 완료' 안내.
///
/// 🔴 기존 [_afterSignUp] 은 그대로 둔다. 구글·애플·이메일은 uid 가
///    유지돼서 옮길 것이 없고, 장수를 말할 일도 없다.
Future<void> _afterSignUpWithCount(BuildContext context, int n) async {
  final go = await showFnAlert(
    context,
    title: '가입 완료! 찍어둔 영수증 $n장이 저장됐어요',
    message: '바탕화면에 설치해 두면 다음부터 앱처럼 바로 열려요.',
    confirmLabel: '설치 안내 보기',
    cancelLabel: '나중에',
    icon: Icons.check_circle_rounded,
  );
  if (!go || !context.mounted) return;
  await AddToHomeSheet.open(context);
}

/// "이미 가입된 계정이에요" — 바로 로그인하지 않고 여쭙는다.
///
/// 🔴 말없이 로그인하면 uid 가 바뀌어 체험 영수증이 **사라진 것처럼**
///    보인다. 그래서 반드시 고르시게 한다. 고르셔도 체험 데이터는
///    지우지 않는다(다음 작업에서 합친다).
Future<void> _askSignInInstead(
    BuildContext context, AuthProvider auth) async {
  final go = await showFnAlert(
    context,
    title: '이미 가입된 계정이에요',
    message: '이 계정으로 로그인할까요?',
    confirmLabel: '로그인',
    cancelLabel: '취소',
    icon: Icons.info_outline_rounded,
  );
  if (!context.mounted) return;
  if (!go) {
    auth.clearPendingLink();
    return;
  }
  // 🔴 로그인 **전에** 체험 토큰을 맡아 둔다. 로그인하는 순간 체험
  //    계정을 증명할 길이 사라진다. (게스트일 때만 맡아 둔다)
  await fnRememberGuest();
  final ok = await auth.signInWithConflicted();
  if (!context.mounted) return;
  if (ok) {
    // 로그인 자체는 성공했다. 체험 영수증 옮기기 결과는 따로 알린다.
    await fnRunGuestMigration(context);
    return;
  }
  final msg = auth.error;
  if (msg != null) {
    showFnToast(context, msg, type: FnToastType.error);
    auth.clearError();
  }
  // 자격이 없어 못 들어갔다면 평소 로그인 화면으로 보낸다.
  if (!auth.isLoggedIn) fnOpenSignIn(context);
}

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

  /// 기존 로그인 화면으로 보낸다. 바텀시트를 먼저 닫는다.
  ///
  /// 🔴 닫기와 이동에 쓰는 `Navigator` 가 서로 다르다. 바텀시트는 자기
  ///    라우트를 닫아야 하고(`Navigator.of(context)`), 화면 이동은 그
  ///    바깥 라우트에 쌓아야 한다. 그래서 바깥 것을 **닫기 전에** 미리
  ///    받아 둔다.
  void _toSignIn(BuildContext context) {
    final outer = context;
    Navigator.of(context).pop();
    fnOpenSignIn(outer);
  }

  /// 구글로 가입 — 체험 계정에 **붙인다.** uid 가 그대로라 영수증이 남는다.
  ///
  /// 🔴 바텀시트를 먼저 닫는다. 구글 팝업·안내창이 시트 위로 겹치면
  ///    눌러도 닿지 않는 자리가 생긴다.
  void _linkGoogle(BuildContext context) {
    final outer = context;
    Navigator.of(context).pop();
    unawaited(fnLinkGuestAccount(outer, GuestLinkMethod.google));
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
        // 🔴 카카오는 커스텀 토큰이라 uid 가 바뀐다. 붙이면 체험 영수증이
        //    사라진 것처럼 보이므로, 옮기는 서버 함수가 생기기 전까지는
        //    지금처럼 로그인 화면으로만 보낸다.
        FnPrimaryButton(
          label: '카카오로 가입',
          onTap: () => _toSignIn(context),
        ),
        const SizedBox(height: FnDs.gapS),
        // 구글은 **붙인다** — uid 가 그대로라 찍어 둔 영수증이 남는다.
        FnOutlineButton(
          label: '구글로 가입',
          onTap: () => _linkGoogle(context),
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
            Navigator.of(context).pop();
            fnOpenSignIn(context);
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
