import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flow_note/design/fn_autocomplete.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// #107 회귀 방지
/// ═══════════════════════════════════════════════════════════════════════
///
/// 사장님 신고 두 가지를 다시는 되돌리지 않기 위한 테스트다.
///
///  (A) 영수증 상세에서 저장한 사진이 안 뜬다
///      → 원인은 Firebase Storage 버킷의 CORS 설정 부재였다.
///        `fetch(url)` 는 실패하는데 `<img src=url>` 은 1200x1600 으로
///        정상 표시됐고, HTTP 응답에 Access-Control-Allow-Origin 이 없었다.
///        버킷에 CORS 를 넣어 근본 해결하고, 그래도 막히면 HTML <img>
///        요소로 그리도록 `webHtmlElementStrategy` 를 붙였다.
///
///  (B) 꽃이름 자동완성 후보를 눌러도 반영이 안 된다
///      → 드롭다운이 OverlayEntry 라 TextField 의 탭 영역 밖이었다.
///        후보에 손가락이 닿는 순간 EditableText 가 포커스를 뺏고
///        (editable_text.dart:6692 `_EditableTextTapOutsideAction`),
///        오버레이가 손가락을 떼기 전에 사라져 onTap 이 소실됐다.
///        `TextFieldTapRegion` 으로 감싸서 해결했다.
///
/// 🔴 이 버그가 왜 그동안 재현되지 않았나 — 반드시 기억할 것.
///    `_EditableTextTapOutsideAction` 은 플랫폼마다 다르게 동작한다.
///      android/ios + 손가락 + 앱   → 포커스 안 빠짐  ← 테스트 기본 환경
///      android/ios + 손가락 + 웹   → unfocus()
///      어느 플랫폼이든 마우스/스타일러스 → unfocus()
///    즉 **웹에서만 나는 버그**였다. 사장님은 크롬 앱을 쓰신다.
///    그래서 아래 테스트는 플랫폼을 데스크톱으로 바꾸고 마우스로 누른다.
///    이걸 지우면 버그가 되살아나도 아무도 모른다.
///
/// 🔴 테스트를 쓸 때 내가 실제로 밟은 함정 세 개 — 남겨 둔다.
///    1. `tester.tap()` 은 down/up 을 같은 프레임에 보낸다. 그래서
///       "떼기 전에 오버레이가 사라진다" 는 경합을 절대 못 잡는다.
///       반드시 startGesture + pump + up 으로 시간을 흘려야 한다.
///    2. `debugDefaultTargetPlatformOverride` 는 `addTearDown` 으로
///       되돌리면 늦다. flutter_test 가 본문 종료 직후 검사해서
///       "foundation debug variable was changed" 로 실패시킨다.
///       본문 마지막에 직접 null 로 되돌려야 한다.
///    3. `FnAutoComplete._select` 는 `onSelected` 가 주어지면
///       controller.text 를 건드리지 않는다 — 텍스트 반영은 콜백
///       (실제로는 `FlowerNameField._select`)의 책임이다.
///       그래서 하니스의 onSelected 가 직접 텍스트를 넣어야 한다.

Widget _harness(TextEditingController ctl, List<String> picked,
    {int itemCount = 2}) {
  return MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: FnAutoComplete(
          controller: ctl,
          itemsBuilder: (q) => List<FnAcItem>.generate(itemCount,
              (i) => FnAcItem(label: '장미 후보$i', value: '장미 후보$i')),
          // 실제 화면(FlowerNameField._select)이 하는 일을 그대로 흉내낸다.
          onSelected: (it) {
            picked.add(it.value);
            ctl.text = it.value;
            ctl.selection = TextSelection.collapsed(offset: it.value.length);
          },
        ),
      ),
    ),
  );
}

void main() {
  group('#107 (B) 자동완성 후보 선택', () {
    testWidgets('🔴 웹/마우스 경로에서도 후보를 누르면 반영된다', (tester) async {
      // 웹과 같은 "밖을 누르면 포커스 뺏김" 경로를 강제한다.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      final ctl = TextEditingController();
      final picked = <String>[];
      await tester.pumpWidget(_harness(ctl, picked));

      await tester.tap(find.byType(TextField), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.text('장미 후보0'), findsOneWidget,
          reason: '드롭다운이 먼저 떠야 한다');

      final node = tester.widget<TextField>(find.byType(TextField)).focusNode!;
      expect(node.hasFocus, isTrue);

      final g = await tester.startGesture(
          tester.getCenter(find.text('장미 후보0')),
          kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 32));

      expect(node.hasFocus, isTrue,
          reason: '후보를 누르는 건 텍스트필드 "안"이어야 한다. '
              'TextFieldTapRegion 이 빠지면 여기서 false 가 된다');
      expect(find.text('장미 후보0'), findsOneWidget,
          reason: '손가락을 떼기 전에 드롭다운이 사라지면 탭이 소실된다');

      await g.up();
      await tester.pumpAndSettle();

      expect(picked, ['장미 후보0'],
          reason: '후보를 눌렀는데 반영되지 않았다 — #107 이 되살아났다');
      expect(ctl.text, '장미 후보0', reason: '꽃 이름 칸에 실제로 들어가야 한다');

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('🔴 앱(안드로이드 손가락) 경로도 그대로 동작한다', (tester) async {
      final ctl = TextEditingController();
      final picked = <String>[];
      await tester.pumpWidget(_harness(ctl, picked));
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();

      final g = await tester
          .startGesture(tester.getCenter(find.text('장미 후보0')));
      await tester.pump(const Duration(milliseconds: 32));
      await g.up();
      await tester.pumpAndSettle();

      expect(picked, ['장미 후보0'], reason: '웹을 고치면서 앱을 깨뜨렸다');
      expect(ctl.text, '장미 후보0');
    });

    testWidgets('🔴 후보가 많아도 아래쪽 후보를 정확히 고를 수 있다', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      // 후보가 여러 개일 때 엉뚱한 줄이 선택되면 사장님이 "여러 번
      // 터치하다가 짜증난다" 고 하신 그 증상이 다시 난다.
      for (final target in [0, 3, 5]) {
        final ctl = TextEditingController();
        final picked = <String>[];
        await tester.pumpWidget(_harness(ctl, picked, itemCount: 10));
        await tester.tap(find.byType(TextField), kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();

        final g = await tester.startGesture(
            tester.getCenter(find.text('장미 후보$target')),
            kind: PointerDeviceKind.mouse);
        await tester.pump(const Duration(milliseconds: 32));
        await g.up();
        await tester.pumpAndSettle();

        expect(picked, ['장미 후보$target'],
            reason: '$target 번째 후보를 눌렀는데 다른 게 선택됐다');
        expect(ctl.text, '장미 후보$target');
      }

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('🔴 손가락이 흔들려도(슬롭 안) 선택은 살아있다', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      // 실측값 — 흔들림이 슬롭을 넘으면 스크롤로 판정돼 탭이 사라진다.
      //   마우스   0/1/2/6/16px → 선택됨,  20px → 소실
      //   손가락   0/1/2/6/16px → 선택됨,  20px → 소실
      // 이건 Flutter 의 정상 동작(kTouchSlop = 18.0)이라 그대로 두되,
      // 슬롭 **안쪽** 흔들림에서 소실되면 회귀로 잡는다.
      for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
        final ctl = TextEditingController();
        final picked = <String>[];
        await tester.pumpWidget(_harness(ctl, picked, itemCount: 10));
        await tester.tap(find.byType(TextField), kind: kind);
        await tester.pumpAndSettle();

        final g = await tester.startGesture(
            tester.getCenter(find.text('장미 후보0')),
            kind: kind);
        await g.moveBy(const Offset(0, 6));
        await tester.pump(const Duration(milliseconds: 32));
        await g.up();
        await tester.pumpAndSettle();

        expect(picked, ['장미 후보0'],
            reason: '${kind.name}: 슬롭(18px) 안의 흔들림으로 선택이 소실되면 안 된다');
      }

      debugDefaultTargetPlatformOverride = null;
    });

    test('🔴 드롭다운은 TextFieldTapRegion 으로 감싸야 한다', () {
      final src = File('lib/design/fn_autocomplete.dart').readAsStringSync();
      expect(src.contains('TextFieldTapRegion('), isTrue,
          reason: '오버레이 드롭다운이 TextField 의 탭 영역 밖이면 '
              'EditableText 가 포커스를 뺏어 탭이 소실된다. '
              'Flutter 자신의 RawAutocomplete 도 이걸 쓴다');

      // 위치가 중요하다. CompositedTransformFollower **안쪽**이어야 한다.
      // 바깥에 두면 TapRegion 의 히트 박스가 변환 전 좌표에 놓여서
      // 히트 경로에 아예 들어오지 않는다(직접 측정으로 확인).
      final follower = src.indexOf('CompositedTransformFollower(');
      final region = src.indexOf('child: TextFieldTapRegion(');
      expect(follower, greaterThan(0));
      expect(region, greaterThan(follower),
          reason: 'TextFieldTapRegion 이 CompositedTransformFollower 보다 '
              '먼저 나온다 = 변환 바깥이다. 그러면 히트 테스트가 어긋난다');

      expect(src.contains('addPostFrameCallback'), isFalse,
          reason: '프레임 한 개 지연은 경합이지 해결이 아니다. '
              '그래서 사장님이 "갑자기 안 된다" 고 느꼈다');
    });
  });

  group('#107 (A) 영수증 사진 표시', () {
    test('🔴 웹에서 CORS 로 막혀도 HTML 요소로 그릴 수 있어야 한다', () {
      final src = File('lib/widgets/receipt_photo.dart').readAsStringSync();
      final networks = 'Image.network('.allMatches(src).length;
      final fallbacks =
          'WebHtmlElementStrategy.fallback'.allMatches(src).length;
      expect(networks, greaterThan(0));
      expect(fallbacks, networks,
          reason: 'Image.network $networks 개 중 fallback 지정은 $fallbacks 개다. '
              'Flutter 웹은 기본값(never)이면 바이트를 XHR 로만 읽어서 '
              'CORS 에 막히면 사진이 아예 안 뜬다');
    });

    test('🔴 원인을 잘못 짚는 안내문("인터넷 연결")을 되살리지 않는다', () {
      final src = File('lib/widgets/receipt_photo.dart').readAsStringSync();
      // 코드 모양으로 검사한다. 주석에는 옛 문구가 근거로 남아 있다.
      expect(src.contains("'인터넷 연결을 확인해주세요',"), isFalse,
          reason: '사진이 안 뜬 건 인터넷 문제가 아니었다. '
              '이 문구는 사장님이 와이파이만 계속 확인하게 만든다');
      expect(src.contains('Icons.wifi_off_rounded)'), isFalse,
          reason: '와이파이 끊김 아이콘도 같은 이유로 쓰지 않는다');
    });
  });
}
