#!/usr/bin/env bash
# Gemini API 키를 주입해서 릴리즈 APK 를 빌드한다.
#
#   1) secrets/gemini.example.json 을 secrets/gemini.json 으로 복사하고 키를 채운다
#   2) ./tool/build_apk.sh              → 아키텍처별 분리 APK (권장, 용량 작음)
#      ./tool/build_apk.sh --fat        → 단일 통합 APK (아무 기기나 설치 가능)
#
# 서명은 android/key.properties + android/release-key.jks 를 사용한다.
set -euo pipefail
cd "$(dirname "$0")/.."

export ANDROID_HOME="${ANDROID_HOME:-$HOME/android-sdk}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"

# Gradle 은 javac 가 있는 JDK 가 필요하다 (시스템 java 는 JRE 만 있는 경우가 있다).
for cand in "${JAVA_HOME:-}" "$HOME/jdks"/jdk-17*; do
  if [[ -n "$cand" && -x "$cand/bin/javac" ]]; then
    export JAVA_HOME="$cand"
    export PATH="$JAVA_HOME/bin:$PATH"
    break
  fi
done
if [[ ! -x "${JAVA_HOME:-}/bin/javac" ]]; then
  echo "!! javac 가 있는 JDK 를 찾지 못했습니다. JAVA_HOME 을 JDK 로 지정하세요." >&2
  exit 1
fi
echo "==> JAVA_HOME=$JAVA_HOME"

ARGS=(build apk --release)
if [[ "${1:-}" == "--fat" ]]; then
  echo "==> 단일 통합(fat) APK 로 빌드합니다"
else
  echo "==> 아키텍처별 분리 APK 로 빌드합니다 (--fat 로 통합 APK 선택 가능)"
  ARGS+=(--split-per-abi)
fi

# 🔴 키가 없으면 **빌드를 거부한다.**
#
# Build 22~24 가 `flutter build apk` 를 직접 실행해서 만들어졌고, 그 결과
# GEMINI_API_KEY 가 빈 문자열로 컴파일됐다. 앱은 스캔할 때마다 실패했는데
# 화면에는 "조명이 밝은 곳에서 다시 찍어주세요" 만 떠서 원인을 알 수 없었다.
# 조용히 망가진 APK 를 내보내는 것보다 빌드가 멈추는 게 낫다.
# 의도적으로 키 없이 만들려면  ALLOW_NO_KEY=1 ./tool/build_apk.sh
if [[ -f secrets/gemini.json ]]; then
  echo "==> secrets/gemini.json 에서 Gemini 설정을 주입합니다"
  ARGS+=(--dart-define-from-file=secrets/gemini.json)
elif [[ "${ALLOW_NO_KEY:-}" == "1" ]]; then
  echo "!! 경고: 키 없이 빌드합니다 (ALLOW_NO_KEY=1). 이 APK 는 스캔이 안 됩니다."
else
  echo "!! secrets/gemini.json 이 없습니다. 빌드를 중단합니다." >&2
  echo "   이 파일 없이 만든 APK 는 영수증 스캔이 전부 실패합니다." >&2
  echo "   1) cp secrets/gemini.example.json secrets/gemini.json" >&2
  echo "   2) GEMINI_API_KEY 를 채운다" >&2
  echo "   그래도 키 없이 빌드하려면: ALLOW_NO_KEY=1 $0" >&2
  exit 1
fi

# 카카오 네이티브 앱 키 주입.
#
# 없어도 빌드는 된다(카카오 버튼이 "준비 중" 으로 남을 뿐, 다른 기능은
# 전부 정상). Gemini 키처럼 빌드를 막지는 않는다.
# Android 리다이렉트 스킴은 build.gradle.kts 가 같은 파일을 직접 읽는다.
if [[ -f secrets/kakao.json ]]; then
  echo "==> secrets/kakao.json 에서 카카오 앱 키를 주입합니다"
  ARGS+=(--dart-define-from-file=secrets/kakao.json)
else
  echo "!! secrets/kakao.json 이 없습니다. 카카오 로그인은 '준비 중' 으로 표시됩니다."
  echo "   활성화하려면: cp secrets/kakao.example.json secrets/kakao.json 후 키를 채우세요."
fi

flutter "${ARGS[@]}"
echo
echo "==> 결과물:"
ls -la build/app/outputs/flutter-apk/*.apk 2>/dev/null || true
