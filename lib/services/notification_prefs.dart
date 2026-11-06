import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 알림 설정 다섯 가지를 저장·복원한다. (요청 #141)
///
/// 시안(`알림 설정` 화면)의 항목 그대로다.
///
/// ```
///   서비스 알림
///     영수증 처리 알림   receipt    기본 켜짐
///     정산·신고 알림     settle     기본 켜짐
///     경영 리포트        report     기본 켜짐
///     공지사항           notice     기본 켜짐
///   혜택 알림
///     이벤트 및 혜택      event      기본 꺼짐
/// ```
///
/// 🔴 기본값을 임의로 정하지 않았다. 시안의 토글 상태를 픽셀로 읽어
///    그대로 맞췄다 — 위 네 개는 코랄(#FF6D78, 켜짐), 마지막 하나만
///    회색(#E5E5E5, 꺼짐)이었다.
///
/// 🔴 마케팅성 알림(`event`)만 기본 꺼짐인 이유: 정보통신망법상 광고성
///    정보는 **사전 동의**가 필요하다. 기본으로 켜 두면 동의 없이 보내는
///    셈이 된다. 서비스 알림은 거래 관계에 따른 안내라 기본 켜짐이 맞다.
///
/// 저장은 `SharedPreferences` 를 쓴다. (`ApiKeyService` 와 같은 방식)
/// 서버 동기화는 하지 않는다 — 기기마다 다르게 두는 편이 자연스럽고,
/// 서버로 올리면 동의 이력 관리 대상이 되어 범위가 커진다.
class NotificationPrefs extends ChangeNotifier {
  NotificationPrefs._();

  static final NotificationPrefs instance = NotificationPrefs._();

  /// 설정 한 칸.
  ///
  /// `key` 는 저장소 키의 일부이므로 **절대 바꾸지 않는다.** 바꾸면
  /// 기존 사용자의 설정이 초기화된다.
  static const List<NotificationOption> options = [
    NotificationOption(
      key: 'receipt',
      group: '서비스 알림',
      title: '영수증 처리 알림',
      desc: '스캔과 장부 정리 결과를 알려드려요.',
      defaultOn: true,
    ),
    NotificationOption(
      key: 'settle',
      group: '서비스 알림',
      title: '정산·신고 알림',
      desc: '다가오는 정산과 신고 일정을 알려드려요.',
      defaultOn: true,
    ),
    NotificationOption(
      key: 'report',
      group: '서비스 알림',
      title: '경영 리포트',
      desc: '매출과 지출 요약을 받아보세요.',
      defaultOn: true,
    ),
    NotificationOption(
      key: 'notice',
      group: '서비스 알림',
      title: '공지사항',
      desc: '업데이트와 주요 소식을 알려드려요.',
      defaultOn: true,
    ),
    NotificationOption(
      key: 'event',
      group: '혜택 알림',
      title: '이벤트 및 혜택',
      desc: '프로모션과 새로운 혜택을 알려드려요.',
      defaultOn: false,
    ),
  ];

  static String _prefKey(String key) => 'notif_pref_$key';

  final Map<String, bool> _values = {};
  bool _loaded = false;

  /// 저장소에서 한 번 읽었는가. 읽기 전에는 기본값을 쓴다.
  bool get loaded => _loaded;

  /// 해당 설정이 켜져 있는가. 저장된 값이 없으면 기본값.
  bool isOn(String key) {
    final v = _values[key];
    if (v != null) return v;
    for (final o in options) {
      if (o.key == key) return o.defaultOn;
    }
    return false;
  }

  /// 저장소에서 읽어 온다. 화면이 열릴 때 한 번 부른다.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final o in options) {
        final v = prefs.getBool(_prefKey(o.key));
        if (v != null) _values[o.key] = v;
      }
    } catch (_) {
      // 🔴 저장소를 못 읽어도 화면은 떠야 한다. 기본값으로 둔다.
      //    (웹에서 사생활 보호 모드면 실패할 수 있다)
    }
    _loaded = true;
    notifyListeners();
  }

  /// 값을 바꾸고 바로 저장한다.
  ///
  /// 시안 문구가 `설정은 변경하는 즉시 저장돼요.` 이므로 별도 저장
  /// 버튼을 두지 않는다. 화면은 저장 성공을 기다리지 않고 즉시
  /// 바뀐다(낙관적 갱신) — 토글이 손가락을 따라오지 않으면 고장처럼
  /// 느껴진다.
  Future<void> set(String key, bool on) async {
    if (_values[key] == on) return;
    _values[key] = on;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKey(key), on);
    } catch (_) {
      // 저장 실패는 조용히 넘긴다. 다음에 다시 켜면 또 시도한다.
    }
  }

  /// 테스트에서 상태를 비우는 용도.
  @visibleForTesting
  void resetForTest() {
    _values.clear();
    _loaded = false;
  }
}

/// 알림 설정 한 항목의 정의.
class NotificationOption {
  const NotificationOption({
    required this.key,
    required this.group,
    required this.title,
    required this.desc,
    required this.defaultOn,
  });

  /// 저장소 키. **바꾸면 기존 설정이 초기화된다.**
  final String key;

  /// 묶음 제목. 시안은 `서비스 알림` / `혜택 알림` 두 묶음이다.
  final String group;

  final String title;
  final String desc;
  final bool defaultOn;
}
