import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'pwa_install_types.dart';

export 'pwa_install_types.dart';

/// 웹 구현 — "홈 화면에 추가" 가능 여부 판별 + 설치 프롬프트.
///
/// 브라우저마다 방식이 완전히 다르다.
///
///  - 안드로이드 크롬 계열: 브라우저가 `beforeinstallprompt` 이벤트를 준다.
///    이걸 잡아두면 우리가 원하는 순간에 설치창을 띄울 수 있다.
///  - 아이폰 사파리: 그런 API 가 **없다.** 공유 버튼 → "홈 화면에 추가" 를
///    사람이 직접 눌러야 한다. 그래서 안내 문구만 보여줄 수 있다.
///  - 아이폰의 크롬·네이버·카카오 인앱 브라우저: 홈 화면 추가가 아예
///    안 된다. 사파리로 열라고 안내해야 한다.
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
      debugPrint('[pwa] 홈 화면에 추가 완료');
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

  if (_isIos(ua)) {
    // 아이폰/아이패드는 사파리에서만 홈 화면 추가가 된다.
    return PwaInstallState(
      howTo: _isIosSafari(ua) ? PwaHowTo.iosSafari : PwaHowTo.iosOther,
      canPrompt: false,
    );
  }

  if (ua.contains('android')) {
    // 프롬프트를 실제로 받아둔 경우에만 버튼을 준다.
    // 안 받았는데 버튼을 주면 눌러도 아무 일이 안 생긴다.
    return _deferred != null
        ? const PwaInstallState(howTo: PwaHowTo.androidPrompt, canPrompt: true)
        : const PwaInstallState(howTo: PwaHowTo.androidManual, canPrompt: false);
  }

  // PC. 프롬프트가 있으면 그대로 쓴다.
  if (_deferred != null) {
    return const PwaInstallState(howTo: PwaHowTo.desktop, canPrompt: true);
  }
  return const PwaInstallState(howTo: PwaHowTo.desktop, canPrompt: false);
}

Future<PwaPromptResult> pwaPromptInstall() async {
  final ev = _deferred;
  if (ev == null) return PwaPromptResult.unavailable;

  try {
    // ev.prompt() — 설치창을 띄운다.
    await ev.callMethod<JSPromise<JSAny?>>('prompt'.toJS).toDart;

    // ev.userChoice — {outcome: 'accepted' | 'dismissed'} 로 resolve 된다.
    final choice = await ev
        .getProperty<JSPromise<JSObject>>('userChoice'.toJS)
        .toDart;
    final outcome =
        choice.getProperty<JSString?>('outcome'.toJS)?.toDart ?? '';
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

/// 이미 홈 화면(독립 창)에서 실행 중인가.
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
    'naver', // 네이버 앱
    'whale', // 웨일
    'kakaotalk', // 카카오톡 인앱
    'kakaostory',
    'daumapps',
    'line/', // 라인 인앱
    'instagram',
    'fban', // 페이스북 인앱
    'fbav',
  ];
  for (final o in others) {
    if (ua.contains(o)) return false;
  }
  return ua.contains('safari');
}

