import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/fn_shell.dart';
import '../../design/fn_tab_intent.dart';
import '../../widgets/lazy_tabs.dart';
import '../../providers/receipt_provider.dart';
import 'calendar_ds_screen.dart';
import 'home_ds_screen.dart';
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
    // 둘 다 실패해도 앱 동작에는 영향이 없다 (Hive 가 진실의 원천).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final receipts = context.read<ReceiptProvider>();
      await receipts.restoreFromCloud();
      await receipts.pushAllToCloud();
    });

    // 저장 완료 화면의 '캘린더 보기' 처럼, 깊은 화면에서 남긴
    // 탭 이동 요청을 받는다. (#113)
    FnTabIntent.pending.addListener(_onTabIntent);
  }

  @override
  void dispose() {
    FnTabIntent.pending.removeListener(_onTabIntent);
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

  void _onTab(String key) {
    final i = fnTabs.indexWhere((t) => t.key == key);
    if (i < 0) return;
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
      navTitle: _titles[_index],
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
