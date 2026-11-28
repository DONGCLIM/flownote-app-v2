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
 * ## 받는 계정에 영수증이 이미 있으면 옮기지 않는다 (#195 ⑤-c)
 *
 * 체험 데이터를 **기존 회원 것과 섞는 일**은 사람이 봐야 한다. 같은 영수증을
 * 체험에서도 찍고 가입 뒤에도 찍었을 수 있고, 그걸 서버가 말없이 합치면
 * 매입 합계가 부풀거나 같은 영수증이 두 건이 된다. 되돌리기도 어렵다.
 * 그래서 **새 회원(영수증 0건)일 때만** 옮기고, 이미 쓰던 분께는
 * 아무것도 하지 않고 "기존 회원이라 옮기지 않음" 을 돌려준다.
 * 합치기는 나중에 대조 화면에서 사장님이 직접 고르시게 만든다.
 *
 * ## 중복 검사 지문도 같이 간다
 *
 * 앱의 중복 검사(`receipt_duplicate_service.dart`)는 지문을 따로 저장하지
 * 않는다. **매입처 · 날짜 · 총액 · 품목** 네 칸에서 그때그때 계산한다.
 * 그래서 이 네 칸을 그대로 옮기면 지문도 함께 옮겨진 셈이고, 가입 뒤에
 * 같은 영수증을 다시 찍으면 **기존 중복 검사에 그대로 걸린다.**
 * 🔴 아래 영수증 복사에서 네 칸을 **일부러 하나씩 적어 둔** 이유다.
 *    나중에 누가 칸을 추려내도 이 네 개는 빠지지 않는다.
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
 * 중복 검사 지문을 이루는 칸. (`receipt_duplicate_service.dart` 의 `ReceiptKey`)
 *
 * 🔴 앱은 지문을 저장하지 않고 이 네 칸에서 계산한다. 하나라도 빠지면
 *    가입 뒤 같은 영수증을 다시 찍어도 중복으로 안 잡힌다.
 */
const FINGERPRINT_FIELDS = ['storeName', 'date', 'totalAmount', 'items'];

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

  /**
   * 중복 검사 지문 네 칸을 **있는 것만** 골라 담는다.
   *
   * 🔴 `date: data.date` 처럼 통째로 적으면 그 칸이 없는 문서에서
   *    `undefined` 가 되고, Firestore 는 그런 값을 받지 않아 **옮기기
   *    자체가 실패**한다. 한 칸이 비었다고 영수증을 통째로 잃을 수는 없다.
   *    있는 것만 적고 없는 칸은 건드리지 않는다.
   */
  function fingerprintOf(data) {
    const out = {};
    for (const f of FINGERPRINT_FIELDS) {
      if (data[f] !== undefined) out[f] = data[f];
    }
    return out;
  }

  /**
   * 받는 계정에 영수증이 **한 장이라도** 있는가.
   *
   * 전부 세지 않는다. 한 장만 찾으면 "기존 회원" 으로 판정하기에 충분하고,
   * 수천 장을 세면 느리고 비싸다.
   */
  async function targetHasReceipts(targetUid) {
    const snap = await db
      .collection('users').doc(targetUid).collection('receipts')
      .limit(1).get();
    return !snap.empty;
  }

  /** 체험 계정의 영수증이 몇 장인가. 안내 문구에 쓴다. */
  async function countGuestReceipts(guestUid) {
    const snap = await db
      .collection('users').doc(guestUid).collection('receipts')
      .limit(MAX_DOCS).get();
    return snap.size;
  }

  // ── 본 작업 ─────────────────────────────────────────────────

  /**
   * 옮긴다. 확인 → (받는 쪽이 새 회원인가) → 사진 → 영수증 → 사입 리스트
   * → 동의 이력 → 완료 기록.
   *
   * 🔴 받는 계정에 영수증이 **한 장이라도 있으면 아무것도 옮기지 않는다.**
   *    섞는 판단은 사람이 해야 한다(#195 ⑤-c). 그때는 `skipped` 가 true 다.
   *
   * @returns {Promise<{receipts:number, purchaseLists:number, photos:number,
   *                    alreadyDone:boolean, skipped:boolean,
   *                    reason:string, guestReceipts:number}>}
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
      //
      // 🔴 '기존 회원이라 건너뜀' 도 끝난 것이다. 다시 부른다고 옮기지
      //    않는다 — 그 사이에 영수증이 지워졌더라도 판단은 그대로 둔다.
      //    (이중 처리 방지. 합치기는 나중에 사람이 고른다)
      if (m.status === 'complete' || m.status === 'skipped_existing_member') {
        return {
          receipts: m.receipts || 0,
          purchaseLists: m.purchaseLists || 0,
          photos: m.photos || 0,
          alreadyDone: true,
          skipped: m.status === 'skipped_existing_member',
          reason: m.reason || '',
          guestReceipts: m.guestReceipts || 0,
        };
      }
      // 끊긴 작업이다. 아래에서 이어서 끝낸다(같은 자리에 다시 쓴다).
    }

    // 🔴 **받는 계정이 이미 쓰던 분인가.** 옮기기 **전에** 본다.
    //
    //    영수증이 한 장이라도 있으면 섞지 않는다. 같은 영수증을 체험에서도
    //    찍고 가입 뒤에도 찍었을 수 있는데, 서버가 말없이 합치면 매입
    //    합계가 부풀고 되돌리기도 어렵다. 사람이 대조 화면에서 고르는 일로
    //    남겨 둔다.
    if (await targetHasReceipts(targetUid)) {
      const guestReceipts = await countGuestReceipts(guestUid);
      const reason = 'existing_member';
      await markRef.set({
        guestUid,
        targetUid,
        status: 'skipped_existing_member',
        reason,
        guestReceipts,
        receipts: 0,
        purchaseLists: 0,
        photos: 0,
        sourceKept: true,
        skippedAt: new Date().toISOString(),
      }, { merge: true });

      log.info('기존 회원이라 옮기지 않음', {
        guestUid, targetUid, guestReceipts,
      });

      return {
        receipts: 0,
        purchaseLists: 0,
        photos: 0,
        alreadyDone: false,
        skipped: true,
        reason,
        guestReceipts,
      };
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

        // 🔴 **중복 검사 지문**(`ReceiptKey`) 네 칸을 일부러 다시 적는다.
        //    앱은 지문을 따로 저장하지 않고 이 값들로 그때그때 계산한다
        //    (`receipt_duplicate_service.dart`: 매입처·날짜·총액·품목).
        //    그대로 옮겨야 가입 뒤 같은 영수증을 다시 찍었을 때
        //    **기존 중복 검사에 걸린다.**
        //
        //    위 `...data` 로도 넘어오지만, 나중에 누가 칸을 추려낼 때
        //    이 네 개가 빠지지 않도록 못 박아 둔다. 없는 칸은 담지 않는다
        //    (`undefined` 는 Firestore 가 받지 않는다).
        ...fingerprintOf(data),

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
      reason: 'new_member',
      receipts,
      purchaseLists,
      photos,
      guestReceipts: receipts,
      sourceKept: true,
      completedAt: new Date().toISOString(),
    }, { merge: true });

    log.info('체험 데이터 옮기기 완료', {
      guestUid, targetUid, receipts, purchaseLists, photos,
    });

    return {
      receipts,
      purchaseLists,
      photos,
      alreadyDone: false,
      skipped: false,
      reason: 'new_member',
      guestReceipts: receipts,
    };
  }

  return { run, verify, shortOf };
}

module.exports = {
  createMigrator,
  MigrateError,
  TRIAL_PREFIX,
  MIGRATIONS,
  FINGERPRINT_FIELDS,
  shortOf,
};
