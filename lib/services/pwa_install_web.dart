import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'pwa_install_types.dart';

export 'pwa_install_types.dart';

/// 웹 구현 — "바탕화면에 설치" 가능 여부 판별 + 설치 프롬프트.
///
/// 브라우저마다 방식이 완전히 다르다.
///
///  - 안드로이드 크롬 계열: 브라우저가 `beforeinstallprompt` 이벤트를 준다.
///    이걸 잡아두면 우리가 원하는 순간에 설치창을 띄울 수 있다.
///  - 아이폰 사파리: 그런 API 가 **없다.** 공유 버튼 → "홈 화면에 추가" 를
///    사람이 직접 눌러야 한다. 그래서 안내 문구만 보여줄 수 있다.
///  - 카카오톡·인스타그램 인앱 브라우저: 설치가 **아예 안 된다.**
///    사파리·크롬으로 옮겨야 한다. 카카오톡만 외부 브라우저로 넘기는
///    주소를 지원한다.
///
/// 판별을 틀리면 "버튼을 눌러도 아무 일이 안 생기는" 최악의 경험이 되므로,
/// 프롬프트를 실제로 받았는지(`_deferred != null`)를 기준으로 갈라준다.

/// 브라우저가 준 `beforeinstallprompt` 이벤트를 보관한다.
///
/// 이 이벤트는 **한 번만** 오고, `preventDefault()` 로 막아두지 않으면
/// 브라우저가 자기 배너를 띄워버린다. 그래서 앱이 시작될 때 바로 잡아둔다.
///
/// 타입은 `JSObject` 로 둔다. `package:web` 에 `BeforeInstallPromptEvent`
/// 타입이 없고, 이 프로젝트의 Dart 언어 버전(`sdk: '>=3.0.0'`)은
/// `extension type` 을 지원하지 않기 때문이다. 대신
/// `js_interop_unsafe` 의 `callMethod`/`getProperty` 로 접근한다.
JSObject? _deferred;

/// `appinstalled` 를 받은 뒤에는 안내를 그리지 않는다.
bool _installed = false;

bool _inited = false;

void pwaInit() {
  if (_inited) return;
  _inited = true;

  web.window.addEventListener(
    'beforeinstallprompt',
    (web.Event e) {
      // 브라우저 기본 배너를 막고 우리가 원하는 시점에 띄운다.
      e.preventDefault();
      _deferred = e as JSObject;
      debugPrint('[pwa] beforeinstallprompt 수신 — 설치 프롬프트 사용 가능');
    }.toJS,
  );

  web.window.addEventListener(
    'appinstalled',
    (web.Event _) {
      _installed = true;
      _deferred = null;
      debugPrint('[pwa] 바탕화면에 설치 완료');
    }.toJS,
  );
}

PwaInstallState pwaState() {
  if (_isStandalone() || _installed) {
    return const PwaInstallState(
      howTo: PwaHowTo.alreadyInstalled,
      canPrompt: false,
    );
  }

  final ua = _ua();
  final ios = _isIos(ua);
  final url = _href();

  // 🔴 인앱 브라우저를 **가장 먼저** 가른다.
  //    아이폰 인앱은 UA 에 'safari' 가 그대로 들어 있어서, 뒤에서 보면
  //    사파리로 오인하고 "공유 버튼을 누르세요" 라는 틀린 안내를 한다.
  final inApp = _inAppKind(ua);
  if (inApp != null) {
    return PwaInstallState(
      howTo: inApp,
      canPrompt: false,
      onIos: ios,
      url: url,
    );
  }

  if (ios) {
    // 아이폰/아이패드는 사파리에서만 바탕화면 추가가 된다.
    return PwaInstallState(
      howTo: _isIosSafari(ua) ? PwaHowTo.iosSafari : PwaHowTo.iosOther,
      canPrompt: false,
      onIos: true,
      url: url,
    );
  }

  if (ua.contains('android')) {
    // 프롬프트를 실제로 받아둔 경우에만 버튼을 준다.
    // 안 받았는데 버튼을 주면 눌러도 아무 일이 안 생긴다.
    return PwaInstallState(
      howTo: _deferred != null ? PwaHowTo.androidPrompt : PwaHowTo.androidManual,
      canPrompt: _deferred != null,
      url: url,
    );
  }

  // PC. 프롬프트가 있으면 그대로 쓴다.
  return PwaInstallState(
    howTo: PwaHowTo.desktop,
    canPrompt: _deferred != null,
    url: url,
  );
}

Future<PwaPromptResult> pwaPromptInstall() async {
  final ev = _deferred;
  if (ev == null) return PwaPromptResult.unavailable;

  try {
    // ev.prompt() — 설치창을 띄운다.
    await ev.callMethod<JSPromise<JSAny?>>('prompt'.toJS).toDart;

    // ev.userChoice — {outcome: 'accepted' | 'dismissed'} 로 resolve 된다.
    final choice =
        await ev.getProperty<JSPromise<JSObject>>('userChoice'.toJS).toDart;
    final outcome = choice.getProperty<JSString?>('outcome'.toJS)?.toDart ?? '';
    debugPrint('[pwa] 설치 프롬프트 결과: $outcome');

    // 이벤트는 재사용할 수 없다. 한 번 쓰면 버린다.
    _deferred = null;

    if (outcome == 'accepted') {
      _installed = true;
      return PwaPromptResult.installed;
    }
    return PwaPromptResult.dismissed;
  } catch (e) {
    debugPrint('[pwa] 설치 프롬프트 실패: $e');
    _deferred = null;
    return PwaPromptResult.unavailable;
  }
}

/// 🔴 카카오톡 인앱 브라우저를 **외부 브라우저로 넘긴다.**
///
/// 카카오톡은 `kakaotalk://web/openExternal?url=…` 주소를 받으면 지금
/// 페이지를 기본 브라우저(사파리·크롬)로 다시 열어 준다. 인앱에서는
/// 바탕화면 설치가 아예 막혀 있어서, 안내문을 읽히기 전에 자동으로
/// 옮겨 주는 쪽이 사장님께 훨씬 빠르다.
///
/// 넘어갔는지 **여기서는 알 수 없다.** 넘어가면 이 화면이 가려지므로,
/// 부르는 쪽이 잠깐 기다렸다가 [pwaPageVisible] 로 확인하고 아직
/// 보이면 안내창을 띄운다.
bool pwaOpenExternalBrowser() {
  try {
    final url = _href();
    if (url.isEmpty) return false;
    final enc = Uri.encodeComponent(url);
    web.window.location.href = 'kakaotalk://web/openExternal?url=$enc';
    return true;
  } catch (e) {
    debugPrint('[pwa] 외부 브라우저 전환 실패: $e');
    return false;
  }
}

/// 이 화면이 아직 사용자에게 보이는가.
///
/// 외부 브라우저로 넘어갔다면 카카오톡이 뒤로 가므로 `hidden` 이 된다.
bool pwaPageVisible() {
  try {
    return web.document.visibilityState != 'hidden';
  } catch (_) {
    return true;
  }
}

// ─────────────────────────────────────────────────────────────
// 판별 유틸
// ─────────────────────────────────────────────────────────────

String _ua() {
  try {
    return web.window.navigator.userAgent.toLowerCase();
  } catch (_) {
    return '';
  }
}

String _href() {
  try {
    return web.window.location.href;
  } catch (_) {
    return '';
  }
}

/// 인앱 브라우저인가. 맞으면 어느 앱인지 돌려준다.
PwaHowTo? _inAppKind(String ua) {
  if (ua.contains('kakaotalk')) return PwaHowTo.inAppKakao;
  if (ua.contains('instagram')) return PwaHowTo.inAppInstagram;
  const others = [
    'fbav', // 페이스북
    'fban',
    'fb_iab',
    'line/',
    'naver(inapp', // 네이버 앱
    'naver ',
    'daumapps',
    'kakaostory',
    'everytimeapp',
    'band/',
    'trill', // 틱톡
    'musical_ly',
  ];
  for (final o in others) {
    if (ua.contains(o)) return PwaHowTo.inAppOther;
  }
  return null;
}

/// 이미 바탕화면(독립 창)에서 실행 중인가.
bool _isStandalone() {
  try {
    // 표준: display-mode 미디어 쿼리.
    for (final q in const [
      '(display-mode: standalone)',
      '(display-mode: fullscreen)',
      '(display-mode: minimal-ui)',
    ]) {
      if (web.window.matchMedia(q).matches) return true;
    }
  } catch (_) {
    // 무시 — 아래 iOS 전용 검사로 넘어간다.
  }

  try {
    // 아이폰 사파리는 display-mode 를 오래 지원하지 않았고,
    // 대신 비표준 `navigator.standalone` 을 준다.
    final nav = web.window.navigator as JSObject;
    final v = nav.getProperty<JSBoolean?>('standalone'.toJS);
    if (v != null && v.toDart) return true;
  } catch (_) {
    // 무시
  }

  return false;
}

bool _isIos(String ua) {
  if (ua.contains('iphone') || ua.contains('ipad') || ua.contains('ipod')) {
    return true;
  }
  // 🔴 iPadOS 13+ 는 데스크톱 사파리처럼 'macintosh' 로 위장한다.
  //
  // 그래서 UA 만 보면 아이패드를 PC 로 착각한다. 터치 포인트 개수로
  // 갈라준다 — 맥은 0, 아이패드는 5.
  if (ua.contains('macintosh')) {
    try {
      final nav = web.window.navigator as JSObject;
      final n = nav.getProperty<JSNumber?>('maxTouchPoints'.toJS);
      if (n != null && n.toDartInt > 1) return true;
    } catch (_) {
      // 무시
    }
  }
  return false;
}

/// 아이폰에서 **사파리인가.**
///
/// 아이폰의 모든 브라우저는 내부적으로 사파리 엔진을 쓰므로 UA 에
/// 'safari' 가 그대로 들어있다. 따라서 "safari 가 있다" 로는 판별이 안 되고,
/// 다른 브라우저들의 고유 표식이 없는지를 확인해야 한다.
bool _isIosSafari(String ua) {
  const others = [
    'crios', // 크롬
    'fxios', // 파이어폭스
    'edgios', // 엣지
    'opt/', // 오페라 터치
    'whale', // 웨일
  ];
  for (final o in others) {
    if (ua.contains(o)) return false;
  }
  return ua.contains('safari');
}
