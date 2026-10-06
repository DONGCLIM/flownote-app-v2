#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════
#  FlowNote 서버 작업 배포 — 양재 경매 시세 일일 요약
#
#  하는 일 (순서대로, 실패하면 즉시 멈춘다)
#   1) 로그인 상태 확인
#   2) 프로젝트 지정          flownote-404ef
#   3) 비밀값 등록            FLOWER_API_KEY  (화훼공판장 서비스키)
#   4) 함수 배포              updateFlowerPrices / updateFlowerPricesNow
#   5) Firestore 규칙 배포
#   6) 첫 데이터 채우기       updateFlowerPricesNow 를 한 번 호출
#
#  쓰는 법
#     FLOWER_API_KEY=xxxxx ./tool/deploy_functions.sh
#
#  🔴 왜 스크립트로 만드나
#     명령을 손으로 하나씩 치면 어디서 실패했는지, 어디까지 갔는지
#     알 수 없다. 특히 3)번 비밀값 등록은 화면에 아무것도 안 찍혀서
#     성공했는지 판단이 안 된다. 각 단계마다 결과를 확인하고 멈춘다.
# ════════════════════════════════════════════════════════════════
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT="flownote-404ef"
REGION="asia-northeast3"
FN_URL="https://${REGION}-${PROJECT}.cloudfunctions.net/updateFlowerPricesNow"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m!! %s\033[0m\n' "$*" >&2; exit 1; }

# ── 0. 준비물 확인 ──────────────────────────────────────────────
command -v firebase >/dev/null || die "firebase CLI 가 없습니다. npm install -g firebase-tools"
[[ -f firebase.json ]] || die "firebase.json 이 없습니다. 저장소 최상위에서 실행하세요."
[[ -d functions/node_modules ]] || {
  say "functions 의존성 설치"
  ( cd functions && npm install )
}

# ── 1. 로그인 확인 ──────────────────────────────────────────────
say "로그인 상태 확인"
if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
  echo "서비스 계정 키 사용: $GOOGLE_APPLICATION_CREDENTIALS"
  [[ -f "$GOOGLE_APPLICATION_CREDENTIALS" ]] || die "키 파일이 없습니다"
elif firebase login:list 2>/dev/null | grep -qi '@'; then
  firebase login:list
else
  die "로그인이 안 되어 있습니다.
   방법 A) firebase login --no-localhost   → 나오는 주소를 브라우저에서 열고
           받은 코드를  firebase login <코드>  로 입력
   방법 B) export GOOGLE_APPLICATION_CREDENTIALS=/경로/서비스계정.json"
fi

# ── 2. 프로젝트 지정 ────────────────────────────────────────────
say "프로젝트 지정: $PROJECT"
firebase use "$PROJECT"

# ── 3. 비밀값 등록 ──────────────────────────────────────────────
# 🔴 서비스키를 스크립트나 저장소에 적지 않는다. 이 저장소는 공개(public)다.
#    반드시 환경변수로 넘긴다:  FLOWER_API_KEY=xxx ./tool/deploy_functions.sh
if [[ -n "${FLOWER_API_KEY:-}" ]]; then
  say "비밀값 FLOWER_API_KEY 등록"
  # --data-file=- 로 stdin 에서 읽는다. 명령줄 인자로 넘기면
  # 프로세스 목록(ps)에 키가 노출된다.
  printf '%s' "$FLOWER_API_KEY" \
    | firebase functions:secrets:set FLOWER_API_KEY --data-file=- --force
else
  echo "FLOWER_API_KEY 환경변수가 없습니다 — 이미 등록돼 있다고 보고 넘어갑니다."
  echo "(등록 여부 확인: firebase functions:secrets:access FLOWER_API_KEY)"
fi

# ── 4. 함수 배포 ────────────────────────────────────────────────
say "함수 배포 (처음이면 API 활성화 때문에 3~7분 걸립니다)"
firebase deploy --only functions

# ── 5. 규칙 배포 ────────────────────────────────────────────────
say "Firestore 규칙 배포"
firebase deploy --only firestore:rules

# ── 6. 첫 데이터 채우기 ─────────────────────────────────────────
# 예약 실행은 매일 새벽 2:30(KST) 이라 지금 당장 데이터가 없다.
# 한 번 직접 호출해서 market/yangjae_latest 문서를 만든다.
say "첫 시세 데이터 채우기"
echo "GET $FN_URL"
code=$(curl -sS -o /tmp/fn_seed.json -w '%{http_code}' --max-time 120 "$FN_URL" || echo "000")
echo "HTTP $code"
cat /tmp/fn_seed.json 2>/dev/null || true
echo
[[ "$code" == "200" ]] || die "함수 호출이 실패했습니다 (HTTP $code). 로그: firebase functions:log"
grep -q '"ok":true' /tmp/fn_seed.json || die "함수가 ok:true 를 돌려주지 않았습니다. 로그: firebase functions:log"

say "완료 — 앱을 완전히 종료한 뒤 다시 켜면 영수증 화면에 경매 시세가 나옵니다"
