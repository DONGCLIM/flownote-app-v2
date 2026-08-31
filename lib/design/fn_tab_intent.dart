import 'package:flutter/foundation.dart';

/// 깊은 화면에서 "루트로 나간 뒤 이 탭을 열어라" 를 전달하는 통로.
///
/// ## 🔴 왜 필요했나 — #113 캘린더 보기 버튼이 안 먹던 이유
///
/// 저장 완료 화면(`ScanDoneDsScreen`) 의 두 버튼은 이렇게 되어 있었다:
///
/// ```dart
/// void _home()     { ... Navigator.of(context).popUntil((r) => r.isFirst); }
/// void _calendar() { ... Navigator.of(context).popUntil((r) => r.isFirst); }
/// ```
///
/// `onGoHome` / `onGoCalendar` 콜백을 받도록 만들어 두긴 했는데,
/// 유일한 호출부(`scan_review_ds_screen.dart`)가 둘 다 넘기지 않았다.
/// 그래서 **두 버튼이 완전히 같은 동작**(루트까지 pop)을 했다.
/// 캘린더 보기를 눌러도 스캔 탭으로 돌아갈 뿐이라, 사장님 눈에는
/// "전환이 안 된다" 로 보였던 것이다.
///
/// ## 왜 이 방식인가
///
/// 앱에 named route 가 없고(`MaterialPageRoute` 직접 push 73곳),
/// 탭 인덱스는 `_MainDsScreenState` 의 private 필드다. 깊은 화면에서
/// 거기까지 닿으려면 (1) 전역 통로, (2) 모든 push 에 콜백 릴레이,
/// (3) InheritedWidget 중 하나가 필요하다. (2)는 손댈 파일이 너무
/// 많고 빠뜨리기 쉽다. (3)은 pop 후에는 이미 context 가 죽어 있어
/// 곤란하다. 그래서 값 하나만 들고 있는 (1)로 했다.
class FnTabIntent {
  FnTabIntent._();

  /// 루트로 돌아간 직후 열어야 할 탭 키. 소비되면 null 로 비워진다.
  static final ValueNotifier<String?> pending = ValueNotifier<String?>(null);

  /// [key] 탭을 열어 달라고 요청한다. (예: `'calendar'`)
  static void request(String key) => pending.value = key;

  /// 요청을 꺼내 간다. 두 번 읽어도 두 번 이동하지 않도록 비운다.
  static String? take() {
    final v = pending.value;
    pending.value = null;
    return v;
  }
}
