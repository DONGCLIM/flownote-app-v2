#!/usr/bin/env bash
# 웹(PWA) 릴리즈 빌드 + (선택) Firebase Hosting 배포.
#
#   ./tool/build_web.sh            → build/web 만 만든다
#   ./tool/build_web.sh --deploy   → 만들고 flownote-404ef.web.app 에 올린다
#
# 🔴 왜 `flutter build web` 을 직접 쓰지 않는가
#
# APK 와 똑같은 이유다. `build_apk.sh` 없이 만든 Build 22~24 는
# GEMINI_API_KEY 가 빈 문자열로 컴파일돼서 스캔이 전부 실패했다.
# 실제로 이 스크립트를 만들기 전에 손으로 돌린 첫 웹 빌드도
# 브라우저 콘솔에 이렇게 남겼다:
#
#   [boot] ⚠️ OCR 키가 빌드에 없습니다 — 스캔이 실패합니다.
#
# 웹에서 스캔을 쓸지는 아직 결정되지 않았지만(사장님 Q1 미회신),
# 키가 조용히 빠진 빌드를 배포하는 건 어떤 경우에도 손해다.
set -euo pipefail
cd "$(dirname "$0")/.."

DEPLOY=0
[[ "${1:-}" == "--deploy" ]] && DEPLOY=1

# 🔴 `--pwa-strategy=none` 을 뺐다 (이 스크립트의 이전 버전에는 있었다).
#
# 그 플래그는 서비스 워커를 아예 생성하지 않는다. 서비스 워커가 없으면
# 브라우저가 "홈 화면에 추가" 를 설치형 앱으로 취급하지 않는다.
# 즉 그 상태로는 모아와처럼 아이콘을 만들 수 없었다.
# 지금은 설치 가능해야 하므로 기본값(offline-first)을 쓴다.
# 캐시가 오래 남는 문제는 firebase.json 의 헤더에서
# flutter_service_worker.js / index.html 을 no-cache 로 지정해 막았다.
ARGS=(build web --release)

# ── Gemini(OCR) 키 ──────────────────────────────────────────
if [[ -f secrets/gemini.json ]]; then
  echo "==> secrets/gemini.json 에서 Gemini 설정을 주입합니다"
  ARGS+=(--dart-define-from-file=secrets/gemini.json)
elif [[ "${ALLOW_NO_KEY:-}" == "1" ]]; then
  echo "!! 경고: 키 없이 빌드합니다 (ALLOW_NO_KEY=1). 스캔이 안 됩니다."
else
  echo "!! secrets/gemini.json 이 없습니다. 빌드를 중단합니다." >&2
  echo "   그래도 키 없이 빌드하려면: ALLOW_NO_KEY=1 $0" >&2
  exit 1
fi

# ── 카카오 키 ───────────────────────────────────────────────
#
# ⚠️ 웹 카카오 로그인은 **네이티브 앱 키가 아니라 JavaScript 키**를 쓴다.
#    (카카오 개발자 콘솔 > 앱 키 > JavaScript 키)
#    네이티브 앱 키만 넣고 웹에서 로그인하면 카카오가 KOE101 을 돌려준다.
#
#    secrets/kakao.json 에 두 키를 모두 넣어야 한다.
#      { "KAKAO_NATIVE_APP_KEY": "...",   ← 안드로이드/iOS
#        "KAKAO_JS_KEY":         "..." }  ← 웹
#    KAKAO_JS_KEY 가 비어 있으면 웹의 카카오 버튼은 '준비 중' 으로 남는다.
#
#    키만으로는 부족하다. 카카오 개발자 콘솔 > 플랫폼 > Web 에
#    사이트 도메인(https://flownote-404ef.web.app)도 등록해야 한다.
#    등록이 빠지면 로그인 창은 열리지만 마지막에 리다이렉트가 막힌다.
#
# 🔴 리다이렉트 URI 가 안 맞을 때 (KOE006)
#
#    [앱] > [플랫폼 키] > [JavaScript 키] > [카카오 로그인 리다이렉트 URI]
#    에 등록한 값과 앱이 보내는 값이 **문자 하나까지** 같아야 한다.
#    끝의 슬래시(/) 하나만 달라도 카카오는 다른 URI 로 본다(공식 문서).
#
#    앱은 기본적으로 `window.location.origin`
#    (= https://flownote-404ef.web.app, 끝 슬래시 없음) 을 보낸다.
#    콘솔 등록값이 이와 다른 형태라면 코드를 고치지 말고
#    secrets/kakao.json 에 한 줄만 추가하면 된다:
#      { …, "KAKAO_REDIRECT_URI": "https://flownote-404ef.web.app/" }
#
# ⚠️ 클라이언트 시크릿은 여기에 넣지 않는다.
#    실측 결과 JS 키는 client_secret 을 아예 검사하지 않는다
#    (틀린 시크릿을 줘도 통과). 시크릿은 REST API 키에만 걸리는 기능이다.
#    게다가 웹 번들은 누구나 열어볼 수 있어서 비밀값을 두면 안 된다.
if [[ -f secrets/kakao.json ]]; then
  echo "==> secrets/kakao.json 을 주입합니다 (웹은 JS 키가 별도로 필요)"
  ARGS+=(--dart-define-from-file=secrets/kakao.json)
fi

flutter "${ARGS[@]}"

echo
echo "==> 결과물:"
du -sh build/web 2>/dev/null || true
ls -la build/web/main.dart.js 2>/dev/null || true

if [[ "$DEPLOY" == "1" ]]; then
  echo
  # 서비스 계정으로 인증한다. `firebase login` 은 브라우저가 필요해서
  # 샌드박스/CI 에서 쓸 수 없다.
  if [[ -f .fbkey/sa.json ]]; then
    export GOOGLE_APPLICATION_CREDENTIALS="$PWD/.fbkey/sa.json"
    echo "==> 서비스 계정으로 인증합니다 (.fbkey/sa.json)"
  else
    echo "!! .fbkey/sa.json 이 없습니다. firebase login 상태를 사용합니다."
  fi
  echo "==> Firebase Hosting 에 배포합니다"
  firebase deploy --only hosting --project flownote-404ef
fi
