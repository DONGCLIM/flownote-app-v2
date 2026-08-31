import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../design/fn_tokens.dart';
import '../../design/fn_card.dart';
import '../../design/fn_controls_ds.dart';
import '../../design/fn_feedback.dart';
import '../../design/fn_sheet.dart';
import '../../services/gallery_intake.dart';
import '../../services/subscription_service.dart';
import '../ds/scan_camera_ds_screen.dart';
import '../ds/scan_processing_ds_screen.dart';
import '../ds/scan_review_ds_screen.dart';
import '../paywall_screen.dart';
import 'scan_draft.dart';

/// 스캔 파이프라인 진입점.
///
///   촬영/선택 → ScanProcessingDsScreen → ScanReviewDsScreen → ScanDoneDsScreen
///
/// 각 화면이 서로를 모르게 하고, 이 함수 하나가 전체 흐름을 조립한다.
/// 4개 화면 모두 시안(`AppH7 scan-camera / scan-processing / scan-review /
/// scan-done`)을 1:1로 포팅한 DS 화면이다.
class ScanFlow {
  ScanFlow._();

  /// 촬영 방식 선택 시트(시안 `CaptureSheet`)를 띄우고 전체 플로우를 실행한다.
  ///
  /// 시안의 `CaptureSheet` 는 **단일 촬영 / 연속 촬영 두 개뿐**이다.
  /// '갤러리에서 선택' 은 시트에 넣지 않고, 화면의 별도 버튼에서
  /// [startFromGallery] 로 바로 앨범을 여는 것이 원래 동작이다.
  ///
  /// [forcedDate] 가 있으면 인식 결과의 날짜를 그 날짜로 고정한다.
  /// (캘린더에서 특정 날짜에 영수증을 추가할 때 사용)
  static Future<void> start(BuildContext context, {DateTime? forcedDate}) async {
    if (!await _ensureQuota(context)) return;
    if (!context.mounted) return;

    final sub = SubscriptionService.instance;
    final mode = await _showCaptureSheet(context, sub.burstLimit);
    if (mode == null || !context.mounted) return;

    if (!await _ensureCamera(context)) return;
    if (!context.mounted) return;

    final r = await Navigator.push<List<XFile>>(
      context,
      MaterialPageRoute(
        builder: (_) => ScanCameraDsScreen(
          mode: mode == _ScanMode.burst ? 'multi' : 'single',
          maxShots: sub.burstLimit,
          // 캘린더에서 특정 날짜로 추가하는 경우 시안처럼 대상 날짜를 배지로 알려준다.
          badgeLabel: forcedDate == null
              ? null
              : '${forcedDate.month}월 ${forcedDate.day}일에 추가',
        ),
      ),
    );
    final files = r ?? const <XFile>[];
    if (files.isEmpty || !context.mounted) return;

    await _runTrimmed(context, files, forcedDate: forcedDate);
  }

  /// '갤러리에서 선택' — 시트 없이 곧바로 앨범을 연다.
  static Future<void> startFromGallery(BuildContext context,
      {DateTime? forcedDate}) async {
    if (!await _ensureQuota(context)) return;

    // 🔴 웹에서는 `image_picker` 를 **거치지 않는다.**
    //
    // `image_picker_for_web` 은 사진을 고른 직후 이렇게 한다.
    //
    // ```dart
    // return XFile(
    //   web.URL.createObjectURL(file),   // ⚠️ blob URL 만 만들고
    //   name: file.name,                 //    File 객체는 버린다
    // );
    // ...
    // return _getSelectedXFiles(input).whenComplete(() {
    //   input.remove();                  // ⚠️ <input> 도 DOM 에서 제거
    // });
    // ```
    //
    // 그래서 우리 손에 남는 것은 `blob:` URL 문자열 하나뿐이다. 그 URL 은
    // 원본 `File` 과 `<input>` 이 모두 사라진 뒤 브라우저가 임의의 시점에
    // 정리해버릴 수 있고, 그러면 읽기가 실패한다. **언제 정리되는지는
    // 브라우저가 정한다** — 메모리 상황과 사진 크기에 따라 달라진다.
    // 이것이 "됐다가 안 됐다가" 의 마지막 조각이었다. 이미 무효가 된 URL 은
    // 재시도를 몇 번 넣어도 계속 무효라서 재시도로는 해결되지 않았다.
    //
    // `GalleryIntake.pickAndPrepare` 는 웹에서 `<input>` 을 직접 만들어
    // `File` 을 붙잡고 `FileReader` 로 읽는다. **blob URL 을 아예 만들지
    // 않는다.** 만들지 않으면 폐기될 일도 없다.
    // 네이티브에서는 그대로 `image_picker` 를 쓴다(파일 경로 기반이라 안전).
    final intake = await GalleryIntake.pickAndPrepare(multiple: true);
    if (intake == null || !context.mounted) return; // 취소

    if (intake.allFailed) {
      await showFnAlert(
        context,
        title: '사진을 열지 못했어요',
        message: '고르신 사진의 실제 파일을 두 번 시도해도 읽을 수 없었어요.\n\n'
            '클라우드(구글포토 등)에만 저장된 사진일 수 있어요. '
            '갤러리에서 사진을 한 번 열어 기기에 내려받은 뒤 다시 골라주세요.\n\n'
            '(조명이나 구도 문제가 아닙니다)',
        icon: Icons.broken_image_outlined,
        iconColor: FnColors.statusNegative,
        confirmLabel: '알겠어요',
      );
      return;
    }

    if (intake.usable.isEmpty) return;

    if (intake.hasFailures) {
      // 일부만 실패한 경우 — 되는 것은 그대로 진행하고 사실만 알려준다.
      showFnToast(
        context,
        '${intake.failedCount}장은 파일을 읽을 수 없어 건너뜁니다',
        type: FnToastType.warning,
        duration: const Duration(seconds: 4),
      );
    }

    await _runTrimmed(context, intake.usable, forcedDate: forcedDate);
  }

  /// 시안 `CaptureSheet` 1:1
  ///
  /// ```js
  /// BottomSheet { title: '촬영 방법을 선택하세요' }
  ///   column gap:10
  ///     Card bordered onClick('single')
  ///       div 16/700 mb3 '단일 촬영'   / div 14 alt '영수증 한 장만 찍어요'
  ///     Card bordered onClick('burst')
  ///       div 16/700 mb3 '연속 촬영'   / div 14 alt '최대 20장까지 이어서 찍어요'
  /// ```
  static Future<_ScanMode?> _showCaptureSheet(
      BuildContext context, int burstLimit) {
    return showFnDsBottomSheet<_ScanMode>(
      context,
      title: '촬영 방법을 선택하세요',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _captureCard(
            context,
            title: '단일 촬영',
            desc: '영수증 한 장만 찍어요',
            value: _ScanMode.single,
          ),
          const SizedBox(height: 10),
          _captureCard(
            context,
            title: '연속 촬영',
            desc: '최대 $burstLimit장까지 이어서 찍어요',
            value: _ScanMode.burst,
          ),
        ],
      ),
    );
  }

  static Widget _captureCard(
    BuildContext context, {
    required String title,
    required String desc,
    required _ScanMode value,
  }) {
    return FnCard(
      bordered: true,
      onTap: () => Navigator.pop(context, value),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: FnColors.labelNormal,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            desc,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              color: FnColors.labelAlternative,
            ),
          ),
        ],
      ),
    );
  }

  /// 스캔 한도 확인. 한도 초과면 PRO 안내를 띄우고 false.
  static Future<bool> _ensureQuota(BuildContext context) async {
    final sub = SubscriptionService.instance;
    if (sub.canScan) return true;

    final go = await showFnAlert(
      context,
      title: '이번 달 무료 스캔을 모두 썼어요',
      message: 'PRO로 바꾸면 스캔 횟수 제한 없이 쓸 수 있어요.',
      icon: Icons.lock_rounded,
      confirmLabel: 'PRO 보기',
      cancelLabel: '닫기',
    );
    if (go && context.mounted) {
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => const PaywallScreen()));
    }
    return false;
  }

  /// 플랜별 장수 제한을 적용한 뒤 처리 플로우를 태운다.
  static Future<void> _runTrimmed(
    BuildContext context,
    List<XFile> files, {
    DateTime? forcedDate,
  }) async {
    final sub = SubscriptionService.instance;
    final limit = sub.burstLimit;
    var trimmed = files;
    if (files.length > limit) {
      trimmed = files.take(limit).toList();
      showFnToast(
        context,
        '${sub.isPro ? "" : "무료 플랜은 "}한 번에 $limit장까지예요. 앞의 $limit장만 처리할게요.',
        type: FnToastType.warning,
        duration: const Duration(seconds: 3),
      );
    }
    await runWithFiles(context, trimmed, forcedDate: forcedDate);
  }

  /// 이미 확보한 이미지 목록으로 처리 → 검토 플로우를 태운다.
  /// (캘린더 화면에서 특정 날짜로 영수증 추가할 때도 재사용)
  static Future<void> runWithFiles(
    BuildContext context,
    List<XFile> files, {
    DateTime? forcedDate,
  }) async {
    if (files.isEmpty) return;

    final drafts = files.map((f) => ScanDraft(file: f)).toList();

    final processed = await Navigator.push<List<ScanDraft>>(
      context,
      MaterialPageRoute(
        builder: (_) => ScanProcessingDsScreen(drafts: drafts),
        fullscreenDialog: true,
      ),
    );
    if (processed == null || !context.mounted) return;

    final usable = processed.where((d) => !d.isFailed || d.hasItems).toList();
    if (usable.isEmpty) {
      // 🔴 실패 사유를 **그대로 보여준다.**
      //
      // 예전에는 원인이 무엇이든 "조명이 밝은 곳에서 다시 찍어주세요" 만
      // 띄웠다. 그래서 API 키가 빠진 빌드에서도, 인터넷이 끊겼을 때도,
      // 사진 용량이 넘쳤을 때도 전부 같은 말이 나왔다. 사장님은 사진을
      // 아무리 밝게 찍어도 안 되니 원인을 찾을 방법이 없었다.
      // 진단 정보를 버리는 UI 는 친절한 게 아니라 무책임한 것이다.
      final why = _failureReason(processed);
      final retry = await showFnAlert(
        context,
        title: why.title,
        message: why.message,
        icon: why.icon,
        iconColor: FnColors.statusNegative,
        confirmLabel: why.canRetry ? '다시 찍기' : '닫기',
        cancelLabel: why.canRetry ? '닫기' : null,
      );
      if (retry && why.canRetry && context.mounted) {
        await start(context, forcedDate: forcedDate);
      }
      return;
    }

    if (forcedDate != null) {
      for (final d in usable) {
        d.date = DateTime(forcedDate.year, forcedDate.month, forcedDate.day,
            d.date.hour, d.date.minute);
      }
    }

    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ScanReviewDsScreen(drafts: usable)),
    );
  }

  static Future<bool> _ensureCamera(BuildContext context) async {
    var status = await Permission.camera.status;
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      if (!context.mounted) return false;
      final go = await showFnAlert(
        context,
        title: '카메라 권한이 필요해요',
        message: '설정에서 카메라 접근을 허용해 주세요.',
        icon: Icons.camera_alt_rounded,
        iconColor: FnColors.statusCautionary,
        confirmLabel: '설정 열기',
        cancelLabel: '닫기',
      );
      if (go) await openAppSettings();
      return false;
    }

    status = await Permission.camera.request();
    if (status.isGranted) return true;

    if (context.mounted) {
      showFnToast(context, '카메라 권한이 거부되었어요', type: FnToastType.error);
    }
    return false;
  }
}

enum _ScanMode { single, burst }

/// 스캔 실패를 사장님이 **행동으로 옮길 수 있는** 안내로 바꾼 결과.
@immutable
class _Failure {
  const _Failure(this.title, this.message,
      {this.icon = Icons.error_outline_rounded, this.canRetry = true});
  final String title;
  final String message;
  final IconData icon;

  /// 다시 찍어서 해결될 문제인가. 키 누락·네트워크는 다시 찍어도 그대로다.
  final bool canRetry;
}

/// 실패 문구를 분류한 결과의 **제목만** 돌려준다 (테스트용).
///
/// 분류가 조용히 깨지면 사장님에게 엉뚱한 안내(특히 "조명이 어두워요")가
/// 나가는데, 그건 화면을 직접 보지 않으면 알 수 없다. 실제로 이 버그를
/// 세 번 놓쳤다. 그래서 분류 규칙을 테스트로 고정한다.
@visibleForTesting
String failureTitleForTest(List<String> errors) {
  final drafts = errors.map((e) {
    final d = ScanDraft(file: XFile('/dev/null'));
    d.status = ScanDraftStatus.failed;
    d.error = e;
    return d;
  }).toList();
  return _failureReason(drafts).title;
}

/// 실패한 초안들의 오류 문구를 보고 원인을 가른다.
///
/// 순서가 중요하다. **사장님이 손쓸 수 없는 것(설정·네트워크)을 먼저** 알려야
/// 한다. 사진 문제를 먼저 말하면 원인이 딴 곳인데 사진만 다시 찍게 된다.
_Failure _failureReason(List<ScanDraft> drafts) {
  final errs = drafts.map((d) => d.error ?? '').where((e) => e.isNotEmpty);
  final all = errs.join(' | ');
  bool has(String s) => all.contains(s);

  if (has('API 키가 설정되지')) {
    return const _Failure(
      'AI 설정이 안 되어 있어요',
      'Gemini API 키가 없어서 영수증을 읽을 수 없어요.\n'
          '프로필 › AI 설정 에서 키를 입력해 주세요.\n'
          '(사진 문제가 아니라서 다시 찍어도 같습니다)',
      icon: Icons.key_off_rounded,
      canRetry: false,
    );
  }
  // 🔴 파일을 못 읽은 경우를 **가장 먼저** 가른다.
  //
  // 이게 이번에 잡은 진짜 원인이다. 갤러리 사진은 `blob:` URL 로 넘어오는데,
  // 구글포토 클라우드 자리표시자·삭제된 파일·분리된 SD카드처럼 실제 바이트가
  // 없으면 읽기가 실패한다. 촬영은 방금 만든 메모리 blob 이라 이런 일이 없다.
  // → **촬영은 되는데 갤러리만 안 되는** 증상의 정체.
  //
  // 예전에는 이 문구가 아래 어느 분기에도 걸리지 않아서 맨 끝의
  // "조명이 밝은 곳에서 다시 찍어주세요" 로 나갔다. 파일이 비어 있는데
  // 조명 탓을 한 것이다. 사장님은 몇 번을 다시 찍어도 될 수가 없었다.
  if (has('파일 읽기 실패') || has('파일이 손상')) {
    return _Failure(
      '사진 파일을 열지 못했어요',
      '$all\n\n'
          '(조명이나 구도 문제가 아닙니다. 다시 찍어도 같은 사진이면 같은 결과예요)',
      icon: Icons.broken_image_outlined,
      canRetry: false,
    );
  }
  if (has('네트워크') || has('SocketException') || has('Failed host lookup')) {
    return const _Failure(
      '인터넷에 연결되지 않았어요',
      '영수증 인식은 인터넷이 필요해요.\n연결을 확인한 뒤 다시 시도해 주세요.',
      icon: Icons.wifi_off_rounded,
      canRetry: false,
    );
  }
  if (has('시간이 초과')) {
    return const _Failure(
      '응답이 너무 오래 걸려요',
      '통신이 불안정한 것 같아요. 잠시 뒤 다시 시도해 주세요.',
      icon: Icons.timer_off_rounded,
      canRetry: false,
    );
  }
  // 용량 초과. 갤러리 원본(4000px 이상)을 그대로 보내면 여기에 걸린다.
  if (has('payload size') || has('too large') || has('RESOURCE_EXHAUSTED')) {
    return const _Failure(
      '사진 용량이 너무 커요',
      '갤러리 원본 사진은 용량이 커서 전송이 안 될 수 있어요.\n'
          '다시 시도하면 앱이 자동으로 줄여서 보냅니다.',
      icon: Icons.photo_size_select_large_rounded,
    );
  }
  // 🔴 AI 가 생각에 출력 토큰을 다 써서 답을 못 쓴 경우.
  //
  // 지금 모델(gemini-3.5-flash-lite)은 thinking 모델이라 응답이
  // `MAX_TOKENS` 로 끊기는 일이 **간헐적으로** 생긴다. 같은 사진을 다시
  // 보내면 대부분 성공한다. 이걸 조명 탓으로 돌리면 사장님은 밝은 곳에서
  // 몇 번을 다시 찍어도 안 되는 이유를 알 수 없다.
  if (has('MAX_TOKENS') || has('중간에 끊')) {
    return const _Failure(
      '다시 한 번만 눌러주세요',
      'AI가 답을 쓰다가 중간에 멈췄어요.\n'
          '사진 문제가 아니라서 그대로 다시 시도하면 대부분 됩니다.',
      icon: Icons.refresh_rounded,
    );
  }
  // JSON 파싱 실패 — 사진이 아니라 응답 형식 문제다.
  if (has('응답을 생성하지 못') || has('응답이 비어')) {
    return const _Failure(
      'AI 응답을 받지 못했어요',
      '잠시 뒤 다시 시도해 주세요.\n계속 같으면 프로필 › AI 설정에서 모델을 바꿔보세요.',
      icon: Icons.smart_toy_outlined,
    );
  }
  if (has('API 오류') || has('quota') || has('429')) {
    return _Failure(
      'AI 서버가 요청을 거절했어요',
      '아래 내용을 확인해 주세요.\n\n$all',
      icon: Icons.cloud_off_rounded,
      canRetry: false,
    );
  }
  // 🔴 예상 못 한 오류는 **조명 탓으로 돌리지 않는다.**
  //
  // `처리 오류: ...` 같은 문구가 여기까지 오면 그건 코드가 모르는 오류다.
  // 그걸 "조명이 어두워요" 로 바꿔 보여주면 사장님은 잘못된 곳을 고치려
  // 애쓰게 되고, 우리는 원인을 영원히 알 수 없다.
  // 모르면 모른다고 하고, 원문을 보여준다.
  if (has('처리 오류')) {
    return _Failure(
      '예상치 못한 오류가 났어요',
      '$all\n\n이 내용을 그대로 알려주시면 원인을 찾을 수 있어요.',
      icon: Icons.bug_report_outlined,
    );
  }

  // 여기까지 안 걸렸으면 진짜로 사진에서 글자를 못 찾은 경우다.
  // 이때만 조명·구도 얘기를 한다.
  //
  // 단, 갤러리 사진은 조명을 다시 어떻게 할 수 없으니 함께 안내한다.
  return const _Failure(
    '영수증을 읽지 못했어요',
    '조명이 밝은 곳에서 영수증 전체가 화면에 들어오도록 다시 찍어주세요.\n\n'
        '갤러리에서 고른 사진이라면, 영수증이 화면을 꽉 채우도록 잘라서 '
        '다시 시도해 보세요.',
  );
}
