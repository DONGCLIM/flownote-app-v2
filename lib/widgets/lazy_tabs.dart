import 'package:flutter/material.dart';

/// 탭 본문 컨테이너. `IndexedStack` 을 대체한다.
///
/// ## IndexedStack 의 무엇이 문제였나
///
/// `IndexedStack` 은 자식 전부를 `Visibility(maintainState: true)` 로
/// 감싸서 트리에 유지한다(`basic.dart:4726`). 상태 유지에는 좋지만,
/// 자식들이 `InheritedWidget` 을 구독하고 있으면 **안 보이는 자식까지
/// 전부 다시 build** 된다. 우리 탭 중 홈·내역·캘린더 세 개가
/// `context.watch<ReceiptProvider>()` 를 쓰고 있었다.
///
/// 직접 측정한 값 (200행 탭 5개, flutter_test):
///
/// | | 결과 |
/// |---|---|
/// | 트리에 살아있는 Element | 7,141개 |
/// | `notifyListeners()` 1회 후 재build 된 탭 | **5 / 5** |
///
/// 영수증을 저장하고 뒤로 나오면 `notifyListeners()` 가 불리고, 그때
/// 화면 전환 애니메이션(기본 300ms)이 같이 돌고 있어서 프레임이 밀렸다.
/// — 사장님이 말한 "뒤로가기 한 다음에 반응이 좀 느려"가 이것이다.
///
/// ## 어떻게 고쳤나
///
/// 1. **지연 생성** — 한 번도 안 열어 본 탭은 아예 만들지 않는다.
///    앱을 처음 켤 때 5화면이 아니라 1화면만 build 된다.
/// 2. **보이지 않는 탭은 rebuild 를 건너뛴다** — `_KeepAlive` 가
///    `active` 가 false 인 동안 이전에 만든 위젯을 그대로 재사용한다.
///    자식이 build 되지 않으므로 provider 재계산도 일어나지 않는다.
///
/// 상태(스크롤 위치, 입력 중인 글자)는 그대로 유지된다 — 위젯을
/// 버리는 게 아니라 **다시 그리지만 않는** 것이다.
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
