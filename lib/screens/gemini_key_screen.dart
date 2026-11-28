import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../services/api_key_service.dart';
import '../services/gemini_ocr_service.dart';
import '../theme/app_theme.dart';

/// Gemini API 키 / 모델 / 프롬프트 설정 화면
class GeminiKeyScreen extends StatefulWidget {
  const GeminiKeyScreen({super.key});

  @override
  State<GeminiKeyScreen> createState() => _GeminiKeyScreenState();
}

class _GeminiKeyScreenState extends State<GeminiKeyScreen> {
  final _keyCtrl = TextEditingController();
  final _customModelCtrl = TextEditingController();

  bool _obscure = true;
  bool _isSaving = false;
  bool _isTesting = false;
  String? _currentKey;
  String? _testResult;
  bool _testSuccess = false;

  // 모델
  String _selectedModel = ApiKeyService.defaultModel;
  bool _useCustomModel = false;

  // 프롬프트
  String? _customPrompt;
  bool _hasCustomPrompt = false;

  // Google API에서 사용 가능한 모델 목록
  // 실제 API 의 models 목록으로 검증한 값들 (2026-08 기준)
  static const List<String> _modelOptions = [
    'gemini-3.5-flash-lite',
    'gemini-3.5-flash',
    'gemini-3.6-flash',
    'gemini-3.1-flash-lite',
    'gemini-3.1-pro-preview',
    'gemini-3-flash-preview',
    'gemini-2.5-flash-lite',
    'gemini-2.5-flash',
    'gemini-2.5-pro',
    'gemini-flash-latest',
    'gemini-flash-lite-latest',
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _customModelCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final key = await ApiKeyService.getGeminiKey();
    final model = await ApiKeyService.getModel();
    final customPrompt = await ApiKeyService.getCustomPrompt();

    final isCustomModel = !_modelOptions.contains(model);

    setState(() {
      _currentKey = key;
      _selectedModel = isCustomModel ? ApiKeyService.defaultModel : model;
      _useCustomModel = isCustomModel;
      if (isCustomModel) _customModelCtrl.text = model;
      _customPrompt = customPrompt;
      _hasCustomPrompt = customPrompt != null;
    });
  }

  // ── API 키 저장 ──
  Future<void> _saveKey() async {
    final key = _keyCtrl.text.trim();
    if (key.isEmpty) {
      _showSnack('API 키를 입력해주세요.', isError: true);
      return;
    }
    if (!key.startsWith('AIza') && !key.startsWith('AQ.')) {
      _showSnack('올바른 Gemini API 키 형식이 아닙니다.', isError: true);
      return;
    }
    setState(() => _isSaving = true);
    await ApiKeyService.saveGeminiKey(key);
    setState(() {
      _isSaving = false;
      _currentKey = key;
      _keyCtrl.clear();
    });
    _showSnack('✅ API 키가 저장되었습니다!');
  }

  Future<void> _deleteKey() async {
    final confirm = await _confirm('API 키 삭제', '저장된 API 키를 삭제하시겠습니까?');
    if (confirm != true) return;
    await ApiKeyService.clearGeminiKey();
    setState(() {
      _currentKey = null;
      _testResult = null;
    });
    _showSnack('API 키가 삭제되었습니다.');
  }

  // ── 연결 테스트 ──
  Future<void> _testKey() async {
    final key =
        _keyCtrl.text.trim().isNotEmpty ? _keyCtrl.text.trim() : _currentKey;
    if (key == null || key.isEmpty) {
      _showSnack('먼저 API 키를 입력해주세요.', isError: true);
      return;
    }
    setState(() {
      _isTesting = true;
      _testResult = null;
    });
    try {
      final result = await _pingGeminiApi(key, _effectiveModel);
      setState(() {
        _isTesting = false;
        _testSuccess = result;
        _testResult = result
            ? '✅ API 키가 유효합니다! 스캔 기능을 사용할 수 있습니다.'
            : '❌ API 키가 유효하지 않거나 선택한 모델을 사용할 수 없습니다.';
      });
    } catch (e) {
      setState(() {
        _isTesting = false;
        _testSuccess = false;
        _testResult = '❌ 연결 오류: $e';
      });
    }
  }

  Future<bool> _pingGeminiApi(String key, String model) async {
    try {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$key',
      );
      final body = '{"contents":[{"parts":[{"text":"hi"}]}],'
          '"generationConfig":{"maxOutputTokens":10}}';
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 15));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── 모델 저장 ──
  String get _effectiveModel =>
      _useCustomModel ? _customModelCtrl.text.trim() : _selectedModel;

  Future<void> _saveModel() async {
    final model = _effectiveModel;
    if (model.isEmpty) {
      _showSnack('모델명을 입력해주세요.', isError: true);
      return;
    }
    await ApiKeyService.saveModel(model);
    _showSnack('✅ 모델이 저장되었습니다: $model');
  }

  // ── 프롬프트 편집 화면으로 이동 ──
  Future<void> _openPromptEditor() async {
    // 현재 프롬프트 (커스텀 or 기본)
    final defaultPrompt = GeminiOcrService().getDefaultPrompt();
    final current = _customPrompt ?? defaultPrompt;

    final result = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) => _PromptEditorScreen(
          initialPrompt: current,
          defaultPrompt: defaultPrompt,
        ),
      ),
    );

    if (result == null) return; // 취소

    if (result.isEmpty) {
      // 기본값으로 초기화
      await ApiKeyService.clearCustomPrompt();
      setState(() {
        _customPrompt = null;
        _hasCustomPrompt = false;
      });
      _showSnack('✅ 프롬프트가 기본값으로 초기화되었습니다.');
    } else {
      await ApiKeyService.savePrompt(result);
      setState(() {
        _customPrompt = result;
        _hasCustomPrompt = true;
      });
      _showSnack('✅ 프롬프트가 저장되었습니다.');
    }
  }

  // ── UI 헬퍼 ──
  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? AppColors.warning : AppColors.accent,
    ));
  }

  Future<bool?> _confirm(String title, String content) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('취소')),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('삭제'),
            ),
          ],
        ),
      );

  // ─────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('AI 설정'),
        backgroundColor: AppColors.background,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── API 키 섹션 ──
            _sectionTitle('🔑 API 키'),
            const SizedBox(height: 10),
            _buildStepGuide(),
            const SizedBox(height: 14),
            if (_currentKey != null) _buildCurrentKeyCard(),
            const SizedBox(height: 10),
            _buildKeyInputSection(),
            if (_testResult != null) ...[
              const SizedBox(height: 10),
              _buildTestResultCard(),
            ],

            const SizedBox(height: 28),

            // ── 모델 선택 섹션 ──
            _sectionTitle('🤖 모델 선택'),
            const SizedBox(height: 6),
            _buildModelSection(),

            const SizedBox(height: 28),

            // ── 프롬프트 섹션 ──
            _sectionTitle('📝 OCR 프롬프트'),
            const SizedBox(height: 6),
            _buildPromptSection(),

            const SizedBox(height: 28),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      );

  // ── API 키 발급 가이드 ──
  Widget _buildStepGuide() {
    final steps = [
      ('1', 'aistudio.google.com 접속'),
      ('2', 'Google 계정으로 로그인'),
      ('3', '"Get API Key" 클릭'),
      ('4', '"Create API key" 버튼 클릭'),
      ('5', '생성된 키를 아래에 붙여넣기'),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('API 키 발급 방법',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(const ClipboardData(
                      text: 'https://aistudio.google.com/app/apikey'));
                  _showSnack('URL이 복사되었습니다!');
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('URL 복사',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...steps.map((step) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(step.$1,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(step.$2,
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                                height: 1.4))),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildCurrentKeyCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              color: AppColors.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('저장된 API 키',
                    style: TextStyle(fontSize: 12, color: AppColors.textHint)),
                Text(
                  ApiKeyService.maskKey(_currentKey!),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent,
                      fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                color: AppColors.error, size: 20),
            onPressed: _deleteKey,
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _buildKeyInputSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _currentKey != null ? '새 API 키로 변경' : 'API 키 입력',
          style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _keyCtrl,
          obscureText: _obscure,
          style: const TextStyle(
              fontFamily: 'monospace', fontSize: 13, letterSpacing: 0.5),
          decoration: InputDecoration(
            hintText: 'AIzaSy...',
            prefixIcon:
                const Icon(Icons.key_outlined, color: AppColors.textHint),
            suffixIcon: IconButton(
              icon: Icon(
                  _obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.textHint),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _isTesting ? null : _testKey,
                icon: _isTesting
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.secondary))
                    : const Icon(Icons.wifi_tethering, size: 18),
                label: Text(_isTesting ? '테스트 중...' : '연결 테스트'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.secondary,
                  side: const BorderSide(color: AppColors.secondary),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveKey,
                icon: _isSaving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_outlined, size: 18),
                label: Text(_isSaving ? '저장 중...' : '저장하기'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTestResultCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _testSuccess
            ? AppColors.accent.withValues(alpha: 0.06)
            : AppColors.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _testSuccess
              ? AppColors.accent.withValues(alpha: 0.25)
              : AppColors.error.withValues(alpha: 0.25),
        ),
      ),
      child: Text(_testResult!,
          style: TextStyle(
              fontSize: 13,
              color: _testSuccess ? AppColors.accent : AppColors.error,
              height: 1.4)),
    );
  }

  // ── 모델 선택 섹션 ──
  Widget _buildModelSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 드롭다운
          DropdownButtonFormField<String>(
            initialValue: _useCustomModel ? null : _selectedModel,
            decoration: const InputDecoration(
              labelText: '모델 선택',
              prefixIcon:
                  Icon(Icons.auto_awesome_outlined, color: AppColors.primary),
              isDense: true,
            ),
            hint: const Text('직접 입력'),
            items: _modelOptions
                .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() {
                  _selectedModel = v;
                  _useCustomModel = false;
                  _customModelCtrl.clear();
                });
              }
            },
          ),

          const SizedBox(height: 12),

          // 직접 입력 토글
          Row(
            children: [
              Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: _useCustomModel,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setState(() => _useCustomModel = v),
                ),
              ),
              const SizedBox(width: 6),
              const Text('직접 모델명 입력',
                  style:
                      TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),

          if (_useCustomModel) ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: _customModelCtrl,
              decoration: const InputDecoration(
                hintText: '예: gemini-2.5-pro-latest',
                isDense: true,
                prefixIcon:
                    Icon(Icons.edit_outlined, color: AppColors.textHint),
              ),
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
            ),
          ],

          const SizedBox(height: 12),

          // 현재 적용 모델 표시
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 14, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '현재 설정: $_effectiveModel',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        fontFamily: 'monospace'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveModel,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('모델 저장'),
            ),
          ),
        ],
      ),
    );
  }

  // ── 프롬프트 섹션 ──
  Widget _buildPromptSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _hasCustomPrompt ? '커스텀 프롬프트 사용 중' : '기본 프롬프트 사용 중',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _hasCustomPrompt
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _hasCustomPrompt
                          ? '직접 수정한 프롬프트로 OCR을 수행합니다.'
                          : '앱에 내장된 기본 프롬프트로 OCR을 수행합니다.',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textHint),
                    ),
                  ],
                ),
              ),
              if (_hasCustomPrompt)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('커스텀',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _openPromptEditor,
              icon: const Icon(Icons.edit_note_outlined, size: 20),
              label: const Text('프롬프트 편집하기'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────
// 프롬프트 편집 전체 화면
// ─────────────────────────────────────────────────────
class _PromptEditorScreen extends StatefulWidget {
  final String initialPrompt;
  final String defaultPrompt;

  const _PromptEditorScreen({
    required this.initialPrompt,
    required this.defaultPrompt,
  });

  @override
  State<_PromptEditorScreen> createState() => _PromptEditorScreenState();
}

class _PromptEditorScreenState extends State<_PromptEditorScreen> {
  late TextEditingController _ctrl;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialPrompt);
    _ctrl.addListener(() {
      final changed = _ctrl.text != widget.initialPrompt;
      if (changed != _hasChanges) setState(() => _hasChanges = changed);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    if (!_hasChanges) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('변경사항 취소'),
        content: const Text('저장하지 않은 변경사항이 있습니다. 나가시겠습니까?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('계속 편집')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('나가기')),
        ],
      ),
    );
    return result ?? false;
  }

  void _resetToDefault() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('기본값으로 초기화'),
        content: const Text('프롬프트를 앱 기본값으로 초기화하시겠습니까?\n현재 작성 내용은 모두 사라집니다.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
            child: const Text('초기화'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      _ctrl.text = widget.defaultPrompt;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          final ok = await _onWillPop();
          if (ok && context.mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          title: const Text('프롬프트 편집'),
          actions: [
            TextButton(
              onPressed: _resetToDefault,
              child: const Text('기본값',
                  style: TextStyle(color: AppColors.textHint, fontSize: 13)),
            ),
            TextButton(
              onPressed: () {
                // 빈 string → 기본값 초기화 신호
                if (_ctrl.text.trim().isEmpty) {
                  Navigator.pop(context, '');
                } else {
                  Navigator.pop(context, _ctrl.text);
                }
              },
              child: const Text('저장',
                  style: TextStyle(
                      color: AppColors.accent,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        body: Column(
          children: [
            // 안내 배너
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppColors.primary.withValues(alpha: 0.06),
              child: const Text(
                '💡 이 프롬프트로 Gemini API를 호출합니다. 수정 후 저장하면 바로 적용됩니다.\n"기본값" 버튼으로 언제든 원래대로 되돌릴 수 있습니다.',
                style: TextStyle(
                    fontSize: 12, color: AppColors.textSecondary, height: 1.5),
              ),
            ),
            // 변경 표시
            if (_hasChanges)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                color: AppColors.warning.withValues(alpha: 0.12),
                child: const Text(
                  '⚠️ 저장되지 않은 변경사항이 있습니다.',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.warning,
                      fontWeight: FontWeight.w600),
                ),
              ),
            // 텍스트 편집 영역
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: TextField(
                  controller: _ctrl,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    fontFamily: 'monospace',
                    color: AppColors.textPrimary,
                  ),
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.all(14),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: '프롬프트를 입력하세요...',
                  ),
                ),
              ),
            ),
            // 하단 저장 버튼
            Padding(
              padding: EdgeInsets.fromLTRB(
                  12, 0, 12, MediaQuery.of(context).padding.bottom + 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    if (_ctrl.text.trim().isEmpty) {
                      Navigator.pop(context, '');
                    } else {
                      Navigator.pop(context, _ctrl.text);
                    }
                  },
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('저장하기'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
