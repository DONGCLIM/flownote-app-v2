/**
 * ═══════════════════════════════════════════════════════════════════
 *  가입하지 않은 체험(게스트) 데이터 30일 뒤 삭제 — cleanupGuestData
 * ═══════════════════════════════════════════════════════════════════
 *
 * ## 왜 지우나
 *
 * 체험 동의 화면에서 **"30일 뒤 삭제"** 를 약속했다. 약속은 지켜야 한다.
 * 가입하신 분의 영수증은 `migrateGuestData` 가 회원 계정으로 옮겨 **영구
 * 보관**하므로, 여기서 지우는 것은 **끝내 가입하지 않은 체험 계정**뿐이다.
 *
 * ## 🔴🔴 이 파일에서 제일 위험한 것 — 카카오 회원을 게스트로 오인하는 일
 *
 * Admin SDK 의 `UserRecord` 에는 **`isAnonymous` 칸이 없다.** 그래서
 * "제공업체가 하나도 없으면 익명" 으로 판단하기 쉬운데, **그러면 카카오
 * 회원이 통째로 지워진다.** 에뮬레이터로 직접 재 본 결과다.
 *
 * ```
 *  익명(게스트)                 providerData: []   email: null  claims: null
 *  이메일 가입                  providerData: ['password']
 *  구글                         providerData: ['google.com']
 *  애플                         providerData: ['apple.com']
 *  카카오(클레임 성공)          providerData: []   email: null  claims: {provider:'kakao'}
 *  🔴 카카오(클레임 실패·메일없음) providerData: []   email: null  claims: null   ← 익명과 똑같다
 * ```
 *
 * 마지막 줄이 핵심이다. 카카오는 **커스텀 토큰**이라 제공업체가 안 붙고,
 * 이메일 동의를 안 한 분은 메일도 없다. 게다가 클레임 저장은
 * `kakaoCustomToken` 안에서 `try/catch` 로 감싸여 있어 **실패해도 로그인이
 * 된다**(그게 맞는 설계다). 그러면 익명 계정과 **구별되는 칸이 하나도
 * 남지 않는다.**
 *
 * 그래서 카카오를 가려내는 믿을 수 있는 단서는 **uid 접두사 하나뿐**이다.
 * `kakaoCustomToken` 이 `kakao:<회원번호>` 로 **서버가 직접** 만들기
 * 때문에 예외가 없다(`const kakaoUid = (id) => \`kakao:${id}\``).
 *
 * ## 그래서 판정을 "지울 수 있다" 쪽으로만 좁힌다
 *
 * 🔴 **거르는 목록(denylist)이 아니라 허용 목록(allowlist)이다.** "이런
 *    사람은 빼자" 가 아니라 **"이 조건을 전부 만족해야만 지운다"** 로 짰다.
 *    거르는 목록은 새 가입 방법이 생기면 조용히 뚫린다. 허용 목록은
 *    모르는 것이 생기면 **안 지우는 쪽**으로 틀린다 — 그게 안전한 방향이다.
 *
 * 🔴 판정이 조금이라도 흔들리면 **보존한다.** 체험 데이터를 하루 더 두는
 *    것과 회원 장부를 지우는 것은 비교할 수 있는 일이 아니다.
 */

'use strict';

/** 며칠 지난 체험 계정을 지우나. `GuestService.keepDays` 와 같은 값. */
const KEEP_DAYS = 30;

/** 체험 데이터를 옮긴 기록. 여기 있으면 **가입하신 분**이다. */
const MIGRATIONS = 'migrations';

/**
 * 커스텀 토큰 로그인이 쓰는 uid 접두사.
 *
 * 🔴 **이 목록이 이 파일의 생명줄이다.** 커스텀 토큰 로그인은 제공업체가
 *    안 붙어서 익명과 구별되지 않는다. 새 SNS 를 커스텀 토큰으로 붙이면
 *    **반드시 여기에 접두사를 더해야 한다.** 안 그러면 그 회원이 30일 뒤
 *    조용히 지워진다.
 *
 *    `functions/index.js` 의 `kakaoUid()` 와 짝이다.
 */
const CUSTOM_TOKEN_UID_PREFIXES = ['kakao:'];

/** 한 번에 너무 많이 지우지 않는다. 사고가 나도 범위가 좁게. */
const MAX_DELETIONS_PER_RUN = 200;

/** `listUsers` 한 쪽 크기. */
const PAGE_SIZE = 1000;

/** 건너뛴 이유 — 로그에 그대로 찍힌다. */
const SKIP = {
  HAS_PROVIDER: 'has_provider',        // 구글·애플·이메일이 붙어 있다
  CUSTOM_TOKEN_UID: 'custom_token_uid',// 카카오 등 커스텀 토큰 회원
  HAS_CLAIMS: 'has_claims',            // 계정에 출처가 적혀 있다
  HAS_IDENTITY: 'has_identity',        // 메일·전화·이름·사진이 있다
  TOO_YOUNG: 'too_young',              // 아직 30일이 안 됐다
  MIGRATED: 'migrated',                // 회원으로 옮겨진 적이 있다
  MEMBER_DOC: 'member_doc',            // 회원 문서가 있다
  NO_CREATED_AT: 'no_created_at',      // 만든 날을 못 읽었다
};

/**
 * 이 계정이 **지워도 되는 체험 계정**인가.
 *
 * 돌려주는 값: `{ ok: true }` 또는 `{ ok: false, reason }`.
 *
 * 🔴 순수 함수로 뺐다. Firestore 없이 테스트할 수 있어야 한다.
 */
function classifyUser(user, now, keepDays = KEEP_DAYS) {
  // ① 다른 로그인 방법이 하나라도 붙어 있으면 **회원**이다.
  //    구글·애플·이메일이 여기서 걸린다. 게스트가 가입 전환(link)을 하면
  //    uid 가 그대로인 채 제공업체만 붙으므로, 그분도 여기서 걸러진다.
  if (user.providerData && user.providerData.length > 0) {
    return { ok: false, reason: SKIP.HAS_PROVIDER };
  }

  // ② 🔴 커스텀 토큰 회원(카카오). 제공업체가 안 붙어서 ①에서 못 걸린다.
  //    uid 접두사가 **유일한** 단서다. 위 머리말 참고.
  const uid = user.uid || '';
  if (CUSTOM_TOKEN_UID_PREFIXES.some((p) => uid.startsWith(p))) {
    return { ok: false, reason: SKIP.CUSTOM_TOKEN_UID };
  }

  // ③ 계정에 출처가 적혀 있으면 누군가 일부러 심은 것이다. 게스트가 아니다.
  const claims = user.customClaims || {};
  if (Object.keys(claims).length > 0) {
    return { ok: false, reason: SKIP.HAS_CLAIMS };
  }

  // ④ 익명 계정에는 메일·전화·이름·사진이 없다. 하나라도 있으면 보존한다.
  if (user.email || user.phoneNumber || user.displayName || user.photoURL) {
    return { ok: false, reason: SKIP.HAS_IDENTITY };
  }

  // ⑤ 만든 날을 못 읽으면 **지우지 않는다.** 모르면 보존이다.
  const created = Date.parse(
    (user.metadata && user.metadata.creationTime) || '',
  );
  if (!Number.isFinite(created)) {
    return { ok: false, reason: SKIP.NO_CREATED_AT };
  }

  const ageDays = (now - created) / 86400000;
  if (ageDays < keepDays) {
    return { ok: false, reason: SKIP.TOO_YOUNG };
  }

  return { ok: true, ageDays };
}

function createCleaner({ auth, db, bucket, logger }) {
  const log = logger || console;

  /** 이 체험 계정이 회원으로 옮겨진 적이 있는가. */
  async function wasMigrated(uid) {
    const snap = await db.collection(MIGRATIONS).doc(uid).get();
    return snap.exists;
  }

  /**
   * `users/{uid}` 문서가 **회원**의 것으로 보이는가.
   *
   * 🔴 마지막 안전망이다. Auth 쪽 판정이 어떤 이유로 틀렸더라도, 회원
   *    문서가 있으면 지우지 않는다. 게스트는 가입 절차를 지나지 않아서
   *    `provider`·`businessName` 같은 칸이 생기지 않는다.
   */
  async function looksLikeMember(uid) {
    const snap = await db.doc(`users/${uid}`).get();
    if (!snap.exists) return false;
    const d = snap.data() || {};
    const provider = String(d.provider || '').toLowerCase();
    // 가입하며 적히는 칸들. 하나라도 차 있으면 회원으로 본다.
    if (provider && provider !== 'anonymous' && provider !== 'guest') return true;
    if (d.email || d.businessName || d.businessNumber || d.name) return true;
    return false;
  }

  /** Firestore `users/{uid}` 아래를 통째로 지운다(하위 컬렉션 포함). */
  async function deleteFirestore(uid) {
    const ref = db.doc(`users/${uid}`);
    if (typeof db.recursiveDelete === 'function') {
      await db.recursiveDelete(ref);
      return;
    }
    // 아주 오래된 SDK 대비 — 하위 컬렉션을 손으로 훑는다.
    const cols = await ref.listCollections();
    for (const c of cols) {
      const docs = await c.listDocuments();
      await Promise.all(docs.map((d) => d.delete()));
    }
    await ref.delete();
  }

  /** Storage `users/{uid}/` 아래를 지운다. */
  async function deletePhotos(uid) {
    // 🔴 접두사 끝의 `/` 를 반드시 붙인다. 없으면 `users/abc` 가
    //    `users/abcdef/...` 까지 긁어 **남의 사진**을 지운다.
    const prefix = `users/${uid}/`;
    await bucket.deleteFiles({ prefix, force: true });
  }

  /**
   * 하루 한 번 돈다.
   *
   * @param {object} [opts]
   * @param {number} [opts.now]      기준 시각(ms). 테스트에서 넣는다.
   * @param {boolean} [opts.dryRun]  true 면 **지우지 않고** 세기만 한다.
   */
  async function run(opts = {}) {
    const now = opts.now || Date.now();
    const dryRun = opts.dryRun === true;
    const keepDays = opts.keepDays || KEEP_DAYS;

    let scanned = 0;
    let deleted = 0;
    const deletedUids = [];
    const skipped = {};
    const failures = [];

    const note = (reason) => { skipped[reason] = (skipped[reason] || 0) + 1; };

    let pageToken;
    do {
      const page = await auth.listUsers(PAGE_SIZE, pageToken);
      pageToken = page.pageToken;

      for (const user of page.users) {
        scanned += 1;

        // ── Auth 정보만으로 거를 수 있는 것부터 (읽기 비용 0) ──
        const verdict = classifyUser(user, now, keepDays);
        if (!verdict.ok) { note(verdict.reason); continue; }

        const uid = user.uid;

        // ── 여기부터는 Firestore 를 읽어 두 번 더 확인한다 ──
        try {
          if (await wasMigrated(uid)) { note(SKIP.MIGRATED); continue; }
          if (await looksLikeMember(uid)) { note(SKIP.MEMBER_DOC); continue; }
        } catch (e) {
          // 🔴 확인에 실패하면 **지우지 않는다.** 모르면 보존이다.
          note(SKIP.MEMBER_DOC);
          log.warn('[cleanupGuestData] 확인 실패 — 보존', {
            uid, err: String(e && e.message),
          });
          continue;
        }

        if (deleted >= MAX_DELETIONS_PER_RUN) break;
        if (dryRun) { deleted += 1; deletedUids.push(uid); continue; }

        // ── 삭제 ──────────────────────────────────────────────
        // 🔴 Auth 계정을 **맨 마지막에** 지운다. 중간에 끊기면 계정이
        //    남아 다음 날 다시 걸린다. 먼저 지우면 데이터만 남아 영영
        //    주인 없는 쓰레기가 된다.
        try {
          await deleteFirestore(uid);
          await deletePhotos(uid);
          await auth.deleteUser(uid);
          deleted += 1;
          deletedUids.push(uid);
        } catch (e) {
          failures.push({ uid, err: String(e && e.message) });
          log.error('[cleanupGuestData] 삭제 실패', {
            uid, err: String(e && e.message),
          });
        }
      }
    } while (pageToken && deleted < MAX_DELETIONS_PER_RUN);

    const summary = {
      scanned,
      deleted,
      skipped,
      skippedTotal: Object.values(skipped).reduce((a, b) => a + b, 0),
      failed: failures.length,
      keepDays,
      dryRun,
    };
    log.info('[cleanupGuestData] 완료', summary);
    return { ...summary, deletedUids, failures };
  }

  return { run, classifyUser, wasMigrated, looksLikeMember };
}

module.exports = {
  createCleaner,
  classifyUser,
  KEEP_DAYS,
  SKIP,
  CUSTOM_TOKEN_UID_PREFIXES,
  MAX_DELETIONS_PER_RUN,
};
