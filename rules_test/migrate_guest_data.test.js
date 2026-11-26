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
const { createMigrator, MigrateError, shortOf } =
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

describe('이미 쓰던 회원에게 합치기', () => {
  test('🔴 기존 데이터는 그대로 두고 5장이 더해진다', async () => {
    const K = 'kakao:5';
    // 회원이 이미 쓰던 영수증 2장.
    await db.doc(`users/${K}/receipts/mine1`).set({ id: 'mine1', storeName: '내것1' });
    await db.doc(`users/${K}/receipts/mine2`).set({ id: 'mine2', storeName: '내것2' });

    const guest = await newAnon();
    await seedGuest(guest.uid, 5);
    await migrate.run({
      guestIdToken: guest.idToken,
      callerUid: K,
      callerToken: memberToken('custom'),
    });

    expect(await countOf(K, 'receipts')).toBe(7);
    // 🔴 기존 것이 덮어써지지 않았다.
    const mine = await db.doc(`users/${K}/receipts/mine1`).get();
    expect(mine.data().storeName).toBe('내것1');
    expect(mine.data().trialReceipt).toBeUndefined();
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
