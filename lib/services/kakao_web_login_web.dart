import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'kakao_web_login_types.dart';

export 'kakao_web_login_types.dart';

/// 웹 카카오 로그인 — **카카오 SDK 를 쓰지 않는 직접 OAuth 구현.**
///
/// 왜 SDK 를 버렸는지는 `kakao_web_login_types.dart` 상단의 실측표를 보라.
/// 요약하면 SDK 웹 구현이 토큰 교환에 `os/javascript` 를 하드코딩해서 붙이고,
/// 그것만으로 카카오가 요청을 거부한다(KOE009 → 화면에는 KOE101).
/// `origin` 값은 무관해서 콘솔 설정으로는 절대 고칠 수 없다.
///
/// 여기서는 표준 OAuth 2.0 Authorization Code + PKCE 를 직접 구현한다.
///   ① `/oauth/authorize` 로 **페이지 전체를 이동**시킨다.
///   ② 사용자가 카카오에서 로그인/동의한다.
///   ③ 카카오가 `?code=…` 를 붙여 우리 사이트로 돌려보낸다.
///   ④ 부팅 시 그 `code` 를 감지해 `/oauth/token` 으로 교환한다.
///      이때 `KA` 헤더를 **붙이지 않는다** → 문제의 검증이 발생하지 않는다.
///
/// 🔴 팝업이 아니라 **전체 페이지 이동**을 쓰는 이유
///
/// 휴대폰 브라우저에서 팝업은 신뢰할 수 없다. 크롬/삼성인터넷은 팝업을
/// 새 탭으로 열고, 원래 탭과의 `window.opener` 연결이 끊기거나 백그라운드로
/// 내려가면서 폴링이 죽는다. SDK 의 팝업 경로가 최대 600초(1초 × 600회)를
/// 기다리다 조용히 실패하는 것도 이 때문이다. 사장님 증상이 휴대폰에서만
/// 재현된 것과 정확히 일치한다.
/// 전체 페이지 이동은 카카오·구글이 모바일 웹에서 권장하는 방식이고,
/// 팝업 차단·인앱 브라우저 문제도 함께 사라진다.
///
/// 🔴 `client_secret` 을 쓰지 않는 이유 (ask#90 실측으로 확정)
///
/// 브라우저 코드는 사용자가 열어볼 수 있어서 비밀값을 둘 수 없다. 대신
/// PKCE(`code_challenge`/`code_verifier`)로 code 가로채기를 막는다.
///
/// 그리고 **JS 키는 애초에 `client_secret` 을 검사하지 않는다.** 같은 요청을
/// 시크릿만 바꿔가며 던져본 결과(`/oauth/token`, code=FAKE):
///
/// | client_id | client_secret | 결과 |
/// |---|---|---|
/// | JS 키   | 아예 없음        | KOE320 (통과) |
/// | JS 키   | `AAAA…` 쓰레기값 | KOE320 (통과) |
/// | JS 키   | 빈 문자열        | KOE320 (통과) |
/// | JS 키   | 진짜 시크릿      | KOE320 (통과) |
/// | REST 키 | 아예 없음        | **KOE010** |
/// | REST 키 | `AAAA…` 쓰레기값 | **KOE010** |
/// | REST 키 | 진짜 시크릿      | KOE320 (통과) |
///
/// JS 키는 **틀린 시크릿을 줘도 통과**한다 → 검사 자체를 안 한다는 뜻이다.
/// 반대로 REST 키는 시크릿이 맞아야만 통과한다. 즉 클라이언트 시크릿은
/// REST API 키에만 걸리는 기능이고, 우리 웹 로그인(JS 키)과는 무관하다.
/// 그러므로 시크릿을 브라우저에 심을 필요도, 서버로 옮길 필요도 없다.
///
/// 🔴 그래도 신원 검증은 서버가 한다
///
/// 여기서 얻는 건 액세스 토큰뿐이다. "내가 카카오 몇번 사용자"라는 주장은
/// 앱이 아니라 서버 함수(`kakaoCustomToken`)가 카카오에 직접 물어서
/// 확인한다. 그 구조는 그대로 유지되므로 보안이 약해지지 않는다.

const String _authorizeUrl = 'https://kauth.kakao.com/oauth/authorize';
const String _tokenUrl = 'https://kauth.kakao.com/oauth/token';

/// 리다이렉트를 건너가며 값을 들고 있을 곳.
///
/// 🔴 반드시 `sessionStorage` 여야 한다. 페이지가 통째로 카카오로 갔다가
/// 돌아오므로 메모리에 둔 변수는 전부 사라진다. `localStorage` 는 탭 사이에
/// 공유돼서, 두 탭에서 동시에 로그인하면 서로의 값을 밟는다.
/// 🔴 `sessionStorage` 하나로는 **홈 화면 앱(PWA)에서 로그인이 깨진다.**
///
/// 홈 화면에 추가한 앱은 브라우저와 분리된 창에서 돈다. 카카오 로그인은
/// 페이지가 통째로 카카오로 넘어가는데, 이때 안드로이드는 카카오 화면을
/// **원래 창이 아닌 별도의 브라우저 탭(Custom Tab)** 에서 열 수 있다.
/// 그러면 돌아온 곳이 처음 출발한 창이 아니게 되고, `sessionStorage` 는
/// 창(탭)마다 따로이므로 저장해둔 `state`/`verifier` 가 **사라진다.**
/// 결과는 `state-mismatch` — 사장님 눈에는 "로그인을 눌렀는데 튕긴다".
///
/// 그래서 `sessionStorage` 와 `localStorage` **양쪽에** 쓰고, 읽을 때는
/// sessionStorage 를 먼저 본다. localStorage 는 창을 넘어서도 남는다.
///
/// localStorage 를 쓰면 "두 탭에서 동시에 로그인하면 서로를 밟는다" 는
/// 문제가 생기는데, 그건 아래 `_kIssued` 만료 검사로 막는다. 어차피
/// 그 상황은 극히 드물고, 홈 화면 앱이 아예 로그인 안 되는 쪽이 훨씬 나쁘다.
const String _kVerifier = 'fn_kakao_pkce_verifier';
const String _kState = 'fn_kakao_oauth_state';
const String _kReturn = 'fn_kakao_return_path';

/// 로그인 시작 시각(ms). 오래된 찌꺼기를 재사용하지 않기 위해 둔다.
const String _kIssued = 'fn_kakao_oauth_issued';

/// 시작 후 이 시간이 지난 값은 버린다. 카카오 화면에서 10분 넘게
/// 머무는 경우는 사실상 이탈이고, 남은 값을 계속 들고 있으면 다음 로그인
/// 시도에서 엉뚱한 `state` 와 비교하게 된다.
const Duration _oauthTtl = Duration(minutes: 10);

/// 카카오 콘솔에 등록된 리다이렉트 URI.
///
/// 🔴 콘솔 등록값과 **문자 하나까지** 같아야 한다. 카카오 공식 문서:
/// "프로토콜(http, https), 도메인, 경로, **끝의 슬래시(/)** 가 다르면 다른
/// URI로 판단됩니다." 하나라도 다르면 KOE006 이 뜬다 (ask#90 에서 발생).
///
/// 기본값은 `window.location.origin` — 끝에 슬래시가 없는
/// `https://flownote-404ef.web.app` 형태다. 경로 없는 도메인만 등록하는 것도
/// 카카오가 허용하므로(공식 문서 확인) 이 값이 정답이어야 한다.
///
/// 🔴 그런데 콘솔 등록값이 끝에 슬래시가 붙는 등 미묘하게 다를 수 있어서,
/// **빌드 타임에 덮어쓸 수 있게** 열어둔다. 그러면 콘솔 값이 어떤 형태든
/// 코드를 고치지 않고 `secrets/kakao.json` 의 `KAKAO_REDIRECT_URI` 만
/// 맞춰주면 된다. 값이 없으면 origin 을 쓴다(지금 동작 그대로).
String _redirectUri() {
  const override =
      String.fromEnvironment('KAKAO_REDIRECT_URI', defaultValue: '');
  if (override.isNotEmpty) return override;
  return web.window.location.origin;
}

/// URL 에 카카오가 붙여준 `code` 가 있는가 (= 로그인하고 막 돌아왔는가).
bool kakaoWebLoginReturning() {
  final p = _params();
  return p['code'] != null || p['error'] != null;
}

/// 리다이렉트로 돌아온 직후 호출 — `code` 를 액세스 토큰으로 교환한다.
///
/// 돌아온 상황이 아니면 `null` 을 준다(그게 정상이다).
/// 성공/실패 어느 쪽이든 URL 의 쿼리를 지워서, 새로고침할 때 이미 써버린
/// code 로 다시 교환을 시도하는 일이 없게 한다.
Future<KakaoWebToken?> kakaoWebFinishRedirect() async {
  final p = _params();
  final code = p['code'];
  final err = p['error'];
  if (code == null && err == null) return null;

  final expectedState = _expired() ? null : _read(_kState);
  final verifier = _read(_kVerifier);
  _clean(); // 저장값 + URL 쿼리 정리 (한 번만 쓰고 버린다)

  if (err != null) {
    // 사용자가 카카오 화면에서 '취소' 를 눌렀다.
    // 카카오는 이때 `error=access_denied` 를 준다. 오류가 아니다.
    if (err == 'access_denied' || err == 'cancel' || err == 'consent_required') {
      throw const KakaoWebLoginCancelled();
    }
    final desc = p['error_description'] ?? '';
    debugPrint('[kakao] authorize 실패: $err $desc  '
        'redirect_uri=${_redirectUri()}');
    throw KakaoWebLoginException(
      desc.isEmpty ? '카카오가 인증을 거부했습니다.' : desc,
      code: err,
    );
  }

  // 🔴 state 검증 — CSRF 방어.
  // 공격자가 자기 code 를 우리 사이트에 던져 남의 세션에 자기 계정을
  // 붙이는 공격(로그인 CSRF)을 막는다. 우리가 만든 난수가 그대로 돌아온
  // 경우에만 진행한다.
  final gotState = p['state'];
  if (expectedState == null || gotState == null || expectedState != gotState) {
    throw const KakaoWebLoginException(
      '로그인 요청이 확인되지 않았습니다.\n다시 시도해 주세요.',
      code: 'state-mismatch',
    );
  }

  return _exchange(code!, verifier);
}

/// 카카오 로그인 시작 — 페이지를 카카오로 보낸다.
///
/// 🔴 이 함수는 **정상적으로는 절대 반환하지 않는다.** 페이지가 이동해버리기
/// 때문이다. 반환값 타입이 `Future<KakaoWebToken>` 인 건 호출부(네이티브와
/// 공용)를 단순하게 두기 위한 것이고, 실제로는 이동이 시작되면 이 뒤의
/// 코드는 실행되지 않는다. 이동이 실패했을 때만 예외로 빠진다.
Future<KakaoWebToken> kakaoWebLogin({required String javaScriptKey}) async {
  if (javaScriptKey.isEmpty) {
    throw const KakaoWebLoginException(
      '카카오 로그인 설정이 없습니다.',
      code: 'no-key',
    );
  }

  final verifier = _randomString(64);
  final state = _randomString(24);
  _write(_kVerifier, verifier);
  _write(_kState, state);
  _write(_kIssued, DateTime.now().millisecondsSinceEpoch.toString());
  // 로그인 후 원래 보던 화면으로 돌려주기 위해 경로를 기억해둔다.
  _write(_kReturn, web.window.location.pathname);

  final challenge = base64Url
      .encode(sha256.convert(utf8.encode(verifier)).bytes)
      .replaceAll('=', ''); // RFC 7636: 패딩 제거

  final uri = Uri.parse(_authorizeUrl).replace(queryParameters: {
    'client_id': javaScriptKey,
    'redirect_uri': _redirectUri(),
    'response_type': 'code',
    'state': state,
    'code_challenge': challenge,
    'code_challenge_method': 'S256',
  });

  debugPrint('[kakao] authorize 이동: redirect_uri=${_redirectUri()}');

  // `assign` 이 아니라 `replace` 를 쓴다. 그래야 카카오에서 뒤로가기를
  // 눌렀을 때 로그인 시작 URL 로 되돌아가 무한 루프가 생기지 않는다.
  web.window.location.replace(uri.toString());

  // 이동이 시작되면 아래는 실행되지 않는다. 여기까지 왔다면 이동이 막힌
  // 것이므로(드물지만 인앱 브라우저에서 발생) 사유를 알려준다.
  await Future<void>.delayed(const Duration(seconds: 3));
  throw const KakaoWebLoginException(
    '카카오 로그인 화면으로 이동하지 못했습니다.\n브라우저에서 다시 시도해 주세요.',
    code: 'navigation-blocked',
  );
}

/// 로그인 후 돌아갈 경로 (없으면 null).
String? kakaoWebReturnPath() => _read(_kReturn);

// ──────────────────────────────────────────────────────────────
// 내부
// ──────────────────────────────────────────────────────────────

/// `code` → 액세스 토큰.
///
/// 🔴 `KA` 헤더를 붙이지 않는 것이 이 우회의 핵심이다. `http` 패키지는
/// 웹에서 `fetch` 를 쓰는데 우리가 지정하지 않은 헤더를 임의로 붙이지
/// 않으므로, 이 요청에는 `os/javascript` 가 들어가지 않는다.
/// (`/oauth/token` 응답에 `Access-Control-Allow-Origin: *` 이 있어서
///  브라우저에서 직접 호출할 수 있다 — 실측 확인)
Future<KakaoWebToken> _exchange(String code, String? verifier) async {
  final body = <String, String>{
    'grant_type': 'authorization_code',
    'client_id': _appKey,
    'redirect_uri': _redirectUri(),
    'code': code,
    if (verifier != null && verifier.isNotEmpty) 'code_verifier': verifier,
  };

  final res = await http
      .post(
        Uri.parse(_tokenUrl),
        headers: const {
          'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8',
        },
        body: body,
      )
      .timeout(const Duration(seconds: 20));

  Map<String, dynamic> json;
  try {
    json = jsonDecode(res.body) as Map<String, dynamic>;
  } catch (_) {
    throw KakaoWebLoginException(
      '카카오 응답을 읽지 못했습니다. (HTTP ${res.statusCode})',
      code: 'bad-response',
    );
  }

  final token = json['access_token'] as String?;
  if (res.statusCode != 200 || token == null || token.isEmpty) {
    // 🔴 원인을 절대 삼키지 않는다. 카카오가 준 코드/설명을 그대로 남긴다.
    // 이전에 이걸 감춰서 "카카오 로그인 중 오류가 발생했습니다." 한 줄만
    // 남았고, 진짜 원인을 찾는 데 여러 차례를 낭비했다.
    final ec = json['error_code'] ?? json['error'] ?? 'HTTP ${res.statusCode}';
    final ed = json['error_description'] ?? '';
    debugPrint('[kakao] token 교환 실패: $ec $ed  '
        'client_id=${_mask(_appKey)} redirect_uri=${_redirectUri()}');

    // 🔴 설정 문제는 사용자가 손댈 수 없으니, 원인을 그대로 알려준다.
    // 그냥 "오류가 발생했습니다" 로 삼키면 원인을 찾는 데 며칠이 날아간다.
    final hint = switch (ec.toString()) {
      'KOE006' => '\n\n(카카오 콘솔에 등록된 리다이렉트 URI 와 '
          '앱이 보낸 값이 다릅니다: ${_redirectUri()})',
      'KOE010' => '\n\n(카카오 앱 키 설정 문제입니다. '
          'JavaScript 키가 맞는지 확인이 필요합니다.)',
      _ => '',
    };
    throw KakaoWebLoginException(
      '${ed.toString().isEmpty ? '카카오 인증을 완료하지 못했습니다.' : ed}$hint',
      code: ec.toString(),
    );
  }
  return KakaoWebToken(token);
}

/// 토큰 교환에 쓸 앱 키. `kakaoWebLogin` 시작 시점의 키를 리다이렉트
/// 이후에도 써야 하므로 컴파일 타임 값을 그대로 읽는다.
String get _appKey =>
    const String.fromEnvironment('KAKAO_JS_KEY', defaultValue: '');

/// 로그에 키를 통째로 남기지 않는다. 앞 6자리만 보여도 어떤 키인지 안다.
String _mask(String s) =>
    s.length <= 6 ? '(빈값)' : '${s.substring(0, 6)}…(${s.length}자)';

Map<String, String?> _params() {
  final q = web.window.location.search;
  if (q.isEmpty || q == '?') return const {};
  final parsed = Uri.splitQueryString(q.startsWith('?') ? q.substring(1) : q);
  return {
    'code': parsed['code'],
    'state': parsed['state'],
    'error': parsed['error'],
    'error_description': parsed['error_description'],
  };
}

/// 저장값과 URL 쿼리를 정리한다.
///
/// URL 을 안 지우면 새로고침 때 이미 소비된 code 로 재교환을 시도해
/// KOE320 이 뜬다. 사용자에게는 "됐다가 새로고침하면 오류" 로 보인다.
/// 저장해둔 값이 너무 오래됐는가.
///
/// localStorage 는 창을 닫아도 남으므로, 만료를 안 보면 몇 시간 전 찌꺼기와
/// 지금 돌아온 `state` 를 비교하게 된다. 시각 자체가 없으면(구버전에서
/// 넘어온 경우) 만료로 보지 않는다 — 없앨 이유가 없다.
bool _expired() {
  final raw = _read(_kIssued);
  if (raw == null) return false;
  final ms = int.tryParse(raw);
  if (ms == null) return false;
  final age = DateTime.now().millisecondsSinceEpoch - ms;
  final over = age > _oauthTtl.inMilliseconds;
  if (over) debugPrint('[kakao] 오래된 로그인 요청($age ms) — 버린다');
  return over;
}

void _clean() {
  _remove(_kVerifier);
  _remove(_kState);
  _remove(_kIssued);
  try {
    final loc = web.window.location;
    web.window.history
        .replaceState(null, '', '${loc.pathname}${loc.hash}');
  } catch (_) {/* history 를 못 써도 로그인 자체는 진행된다 */}
}

String _randomString(int len) {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  final rnd = Random.secure();
  return List.generate(len, (_) => chars[rnd.nextInt(chars.length)]).join();
}

/// sessionStorage → localStorage 순서로 찾는다.
///
/// 같은 창으로 정상 복귀한 경우엔 sessionStorage 에서 바로 나온다.
/// 홈 화면 앱처럼 창이 바뀐 경우에만 localStorage 를 타게 된다.
String? _read(String k) {
  try {
    final v = web.window.sessionStorage.getItem(k);
    if (v != null && v.isNotEmpty) return v;
  } catch (_) {/* 접근 불가 — localStorage 를 시도한다 */}
  try {
    final v = web.window.localStorage.getItem(k);
    if (v != null && v.isNotEmpty) return v;
  } catch (_) {/* 시크릿 모드 등 — 아래에서 state 불일치로 잡힌다 */}
  return null;
}

/// 양쪽에 쓴다. 하나가 막혀 있어도 다른 하나로 복귀할 수 있다.
void _write(String k, String v) {
  try {
    web.window.sessionStorage.setItem(k, v);
  } catch (_) {}
  try {
    web.window.localStorage.setItem(k, v);
  } catch (_) {}
}

void _remove(String k) {
  try {
    web.window.sessionStorage.removeItem(k);
  } catch (_) {}
  try {
    web.window.localStorage.removeItem(k);
  } catch (_) {}
}
