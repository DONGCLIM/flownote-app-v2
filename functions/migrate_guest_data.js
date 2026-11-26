'use strict';

/**
 * 체험(익명) 계정 데이터를 정식 계정으로 옮긴다. (#195 ⑤-b)
 *
 * ## 왜 서버가 하나
 *
 * 구글·애플·이메일은 앱에서 `linkWithCredential` 로 **붙일 수 있다.**
 * uid 가 그대로라 옮길 것이 없다. 그런데 **카카오는 커스텀 토큰**이라
 * 붙일 수 없고 uid 가 바뀐다(`kakao:123…`). 그래서 체험으로 찍어 둔
 * 영수증이 `users/<익명 uid>` 아래 남겨진 채 안 보이게 된다.
 *
 * 앱이 직접 옮기면 **남의 데이터를 옮기라고 시킬 수 있다.** 보안 규칙은
 * "자기 uid 아래만" 이므로 남의 것을 읽지도 못한다. 그래서 Admin SDK 를
 * 쓰는 서버가 대신 한다.
 *
 * ## 안전 장치 (이 함수의 핵심)
 *
 * 🔴 **받는 계정을 입력으로 받지 않는다.** 오직 `context.auth.uid`,
 *    즉 **지금 이 요청을 보낸 사람 자신**으로만 정한다. 입력으로 받으면
 *    "내 게스트 데이터를 남의 계정으로 보내 줘" 가 가능해진다.
 *
 * 🔴 게스트 쪽은 **ID 토큰**으로 증명한다. uid 문자열이 아니다. 문자열만
 *    받으면 남의 익명 uid 를 적어 그 사람 영수증을 가져올 수 있다.
 *    토큰은 서명·만료·폐기를 Admin SDK 가 검증한다.
 *
 * 🔴 한 번 옮긴 게스트 계정은 **다시 다른 계정으로 못 옮긴다.**
 *    `migrations/{게스트 uid}` 가 자물쇠 겸 진행 기록이다.
 *
 * ## 다시 불러도 안전하다
 *
 * 복사본의 문서 id·파일 이름을 **게스트 uid 로부터 정해지는 값**으로
 * 만든다. 같은 요청을 두 번 보내도 같은 자리에 같은 내용을 쓸 뿐이라
 * 늘어나지 않는다. 중간에 끊겨도 다시 부르면 이어서 끝난다.
 *
 * ## 원본은 지우지 않는다
 *
 * 옮긴 뒤에도 `users/<게스트 uid>` 는 그대로 둔다. 지우다 끊기면 양쪽
 * 모두 잃는다. 지우는 일은 30일 정리 작업이 맡는다.
 */

const crypto = require('crypto');

/** 복사본에 붙이는 머리말. 기존 회원 데이터와 절대 겹치지 않게 한다. */
const TRIAL_PREFIX = 'trial_';

/** 진행 기록이 쌓이는 곳. 앱에서는 읽지도 쓰지도 못한다(규칙으로 막는다). */
const MIGRATIONS = 'migrations';

/** 한 번에 옮기는 최대 개수. 체험 한도가 5장이라 넉넉하다. */
const MAX_DOCS = 500;

/**
 * 게스트 uid 를 짧고 안전한 꼬리표로 바꾼다.
 *
 * uid 를 그대로 파일 이름에 쓰지 않는 이유: 카카오 uid 에는 `:` 가 들어가고,
 * 익명 uid 도 길다. 해시 12자면 겹칠 걱정이 없다.
 */
function shortOf(uid) {
  return crypto.createHash('sha256').update(uid).digest('hex').slice(0, 12);
}

/** 사용자에게 보여줄 오류. 호출부가 HttpsError 로 바꾼다. */
class MigrateError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;          // 'unauthenticated' | 'permission-denied' | ...
  }
}

/**
 * 옮기기 일꾼을 만든다.
 *
 * 테스트가 에뮬레이터용 `auth`·`db`·`bucket` 을 끼워 넣을 수 있도록
 * 밖에서 받는다. 실제 함수는 `index.js` 가 Admin SDK 를 넣어 준다.
 */
function createMigrator({ auth, db, bucket, logger }) {
  const log = logger || { info() {}, warn() {}, error() {} };

  // ── 확인 ────────────────────────────────────────────────────

  /**
   * 요청이 올바른지 본다. 하나라도 어긋나면 **아무것도 하지 않고** 거절한다.
   *
   * @returns {Promise<{guestUid: string, targetUid: string}>}
   */
  async function verify({ guestIdToken, callerUid, callerToken }) {
    // ① 호출한 사람이 로그인했는가.
    if (!callerUid || typeof callerUid !== 'string') {
      throw new MigrateError('unauthenticated', '로그인이 필요합니다.');
    }

    // ② 호출한 사람이 **익명이 아닌가.** 익명이 익명에게 옮길 이유가 없고,
    //    열어 두면 아무나 남의 체험 데이터를 긁어 모을 수 있다.
    //
    //    🔴 `.` 로 바로 꺼내지 않는다. 없는 키를 그렇게 꺼내면 터진다(#194).
    const callerProvider =
      (callerToken && callerToken.firebase && callerToken.firebase.sign_in_provider) || '';
    if (callerProvider === 'anonymous') {
      throw new MigrateError('permission-denied',
        '체험 계정으로는 옮길 수 없습니다. 먼저 가입해 주세요.');
    }

    // ③ 게스트 토큰이 왔는가.
    if (!guestIdToken || typeof guestIdToken !== 'string') {
      throw new MigrateError('invalid-argument', '체험 계정 토큰이 필요합니다.');
    }

    // ④ 토큰이 진짜인가 · 만료되지 않았는가 · 폐기되지 않았는가.
    //    두 번째 인자 `true` 가 폐기 확인이다.
    let decoded;
    try {
      decoded = await auth.verifyIdToken(guestIdToken, true);
    } catch (e) {
      log.warn('체험 토큰 검증 실패', { err: String((e && e.message) || e) });
      throw new MigrateError('permission-denied', '체험 계정 확인에 실패했습니다.');
    }

    // ⑤ 그 토큰이 **익명 계정**의 것인가. 회원 토큰을 체험 토큰인 척
    //    내밀어 남의 회원 데이터를 가져가지 못하게 막는다.
    const guestProvider =
      (decoded.firebase && decoded.firebase.sign_in_provider) || '';
    if (guestProvider !== 'anonymous') {
      throw new MigrateError('permission-denied', '체험 계정이 아닙니다.');
    }

    const guestUid = decoded.uid;
    if (!guestUid) {
      throw new MigrateError('permission-denied', '체험 계정을 확인하지 못했습니다.');
    }

    // ⑥ 자기 자신에게 옮기는 요청은 뜻이 없다. (구글·애플·이메일은 uid 가
    //    그대로라 애초에 옮길 필요가 없다 — 앱이 잘못 부른 것이다)
    if (guestUid === callerUid) {
      throw new MigrateError('invalid-argument', '같은 계정으로는 옮길 수 없습니다.');
    }

    return { guestUid, targetUid: callerUid };
  }

  // ── 사진 ────────────────────────────────────────────────────

  /**
   * `users/<게스트>/…` 아래 사진을 `users/<회원>/…` 로 복사한다.
   *
   * @returns {Promise<{count: number, urlMap: Map<string,string>}>}
   *          urlMap: 옛 저장 경로 → 새 내려받기 주소
   */
  async function copyPhotos(guestUid, targetUid) {
    const prefix = `users/${guestUid}/`;
    const short = shortOf(guestUid);
    const urlMap = new Map();
    let count = 0;

    let files = [];
    try {
      [files] = await bucket.getFiles({ prefix });
    } catch (e) {
      // 사진을 못 읽어도 영수증 글자는 옮긴다. 사진 때문에 전부 막지 않는다.
      log.warn('체험 사진 목록 읽기 실패', { err: String((e && e.message) || e) });
      return { count: 0, urlMap };
    }

    for (const f of files) {
      const rest = f.name.slice(prefix.length);
      if (!rest) continue;

      // 경로 모양은 그대로 두고 파일 이름에만 머리말을 붙인다.
      //   users/A/receipts/r_1.jpg → users/K/receipts/trial_<짧은>_r_1.jpg
      // 🔴 **게스트 uid 로부터 정해지는 이름**이라 두 번 불러도 같은 자리다.
      const cut = rest.lastIndexOf('/');
      const dir = cut < 0 ? '' : rest.slice(0, cut + 1);
      const base = cut < 0 ? rest : rest.slice(cut + 1);
      const destName = `users/${targetUid}/${dir}${TRIAL_PREFIX}${short}_${base}`;
      const dest = bucket.file(destName);

      try {
        const [exists] = await dest.exists();
        if (!exists) {
          await f.copy(dest);
        }
        // 내려받기 주소에는 토큰이 필요하다. 없으면 새로 하나 붙인다.
        const token = await ensureDownloadToken(dest);
        urlMap.set(f.name, downloadUrl(destName, token));
        count += 1;
      } catch (e) {
        log.warn('사진 복사 실패', {
          from: f.name, err: String((e && e.message) || e),
        });
      }
    }
    return { count, urlMap };
  }

  /** 내려받기 토큰을 확인하고, 없으면 만들어 붙인다. */
  async function ensureDownloadToken(file) {
    let meta = {};
    try {
      [meta] = await file.getMetadata();
    } catch (_) {/* 바로 아래에서 새로 붙인다 */}
    const existing =
      meta && meta.metadata && meta.metadata.firebaseStorageDownloadTokens;
    if (existing) return String(existing).split(',')[0];

    const token = crypto.randomUUID();
    try {
      await file.setMetadata({
        metadata: { firebaseStorageDownloadTokens: token },
      });
    } catch (e) {
      log.warn('내려받기 토큰 붙이기 실패', { err: String((e && e.message) || e) });
    }
    return token;
  }

  /** Firebase Storage 내려받기 주소를 만든다. 앱이 쓰던 모양과 같다. */
  function downloadUrl(objectName, token) {
    return (
      `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/` +
      `${encodeURIComponent(objectName)}?alt=media&token=${token}`
    );
  }

  /**
   * 영수증 안의 사진 주소를 새 경로로 바꾼다.
   *
   * 저장된 값은 (ㄱ) 내려받기 주소이거나 (ㄴ) 저장 경로다. 둘 다 본다.
   */
  function rewritePhoto(imagePath, urlMap) {
    const v = typeof imagePath === 'string' ? imagePath : '';
    if (!v) return v;
    for (const [oldName, newUrl] of urlMap) {
      // 주소 안에는 경로가 URL 인코딩되어 들어 있다.
      if (v.includes(oldName) || v.includes(encodeURIComponent(oldName))) {
        return newUrl;
      }
    }
    return v;
  }

  // ── 문서 ────────────────────────────────────────────────────

  /**
   * 하위 컬렉션 하나를 통째로 옮긴다.
   *
   * 🔴 복사본 id 는 `trial_<짧은 게스트>_<원래 id>` 다. 기존 회원 데이터와
   *    절대 겹치지 않고(덮어쓰지 않는다), 두 번 불러도 같은 자리에 쓴다.
   */
  async function copyCollection(guestUid, targetUid, name, decorate) {
    const short = shortOf(guestUid);
    const src = db.collection('users').doc(guestUid).collection(name);
    const dstCol = db.collection('users').doc(targetUid).collection(name);

    const snap = await src.limit(MAX_DOCS).get();
    if (snap.empty) return 0;

    let n = 0;
    let batch = db.batch();
    let inBatch = 0;
    for (const d of snap.docs) {
      const id = `${TRIAL_PREFIX}${short}_${d.id}`;
      batch.set(dstCol.doc(id), decorate(d.data(), d.id, id), { merge: true });
      n += 1;
      inBatch += 1;
      if (inBatch >= 400) {
        await batch.commit();
        batch = db.batch();
        inBatch = 0;
      }
    }
    if (inBatch > 0) await batch.commit();
    return n;
  }

  // ── 본 작업 ─────────────────────────────────────────────────

  /**
   * 옮긴다. 확인 → 사진 → 영수증 → 사입 리스트 → 동의 이력 → 완료 기록.
   *
   * @returns {Promise<{receipts:number, purchaseLists:number, photos:number,
   *                    alreadyDone:boolean}>}
   */
  async function run({ guestIdToken, callerUid, callerToken }) {
    const { guestUid, targetUid } =
      await verify({ guestIdToken, callerUid, callerToken });

    const markRef = db.collection(MIGRATIONS).doc(guestUid);
    const mark = await markRef.get();

    if (mark.exists) {
      const m = mark.data() || {};
      // 🔴 한 번 옮긴 체험 계정을 **다른 사람**이 또 가져갈 수 없다.
      if (m.targetUid && m.targetUid !== targetUid) {
        throw new MigrateError('permission-denied',
          '이미 다른 계정으로 옮겨진 체험 데이터입니다.');
      }
      // 같은 사람이 또 불렀다. 이미 끝났으면 **그때 결과를 그대로** 준다.
      if (m.status === 'complete') {
        return {
          receipts: m.receipts || 0,
          purchaseLists: m.purchaseLists || 0,
          photos: m.photos || 0,
          alreadyDone: true,
        };
      }
      // 끊긴 작업이다. 아래에서 이어서 끝낸다(같은 자리에 다시 쓴다).
    }

    await markRef.set({
      guestUid,
      targetUid,
      status: 'running',
      startedAt: new Date().toISOString(),
    }, { merge: true });

    // ① 사진을 먼저 옮긴다. 영수증에 새 주소를 적어야 하기 때문이다.
    const { count: photos, urlMap } = await copyPhotos(guestUid, targetUid);

    // ② 영수증. 🔴 `trialReceipt: true` 를 붙인다 — 학습 데이터로 올리지
    //    않기 위해서다. 체험에는 학습 활용 동의가 없다.
    const receipts = await copyCollection(
      guestUid, targetUid, 'receipts',
      (data, oldId, newId) => ({
        ...data,
        id: newId,
        imagePath: rewritePhoto(data.imagePath, urlMap),
        trialReceipt: true,
        migratedFrom: guestUid,
        migratedOriginalId: oldId,
      }),
    );

    // ③ 사입 리스트.
    const purchaseLists = await copyCollection(
      guestUid, targetUid, 'purchase_lists',
      (data, oldId, newId) => ({
        ...data,
        id: newId,
        trialList: true,
        migratedFrom: guestUid,
        migratedOriginalId: oldId,
      }),
    );

    // ④ 동의 이력. 어디서 온 기록인지 **출처를 남긴다.**
    await copyCollection(
      guestUid, targetUid, 'consent_log',
      (data, oldId) => ({
        ...data,
        migratedFrom: guestUid,
        migratedOriginalId: oldId,
        source: 'guest_trial',
      }),
    );

    // ⑤ 완료 기록. 🔴 원본(`users/<게스트>`)은 **지우지 않는다.**
    //    지우다 끊기면 양쪽을 모두 잃는다. 30일 정리 작업이 맡는다.
    await markRef.set({
      guestUid,
      targetUid,
      status: 'complete',
      receipts,
      purchaseLists,
      photos,
      sourceKept: true,
      completedAt: new Date().toISOString(),
    }, { merge: true });

    log.info('체험 데이터 옮기기 완료', {
      guestUid, targetUid, receipts, purchaseLists, photos,
    });

    return { receipts, purchaseLists, photos, alreadyDone: false };
  }

  return { run, verify, shortOf };
}

module.exports = {
  createMigrator,
  MigrateError,
  TRIAL_PREFIX,
  MIGRATIONS,
  shortOf,
};
