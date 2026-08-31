import 'pwa_install_types.dart';

export 'pwa_install_types.dart';

/// 네이티브 구현 — 아무것도 하지 않는다.
///
/// 안드로이드/iOS 앱은 이미 "설치된" 상태다. 여기서 "홈 화면에 추가"
/// 를 안내하면 사장님이 혼란스러워지므로, 항상 `notWeb` 을 돌려줘서
/// 화면 쪽에서 안내를 아예 그리지 않게 한다.
void pwaInit() {}

PwaInstallState pwaState() => PwaInstallState.none;

Future<PwaPromptResult> pwaPromptInstall() async => PwaPromptResult.unavailable;
