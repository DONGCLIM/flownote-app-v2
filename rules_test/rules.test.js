// 🔴 보안 규칙 테스트 — 규칙을 바꾸면 **배포 전에 반드시** 돌린다. (#194)
//
// 왜 생겼나: #194 에서 게스트를 막으려고 `isSignedIn()` → `isMember()` 로
// 바꾼 두 줄이 **회원이 영수증을 찍을 때마다 지나는 길**이었다. 규칙은
// 컴파일에 성공했고, 그래서 그대로 배포했다. 컴파일 성공은 "문법이 맞다"
// 일 뿐 "회원이 저장할 수 있다" 가 아니다. 그 확인을 여기서 한다.
//
// 세 가지 신분을 모두 본다. 구글만 보면 #194 를 못 잡는다 —
// 카카오는 커스텀 토큰이라 `sign_in_provider` 가 'custom' 이다.

import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';
import {
  doc, setDoc, getDoc, updateDoc, addDoc, collection,
} from 'firebase/firestore';
import { ref, uploadBytes, getBytes } from 'firebase/storage';
import { beforeAll, afterAll, beforeEach, describe, test } from 'vitest';

const here = dirname(fileURLToPath(import.meta.url));
const r = (p) => resolve(here, '..', p);

let env;

// ── 신분 ──────────────────────────────────────────────────────
//
// 🔴 `sign_in_provider` 를 실제 값으로 넣는다. 이게 이 테스트의 핵심이다.
const GOOGLE = { uid: 'u_google', provider: 'google.com',
  email: 'boss@gmail.com', email_verified: true };
const KAKAO = { uid: 'kakao:12345', provider: 'custom',
  email: 'boss@kakao.com', email_verified: false };
const ANON = { uid: 'u_anon', provider: 'anonymous' };
const OTHER = { uid: 'u_other', provider: 'google.com',
  email: 'other@gmail.com', email_verified: true };

/** 그 사람으로 로그인한 Firestore 손잡이. */
function db(who) {
  return env.authenticatedContext(who.uid, {
    firebase: { sign_in_provider: who.provider, identities: {} },
    ...(who.email ? { email: who.email } : {}),
    ...(who.email_verified !== undefined
      ? { email_verified: who.email_verified } : {}),
  }).firestore();
}

function st(who) {
  return env.authenticatedContext(who.uid, {
    firebase: { sign_in_provider: who.provider, identities: {} },
    ...(who.email ? { email: who.email } : {}),
    ...(who.email_verified !== undefined
      ? { email_verified: who.email_verified } : {}),
  }).storage();
}

const PNG = new Uint8Array([0x89, 0x50, 0x4e, 0x47]);
const META = { contentType: 'image/jpeg' };

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: 'flownote-rules-test',
    firestore: {
      rules: readFileSync(r('firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8080,
    },
    storage: {
      rules: readFileSync(r('storage.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 9199,
    },
  });
});

afterAll(async () => { await env?.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
});

// ══════════════════════════════════════════════════════════════
// 회원이 평소에 하는 일 — 하나라도 막히면 배포하면 안 된다
// ══════════════════════════════════════════════════════════════
for (const who of [
  { name: '구글 회원', id: GOOGLE },
  { name: '카카오 회원 (커스텀 토큰)', id: KAKAO },
]) {
  describe(`${who.name} — 평소 쓰는 길이 열려 있다`, () => {
    test('🔴 영수증 저장 (users/{uid}/receipts)', async () => {
      const d = db(who.id);
      await assertSucceeds(setDoc(
        doc(d, `users/${who.id.uid}/receipts/r1`),
        { storeName: '화람원예', totalAmount: 160000 },
      ));
    });

    test('🔴 영수증 사진 업로드 (users/{uid}/receipts/*.jpg)', async () => {
      // 웹에서 blob URL 이 죽기 전에 여기로 올린다. 막히면 사진이 사라진다.
      const s = st(who.id);
      await assertSucceeds(
        uploadBytes(ref(s, `users/${who.id.uid}/receipts/r_1.jpg`), PNG, META));
    });

    test('🔴 학습 데이터 저장 (training_data) — 모든 스캔이 지난다', async () => {
      // 🔴 #194 에서 막혔던 곳 ①
      const d = db(who.id);
      await assertSucceeds(setDoc(
        doc(d, 'training_data/doc1'),
        { doc_id: 'doc1', user_id: who.id.uid, is_corrected: false },
      ));
      await assertSucceeds(updateDoc(
        doc(d, 'training_data/doc1'), { is_corrected: true }));
    });

    test('🔴 학습 이미지 업로드 (receipts/**) — 모든 스캔이 지난다', async () => {
      // 🔴 #194 에서 막혔던 곳 ②
      const s = st(who.id);
      await assertSucceeds(
        uploadBytes(ref(s, 'receipts/doc1.jpg'), PNG, META));
    });

    test('🔴 문의 작성', async () => {
      const d = db(who.id);
      await assertSucceeds(addDoc(collection(d, 'inquiries'), {
        uid: who.id.uid,
        status: '접수',
        answer: '',
        answeredAt: null,
        content: '건의드립니다',
        category: '기능',
        attachmentUrls: [],
      }));
    });

    test('🔴 사입 리스트 저장 (purchase_lists)', async () => {
      const d = db(who.id);
      await assertSucceeds(setDoc(
        doc(d, `users/${who.id.uid}/purchase_lists/p1`),
        { id: 'p1', purpose: '주말 부케', items: [] },
      ));
    });

    test('🔴 자기 영수증 읽기', async () => {
      await env.withSecurityRulesDisabled(async (c) => {
        await setDoc(doc(c.firestore(),
          `users/${who.id.uid}/receipts/r1`), { storeName: '화람원예' });
      });
      await assertSucceeds(
        getDoc(doc(db(who.id), `users/${who.id.uid}/receipts/r1`)));
    });

    test('🔴 시세 읽기 (market)', async () => {
      await env.withSecurityRulesDisabled(async (c) => {
        await setDoc(doc(c.firestore(), 'market/yangjae_latest'), { n: 1 });
      });
      await assertSucceeds(
        getDoc(doc(db(who.id), 'market/yangjae_latest')));
    });
  });
}

// ══════════════════════════════════════════════════════════════
// 남의 데이터는 못 본다
// ══════════════════════════════════════════════════════════════
describe('회원 A 는 회원 B 의 것을 못 본다', () => {
  beforeEach(async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      const f = c.firestore();
      await setDoc(doc(f, `users/${OTHER.uid}/receipts/r1`),
        { storeName: '남의 영수증', totalAmount: 99000 });
      await setDoc(doc(f, `users/${OTHER.uid}/purchase_lists/p1`),
        { id: 'p1', purpose: '남의 리스트' });
      await setDoc(doc(f, `users/${OTHER.uid}`), { name: '남' });
      await setDoc(doc(f, 'inquiries/q1'),
        { uid: OTHER.uid, status: '접수', answer: '', content: '남의 문의' });
    });
  });

  test('🔴 남의 영수증 읽기 거부', async () => {
    await assertFails(
      getDoc(doc(db(GOOGLE), `users/${OTHER.uid}/receipts/r1`)));
  });

  test('🔴 남의 영수증 쓰기 거부', async () => {
    await assertFails(setDoc(
      doc(db(GOOGLE), `users/${OTHER.uid}/receipts/r2`), { x: 1 }));
  });

  test('🔴 남의 사입 리스트 읽기·쓰기 거부', async () => {
    await assertFails(
      getDoc(doc(db(KAKAO), `users/${OTHER.uid}/purchase_lists/p1`)));
    await assertFails(setDoc(
      doc(db(KAKAO), `users/${OTHER.uid}/purchase_lists/p2`), { id: 'p2' }));
  });

  test('🔴 남의 회원 문서 읽기·쓰기 거부', async () => {
    await assertFails(getDoc(doc(db(GOOGLE), `users/${OTHER.uid}`)));
    await assertFails(setDoc(doc(db(GOOGLE), `users/${OTHER.uid}`),
      { name: '바꿔치기' }));
  });

  test('🔴 남의 문의 읽기 거부', async () => {
    await assertFails(getDoc(doc(db(GOOGLE), 'inquiries/q1')));
  });

  test('🔴 남의 이름으로 문의 쓰기 거부', async () => {
    await assertFails(addDoc(collection(db(GOOGLE), 'inquiries'), {
      uid: OTHER.uid, status: '접수', answer: '', answeredAt: null,
      content: '사칭', category: '기능', attachmentUrls: [],
    }));
  });

  test('🔴 남의 폴더 사진 업로드·읽기 거부', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await uploadBytes(
        ref(c.storage(), `users/${OTHER.uid}/receipts/r1.jpg`), PNG, META);
    });
    await assertFails(uploadBytes(
      ref(st(GOOGLE), `users/${OTHER.uid}/receipts/x.jpg`), PNG, META));
    await assertFails(
      getBytes(ref(st(GOOGLE), `users/${OTHER.uid}/receipts/r1.jpg`)));
  });

  test('🔴 학습 데이터는 아무도 못 읽는다 (관리자만 콘솔에서)', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await setDoc(doc(c.firestore(), 'training_data/doc1'), { x: 1 });
    });
    await assertFails(getDoc(doc(db(GOOGLE), 'training_data/doc1')));
  });

  test('🔴 시세는 아무도 못 쓴다 (서버만)', async () => {
    await assertFails(setDoc(
      doc(db(GOOGLE), 'market/yangjae_latest'), { n: 2 }));
  });
});

// ══════════════════════════════════════════════════════════════
// 게스트(익명)
//
// 🔴 지금 라이브 규칙(520662e)에는 익명 전용 조항이 **없다.** 그래서
//    익명도 `users/{자기 uid}` 아래를 쓸 수 있다 — 그게 체험에 필요한
//    동작이라 맞다. 공용 경로(training_data, receipts/**, inquiries)는
//    **앱에서** 안 가도록 막는다(게스트는 학습 활용 동의가 없다).
//    그 약속을 `app_guards.test.js` 가 소스로 확인한다.
//
//    재설계안(`docs/게스트_규칙_재설계안.md`)을 올리는 날,
//    아래 '재설계안' 묶음의 skip 을 풀면 그대로 검증된다.
// ══════════════════════════════════════════════════════════════
describe('게스트(익명) — 지금 라이브 규칙 기준', () => {
  test('🔴 자기 users/{uid} 아래는 쓸 수 있다 (체험 영수증)', async () => {
    await assertSucceeds(setDoc(
      doc(db(ANON), `users/${ANON.uid}/receipts/r1`),
      { storeName: '체험', totalAmount: 1000 },
    ));
  });

  test('🔴 자기 폴더에 사진을 올릴 수 있다 (웹 blob 대비)', async () => {
    await assertSucceeds(uploadBytes(
      ref(st(ANON), `users/${ANON.uid}/receipts/r_1.jpg`), PNG, META));
  });

  test('🔴 남의 uid 아래는 못 쓴다', async () => {
    await assertFails(setDoc(
      doc(db(ANON), `users/${OTHER.uid}/receipts/r1`), { x: 1 }));
    await assertFails(uploadBytes(
      ref(st(ANON), `users/${OTHER.uid}/receipts/x.jpg`), PNG, META));
  });

  test('🔴 규칙에 아직 익명 조항이 없다 (앱에서 막는다)', async () => {
    // 이 테스트는 **지금 상태를 적어 두는 것**이다. 실패가 아니라 기록이다.
    // 규칙에서도 막고 싶으면 재설계안을 올린 뒤 아래 skip 을 푼다.
    await assertSucceeds(setDoc(
      doc(db(ANON), 'training_data/doc1'), { doc_id: 'doc1' }));
  });
});

// 🔴 재설계안을 올리기 전까지는 건너뛴다. 올리는 날 `describe.skip` 의
//    skip 만 지우면 바로 검증된다. (`docs/게스트_규칙_재설계안.md`)
describe.skip('재설계안 — users/{uid}/usage 를 더한 뒤', () => {
  test('게스트는 scans 를 1씩만 올린다', async () => {
    const d = db(ANON);
    const p = `users/${ANON.uid}/usage/counters`;
    await assertSucceeds(setDoc(doc(d, p), { scans: 1 }));
    await assertSucceeds(updateDoc(doc(d, p), { scans: 2 }));
    // 건너뛰기·되돌리기는 거부
    await assertFails(updateDoc(doc(d, p), { scans: 5 }));
    await assertFails(updateDoc(doc(d, p), { scans: 1 }));
  });

  test('게스트는 5 를 넘길 수 없다', async () => {
    await env.withSecurityRulesDisabled(async (c) => {
      await setDoc(doc(c.firestore(),
        `users/${ANON.uid}/usage/counters`), { scans: 5 });
    });
    await assertFails(updateDoc(
      doc(db(ANON), `users/${ANON.uid}/usage/counters`), { scans: 6 }));
  });

  test('🔴 회원은 usage 에 제한이 없다', async () => {
    for (const who of [GOOGLE, KAKAO]) {
      const p = `users/${who.uid}/usage/counters`;
      await assertSucceeds(setDoc(doc(db(who), p), { scans: 0 }));
      await assertSucceeds(updateDoc(doc(db(who), p), { scans: 99 }));
    }
  });

  test('🔴 회원이 쓰던 길은 그대로 열려 있다', async () => {
    for (const who of [GOOGLE, KAKAO]) {
      await assertSucceeds(setDoc(
        doc(db(who), 'training_data/d1'), { doc_id: 'd1' }));
      await assertSucceeds(uploadBytes(
        ref(st(who), 'receipts/d1.jpg'), PNG, META));
    }
  });
});
