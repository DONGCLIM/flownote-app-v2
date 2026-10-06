/**
 * ═══════════════════════════════════════════════════════════════════════
 *  FlowNote 서버 작업 — 양재 화훼공판장 경매 시세 일일 요약
 * ═══════════════════════════════════════════════════════════════════════
 *
 * ## 왜 서버가 필요한가
 * `지난주보다 41% 올랐어요` 는 **최근 6번의 경매 결과**가 있어야 계산된다.
 * 오늘 시세는 오늘 경매가 끝나야 나오므로 앱에 미리 넣어둘 수 없다.
 * 그래서 누군가는 API 를 불러야 한다. 문제는 `누가 몇 번` 부르냐다.
 *
 *   ❌ 앱이 영수증 열 때마다 → 1회 185KB, 1.7~2.5초. 100장 찍으면 18MB.
 *   ✅ 서버가 하루 한 번    → 앱은 요약 3.4KB 만 받는다 (원본의 1.9%).
 *
 * ## 측정으로 확정한 사실 (2년치 337,383행 실측)
 *
 * 1. **경매는 월·수·금만 열린다.** 화/목/토는 행이 20개 남짓(정산 잔여).
 *    그래서 `어제 대비` 가 아니라 `최근 3경매일 vs 이전 3경매일` 로 본다.
 *    3경매일 ≈ 1주라서 사장님께는 `지난주보다` 라고 말할 수 있다.
 *
 * 2. **요약이 묵으면 판정이 빨리 틀린다.**
 *      1경매일(2일) 묵음 → 오름/내림 판정 불일치 29%
 *      2경매일(4일) 묵음 → 46%
 *      3경매일(7일) 묵음 → 56%
 *    → 하루 1번 갱신이 **필수**다. 주 3회로 줄이면 절반이 거짓이 된다.
 *
 * 3. **단기 추세에 예측력은 없다.** 오름 판정 후 다음 기간에도 같은 방향일
 *    확률이 51~53% = 동전 던지기였다(문턱 5~25% 전부 동일).
 *    → 그래서 앱 문구는 `올랐어요`(사실)만 쓰고 `오를 것 같아요`(예측)는
 *      절대 쓰지 않는다. 이 파일이 내보내는 값도 과거 사실뿐이다.
 *
 * 3-1. **잡음 구간은 앱에서 뭉갠다.** 여기서는 계산한 %를 그대로 실어 보내고,
 *    표시 단계(`FlowerPriceQuote.changeBand` = 5)에서 ±5% 안이면
 *    `지난주와 비슷해요` 로 바꾼다. 품목별 주간 변동 중간값이 9.5~19.6% 라
 *    1~2% 는 제자리인데 "올랐다"고 말하면 없는 신호를 보여주는 셈이다.
 *    문턱을 서버에 두지 않은 이유: 원본 %를 보존해두면 나중에 문턱을 바꿀 때
 *    앱만 고치면 되고 데이터를 다시 모을 필요가 없다.
 *
 * 4. **등급 구성비 오염은 무시 가능**했다. 등급 고정 가중 지수와 비교해
 *    방향 불일치 1~11%, 평균 차이 0.7~5.1%p. → 단순 가중평균으로 충분하다.
 *
 * 5. **이 API 는 양재 단독이다.** 응답에 시장 구분 필드가 없어서 직접 대조했다.
 *    `flower.at.or.kr` 메인의 "양재 거래동향" 집계와 3일 모두 물량이 정확히
 *    일치했다 (08-21: 96,033단, 08-20: 1,056단, 08-22: 1,097단, 오차 0).
 *    → 그래서 앱에 `양재 경매가` 라고 표기해도 사실이다.
 *
 * 6. **단위는 `단`.** 사이트가 스스로 `단(속)` 으로 표기한다. 즉 1속 = 1단이고
 *    `속` 은 경매장 표기, `단` 은 일반 표기다. 앱은 `단` 만 쓴다.
 *
 * ## 배포
 *   cd functions && npm install
 *   firebase deploy --only functions
 *
 * ## 필요한 설정 (서비스키를 코드에 박지 않는다)
 *   firebase functions:secrets:set FLOWER_API_KEY
 */

'use strict';

const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onRequest } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const logger = require('firebase-functions/logger');
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();

/** 화훼유통정보 서비스키. 소스에 박지 않고 Secret Manager 에서 읽는다. */
const FLOWER_API_KEY = defineSecret('FLOWER_API_KEY');

// 🔴 카카오 로그인 통행증(커스텀 토큰) 서명용 자격증명.
//
//    커스텀 토큰은 "서비스 계정이 자기 개인키로 서명한 문서"다. 함수는
//    기본적으로 개인키를 들고 있지 않고, 대신 구글에 "나 대신 서명해줘"
//    (iam.serviceAccounts.signBlob) 라고 부탁한다. 그 부탁 권한이 없으면
//    signBlob denied 로 실패한다 — 실제로 그 오류가 났다.
//
//    IAM 권한을 주는 방법도 있지만 프로젝트 소유자만 할 수 있다. 대신
//    **개인키를 직접 들려주면** 부탁할 일이 없어져 권한이 아예 불필요하다.
//    그 키는 코드가 아니라 Secret Manager 에 둔다.
const KAKAO_SIGNER_SA = defineSecret('KAKAO_SIGNER_SA');

// ─────────────────────────────────────────────────────────────────────
//  상수
// ─────────────────────────────────────────────────────────────────────

const API_BASE = 'https://flower.at.or.kr/api/returnData.api';

/** 이 API 는 브라우저 UA 가 없으면 응답을 안 준다. */
const UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/**
 * 경매일 판정 기준 행 수.
 *
 * 실측: 월/수/금 평균 1,046~1,074행, 화/목/토 평균 20~22행.
 * 200 은 그 사이 어디에 그어도 되는 안전한 값이다 (월수금 96~100%가 200 초과,
 * 화목토는 0%).
 */
const AUCTION_DAY_MIN_ROWS = 200;

/** 추세 비교 창. 3경매일 ≈ 1주 (월·수·금). */
const WINDOW = 3;

/**
 * 며칠(경매일) 이상 묵으면 아예 안 보여줄지.
 *
 * 실측 판정 불일치율이 1경매일 29% → 2경매일 46% 로 급등한다.
 * 3경매일(약 1주) 넘게 갱신이 끊겼으면 낡은 값을 보여주는 대신 침묵한다.
 */
const MAX_STALE_AUCTION_DAYS = 3;

/**
 * 과거를 며칠까지 훑을지. 최근 6경매일을 확보하려면 넉넉해야 한다.
 * 월수금만 열리므로 6경매일 ≈ 14일. 결측(31% 날짜에 특정 품목 없음)을
 * 감안해 30일을 본다.
 */
const LOOKBACK_DAYS = 30;

/** 요약 문서 위치. 전체 사용자 공용이라 사용자별로 두지 않는다. */
const SUMMARY_DOC = 'market/yangjae_latest';

// ─────────────────────────────────────────────────────────────────────
//  API 호출
// ─────────────────────────────────────────────────────────────────────

/** `YYYY-MM-DD` */
function ymd(d) {
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getUTCFullYear()}-${p(d.getUTCMonth() + 1)}-${p(d.getUTCDate())}`;
}

/** 한국 시간 기준 오늘. 경매는 한국에서 열리니 KST 로 봐야 한다. */
function todayKst() {
  const now = new Date();
  return new Date(now.getTime() + 9 * 60 * 60 * 1000);
}

/**
 * 하루치 경매 결과를 받아온다.
 *
 * `flowerGubn=1` = 절화만. 사장님 방침대로 난/관엽은 제외한다.
 * 실패하면 `null` 을 주고 호출자가 그 날을 건너뛴다 — 한 날 실패로
 * 전체 요약이 깨지면 안 된다.
 */
async function fetchDay(dateStr, apiKey) {
  const url =
    `${API_BASE}?kind=f001&serviceKey=${encodeURIComponent(apiKey)}` +
    `&baseDate=${dateStr}&flowerGubn=1&dataType=json&countPerPage=9999`;

  try {
    const res = await fetch(url, {
      headers: { 'User-Agent': UA },
      signal: AbortSignal.timeout(30000),
    });
    if (!res.ok) {
      logger.warn(`fetchDay ${dateStr} HTTP ${res.status}`);
      return null;
    }
    const body = await res.json();
    const r = body && body.response;
    if (!r || r.resultCd !== '0') {
      logger.warn(`fetchDay ${dateStr} resultCd=${r && r.resultCd}`);
      return null;
    }
    return Array.isArray(r.items) ? r.items : [];
  } catch (e) {
    logger.warn(`fetchDay ${dateStr} 실패: ${e && e.message}`);
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────
//  집계
// ─────────────────────────────────────────────────────────────────────

/**
 * 품목별 가중평균을 낸다. `Σ금액 / Σ물량`.
 *
 * ⚠️ 응답의 `avgAmt` 를 단순평균하면 안 된다. 물량 12속짜리 특1 행이
 * 836속짜리 상3 행과 같은 무게를 갖게 되어 평균이 부풀려진다.
 * (실측: 장미 하루 min 2,490 / 가중평균 11,827 / max 50,000 = 20배 차이)
 *
 * @returns {Map<string, {amt:number, qty:number}>} 품목명 → 합계
 */
function aggregateByItem(items) {
  const m = new Map();
  for (const it of items) {
    const qty = parseInt(it.totQty, 10);
    const amt = parseInt(it.totAmt, 10);
    if (!Number.isFinite(qty) || !Number.isFinite(amt) || qty <= 0) continue;
    const key = (it.pumName || '').trim();
    if (!key) continue;
    const cur = m.get(key) || { amt: 0, qty: 0 };
    cur.amt += amt;
    cur.qty += qty;
    m.set(key, cur);
  }
  return m;
}

const mean = (a) => a.reduce((x, y) => x + y, 0) / a.length;

/**
 * 최근 경매일들의 품목별 시세로 요약 문서를 만든다.
 *
 * @param {Array<{date:string, byItem:Map}>} days 최신순(내림차순) 경매일
 */
function buildSummary(days) {
  /** 품목 → [{date, price}] (최신순) */
  const series = new Map();
  for (const d of days) {
    for (const [name, v] of d.byItem) {
      if (!series.has(name)) series.set(name, []);
      series.get(name).push({ date: d.date, price: v.amt / v.qty });
    }
  }

  const items = {};
  for (const [name, s] of series) {
    const latest = s[0];

    // 주간 변화: 최근 3경매일 평균 vs 그 이전 3경매일 평균.
    // 6개가 다 안 모이면 `null` — 없는 정보를 지어내지 않는다.
    // (실측: 247품목 중 최근 6경매일 전부 출하된 건 81품목 = 33%.
    //  철 지난 꽃은 말할 게 없는 게 정상이다.)
    let chg = null;
    if (s.length >= WINDOW * 2) {
      const cur = mean(s.slice(0, WINDOW).map((x) => x.price));
      const prev = mean(s.slice(WINDOW, WINDOW * 2).map((x) => x.price));
      if (prev > 0) chg = Math.round(((cur - prev) / prev) * 100);
    }

    items[name] = {
      d: latest.date,               // 그 시세가 찍힌 경매일
      p: Math.round(latest.price),  // 원/단 (1속 = 1단)
      c: chg,                       // 지난주 대비 % (없으면 null)
    };
  }

  return {
    v: 1,
    market: '양재',                 // 대조 확인됨: 사이트 "양재 거래동향" 과 물량 일치
    unit: '단',
    base: days[0].date,             // 이 요약의 최신 경매일
    window: WINDOW,
    maxStale: MAX_STALE_AUCTION_DAYS,
    itemCount: Object.keys(items).length,
    items,
  };
}

// ─────────────────────────────────────────────────────────────────────
//  본 작업
// ─────────────────────────────────────────────────────────────────────

/**
 * 과거 30일을 훑어 경매일 6일을 확보하고 요약을 Firestore 에 쓴다.
 *
 * 호출 횟수: 6경매일을 채울 때까지 하루 1건씩. 월수금만 열리므로
 * 보통 14~16회 호출이면 끝난다 (화목토는 행이 적어 즉시 걸러진다).
 */
async function runSummary(apiKey) {
  const start = todayKst();
  const days = [];

  for (let i = 0; i < LOOKBACK_DAYS && days.length < WINDOW * 2; i++) {
    const d = new Date(start.getTime() - i * 86400000);
    const dateStr = ymd(d);
    const items = await fetchDay(dateStr, apiKey);
    if (items === null) continue;

    // 경매가 안 열린 날(화/목/토)은 행이 20개 남짓이다. 건너뛴다.
    if (items.length < AUCTION_DAY_MIN_ROWS) continue;

    days.push({ date: dateStr, byItem: aggregateByItem(items) });
  }

  if (days.length === 0) {
    throw new Error('경매일을 하나도 못 받았습니다. API 상태를 확인하세요.');
  }

  const summary = buildSummary(days);
  const bytes = Buffer.byteLength(JSON.stringify(summary), 'utf8');

  await db.doc(SUMMARY_DOC).set({
    ...summary,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  logger.info(
    `요약 저장 완료: 경매일 ${days.length}일(${days.map((d) => d.date).join(',')}), ` +
      `품목 ${summary.itemCount}개, ${bytes.toLocaleString()} bytes`,
  );
  return { ...summary, bytes, auctionDays: days.length };
}

// ─────────────────────────────────────────────────────────────────────
//  트리거
// ─────────────────────────────────────────────────────────────────────

/**
 * 매일 1회 갱신. 사장님이 확정한 "시세 갱신은 하루 한번" 방침.
 *
 * 시각을 17:30 KST 로 잡은 이유: 양재 경매는 새벽~오전에 끝나고 정산 데이터가
 * 낮에 올라온다. 오후 늦게 받으면 당일치가 확실히 들어있다.
 */
exports.updateFlowerPrices = onSchedule(
  {
    schedule: '30 17 * * *',
    timeZone: 'Asia/Seoul',
    region: 'asia-northeast3',
    secrets: [FLOWER_API_KEY],
    timeoutSeconds: 540,
    memory: '512MiB',
    retryCount: 3,
  },
  async () => {
    await runSummary(FLOWER_API_KEY.value());
  },
);

/**
 * 수동 실행용. 배포 직후 데이터를 한 번 채우거나 문제를 확인할 때 쓴다.
 * 운영에서 앱이 호출하는 엔드포인트가 아니다 — 앱은 Firestore 를 직접 읽는다.
 */
exports.updateFlowerPricesNow = onRequest(
  {
    region: 'asia-northeast3',
    secrets: [FLOWER_API_KEY],
    timeoutSeconds: 540,
    memory: '512MiB',
  },
  async (req, res) => {
    try {
      const out = await runSummary(FLOWER_API_KEY.value());
      res.json({
        ok: true,
        base: out.base,
        auctionDays: out.auctionDays,
        itemCount: out.itemCount,
        bytes: out.bytes,
      });
    } catch (e) {
      logger.error(e);
      res.status(500).json({ ok: false, error: String((e && e.message) || e) });
    }
  },
);

// ═══════════════════════════════════════════════════════════════════════
//  카카오 로그인 — Firebase 커스텀 토큰 발급
// ═══════════════════════════════════════════════════════════════════════
//
// ## 왜 서버가 필요한가
//
// Firebase Auth 는 구글·애플·페이스북 등은 기본 지원하지만 **카카오는 모른다.**
// 그래서 중간에서 신원을 보증해 주는 다리가 필요하다.
//
//   앱: 카카오 로그인 → 액세스 토큰 받음
//    ↓  토큰을 이 함수로 보냄
//   여기: 카카오에 "이 토큰 진짜냐?" 직접 물어봄  ← 이게 핵심
//    ↓  진짜면 Firebase 커스텀 토큰 발급
//   앱: signInWithCustomToken() → 로그인 완료
//
// ## 🔴 왜 앱에서 검증하면 안 되는가
//
// 앱은 사용자 손에 있어서 뜯어고칠 수 있다. 앱이 "나 카카오 12345번이야"
// 라고 주장하는 걸 그대로 믿으면, 남의 회원번호를 적어 보내는 것만으로
// 그 사람 계정에 들어갈 수 있다. 영수증·매출이 전부 남에게 열린다.
// 그래서 **토큰을 받아 카카오 서버에 직접 확인**하는 절차를 서버에 둔다.
// 액세스 토큰은 카카오가 발급한 것이라 위조할 수 없다.

const KAKAO_ME = 'https://kapi.kakao.com/v2/user/me';

/// 커스텀 토큰 서명 전용 admin 앱.
///
/// 기본 앱은 개인키가 없어 서명을 남에게 부탁한다. 이 앱은 개인키를
/// 직접 들고 있어 스스로 서명한다. 사용자 조회/생성 등 나머지 작업은
/// 기본 앱을 계속 쓴다(권한이 이미 있으므로 바꿀 이유가 없다).
let _signerApp = null;
function signerAuth() {
  if (_signerApp) return _signerApp.auth();
  let raw = '';
  try {
    raw = KAKAO_SIGNER_SA.value();
  } catch (_) {
    raw = '';
  }
  if (!raw) {
    // 시크릿이 없으면 기본 앱으로 시도한다(권한이 있는 환경이면 동작).
    return admin.auth();
  }
  const sa = JSON.parse(raw);
  _signerApp = admin.initializeApp(
    {
      credential: admin.credential.cert({
        projectId: process.env.GCLOUD_PROJECT || 'flownote-404ef',
        clientEmail: sa.client_email,
        privateKey: sa.private_key,
      }),
    },
    'kakaoSigner',
  );
  return _signerApp.auth();
}

/// 카카오 회원번호 → Firebase uid
///
/// 🔴 접두사를 붙이는 이유
///    카카오 회원번호는 그냥 숫자(예: 3812345678)다. 접두사 없이 쓰면
///    다른 로그인 수단의 uid 와 우연히 겹칠 수 있다. 겹치면 남의 계정에
///    들어가진다. `kakao:` 를 붙여 출처를 uid 안에 못박는다.
const kakaoUid = (id) => `kakao:${id}`;

exports.kakaoCustomToken = onRequest(
  {
    region: 'asia-northeast3',
    timeoutSeconds: 30,
    memory: '256MiB',
    cors: true,
    secrets: [KAKAO_SIGNER_SA],
  },
  async (req, res) => {
    try {
      if (req.method !== 'POST') {
        return res.status(405).json({ ok: false, error: 'POST 만 허용됩니다.' });
      }

      const accessToken = (req.body && req.body.accessToken) || '';
      if (!accessToken || typeof accessToken !== 'string') {
        return res.status(400).json({ ok: false, error: 'accessToken 이 필요합니다.' });
      }

      // ── 1) 카카오에 토큰 검증 요청 ──────────────────────────────
      // 토큰이 위조·만료면 카카오가 401 을 준다. 우리가 판단하지 않는다.
      const kr = await fetch(KAKAO_ME, {
        method: 'GET',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-type': 'application/x-www-form-urlencoded;charset=utf-8',
        },
      });

      if (!kr.ok) {
        const body = await kr.text().catch(() => '');
        logger.warn('카카오 토큰 검증 실패', { status: kr.status, body: body.slice(0, 200) });
        // 401 = 토큰이 틀렸거나 만료. 앱에 그대로 알려 재로그인을 유도한다.
        return res
          .status(kr.status === 401 ? 401 : 502)
          .json({ ok: false, error: '카카오 인증 확인에 실패했습니다.' });
      }

      const me = await kr.json();
      const kakaoId = me && me.id;
      if (!kakaoId) {
        return res.status(502).json({ ok: false, error: '카카오 회원번호를 받지 못했습니다.' });
      }

      // ── 2) 프로필 추출 ─────────────────────────────────────────
      // 동의 안 한 항목은 응답에 아예 없다. 없어도 로그인은 되게 한다.
      const acc = me.kakao_account || {};
      const prof = acc.profile || {};
      // 이메일은 `동의 + 인증완료` 둘 다여야 신뢰할 수 있다.
      const email =
        acc.email && acc.is_email_verified === true && acc.is_email_valid === true
          ? acc.email
          : null;
      const nickname = prof.nickname || null;
      const photo = prof.profile_image_url || prof.thumbnail_image_url || null;

      const uid = kakaoUid(kakaoId);

      // ── 3) Firebase 사용자 생성/갱신 ────────────────────────────
      // 🔴 이메일을 Auth 레코드에 넣지 않는다.
      //    같은 이메일을 쓰는 구글 계정이 이미 있으면 createUser 가
      //    `email-already-exists` 로 실패해서 **카카오 로그인 자체가 막힌다.**
      //    이메일은 아래 클레임으로만 넘기고, 계정 통합은 앱에서 판단한다.
      const patch = {};
      if (nickname) patch.displayName = nickname;
      if (photo) patch.photoURL = photo;

      try {
        await admin.auth().updateUser(uid, patch);
      } catch (e) {
        if (e && e.code === 'auth/user-not-found') {
          await admin.auth().createUser({ uid, ...patch });
        } else {
          throw e;
        }
      }

      // ── 3.5) 계정에 출처를 영구 기록 ───────────────────────────
      // 🔴 커스텀 토큰에 담는 클레임은 **그 토큰에만** 붙는다. 계정 자체에는
      //    남지 않아서, Firebase 콘솔이나 관리자 조회에서는 여전히 아무
      //    정보도 안 보인다(제공업체 칸이 빈 채로 남는다).
      //    계정에 붙여두려면 setCustomUserClaims 를 따로 호출해야 한다.
      //    이러면 콘솔 조회·관리자 도구·Firestore 규칙에서 모두 보인다.
      try {
        await admin.auth().setCustomUserClaims(uid, {
          provider: 'kakao',
          kakaoId: String(kakaoId),
          ...(email ? { kakaoEmail: email } : {}),
        });
      } catch (e) {
        // 클레임은 부가 정보다. 실패해도 로그인은 되게 한다.
        logger.warn('카카오 클레임 저장 실패', { uid, err: String(e && e.message) });
      }

      // ── 4) 커스텀 토큰 발급 ────────────────────────────────────
      // 위에서 계정에 심은 것과 같은 값을 토큰에도 담는다. 토큰 쪽은 앱이
      // 즉시 읽을 수 있어서(재로그인 없이) 편하다.
      const token = await signerAuth().createCustomToken(uid, {
        provider: 'kakao',
        kakaoId: String(kakaoId),
        ...(email ? { kakaoEmail: email } : {}),
      });

      logger.info('카카오 로그인 성공', { uid, hasEmail: !!email });
      return res.json({
        ok: true,
        token,
        uid,
        email,
        displayName: nickname,
        photoURL: photo,
      });
    } catch (e) {
      logger.error('kakaoCustomToken 실패', e);
      return res
        .status(500)
        .json({ ok: false, error: String((e && e.message) || e) });
    }
  },
);
