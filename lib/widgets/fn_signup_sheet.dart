import 'package:flutter/material.dart';

import '../design/fn_controls_ds.dart';
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
