import 'pwa_install_types.dart';

export 'pwa_install_types.dart';

/// 네이티브 구현 — 아무것도 하지 않는다.
///
/// 안드로이드/iOS 앱은 이미 "설치된" 상태다. 여기서 "바탕화면에 설치하기"
/// 를 안내하면 사장님이 혼란스러워지므로, 항상 `notWeb` 을 돌려줘서
/// 화면 쪽에서 안내를 아예 그리지 않게 한다.
void pwaInit() {}

PwaInstallState pwaState() => PwaInstallState.none;

Future<PwaPromptResult> pwaPromptInstall() async => PwaPromptResult.unavailable;

/// 카카오톡 인앱 → 외부 브라우저 넘기기. 앱에서는 할 일이 없다.
bool pwaOpenExternalBrowser() => false;

/// 화면이 아직 보이는가. 앱에서는 늘 보인다고 본다.
bool pwaPageVisible() => true;
