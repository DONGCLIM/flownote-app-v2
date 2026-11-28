// 🔴 가입하지 않은 체험 데이터 30일 뒤 삭제 — 서버 함수 테스트
//
// 이 함수는 **계정과 데이터를 지우는 힘**을 가진다. 되돌릴 수 없다.
// 그래서 "지워지는가" 보다 **"엉뚱한 것을 지우지 않는가"** 를 훨씬 더
// 많이 본다. 회원 한 분이라도 지워지면 장부가 영영 사라진다.
//
// 🔴 특히 **카카오**를 집요하게 본다. 카카오는 커스텀 토큰이라 Admin SDK
//    눈에 익명 계정과 **구별되는 칸이 하나도 없다**(제공업체 없음, 메일
//    없음, 클레임도 실패할 수 있음). 에뮬레이터로 직접 재서 확인한
//    사실이고, `cleanup_guest_data.js` 머리말에 적어 두었다.

import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

import { beforeAll, afterAll, beforeEach, describe, test, expect } from 'vitest';

const here = dirname(fileURLToPath(import.meta.url));
const r = (p) => resolve(here, '..', p);
const read = (p) => readFileSync(r(p), 'utf8');

// 🔴 기준을 `functions/package.json` **파일**로 잡는다. 폴더 경로를 주면
//    `resolve()` 가 끝의 `/` 를 떼어 Node 가 한 칸 위부터 찾는다.
const fnRequire = createRequire(r('functions/package.json'));
const admin = fnRequire('firebase-admin');
const { createCleaner, classifyUser, SKIP, KEEP_DAYS } =
  fnRequire(r('functions/cleanup_guest_data.js'));

const PROJECT = 'flownote-rules-test';
const AUTH_HOST = '127.0.0.1:9099';

process.env.FIRESTORE_EMULATOR_HOST = '127.0.0.1:8080';
process.env.FIREBASE_AUTH_EMULATOR_HOST = AUTH_HOST;
process.env.STORAGE_EMULATOR_HOST = 'http://127.0.0.1:9199';

const DAY = 86400000;

let app; let auth; let db; let bucket; let cleaner;
const quiet = { info() {}, warn() {}, error() {} };

// ── 계정 만들기 ──────────────────────────────────────────────

/** 익명(체험) 계정. */
async function newAnon() {
  const res = await fetch(
    `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`,
    { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ returnSecureToken: true }) });
  const j = await res.json();
  return j.localId;
}

/** 이메일 가입 — 앱의 '웹앱 내 일반 가입'. */
async function newEmail(email) {
  const res = await fetch(
    `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake`,
    { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password: 'pw123456', returnSecureToken: true }) });
  const j = await res.json();
  return j.localId;
}

/** 구글·애플처럼 **연동 제공업체**가 붙는 가입. */
async function newIdp(providerId, email, sub) {
  const res = await fetch(
    `http://${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithIdp?key=fake`,
    { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        postBody:
          `id_token=${encodeURIComponent(JSON.stringify({ sub, email }))}` +
          `&providerId=${providerId}`,
        requestUri: 'http://localhost', returnSecureToken: true }) });
  const j = await res.json();
  if (!j.localId) throw new Error(`${providerId}: ${JSON.stringify(j)}`);
  return j.localId;
}

/**
 * 카카오 회원 — `kakaoCustomToken` 이 하는 것과 **똑같이** 만든다.
 * (`admin.createUser` + `setCustomUserClaims`, 제공업체는 안 붙는다)
 *
 * [withClaims] 가 false 면 **클레임 저장이 실패한 최악의 경우**다.
 * 실제 함수가 `try/catch` 로 감싸고 있어 충분히 일어날 수 있다.
 */
async function newKakao(id, { withClaims = true, email = null } = {}) {
  const uid = `kakao:${id}`;
  await auth.createUser({ uid, ...(email ? { email, emailVerified: true } : {}) });
  if (withClaims) {
    await auth.setCustomUserClaims(uid, { provider: 'kakao', kakaoId: String(id) });
  }
  return uid;
}

// ── 데이터 깔기 ──────────────────────────────────────────────

/** 영수증 n장 + 사진 n장을 깔아 둔다. */
async function seed(uid, n = 5) {
  for (let i = 1; i <= n; i += 1) {
    await bucket.file(`users/${uid}/receipts/r_${i}.jpg`)
      .save(Buffer.from([0x89, 0x50, i]), { contentType: 'image/jpeg' });
    await db.doc(`users/${uid}/receipts/r${i}`)
      .set({ id: `r${i}`, storeName: `상회${i}`, totalAmount: 1000 * i });
  }
}

/** 가입하신 분의 회원 문서. */
async function seedMemberDoc(uid, provider) {
  await db.doc(`users/${uid}`).set({
    id: uid, provider, email: `${uid}@x.com`, name: '사장님',
  });
}

async function countReceipts(uid) {
  return (await db.collection(`users/${uid}/receipts`).get()).size;
}
async function countPhotos(uid) {
  const [files] = await bucket.getFiles({ prefix: `users/${uid}/` });
  return files.length;
}
async function userExists(uid) {
  try { await auth.getUser(uid); return true; } catch { return false; }
}

async function wipe() {
  await fetch(
    `http://127.0.0.1:8080/emulator/v1/projects/${PROJECT}/databases/(default)/documents`,
    { method: 'DELETE' });
  await fetch(`http://${AUTH_HOST}/emulator/v1/projects/${PROJECT}/accounts`,
    { method: 'DELETE' });
  try {
    const [files] = await bucket.getFiles();
    await Promise.all(files.map((f) => f.delete().catch(() => {})));
  } catch { /* 비어 있으면 그만 */ }
}

beforeAll(async () => {
  app = admin.initializeApp(
    { projectId: PROJECT, storageBucket: `${PROJECT}.appspot.com` },
    'cleanup-test');
  auth = app.auth();
  db = app.firestore();
  bucket = app.storage().bucket();
  cleaner = createCleaner({ auth, db, bucket, logger: quiet });
});
afterAll(async () => { await app?.delete(); });
beforeEach(wipe);

/** 지금 만든 계정이 31일 됐다고 치고 돌린다. */
const in31Days = () => ({ now: Date.now() + 31 * DAY });
const in29Days = () => ({ now: Date.now() + 29 * DAY });

// ══════════════════════════════════════════════════════════════
// 지워야 하는 것 — 끝내 가입하지 않은 체험 계정
// ══════════════════════════════════════════════════════════════
describe('가입 안 한 게스트 — 30일 지나면 지운다', () => {
  test('🔴 31일 된 게스트는 계정·영수증·사진이 모두 지워진다', async () => {
    const g = await newAnon();
    await seed(g, 3);
    expect(await countReceipts(g)).toBe(3);
    expect(await countPhotos(g)).toBe(3);

    const out = await cleaner.run(in31Days());

    expect(out.deleted).toBe(1);
    expect(out.deletedUids).toContain(g);
    expect(await countReceipts(g)).toBe(0);
    expect(await countPhotos(g)).toBe(0);
    expect(await userExists(g)).toBe(false);
  });

  test('🔴 29일 된 게스트는 그대로 둔다', async () => {
    const g = await newAnon();
    await seed(g, 3);

    const out = await cleaner.run(in29Days());

    expect(out.deleted).toBe(0);
    expect(out.skipped[SKIP.TOO_YOUNG]).toBe(1);
    expect(await countReceipts(g)).toBe(3);
    expect(await countPhotos(g)).toBe(3);
    expect(await userExists(g)).toBe(true);
  });

  test('🔴 30일 경계 — 딱 30일이면 지운다, 하루 전이면 안 지운다', () => {
    const now = Date.now();
    const user = (ageDays) => ({
      uid: 'u1', providerData: [], customClaims: null,
      metadata: { creationTime: new Date(now - ageDays * DAY).toISOString() },
    });
    expect(classifyUser(user(30.1), now).ok).toBe(true);
    expect(classifyUser(user(29.9), now).ok).toBe(false);
    expect(classifyUser(user(29.9), now).reason).toBe(SKIP.TOO_YOUNG);
  });
});

// ══════════════════════════════════════════════════════════════
// 🔴🔴 가입한 분은 절대 안 지운다 — 앱에 있는 **모든** 가입 방법
//
//   카카오 · 구글 · 애플 · 이메일(웹앱 내 일반 가입)
//   네이버는 앱에 **없다**(버튼은 있으나 '준비 중' 안내만 띄운다).
// ══════════════════════════════════════════════════════════════
describe('가입한 분 — 31일이 지나도 절대 안 지운다', () => {
  test('🔴 카카오 회원은 31일 뒤에도 영수증 5장·사진 그대로', async () => {
    const k = await newKakao(1001);
    await seed(k, 5);
    await seedMemberDoc(k, 'kakao');

    const out = await cleaner.run(in31Days());

    expect(out.deleted).toBe(0);
    expect(await userExists(k)).toBe(true);
    expect(await countReceipts(k)).toBe(5);
    expect(await countPhotos(k)).toBe(5);
  });

  test('🔴🔴 클레임 저장이 실패한 카카오 회원도 안 지워진다', async () => {
    // 이것이 이 파일에서 **제일 위험한 경우**다. 제공업체도 없고, 메일도
    // 없고, 클레임도 없다 — Admin SDK 눈에 **익명 계정과 똑같이 보인다.**
    // uid 접두사만이 유일한 단서다.
    const k = await newKakao(1002, { withClaims: false });
    await seed(k, 5);

    const out = await cleaner.run(in31Days());

    expect(out.deleted).toBe(0);
    expect(out.skipped[SKIP.CUSTOM_TOKEN_UID]).toBe(1);
    expect(await userExists(k)).toBe(true);
    expect(await countReceipts(k)).toBe(5);
    expect(await countPhotos(k)).toBe(5);
  });

  test('🔴 구글 회원은 31일 뒤에도 그대로', async () => {
    const u = await newIdp('google.com', 'g@x.com', 'g1');
    await seed(u, 5);
    await seedMemberDoc(u, 'google.com');

    const out = await cleaner.run(in31Days());

    expect(out.deleted).toBe(0);
    expect(await userExists(u)).toBe(true);
    expect(await countReceipts(u)).toBe(5);
    expect(await countPhotos(u)).toBe(5);
  });

  test('🔴 애플 회원은 31일 뒤에도 그대로', async () => {
    const u = await newIdp('apple.com', 'a@x.com', 'a1');
    await seed(u, 5);
    await seedMemberDoc(u, 'apple.com');

    const out = await cleaner.run(in31Days());

    expect(out.deleted).toBe(0);
    expect(await userExists(u)).toBe(true);
    expect(await countReceipts(u)).toBe(5);
    expect(await countPhotos(u)).toBe(5);
  });

  test('🔴 이메일 가입 회원은 31일 뒤에도 그대로', async () => {
    const u = await newEmail('boss@x.com');
    await seed(u, 5);
    await seedMemberDoc(u, 'password');

    const out = await cleaner.run(in31Days());

    expect(out.deleted).toBe(0);
    expect(await userExists(u)).toBe(true);
    expect(await countReceipts(u)).toBe(5);
    expect(await countPhotos(u)).toBe(5);
  });

  test('🔴 네 가지 가입 방법을 한 판에 섞어도 하나도 안 지워진다', async () => {
    const members = [
      await newKakao(2001),
      await newKakao(2002, { withClaims: false }),
      await newIdp('google.com', 'g2@x.com', 'g2'),
      await newIdp('apple.com', 'a2@x.com', 'a2'),
      await newEmail('boss2@x.com'),
    ];
    for (const m of members) await seed(m, 5);

    const out = await cleaner.run(in31Days());

    expect(out.deleted).toBe(0);
    for (const m of members) {
      expect(await userExists(m), m).toBe(true);
      expect(await countReceipts(m), m).toBe(5);
      expect(await countPhotos(m), m).toBe(5);
    }
  });

  test('🔴 게스트가 구글로 **가입 전환**(link)한 경우도 안 지워진다', async () => {
    // uid 는 익명 때 그대로인데 제공업체만 붙는다. 영수증이 그 uid 아래
    // 있으므로, 여기서 지우면 가입하신 분의 장부가 사라진다.
    const g = await newAnon();
    await seed(g, 5);
    await auth.updateUser(g, { email: 'linked@x.com', password: 'pw123456' });

    const out = await cleaner.run(in31Days());

    expect(out.deleted).toBe(0);
    expect(await userExists(g)).toBe(true);
    expect(await countReceipts(g)).toBe(5);
  });
});

// ══════════════════════════════════════════════════════════════
// 옮겨진 게스트 — migrations 기록이 있으면 건드리지 않는다
// ══════════════════════════════════════════════════════════════
describe('한 번이라도 회원으로 옮겨진 게스트', () => {
  test('🔴 migrations 기록이 있으면 안 지운다', async () => {
    const g = await newAnon();
    await seed(g, 5);
    await db.collection('migrations').doc(g).set({
      targetUid: 'kakao:777', status: 'complete',
    });

    const out = await cleaner.run(in31Days());

    expect(out.deleted).toBe(0);
    expect(out.skipped[SKIP.MIGRATED]).toBe(1);
    expect(await userExists(g)).toBe(true);
    expect(await countReceipts(g)).toBe(5);
  });

  test('🔴 "기존 회원이라 안 옮김" 기록이어도 안 지운다', async () => {
    const g = await newAnon();
    await seed(g, 5);
    await db.collection('migrations').doc(g).set({
      status: 'skipped_existing_member', reason: 'existing_member',
    });

    const out = await cleaner.run(in31Days());

    expect(out.deleted).toBe(0);
    expect(out.skipped[SKIP.MIGRATED]).toBe(1);
  });
});

// ══════════════════════════════════════════════════════════════
// 남의 것을 건드리지 않는다
// ══════════════════════════════════════════════════════════════
describe('삭제 범위 — 남의 데이터는 한 톨도 안 건드린다', () => {
  test('🔴 게스트를 지워도 회원 영수증·사진은 그대로', async () => {
    const g = await newAnon();
    const k = await newKakao(3001);
    const google = await newIdp('google.com', 'g3@x.com', 'g3');
    await seed(g, 3);
    await seed(k, 5);
    await seed(google, 5);

    const out = await cleaner.run(in31Days());

    expect(out.deleted).toBe(1);
    expect(out.deletedUids).toEqual([g]);
    // 회원 둘은 그대로.
    expect(await countReceipts(k)).toBe(5);
    expect(await countPhotos(k)).toBe(5);
    expect(await countReceipts(google)).toBe(5);
    expect(await countPhotos(google)).toBe(5);
  });

  test('🔴 uid 가 앞부분만 같은 남의 사진을 지우지 않는다', async () => {
    // 🔴 접두사에 `/` 를 안 붙이면 `users/abc` 가 `users/abcdef/...` 까지
    //    긁어 간다. 실제로 일어나는 사고라 못으로 박는다.
    const g = await newAnon();
    const other = `${g}MORE`;
    await seed(g, 2);
    await seed(other, 4);
    await auth.createUser({ uid: other, email: 'other@x.com' });

    await cleaner.run(in31Days());

    expect(await countPhotos(g)).toBe(0);
    expect(await countPhotos(other)).toBe(4);
    expect(await countReceipts(other)).toBe(4);
  });

  test('🔴 게스트가 여럿이면 각자 것만 지운다', async () => {
    const a = await newAnon();
    const b = await newAnon();
    await seed(a, 2);
    await seed(b, 3);

    const out = await cleaner.run(in31Days());

    expect(out.deleted).toBe(2);
    expect(await countPhotos(a)).toBe(0);
    expect(await countPhotos(b)).toBe(0);
  });
});

// ══════════════════════════════════════════════════════════════
// 마지막 안전망 — 회원 문서가 있으면 지우지 않는다
// ══════════════════════════════════════════════════════════════
describe('안전망 — users/{uid} 가 회원 것으로 보이면 보존', () => {
  test('🔴 익명인데 회원 문서가 있으면 지우지 않는다', async () => {
    // Auth 판정이 어떤 이유로 틀렸을 때를 대비한 마지막 그물이다.
    const g = await newAnon();
    await seed(g, 5);
    await seedMemberDoc(g, 'kakao');

    const out = await cleaner.run(in31Days());

    expect(out.deleted).toBe(0);
    expect(out.skipped[SKIP.MEMBER_DOC]).toBe(1);
    expect(await countReceipts(g)).toBe(5);
  });

  test('🔴 provider 가 anonymous 인 문서는 게스트로 본다', async () => {
    const g = await newAnon();
    await db.doc(`users/${g}`).set({ id: g, provider: 'anonymous' });

    const out = await cleaner.run(in31Days());

    expect(out.deleted).toBe(1);
  });
});

// ══════════════════════════════════════════════════════════════
// 판정 규칙 자체 (Firestore 없이)
// ══════════════════════════════════════════════════════════════
describe('판정 규칙 — 모르면 보존한다', () => {
  const base = (over = {}) => ({
    uid: 'u1', providerData: [], customClaims: null,
    metadata: { creationTime: new Date(Date.now() - 40 * DAY).toISOString() },
    ...over,
  });

  test('🔴 만든 날을 못 읽으면 지우지 않는다', () => {
    const v = classifyUser(base({ metadata: {} }), Date.now());
    expect(v.ok).toBe(false);
    expect(v.reason).toBe(SKIP.NO_CREATED_AT);
  });

  test('🔴 메일·전화·이름·사진이 하나라도 있으면 지우지 않는다', () => {
    for (const f of [
      { email: 'a@x.com' }, { phoneNumber: '+8210' },
      { displayName: '사장님' }, { photoURL: 'http://x/y.png' },
    ]) {
      const v = classifyUser(base(f), Date.now());
      expect(v.ok, JSON.stringify(f)).toBe(false);
      expect(v.reason).toBe(SKIP.HAS_IDENTITY);
    }
  });

  test('🔴 클레임이 하나라도 있으면 지우지 않는다', () => {
    const v = classifyUser(base({ customClaims: { provider: 'kakao' } }), Date.now());
    expect(v.ok).toBe(false);
    expect(v.reason).toBe(SKIP.HAS_CLAIMS);
  });

  test('🔴 제공업체가 붙어 있으면 지우지 않는다', () => {
    const v = classifyUser(
      base({ providerData: [{ providerId: 'google.com' }] }), Date.now());
    expect(v.ok).toBe(false);
    expect(v.reason).toBe(SKIP.HAS_PROVIDER);
  });

  test('🔴 kakao: 로 시작하는 uid 는 절대 지우지 않는다', () => {
    const v = classifyUser(base({ uid: 'kakao:5' }), Date.now());
    expect(v.ok).toBe(false);
    expect(v.reason).toBe(SKIP.CUSTOM_TOKEN_UID);
  });
});

// ══════════════════════════════════════════════════════════════
// 로그 — 몇 개 지웠고, 몇 개를 왜 건너뛰었나
// ══════════════════════════════════════════════════════════════
describe('로그', () => {
  test('🔴 삭제 수와 건너뛴 이유별 수를 남긴다', async () => {
    const g = await newAnon();          // 지워짐
    const young = await newAnon();      // 29일 → 아님... (아래 now 로 31일)
    await newKakao(4001);               // 카카오
    await newEmail('log@x.com');        // 이메일
    const migrated = await newAnon();   // 옮겨짐
    await db.collection('migrations').doc(migrated).set({ status: 'complete' });

    const lines = [];
    const spy = createCleaner({
      auth, db, bucket,
      logger: { info: (m, o) => lines.push([m, o]), warn() {}, error() {} },
    });
    const out = await spy.run(in31Days());

    expect(out.deleted).toBe(2);                       // g, young
    expect(out.skipped[SKIP.CUSTOM_TOKEN_UID]).toBe(1);
    expect(out.skipped[SKIP.HAS_PROVIDER]).toBe(1);
    expect(out.skipped[SKIP.MIGRATED]).toBe(1);
    expect(out.skippedTotal).toBe(3);
    expect(out.scanned).toBe(5);
    expect(out.failed).toBe(0);
    expect([g, young].every((u) => out.deletedUids.includes(u))).toBe(true);

    // 요약 한 줄이 실제로 찍혔다.
    const [msg, obj] = lines.at(-1);
    expect(msg).toContain('cleanupGuestData');
    expect(obj.deleted).toBe(2);
    expect(obj.skipped[SKIP.MIGRATED]).toBe(1);
  });

  test('🔴 dryRun 은 세기만 하고 지우지 않는다', async () => {
    const g = await newAnon();
    await seed(g, 3);

    const out = await cleaner.run({ ...in31Days(), dryRun: true });

    expect(out.deleted).toBe(1);
    expect(out.dryRun).toBe(true);
    expect(await userExists(g)).toBe(true);
    expect(await countReceipts(g)).toBe(3);
  });
});

// ══════════════════════════════════════════════════════════════
// 소스 계약 — 기존 함수를 건드리지 않았다
// ══════════════════════════════════════════════════════════════
describe('기존 함수 불변 (#194 재발 방지)', () => {
  test('🔴 기존 함수 네 개가 그대로 있다', () => {
    const src = read('functions/index.js');
    for (const f of [
      'exports.updateFlowerPrices =',
      'exports.updateFlowerPricesNow =',
      'exports.kakaoCustomToken =',
      'exports.migrateGuestData =',
      'exports.cleanupGuestData =',
    ]) {
      expect(src, `${f} 가 사라졌다`).toContain(f);
    }
  });

  test('🔴 하루 한 번 돈다', () => {
    const src = read('functions/index.js');
    const part = src.slice(src.indexOf('exports.cleanupGuestData ='));
    expect(part).toContain("schedule: '0 4 * * *'");
    expect(part).toContain("timeZone: 'Asia/Seoul'");
  });

  test('🔴 보관 기간이 앱과 같은 값이다 (30일)', () => {
    expect(KEEP_DAYS).toBe(30);
    const dart = read('lib/services/guest_service.dart');
    expect(dart).toContain('static const int keepDays = 30;');
  });

  test('🔴 커스텀 토큰 접두사 목록이 kakaoUid() 와 짝이 맞는다', () => {
    // 🔴 새 SNS 를 커스텀 토큰으로 붙이면 이 목록에도 더해야 한다.
    //    안 그러면 그 회원이 30일 뒤 조용히 지워진다.
    const src = read('functions/index.js');
    expect(src).toContain('const kakaoUid = (id) => `kakao:${id}`;');
    const cleanup = read('functions/cleanup_guest_data.js');
    expect(cleanup).toContain("CUSTOM_TOKEN_UID_PREFIXES = ['kakao:']");
  });

  test('🔴 Storage 접두사에 / 를 붙인다 (남의 폴더 보호)', () => {
    const src = read('functions/cleanup_guest_data.js');
    expect(src).toContain('const prefix = `users/${uid}/`;');
  });
});
