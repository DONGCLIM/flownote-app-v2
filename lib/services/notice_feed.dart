import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 알림목록에 뜨는 한 건.
@immutable
class NoticeItem {
  const NoticeItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.date,
  });

  /// 읽음 표시를 저장할 때 쓰는 고유 키. 🔴 한 번 정하면 바꾸지 않는다.
  /// 바꾸면 사장님이 이미 읽은 글이 다시 '읽지 않음' 으로 돌아간다.
  final String id;

  final NoticeKind kind;

  /// 제목. 줄바꿈(`\n`) 을 넣으면 시안처럼 두 줄로 나온다.
  final String title;

  /// 올린 날짜.
  final DateTime date;

  /// 시안 표기 `26.09.18`.
  String get ymd {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(date.year % 100)}.${two(date.month)}.${two(date.day)}';
  }
}

/// 분류. 시안 필터 칩과 1:1 로 맞춘다.
enum NoticeKind {
  /// 서비스가 보내는 알림.
  alert('알림'),

  /// 운영 공지.
  notice('공지'),

  /// 이벤트·혜택.
  event('이벤트');

  const NoticeKind(this.label);

  /// 배지에 찍히는 글자.
  final String label;

  /// 필터 칩에 찍히는 글자. 공지만 배지(`공지`)와 칩(`공지사항`)이 다르다.
  String get filterLabel => this == NoticeKind.notice ? '공지사항' : label;
}

/// 알림목록의 내용과 읽음 상태.
///
/// ## 🔴 지금은 내용을 **코드에서만** 바꿀 수 있다
///
/// 사장님 요청(#164): "관리자인 나만 이 내용을 써서 업데이트 시킬 수
/// 있도록" — 맞는 방향이다. 다만 사장님이 "우선은 앱 화면부터 만들어주고
/// 추가적으로 기능을 만들어야한다면 나랑 상의한 후에 진행해줘" 라고
/// 하셨으므로, **글을 쓰는 화면이나 서버 연동은 아직 만들지 않았다.**
///
/// 그래서 지금 구조는 이렇다.
///
/// * 내용 = 아래 [_seed] 목록. 새 공지를 올리려면 이 목록에 한 줄
///   추가하고 앱을 다시 배포한다. 일반 사용자는 어떤 경로로도 글을
///   쓰거나 고칠 수 없다 — 쓰기 함수 자체가 없다.
/// * 읽음 표시 = 기기에만 저장한다([SharedPreferences]). 읽었다는 사실은
///   남한테 보여줄 정보가 아니라서 서버에 올리지 않는다.
///
/// 나중에 사장님이 "앱에서 바로 공지를 쓰고 싶다" 고 하시면 그때
/// Firestore `notices` 컬렉션 + 관리자 전용 작성 화면을 붙이면 된다.
/// 그 작업은 **승인받고 나서** 한다.
class NoticeFeed extends ChangeNotifier {
  NoticeFeed._();

  static final NoticeFeed instance = NoticeFeed._();

  static const String _readKey = 'notice_read_ids';

  /// 관리자가 올린 글 목록. 최신이 위.
  ///
  /// 🔴 새 글을 올릴 때 지켜야 할 것
  ///   1. `id` 는 절대 재사용하지 않는다 (읽음 표시가 엉킨다).
  ///   2. 맨 **앞**에 넣는다. 화면은 이 순서를 그대로 쓴다.
  static final List<NoticeItem> _seed = <NoticeItem>[
    NoticeItem(
      id: 'n-2026-09-18-update',
      kind: NoticeKind.notice,
      title: '플로우노트 업데이트 안내',
      date: _d20260918,
    ),
    NoticeItem(
      id: 'n-2026-09-18-trial',
      kind: NoticeKind.event,
      title: '한달 무료체험으로\n부담없이 이용해보세요',
      date: _d20260918,
    ),
    NoticeItem(
      id: 'n-2026-09-18-camera',
      kind: NoticeKind.notice,
      title: '영수증 촬영 오류 해결 안내',
      date: _d20260918,
    ),
    NoticeItem(
      id: 'n-2026-09-18-report',
      kind: NoticeKind.alert,
      title: '이번달 점검 결과가 나왔어요!\n지금 바로 확인해보세요.',
      date: _d20260918,
    ),
    NoticeItem(
      id: 'n-2026-09-18-sales',
      kind: NoticeKind.alert,
      title: '8월 매출 총 매입을\n확인해보세요.',
      date: _d20260918,
    ),
  ];

  /// 🔴 `DateTime` 에는 const 생성자가 없다. 그래서 [_seed] 도
  ///    `const` 가 아니라 `final` 이다.
  static final DateTime _d20260918 = DateTime(2026, 9, 18);

  /// 화면에 보여 줄 목록.
  List<NoticeItem> get items => _seed;

  Set<String> _read = <String>{};
  bool _loaded = false;

  bool get loaded => _loaded;

  /// 아직 안 읽은 글이 하나라도 있나. 프로필 종(bell) 의 빨간 점에 쓴다.
  bool get hasUnread => _seed.any((e) => !_read.contains(e.id));

  /// 안 읽은 글 수.
  int get unreadCount => _seed.where((e) => !_read.contains(e.id)).length;

  bool isRead(String id) => _read.contains(id);

  Future<void> load() async {
    if (_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      _read = (p.getStringList(_readKey) ?? const <String>[]).toSet();
    } catch (_) {
      // 저장소를 못 읽어도 화면은 떠야 한다. 전부 '읽지 않음' 으로 본다.
      _read = <String>{};
    }
    _loaded = true;
    notifyListeners();
  }

  /// 한 건을 읽음으로 표시한다.
  Future<void> markRead(String id) async {
    if (_read.contains(id)) return;
    _read = <String>{..._read, id};
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_readKey, _read.toList());
    } catch (_) {
      // 저장 실패는 조용히 넘어간다. 다음에 다시 '읽지 않음' 으로 보일 뿐이다.
    }
  }

  /// 전부 읽음.
  Future<void> markAllRead() async {
    final all = _seed.map((e) => e.id).toSet();
    if (_read.containsAll(all)) return;
    _read = <String>{..._read, ...all};
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_readKey, _read.toList());
    } catch (_) {
      // 위와 같다.
    }
  }

  @visibleForTesting
  void resetForTest() {
    _read = <String>{};
    _loaded = false;
  }
}
