/// 큰 JPEG 를 실제로 줄이는 유틸.
///
/// 웹에서는 브라우저 canvas 로 재인코딩할 수 있고(`image_shrink_web.dart`),
/// 네이티브에서는 순수 Dart 로 JPEG 재인코딩이 불가하므로 아무것도 하지
/// 않는다(`image_shrink_stub.dart`). 네이티브는 `image_picker` 의
/// maxWidth/maxHeight 가 가져올 때 이미 줄여준다.
library;

export 'image_shrink_stub.dart'
    if (dart.library.js_interop) 'image_shrink_web.dart';
