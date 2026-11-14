import 'package:flutter/material.dart';

import '../../design/fn_shell.dart';
import '../../models/purchase_list_model.dart';
import '../../services/purchase_list_service.dart';
import '../../theme/fn_ds.dart';

/// 사입 메모장 — 시장에서 쓰는 화면. (시안 #179)
///
/// 🚧 **2단계에서 채운다.** 지금은 예산 검토에서 넘어올 자리만 잡아 두었다.
///    사장님 지시대로 단계마다 커밋하기 때문에, 1단계에서는 저장된 리스트를
///    받아 제목만 보여 준다.
///
/// 2단계에 붙일 것:
///   * "오늘 살 것" 체크리스트 (남은 품목·남은 예산, 큰 체크 버튼)
///   * 메모 카드 (이 리스트에 묶어 자동 저장)
/// 3단계: 길게 눌러 실제 가격 수정 · "못 샀어요"
/// 4단계: 스케치 저장 · 인터넷 끊김 대응
class PurchaseMemoDsScreen extends StatefulWidget {
  const PurchaseMemoDsScreen({super.key, required this.listId});

  /// 어느 사입 리스트를 펼칠지.
  final String listId;

  @override
  State<PurchaseMemoDsScreen> createState() => _PurchaseMemoDsScreenState();
}

class _PurchaseMemoDsScreenState extends State<PurchaseMemoDsScreen> {
  PurchaseList? get _list => PurchaseListService.instance.byId(widget.listId);

  @override
  void dispose() {
    // 화면을 나갈 때 아직 못 올린 것을 올린다. (사장님 지시)
    PurchaseListService.instance.flush();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return FnShell(
      navTitle: '사입 메모장',
      bg: FnDs.bg,
      onBack: () => Navigator.of(context).pop(),
      child: ColoredBox(
        color: FnDs.bg,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              FnDs.pagePad, 14, FnDs.pagePad, FnDs.gapXl),
          children: [
            const Text(
              '사입 갈 때 챙길 것과 주문 메모를 적고, 부케 모양이나 꽃 배치\n'
              '를 그려 기록해요.',
              style: FnDs.tsSub,
            ),
            const SizedBox(height: FnDs.gapM),
            if (list == null)
              const Text('사입 리스트를 찾지 못했어요.', style: FnDs.tsSub)
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(FnDs.cardPad),
                decoration: FnDs.cardDeco(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(list.purpose.isEmpty ? '사입 리스트' : list.purpose,
                        style: FnDs.tsSection),
                    const SizedBox(height: FnDs.gapXs),
                    Text('${list.items.length}개 품목', style: FnDs.tsSub),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
