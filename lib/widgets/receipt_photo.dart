import 'dart:io' as io;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

/// 저장된 영수증 사진(`receipt.imagePath`)을 플랫폼·경로 종류에 상관없이
/// 안전하게 그려주는 위젯.
///
/// ## `imagePath` 에 들어올 수 있는 값이 세 가지다
///
/// | 값 | 언제 | 어떻게 그리나 |
/// |---|---|---|
/// | `https://firebasestorage…` | 웹에서 저장 (클라우드 업로드) | `Image.network` |
/// | `/data/user/0/…/receipts/…` | 앱에서 저장 (문서 폴더) | `Image.file` |
/// | `blob:https://…` | 웹에서 저장했는데 업로드 실패 | 같은 탭에서만 `Image.network` |
///
/// 🔴 세 번째가 문제였다.
///    `blob:` URL 은 **그 탭이 살아있는 동안만** 유효하다. 새로고침하면
///    죽는다. 그런데 화면 코드는 `path.startsWith('http')` 로만 갈라서
///    `blob:` 은 `Image.file(File('blob:https://...'))` 로 흘러갔고,
///    웹에서 `dart:io` 는 전부 `UnsupportedError` 를 던지는 스텁이라
///    통째로 실패했다.
///
///    지금은 저장 시점에 클라우드로 올리므로(`ReceiptImageStore.persist`)
///    보통은 첫 번째 경우다. 다만 업로드가 실패했거나 예전에 저장한
///    영수증은 여전히 `blob:` 일 수 있어서 이 위젯이 그 경우를 흡수한다.
///
/// ## 죽은 사진을 만나면 이유를 알려준다
///
/// 그냥 "이미지를 불러올 수 없어요" 만 띄우면 사장님이 뭘 해야 할지
/// 알 수 없다. 경로 종류에 따라 다른 안내를 보여준다.
class ReceiptPhoto extends StatelessWidget {
  const ReceiptPhoto(
    this.path, {
    super.key,
    this.fit = BoxFit.fitWidth,
    this.width,
    this.height,
    this.onDark = true,
  });

  /// `receipt.imagePath`
  final String path;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// 어두운 배경 위에 올라가는가 (상세 화면은 어두운 회색 배경이다)
  final bool onDark;

  /// 이 경로가 지금 그려질 수 있는 값인가.
  ///
  /// 화면에서 "사진 영역을 아예 보여주지 말지" 판단할 때 쓴다.
  static bool isViewable(String? p) {
    final s = p ?? '';
    if (s.isEmpty) return false;
    if (s.startsWith('http')) return true;
    // 웹에서 로컬 경로/죽은 blob URL 은 그릴 수 없다.
    if (kIsWeb) return s.startsWith('blob:');
    return true;
  }

  /// 클라우드에 올라가 있어서 어디서든 보이는 사진인가.
  static bool isPermanent(String? p) => (p ?? '').startsWith('http');

  @override
  Widget build(BuildContext context) {
    final err = _error();

    // ── 클라우드 사진 (웹·앱 공통, 가장 흔한 경우) ──────────────
    if (path.startsWith('http')) {
      return Image.network(
        path,
        fit: fit,
        width: width,
        height: height,
        errorBuilder: (_, __, ___) => err('사진을 불러오지 못했어요',
            '인터넷 연결을 확인해주세요', Icons.wifi_off_rounded),
        loadingBuilder: (_, child, ev) {
          if (ev == null) return child;
          return SizedBox(
            height: height ?? 160,
            child: const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
      );
    }

    // ── 브라우저 임시 사진 (같은 탭에서만 유효) ──────────────────
    if (kIsWeb) {
      if (path.startsWith('blob:')) {
        return Image.network(
          path,
          fit: fit,
          width: width,
          height: height,
          errorBuilder: (_, __, ___) => err(
            '사진이 저장되지 않았어요',
            '이 영수증을 저장할 때 사진 업로드가 실패했어요.\n수정 화면에서 사진을 다시 붙여주세요.',
            Icons.cloud_off_rounded,
          ),
        );
      }
      // 웹인데 기기 경로 → 앱에서 저장한 영수증을 웹에서 열었다.
      return err(
        '사진은 휴대폰 앱에만 있어요',
        '앱에서 저장한 사진은 그 기기에 있어요.\n앱에서 열면 보입니다.',
        Icons.phone_android_rounded,
      );
    }

    // ── 기기 사진 (앱) ─────────────────────────────────────────
    return Image.file(
      io.File(path),
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, __, ___) => err(
        '사진을 찾을 수 없어요',
        '기기에서 파일이 삭제된 것 같아요.',
        Icons.broken_image_outlined,
      ),
    );
  }

  Widget Function(String, String, IconData) _error() {
    return (title, body, icon) {
      final fg = onDark ? Colors.white : const Color(0xFF6B7280);
      final sub = onDark ? Colors.white54 : const Color(0xFF9CA3AF);
      return SizedBox(
        height: height ?? 160,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 30, color: sub),
                const SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: fg.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 11,
                    height: 1.4,
                    color: sub,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    };
  }
}
