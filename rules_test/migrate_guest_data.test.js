// 🔴 체험(익명) 데이터 옮기기 — 서버 함수 테스트 (#195 ⑤-b)
//
// 이 함수는 **남의 데이터를 옮길 수 있는 힘**을 가진다(Admin SDK 는 보안
// 규칙을 지나치지 않는다). 그래서 \"되는가\" 보다 **\"엉뚱한 곳으로 가지
// 않는가\"** 를 훨씬 더 많이 본다.
//
// 에뮬레이터 셋(auth · firestore · storage)을 켜고 진짜로 옮겨 본다.
// `firebase-admin` 은 `functions/node_modules` 것을 그대로 빌려 쓴다
// (rules_test 에 또 설치하면 버전이 갈라진다).

import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

import { beforeAll, afterAll, beforeEach, describe, test, expect } from 'vitest';

const here = dirname(fileURLToPath(import.meta.url));
const r = (p) => resolve(here, '..', p);
const read = (p) => readFileSync(r(p), 'utf8');

// functions/ 의 Admin SDK 와 우리 모듈을 빌려 온다.
//
// 🔴 기준을 `functions/package.json` **파일**로 잡는다. 폴더 경로를 주면
//    `resolve()` 가 끝의 `/` 를 떼어 버려서, Node 가 그것을 파일로 보고
//    한 칸 위(webapp/node_modules)부터 찾는다 — firebase-admin 을 못 찾는다.
const fnRequire = createRequire(r('functions/package.json'));
const admin = fnRequire('firebase-admin');
const { createMigrator, MigrateError, shortOf, FINGERPRINT_FIELDS } =
  fnRequire(r('functions/migrate_guest_data.js'));

const PROJECT = 'flownote-rules-test';
const AUTH_HOST = '127.0.0.1:9099';

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = AUTH_HOST;
process.env.STORAGE_EMULATOR_HOST = 'http://127.0.0.1:9199';

let app;
let auth;
let db;
let bucket;
let migrate;

/** 조용한 로거 — 테스트 출력이 지저분해지지 않게. */
const quiet = { info() {}, warn() {}, error() {} };

// ── 에뮬레이터 손잡이 ────────────────────────────────────────

/** 익명 계정을 만들고 `{uid, idToken}` 을 준다. */
async function newAnon() {
  const res = await fetch(
    `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ returnSecureToken: true }),
    },
  );
  const j = await res.json();
  return { uid: j.localId, idToken: j.idToken };
}

/** 이메일 회원을 만들고 `{uid, idToken}` 을 준다. (익명이 아닌 진짜 계정) */
async function newMember(email) {
  const res = await fetch(
    `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email, password: 'pw123456', returnSecureToken: true,
      }),
    },
  );
  const j = await res.json();
  return { uid: j.localId, idToken: j.idToken };
}

/** 회원이 함수를 부를 때 들어오는 토큰 모양. */
const memberToken = (provider = 'password') =>
  ({ firebase: { sign_in_provider: provider, identities: {} } });
const anonToken = () =>
  ({ firebase: { sign_in_provider: 'anonymous', identities: {} } });

/** 체험 계정에 영수증 n장 + 사진 n장 + 사입 리스트 1개를 깔아 둔다. */
async function seedGuest(uid, n = 5) {
  for (let i = 1; i <= n; i += 1) {
    const object = `users/${uid}/receipts/r_${i}.jpg`;
    await bucket.file(object).save(Buffer.from([0x89, 0x50, i]), {
      contentType: 'image/jpeg',
    });
    await db.doc(`users/${uid}/receipts/r${i}`).set({
      id: `r${i}`,
      storeName: `체험상회${i}`,
      totalAmount: 1000 * i,
      // 앱이 저장하는 모양 그대로 — 내려받기 주소 안에 경로가 인코딩돼 있다.
      imagePath:
        `https://firebasestorage.googleapis.com/v0/b/${bucket.name}/o/` +
        `${encodeURIComponent(object)}?alt=media&token=old-token`,
    });
  }
  await db.doc(`users/${uid}/purchase_lists/p1`).set({
    id: 'p1', purpose: '체험 사입', items: [],
  });
  await db.collection(`users/${uid}/consent_log`).doc('c1').set({
    consents: { privacy: { agreed: true, version: '1.0' } },
    at: new Date().toISOString(),
  });
}

async function countOf(uid, col) {
  const s = await db.collection(`users/${uid}/${col}`).get();
  return s.size;
}

async function wipe() {
  // Firestore 전체 비우기 (에뮬레이터 전용 엔드포인트).
  await fetch(
    `http://127.0.0.1:8080/emulator/v1/projects/${PROJECT}/databases/(default)/documents`,
    { method: 'DELETE' },
  );
  try {
    const [files] = await bucket.getFiles();
    await Promise.all(files.map((f) => f.delete().catch(() => {})));
  } catch (_) {/* 비어 있으면 그만 */}
}

beforeAll(async () => {
  app = admin.initializeApp(
    { projectId: PROJECT, storageBucket: `${PROJECT}.appspot.com` },
    'migrate-test',
  );
  auth = app.auth();
  db = app.firestore();
  bucket = app.storage().bucket();
  migrate = createMigrator({ auth, db, bucket, logger: quiet });
});

afterAll(async () => { await app?.delete(); });
beforeEach(wipe);

// ══════════════════════════════════════════════════════════════
// 되는 길
// ══════════════════════════════════════════════════════════════
describe('체험 → 새 카카오 회원 옮기기', () => {
  test('🔴 영수증 5장·사입 리스트·사진이 모두 따라온다', async () => {
    const guest = await newAnon();
    await seedGuest(guest.uid, 5);

    // 받는 쪽은 카카오 회원 (커스텀 토큰 → provider 가 'custom').
    const K = 'kakao:98765';
    const out = await migrate.run({
      guestIdToken: guest.idToken,
      callerUid: K,
      callerToken: memberToken('custom'),
    });

    expect(out.receipts).toBe(5);
    expect(out.purchaseLists).toBe(1);
    expect(out.photos).toBe(5);
    expect(await countOf(K, 'receipts')).toBe(5);
    expect(await countOf(K, 'purchase_lists')).toBe(1);
  });

  test('🔴 옮기면 원래 게스트의 meta/guest 에 migratedAt 이 적힌다', async () => {
    // 방문자 집계용. `migrations` 는 앱이 못 읽는 서버 전용 칸이라,
    // 게스트 쪽에도 흔적을 남긴다.
    const guest = await newAnon();
    await seedGuest(guest.uid, 2);
    const K = 'kakao:5555';

    await migrate.run({
      guestIdToken: guest.idToken,
      callerUid: K,
      callerToken: memberToken('custom'),
    });

    const snap = await db.doc(`users/${guest.uid}/meta/guest`).get();
    expect(snap.exists).toBe(true);
    expect(typeof snap.data().migratedAt).toBe('string');
    expect(snap.data().migratedTo).toBe(K);

    // 🔴 **받는 계정(회원) 쪽에는 이 표시를 만들지 않는다.**
    const mine = await db.doc(`users/${K}/meta/guest`).get();
    expect(mine.exists).toBe(false);
  });

  test('🔴 사진 주소가 새 경로로 바뀐다', async () => {
    const guest = await newAnon();
    await seedGuest(guest.uid, 2);
    const K = 'kakao:1';
    await migrate.run({
      guestIdToken: guest.idToken,
      callerUid: K,
      callerToken: memberToken('custom'),
    });

    const snap = await db.collection(`users/${K}/receipts`).get();
    for (const d of snap.docs) {
      const p = d.data().imagePath;
      // 옛 게스트 경로가 남아 있으면 가입 뒤 사진이 깨져 보인다.
      expect(p).not.toContain(encodeURIComponent(`users/${guest.uid}/`));
      expect(p).toContain(encodeURIComponent(`users/${K}/`));
    }
    // 실제 파일도 새 자리에 있다.
    const [files] = await bucket.getFiles({ prefix: `users/${K}/` });
    expect(files.length).toBe(2);
  });

  test('🔴 옮긴 영수증에 trialReceipt 표시가 붙는다 (학습 제외용)', async () => {
    const guest = await newAnon();
    await seedGuest(guest.uid, 3);
    const K = 'kakao:2';
    await migrate.run({
      guestIdToken: guest.idToken,
      callerUid: K,
      callerToken: memberToken('custom'),
    });

    const snap = await db.collection(`users/${K}/receipts`).get();
    expect(snap.size).toBe(3);
    for (const d of snap.docs) {
      expect(d.data().trialReceipt).toBe(true);
      expect(d.data().migratedFrom).toBe(guest.uid);
    }
  });

  test('🔴 동의 이력이 출처와 함께 따라온다', async () => {
    const guest = await newAnon();
    await seedGuest(guest.uid, 1);
    const K = 'kakao:3';
    await migrate.run({
      guestIdToken: guest.idToken,
      callerUid: K,
      callerToken: memberToken('custom'),
    });

    const snap = await db.collection(`users/${K}/consent_log`).get();
    expect(snap.size).toBe(1);
    expect(snap.docs[0].data().source).toBe('guest_trial');
    expect(snap.docs[0].data().migratedFrom).toBe(guest.uid);
  });

  test('🔴 기록이 남고, 원본은 지우지 않는다', async () => {
    const guest = await newAnon();
    await seedGuest(guest.uid, 5);
    const K = 'kakao:4';
    await migrate.run({
      guestIdToken: guest.idToken,
      callerUid: K,
      callerToken: memberToken('custom'),
    });

    const m = (await db.doc(`migrations/${guest.uid}`).get()).data();
    expect(m.guestUid).toBe(guest.uid);
    expect(m.targetUid).toBe(K);
    expect(m.status).toBe('complete');
    expect(m.receipts).toBe(5);
    expect(m.purchaseLists).toBe(1);
    expect(m.photos).toBe(5);
    expect(m.completedAt).toBeTruthy();
    expect(m.sourceKept).toBe(true);

    // 🔴 원본은 그대로 있다. 지우다 끊기면 양쪽을 모두 잃는다.
    expect(await countOf(guest.uid, 'receipts')).toBe(5);
  });
});

describe('이미 쓰던 회원 — 아무것도 옮기지 않는다 (#195 ⑤-c)', () => {
  // 🔴 섞는 판단은 사람이 해야 한다. 서버가 말없이 합치면 같은 영수증을
  //    체험에서도 찍고 가입 뒤에도 찍은 경우 매입 합계가 부푼다.
  //    합치기는 나중에 대조 화면에서 사장님이 직접 고르신다.

  async function skipCase(K) {
    await db.doc(`users/${K}/receipts/mine1`).set({ id: 'mine1', storeName: '내것1' });
    await db.doc(`users/${K}/receipts/mine2`).set({ id: 'mine2', storeName: '내것2' });
    const guest = await newAnon();
    await seedGuest(guest.uid, 5);
    const out = await migrate.run({
      guestIdToken: guest.idToken,
      callerUid: K,
      callerToken: memberToken('custom'),
    });
    return { guest, out };
  }

  test('🔴 영수증이 이미 있으면 한 건도 옮기지 않는다', async () => {
    const K = 'kakao:5';
    const { out } = await skipCase(K);

    expect(out.skipped).toBe(true);
    expect(out.reason).toBe('existing_member');
    expect(out.receipts).toBe(0);
    expect(out.purchaseLists).toBe(0);
    expect(out.photos).toBe(0);
    // 체험 영수증이 몇 장인지는 알려 준다 (나중에 합칠 때 쓴다).
    expect(out.guestReceipts).toBe(5);
  });

  test('🔴 기존 영수증은 하나도 안 바뀐다', async () => {
    const K = 'kakao:5b';
    await skipCase(K);

    // 2장 그대로. 7장이 되면 안 된다.
    expect(await countOf(K, 'receipts')).toBe(2);
    expect(await countOf(K, 'purchase_lists')).toBe(0);
    const mine = await db.doc(`users/${K}/receipts/mine1`).get();
    expect(mine.data().storeName).toBe('내것1');
    expect(mine.data().trialReceipt).toBeUndefined();
    // 사진도 안 옮겼다.
    const [files] = await bucket.getFiles({ prefix: `users/${K}/` });
    expect(files.length).toBe(0);
  });

  test('🔴 체험 원본도 그대로 남는다', async () => {
    const K = 'kakao:5c';
    const { guest } = await skipCase(K);
    expect(await countOf(guest.uid, 'receipts')).toBe(5);
  });

  test('🔴 migrations 에 "기존 회원이라 옮기지 않음" 이 남는다', async () => {
    const K = 'kakao:5d';
    const { guest } = await skipCase(K);

    const m = (await db.doc(`migrations/${guest.uid}`).get()).data();
    expect(m.status).toBe('skipped_existing_member');
    expect(m.reason).toBe('existing_member');
    expect(m.guestUid).toBe(guest.uid);
    expect(m.targetUid).toBe(K);
    expect(m.receipts).toBe(0);
    expect(m.guestReceipts).toBe(5);
    expect(m.sourceKept).toBe(true);
    expect(m.skippedAt).toBeTruthy();
  });

  test('🔴 다시 불러도 옮기지 않는다 (이중 처리 방지)', async () => {
    const K = 'kakao:5e';
    const { guest } = await skipCase(K);

    // 그 사이 기존 영수증이 사라져도 판단은 그대로다.
    await db.doc(`users/${K}/receipts/mine1`).delete();
    await db.doc(`users/${K}/receipts/mine2`).delete();

    const again = await migrate.run({
      guestIdToken: guest.idToken,
      callerUid: K,
      callerToken: memberToken('custom'),
    });
    expect(again.skipped).toBe(true);
    expect(again.alreadyDone).toBe(true);
    expect(await countOf(K, 'receipts')).toBe(0);
  });
});

// ══════════════════════════════════════════════════════════════
// 중복 검사 지문이 함께 옮겨진다
//
// 🔴 앱은 지문을 저장하지 않는다. **매입처·날짜·총액·품목** 네 칸에서
//    그때그때 계산한다(`receipt_duplicate_service.dart` 의 `ReceiptKey`).
//    그래서 네 칸이 그대로 따라가야 가입 뒤 같은 영수증을 다시 찍었을 때
//    기존 중복 검사에 걸린다.
// ══════════════════════════════════════════════════════════════
describe('🔴 중복 검사 지문', () => {
  /** 앱의 `ReceiptKey` 와 같은 규칙으로 지문을 만든다. */
  function keyOf(data) {
    const store = String(data.storeName || '')
      .toLowerCase()
      .replace(/주식회사|\(주\)|（주）|㈜|유한회사|\(유\)/g, '')
      .replace(/[\s.\-·,]/g, '');
    const d = new Date(data.date);
    const day = `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
    const total = Math.round(Number(data.totalAmount) || 0);
    const items = (data.items || [])
      .map((i) => `${String(i.name || '').toLowerCase().replace(/\s/g, '')}`
        + `|${i.quantity}|${Math.round(Number(i.unitPrice) || 0)}`)
      .sort()
      .join(';');
    return `${store}#${day}#${total}#${items}`;
  }

  test('🔴 네 칸이 글자 그대로 따라온다', async () => {
    const guest = await newAnon();
    // 지문 네 칸이 모두 들어간 영수증 하나.
    await db.doc(`users/${guest.uid}/receipts/r1`).set({
      id: 'r1',
      storeName: '(주)대한꽃도매',
      date: '2026-07-24T09:30:00.000',
      totalAmount: 160000,
      items: [
        { name: '장미', quantity: 10, unitPrice: 12000 },
        { name: '수국', quantity: 2, unitPrice: 20000 },
      ],
    });

    const K = 'kakao:fp1';
    await migrate.run({
      guestIdToken: guest.idToken,
      callerUid: K,
      callerToken: memberToken('custom'),
    });

    const before = (await db.doc(`users/${guest.uid}/receipts/r1`).get()).data();
    const snap = await db.collection(`users/${K}/receipts`).get();
    expect(snap.size).toBe(1);
    const after = snap.docs[0].data();

    for (const f of ['storeName', 'date', 'totalAmount']) {
      expect(after[f]).toEqual(before[f]);
    }
    expect(after.items).toEqual(before.items);
    // 🔴 지문이 같다 = 다시 찍으면 중복으로 잡힌다.
    expect(keyOf(after)).toBe(keyOf(before));
  });

  test('🔴 옮긴 뒤 같은 영수증을 다시 찍으면 중복으로 걸린다', async () => {
    const guest = await newAnon();
    await db.doc(`users/${guest.uid}/receipts/r1`).set({
      id: 'r1',
      storeName: '대한꽃도매',
      date: '2026-07-24T09:30:00.000',
      totalAmount: 160000,
      items: [{ name: '장미', quantity: 10, unitPrice: 16000 }],
    });

    const K = 'kakao:fp2';
    await migrate.run({
      guestIdToken: guest.idToken,
      callerUid: K,
      callerToken: memberToken('custom'),
    });

    // 가입 뒤 **같은 영수증을 다시 찍었다** — OCR 이 가게 이름을 조금
    // 다르게 읽은 상황까지 흉내 낸다(정규화로 같아져야 한다).
    const rescan = {
      storeName: '(주)대한 꽃도매',
      date: '2026-07-24T18:00:00.000',   // 같은 날, 다른 시각
      totalAmount: 160000,
      items: [{ name: '장미', quantity: 10, unitPrice: 16000 }],
    };

    const moved = (await db.collection(`users/${K}/receipts`).get()).docs[0].data();
    expect(keyOf(rescan)).toBe(keyOf(moved));
  });

  test('🔴 지문 칸 목록이 앱과 같다', () => {
    // 앱의 `ReceiptKey.ofReceipt` 가 읽는 네 칸 그대로여야 한다.
    expect(FINGERPRINT_FIELDS)
      .toEqual(['storeName', 'date', 'totalAmount', 'items']);

    const dart = read('lib/services/receipt_duplicate_service.dart');
    const ofReceipt = dart.slice(
      dart.indexOf('static ReceiptKey ofReceipt'),
      dart.indexOf('static ReceiptKey ofDraft'),
    );
    expect(ofReceipt).toContain('r.storeName');
    expect(ofReceipt).toContain('r.date');
    expect(ofReceipt).toContain('r.totalAmount');
    expect(ofReceipt).toContain('r.items');
  });

  test('🔴 서버가 영수증을 옮길 때 지문을 따로 챙긴다', () => {
    const js = read('functions/migrate_guest_data.js');

    // 지문은 한 곳(`fingerprintOf`)에서만 만든다. 여러 군데로 흩어지면
    // 한쪽만 고치고 잊는다.
    expect(js).toContain('function fingerprintOf(data)');
    expect(js).toContain('for (const f of FINGERPRINT_FIELDS)');

    // 영수증 복사에서 그 지문을 실제로 쓴다.
    const part = js.slice(js.indexOf("'receipts',"), js.indexOf("'purchase_lists',"));
    expect(part).toContain('...fingerprintOf(data),');

    // 🔴 없는 칸은 담지 않는다. `undefined` 를 쓰면 Firestore 가 문서를
    //    통째로 거부해서 **옮기기 자체가 실패**한다(실제로 한 번 겪었다).
    expect(js).toContain('if (data[f] !== undefined) out[f] = data[f];');
  });
});

describe('같은 요청을 두 번 보내도 안전하다', () => {
  test('🔴 두 번 불러도 늘어나지 않는다', async () => {
    const guest = await newAnon();
    await seedGuest(guest.uid, 5);
    const K = 'kakao:6';
    const call = () => migrate.run({
      guestIdToken: guest.idToken,
      callerUid: K,
      callerToken: memberToken('custom'),
    });

    const a = await call();
    const b = await call();

    expect(a.alreadyDone).toBe(false);
    expect(b.alreadyDone).toBe(true);
    expect(b.receipts).toBe(5);
    // 🔴 10장이 되면 안 된다.
    expect(await countOf(K, 'receipts')).toBe(5);
    expect(await countOf(K, 'purchase_lists')).toBe(1);
    const [files] = await bucket.getFiles({ prefix: `users/${K}/` });
    expect(files.length).toBe(5);
  });

  test('🔴 끊긴 작업(running) 을 다시 불러도 중복되지 않는다', async () => {
    const guest = await newAnon();
    await seedGuest(guest.uid, 5);
    const K = 'kakao:7';
    await migrate.run({
      guestIdToken: guest.idToken,
      callerUid: K,
      callerToken: memberToken('custom'),
    });
    // 완료 표시를 지워 \"중간에 끊긴 것\" 으로 되돌린다.
    await db.doc(`migrations/${guest.uid}`).set(
      { status: 'running' }, { merge: true });

    await migrate.run({
      guestIdToken: guest.idToken,
      callerUid: K,
      callerToken: memberToken('custom'),
    });
    expect(await countOf(K, 'receipts')).toBe(5);
  });
});

// ══════════════════════════════════════════════════════════════
// 엉뚱한 곳으로 가지 않는다 — 여기가 이 테스트의 핵심
// ══════════════════════════════════════════════════════════════
describe('🔴 다른 회원에게 옮겨지지 않는다', () => {
  test('🔴 회원 B 가 게스트 A 토큰으로 불러도 B 에게만 간다 (C 는 그대로)', async () => {
    const guest = await newAnon();
    await seedGuest(guest.uid, 5);

    const C = 'kakao:victim';
    await db.doc(`users/${C}/receipts/c1`).set({ id: 'c1', storeName: '제3자' });

    const B = 'kakao:caller';
    const out = await migrate.run({
      guestIdToken: guest.idToken,
      callerUid: B,
      callerToken: memberToken('custom'),
    });

    expect(out.receipts).toBe(5);
    // 부른 사람(B) 에게만 갔다.
    expect(await countOf(B, 'receipts')).toBe(5);
    // 🔴 제3자 C 는 한 글자도 안 바뀌었다.
    expect(await countOf(C, 'receipts')).toBe(1);
    expect((await db.doc(`users/${C}/receipts/c1`).get()).data().storeName)
      .toBe('제3자');
  });

  test('🔴 이미 옮긴 체험 데이터를 다른 사람이 또 가져갈 수 없다', async () => {
    const guest = await newAnon();
    await seedGuest(guest.uid, 5);
    await migrate.run({
      guestIdToken: guest.idToken,
      callerUid: 'kakao:first',
      callerToken: memberToken('custom'),
    });

    await expect(migrate.run({
      guestIdToken: guest.idToken,
      callerUid: 'kakao:second',
      callerToken: memberToken('custom'),
    })).rejects.toThrow(MigrateError);

    expect(await countOf('kakao:second', 'receipts')).toBe(0);
  });
});

describe('🔴 잘못된 요청은 모두 거절하고, 아무 데이터도 바꾸지 않는다', () => {
  test('🔴 위조한 토큰', async () => {
    const K = 'kakao:8';
    await expect(migrate.run({
      guestIdToken: 'this.is.not-a-real-token',
      callerUid: K,
      callerToken: memberToken('custom'),
    })).rejects.toThrow(MigrateError);
    expect(await countOf(K, 'receipts')).toBe(0);
  });

  test('🔴 폐기된(만료 처리된) 토큰', async () => {
    const guest = await newAnon();
    await seedGuest(guest.uid, 5);
    // 발급 시각과 폐기 시각이 같은 초로 뭉개지지 않도록 한 박자 쉰다.
    await new Promise((s) => setTimeout(s, 1500));
    await auth.revokeRefreshTokens(guest.uid);

    const K = 'kakao:9';
    await expect(migrate.run({
      guestIdToken: guest.idToken,
      callerUid: K,
      callerToken: memberToken('custom'),
    })).rejects.toThrow(MigrateError);
    expect(await countOf(K, 'receipts')).toBe(0);
  });

  test('🔴 회원 토큰을 체험 토큰인 척 내밀기', async () => {
    // 🔴 이걸 막지 못하면 남의 **회원** 데이터를 통째로 가져갈 수 있다.
    const victim = await newMember(`victim${Date.now()}@test.com`);
    await db.doc(`users/${victim.uid}/receipts/v1`).set({ id: 'v1', storeName: '남의것' });

    const K = 'kakao:10';
    await expect(migrate.run({
      guestIdToken: victim.idToken,
      callerUid: K,
      callerToken: memberToken('custom'),
    })).rejects.toThrow(MigrateError);

    expect(await countOf(K, 'receipts')).toBe(0);
    expect(await countOf(victim.uid, 'receipts')).toBe(1);
  });

  test('🔴 익명 계정이 부르는 경우', async () => {
    const guest = await newAnon();
    await seedGuest(guest.uid, 5);
    const other = await newAnon();

    await expect(migrate.run({
      guestIdToken: guest.idToken,
      callerUid: other.uid,
      callerToken: anonToken(),
    })).rejects.toThrow(MigrateError);
    expect(await countOf(other.uid, 'receipts')).toBe(0);
  });

  test('🔴 로그인하지 않은 호출', async () => {
    const guest = await newAnon();
    await expect(migrate.run({
      guestIdToken: guest.idToken,
      callerUid: null,
      callerToken: null,
    })).rejects.toThrow(MigrateError);
  });

  test('🔴 토큰을 아예 안 보낸 경우', async () => {
    await expect(migrate.run({
      guestIdToken: '',
      callerUid: 'kakao:11',
      callerToken: memberToken('custom'),
    })).rejects.toThrow(MigrateError);
  });

  test('🔴 자기 자신에게 옮기기', async () => {
    const guest = await newAnon();
    await expect(migrate.run({
      guestIdToken: guest.idToken,
      callerUid: guest.uid,
      callerToken: memberToken('custom'),
    })).rejects.toThrow(MigrateError);
  });

  test('🔴 거절된 요청은 migrations 기록도 남기지 않는다', async () => {
    const guest = await newAnon();
    await seedGuest(guest.uid, 2);
    const other = await newAnon();
    await migrate.run({
      guestIdToken: guest.idToken,
      callerUid: other.uid,
      callerToken: anonToken(),
    }).catch(() => {});
    expect((await db.doc(`migrations/${guest.uid}`).get()).exists).toBe(false);
  });
});

// ══════════════════════════════════════════════════════════════
// 소스 계약 — 코드가 위험한 모양으로 바뀌면 여기서 걸린다
// ══════════════════════════════════════════════════════════════
describe('🔴 소스 계약', () => {
  test('🔴 받는 계정을 입력(data)에서 읽지 않는다', () => {
    const idx = read('functions/index.js');
    const part = idx.slice(idx.indexOf('exports.migrateGuestData'));

    // 🔴 입력에서 읽어도 되는 것은 체험 토큰 하나뿐이다.
    //    `request.data.targetUid` 같은 줄이 생기면 \"내 데이터를 남의
    //    계정으로 보내 줘\" 가 가능해진다.
    const reads = part.match(/request\.data\.[A-Za-z_]+/g) || [];
    expect([...new Set(reads)]).toEqual(['request.data.guestIdToken']);

    // 받는 계정은 오직 호출한 사람이다.
    expect(part).toContain('callerUid: request.auth && request.auth.uid');
    for (const bad of ['targetUid: request.data', 'uid: request.data',
      'data.targetUid', 'data.uid', 'data.callerUid']) {
      expect(part).not.toContain(bad);
    }
  });

  test('🔴 일꾼도 받는 uid 를 입력에서 만들지 않는다', () => {
    const src = read('functions/migrate_guest_data.js');
    // targetUid 는 callerUid 에서만 나온다.
    expect(src).toContain('return { guestUid, targetUid: callerUid };');
    expect(src).not.toMatch(/targetUid\s*=\s*(data|input|payload|request)/);
  });

  test('🔴 네 가지 확인이 모두 살아 있다', () => {
    const src = read('functions/migrate_guest_data.js');
    expect(src).toContain('verifyIdToken(guestIdToken, true)');   // 진짜·폐기
    expect(src).toContain("guestProvider !== 'anonymous'");        // 익명인가
    expect(src).toContain("callerProvider === 'anonymous'");       // 부른 이
    expect(src).toContain('guestUid === callerUid');               // 같으면 거절
  });

  test('🔴 터질 수 있는 방식으로 provider 를 꺼내지 않는다 (#194)', () => {
    const src = read('functions/migrate_guest_data.js');
    // Admin SDK 쪽은 평범한 객체라 `.` 접근이 되지만, 없는 경우를 반드시
    // 함께 본다. `||` 기본값이 그 장치다.
    expect(src).toMatch(/sign_in_provider\) \|\| ''/);
  });

  test('🔴 원본을 지우는 코드가 없다 (30일 정리 작업이 맡는다)', () => {
    const src = read('functions/migrate_guest_data.js');
    expect(src).not.toMatch(/\.delete\(\)/);
    expect(src).not.toContain('deleteFiles');
    expect(src).not.toContain('recursiveDelete');
  });

  test('🔴 복사본 이름이 게스트 uid 로 정해진다 (두 번 불러도 같은 자리)', () => {
    const src = read('functions/migrate_guest_data.js');
    expect(src).toContain('shortOf(guestUid)');
    // 시각·난수로 이름을 지으면 부를 때마다 새 문서가 쌓인다.
    expect(src).not.toMatch(/Date\.now\(\).{0,40}(docId|id\s*=)/);
    expect(shortOf('abc')).toBe(shortOf('abc'));
    expect(shortOf('abc')).not.toBe(shortOf('abd'));
  });

  test('🔴 기존 kakaoCustomToken 은 그대로다', () => {
    const idx = read('functions/index.js');
    // 있어야 할 것
    expect(idx).toContain('exports.kakaoCustomToken = onRequest(');
    expect(idx).toContain('secrets: [KAKAO_SIGNER_SA]');
    expect(idx).toContain('createCustomToken(uid, {');
    expect(idx).toContain('https://kapi.kakao.com/v2/user/me');
    // 다른 함수들도 그대로
    expect(idx).toContain('exports.updateFlowerPrices = onSchedule(');
    expect(idx).toContain('exports.updateFlowerPricesNow = onRequest(');
  });

  test('🔴 migrations 는 앱에서 읽지도 쓰지도 못한다', () => {
    const rules = read('firestore.rules');
    const part = rules.slice(rules.indexOf('match /migrations/{guestUid}'));
    expect(part).toContain('allow read, write: if false;');
  });
});
