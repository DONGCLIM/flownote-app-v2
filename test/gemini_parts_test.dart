import 'package:flutter_test/flutter_test.dart';
import 'package:flow_note/services/gemini_ocr_service.dart';

/// 갤러리 스캔이 "어쩔 때는 되고 어쩔 때는 안 되던" 버그를 못 박는 테스트.
///
/// thinking 모델은 생각이 길어지면 `parts` 를 두 개로 돌려준다.
/// 예전 코드는 `parts[0]` 만 읽어서 생각 문장을 JSON 이라 믿고 파싱했다.
/// 생각 길이가 매번 달라지므로 실패가 간헐적이었다.
void main() {
  group('extractAnswerText', () {
    test('생각(thought) 조각을 건너뛰고 실제 답만 돌려준다', () {
      // 실제로 관측된 형태: parts[0] 이 생각, parts[1] 이 답.
      final parts = [
        {
          'text': '영수증을 보니 대림생화이고 품목이 7개인 것 같다. 금액을 다시 확인해보자...',
          'thought': true,
        },
        {'text': '{"store_name":"대림생화","total_amount":271000}'},
      ];

      final r = extractAnswerText(parts);

      expect(r.thoughtParts, 1);
      expect(r.text, '{"store_name":"대림생화","total_amount":271000}');
      // 생각 문장이 절대 섞여 들어가면 안 된다.
      expect(r.text.contains('확인해보자'), isFalse);
    });

    test('생각이 없는 단일 parts 응답도 그대로 동작한다', () {
      final parts = [
        {'text': '{"store_name":"대림생화"}'},
      ];

      final r = extractAnswerText(parts);

      expect(r.thoughtParts, 0);
      expect(r.text, '{"store_name":"대림생화"}');
    });

    test('답 조각이 여러 개면 순서대로 이어 붙인다', () {
      final parts = [
        {'text': '생각 중', 'thought': true},
        {'text': '{"store_name":'},
        {'text': '"대림생화"}'},
      ];

      final r = extractAnswerText(parts);

      expect(r.thoughtParts, 1);
      expect(r.text, '{"store_name":"대림생화"}');
    });

    test('생각만 오고 답이 없으면 빈 문자열 — 호출부가 MAX_TOKENS 로 처리한다', () {
      final parts = [
        {'text': '아주 긴 생각...', 'thought': true},
      ];

      final r = extractAnswerText(parts);

      expect(r.thoughtParts, 1);
      expect(r.text, isEmpty);
    });

    test('parts 가 null 이거나 비어도 죽지 않는다', () {
      expect(extractAnswerText(null).text, isEmpty);
      expect(extractAnswerText([]).text, isEmpty);
      // Map 이 아닌 값이 섞여 있어도 무시한다.
      expect(extractAnswerText(['이상한 값', 42]).text, isEmpty);
    });

    test('앞뒤 공백은 정리한다', () {
      final r = extractAnswerText([
        {'text': '\n\n  {"a":1}  \n'},
      ]);
      expect(r.text, '{"a":1}');
    });
  });
}
