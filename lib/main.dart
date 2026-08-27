import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'models/receipt_model.dart';
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
import 'services/vendor_tax_service.dart';
import 'services/subscription_service.dart';
import 'services/kakao_config.dart';
import 'services/pwa_install.dart';
import 'theme/app_theme.dart';
import 'screens/ds/splash_ds_screen.dart';
import 'screens/ds/main_ds_screen.dart';

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

class _AppEntry extends StatelessWidget {
  const _AppEntry();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    // 세션 부트스트랩(토큼 갱슱) 중엔 로그인화면이 잠긐 보이는 것을 막는다.
    if (auth.isBootstrapping) {
      return const Scaffold(
        backgroundColor: Color(0xFFFFFCFA),
        body: Center(
          child: SizedBox(
            width: 84,
            height: 84,
            child: Image(image: AssetImage('assets/icon/app_icon.png')),
          ),
        ),
      );
    }

    return auth.isLoggedIn ? const MainDsScreen() : const SplashDsScreen();
  }
}
