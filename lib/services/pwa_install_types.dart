/// "홈 화면에 추가" 안내에 필요한 공용 타입.
///
/// 웹 구현(`pwa_install_web.dart`)과 네이티브 구현(`pwa_install_stub.dart`)
/// 이 **같은 타입**을 써야 하므로, 조건부 import 를 타지 않는 별도 파일에
/// 둔다. 여기에 두지 않고 양쪽에 각각 선언하면 플랫폼마다 다른 타입이
/// 되어버려서 화면 코드가 컴파일되지 않는다.
library;

/// 지금 브라우저가 어떤 방식으로 "홈 화면에 추가" 를 지원하는가.
enum PwaHowTo {
  /// 웹이 아니다 (네이티브 앱). 안내 자체가 필요 없다.
  notWeb,

  /// 이미 홈 화면에서 실행 중이다. 안내가 필요 없다.
  alreadyInstalled,

  /// 안드로이드 크롬 계열 — 브라우저가 설치 프롬프트를 지원한다.
  /// `pwaPromptInstall()` 로 바로 설치창을 띄울 수 있다.
  androidPrompt,

  /// 안드로이드지만 프롬프트를 아직(또는 전혀) 못 받은 경우.
  /// 메뉴(⋮) → "홈 화면에 추가" 를 손으로 안내한다.
  androidManual,

  /// 아이폰/아이패드 사파리 — 프롬프트 API 가 없다.
  /// 공유 버튼 → "홈 화면에 추가" 를 손으로 안내해야 한다.
  iosSafari,

  /// 아이폰/아이패드인데 사파리가 아니다 (크롬·네이버 앱 등).
  /// 이 브라우저들은 홈 화면 추가가 안 되므로 사파리로 열라고 안내한다.
  iosOther,

  /// PC 브라우저. 주소창 설치 아이콘을 안내한다.
  desktop,

  /// 판별 실패. 일반 안내만 보여준다.
  unknown,
}

/// 설치 프롬프트 호출 결과.
enum PwaPromptResult {
  /// 사용자가 설치를 눌렀다.
  installed,

  /// 사용자가 취소했다.
  dismissed,

  /// 프롬프트를 쓸 수 없다 (이벤트 미수신, 웹 아님 등).
  unavailable,
}

/// 현재 상태 묶음.
class PwaInstallState {
  const PwaInstallState({
    required this.howTo,
    required this.canPrompt,
  });

  final PwaHowTo howTo;

  /// `pwaPromptInstall()` 을 눌러도 되는가.
  final bool canPrompt;

  /// "홈 화면에 추가" 안내를 보여줄 이유가 있는가.
  bool get shouldGuide =>
      howTo != PwaHowTo.notWeb && howTo != PwaHowTo.alreadyInstalled;

  static const none =
      PwaInstallState(howTo: PwaHowTo.notWeb, canPrompt: false);
}
