import 'package:flutter/material.dart';

import '../../design/fn_profile_tokens.dart';
import '../../design/fn_shell.dart';
import '../../services/notice_feed.dart';

/// 알림목록 화면 — 요청 #164 시안 1:1.
///
/// ## 시안 실측 (472x1024, 환산비 1.2103 → 390dp)
///
/// ```
///   배경            #FEF9F5
///   필터 칩         y 142.1..168.6dp (h 26.4)  좌 23.1dp  간격 7.4dp
///     켜짐          #FF6D78 바탕 + 흰 글자
///     꺼짐          흰 바탕 + #EFEEEA 테두리 + #5D5D5D 글자
///   목록 칸          h 100.0(한 줄) / 125.6(두 줄)   간격 11.6~12.4dp
///     바탕          #FEFDFB  (흰색이 아니다 — 배경보다 아주 살짝 밝다)
///     배지          h 18.3dp  좌 40.0dp  #FF6D78
///     제목          16dp/w700  좌 40.0dp
///     날짜          12dp       #76726F
///     읽지않음 점     지름 8.3dp  우측 끝 369.3dp
/// ```
///
/// ## 🔴 내용은 관리자만 바꾼다
///
/// 글 목록은 [NoticeFeed] 안의 코드 상수다. 이 화면에는 글을 쓰거나
/// 고치는 길이 **없다**. 사장님 지시대로 "우선 화면부터" 만들었고,
/// 앱에서 직접 공지를 쓰는 기능은 상의 후에 붙인다.
class NoticeListDsScreen extends StatefulWidget {
  const NoticeListDsScreen({super.key});

  @override
  State<NoticeListDsScreen> createState() => _NoticeListDsScreenState();
}

class _NoticeListDsScreenState extends State<NoticeListDsScreen> {
  /// null = '전체'.
  NoticeKind? _filter;

  @override
  void initState() {
    super.initState();
    NoticeFeed.instance.load();
  }

  @override
  Widget build(BuildContext context) {
    return FnShell(
      navTitle: '알림목록',
      bg: FnProfile.bg,
      onBack: () => Navigator.of(context).maybePop(),
      child: ListenableBuilder(
        listenable: NoticeFeed.instance,
        builder: (context, _) => _body(),
      ),
    );
  }

  Widget _body() {
    final all = NoticeFeed.instance.items;
    final shown =
        _filter == null ? all : all.where((e) => e.kind == _filter).toList();

    return ColoredBox(
      color: FnProfile.bg,
      child: SizedBox.expand(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _filters(),
            Expanded(
              child: shown.isEmpty
                  ? _empty()
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: shown.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: FnProfile.listGap),
                      itemBuilder: (_, i) => _tile(shown[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 필터 칩 줄. 시안 좌 23.1dp, 칩 사이 7.4dp.
  Widget _filters() {
    final chips = <(String, NoticeKind?)>[
      ('전체', null),
      for (final k in NoticeKind.values) (k.filterLabel, k),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(FnProfile.pad, 24, FnProfile.pad, 20),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < chips.length; i++) ...[
              if (i > 0) const SizedBox(width: FnProfile.chipGap),
              _chip(chips[i].$1, chips[i].$2),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, NoticeKind? kind) {
    final on = _filter == kind;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _filter = kind),
      child: Container(
        height: FnProfile.chipH,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? FnProfile.coral : Colors.white,
          borderRadius: BorderRadius.circular(FnProfile.chipH / 2),
          border: on ? null : Border.all(color: FnProfile.chipLine),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: FnProfile.chipFont,
            fontWeight: FontWeight.w600,
            color: on ? Colors.white : FnProfile.chipOffFg,
          ),
        ),
      ),
    );
  }

  /// 목록 한 칸.
  ///
  /// 시안에서 이것은 카드가 아니라 **좌우 끝까지 가는 띠**다. 모서리가
  /// 둥글지 않고 그림자도 없다. 칸과 칸 사이에만 배경색이 보인다.
  Widget _tile(NoticeItem n) {
    final read = NoticeFeed.instance.isRead(n.id);
    final lines = n.title.split('\n').length;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => NoticeFeed.instance.markRead(n.id),
      child: Container(
        constraints: BoxConstraints(
          minHeight: lines > 1 ? FnProfile.listRow2H : FnProfile.listRow1H,
        ),
        color: FnProfile.listTile,
        padding: const EdgeInsets.fromLTRB(
          FnProfile.listPadH,
          16,
          FnProfile.pad,
          16,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _badge(n.kind),
                  const SizedBox(height: 10),
                  Text(
                    n.title,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: FnProfile.listTitleFont,
                      fontWeight: FontWeight.w700,
                      height: 1.34,
                      color: FnProfile.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    n.ymd,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: FnProfile.listDateFont,
                      color: FnProfile.sub,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // 읽지 않은 글에만 점이 붙는다. 읽으면 사라진다.
            SizedBox(
              width: FnProfile.listDot,
              height: FnProfile.listDot,
              child: read
                  ? null
                  : const DecoratedBox(
                      decoration: BoxDecoration(
                        color: FnProfile.coral,
                        shape: BoxShape.circle,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(NoticeKind k) {
    // 🔴 `Align` 으로 감싼다. `Container` 에 `alignment` 를 주면 폭 제약이
    //    없을 때 **가로 전체로 늘어난다**(Flutter 문서화된 동작). 렌더를
    //    찍어 보고 나서야 배지가 화면 끝까지 늘어난 걸 발견했다.
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        height: FnProfile.listBadgeH,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: FnProfile.coral,
          borderRadius: BorderRadius.circular(FnProfile.listBadgeRadius),
        ),
        child: Text(
          k.label,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: FnProfile.listBadgeFont,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.only(bottom: 60),
        child: Text(
          '아직 받은 알림이 없어요',
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13.5,
            color: FnProfile.sub,
          ),
        ),
      ),
    );
  }
}
