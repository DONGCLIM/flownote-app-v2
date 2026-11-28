import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flow_note/models/receipt_model.dart';
import 'package:flow_note/providers/receipt_provider.dart';
import 'package:flow_note/services/guest_migration.dart';
import 'package:flow_note/services/guest_service.dart';

/// 요청 #30 회귀 — "로그인은 되는데 다음 화면으로 안 넘어간다".
///
/// ## 진짜 원인
/// 앱의 화면 전환은 루트 `_AppEntry` 하나가 담당한다.
/// ```dart
/// return auth.isLoggedIn ? const MainDsScreen() : const SplashDsScreen();
/// ```
/// 그런데 로그아웃 / 회원가입 / 온보딩 완료 3곳에서
/// `pushAndRemoveUntil(..., (r) => false)` 를 써서 스택을 통째로 비웠다.
/// 이 조건은 **루트까지 제거**하므로 `_AppEntry` 자체가 트리에서 사라진다.
/// → 이후 로그인에 성공해서 `isLoggedIn == true` 가 되어도
///   화면을 바꿔줄 위젯이 없어서 스플래시가 그대로 남는다.
///
/// 이 테스트는 그 네비게이션 규칙을 못으로 박아 둔다.
void main() {
  group('네비게이션 규칙 — 루트(_AppEntry)는 절대 제거되지 않는다', () {
    testWidgets('(r) => false 는 루트까지 제거한다 (금지 패턴 증명)', (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: const Text('ROOT'),
      ));
      expect(find.text('ROOT'), findsOneWidget);

      // 금지 패턴: 루트까지 날아간다.
      nav.currentState!.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const Text('PUSHED')),
        (r) => false,
      );
      await tester.pumpAndSettle();

      expect(find.text('PUSHED'), findsOneWidget);
      // 루트가 사라졌으므로 더 이상 pop 할 곳이 없다 = 복귀 불가.
      expect(nav.currentState!.canPop(), isFalse);
    });

    testWidgets('(r) => r.isFirst 는 루트를 보존한다 (권장 패턴)', (tester) async {
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: const Text('ROOT'),
      ));

      nav.currentState!.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const Text('PUSHED')),
        (r) => r.isFirst,
      );
      await tester.pumpAndSettle();

      expect(find.text('PUSHED'), findsOneWidget);
      // 루트가 남아 있으므로 언제든 되돌아갈 수 있다.
      expect(nav.currentState!.canPop(), isTrue);

      nav.currentState!.popUntil((r) => r.isFirst);
      await tester.pumpAndSettle();
      expect(find.text('ROOT'), findsOneWidget);
    });

    testWidgets('popUntil(isFirst) 로 루트의 로그인 상태 화면이 되살아난다',
        (tester) async {
      final nav = GlobalKey<NavigatorState>();
      final loggedIn = ValueNotifier<bool>(false);

      // 루트 = _AppEntry 와 동일 구조 (상태를 보고 화면을 고른다)
      await tester.pumpWidget(MaterialApp(
        navigatorKey: nav,
        home: ValueListenableBuilder<bool>(
          valueListenable: loggedIn,
          builder: (_, v, __) => Text(v ? 'HOME' : 'SPLASH'),
        ),
      ));
      expect(find.text('SPLASH'), findsOneWidget);

      // 로그인 화면을 루트 위에 push (SignInDsScreen 과 동일한 상황)
      nav.currentState!.push(
          MaterialPageRoute(builder: (_) => const Text('SIGN_IN')));
      await tester.pumpAndSettle();
      expect(find.text('SIGN_IN'), findsOneWidget);

      // 로그인 성공: 상태만 바꾸면 화면은 그대로다 (버그 재현)
      loggedIn.value = true;
      await tester.pumpAndSettle();
      expect(find.text('SIGN_IN'), findsOneWidget,
          reason: '루트 위에 얹혀 있으면 상태만 바뀌어도 화면이 안 바뀐다');
      expect(find.text('HOME'), findsNothing);

      // 수정된 동작: 루트까지 pop → 루트가 HOME 을 그린다
      if (nav.currentState!.canPop()) {
        nav.currentState!.popUntil((r) => r.isFirst);
      }
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });
  });

  _k195GuestLink();
  _k195GuestMigrate();
}

// ─────────────────────────────────────────────────────────────────────
//  #195 ⑤ 체험 계정 → 정식 계정 전환 (구글·애플·이메일)
//
//  🔴 여기서는 **코드 계약**을 못으로 박는다. 실제 연결은 Firebase 서버가
//     있어야 해서 테스트에서 돌릴 수 없다. 그래서 "무엇을 부르는가" 를
//     소스로 확인한다 — 이 계약이 깨지면 체험 영수증이 조용히 사라진다.
// ─────────────────────────────────────────────────────────────────────
void _k195GuestLink() {
  String read(String p) => File(p).readAsStringSync();

  group('#195 ⑤ 체험 계정 전환 — 연결(link)이지 로그인이 아니다', () {
    test('🔴 구글·애플·이메일 모두 link 로 붙인다 (signIn 이 아니다)', () {
      final src = read('lib/services/auth_service.dart');
      final g = src.substring(src.indexOf('Future<User> linkGuestWithGoogle'),
          src.indexOf('Future<User> linkGuestWithApple'));
      final a = src.substring(src.indexOf('Future<User> linkGuestWithApple'),
          src.indexOf('Future<User> linkGuestWithEmail'));
      final e = src.substring(src.indexOf('Future<User> linkGuestWithEmail'),
          src.indexOf('Object _linkFailure'));

      // 🔴 `signInWith*` 를 쓰면 uid 가 바뀌어 체험 영수증이 전부 사라진다.
      expect(g, anyOf(contains('linkWithPopup'), contains('linkWithCredential')));
      expect(a, contains('linkWithCredential'));
      expect(e, contains('linkWithCredential'));
      for (final part in [g, a, e]) {
        expect(part, isNot(contains('_auth!.signInWithCredential')));
        expect(part, isNot(contains('signInWithPopup')));
      }
    });

    test('🔴 체험(익명) 계정일 때만 붙인다', () {
      final src = read('lib/services/auth_service.dart');
      // 회원이 실수로 이 길에 들어오면 자기 계정에 엉뚱한 수단이 붙는다.
      expect(src, contains('if (u == null || !u.isAnonymous) return null;'));
      final body = src.substring(src.indexOf('Future<User> linkGuestWithGoogle'),
          src.indexOf('Object _linkFailure'));
      expect('_guestUser'.allMatches(body).length, 3,
          reason: '세 수단 모두 체험 계정인지 먼저 봐야 한다');
    });

    test('🔴 이미 쓰인 계정이면 말없이 로그인하지 않는다', () {
      final src = read('lib/services/auth_service.dart');
      final f = src.substring(src.indexOf('Object _linkFailure'),
          src.indexOf('Future<User> signInWithPendingCredential'));
      // credential-already-in-use 를 그 자리에서 로그인으로 바꿔치기하면
      // uid 가 달라져 체험 영수증이 눈앞에서 사라진 것처럼 보인다.
      expect(f, contains("'credential-already-in-use'"));
      expect(f, contains('AuthLinkConflict'));
      expect(f, isNot(contains('signInWithCredential')));
    });
  });

  group('#195 ⑤ 연결 뒤 절차는 기존 가입과 같다', () {
    test('🔴 users/{uid} 문서 생성과 consent_log 기록을 같은 함수로 한다', () {
      final src = read('lib/providers/auth_provider.dart');
      final body = src.substring(src.indexOf('Future<GuestLinkResult> linkGuestTo'),
          src.indexOf('AuthLinkConflict? _pendingLink'));
      // 🔴 기존 소셜 가입과 **같은** 두 함수를 쓴다. 새로 만들면 동의 항목이
      //    갈라지고, 한쪽만 고치는 사고가 난다.
      expect(body, contains('_hydrate(fbUser)'));
      expect(body, contains('_ensureRequiredConsents(fbUser.uid'));
      // _hydrate 가 users 문서를 만든다 (createIfAbsent).
      final hyd = src.substring(src.indexOf('Future<void> _hydrate'));
      expect(hyd, contains('createIfAbsent'));
      // _ensureRequiredConsents 가 동의 이력을 남긴다.
      final con = src.substring(src.indexOf('Future<void> _ensureRequiredConsents'));
      expect(con, contains('recordConsents'));
    });

    test('🔴 새 동의 항목을 만들지 않았다 (약관·개인정보·마케팅 그대로)', () {
      final src = read('lib/providers/auth_provider.dart');
      final b = src.substring(src.indexOf('UserConsents _buildConsents'));
      expect(b, contains('terms:'));
      expect(b, contains('privacy:'));
      expect(b, contains('marketing:'));
      // 동의 묶음은 이 셋뿐이다.
      final model = read('lib/models/user_model.dart');
      final uc = model.substring(model.indexOf('class UserConsents'),
          model.indexOf('Map<String, dynamic> toMap()', model.indexOf('class UserConsents')));
      expect('ConsentRecord?'.allMatches(uc).length, 3,
          reason: '동의 항목이 늘었다 — 기존 가입 흐름과 어긋난다');
    });

    test('🔴 이메일 가입 화면은 게스트일 때만 연결로 간다', () {
      final src = read('lib/screens/ds/auth_ds_screens.dart');
      final s = src.substring(src.indexOf('Future<void> _submit()'));
      final guard = s.indexOf('if (GuestService.instance.isGuest)');
      final signUp = s.indexOf('await auth.signUp(');
      expect(guard, greaterThan(0));
      expect(signUp, greaterThan(guard),
          reason: '회원은 예전 signUp() 으로 그대로 가야 한다');
      expect(s.substring(guard, signUp), contains('GuestLinkMethod.email'));
    });
  });

  group('#195 ⑤ 이미 가입된 계정 — 여쭙고, 체험 데이터는 보존', () {
    test('🔴 안내창 문구와 버튼이 지시대로다', () {
      final src = read('lib/widgets/fn_signup_sheet.dart');
      final a = src.substring(src.indexOf('_askSignInInstead(\n'));
      expect(a, contains('이미 가입된 계정이에요'));
      expect(a, contains('이 계정으로 로그인할까요?'));
      expect(a, contains("confirmLabel: '로그인'"));
      expect(a, contains("cancelLabel: '취소'"));
    });

    test('🔴 로그인을 고르셔도 체험 데이터를 지우지 않는다', () {
      final prov = read('lib/providers/auth_provider.dart');
      final s = prov.substring(prov.indexOf('Future<bool> signInWithConflicted'));
      final end = s.indexOf('\n  }\n');
      // 🔴 여기서 지우면 다음 작업(합치기)에서 되살릴 것이 없다.
      expect(s.substring(0, end), isNot(contains('clearAfterSignUp')));

      final sheet = read('lib/widgets/fn_signup_sheet.dart');
      final ask = sheet.substring(sheet.indexOf('_askSignInInstead(\n'));
      expect(ask, isNot(contains('clearAfterSignUp')));
    });

    test('🔴 가입 성공일 때만 체험 카운터를 치운다', () {
      final src = read('lib/widgets/fn_signup_sheet.dart');
      final f = src.substring(src.indexOf('Future<void> fnLinkGuestAccount'));
      final ok = f.indexOf('case GuestLinkResult.ok:');
      final conflict = f.indexOf('case GuestLinkResult.conflict:');
      final clear = f.indexOf('clearAfterSignUp');
      expect(ok, greaterThan(0));
      expect(clear, greaterThan(ok));
      expect(clear, lessThan(conflict), reason: '성공 갈래 안에서만 치워야 한다');
    });
  });

  group('#195 ⑤ 카카오는 이번에 붙이지 않는다', () {
    test('🔴 카카오 연결 함수를 만들지 않았다', () {
      final src = read('lib/services/auth_service.dart');
      // 카카오는 커스텀 토큰이라 uid 가 바뀐다. 붙이면 영수증이 사라진다.
      expect(src, isNot(contains('linkGuestWithKakao')));
    });

    test('🔴 카카오 가입 버튼은 기존 로그인 화면으로 간다', () {
      for (final f in [
        'lib/widgets/fn_signup_sheet.dart',
        'lib/screens/ds/profile_ds_screen.dart',
      ]) {
        final src = read(f);
        // 🔴 `indexOf('카카오로')` 로 찾으면 **주석**이 먼저 걸린다.
        //    실제 버튼은 `label:` 이 붙어 있다.
        final i = src.indexOf("label: '카카오로");
        expect(i, greaterThan(0), reason: f);
        // 버튼 바로 아래 onTap 이 로그인 화면으로 간다.
        //
        // 🔴 두 화면이 부르는 모양이 다르다. 바텀시트는 시트를 먼저 닫아야
        //    해서 `_toSignIn`(그 안에서 `fnOpenSignIn`)을 거치고, 프로필은
        //    닫을 시트가 없어 곧바로 부른다. 둘 다 같은 곳으로 간다.
        expect(src.substring(i, i + 160),
            anyOf(contains('fnOpenSignIn'), contains('_toSignIn')),
            reason: f);
        // 연결(link)로 가면 안 된다 — uid 가 바뀌어 영수증이 사라진다.
        expect(src.substring(i, i + 160), isNot(contains('fnLinkGuestAccount')),
            reason: f);
      }
    });

    test('🔴 바텀시트의 _toSignIn 은 결국 로그인 화면으로 간다', () {
      final src = read('lib/widgets/fn_signup_sheet.dart');
      final t = src.substring(src.indexOf('void _toSignIn(BuildContext context)'));
      expect(t.substring(0, t.indexOf('\n  }\n')), contains('fnOpenSignIn'));
    });

    test('🔴 "이미 가입하셨나요? 로그인" 도 기존 로그인 화면이다', () {
      final src = read('lib/widgets/fn_signup_sheet.dart');
      final i = src.indexOf('이미 가입하셨나요? 로그인');
      expect(i, greaterThan(0));
      expect(src, contains('fnOpenSignIn'));
      // 기존 로그인 화면 = 카카오까지 들어 있는 스플래시.
      expect(src, contains('SplashDsScreen'));
    });
  });

  group('#195 ⑤ 회원 흐름은 그대로다', () {
    test('🔴 기존 가입·로그인 함수를 고치지 않았다', () {
      final src = read('lib/providers/auth_provider.dart');
      for (final f in [
        'Future<bool> signUp({',
        'Future<bool> signIn({',
        'Future<bool> signInWithGoogle({',
        'Future<bool> signInWithApple({',
        'Future<bool> signInWithKakao({',
      ]) {
        expect(src, contains(f), reason: '$f 가 사라졌다');
      }
      // 🔴 기존 로그인 함수 안에 게스트 분기가 들어가면 회원이 위험하다.
      final g = src.substring(src.indexOf('Future<bool> signInWithGoogle({'),
          src.indexOf('Future<bool> signInWithApple({'));
      expect(g, isNot(contains('GuestService')));
      expect(g, isNot(contains('isAnonymous')));
    });

    test('🔴 가입 완료 안내가 바탕화면 설치로 이어진다', () {
      final src = read('lib/widgets/fn_signup_sheet.dart');
      final a = src.substring(src.indexOf('Future<void> _afterSignUp'));
      expect(a, contains('가입 완료! 찍어둔 영수증이 저장됐어요'));
      expect(a, contains('AddToHomeSheet.open'));
    });

    test('🔴 아이폰 체험 설치 안내 문구는 게스트에게만 다르다', () {
      final src = read('lib/screens/ds/add_to_home_sheet.dart');
      expect(src, contains('가입한 뒤 설치하면 영수증이 그대로 보여요'));
      // 회원 문구는 그대로 남아 있다.
      expect(src, contains('한 번 설치하면 앱처럼 바로 열려요.'));
      expect(src, contains('GuestService.instance.isGuest'));
    });
  });
}


// ─────────────────────────────────────────────────────────────────────
//  #195 ⑤-d 체험 데이터 옮기기 (migrateGuestData 연결)
//
//  🔴 서버를 부르는 길은 Firebase 가 있어야 해서 테스트에서 돌릴 수 없다.
//     그래서 ① 서버 없이 돌릴 수 있는 곳은 **실제로 돌려 보고**(상자 복사·
//     답 해석·회원 차단), ② 화면을 잇는 순서는 **코드 계약**으로 못을
//     박는다. 이 계약이 깨지면 체험 영수증이 조용히 사라진다.
// ─────────────────────────────────────────────────────────────────────
void _k195GuestMigrate() {
  String read(String p) => File(p).readAsStringSync();

  ReceiptModel receipt(int i) => ReceiptModel(
        id: 'g$i',
        date: DateTime(2026, 3, 10 + i),
        storeName: '양재꽃시장',
        items: [
          FlowerItem(name: '장미', quantity: 10, unitPrice: 1200, unit: 'stems'),
        ],
        totalAmount: 12000 + i.toDouble(),
        rawOcrText: 't$i',
        createdAt: DateTime(2026, 3, 10 + i),
      );

  // ── ① 게스트 → 카카오 **새 회원** ──────────────────────────────
  group('#195 ⑤-d 게스트 → 카카오 새 회원 — 5장이 그대로 따라온다', () {
    late Directory dir;

    setUpAll(() async {
      dir = await Directory.systemTemp.createTemp('fn195mig');
      Hive.init(dir.path);
      if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ReceiptModelAdapter());
      if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(FlowerItemAdapter());
    });

    tearDownAll(() async {
      await Hive.deleteFromDisk();
      await dir.delete(recursive: true);
    });

    test('🔴 체험 상자 5장이 새 계정 상자로 그대로 옮겨진다', () async {
      final from = await Hive.openBox<ReceiptModel>('mig_guest_a');
      final to = await Hive.openBox<ReceiptModel>('mig_member_a');
      for (var i = 0; i < 5; i++) {
        await from.put('g$i', receipt(i));
      }

      final moved = await ReceiptProvider.copyReceipts(from, to);

      expect(moved, 5);
      expect(to.length, 5);
      // 품목까지 따라와야 한다 — 빈 영수증만 남으면 쓸모가 없다.
      expect(to.get('g2')!.items.single.name, '장미');
      expect(to.get('g2')!.totalAmount, 12002);
      // 🔴 원본은 지우지 않는다. 옮기다 끊겨도 되돌릴 것이 남아야 한다.
      expect(from.length, 5);

      await from.close();
      await to.close();
    });

    test('🔴 두 번 옮겨도 늘어나지 않는다 (다시 시도해도 안전)', () async {
      final from = await Hive.openBox<ReceiptModel>('mig_guest_b');
      final to = await Hive.openBox<ReceiptModel>('mig_member_b');
      for (var i = 0; i < 5; i++) {
        await from.put('g$i', receipt(i));
      }

      expect(await ReceiptProvider.copyReceipts(from, to), 5);
      expect(await ReceiptProvider.copyReceipts(from, to), 0);
      expect(to.length, 5);

      await from.close();
      await to.close();
    });

    test('🔴 서버가 "옮겼다" 고 하면 장수를 그대로 읽는다', () {
      final r = GuestMigration.parseResult(const {
        'ok': true,
        'skipped': false,
        'receipts': 5,
        'purchaseLists': 1,
        'guestReceipts': 5,
      });
      expect(r.isMoved, isTrue);
      expect(r.receipts, 5);
    });

    test('🔴 옮김 갈래에서만 상자를 복사하고 클라우드로 올린다', () {
      final s = read('lib/widgets/fn_signup_sheet.dart');
      final mv = s.substring(s.indexOf('case GuestMigrateStatus.moved:'),
          s.indexOf('case GuestMigrateStatus.skippedExisting:'));
      expect(mv, contains('adoptGuestBox'));
      expect(mv, contains('pushAllToCloud'));
      expect(mv, contains('clearAfterSignUp'));
      expect(mv, contains('_afterSignUpWithCount'));
      // 안내 문구에 장수가 들어간다.
      final a = s.substring(s.indexOf('Future<void> _afterSignUpWithCount'));
      expect(a, contains(r"가입 완료! 찍어둔 영수증 $n장이 저장됐어요"));
      expect(a, contains('AddToHomeSheet.open'));   // → 바탕화면 설치 안내
    });

    test('🔴 가입 동의 절차는 기존 카카오 로그인이 그대로 한다', () {
      final prov = read('lib/providers/auth_provider.dart');
      final k = prov.substring(prov.indexOf('Future<bool> signInWithKakao({'),
          prov.indexOf('bool get isKakaoAccount'));
      // 🔴 기존 함수 안에 게스트 분기를 넣지 않았다. 회원은 지금 그대로다.
      expect(k, isNot(contains('GuestService')));
      expect(k, isNot(contains('GuestMigration')));
      // 회원 문서 생성 · 필수 동의 기록은 예전 그대로 남아 있다.
      expect(k, contains('_hydrate(fbUser)'));
      expect(k, contains('_ensureRequiredConsents(fbUser.uid'));
    });
  });

  // ── ② 게스트 → **기존** 카카오 회원 ───────────────────────────
  group('#195 ⑤-d 게스트 → 기존 회원 — 옮기지 않고 알려만 드린다', () {
    test('🔴 서버가 건너뛰었다고 하면 장수와 함께 "안 옮김" 으로 읽는다', () {
      final r = GuestMigration.parseResult(const {
        'ok': true,
        'skipped': true,
        'reason': 'existing_member',
        'receipts': 0,
        'guestReceipts': 5,
      });
      expect(r.isSkipped, isTrue);
      expect(r.isMoved, isFalse);
      expect(r.guestReceipts, 5);
    });

    test('🔴 안내 문구가 지시대로이고, 상자는 건드리지 않는다', () {
      final s = read('lib/widgets/fn_signup_sheet.dart');
      final sk = s.substring(s.indexOf('case GuestMigrateStatus.skippedExisting:'),
          s.indexOf('case GuestMigrateStatus.failed:'));
      // 🔴 2026-11-28 사장님 지시로 **팝업이 아니라 닫을 수 있는 안내 줄**
      //    이 되었다. 문구는 `FnMigrateSkippedNotice` 가 들고 있다.
      expect(sk, contains('raiseSkipNotice'));
      final banner = read('lib/widgets/fn_guest_banner.dart');
      expect(banner, contains('체험으로 찍은 영수증은 기존 계정으로 옮겨지지 않아요.'));
      expect(banner, contains('필요한 영수증은 다시 스캔해 주세요.'));
      // 닫을 수 있어야 한다.
      expect(banner, contains('dismissSkipNotice'));
      // 🔴 새로 가입한 분에게는 안 뜬다 — 켜는 자리가 이 갈래 하나뿐이다.
      expect('raiseSkipNotice()'.allMatches(s).length, 1);
      // 🔴 기기 상자를 복사하면 남의 장부에 체험 영수증이 섞인다.
      expect(sk, isNot(contains('adoptGuestBox')));
      expect(sk, isNot(contains('pushAllToCloud')));
      // 🔴 체험 데이터는 지우지 않는다.
      expect(sk, isNot(contains('clearAfterSignUp')));
    });

    test('🔴 상자 복사는 서버가 "옮겼다" 고 할 때만 부른다', () {
      final s = read('lib/widgets/fn_signup_sheet.dart');
      // 파일 통틀어 adoptGuestBox 를 부르는 자리는 옮김 갈래 한 곳뿐이다.
      expect('await receipts.adoptGuestBox'.allMatches(s).length, 1);
    });
  });

  // ── ③ 실패 ──────────────────────────────────────────────────
  group('#195 ⑤-d 옮기기 실패 — 다시 시도, 체험 데이터 보존', () {
    test('🔴 서버가 거절하면 실패로 읽고 문구를 들고 온다', () {
      final r = GuestMigration.parseResult(const {'ok': false});
      expect(r.isFailed, isTrue);
      expect(r.message, '체험 영수증을 옮기지 못했어요.');
    });

    test('🔴 실패했을 때만 맡아 둔 토큰을 남겨 둔다', () {
      final g = read('lib/services/guest_migration.dart');
      // 성공·건너뜀은 끝난 일이라 지우고, 실패만 남겨 다시 시도한다.
      expect(g, contains('if (!out.isFailed) await clear();'));
      // 예외로 떨어져도 지우지 않는다 — catch 안에 clear 가 없어야 한다.
      final c = g.substring(g.indexOf('    } catch (e) {',
          g.indexOf('Future<GuestMigrateResult> runIfPending')));
      expect(c.substring(0, c.indexOf('\n  }')), isNot(contains('clear()')));
    });

    test('🔴 [다시 시도] 를 드리고, 누르면 한 번 더 간다', () {
      final s = read('lib/widgets/fn_signup_sheet.dart');
      final fl = s.substring(s.indexOf('case GuestMigrateStatus.failed:'),
          s.indexOf('/// 옮긴 장수를 넣은'));
      expect(fl, contains('체험 영수증을 옮기지 못했어요.'));
      expect(fl, contains("confirmLabel: '다시 시도'"));
      expect(fl, contains('await fnRunGuestMigration(context)'));
      // 🔴 로그인은 그대로 둔다 — 여기서 로그아웃시키면 안 된다.
      expect(fl, isNot(contains('signOut')));
      // 🔴 체험 데이터는 지우지 않는다.
      expect(fl, isNot(contains('clearAfterSignUp')));
      expect(fl, isNot(contains('adoptGuestBox')));
    });
  });

  // ── ④ 회원 로그인은 지금과 똑같다 ─────────────────────────────
  group('#195 ⑤-d 회원 로그인 — 이 길로 들어오지 않는다', () {
    tearDown(() {
      GuestService.debugIsGuest = null;
      GuestMigration.debugCall = null;
    });

    test('🔴 회원이면 토큰을 맡아 두지 않는다', () async {
      SharedPreferences.setMockInitialValues({});
      GuestService.debugIsGuest = false;

      final kept = await GuestMigration.instance.rememberGuest();

      expect(kept, isFalse);
      expect(GuestMigration.instance.hasPending, isFalse);
      expect(GuestMigration.instance.pendingGuestUid, isNull);
    });

    test('🔴 맡아 둔 것이 없으면 서버를 부르지 않는다', () async {
      SharedPreferences.setMockInitialValues({});
      GuestService.debugIsGuest = false;
      await GuestMigration.instance.clear();

      var called = 0;
      GuestMigration.debugCall = (_) async {
        called++;
        return const {'ok': true};
      };

      final r = await GuestMigration.instance.runIfPending();

      expect(called, 0, reason: '회원 로그인에서 migrateGuestData 를 불렀다');
      expect(r.status, GuestMigrateStatus.none);
    });

    test('🔴 체험 중일 때만 토큰을 맡아 둔다 (게스트 빗장)', () {
      final g = read('lib/services/guest_migration.dart');
      final rm = g.substring(g.indexOf('Future<bool> rememberGuest()'));
      expect(rm.substring(0, rm.indexOf('\n  }')),
          contains('if (!GuestService.instance.isGuest) return false;'));
    });

    test('🔴 로그인 화면은 기존 호출을 고치지 않고 앞뒤로만 덧붙였다', () {
      final s = read('lib/screens/ds/splash_ds_screen.dart');
      final f = s.substring(s.indexOf('Future<void> _sns(_Sns s) async {'));
      final guard = f.indexOf('final wasGuest = GuestService.instance.isGuest;');
      final remember = f.indexOf('await fnRememberGuest();');
      final kakao = f.indexOf('_Sns.kakao => await auth.signInWithKakao(),');
      final run = f.indexOf('await fnRunGuestMigration(context);');

      expect(guard, greaterThan(0));
      // 순서: 게스트인지 본다 → 토큰 보관 → (기존 로그인 그대로) → 옮기기
      expect(remember, greaterThan(guard));
      expect(kakao, greaterThan(remember));
      expect(run, greaterThan(kakao));
      // 🔴 둘 다 게스트일 때만 돈다.
      expect('if (wasGuest)'.allMatches(f.substring(0, run + 60)).length, 2);
      // 기존 로그인 줄 자체는 그대로다.
      expect(f, contains('_Sns.apple => await auth.signInWithApple(),'));
      expect(f, contains('_ => await auth.signInWithGoogle(),'));
    });

    test('🔴 기존 로그인 서비스에는 손대지 않았다', () {
      final a = read('lib/services/auth_service.dart');
      expect(a, isNot(contains('GuestMigration')));
      // 카카오 로그인 세 함수가 그대로 있다.
      for (final f in [
        'Future<User> signInWithKakao()',
        'Future<User?> completeKakaoWebLogin()',
        'Future<User> _finishKakao(',
      ]) {
        expect(a, contains(f), reason: '$f 가 사라졌다');
      }
    });
  });

  // ── ⑤ 공통 ──────────────────────────────────────────────────
  group('#195 ⑤-d 공통 — 옮긴 영수증은 학습으로 올리지 않는다', () {
    test('🔴 옮기기 길에는 학습 수집이 끼어들지 않는다', () {
      // 학습 업로드는 **스캔하는 순간** 한 번만 일어난다. 옮기기는 이미
      // 찍힌 것을 자리만 바꾸는 일이라 그 길을 지나지 않는다.
      expect(read('lib/widgets/fn_signup_sheet.dart'),
          isNot(contains('TrainingDataService')));
      expect(read('lib/providers/receipt_provider.dart'),
          isNot(contains('TrainingDataService')));
      expect(read('lib/services/guest_migration.dart'),
          isNot(contains('TrainingDataService')));
    });

    test('🔴 웹 카카오는 돌아온 뒤에 마저 옮긴다', () {
      // 웹 카카오 로그인은 페이지가 통째로 갔다 오므로, 로그인 완료가
      // 다음 실행에서 일어난다. 그때 집어 줄 자리가 있어야 한다.
      final m = read('lib/screens/ds/main_ds_screen.dart');
      expect(m, contains('await fnRunGuestMigration(context);'));
      final i = m.indexOf('await fnRunGuestMigration(context);');
      final restore = m.indexOf('await receipts.restoreFromCloud();');
      expect(i, greaterThan(0));
      expect(restore, greaterThan(i),
          reason: '옮기기보다 클라우드 복원이 먼저 돌면 장부가 엇갈린다');
    });

    test('🔴 체험 상자는 내 상자일 때만 넘겨받는다', () {
      final r = read('lib/providers/receipt_provider.dart');
      final f = r.substring(r.indexOf('Future<int> adoptGuestBox('));
      final body = f.substring(0, f.indexOf('\n  }'));
      // pushAllToCloud 와 같은 빗장 — 계정이 바뀌는 찰나를 막는다.
      expect(body, contains('if (_openedFor != uid) return 0;'));
      // 🔴 원본을 지우는 코드가 없어야 한다.
      expect(body, isNot(contains('deleteBoxFromDisk')));
      expect(body, isNot(contains('.clear()')));
    });
  });
}
