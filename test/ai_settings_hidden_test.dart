import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// ═══════════════════════════════════════════════════════════════════════
/// #108 — AI 인식(Gemini) 설정 화면을 앱/웹 어디서도 열 수 없어야 한다
/// ═══════════════════════════════════════════════════════════════════════
///
/// 사장님 요청: "api 키랑 프롬프트랑 모델이랑 다 그대로 코드에는 남겨놓고
///              설정 바꾸지 말고, 프로필에서 그걸 볼 수 없게. 앱이든 웹이든
///              접속 못하게."
///
/// 그래서 이 테스트는 **두 방향**을 동시에 지킨다.
///   ① 진입 경로가 없어야 한다        (다시 생기면 실패)
///   ② 화면/서비스/설정은 남아야 한다  (지우면 실패)
///
/// ②가 중요하다. 입구만 막는 것이라 영수증 OCR 은 그대로 동작해야 한다.
/// `ApiKeyService` 가 저장소에서 키를 직접 읽기 때문에 화면이 없어도 된다.
/// 누가 "안 쓰는 코드네" 하고 지우면 스캔이 통째로 죽는다.

const _entryHosts = [
  'lib/screens/ds/profile_ds_screen.dart', // 현재 살아있는 프로필
  'lib/screens/profile_screen.dart', // 레거시 프로필
  'lib/screens/scan_screen.dart', // 레거시 스캔(톱니 버튼)
];

/// 주석이 아닌 줄만 본다. 주석에는 복구 방법이 근거로 남아 있다.
List<String> _liveLines(String src, String needle) {
  return src
      .split('\n')
      .where((l) => l.contains(needle) && !l.trimLeft().startsWith('//'))
      .toList();
}

void main() {
  group('#108 AI 설정 화면 진입 차단', () {
    test('🔴 어떤 화면에서도 GeminiKeyScreen 을 열지 않는다', () {
      for (final path in _entryHosts) {
        final f = File(path);
        if (!f.existsSync()) continue;
        final live = _liveLines(f.readAsStringSync(), 'GeminiKeyScreen');
        expect(live, isEmpty,
            reason: '$path 에 진입 경로가 되살아났다: $live\n'
                '사장님이 앱/웹 양쪽에서 못 들어가게 해달라고 하셨다');
      }
    });

    test('🔴 프로필 목록에 AI 설정 항목 문구가 없다', () {
      for (final path in _entryHosts) {
        final f = File(path);
        if (!f.existsSync()) continue;
        final src = f.readAsStringSync();
        // 코드 모양(따옴표로 감싼 항목 라벨)으로만 검사한다.
        for (final needle in [
          "'AI 인식(Gemini) API 키 설정'",
          "label: 'AI 설정'",
          "tooltip: 'AI 설정'",
        ]) {
          expect(_liveLines(src, needle), isEmpty,
              reason: '$path 에 $needle 이 되살아났다');
        }
      }
    });

    test('🔴 이름있는 라우트/딥링크로도 열 수 없다', () {
      // 웹에서 주소창으로 들어가는 경로가 생기면 안 된다.
      for (final dir in [Directory('lib')]) {
        for (final e in dir.listSync(recursive: true)) {
          if (e is! File || !e.path.endsWith('.dart')) continue;
          final src = e.readAsStringSync();
          for (final needle in ['routes:', 'onGenerateRoute']) {
            final live = _liveLines(src, needle);
            expect(live, isEmpty,
                reason: '${e.path} 에 이름있는 라우트가 생겼다. '
                    'AI 설정 화면이 주소로 열리지 않는지 확인해야 한다: $live');
          }
        }
      }
    });
  });

  group('#108 그러나 기능은 살아 있어야 한다', () {
    test('🔴 화면 파일과 서비스를 지우지 않았다', () {
      // 사장님 요청은 "코드에는 다 그대로 남겨놓고" 였다.
      for (final path in [
        'lib/screens/gemini_key_screen.dart',
        'lib/services/api_key_service.dart',
        'lib/services/gemini_ocr_service.dart',
      ]) {
        final f = File(path);
        expect(f.existsSync(), isTrue,
            reason: '$path 를 지우면 안 된다. 입구만 막은 것이다');
        expect(f.lengthSync(), greaterThan(1000),
            reason: '$path 가 비었다. 내용을 지우면 안 된다');
      }
    });

    test('🔴 저장된 키/프롬프트/모델을 읽는 통로가 남아 있다', () {
      final svc = File('lib/services/api_key_service.dart').readAsStringSync();
      for (final m in [
        'getGeminiKey',
        'getModel',
        'getCustomPrompt',
        'defaultModel',
      ]) {
        expect(svc.contains(m), isTrue,
            reason: 'ApiKeyService.$m 이 사라졌다. '
                '화면이 없어도 OCR 은 이 통로로 키를 읽는다');
      }
    });

    test('🔴 OCR 서비스가 여전히 저장된 설정을 사용한다', () {
      final ocr = File('lib/services/gemini_ocr_service.dart').readAsStringSync();
      expect(ocr.contains('ApiKeyService'), isTrue,
          reason: 'OCR 이 저장된 키를 안 읽으면 스캔이 죽는다');
    });
  });
}
