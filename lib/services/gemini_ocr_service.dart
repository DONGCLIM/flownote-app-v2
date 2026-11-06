import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';
import 'api_key_service.dart';
import 'image_shrink.dart';

/// `extractAnswerText` 결과.
class GeminiAnswerText {
  const GeminiAnswerText(this.text, this.thoughtParts);

  /// 생각을 걸러낸 실제 답변 본문.
  final String text;

  /// 걸러낸 생각 조각 개수 (진단용).
  final int thoughtParts;
}

/// Gemini 응답의 `parts` 에서 **실제 답변만** 뽑아낸다.
///
/// 🔴 이 함수가 왜 따로 있는가 — 간헐적 버그를 테스트로 못 박기 위해서다.
///
/// 지금 쓰는 `gemini-3.5-flash-lite` 는 thinking 모델이다
/// (models 조회 결과 `"thinking": true`). 이 모델은 답을 내기 전에 속으로
/// 생각을 하고, **그 생각이 길어지면** 응답의 `parts` 가 두 개로 온다.
///
///   parts[0] = { "text": "...생각...", "thought": true }
///   parts[1] = { "text": "{\"store_name\": ...}" }   ← 진짜 답
///
/// 예전 코드는 `parts[0]` 만 읽었다. 즉 생각 문장을 JSON 이라고 믿고
/// 파싱하다 실패했다. 생각 길이는 매번 달라지므로(같은 사진 10회 반복 시
/// candidatesTokenCount 448×8 / 269×2, thoughtsTokenCount 최대 1042 측정)
/// 실패가 **간헐적**이었다. 사진이나 형식 문제가 아니었다.
///
/// 간헐적 버그는 실행을 반복해도 재현이 보장되지 않는다. 그래서 파싱을
/// 순수 함수로 떼어내 `test/gemini_parts_test.dart` 에서 2-parts 응답을
/// 직접 만들어 검증한다. 이렇게 해두면 이 버그가 다시 들어올 수 없다.
GeminiAnswerText extractAnswerText(List? parts) {
  final buf = StringBuffer();
  var thoughtParts = 0;
  for (final p in parts ?? const []) {
    if (p is! Map) continue;
    if (p['thought'] == true) {
      thoughtParts++;
      continue; // 생각은 답이 아니다
    }
    final t = p['text'];
    if (t is String && t.isNotEmpty) buf.write(t);
  }
  return GeminiAnswerText(buf.toString().trim(), thoughtParts);
}

/// Gemini Vision API 기반 OCR 서비스
/// - 이미지 최적 리사이즈 (1200px, 선명도 유지)
/// - Few-shot 예시 포함 전문 프롬프트
/// - temperature 0.1, maxOutputTokens 1200
/// - 5단계 JSON 파싱 전략
class GeminiOcrService {
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// 런타임 API 키 해결: 저장된 키 우선, 없으면 앱 내장 기본 키
  /// (`ApiKeyService.defaultApiKey` 는 `--dart-define=GEMINI_API_KEY=` 로 덮어쓸 수 있다)
  Future<String?> _resolveApiKey() => ApiKeyService.resolveGeminiKey();

  // 이미지 최대 크기: 1200px (선명도와 속도 균형)
  static const int _maxImageDimension = 1200;

  Future<GeminiOcrResult> recognizeReceipt({required XFile xFile}) async {
    try {
      // 0) API 키 + 모델 + 프롬프트 확인
      final apiKey = await _resolveApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        return GeminiOcrResult.error(
          'API 키가 설정되지 않았습니다.\n프로필 › AI 설정 에서 Gemini API 키를 입력해주세요.',
        );
      }

      // 저장된 모델 (없으면 기본값)
      final model = await ApiKeyService.getModel();
      // 저장된 프롬프트 (없으면 내장 프롬프트)
      final customPrompt = await ApiKeyService.getCustomPrompt();
      final prompt = customPrompt ?? _buildPrompt();

      // 1) 이미지 읽기
      //
      // 🔴 `readAsBytes()` 가 웹에서 **멈출 수 있다.**
      //
      // 웹에서 `XFile.path` 는 `blob:` URL 이고, 읽기는 그 URL 을 fetch 하는
      // 동작이다. 갤러리에서 고른 사진이 아래 상황이면 이 fetch 가 실패하거나
      // 영원히 안 끝난다.
      //   · 구글포토가 클라우드에만 있는 사진을 자리표시자로 넘긴 경우
      //   · 파일을 고른 뒤 다른 앱이 그 파일을 지우거나 옮긴 경우
      //   · SD카드/USB 저장소가 중간에 분리된 경우
      // 촬영 경로는 방금 만든 메모리 blob 이라 이런 일이 없다.
      // **갤러리에서만 실패한다는 신고의 정체가 이것이다.**
      //
      // 상한을 두지 않으면 인식 화면이 영원히 도는 상태가 된다.
      //
      // 🔴 실패하면 **한 번 더 시도한다.**
      //
      // 웹 `XFile` 은 읽을 때마다 `blob:` URL 을 다시 XHR 한다
      // (`cross_file` 의 `_blob` getter 가 결과를 캐시하지 않는다).
      // 그래서 첫 읽기가 성공했어도 두 번째 읽기는 실패할 수 있다.
      // 실측으로 확인한 것:
      //
      // ```
      // 1차 성공 후 URL 폐기 → 2차 읽기: ❌ XHR error (revoked?)
      // ```
      //
      // 갤러리 경로는 이제 `GalleryIntake` 가 바이트를 메모리에 실어
      // 넘기므로 여기서 디스크를 타지 않는다. 하지만 촬영 경로와
      // 다른 진입점도 있으니 여기서도 한 번은 더 시도해 준다.
      // 한 번의 일시적 실패로 사장님에게 실패 화면을 띄우지 않는다.
      Uint8List? readBytes;
      Object? lastError;
      for (var attempt = 1; attempt <= 2; attempt++) {
        try {
          final b = await xFile.readAsBytes().timeout(
                const Duration(seconds: 20),
              );
          if (b.isNotEmpty) {
            readBytes = b;
            break;
          }
          lastError = '0바이트';
          debugPrint('[ocr] "${xFile.name}" 시도 $attempt — 0바이트');
        } catch (e) {
          lastError = e;
          debugPrint('[ocr] "${xFile.name}" 시도 $attempt — 읽기 실패: $e');
        }
        if (attempt == 1) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
        }
      }

      // 두 번 시도해도 못 읽었다. 예전에는 이 자리에서 아무 로그도 남기지
      // 않고 '이미지를 읽을 수 없습니다.' 만 돌려줬다. 그 문구는
      // `scan_flow` 의 어느 분기에도 걸리지 않아서 결국 "조명이 밝은 곳에서
      // 다시 찍어주세요" 로 바뀌어 나갔다. 사장님이 사진을 아무리 밝게
      // 다시 찍어도 될 수가 없었다.
      if (readBytes == null) {
        debugPrint('[ocr] ❌ "${xFile.name}" 두 번 시도 후 포기: $lastError');
        return GeminiOcrResult.error(
          '사진 파일을 열지 못했습니다. (파일 읽기 실패)\n'
          '클라우드에만 저장된 사진일 수 있어요. '
          '갤러리에서 사진을 열어 기기에 내려받은 뒤 다시 골라주세요.',
        );
      }
      final Uint8List rawBytes = readBytes;

      // 2) MIME 타입 감지
      final mimeType = _detectMimeType(rawBytes, xFile.name);

      // 🔴 진단 로그는 `kDebugMode` 로 감싸지 않는다.
      //
      // 배포된 웹에서 문제가 생겼을 때 사장님 브라우저 콘솔에 아무것도
      // 남지 않으면 원인을 찾을 방법이 없다. 실제로 갤러리 스캔 실패를
      // 세 번 추적하는 동안 이 한 줄이 없어서 계속 추측만 했다.
      debugPrint('[ocr] 입력 "${xFile.name}" '
          '형식=$mimeType '
          '크기=${(rawBytes.lengthInBytes / 1024).toStringAsFixed(0)}KB');

      // 3) 이미지 최적 리사이즈 (너무 크면 Gemini가 축소해서 오히려 품질 저하)
      final processedBytes = await _resizeIfNeeded(rawBytes, mimeType);
      final base64Image = base64Encode(processedBytes);

      // 실제로 보내는 바이트의 형식을 정직하게 적는다.
      // 축소/변환이 성공했으면 JPEG 가 되었고, 실패했으면 원본 형식이다.
      // 예전에는 항상 'image/jpeg' 로 적었는데, HEIC 원본이 그대로
      // 나갈 때 형식과 이름표가 어긋나 인식이 실패했다.
      final sentMime = identical(processedBytes, rawBytes)
          ? (mimeType == 'image/heic' ? 'image/jpeg' : mimeType)
          : 'image/jpeg';

      // 4) API 요청
      final requestBody = {
        'contents': [
          {
            'parts': [
              {'text': prompt},
              {
                'inlineData': {
                  'mimeType': sentMime,
                  'data': base64Image,
                }
              }
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.1, // 약간의 유연성 (0.0은 모호한 글자 스킵)
          'maxOutputTokens': 4000, // Pro 모델도 MAX_TOKENS 없이 충분히 처리
          'responseMimeType': 'application/json',
        }
      };

      final url = '$_baseUrl/$model:generateContent?key=$apiKey';

      // 🔴 타임아웃은 업로드 용량에 따라 늘린다.
      //
      // 45초 고정이던 시절, 웹에서 스캔이 계속 '응답이 너무 오래 걸려요' 로
      // 끝났다. 측정해보니 API 자체는 서버에서 2초(13MB 를 보내도 3.4초)면
      // 끝나는데, **브라우저에서 같은 요청이 훨씬 느렸다.**
      // 브라우저는 업로드 대역폭이 좁고 base64 본문이 커서, 큰 사진일수록
      // 전송에만 수십 초가 걸린다. 즉 API 문제가 아니라 우리 타임아웃이
      // 짧았던 것이다.
      // 기본 60초 + 1MB 당 10초를 더해 최대 180초까지 기다린다.
      final payload = jsonEncode(requestBody);
      final mb = payload.length / (1024 * 1024);
      final timeout = Duration(
        seconds: (60 + (mb * 10)).clamp(60, 180).round(),
      );
      // 배포 빌드에서도 보이게 한다. (위 '입력' 로그와 같은 이유)
      debugPrint('[ocr] 요청 ${mb.toStringAsFixed(1)}MB '
          '전송형식=$sentMime (제한 ${timeout.inSeconds}초, 모델 $model)');

      final response = await http
          .post(
            Uri.parse(url), // 런타임에 결정된 키+모델 사용
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: payload,
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        String errMsg = '알 수 없는 오류';
        try {
          final errBody = jsonDecode(response.body);
          errMsg = errBody['error']?['message'] ?? errMsg;
        } catch (_) {}
        debugPrint('[ocr] ❌ HTTP ${response.statusCode}: $errMsg');

        // 🔴 "이미지를 처리할 수 없다" 는 사진이 깨졌다는 뜻이다.
        //
        // 실측(갤러리에서 잘린 JPEG 을 골랐을 때):
        //   HTTP 400 Unable to process input image.
        // 이건 조명이나 구도 문제가 아니라 **파일 자체가 손상**된 것이다.
        // 카카오톡으로 받은 사진, 전송 중 끊긴 사진에서 실제로 나온다.
        if (errMsg.contains('Unable to process input image') ||
            errMsg.contains('Provided image is not valid')) {
          return GeminiOcrResult.error(
            '사진 파일이 손상되어 읽을 수 없습니다.\n'
            '다른 사진으로 시도하거나, 영수증을 직접 촬영해 주세요.\n'
            '(조명 문제가 아니라 파일 문제입니다)',
          );
        }
        return GeminiOcrResult.error(
            'API 오류 (${response.statusCode}): $errMsg');
      }

      // 5) 응답 파싱
      final responseJson = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = responseJson['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        return GeminiOcrResult.error('AI 응답이 비어있습니다. 다시 시도해주세요.');
      }

      final finishReason = (candidates[0]['finishReason'] as String?) ?? 'STOP';

      // 🔴 `parts[0]` 만 읽으면 **간헐적으로** 실패한다.
      //
      // 지금 쓰는 `gemini-3.5-flash-lite` 는 thinking 모델이다
      // (models 조회 결과 `"thinking": true`). 이 모델은 답을 내기 전에
      // 속으로 생각을 하고, 그 생각이 길어지면 응답의 `parts` 가
      // **두 개**로 온다.
      //
      //   parts[0] = { "text": "...생각...", "thought": true }
      //   parts[1] = { "text": "{\"store_name\": ...}" }   ← 진짜 답
      //
      // 실제로 측정했다. 같은 사진·같은 설정으로 10번 보내면
      // 어떤 때는 `parts` 가 1개, 어떤 때는 2개로 왔다.
      // (생각 토큰 `thoughtsTokenCount` 가 1042 까지 찍혔다)
      //
      // 즉 `parts[0]` 만 읽는 코드는 **생각 문장을 JSON 이라고 믿고**
      // 파싱하다 실패한다. 사진을 바꾼 것도, 형식이 문제인 것도 아니고
      // 그냥 모델이 그날 생각을 길게 했는지에 따라 갈렸다.
      // 사장님이 "어쩔 때는 되고 어쩔 때는 안 된다" 고 한 게 이것이다.
      //
      // 그래서 생각 조각(`thought: true`)은 건너뛰고, 남은 텍스트를
      // 모두 이어 붙인다.
      final parts = candidates[0]['content']?['parts'] as List?;
      final extracted = extractAnswerText(parts);
      final text = extracted.text;

      debugPrint('[ocr] 응답 finish=$finishReason parts=${parts?.length ?? 0}'
          '(생각 ${extracted.thoughtParts}) 본문 ${text.length}자');

      if (text.isEmpty) {
        // 생각에만 토큰을 다 쓰고 답을 못 쓴 경우가 대표적이다.
        // 이건 사진 문제가 아니므로 그렇게 말해줘야 한다.
        if (finishReason == 'MAX_TOKENS') {
          return GeminiOcrResult.error(
              'AI 응답이 중간에 끊겼습니다. (MAX_TOKENS)\n다시 시도하면 대부분 됩니다.');
        }
        return GeminiOcrResult.error(
            'AI가 응답을 생성하지 못했습니다. (reason: $finishReason)');
      }

      // 답이 오긴 왔는데 길이 제한에 걸려 잘린 경우.
      // 아래 파싱이 복구를 시도하지만, 실패하면 원인을 정확히 알려준다.
      if (finishReason == 'MAX_TOKENS') {
        debugPrint('[ocr] ⚠️ 응답이 MAX_TOKENS 로 잘렸다 — 복구 시도');
      }

      return _parseResponseRobust(text, finishReason);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('TimeoutException')) {
        return GeminiOcrResult.error('응답 시간이 초과되었습니다.\n잠시 후 다시 시도해주세요.');
      }
      if (msg.contains('SocketException') ||
          msg.contains('Failed host lookup') ||
          msg.contains('NetworkError')) {
        return GeminiOcrResult.error('네트워크 오류입니다.\n인터넷 연결을 확인해주세요.');
      }
      return GeminiOcrResult.error('처리 오류: $e');
    }
  }

  // ─────────────────────────────────────────
  // 이미지 리사이즈 (순수 Dart, 외부 패키지 없음)
  // ─────────────────────────────────────────
  Future<Uint8List> _resizeIfNeeded(Uint8List bytes, String mimeType) async {
    try {
      // 🔴 JPEG 가 아니면 크기를 읽지 못한다 — 그래도 축소는 시도해야 한다.
      //
      // 예전에는 `_readJpegSize` 가 null 이면 바로 원본을 돌려줬다.
      // 그래서 **갤러리의 PNG 스크린샷과 아이폰 HEIC 사진은 축소를 통째로
      // 건너뛰었다.** 촬영은 항상 JPEG 라서 잘 되는데 갤러리만 안 되는
      // 이유가 이것이었다. HEIC 는 Gemini 가 아예 받지 못하는 형식이라
      // 변환 없이는 무조건 실패한다.
      //
      // 이제 판단을 브라우저에 맡긴다. 브라우저는 형식과 크기를 정확히
      // 알고 있으므로, 줄일 필요가 없으면 스스로 null 을 돌려준다.
      final isJpeg = mimeType == 'image/jpeg';
      final size = isJpeg ? _readJpegSize(bytes) : null;

      if (isJpeg && size != null &&
          math.max(size[0], size[1]) <= _maxImageDimension) {
        return bytes; // 이미 충분히 작은 JPEG — 손대지 않는다
      }

      final w = size?[0] ?? 0;
      final h = size?[1] ?? 0;

      // 여기까지 왔으면 호출부가 크기를 안 줄여서 보낸 것이다.
      //
      // 예전에는 이 자리에서 `compute(_resizeJpegIsolate, ...)` 를 불렀는데,
      // 그 함수는 **원본 바이트를 그대로 반환**했다. 즉 줄이는 척만 했다.
      // 순수 Dart 로 JPEG 재인코딩은 불가하다.
      //
      // 웹에서는 브라우저의 canvas 로 실제로 줄일 수 있다. 웹 카메라
      // (`camera_web`)는 `imageQuality` 옵션이 없어서 항상 원본 크기로
      // 나오기 때문에, 이 경로가 없으면 큰 사진이 그대로 전송된다.
      final shrunk = await shrinkJpeg(
        bytes,
        _maxImageDimension,
        mimeType: mimeType,
      );
      final dim = (w > 0 && h > 0) ? '${w}x$h' : mimeType;
      if (shrunk != null) {
        debugPrint('[ocr] 이미지 변환/축소 $dim '
            '(${(bytes.lengthInBytes / 1024 / 1024).toStringAsFixed(1)}MB)'
            ' → JPEG '
            '${(shrunk.lengthInBytes / 1024 / 1024).toStringAsFixed(1)}MB');
        return shrunk;
      }

      // 네이티브에서는 `image_picker` 의 maxWidth/maxHeight 로 **가져올 때**
      // 줄인다. 여기 도달했다면 호출부에서 그게 빠진 것이다.
      debugPrint('[ocr] 축소하지 않고 원본 전송 $dim '
          '(${(bytes.lengthInBytes / 1024 / 1024).toStringAsFixed(1)}MB)');
      return bytes;
    } catch (_) {
      return bytes; // 크기 판독 실패 시 원본 그대로
    }
  }

  /// JPEG SOF 마커에서 [width, height] 읽기
  List<int>? _readJpegSize(Uint8List bytes) {
    try {
      int i = 2; // SOI 다음부터
      while (i < bytes.length - 1) {
        if (bytes[i] != 0xFF) break;
        final marker = bytes[i + 1];
        if (marker == 0xFF) {
          i++;
          continue;
        }
        final segLen = (bytes[i + 2] << 8) | bytes[i + 3];
        // SOF 마커: C0~C3, C5~C7, C9~CB, CD~CF
        if ((marker >= 0xC0 && marker <= 0xC3) ||
            (marker >= 0xC5 && marker <= 0xC7) ||
            (marker >= 0xC9 && marker <= 0xCB) ||
            (marker >= 0xCD && marker <= 0xCF)) {
          final h = (bytes[i + 5] << 8) | bytes[i + 6];
          final w = (bytes[i + 7] << 8) | bytes[i + 8];
          return [w, h];
        }
        i += 2 + segLen;
      }
    } catch (_) {}
    return null;
  }


  // ─────────────────────────────────────────
  // MIME 타입 감지
  // ─────────────────────────────────────────
  String _detectMimeType(Uint8List bytes, String filename) {
    if (bytes.length >= 4) {
      if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        return 'image/jpeg';
      }
      if (bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47) {
        return 'image/png';
      }
      if (bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46) {
        return 'image/webp';
      }
    }
    final lower = filename.toLowerCase();
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
    if (lower.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }

  // ─────────────────────────────────────────
  // 개선된 꽃집 영수증 프롬프트 (Few-shot 포함)
  // ─────────────────────────────────────────
  /// 기본 프롬프트를 외부에서 참조할 수 있도록 공개
  String getDefaultPrompt() => _buildPrompt();

  String _buildPrompt() {
    final today = DateTime.now();
    final currentYear = today.year;
    final todayStr =
        '$currentYear-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    return '''You are an OCR system for Korean florist receipts.
Today: $todayStr. Default year: $currentYear.

## PRIORITY (충돌 시 위쪽이 이긴다)
1. business_number, store_name  — 틀리면 안 된다
2. date                          — 틀리면 안 된다
3. 항목 개수 (손글씨가 적힌 행 수 = items 길이)
4. total_amount                  — 틀리면 안 된다
5. 품목명(name)                  — 최선을 다하되, 1~4를 훼손하면서 맞추지 않는다

품목명을 못 읽는 것은 허용된다. 행을 잃는 것은 허용되지 않는다.

## ORIENTATION
90도/180도 회전 촬영이 많다. 표의 괘선과 인쇄 문구 방향으로 정립시킨 뒤 읽는다.
회전 상태로 열을 배정하지 말 것.

## PRINTED vs HANDWRITTEN (전체를 관통하는 축)
간이영수증 = 인쇄 양식 + 손글씨 기입.

인쇄체 = 양식·고정정보. 거래 데이터가 아니다.
  양식 라벨: 사업자등록번호 상호 성명 사업장소재지 업태 종목 연락처
             작성년월일 공급대가총액 비고 귀하 No 품명 수량 단가 금액 합계
  고정 숫자: 사업자등록번호, 전화/팩스번호, 계좌번호, 주소 번지
  행 번호  : 표 왼쪽 1~10
  안내 문구: 위 금액을 정히 영수(청구)함, 은행명, 대표자명
  → 이 숫자에는 DASH RULE을 적용하지 않는다.

손글씨 = 실제 거래 데이터. 전부 추출한다.
  날짜, 총액, 품목명, 수량, 단가, 금액
  → DASH RULE은 손글씨 숫자에만 적용한다.
  → FLOWER NAMES 사전은 손글씨 품목명에만 적용한다.

## 1. BUSINESS NUMBER
인쇄체 중 가장 크고 굵다. 형식 XXX-XX-XXXXX (3-2-5, 총 10자리).
자릿수가 3-2-5가 아니면 오독이다. 다시 읽는다.
계좌번호·전화번호와 혼동하지 않는다. 사업자번호는 상단 "등록번호" 칸에 있다.
못 읽으면 "".

## 2. STORE NAME
"상호" 라벨 오른쪽 칸의 값만 읽는다.

주의:
- 상호 칸 오른쪽에 성명(대표자) 칸이 붙어 있다. 포함하지 않는다.
    "상호 강릉원예 성명 홍찬표" → 강릉원예
    "상호 로얄원예 성명 최학희" → 로얄원예
- 도장·직인이 성명 칸을 덮는 경우가 많다. 도장 글자는 무시한다.
- 상호는 대부분 인쇄체다. 백지에 손글씨로 쓴 경우 그것을 쓴다.
- 공백을 모두 제거한다.  김 바 우 원 예 → 김바우원예
- "귀하" 칸에 적힌 이름은 구매자다. store_name이 아니다.

## 3. DATE
작성년월일 칸 앞부분은 인쇄된 연도 접두사다. 숫자로 읽지 않는다.
접두사는 양식마다 "20" 또는 "202" 로 다르다.

  인쇄 "202" + 손글씨 "4.9.4"  → 2024-09-04
  인쇄 "202" + 손글씨 "4.9/4"  → 2024-09-04
  인쇄 "20"  + 손글씨 "24.9.7" → 2024-09-07
  인쇄 "20"  + 손글씨 "6/20"   → $currentYear-06-20   (연도 미기입)

출력 YYYY-MM-DD. 구분자는 . / - 공백 무엇이든 올 수 있다.
날짜가 전혀 없으면 $todayStr.

## 4. NUMBER FORMAT (손글씨 숫자 전용)
천 단위 생략 표기. 아래 4종은 모두 ×1000이다.

  15-    → 15000
  2--    → 2000      (-- 도 -와 동일. 20000이 아니다)
  12,    → 12000
  13,-   → 13000

전체 자릿수를 그대로 적기도 한다. 이때는 변환하지 않는다.
  30450  → 30450
  12,000 → 12000

판별: 하이픈/쉼표로 "끝나는" 숫자만 ×1000.
      하이픈 양쪽에 숫자가 있으면 식별번호다. 변환 금지.
        114-90-17441 / 010-3876-3536 / 110-354-456910

현실 범위: 단가 2,000~100,000원. 벗어나면 위 규칙을 재확인한다.

## 5. ITEMS — 행 보존이 최우선
표의 한 행 = 한 항목.

행 유지:
- 손글씨가 하나라도 있는 행은 반드시 출력한다.
- 품목명을 못 읽어도 행을 삭제하지 않는다. name=""로 두고 행은 남긴다.
- 금액이 적혀 있으면 그 행은 존재하는 것이다.
- 손글씨가 전혀 없는 빈 행(행번호만 인쇄된 행)은 출력하지 않는다.
- 합계/총액 줄에서 중단한다.

열 배정:
- 열 헤더 위치를 기준으로 배정한다. 토큰 순서로 밀어넣지 않는다.
- 빈 칸의 오른쪽 값을 왼쪽으로 당기지 않는다.
- 단가 칸이 비어 있는 영수증이 다수다. 수량과 금액만 적는 것이 오히려 일반적이다.
    단가 공란 + 수량 + 금액 → unit_price = total_price ÷ quantity
    숫자 1개만            → quantity=1, total_price=금액, unit_price=금액
- 숫자가 붙어 보이면 검산식으로 분해한다.
    "216 32" → 2×16=32 이므로 수량2 / 단가16000 / 금액32000
    216을 수량으로 쓰지 않는다.
- 수량은 거의 1~5. 20을 넘으면 열 오인을 의심한다.

품목명:
- 같은 이름이 다른 행에 있으면 별개 항목이다. 병합 금지.
- " 기호(동일품목 표시)는 이전 품목명을 반복 출력한다.
- FLOWER NAMES에 없는 이름이어도 보이는 대로 출력한다. 억지로 사전에 맞추지 않는다.
- 판독 불가 시 "" (빈 문자열). 추측으로 지어내지 않는다.

배송 누락:
- "안 들어옴", "미입고", "결품" 등이 붙은 줄은 실제 매입이 아니다. items에 넣지 않는다.
  총액에서 차감된 경우가 많으니 검산 시 참고한다.

## 6. TOTAL
총액 위치(우선순위 순):
  a. 공급대가총액 칸의 손글씨
  b. 하단에 큰 동그라미로 강조된 숫자
  c. 합계/총액/계 줄
  d. 위가 모두 없으면 항목 금액 합산

키워드: 합계 총액 계 공급대가총액 총공급대가 금액계

## 7. SELF-CHECK (재시도 후 플래그)
sum(items[].total_price) 와 total_amount 를 비교한다.

일치 → needs_review = false

불일치 → 아래 순서로 재시도한다.
  1. 누락된 행이 있는지 표 전체를 다시 훑는다 (특히 흐린 행, 표 하단)
  2. NUMBER FORMAT 오적용 확인 (2-- 를 20000으로 읽지 않았는지)
  3. 열 오인 확인 (붙은 숫자를 검산식으로 분해했는지)
  4. 배송 누락분이 총액에서 차감된 것은 아닌지 확인

재시도 후에도 불일치 →
  - 읽은 값을 그대로 출력한다. 차액을 임의로 채우거나 금액을 지어내지 않는다.
  - total_amount 는 기입된 총액을 사용한다 (항목 합산으로 덮어쓰지 않는다)
  - needs_review = true
  - review_reason 에 사유를 한 줄로 적는다

## FLOWER NAMES
읽기 애매한 손글씨 품목명은 아래를 참고한다. 없으면 보이는 대로 쓴다.

### 품목명은 **적힌 만큼 그대로** 옮긴다 (요약/상위분류 금지)
영수증에 `장미 쥬밀리아` 라고 적혀 있으면 `장미 쥬밀리아` 로 쓴다.
`장미` 로 줄이지 않는다. 품종/색/규격이 적혀 있으면 **버리지 말고 붙여서** 쓴다.
- `소국` → 소국 (X 국화)   `대국` → 대국 (X 국화)
- `스프레이국화` → 스프레이국화 (X 국화)
- `졸리핑크` → 졸리핑크 (X 리시안사스)
- `장미(레드)` → 장미 레드
사장님이 적은 구체적인 이름이 사라지면 시세 비교가 무의미해진다.

### 표준 품목명 (화훼공판장 경매 표기, 2년 거래량 순)
아래 목록은 **글자가 흐려서 판독이 애매할 때만** 참고한다.
선명하게 적힌 이름을 목록의 이름으로 바꾸지 않는다.
(예: 흐릿한 "리시안ㅅㅅ" → 리시안사스 O / 안 보이는 글자 → "" O)
참고: 경매 표기는 리시안사스, 튜립, 안개, 히야신스, 프리지아 다.
      다만 영수증에 `리시안셔스`/`튤립`/`후리지아` 라고 **선명히** 적혀
      있으면 적힌 그대로 쓴다. 표기 통일은 앱이 나중에 제안으로 처리한다.
장미 국화 거베라 프리지아 리시안사스 스톡크 백합 작약 유칼립투스 라넌큘러스 튜립 루스커스 칼라 옥시페탈륨 해바라기
알스트메리아 수국 스타티스 안시리움 노무라 공작초 금어초 안개 델피니움 보리사초 편백 캐모마일 카네이션 마가렛
맨드라미 엽란 파니쿰 호접란 조팝 다알리아 메리골드 유스가스 글라디올러스 석죽 알리움 시레네 스카비오사 소철 천일홍
냉이초 아미초 쿠루쿠마 후록스 심비디움 절화 설유화 불노초 아스그레피아스 영춘화 캄파눌라 디디스커스 아스틸베
솔리다스터 소재 기린초 아네모네 과꽃 솔리다고 명자란 클레마티스 코스모스 절지 꽃양배추 허브 베로니카 아이리스
하이페리콤 용담 골드킹 부들레야 브바르디아 아가판서스 오니소갈룸 등골나무 열매 왁스플라워 개미취 아게라덤 글로리오사
헬리옵시스 심포리카르포스 아카시아 시네라리아 남천 신지매 골든볼 수선 헬레보루스 루드베키아 홍가시 비부리움 그라스
천조초 백일홍 부프리움 각구도라 잎안개 니겔라 극락조화 카랑코에 이끼시아 멜라루카 사루비아 밥티시아 에키놉스
스위트피 금꿩의다리 히야신스 층꽃 말채나무 도라지꽃 금잔화 뽀삐 핑크뮬리 보리 팜파스 트리플륨 양란 스모그트리
헬레늄 버들나무 쥐똥나무 폴리안테스 연밥 유포로비아 산더소니아 라이스플라워 유채 아킬레아 호엽란 이베리스 풍선초
연꽃 피토스포륨 다정금 돈나무 아스파라거스 에렌지움 매화 탑사철 조 광나무(여정목) 모나르다 드럼스틱 디스텔 엉겅퀴
리아트리스 맥문동 미리오그라다스 마타리 비단향 꽃고추 억새풀 은사철 토마토

### 손글씨 변형 참고 (아래는 실제 영수증에 나온 약칭·색상접두 표기)
튤립 리시안 거베라 카라 투베로사 다알리아 페니쿰 공작 수국 장미
카네이션 라넌 베로니카 레몬트리 델피 유니폴라 홍가시 다알 용담
리시안셔스 금어초 라스 네리네 코스모스 자리공 리시 투베로즈
코랄리프 로얄 여뀌 영춘화 딥실버 W몬디알 아미초 립스틱 이끼시아
에렌지움 스텔링 옥스포드 클레마티스 메리골드 만다라 아스틸베
아스크레피어스 테디베어 라일락 파스타 온시 백일홍 향등골 델피늄
실거베라 쉬머 P몬디알 컨트리B 차밍 율듀스 P슈크렁 LT 녹보수
후리지아 솔채 무늬홍콩 채세나 용담초 라넌큘러스 오하라 아이비
모카라 덴파레 호접 심비디움 덴파레P 덴파레W
(소재) 페니쿰 공작 홍가시 레몬트리 유니폴라 여뀌 자리공 향등골
녹보수 에리카 조팝 설유화 목련 아스틸베 부추 층꽃 당근초 아미초

색상 접두/접미 그대로 보존: W리시안 Y다알리아 P몬디알 리시안P 리시안 연핑크
이름 변형 그대로 보존: 리시안=리시안셔스=리시 / 다알리아=다알=달리아 / 온시=온시디움

## EXAMPLES

Ex1 (기본):
Input: "[상호] 김 바 우 원 예 24.09.11 / Y리시안 3 15- 45- / 아스틸베 1 15- 15- / 합계 60-"
Output: {"business_number":"","store_name":"김바우원예","date":"2024-09-11","total_amount":60000,"needs_review":false,"review_reason":"","items":[{"name":"Y리시안","quantity":3,"unit_price":15000,"total_price":45000},{"name":"아스틸베","quantity":1,"unit_price":15000,"total_price":15000}]}

Ex2 (ditto mark):
Input: "신안원예 / 메리골드 2 12- 24- / 카네이션 1 15- 15- / " 1 12- 12- / 합계 51-"
Output: {"business_number":"","store_name":"신안원예","date":"$todayStr","total_amount":51000,"needs_review":false,"review_reason":"","items":[{"name":"메리골드","quantity":2,"unit_price":12000,"total_price":24000},{"name":"카네이션","quantity":1,"unit_price":15000,"total_price":15000},{"name":"카네이션","quantity":1,"unit_price":12000,"total_price":12000}]}

Ex3 (단가 공란 + 인쇄 연도 접두사 + 품목명 판독 불가):
Input: "등록번호 114-90-04403 / 상호 김바우원예 성명 김승수(도장) / 귀하 라마또
       작성년월일 202 4.9/4 / 공급대가총액 ₩26,-
       1 [판독불가] 1 (단가 빈칸) 13,- / 2 아이보리 1 (단가 빈칸) 13,-
       신한은행 367-02-014951"
주의: 114-90-04403, 367-02-014951 은 인쇄체. NUMBER FORMAT 적용 안 함.
      "라마또"는 귀하 칸(구매자). store_name 아님.
      1행 품목명 판독 불가 → name="" 이지만 행은 유지.
Self-check: 13000+13000=26000 = 총액 OK
Output: {"business_number":"114-90-04403","store_name":"김바우원예","date":"2024-09-04","total_amount":26000,"needs_review":false,"review_reason":"","items":[{"name":"","quantity":1,"unit_price":13000,"total_price":13000},{"name":"아이보리","quantity":1,"unit_price":13000,"total_price":13000}]}

Ex4 (붙은 숫자 분해):
Input: "등록번호 528-01-01372 / 상호 강남원예 성명 김판국 / 24.09.25
       코랄리프 216 32 / 컨트리B 116 16 / 라넌 213 26 / 합계 74-"
WRONG: quantity=216, unit_price=32000
RIGHT: 2×16=32 이므로 quantity=2, unit_price=16000, total_price=32000
Self-check: 32000+16000+26000=74000 OK
Output: {"business_number":"528-01-01372","store_name":"강남원예","date":"2024-09-25","total_amount":74000,"needs_review":false,"review_reason":"","items":[{"name":"코랄리프","quantity":2,"unit_price":16000,"total_price":32000},{"name":"컨트리B","quantity":1,"unit_price":16000,"total_price":16000},{"name":"라넌","quantity":2,"unit_price":13000,"total_price":26000}]}

Ex5 (재시도 후에도 불일치 → 플래그):
Input: "등록번호 689-95-00075 / 상호 다인플라워 / 2024.1.6 / 공급대가총액 59-
       1행 2 7- 14- / 2행 2 10- 20- / 3행 [흐림] / 4행 1 15- 15-"
재시도: 3행이 흐리지만 손글씨 흔적이 있으므로 행 유지. 금액 판독 불가.
Self-check: 14000+20000+15000=49000 ≠ 59000 (차액 10000, 확정 불가)
차액을 3행에 임의로 채우지 않는다.
Output: {"business_number":"689-95-00075","store_name":"다인플라워","date":"2024-01-06","total_amount":59000,"needs_review":true,"review_reason":"3행 금액 판독 불가, 항목합 49000 vs 총액 59000","items":[{"name":"","quantity":2,"unit_price":7000,"total_price":14000},{"name":"","quantity":2,"unit_price":10000,"total_price":20000},{"name":"","quantity":0,"unit_price":0,"total_price":0},{"name":"","quantity":1,"unit_price":15000,"total_price":15000}]}

## OUTPUT
JSON만 출력. 마크다운·설명 없음.
{"business_number":"XXX-XX-XXXXX","store_name":"공백없는문자열","date":"YYYY-MM-DD","total_amount":숫자,"needs_review":true/false,"review_reason":"문자열","items":[{"name":"문자열","quantity":숫자,"unit_price":숫자,"total_price":숫자}]}

규칙:
- 숫자 필드는 모두 number 타입
- store_name 공백 없음, 대표자명 미포함
- business_number 는 XXX-XX-XXXXX 형식. 못 읽으면 ""
- name 은 판독 불가 시 "" (지어내지 않음)
- quantity × unit_price = total_price
- 판독 불가 행은 0으로 채우되 행 자체는 유지
- needs_review=false 이면 sum(total_price) == total_amount 여야 함
- unit_price > 100,000 → NUMBER FORMAT 재확인
- quantity > 20 → 열 오인 재확인''';
  }

  // ─────────────────────────────────────────
  // 견고한 JSON 파싱 - 5단계 전략
  // ─────────────────────────────────────────
  GeminiOcrResult _parseResponseRobust(String text, String finishReason) {
    String jsonStr = text.trim();

    // 전략 1: 직접 파싱
    try {
      return _parseJsonString(jsonStr);
    } catch (_) {}

    // 전략 2: 마크다운 코드블록 제거
    try {
      final match =
          RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').firstMatch(jsonStr);
      if (match != null) return _parseJsonString(match.group(1)!.trim());
    } catch (_) {}

    // 전략 3: 첫 { ~ 마지막 } 추출
    try {
      final start = jsonStr.indexOf('{');
      final end = jsonStr.lastIndexOf('}');
      if (start != -1 && end != -1 && end > start) {
        return _parseJsonString(jsonStr.substring(start, end + 1));
      }
    } catch (_) {}

    // 전략 4: 잘린 JSON 복구
    try {
      final fixed = _repairTruncatedJson(jsonStr);
      if (fixed != null) return _parseJsonString(fixed);
    } catch (_) {}

    // 전략 5: { 부터 시작해서 복구
    try {
      final start = jsonStr.indexOf('{');
      if (start != -1) {
        final fixed = _repairTruncatedJson(jsonStr.substring(start));
        if (fixed != null) return _parseJsonString(fixed);
      }
    } catch (_) {}

    // 🔴 여기까지 왔으면 5단계 파싱이 전부 실패한 것이다.
    //
    // 예전에는 조용히 `_extractFromPlainText` 로 넘어가 **품목 0개 ·
    // success:true** 를 돌려줬다. 그러면 `scan_flow` 는 실패로 분류하지
    // 못하고(에러 문구가 없으니) 결국 "조명이 밝은 곳에서 다시 찍어주세요"
    // 만 띄웠다. 파싱 실패인데 사진 탓을 한 것이다.
    debugPrint('[ocr] ❌ JSON 파싱 5단계 모두 실패 '
        '(finish=$finishReason, ${text.length}자) 앞부분: '
        '${jsonStr.length > 160 ? jsonStr.substring(0, 160) : jsonStr}');

    // 응답이 잘려서 파싱이 안 되는 경우는 재시도로 해결된다.
    if (finishReason == 'MAX_TOKENS') {
      return GeminiOcrResult.error(
          'AI 응답이 중간에 끊겨서 읽지 못했습니다. (MAX_TOKENS)\n다시 시도해 주세요.');
    }

    // 최후: 텍스트에서 수동 추출
    return _extractFromPlainText(jsonStr);
  }

  GeminiOcrResult _parseJsonString(String jsonStr) {
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;

    // 프롬프트 규칙: 판독 불가한 값은 지어내지 않고 빈 값으로 둔다.
    // 따라서 여기서도 '꽃집' 같은 가짜 기본값을 넣지 않는다.
    final rawStoreName = _safeString(data['store_name']) ?? '';
    // 상호명에서 공백 제거 (OCR이 자모/글자 사이에 공백을 넣을 수 있음)
    final storeName = rawStoreName.replaceAll(' ', '');
    final dateStr = _safeString(data['date']) ?? '';
    final businessNumber =
        _normalizeBizNo(_safeString(data['business_number']) ?? '');
    final needsReview = _safeBool(data['needs_review']) ?? false;
    final reviewReason = _safeString(data['review_reason']) ?? '';
    final totalAmount = _safeDouble(data['total_amount']) ?? 0.0;

    DateTime date;
    try {
      date = DateTime.parse(dateStr);
    } catch (_) {
      date = DateTime.now();
    }

    final itemsList = data['items'];
    final items = <GeminiItem>[];
    if (itemsList is List) {
      for (final item in itemsList) {
        if (item is! Map<String, dynamic>) continue;
        // 판독 불가 행은 0으로 채워서 오지만 행 자체는 유지해야 한다.
        // → quantity 0 을 1 로 덮어쓰지 않는다.
        final qty = _safeInt(item['quantity']) ?? 0;
        final unitPrice = _safeDouble(item['unit_price']) ?? 0.0;
        final totalPrice =
            _safeDouble(item['total_price']) ?? (unitPrice * qty);
        items.add(GeminiItem(
          // 이름은 판독 불가 시 '' 를 그대로 유지한다.
          name: _safeString(item['name']) ?? '',
          quantity: qty,
          unitPrice: unitPrice > 0
              ? unitPrice
              : (qty > 0 && totalPrice > 0 ? totalPrice / qty : 0),
          unit: _safeString(item['unit']) ?? '단(묶음)',
          totalPrice: totalPrice,
        ));
      }
    }

    final itemSum = items.fold(0.0, (s, i) => s + i.totalPrice);
    // 프롬프트 규칙: total_amount 는 기입된 총액을 그대로 쓴다.
    // (항목 합산으로 덮어쓰지 않는다. 총액이 아예 없을 때만 합산으로 보완)
    final resolvedTotal = totalAmount > 0 ? totalAmount : itemSum;

    // 새 프롬프트에는 confidence 필드가 없다.
    // needs_review / 합계 불일치 여부로 신뢰도를 산출한다.
    final mismatch = resolvedTotal > 0 && (resolvedTotal - itemSum).abs() > 1;
    double confidence = 0.92;
    if (needsReview) confidence = 0.5;
    if (mismatch) confidence = confidence > 0.55 ? 0.55 : confidence;
    if (storeName.isEmpty || items.isEmpty) confidence = 0.4;

    return GeminiOcrResult(
      success: true,
      storeName: storeName,
      businessNumber: businessNumber,
      date: date,
      items: items,
      totalAmount: resolvedTotal,
      needsReview: needsReview || mismatch,
      reviewReason: reviewReason.isNotEmpty
          ? reviewReason
          : (mismatch
              ? '항목 합계(${itemSum.toStringAsFixed(0)})와 '
                  '총액(${resolvedTotal.toStringAsFixed(0)})이 다릅니다'
              : ''),
      // 새 스키마에는 raw_text 가 없다. 모델이 돌려준 JSON 원문을 보존한다.
      rawText: jsonStr,
      confidence: confidence,
    );
  }

  /// 사업자등록번호를 XXX-XX-XXXXX 로 정규화한다.
  /// 숫자가 10자리가 아니면 오독이므로 버린다.
  String _normalizeBizNo(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 10) return '';
    return '${digits.substring(0, 3)}-${digits.substring(3, 5)}'
        '-${digits.substring(5)}';
  }

  // ─────────────────────────────────────────
  // 타입 안전 파싱 헬퍼
  // ─────────────────────────────────────────
  String? _safeString(dynamic v) {
    if (v == null) return null;
    if (v is String) return v.isEmpty ? null : v;
    return v.toString();
  }

  double? _safeDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  int? _safeInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  bool? _safeBool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final s = v.trim().toLowerCase();
      if (s == 'true' || s == '1' || s == 'yes') return true;
      if (s == 'false' || s == '0' || s == 'no') return false;
    }
    return null;
  }

  /// 잘린 JSON 복구
  String? _repairTruncatedJson(String truncated) {
    String work = truncated.trim();
    final start = work.indexOf('{');
    if (start > 0) work = work.substring(start);
    if (work.isEmpty) return null;

    final buf = StringBuffer(work);
    int braces = 0, brackets = 0;
    bool inString = false, escaped = false;

    for (int i = 0; i < work.length; i++) {
      final c = work[i];
      if (escaped) {
        escaped = false;
        continue;
      }
      if (c == '\\') {
        escaped = true;
        continue;
      }
      if (c == '"') {
        inString = !inString;
        continue;
      }
      if (!inString) {
        if (c == '{') braces++;
        if (c == '}') braces--;
        if (c == '[') brackets++;
        if (c == ']') brackets--;
      }
    }

    if (inString) buf.write('"');
    for (int i = 0; i < brackets; i++) buf.write(']');
    for (int i = 0; i < braces; i++) buf.write('}');

    final result = buf.toString();
    try {
      jsonDecode(result);
      return result;
    } catch (_) {
      for (final suffix in [']}', ']}}', '}', '{}]}']) {
        try {
          final attempt = work + suffix;
          jsonDecode(attempt);
          return attempt;
        } catch (_) {}
      }
      return null;
    }
  }

  /// JSON 파싱 완전 실패 시 텍스트에서 직접 추출
  GeminiOcrResult _extractFromPlainText(String text) {
    final dateMatch = RegExp(r'\d{4}[-./]\d{1,2}[-./]\d{1,2}').firstMatch(text);
    DateTime date = DateTime.now();
    if (dateMatch != null) {
      try {
        date = DateTime.parse(
            dateMatch.group(0)!.replaceAll(RegExp(r'[./]'), '-'));
      } catch (_) {}
    }

    return GeminiOcrResult(
      success: true,
      storeName: '',
      businessNumber: '',
      date: date,
      items: [],
      totalAmount: 0,
      needsReview: true,
      reviewReason: 'JSON 파싱 실패 — 직접 확인이 필요합니다',
      rawText: text,
      confidence: 0.3,
    );
  }
}

// ─────────────────────────────────────────
// 결과 데이터 클래스
// ─────────────────────────────────────────
class GeminiOcrResult {
  final bool success;
  final String? errorMessage;
  final String storeName;

  /// 사업자등록번호 (XXX-XX-XXXXX). 판독 불가 시 ''.
  final String businessNumber;
  final DateTime date;
  final List<GeminiItem> items;
  final double totalAmount;

  /// 모델이 스스로 검산에 실패했다고 표시한 경우 true.
  final bool needsReview;

  /// `needsReview` 사유 한 줄. 없으면 ''.
  final String reviewReason;
  final String rawText;
  final double confidence;

  GeminiOcrResult({
    required this.success,
    this.errorMessage,
    required this.storeName,
    this.businessNumber = '',
    required this.date,
    required this.items,
    required this.totalAmount,
    this.needsReview = false,
    this.reviewReason = '',
    required this.rawText,
    required this.confidence,
  });

  factory GeminiOcrResult.error(String message) => GeminiOcrResult(
        success: false,
        errorMessage: message,
        storeName: '',
        businessNumber: '',
        date: DateTime.now(),
        items: [],
        totalAmount: 0,
        needsReview: true,
        reviewReason: message,
        rawText: '',
        confidence: 0,
      );

  bool get hasItems => items.isNotEmpty;
  bool get isHighConfidence => confidence >= 0.6;
}

class GeminiItem {
  final String name;
  final int quantity;
  final double unitPrice;
  final String unit;
  final double totalPrice;

  GeminiItem({
    required this.name,
    required this.quantity,
    required this.unitPrice,
    required this.unit,
    required this.totalPrice,
  });
}
