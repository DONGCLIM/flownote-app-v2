import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 사업자등록증 인식 결과.
class BusinessInfoResult {
  const BusinessInfoResult({
    required this.success,
    this.errorMessage,
    this.businessName = '',
    this.businessNumber = '',
    this.ownerName = '',
    this.businessAddress = '',
    this.openDate = '',
    this.businessType = '',
    this.businessItem = '',
    this.confidence = 0,
  });

  final bool success;
  final String? errorMessage;

  /// 상호
  final String businessName;

  /// 사업자등록번호 (000-00-00000)
  final String businessNumber;

  /// 대표자
  final String ownerName;

  /// 사업장 소재지
  final String businessAddress;

  /// 개업연월일
  final String openDate;

  /// 업태
  final String businessType;

  /// 종목
  final String businessItem;

  final double confidence;

  factory BusinessInfoResult.error(String m) =>
      BusinessInfoResult(success: false, errorMessage: m);

  bool get isEmpty =>
      businessName.isEmpty && businessNumber.isEmpty && ownerName.isEmpty;

  /// 필수 항목이 모두 채워졌는지
  bool get isComplete =>
      businessName.isNotEmpty &&
      businessNumber.isNotEmpty &&
      ownerName.isNotEmpty;

  BusinessInfoResult copyWith({
    String? businessName,
    String? businessNumber,
    String? ownerName,
    String? businessAddress,
    String? openDate,
    String? businessType,
    String? businessItem,
  }) =>
      BusinessInfoResult(
        success: success,
        errorMessage: errorMessage,
        businessName: businessName ?? this.businessName,
        businessNumber: businessNumber ?? this.businessNumber,
        ownerName: ownerName ?? this.ownerName,
        businessAddress: businessAddress ?? this.businessAddress,
        openDate: openDate ?? this.openDate,
        businessType: businessType ?? this.businessType,
        businessItem: businessItem ?? this.businessItem,
        confidence: confidence,
      );
}

/// 사업자등록증 이미지에서 사업자 정보를 뽑아내는 서비스.
///
/// 영수증 OCR 과 같은 Gemini 엔드포인트를 쓰지만 프롬프트/스키마가 달라
/// 별도 서비스로 분리했다.
class BusinessOcrService {
  static const String _compiledKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent';

  Future<String?> _resolveApiKey() async {
    if (_compiledKey.isNotEmpty) return _compiledKey;
    final prefs = await SharedPreferences.getInstance();
    final k = prefs.getString('gemini_api_key');
    if (k != null && k.trim().isNotEmpty) return k.trim();
    return null;
  }

  static const _prompt = '''
너는 대한민국 사업자등록증을 읽는 OCR 도우미다.
이미지에서 아래 항목을 찾아 JSON 으로만 답하라. 설명 문장은 절대 붙이지 마라.

{
  "businessName": "상호(법인명)",
  "businessNumber": "등록번호 (000-00-00000 형식)",
  "ownerName": "성명(대표자)",
  "businessAddress": "사업장 소재지 전체 주소",
  "openDate": "개업연월일 (YYYY-MM-DD)",
  "businessType": "업태",
  "businessItem": "종목",
  "confidence": 0.0~1.0
}

규칙:
- 찾지 못한 항목은 빈 문자열 "" 로 둔다.
- 등록번호는 반드시 숫자 10자리를 000-00-00000 형태로 정규화한다.
- 상호에서 "주식회사", "(주)" 같은 접두는 그대로 유지한다.
- 사업자등록증이 아니면 모든 항목을 "" 로 두고 confidence 를 0 으로 한다.
''';

  Future<BusinessInfoResult> recognize({required XFile xFile}) async {
    final key = await _resolveApiKey();
    if (key == null) {
      return BusinessInfoResult.error('AI 설정에서 API 키를 먼저 등록해 주세요.');
    }

    try {
      final Uint8List bytes = await xFile.readAsBytes();
      final mime = _detectMime(bytes, xFile.name);

      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': _prompt},
              {
                'inline_data': {
                  'mime_type': mime,
                  'data': base64Encode(bytes),
                }
              },
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.1,
          'maxOutputTokens': 1024,
          'responseMimeType': 'application/json',
        },
      });

      final res = await http
          .post(
            Uri.parse('$_baseUrl?key=$key'),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 40));

      if (res.statusCode != 200) {
        return BusinessInfoResult.error(
            '인식 서버 오류 (${res.statusCode}). 잠시 후 다시 시도해 주세요.');
      }

      final decoded = jsonDecode(utf8.decode(res.bodyBytes))
          as Map<String, dynamic>;
      final candidates = decoded['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        return BusinessInfoResult.error('사업자등록증을 읽지 못했어요.');
      }
      final text = (((candidates.first
                  as Map<String, dynamic>)['content']
              as Map<String, dynamic>)['parts'] as List)
          .map((e) => (e as Map<String, dynamic>)['text'] ?? '')
          .join();

      return _parse(text);
    } catch (e) {
      return BusinessInfoResult.error(
          '인식 중 문제가 생겼어요. 네트워크를 확인해 주세요.');
    }
  }

  BusinessInfoResult _parse(String raw) {
    var s = raw.trim();
    if (s.startsWith('```')) {
      s = s.replaceAll(RegExp(r'^```(json)?'), '').replaceAll('```', '').trim();
    }
    try {
      final m = jsonDecode(s) as Map<String, dynamic>;
      final num conf = (m['confidence'] as num?) ?? 0;
      final result = BusinessInfoResult(
        success: true,
        businessName: (m['businessName'] ?? '').toString().trim(),
        businessNumber:
            normalizeBizNumber((m['businessNumber'] ?? '').toString()),
        ownerName: (m['ownerName'] ?? '').toString().trim(),
        businessAddress: (m['businessAddress'] ?? '').toString().trim(),
        openDate: (m['openDate'] ?? '').toString().trim(),
        businessType: (m['businessType'] ?? '').toString().trim(),
        businessItem: (m['businessItem'] ?? '').toString().trim(),
        confidence: conf.toDouble(),
      );
      if (result.isEmpty) {
        return BusinessInfoResult.error(
            '사업자등록증이 아닌 것 같아요. 다시 촬영해 주세요.');
      }
      return result;
    } catch (_) {
      return BusinessInfoResult.error('인식 결과를 해석하지 못했어요.');
    }
  }

  String _detectMime(Uint8List b, String name) {
    if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return 'image/jpeg';
    if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50) return 'image/png';
    final n = name.toLowerCase();
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  /// 숫자 10자리를 000-00-00000 형태로 정규화.
  static String normalizeBizNumber(String v) {
    final d = v.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length != 10) return v.trim();
    return '${d.substring(0, 3)}-${d.substring(3, 5)}-${d.substring(5)}';
  }

  /// 사업자등록번호 체크섬 검증 (국세청 규칙).
  static bool isValidBizNumber(String v) {
    final d = v.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.length != 10) return false;
    const w = [1, 3, 7, 1, 3, 7, 1, 3, 5];
    var sum = 0;
    for (var i = 0; i < 9; i++) {
      sum += int.parse(d[i]) * w[i];
    }
    sum += (int.parse(d[8]) * 5) ~/ 10;
    final check = (10 - (sum % 10)) % 10;
    return check == int.parse(d[9]);
  }
}
