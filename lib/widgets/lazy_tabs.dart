import 'package:flutter/material.dart';

/// 탭 본문 컨테이너. `IndexedStack` 을 대체한다.
///
/// ## 하는 일 — **지연 생성**
///
/// 한 번도 안 열어 본 탭은 아예 만들지 않는다. 앱을 처음 켤 때
/// 5화면이 아니라 1화면만 build 되므로 첫 진입이 가벼워진다.
/// 한 번 만든 탭은 계속 트리에 남으므로 스크롤 위치·입력값·필터 선택은
/// 유지된다.
///
/// ## 🔴 하지 못하는 일 — 솔직히 적어 둔다
///
/// 처음에는 "안 보이는 탭은 rebuild 를 건너뛴다" 고 적었는데 **틀렸다.**
/// `_KeepAlive` 가 위젯 인스턴스를 재사용해도, 자식 안에서
/// `context.watch<T>()` 를 하면 그 **element 가 직접** provider 를
/// 구독한다. 부모가 위젯을 재사용하는 것과는 무관하게 알림이 오면
/// 그 element 는 dirty 로 표시되고 다시 build 된다.
///
/// 직접 재본 값 (`context.watch` 하는 탭 3개, 보이는 탭은 0번):
///
/// ```
/// ▶ notifyListeners 1회 후 재build: {0: 1, 2: 1, 1: 1}
/// ▶ 숨은 탭(1,2)이 다시 그려졌는가? 예
/// ```
///
/// 그래서 "탭 재build 를 막는다" 는 방향은 **포기했다.** 대신
/// [ReceiptProvider] 쪽에서 근본 비용을 줄였다:
///
/// - `allReceipts` 결과 캐시 (1000건 12회 호출 25ms -> 0에 가깝게)
/// - `batch()` 로 여러 건 저장 시 알림을 4회 -> 1회로 묶음
///
/// 숨은 탭을 아예 트리에서 내리는 방법(활성 탭만 mount)도 재봤다.
/// 재build 는 `{0: 1}` 로 완벽히 막히지만, 구매내역의 필터·정렬 선택과
/// 캘린더의 보고 있던 연/월이 전부 초기화된다. 그 대가가 더 크다고 보고
/// 쓰지 않았다.
class LazyTabs extends StatefulWidget {
  const LazyTabs({
    super.key,
    required this.index,
    required this.builders,
  });

  final int index;
  final List<Widget Function()> builders;

  @override
  State<LazyTabs> createState() => _LazyTabsState();
}

class _LazyTabsState extends State<LazyTabs> {
  /// 한 번이라도 열어 본 탭 번호
  final _seen = <int>{};

  @override
  void initState() {
    super.initState();
    _seen.add(widget.index);
  }

  @override
  void didUpdateWidget(LazyTabs old) {
    super.didUpdateWidget(old);
    _seen.add(widget.index);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        for (var i = 0; i < widget.builders.length; i++)
          if (_seen.contains(i))
            Offstage(
              offstage: i != widget.index,
              // 안 보이는 탭에서 애니메이션·타이머가 계속 돌 이유가 없다.
              child: TickerMode(
                enabled: i == widget.index,
                child: _KeepAlive(
                  active: i == widget.index,
                  builder: widget.builders[i],
                ),
              ),
            ),
      ],
    );
  }
}

/// [active] 가 false 인 동안에는 자식을 **다시 build 하지 않는다.**
///
/// 자식 위젯 인스턴스를 캐시해 두고 그대로 돌려주므로, 부모가 rebuild
/// 되어도 자식 `build()` 는 호출되지 않는다. 자식이 `context.watch` 로
/// 구독한 provider 가 바뀌면 자식 스스로는 여전히 갱신되지만, 그건
/// 보이는 탭일 때만 의미가 있고 안 보일 때는 어차피 화면에 영향이 없다.
///
/// ⚠️ 안 보이는 동안 데이터가 바뀌면 그 탭은 stale 한 위젯을 들고 있다.
///    그래서 다시 그 탭으로 돌아올 때(`active` 가 true 로 바뀔 때)
///    캐시를 버리고 새로 만든다. 사장님 눈에는 항상 최신이 보인다.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.active, required this.builder});

  final bool active;
  final Widget Function() builder;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> {
  Widget? _cached;

  @override
  void didUpdateWidget(_KeepAlive old) {
    super.didUpdateWidget(old);
    // 숨어 있던 탭으로 돌아왔다 -> 그 사이 데이터가 바뀌었을 수 있으니
    // 캐시를 버리고 최신으로 다시 만든다.
    if (widget.active && !old.active) _cached = null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.active || _cached == null) {
      _cached = widget.builder();
    }
    return _cached!;
  }
}
