import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/fn_shell.dart';
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

  late final List<Widget> _pages = [
    const HomeDsScreen(),
    const SettleDsScreen(),
    ScanDsScreen(key: _scanKey),
    const CalendarDsScreen(),
    const ProfileDsScreen(),
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
      child: IndexedStack(index: _index, children: _pages),
    );
  }
}
