# FlowNote 로그인·회원가입 켜는 방법 (Firebase 설정 가이드)

> **코드는 전부 준비되어 있습니다.** 아래 Firebase 콘솔 작업만 하시면 바로 동작합니다.
> 소요 시간: **약 15분**

---

## 준비물

| 항목 | 값 |
|---|---|
| Firebase 프로젝트 | `flownote-404ef` (이미 만들어져 있음) |
| 콘솔 주소 | https://console.firebase.google.com/project/flownote-404ef |
| 앱 패키지명 | `com.flownote.app` |
| **릴리즈 서명 SHA-1** | `79:6C:01:29:32:F0:AA:FB:3F:1D:CE:29:56:73:94:77:98:8E:F6:12` |
| **릴리즈 서명 SHA-256** | `A1:F1:99:F3:35:08:89:B2:74:A1:70:A7:03:45:3B:70:84:27:3B:03:91:FF:2E:48:5C:2B:8C:C8:E8:10:98:DC` |

> SHA 값은 이미 사용 중인 릴리즈 키(`android/release-key.jks`)에서 뽑은 값입니다.
> 콘솔에 붙여넣을 때는 콜론(`:`)이 있어도 되고 없어도 됩니다.

---

## STEP 1 — 이메일/비밀번호 로그인 켜기 (2분)

1. 콘솔 → 좌측 메뉴 **빌드 › Authentication** 클릭
2. 처음이면 **[시작하기]** 버튼 클릭
3. **Sign-in method** 탭 → 공급업체 목록에서 **이메일/비밀번호** 클릭
4. 첫 번째 토글 **사용 설정** → **ON**
   - 두 번째 "이메일 링크(비밀번호 없는 로그인)"는 **OFF** 로 두세요
5. **[저장]**

✅ 여기까지만 하면 **이메일 회원가입 / 로그인 / 비밀번호 찾기** 가 즉시 동작합니다.

---

## STEP 2 — 구글 로그인 켜기 (5분)

### 2-1. 공급업체 추가
1. 같은 **Sign-in method** 탭 → **[새 공급업체 추가]** → **Google**
2. **사용 설정** → **ON**
3. **프로젝트 지원 이메일** 을 본인 이메일로 선택 (필수)
4. **[저장]**

### 2-2. 🔴 앱 등록 + SHA-1 지문 등록 (이걸 안 하면 구글 로그인이 실패합니다)

> **🔴 정정 (2026-08-18):** 콘솔에는 옛날 앱 `com.florascan.scan` **하나만** 등록되어 있고
> 현재 패키지 `com.flownote.app` 은 **등록조차 되어 있지 않습니다.**
> (빌드를 통과시키려고 `google-services.json` 에 해당 항목을 수동으로 추가해 둔 상태입니다.
>  두 항목의 `mobilesdk_app_id` 가 동일한 것이 그 증거입니다.)
> 따라서 아래 3번은 **"찾기"가 아니라 "새로 등록"** 입니다.
> 자세한 클릭 순서는 **`docs/GOOGLE_LOGIN_SETUP.md`** 를 보세요.

1. 콘솔 좌측 상단 **⚙️ 톱니바퀴 › 프로젝트 설정**
2. **일반** 탭 아래로 스크롤 → **내 앱** 섹션
3. **[앱 추가] › Android** 를 눌러 새로 등록합니다
   - Android 패키지 이름: `com.flownote.app`
   - 디버그 서명 인증서 SHA-1 칸에 아래 SHA-1 을 입력 (선택 표시지만 필수입니다)
   - ⚠️ `com.florascan.scan` 옛날 앱은 **삭제하지 말고 그대로 두세요.**
   - 혹시 `com.flownote.app` 카드가 이미 있다면 새로 만들지 말고
     그 카드의 **[디지털 지문 추가]** 로 SHA-1 만 넣으세요.
4. 카드 안 **[디지털 지문 추가]** (SHA 인증서 지문 추가) 클릭
5. 아래 값을 각각 등록합니다 (두 번 클릭해서 두 개 다 넣으세요)
   ```
   796c012932f0aafb3f1dce2956739477988ef612
   ```
   ```
   a1f199f3350889b274a170a703453b7084273b0391ff2e485c2b8cc8e81098dc
   ```

### 2-3. 🔴 google-services.json 다시 받기
앱을 등록하고 지문을 넣으면 **OAuth 클라이언트가 새로 생성**됩니다.
현재 프로젝트에 들어있는 `google-services.json` 은 `"oauth_client": []` 가 **비어 있어서**
이 파일을 교체하지 않으면 구글 로그인이 계속 실패합니다.

1. 같은 `com.flownote.app` 앱 카드에서 **[google-services.json 다운로드]** 클릭
2. 받은 파일을 아래 경로에 **덮어쓰기**
   ```
   android/app/google-services.json
   ```
3. 파일을 열어서 `oauth_client` 안에 내용이 **채워졌는지** 확인하세요.
   ```json
   "oauth_client": [
     {
       "client_id": "250664220370-xxxxx.apps.googleusercontent.com",
       "client_type": 1,
       "android_info": {
         "package_name": "com.flownote.app",
         "certificate_hash": "796c012932f0aafb3f1dce2956739477988ef612"
       }
     },
     ...
   ]
   ```
   `[]` 로 비어 있으면 지문 등록이 안 된 것이니 STEP 2-2 를 다시 확인하세요.

### 2-4. APK 다시 빌드
```bash
./tool/build_apk.sh --fat
```

---

## STEP 3 — 데이터베이스 만들기 (3분)

1. 콘솔 → **빌드 › Firestore Database**
2. **[데이터베이스 만들기]**
3. 위치: **`asia-northeast3 (Seoul)`** 선택 ← 한국 사용자에게 가장 빠릅니다
4. 규칙 모드: **프로덕션 모드에서 시작** 선택
   (테스트 모드는 30일 뒤 모든 접근이 막혀서 앱이 갑자기 멈춥니다)
5. **[만들기]**

---

## STEP 4 — 보안 규칙 적용 (3분)

DB 를 프로덕션 모드로 만들면 **기본 규칙이 모든 접근을 차단**합니다.
프로젝트에 준비된 규칙 파일로 교체해야 합니다.

### Firestore 규칙
1. **Firestore Database › 규칙** 탭
2. 편집창 내용을 전부 지우고, 프로젝트의 **`firestore.rules`** 파일 내용을 그대로 붙여넣기
3. **[게시]**

### Storage 규칙
1. 콘솔 → **빌드 › Storage** (아직 없으면 **[시작하기]** → 위치는 Firestore 와 동일하게)
2. **규칙** 탭 → 프로젝트의 **`storage.rules`** 내용 붙여넣기 → **[게시]**

> ⚠️ **왜 이게 중요한가**
> 기존 앱은 영수증 OCR 학습 데이터를 `training_data` 컬렉션에 **인증 없이** 쓰고 있었습니다.
> 프로덕션 규칙만 켜고 위 파일을 안 넣으면 **스캔할 때 학습 데이터 저장이 조용히 실패**합니다.
> `firestore.rules` 에는 `training_data` 를 로그인 사용자에게 허용하는 예외가 들어 있습니다.

---

## STEP 5 — 동작 확인 체크리스트

APK 를 설치하고 순서대로 확인하세요.

| # | 확인 항목 | 기대 결과 |
|---|---|---|
| 1 | 앱 실행 | 로그인/가입 화면 (게스트 버튼 없음) |
| 2 | 이메일·비밀번호 입력 후 **가입하기** | 회원가입 화면으로 이동 (약관 4개 노출) |
| 3 | 약관 옆 **보기** 탭 | 이용약관 전문이 열림 |
| 4 | 필수 2개만 체크하고 **가입하기** | 사업자등록증 촬영 온보딩으로 이동 |
| 5 | 콘솔 **Authentication › Users** | 방금 만든 이메일이 목록에 보임 |
| 6 | 콘솔 **Firestore › users** | `{uid}` 문서에 `consents`, `email`, `name` 저장됨 |
| 7 | 앱 종료 후 재실행 | 로그인 유지 (다시 로그인 안 물어봄) |
| 8 | **프로필 › 로그아웃** → **구글** 버튼 | 구글 계정 선택창이 뜸 |
| 9 | 구글 계정 선택 | 홈 화면으로 진입, 프로필에 구글 이름 표시 |
| 10 | 영수증 1건 저장 후 콘솔 확인 | `users/{uid}/receipts/{id}` 문서 생성 |
| 11 | **프로필 › 회원 탈퇴** → `탈퇴합니다` 입력 | 계정·Firestore 문서 모두 삭제, 로그인 화면 복귀 |

### 문제가 생기면

| 증상 | 원인 | 해결 |
|---|---|---|
| `이 로그인 방식이 아직 활성화되지 않았습니다` | STEP 1/2 공급업체 OFF | 콘솔에서 사용 설정 ON |
| `구글 로그인을 사용할 수 없습니다` | 앱 미등록 / SHA-1 미등록 / json 미교체 | STEP 2-2, 2-3 재확인 (`docs/GOOGLE_LOGIN_SETUP.md` 참고) |
| 가입은 되는데 Firestore 에 문서가 없음 | DB 미생성 또는 규칙 차단 | STEP 3, 4 확인 |
| 스캔은 되는데 학습 데이터가 안 쌓임 | `training_data` 규칙 누락 | `firestore.rules` 그대로 게시 |
| `네트워크 연결을 확인해 주세요` | 실제 네트워크 문제 | 와이파이/데이터 확인 |

---

## STEP 6 — 출시 전 반드시 채울 항목 🔴

`lib/services/legal_documents.dart` 상단의 placeholder 를 실제 정보로 바꿔야
법적으로 유효한 약관이 됩니다.

```dart
static const companyName    = 'FlowNote';                 // ← 사업자 상호
static const representative = '(대표자명 입력 필요)';       // ← 대표자 성명
static const address        = '(사업장 주소 입력 필요)';     // ← 사업장 주소
static const contactEmail   = 'support@flownote.kr';      // ← 실제 문의 메일
static const privacyOfficer = '(개인정보 보호책임자명 입력 필요)';
```

바꾼 뒤에는 `termsVersion` / `privacyVersion` 을 `1.1` 로 올려주세요.
버전이 올라가면 기존 사용자에게 재동의를 받아야 하므로,
**출시 전에 한 번에 정리하는 것이 가장 좋습니다.**

---

## 부록 A — 만들어진 데이터 구조

```
Firestore
└── users/{uid}                        ← 회원 개인정보
    ├── id, email, name, photoUrl, provider
    ├── scanCount, isUnlimited, createdAt
    ├── businessName, businessNumber, ownerName, businessAddress, phoneNumber
    ├── consents: { terms:{agreed,version,at}, privacy:{...}, marketing:{...} }
    ├── receipts/{receiptId}           ← 영수증 클라우드 백업 (기기 변경 복원용)
    └── consent_log/{logId}            ← 동의 이력 감사 로그 (수정 불가)

└── training_data/{docId}              ← OCR 학습 데이터 (기존 기능 유지)

Storage
├── training_data/...                  ← 학습용 영수증 원본 이미지
└── users/{uid}/...                    ← 사용자별 이미지
```

**로컬(Hive)** 의 `receipts` 박스는 그대로 유지됩니다.
꽃시장은 인터넷이 불안정하므로 **로컬이 항상 진실의 원천**이고,
Firestore 는 기기를 바꿀 때 복원하기 위한 백업입니다.
저장 버튼을 눌렀을 때 네트워크를 기다리지 않습니다.

## 부록 B — 이번에 바뀐 것

### 보안 문제 해결
| 이전 | 이후 |
|---|---|
| 🔴 비밀번호를 기기에 **평문 저장** (`user_password_$email`) | Firebase 서버 단방향 암호화, 기기에 저장 안 함 |
| 🔴 `Future.delayed` 로 로그인 흉내낸 **가짜 인증** | 실제 Firebase Auth 서버 인증 |
| 🔴 계정이 기기에만 있어서 폰 바꾸면 **소멸** | 서버 계정 + Firestore 백업으로 복원 가능 |
| 🔴 로그인/가입 화면이 **연결 안 돼 있었음** | 스플래시 → 가입/로그인 → 온보딩 전체 연결 |
| 🔴 약관 체크박스에 **내용이 없었음** | 이용약관·개인정보 처리방침 전문 + 동의 이력 저장 |

### 게스트 모드 제거
요청대로 게스트/데모 데이터를 전부 없앴습니다.
- `AuthProvider.signInAsGuest()` **삭제**
- 스플래시의 `둘러보기 (온보딩 건너뛰기)` 버튼 **삭제**
- 게스트용 샘플 사업자 정보(`꽃향기 플라워샵` 등) 자동 입력 **삭제**
- 기존 기기에 남아 있던 게스트 캐시는 앱 실행 시 **자동 폐기**
- 구버전이 남긴 평문 비밀번호 키도 로그아웃 시 **자동 삭제**

### 추가된 기능
- 구글 로그인
- 비밀번호 재설정 메일
- 회원 탈퇴 (재인증 → 클라우드 데이터 삭제 → 계정 삭제)
- 마케팅 수신 동의 ON/OFF (프로필에서 언제든 철회)
- 영수증 클라우드 백업 / 기기 변경 복원
