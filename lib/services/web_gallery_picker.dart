/// 웹에서 갤러리 사진을 **바이트로 직접** 가져온다.
///
/// 조건부 임포트로 웹에서만 실제 구현이 붙는다.
library;

export 'web_gallery_picker_stub.dart'
    if (dart.library.js_interop) 'web_gallery_picker_web.dart';
