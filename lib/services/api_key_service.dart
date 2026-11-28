import 'package:shared_preferences/shared_preferences.dart';

/// Gemini API 키 / 모델 / 프롬프트 로컬 저장 관리
class ApiKeyService {
  static const String _keyGemini = 'gemini_api_key';
  static const String _keyModel = 'gemini_model';
  static const String _keyPrompt = 'gemini_prompt';

  /// 기본 모델. 빌드 시 `GEMINI_MODEL` 로 덮어쓸 수 있다.
  static const String defaultModel = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-3.5-flash-lite',
  );

  /// 빌드 시 주입되는 기본 API 키.
  ///
  /// 키는 소스에 하드코딩하지 않는다 (GitHub push protection 차단 대상이자 보안 사고 원인).
  /// `secrets/gemini.json` 을 만들고 `tool/build_web.sh` 로 빌드하면
  /// `--dart-define-from-file` 로 이 값이 주입된다.
  /// 주입되지 않은 빌드는 사용자가 앱 안 'AI 설정' 에서 키를 지정해야 한다.
  static const String defaultApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );

  // ── API 키 ──
  static Future<void> saveGeminiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyGemini, key.trim());
  }

  static Future<String?> getGeminiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString(_keyGemini);
    if (key == null || key.isEmpty) return null;
    return key;
  }

  static Future<bool> hasGeminiKey() async {
    final key = await getGeminiKey();
    if (key != null && key.length > 10) return true;
    // 내장 기본 키가 있으면 별도 설정 없이도 사용 가능하다.
    return defaultApiKey.length > 10;
  }

  /// 실제 호출에 사용할 키. 저장된 키 → 내장 기본 키 순서로 해석한다.
  static Future<String?> resolveGeminiKey() async {
    final saved = await getGeminiKey();
    if (saved != null && saved.length > 10) return saved;
    if (defaultApiKey.length > 10) return defaultApiKey;
    return null;
  }

  static Future<void> clearGeminiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyGemini);
  }

  /// API 키 마스킹 표시용 (앞 8자 + ***)
  static String maskKey(String key) {
    if (key.length <= 8) return '****';
    return '${key.substring(0, 8)}••••••••••••••••';
  }

  // ── 모델 ──
  static Future<void> saveModel(String model) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyModel, model.trim());
  }

  static Future<String> getModel() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyModel) ?? defaultModel;
  }

  // ── 프롬프트 (null = 기본 프롬프트 사용) ──
  static Future<void> savePrompt(String prompt) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyPrompt, prompt);
  }

  static Future<String?> getCustomPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    final p = prefs.getString(_keyPrompt);
    if (p == null || p.isEmpty) return null;
    return p;
  }

  static Future<void> clearCustomPrompt() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPrompt);
  }
}
