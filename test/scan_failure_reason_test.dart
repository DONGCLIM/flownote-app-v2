import 'package:flutter_test/flutter_test.dart';
import 'package:flow_note/screens/scan/scan_flow.dart';

/// 스캔 실패 안내가 **원인에 맞게** 나가는지 고정한다.
///
/// 왜 이 테스트가 있는가:
/// 갤러리 스캔이 안 된다는 신고를 여러 번 받았는데, 화면에는 매번
/// "조명이 밝은 곳에서 다시 찍어주세요" 가 떴다. 정작 원인은 조명이
/// 아니라 **파일을 못 읽은 것**이었다. 분류 분기에 걸리지 않은 오류가
/// 모두 맨 끝의 조명 안내로 흘러가는 구조였기 때문이다.
///
/// 사장님은 사진을 아무리 밝게 다시 찍어도 될 수 없었고, 우리는 화면을
/// 직접 보지 않으면 이 사실을 알 수 없었다. 그래서 규칙을 코드로 굳힌다.
void main() {
  group('스캔 실패 분류', () {
    test('파일을 못 읽으면 조명 얘기를 하지 않는다', () {
      final t = failureTitleForTest([
        '사진 파일이 비어 있습니다. (파일 읽기 실패)\n'
            '클라우드에만 저장된 사진일 수 있어요.',
      ]);
      expect(t, '사진 파일을 열지 못했어요');
      expect(t.contains('조명'), isFalse);
    });

    test('파일이 손상된 경우도 파일 문제로 분류한다', () {
      // 실측: 잘린 JPEG → HTTP 400 Unable to process input image
      expect(
        failureTitleForTest(['사진 파일이 손상되어 읽을 수 없습니다.']),
        '사진 파일을 열지 못했어요',
      );
    });

    test('알 수 없는 오류를 조명 탓으로 돌리지 않는다', () {
      expect(
        failureTitleForTest(['처리 오류: TypeError: null is not an object']),
        '예상치 못한 오류가 났어요',
      );
    });

    test('API 키 누락은 설정 문제로 먼저 걸린다', () {
      expect(
        failureTitleForTest(['API 키가 설정되지 않았습니다.']),
        'AI 설정이 안 되어 있어요',
      );
    });

    test('네트워크 오류는 인터넷 문제로 분류한다', () {
      expect(
        failureTitleForTest(['네트워크 오류입니다.']),
        '인터넷에 연결되지 않았어요',
      );
    });

    test('MAX_TOKENS 는 재시도 안내로 분류한다', () {
      expect(
        failureTitleForTest(['AI 응답이 중간에 끊겼습니다. (MAX_TOKENS)']),
        '다시 한 번만 눌러주세요',
      );
    });

    test('진짜로 글자를 못 찾은 경우에만 조명 안내가 나간다', () {
      expect(
        failureTitleForTest(['인식에 실패했어요']),
        '영수증을 읽지 못했어요',
      );
    });

    test('파일 오류가 섞여 있으면 파일 오류를 우선한다', () {
      // 여러 장을 고른 경우 오류가 합쳐져 들어온다. 사장님이 손쓸 수 있는
      // 쪽(파일 다시 고르기)을 먼저 알려야 한다.
      expect(
        failureTitleForTest([
          '인식에 실패했어요',
          '사진 파일이 비어 있습니다. (파일 읽기 실패)',
        ]),
        '사진 파일을 열지 못했어요',
      );
    });
  });
}
