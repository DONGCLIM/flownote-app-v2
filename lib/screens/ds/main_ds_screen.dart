import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/fn_shell.dart';
import '../../design/fn_home_tokens.dart';
import '../../design/fn_tab_intent.dart';
import '../../widgets/lazy_tabs.dart';
import '../../providers/receipt_provider.dart';
import '../../services/notice_feed.dart';
import '../../services/guest_service.dart';
import '../../services/purchase_list_service.dart';
import '../../widgets/fn_signup_sheet.dart';
import 'calendar_ds_screen.dart';
import 'home_ds_screen.dart';
import 'notice_list_ds_screen.dart';
import 'profile_ds_screen.dart';
import 'scan_ds_screen.dart';
import 'settle_ds_screen.dart';

/// 시안 `Shell` 기반 5탭 컨테이너.
///
/// 시안은 각 화면이 자기만의 Shell을 들고 있지만(React 프로토타입 특성),
/// 실앱에서는 Shell을 한 번만 두고 body만 교체해야 탭 전환 상태가 유지된다.
/// navTitle / activeTab은 시안 각 화면의 값과 동일하게 매핑한다.
///
/// | tab key  | navTitle | 시안 출처            |
/// |----------|----------|----------------------|
/// | home     | 홈       | AppH3   / home       |
/// | settle   | 내역     | AppH2   / main       |
/// | scan     | 스캔     | AppH1Mvp/ main       |
/// | calendar | 캘린더   | AppH7   / calendar   |
/// | profile  | 프로필   | AppH7   / profile    |
class MainDsScreen extends StatefulWidget {
  const MainDsScreen({super.key});

  @override
  State<MainDsScreen> createState() => _MainDsScreenState();
}

class _MainDsScreenState extends State<MainDsScreen> {
  int _index = 0;

  final _scanKey = GlobalKey<ScanDsScreenState>();

  /// 시안의 각 화면 navTitle
  /// home → '홈'(AppH3), settle → '구매 내역'(AppH2),
  /// scan → '스캔'(AppH1Mvp), calendar → '구매 캘린더'(AppH7),
  /// profile → '프로필'(AppH7)
  static const _titles = ['홈', '구매 내역', '스캔', '구매 캘린더', '프로필'];

  /// 탭 본문을 **필요할 때** 만든다.
  ///
  /// 리스트로 미리 만들어 두면 앱을 켜는 순간 5화면이 전부 build 돼서
  /// 첫 진입이 느려진다. 열어 본 탭만 만들고, 한 번 만든 뒤에는
  /// `_LazyTabs` 가 그대로 들고 있으므로 스크롤 위치·입력값은 유지된다.
  late final List<Widget Function()> _pageBuilders = [
    () => const HomeDsScreen(),
    () => const SettleDsScreen(),
    () => ScanDsScreen(key: _scanKey),
    () => const CalendarDsScreen(),
    () => const ProfileDsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // 로그인 후 첫 진입에서 클라우드 동기화를 한 번 시도한다.
    //  1) 기기 변경 복원 — 클라우드에만 있는 영수증을 내려받는다
    //  2) 로컬 백업 — 아직 안 올라간 영수증을 밀어올린다
    //  3) 사입 리스트 — 내려받고, 폰에만 있던 것은 올린다 (#191)
    // 모두 실패해도 앱 동작에는 영향이 없다 (Hive 가 진실의 원천).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // 🔴 #195 ⑤-d — 웹 카카오 로그인은 **페이지가 통째로 카카오로 갔다
      //    돌아오는** 방식이라, 로그인 요청과 완료가 서로 다른 실행에서
      //    일어난다. 돌아오면 앱이 처음부터 다시 뜨고 곧장 여기로 온다.
      //    그래서 맡겨 둔 체험 토큰이 있으면 여기서 마저 옮긴다.
      //
      //    맡겨 둔 것이 없으면(=회원이었다면) 첫 줄에서 조용히 돌아간다.
      //    가입하신 분에게는 아무 일도 일어나지 않는다.
      await fnRunGuestMigration(context);
      if (!mounted) return;

      final receipts = context.read<ReceiptProvider>();
      await receipts.restoreFromCloud();
      await receipts.pushAllToCloud();

      // 🔴 #191 에서 이었다. 전에는 `syncWithCloud()` 를 **아무도 안 불러서**
      //    PC 에서 적은 사입 리스트가 폰에 영영 안 보였다. 올리기만 하고
      //    내려받지 않았던 것이다.
      try {
        await PurchaseListService.instance.syncWithCloud();
      } catch (_) {
        // 인터넷이 없다. 폰 저장만으로 그대로 돈다.
      }
    });

    // 저장 완료 화면의 '캘린더 보기' 처럼, 깊은 화면에서 남긴
    // 탭 이동 요청을 받는다. (#113)
    FnTabIntent.pending.addListener(_onTabIntent);

    // 🔴 알림 벨의 빨간 점은 '안 읽은 알림이 있나' 로 정해진다.
    //    듣고 있지 않으면 알림을 읽어도 점이 그대로 남는다.
    NoticeFeed.instance.addListener(_onNotice);
    NoticeFeed.instance.load();
  }

  void _onNotice() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    FnTabIntent.pending.removeListener(_onTabIntent);
    NoticeFeed.instance.removeListener(_onNotice);
    super.dispose();
  }

  void _onTabIntent() {
    if (FnTabIntent.pending.value == null) return;
    // pop 애니메이션이 끝난 뒤에 바꿔야 전환이 자연스럽다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _applyTabIntent();
    });
  }


  /// 저장 완료 화면 등에서 "이 탭을 열어라" 고 남긴 요청을 처리한다.
  void _applyTabIntent() {
    final key = FnTabIntent.take();
    if (key == null) return;
    final i = fnTabs.indexWhere((t) => t.key == key);
    if (i < 0 || i == _index) return;
    setState(() => _index = i);
  }

  /// 알림 벨 — 알림목록 화면을 연다. (#164)
  ///
  /// 예전에는 '알림은 준비 중이에요' 스낵바였다. 화면이 생겼으므로
  /// 실제로 연결한다.
  void _onBell() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NoticeListDsScreen()),
    );
  }

  /// 게스트에게 잠긴 탭. 잠겼으면 **기능 한 줄 설명**을 준다. (#195)
  ///
  /// 🔴 홈의 `_push()` 와 달리 캘린더는 **탭바**로 열린다. 그래서 홈 쪽
  ///    잠금이 여기까지 닿지 않았고, 이 자리에 따로 붙였다.
  ///
  /// 🔴 잠그는 건 캘린더 하나뿐이다. 홈·내역·스캔·프로필은 체험해 보셔야
  ///    가입할 마음이 들기 때문에 일부러 열어 둔다.
  static String? _guestLockLine(String key) {
    if (key == 'calendar') {
      return '어느 날 얼마나 사입했는지 달력 위에서 한눈에 보여 드려요';
    }
    return null;
  }

  void _onTab(String key) {
    final i = fnTabs.indexWhere((t) => t.key == key);
    if (i < 0) return;

    // 🔴 **게스트일 때만** 갈라진다. 회원은 아래로 그대로 내려가 탭이 바뀐다.
    //    탭을 바꾸기 **전에** 막아야 캘린더가 한 번 보였다 사라지지 않는다.
    if (GuestService.instance.isGuest) {
      final line = _guestLockLine(key);
      if (line != null) {
        unawaited(showFnSignUpSheet(context, feature: line));
        return;
      }
    }

    // 스캔 탭을 이미 보고 있는 상태에서 다시 누르면 촬영 시트를 연다.
    if (i == 2 && _index == 2) {
      _scanKey.currentState?.showCameraOptions();
      return;
    }
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    return FnShell(
      // #136 시안 — 제목 대신 워드마크 + 알림 벨, 탭바는 떠 있는 흰 카드.
      //   `navTitle` 은 그대로 넘긴다. `brandHeader` 를 끄면 즉시
      //   예전 제목 헤더로 돌아간다 (되돌리기 쉽게 남겨 둔다).
      navTitle: _titles[_index],
      brandHeader: true,
      // 🔴 안 읽은 알림이 있을 때만 빨간 점을 찍는다.
      //    전에는 늘 true 라 읽어도 점이 사라지지 않았다.
      bellDot: NoticeFeed.instance.hasUnread,
      onBellTap: _onBell,
      floatingTabs: true,
      bg: FnHome.bgWarm,
      tabs: fnTabs,
      activeTab: fnTabs[_index].key,
      onTabChange: _onTab,
      // 🔴 예전에는 `IndexedStack(index: _index, children: _pages)` 였다.
      //    IndexedStack 은 안 보이는 자식도 트리에 살려 두는데, 그 자식들이
      //    `context.watch<ReceiptProvider>()` 를 하고 있었다. 그래서
      //    영수증을 저장하고 뒤로 나올 때 `notifyListeners()` 한 번에
      //    **5개 탭이 전부 다시 build** 됐다. (직접 셌다: 재build 5/5,
      //    트리에 살아있던 Element 7,141개)
      //
      //    화면 전환 애니메이션이 도는 중에 그 일이 겹치니까 뒤로가기
      //    직후가 유난히 굼떴다. `_LazyTabs` 는 (1) 한 번이라도 열어 본
      //    탭만 만들고, (2) 지금 보이지 않는 탭은 rebuild 를 건너뛴다.
      child: LazyTabs(index: _index, builders: _pageBuilders),
    );
  }
}
