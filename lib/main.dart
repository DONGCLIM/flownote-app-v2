import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'models/receipt_model.dart';
import 'models/purchase_list_model.dart';
import 'providers/auth_provider.dart';
import 'providers/receipt_provider.dart';
import 'services/auth_service.dart';
import 'services/firebase_status.dart';
import 'services/flower_price_service.dart';
import 'services/api_key_service.dart';
import 'services/flower_season_service.dart';
import 'services/user_repository.dart';
import 'services/notification_service.dart';
import 'services/training_data_service.dart';
import 'services/flower_name_service.dart';
import 'services/home_tips.dart';
import 'services/fn_analytics.dart';
import 'services/guest_service.dart';
import 'services/purchase_list_service.dart';
import 'services/vendor_tax_service.dart';
import 'services/subscription_service.dart';
import 'services/kakao_config.dart';
import 'services/pwa_install.dart';
import 'theme/app_theme.dart';
import 'screens/ds/splash_ds_screen.dart';
import 'screens/ds/main_ds_screen.dart';
import 'screens/ds/intro_ds_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 릴리즈 빌드에서 위젯 build() 가 throw 하면 Flutter 기본 동작은
  // **아무 설명 없는 회색 사각형**(ErrorWidget) 이다. 사용자가 "홈 화면이
  // 회색으로 나온다" 고 신고한 원인이 이것이었다.
  // → 무슨 화면에서 무슨 오류가 났는지 화면에 보이게 바꾼다.
  ErrorWidget.builder = (details) => _FnErrorBox(details: details);

  // Initialize Korean locale
  await initializeDateFormatting('ko', null);

  // 카카오 SDK 초기화.
  // 로그인 버튼을 누르기 전에 반드시 끝나 있어야 한다. 네트워크를 쓰지
  // 않는 값 세팅뿐이라 즉시 끝난다. 키가 없으면 아무것도 하지 않는다.
  //
  // 🔴 웹 로그인은 이제 SDK 를 타지 않는다. 그래도 초기화는 남겨둔다 —
  //    로그아웃 시 `UserApi.logout()`, 회원탈퇴 시 `unlink()` 처럼
  //    SDK 를 쓰는 다른 호출이 있고, 그건 초기화가 되어 있어야 한다.
  //    (웹 로그인이 SDK 를 버린 이유는 kakao_web_login_types.dart 참고)
  KakaoConfig.init();

  // 홈 화면 추가 프롬프트 가로잡기.
  //
  // 브라우저가 주는 `beforeinstallprompt` 이벤트는 **페이지 로드 지후
  // 딜 단 한 번** 오고, 그 때 잡아두지 않으면 다시 받을 수 없다.
  // 그래서 화면이 그려지기 전에 리스너를 붙여둔다.
  // (네이티본에서는 stub 구현이라 아무것도 하지 않는다)
  pwaInit();

  // Initialize Hive
  await Hive.initFlutter();
  Hive.registerAdapter(ReceiptModelAdapter());
  Hive.registerAdapter(FlowerItemAdapter());
  // 사입 리스트 (#179) — typeId 2·3·4
  Hive.registerAdapter(PurchaseListAdapter());
  Hive.registerAdapter(PurchaseItemAdapter());
  Hive.registerAdapter(SketchStrokeAdapter());

  // Initialize Firebase (실패해도 앱은 계속 실행)
  //
  // 실패 사유를 절대로 버리지 않는다. 이전에는 `kDebugMode` 로그만 남겨서
  // 릴리즈 APK 에서 "로그인이 안 되는데 이유를 알 수 없는" 상태가 됐다.
  // → `FirebaseStatus` 에 담아 두고 로그인 화면 배너에 그대로 보여준다.
  var coreOk = false;
  try {
    // 네트워크가 막힌 곳에서 무한 대기가 되지 않도록 상한을 둔다.
    //
    // 🔴 웹은 반드시 `options:` 를 넘겨야 한다.
    // Android 는 google-services.json 을 네이티브가 읽어 주지만 브라우저에는
    // 그 경로가 없어서, 인자 없이 부르면
    // "Null check operator used on a null value" 로 죽는다.
    // 네이티브에서는 `currentPlatformOrNull` 이 null 을 주므로 기존 동작
    // (네이티브 설정 파일 사용) 을 그대로 유지한다.
    final opts = DefaultFirebaseOptions.currentPlatformOrNull;
    await (opts == null
            ? Firebase.initializeApp()
            : Firebase.initializeApp(options: opts))
        .timeout(const Duration(seconds: 20));
    coreOk = true;
  } catch (e) {
    FirebaseStatus.markFailed('Firebase.initializeApp', e);
  }

  if (coreOk) {
    try {
      // 인증 + 사용자 문서 서비스는 Firebase 초기화 직후에 붙여야 한다.
      AuthService.instance.init();
      UserRepository.instance.init();
      if (AuthService.instance.isAvailable) {
        FirebaseStatus.markReady();
      } else {
        FirebaseStatus.markFailed(
            'FirebaseAuth.instance', 'Auth 인스턴스를 가져오지 못했습니다.');
      }
      await TrainingDataService().init();
    } catch (e) {
      FirebaseStatus.markFailed('AuthService.init', e);
    }
  }

  // Initialize new domain services (vendor tax / subscription)
  await VendorTaxService.instance.init();
  await SubscriptionService.instance.init();

  // 🔴 사입 리스트 상자를 연다. (#188 버그)
  //
  //    이게 빠져 있어서 `PurchaseListService` 가 `_ready = false` 로 남았고,
  //    `touch()` 는 첫 줄에서 조용히 돌아가 **아무것도 저장되지 않았다.**
  //    읽는 쪽 `all` 도 빈 목록을 돌려줘서, 저장된 사입 리스트 화면은
  //    늘 "아직 저장된 사입 리스트가 없어요" 였다.
  //    실패해도 안에서 삼키고 앱은 계속 뜬다.
  try {
    await PurchaseListService.instance.init();
  } catch (e) {
    debugPrint('[boot] 사입 리스트 상자를 열지 못했습니다: $e');
  }

  // 홈 팁 — 어떤 팁을 언제 봤는지 이 기기에서만 읽어 둔다. (#186)
  // 실패해도 안에서 삼키고 처음 보는 것처럼 돈다.
  await HomeTipStore.instance.init();

  // 꽃 표준 이름 사전 (자동완성/표준화). 40KB asset 파싱이라 빠르고,
  // 실패해도 내부에서 삼켜서 자동완성만 조용히 비활성화된다.
  await FlowerNameService.instance.load();

  // 🔴 빌드에 OCR 키가 실렸는지 시작할 때 남긴다.
  //
  // Build 22~24 가 키 없이 빌드돼 스캔이 전부 실패했는데, 로그에도 아무
  // 흔적이 없어서 원인을 찾는 데 오래 걸렸다. 한 줄이면 즉시 판별된다.
  debugPrint(ApiKeyService.defaultApiKey.isEmpty
      ? '[boot] ⚠️ OCR 키가 빌드에 없습니다 — 스캔이 실패합니다. '
          'tool/build_apk.sh 로 빌드하세요 (앱 내 AI 설정으로도 지정 가능)'
      : '[boot] OCR 키 주입됨 (${ApiKeyService.defaultModel})');

  // 꽃별 계절 시세 패턴 (인사이트 탭). 4.5KB asset 이고 네트워크를 쓰지 않아서
  // Firebase 상태와 무관하게 항상 붙는다 — 매입 내역이 없는 첫 사용자에게도
  // 보여줄 게 있는 유일한 인사이트다.
  await FlowerSeasonService.instance.load();

  // 양재 경매 시세 요약. 로컬 캐시를 먼저 붙이고 갱신은 백그라운드로 던진다
  // (`init` 내부에서 `refresh()` 를 await 하지 않는다).
  // 서버가 하루 한 번 요약해둔 약 6KB 문서 하나만 읽으므로 앱은 경매 API 를
  // 직접 부르지 않는다. 실패해도 시세 줄만 안 보이고 앱은 정상 동작한다.
  if (coreOk) {
    await FlowerPriceService.instance.init();
  }

  // Initialize notification service
  await NotificationService().init();

  // Initialize auth provider
  final authProvider = AuthProvider();
  await authProvider.init();

  // Initialize receipt provider
  final receiptProvider = ReceiptProvider();
  await receiptProvider.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authProvider),
        ChangeNotifierProvider.value(value: receiptProvider),
      ],
      child: const FlowNoteApp(),
    ),
  );
}

/// build() 예외를 회색 박스 대신 읽을 수 있는 안내로 보여준다.
class _FnErrorBox extends StatelessWidget {
  const _FnErrorBox({required this.details});
  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFFFCFA),
      padding: const EdgeInsets.all(20),
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 40, color: Color(0xFFE8697B)),
          const SizedBox(height: 12),
          const Text(
            '이 화면을 표시하는 중 문제가 발생했어요',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF171717),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${details.exception}',
            textAlign: TextAlign.center,
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12,
              height: 1.5,
              color: Color(0xFF7C7D82),
            ),
          ),
        ],
      ),
    );
  }
}

class FlowNoteApp extends StatelessWidget {
  const FlowNoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FlowNote',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // 한국어 로컬라이제이션 — showDatePicker 등 Material 위젯이
      // 한글 UI 로 뜨게 한다. (delegate 가 없으면 ko 로케일 요청 시 실패)
      locale: const Locale('ko'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ko'), Locale('en')],
      home: const _AppEntry(),
    );
  }
}

/// 🔴 #124 앱의 첫 화면을 고르는 곳.
///
/// ```
///   1) 스플래시 (IntroSplash 위젯)  — 1.4초, **매번** 보인다
///   2) 로그인됨   -> MainDsScreen
///   3) 비로그인   -> 게스트로 들어간다 -> MainDsScreen      (#192)
///   4) 게스트도 안 되면 -> IntroDsScreen -> SplashDsScreen(로그인)
/// ```
///
/// 🔴 #192 에서 **게스트 체험**이 들어왔다. 전에는 앱이 뭘 해 주는지
///    보기도 전에 가입을 해야 했다. 이제 로그인 없이 바로 홈으로 가고,
///    영수증 5장까지 찍어 본 뒤 마음에 들면 가입한다.
///    로그인 화면은 "이미 가입하셨나요? 로그인" 으로만 연다.
///
/// 🔴 4) 는 Firebase 콘솔에서 익명 로그인이 꺼져 있거나 인터넷이 없을
///    때다. 그때는 예전처럼 인트로 → 로그인으로 간다. 게스트가 안 된다고
///    앱이 멈추면 안 된다.
class _AppEntry extends StatefulWidget {
  const _AppEntry();

  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> {
  /// 스플래시를 지나왔나.
  bool _splashDone = false;

  /// 인트로를 지나왔나. (이번 실행 동안만 기억한다 — 저장하지 않는다)
  bool _introDone = false;

  /// 게스트로 들어가 보는 중인가. (#192)
  bool _guestTrying = false;

  /// 게스트 시도를 이미 했나. 한 번만 한다 — 실패했는데 계속 다시
  /// 시도하면 로그인 화면이 영영 안 보인다.
  bool _guestTried = false;

  @override
  void initState() {
    super.initState();
    // 스플래시는 '잠깐 띄워지는 이미지'다. 1.4초면 로고를 읽을 수 있고
    // 기다린다는 느낌도 들지 않는다.
    Future<void>.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _splashDone = true);
    });
  }

  /// 로그인 안 돼 있으면 게스트로 들어간다. (#192)
  ///
  /// 🔴 `build` 안에서 부르지만 **딱 한 번만** 돈다(`_guestTried`).
  ///    익명 로그인이 꺼져 있으면 실패하는데, 그때마다 다시 시도하면
  ///    로그인 화면으로 넘어가질 못한다.
  Future<void> _tryGuest() async {
    if (_guestTried) return;
    _guestTried = true;
    setState(() => _guestTrying = true);
    var ok = false;
    try {
      ok = await GuestService.instance.enterAsGuest();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() => _guestTrying = false);
    if (ok) {
      // 첫 방문을 남긴다. 화면은 바뀌지 않는다.
      unawaited(FnAnalytics.guestStart());
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    // 스플래시 중이거나, 세션 부트스트랩(토큰 갱신) 중이면 스플래시를
    // 띄운다. 로그인 화면이 잠깐 번쩍이는 것을 막는다.
    if (!_splashDone || auth.isBootstrapping) {
      return const Scaffold(body: IntroSplash());
    }

    // 🔴 스플래시가 끝났는데 로그인이 안 돼 있다 → 게스트로 들어간다.
    //    `addPostFrameCallback` 으로 미루는 이유: build 안에서 바로
    //    `setState` 를 부르면 Flutter 가 거부한다.
    if (!auth.isLoggedIn && !_guestTried) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_tryGuest());
      });
    }

    if (auth.isLoggedIn) return const MainDsScreen();

    // 🔴 게스트로 들어가 보는 중이다(#192). 스플래시를 유지해서
    //    로그인 화면이 한 번 번쩍이는 것을 막는다.
    if (_guestTrying) {
      return const Scaffold(body: IntroSplash());
    }

    // 게스트도 안 됐다. 예전 길(인트로 → 로그인)로 간다.
    if (!_introDone) {
      return IntroDsScreen(
        onDone: () => setState(() => _introDone = true),
      );
    }

    return const SplashDsScreen();
  }
}
