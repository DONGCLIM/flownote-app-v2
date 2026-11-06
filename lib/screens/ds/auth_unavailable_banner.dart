import 'package:flutter/material.dart';

import '../../design/fn_tokens.dart';
import '../../services/firebase_status.dart';

/// 로그인 서버(Firebase)가 붙지 않았을 때 로그인 화면 상단에 띄우는 경고.
///
/// **왜 필요한가**
/// `Firebase.initializeApp()` 이 실패하면 로그인 화면은 **완전히 정상처럼**
/// 그려지지만 어떤 버튼을 눌러도 로그인이 성립하지 않는다. 사용자에게는
/// "그냥 로그인이 안 된다" 로만 보이고, 진짜 사유는 릴리즈 빌드에서 어디에도
/// 남지 않는다. → 사유를 화면에 그대로 노출하고, 버튼도 비활성화한다.
///
/// 서버가 정상이면 아무것도 그리지 않는다(`SizedBox.shrink`).
class AuthUnavailableBanner extends StatelessWidget {
  const AuthUnavailableBanner({super.key});

  /// 로그인/가입 버튼을 눌러도 소용없는 상태인지.
  static bool get blocked => FirebaseStatus.attempted && !FirebaseStatus.ready;

  @override
  Widget build(BuildContext context) {
    if (!blocked) return const SizedBox.shrink();

    final detail = FirebaseStatus.errorDetail;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FnColors.statusNegativeBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: FnColors.statusNegative.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 18, color: FnColors.statusNegative),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  '로그인 서버에 연결되지 않았어요',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: FnColors.statusNegative,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '앱을 완전히 종료한 뒤 다시 실행해 주세요.\n계속 같은 화면이면 아래 사유를 그대로 알려주시면 바로 고쳐드립니다.',
            style: TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 12,
              height: 1.5,
              color: FnColors.labelNeutral,
            ),
          ),
          if (detail != null && detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                '[${FirebaseStatus.errorStage}]\n$detail',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.45,
                  color: FnColors.labelNormal,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
