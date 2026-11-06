# 🍎 아이폰(iOS) 출시 준비 가이드 — FlowNote

> **먼저 꼭 알아두실 것**
>
> **아이폰 앱 파일(IPA)은 반드시 맥(Mac) 컴퓨터에서만 만들 수 있습니다.**
> 애플이 만든 규칙이라서, 윈도우 PC나 지금 제가 작업하는 리눅스 서버에서는
> 아무리 코드가 완벽해도 아이폰용 앱 파일을 뽑아낼 수 없습니다.
>
> - 안드로이드 APK → ✅ 제가 여기서 만들어 드릴 수 있습니다 (지금까지 계속 해온 것)
> - 아이폰 IPA → ❌ 맥이 필요합니다
>
> **제가 지금까지 한 일**: 아이폰용 코드와 설정을 전부 다 넣어놨습니다.
> **남은 일**: 맥에서 버튼 몇 번 누르는 것 (아래 STEP 5)

---

## 무엇이 이미 준비되어 있나요?

| 항목 | 상태 |
|---|---|
| 애플 로그인 코드 (`signInWithApple`) | ✅ 완료 |
| 로그인 화면 애플 버튼 (아이폰에서만 자동 표시) | ✅ 완료 |
| 탈퇴 시 애플 재인증 | ✅ 완료 |
| 앱 고유 ID(번들 ID)를 `com.flownote.app` 로 통일 | ✅ 완료 |
| 애플 로그인 권한 파일 (`Runner.entitlements`) | ✅ 완료 |
| iOS 라이브러리 설정 파일 (`Podfile`) | ✅ 완료 |
| 최소 지원 버전 iOS 15 로 설정 | ✅ 완료 |
| 카메라/사진 권한 안내 문구 (한글) | ✅ 완료 |
| **`GoogleService-Info.plist`** (파이어베이스 iOS 설정 파일) | ❌ **사장님이 받아오셔야 합니다 (STEP 2)** |
| **구글 로그인용 URL Scheme 값** | ❌ **위 파일을 받으면 자동 해결 (STEP 3)** |
| **애플 개발자 프로그램 가입** | ❌ **사장님이 결제하셔야 합니다 (STEP 1)** |

---

## STEP 1. 애플 개발자 프로그램 가입 (연 129,000원)

아이폰 앱은 **애플에 돈을 내야** 앱스토어에 올릴 수 있습니다. 안드로이드는
평생 1회 25달러인데, 애플은 **매년** 결제해야 합니다.

1. https://developer.apple.com/programs/ 접속
2. 오른쪽 위 **Enroll** (등록) 클릭
3. 애플 아이디로 로그인 → 개인(Individual) 또는 사업자(Organization) 선택
   - **사업자로 등록하려면** D-U-N-S 번호가 필요하고 2~3주 걸립니다
   - **개인으로 등록하면** 하루~이틀 안에 승인되고, 앱스토어에 사장님 실명이 표시됩니다
   - 👉 빠르게 시작하려면 **개인(Individual)** 을 추천합니다
4. 연 US$99 (약 129,000원) 결제
5. 승인 메일을 기다립니다

> ⚠️ 이 단계 없이는 아이폰에 앱을 설치하는 것 자체가 불가능합니다.
> (테스트용으로 7일짜리 임시 설치는 가능하지만 앱스토어 출시는 불가)

---

## STEP 2. 파이어베이스에 아이폰 앱 등록 → 설정 파일 받기

안드로이드 때와 똑같은 작업을 아이폰용으로 한 번 더 하는 것입니다.

1. https://console.firebase.google.com 접속 → **flownote-404ef** 프로젝트 선택
2. 왼쪽 위 **⚙️ 톱니바퀴 → 프로젝트 설정**
3. 아래로 스크롤 → **내 앱** 영역 → **[앱 추가]** 버튼 클릭
4. 아이콘 중 **iOS** (사과 모양) 선택
5. 입력창에 아래 값을 **그대로** 넣으세요:

   | 칸 이름 | 넣을 값 |
   |---|---|
   | Apple 번들 ID | `com.flownote.app` |
   | 앱 닉네임 (선택) | `FlowNote iOS` |
   | App Store ID (선택) | 비워두세요 |

   > 🔴 번들 ID는 **한 글자도 틀리면 안 됩니다.** 복사해서 붙여넣으세요.

6. **[앱 등록]** 클릭
7. 다음 화면에서 **`GoogleService-Info.plist` 다운로드** 버튼을 누릅니다
8. 그 아래 "3단계", "4단계" 안내는 **전부 무시하고 넘기세요**
   (Xcode 에서 뭘 하라는 내용인데, 제가 이미 코드로 다 처리해놨습니다)
9. 다운로드된 **`GoogleService-Info.plist` 파일을 저에게 주세요**

---

## STEP 3. 구글 로그인 URL Scheme 채우기 (제가 처리)

`ios/Runner/Info.plist` 파일에 지금 이렇게 임시값이 들어있습니다:

```xml
<string>REPLACE_WITH_REVERSED_CLIENT_ID</string>
```

STEP 2에서 받은 `GoogleService-Info.plist` 안에 `REVERSED_CLIENT_ID` 라는
항목이 있는데, 그 값(`com.googleusercontent.apps.250664220370-xxxxx` 형태)으로
바꿔야 아이폰에서 구글 로그인 창이 열립니다.

👉 **파일만 주시면 제가 바꿔드립니다.** 직접 하실 필요 없습니다.

> 참고: **애플 로그인은 이 값이 없어도 정상 작동합니다.** 구글 로그인만 영향받습니다.

---

## STEP 4. 애플 로그인 켜기 (2곳)

### 4-1. 애플 개발자 사이트에서 권한 켜기

1. https://developer.apple.com/account 접속 → 로그인
2. **Certificates, Identifiers & Profiles** 클릭
3. 왼쪽 메뉴 **Identifiers** → **➕** 버튼
4. **App IDs** 선택 → **Continue** → **App** 선택 → **Continue**
5. 입력:
   - Description: `FlowNote`
   - Bundle ID: **Explicit** 선택 후 `com.flownote.app` 입력
6. 아래 **Capabilities** 목록에서 **`Sign In with Apple`** 체크박스를 **켜세요** ✅
7. **Continue** → **Register**

### 4-2. 파이어베이스에서 애플 로그인 제공업체 켜기

1. 파이어베이스 콘솔 → **Authentication** → **Sign-in method** 탭
2. 목록에서 **Apple** 클릭
3. **사용 설정(Enable)** 토글을 켭니다
4. **저장**

> 💡 아래 "서비스 ID", "OAuth 코드 흐름" 같은 칸들은 **비워두세요.**
> 그건 웹사이트나 안드로이드에서 애플 로그인을 쓸 때만 필요합니다.
> 아이폰 앱에서만 쓰신다면 토글만 켜면 끝입니다.

---

## STEP 5. 맥에서 앱 만들기 (맥이 있는 분에게 맡기셔도 됩니다)

여기부터는 **맥 컴퓨터**가 필요합니다. 맥이 없으시면 아래 방법 중 하나:

- **방법 A**: 주변에 맥 쓰는 개발자에게 이 문서를 그대로 전달
- **방법 B**: Codemagic / Bitrise 같은 "클라우드 맥" 서비스 사용 (월 무료 한도 있음)
- **방법 C**: 맥미니 구매 (약 80만원, 계속 앱을 운영하실 거라면 결국 필요)

### 맥에서 실행할 명령어 (복사해서 터미널에 붙여넣기)

```bash
# 1) 개발 도구 설치 (한 번만)
#    - Xcode: 앱스토어에서 "Xcode" 검색 후 설치 (용량 큼, 시간 걸림)
#    - Flutter: https://docs.flutter.dev/get-started/install/macos

# 2) 이 프로젝트 내려받기
git clone https://github.com/DONGCLIM/flownote-app-v2.git
cd flownote-app-v2
git checkout genspark_ai_developer

# 3) GoogleService-Info.plist 를 ios/Runner/ 폴더에 넣기
#    (STEP 2에서 받은 파일)

# 4) 라이브러리 설치
flutter pub get
cd ios && pod install && cd ..

# 5) Xcode 로 열어서 팀(Team) 지정 — 이건 GUI 작업
open ios/Runner.xcworkspace
#    → 왼쪽에서 Runner 클릭 → Signing & Capabilities 탭
#    → Team 드롭다운에서 사장님 애플 개발자 계정 선택
#    → "Sign In with Apple" 항목이 목록에 보이는지 확인 (이미 설정돼 있어야 정상)

# 6) 앱 파일 만들기
flutter build ipa --release --dart-define-from-file=secrets/gemini.json
#    → build/ios/ipa/*.ipa 파일이 생깁니다
#    → 이걸 Transporter 앱으로 앱스토어에 업로드
```

---

## 자주 나는 오류

| 증상 | 원인 / 해결 |
|---|---|
| `pod install` 실패 | 맥 터미널에서 `sudo gem install cocoapods` 먼저 실행 |
| Xcode 에서 `No account for team` | Signing & Capabilities 에서 Team 을 선택하지 않았습니다 |
| `Sign In with Apple` 항목이 안 보임 | STEP 4-1 에서 Capability 를 안 켰거나, 번들 ID가 다릅니다 |
| 애플 로그인 눌렀는데 `audience` 오류 | 파이어베이스 Apple 제공업체를 안 켰습니다 (STEP 4-2) |
| 구글 로그인 창이 안 열림 | `Info.plist` 의 `REVERSED_CLIENT_ID` 를 안 바꿨습니다 (STEP 3) |
| 앱 심사 반려 `Guideline 4.8` | 소셜 로그인이 있는데 애플 로그인이 없을 때 나는 반려입니다. 지금은 코드가 다 들어있으니 STEP 4를 켜면 해결됩니다 |
| 애플 로그인 후 이름이 안 들어옴 | 애플은 **최초 1회만** 이름을 줍니다. 파이어베이스 콘솔에서 그 계정을 지우고 다시 로그인하면 이름을 다시 받습니다 |

---

## 정리 — 사장님이 하실 일 체크리스트

- [ ] **STEP 1** 애플 개발자 프로그램 가입 (연 129,000원)
- [ ] **STEP 2** 파이어베이스에 iOS 앱 등록 → `GoogleService-Info.plist` 받아서 저에게 전달
- [ ] **STEP 4-1** 애플 개발자 사이트에서 `Sign In with Apple` 켜기
- [ ] **STEP 4-2** 파이어베이스 Authentication 에서 Apple 토글 켜기
- [ ] **STEP 5** 맥 확보 (또는 맥 있는 분에게 위임)

### 안드로이드는 별도로 하나 남아있습니다

애플과 무관하게, **안드로이드 구글 로그인**도 아직 막혀 있습니다.
그건 `docs/GOOGLE_LOGIN_SETUP.md` 를 보시면 됩니다. (파이어베이스에
`com.flownote.app` 안드로이드 앱을 새로 등록 + SHA-1 지문 입력)

두 문서의 작업은 **서로 독립적**이므로 아무 순서로 하셔도 됩니다.
