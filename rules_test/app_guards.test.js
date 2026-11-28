// 🔴 #194 재발 방지 — 규칙 파일이 함부로 바뀌지 않았는지 소스로 확인한다.
//
// 에뮬레이터가 없어도 도는 가벼운 확인이다. 규칙 테스트(`rules.test.js`)가
// "되는가" 를 본다면, 여기서는 "위험한 모양으로 바뀌지 않았는가" 를 본다.

import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, test, expect } from 'vitest';

const here = dirname(fileURLToPath(import.meta.url));
const path = (p) => resolve(here, '..', p);
const read = (p) => readFileSync(path(p), 'utf8');

describe('라이브 규칙을 함부로 바꾸지 않았다 (#194 재발 방지)', () => {
  // 🔴 #194 에서 이 두 줄을 `isMember()` 로 바꿨다가 **회원** 영수증 저장이
  //    막혔다. 게스트 전용 길인 줄 알았는데, 회원이 영수증을 찍을 때마다
  //    지나는 길이었다. 다시 바뀌면 여기서 걸린다.
  test('🔴 training_data 는 로그인 사용자면 쓸 수 있다', () => {
    const rules = read('firestore.rules');
    const part = rules.slice(rules.indexOf('match /training_data/{docId}'));
    expect(part).toContain('allow create: if isSignedIn();');
    expect(part).toContain('allow update: if isSignedIn();');
  });

  test('🔴 receipts/** 학습 이미지 업로드는 로그인 사용자면 된다', () => {
    const rules = read('storage.rules');
    const part = rules.slice(rules.indexOf('match /receipts/{allPaths=**}'));
    expect(part.slice(0, 220)).toContain('allow write: if isSignedIn()');
  });

  test('🔴 문의 작성은 로그인 사용자면 된다', () => {
    const rules = read('firestore.rules');
    const part = rules.slice(rules.indexOf('match /inquiries/{docId}'));
    expect(part).toContain('allow create: if isSignedIn()');
  });

  test('🔴 터질 수 있는 방식으로 익명을 가리지 않는다', () => {
    // `request.auth.token.firebase.sign_in_provider` 를 **직접** 꺼내면
    // 키가 없을 때 식이 오류가 되고, **오류 난 규칙은 거부**로 끝난다.
    // 카카오는 커스텀 토큰이라 토큰 모양이 달라 실제로 이 사고가 났다.
    // 꺼내야 한다면 `.get('firebase', {}).get('sign_in_provider', '')`.
    for (const f of ['firestore.rules', 'storage.rules']) {
      expect(read(f), `${f} 에 터질 수 있는 꺼내기가 있다`)
        .not.toContain('request.auth.token.firebase.sign_in_provider');
    }
  });
});

describe('재설계안 문서 (#194 — 아직 규칙에 반영 안 함)', () => {
  const doc = () => read('docs/게스트_규칙_재설계안.md');

  test('🔴 문서가 남아 있다', () => {
    expect(existsSync(path('docs/게스트_규칙_재설계안.md'))).toBe(true);
  });

  test('🔴 기존 allow 줄을 건드리지 않는다는 원칙이 적혀 있다', () => {
    expect(doc()).toMatch(/기존 `allow` 줄을 고치지 않는다/);
  });

  test('🔴 게스트 영수증을 학습에 쓰지 않기로 한 것이 적혀 있다', () => {
    // 막는 이유가 보안이 아니라 **동의**다. 게스트는 학습 활용에
    // 동의한 적이 없다. 그래서 규칙이 아니라 앱에서 건너뛴다.
    const d = doc();
    expect(d).toMatch(/학습 활용 동의/);
    expect(d).toMatch(/training_data/);
  });

  test('🔴 익명 판별을 .get() 으로 한다고 적혀 있다', () => {
    expect(doc()).toContain("get('sign_in_provider', '')");
  });
});

describe('작업 규칙에 배포 절차가 적혀 있다 (#194)', () => {
  test('🔴 규칙 배포 전 규칙 테스트가 필수라고 적혀 있다', () => {
    const todo = read('docs/TODO_기능연결.md');
    expect(todo).toMatch(/규칙 배포 전/);
    expect(todo).toMatch(/rules_test/);
  });
});
