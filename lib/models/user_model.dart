import '../services/subscription_service.dart';

/// 약관 동의 이력 한 건
class ConsentRecord {
  final bool agreed;
  final String version;
  final DateTime at;

  const ConsentRecord({
    required this.agreed,
    required this.version,
    required this.at,
  });

  Map<String, dynamic> toMap() => {
        'agreed': agreed,
        'version': version,
        'at': at.toIso8601String(),
      };

  factory ConsentRecord.fromMap(Map<String, dynamic> map) => ConsentRecord(
        agreed: map['agreed'] as bool? ?? false,
        version: map['version'] as String? ?? '',
        at: DateTime.tryParse(map['at'] as String? ?? '') ?? DateTime.now(),
      );

  ConsentRecord copyWith({bool? agreed, String? version, DateTime? at}) =>
      ConsentRecord(
        agreed: agreed ?? this.agreed,
        version: version ?? this.version,
        at: at ?? this.at,
      );
}

/// 약관 동의 묶음 (필수 2건 + 선택 1건)
class UserConsents {
  final ConsentRecord? terms;      // [필수] 서비스 이용약관
  final ConsentRecord? privacy;    // [필수] 개인정보 처리방침
  final ConsentRecord? marketing;  // [선택] 마케팅 정보 수신

  const UserConsents({this.terms, this.privacy, this.marketing});

  bool get hasRequired =>
      (terms?.agreed ?? false) && (privacy?.agreed ?? false);

  bool get marketingAgreed => marketing?.agreed ?? false;

  Map<String, dynamic> toMap() => {
        if (terms != null) 'terms': terms!.toMap(),
        if (privacy != null) 'privacy': privacy!.toMap(),
        if (marketing != null) 'marketing': marketing!.toMap(),
      };

  factory UserConsents.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const UserConsents();
    ConsentRecord? pick(String key) {
      final v = map[key];
      if (v is Map) return ConsentRecord.fromMap(Map<String, dynamic>.from(v));
      return null;
    }

    return UserConsents(
      terms: pick('terms'),
      privacy: pick('privacy'),
      marketing: pick('marketing'),
    );
  }

  UserConsents copyWith({
    ConsentRecord? terms,
    ConsentRecord? privacy,
    ConsentRecord? marketing,
  }) =>
      UserConsents(
        terms: terms ?? this.terms,
        privacy: privacy ?? this.privacy,
        marketing: marketing ?? this.marketing,
      );
}

class UserModel {
  final String id;
  final String email;
  final String name;
  int scanCount;
  bool isUnlimited;
  final DateTime createdAt;

  // 계정 정보
  String photoUrl;   // 구글 프로필 이미지 URL (없으면 빈 문자열)
  String provider;   // 'password' | 'google.com' | 'apple.com' | 'kakao'

  // 약관 동의 이력
  UserConsents consents;

  // 사업자 정보
  String businessName;      // 상호명
  String businessNumber;    // 사업자 번호
  String ownerName;         // 대표 이름
  String businessAddress;   // 사업장 주소
  String phoneNumber;       // 전화번호 (선택)

  static const int freeScanLimit = 30;

  UserModel({
    required this.id,
    required this.email,
    required this.name,
    this.scanCount = 0,
    this.isUnlimited = false,
    required this.createdAt,
    this.photoUrl = '',
    this.provider = 'password',
    this.consents = const UserConsents(),
    this.businessName = '',
    this.businessNumber = '',
    this.ownerName = '',
    this.businessAddress = '',
    this.phoneNumber = '',
  });

  /// 실제로 잠금이 풀려 있는지.
  ///
  /// 🔴 이 앱에는 스캔 잠금이 **두 군데**에 있다.
  ///    ① [SubscriptionService] (요금제 · 새 화면들이 쓴다)
  ///    ② 여기 [isUnlimited] (초기에 만든 구형 잠금 · 프로필 화면이 쓴다)
  ///
  ///    ②는 서버(Firestore)에 저장되는 값이라 그대로 두고,
  ///    판단만 ①의 전체 잠금 해제 스위치와 함께 본다.
  ///    그래야 "모든 기능 사용 가능" 이 한 곳만 풀리고 다른 곳은
  ///    여전히 "남은 횟수 0회" 를 보여주는 엇박이 생기지 않는다.
  bool get effectiveUnlimited =>
      SubscriptionService.unlockEverything || isUnlimited;

  int get remainingScans => effectiveUnlimited
      ? 999
      : (freeScanLimit - scanCount).clamp(0, freeScanLimit);

  bool get canScan => effectiveUnlimited || scanCount < freeScanLimit;

  double get scanUsagePercent => effectiveUnlimited
      ? 1.0
      : (scanCount / freeScanLimit).clamp(0.0, 1.0);

  bool get hasBusinessInfo =>
      businessName.isNotEmpty || businessNumber.isNotEmpty;

  bool get isGoogleAccount => provider == 'google.com';

  /// 카카오로 들어온 계정.
  ///
  /// 🔴 카카오는 Firebase 기본 제공자가 아니라 커스텀 토큰으로 로그인한다.
  ///    그래서 `providerData` 가 **빈 배열**이고, 거기서 제공자를 유추하면
  ///    엉뚱하게 'password' 로 잡힌다. uid 접두사로 판별해야 한다.
  bool get isKakaoAccount => provider == 'kakao' || id.startsWith('kakao:');

  /// 화면에 보여줄 계정 식별자.
  ///
  /// 카카오는 이메일 제공 동의를 받지 않으면 이메일이 아예 없다.
  /// 그때 빈칸을 두면 "내 계정이 이상한가?" 하고 불안해지므로
  /// 무엇으로 로그인했는지를 대신 보여준다.
  String get accountLabel {
    if (email.isNotEmpty) return email;
    if (isKakaoAccount) return '카카오 계정';
    if (isGoogleAccount) return '구글 계정';
    if (provider == 'apple.com') return 'Apple 계정';
    return '-';
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'email': email,
        'name': name,
        'scanCount': scanCount,
        'isUnlimited': isUnlimited,
        'createdAt': createdAt.toIso8601String(),
        'photoUrl': photoUrl,
        'provider': provider,
        'consents': consents.toMap(),
        'businessName': businessName,
        'businessNumber': businessNumber,
        'ownerName': ownerName,
        'businessAddress': businessAddress,
        'phoneNumber': phoneNumber,
      };

  factory UserModel.fromMap(Map<String, dynamic> map) => UserModel(
        id: map['id'] as String,
        email: map['email'] as String? ?? '',
        name: map['name'] as String? ?? '',
        scanCount: map['scanCount'] as int? ?? 0,
        isUnlimited: map['isUnlimited'] as bool? ?? false,
        createdAt:
            DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
        photoUrl: map['photoUrl'] as String? ?? '',
        provider: map['provider'] as String? ?? 'password',
        consents: UserConsents.fromMap(
          map['consents'] is Map
              ? Map<String, dynamic>.from(map['consents'] as Map)
              : null,
        ),
        businessName: map['businessName'] as String? ?? '',
        businessNumber: map['businessNumber'] as String? ?? '',
        ownerName: map['ownerName'] as String? ?? '',
        businessAddress: map['businessAddress'] as String? ?? '',
        phoneNumber: map['phoneNumber'] as String? ?? '',
      );

  UserModel copyWith({
    String? id,
    String? email,
    String? name,
    int? scanCount,
    bool? isUnlimited,
    DateTime? createdAt,
    String? photoUrl,
    String? provider,
    UserConsents? consents,
    String? businessName,
    String? businessNumber,
    String? ownerName,
    String? businessAddress,
    String? phoneNumber,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      scanCount: scanCount ?? this.scanCount,
      isUnlimited: isUnlimited ?? this.isUnlimited,
      createdAt: createdAt ?? this.createdAt,
      photoUrl: photoUrl ?? this.photoUrl,
      provider: provider ?? this.provider,
      consents: consents ?? this.consents,
      businessName: businessName ?? this.businessName,
      businessNumber: businessNumber ?? this.businessNumber,
      ownerName: ownerName ?? this.ownerName,
      businessAddress: businessAddress ?? this.businessAddress,
      phoneNumber: phoneNumber ?? this.phoneNumber,
    );
  }
}
