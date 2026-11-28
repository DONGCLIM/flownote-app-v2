import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/receipt_provider.dart';
import '../theme/app_theme.dart';
import '../models/user_model.dart';
import 'login_screen.dart';
import 'insight/insight_hub.dart';
import 'paywall_screen.dart';
import 'settlement/settlement_screen.dart';
import '../services/subscription_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().currentUser;
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildHeader(user),
              _buildScanPlanCard(context, user),
              const SizedBox(height: 16),
              _buildBusinessInfoSection(context, user),
              const SizedBox(height: 16),
              _buildStatsSection(context),
              const SizedBox(height: 16),
              _buildSettingsSection(context),
              const SizedBox(height: 90),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(UserModel user) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.2),
                  AppColors.secondary.withValues(alpha: 0.15),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Center(
              child: Text(
                user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  user.email,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: user.effectiveUnlimited
                        ? AppColors.accent.withValues(alpha: 0.12)
                        : AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    user.effectiveUnlimited ? '🌟 무제한 플랜' : '🌱 무료 플랜',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: user.effectiveUnlimited
                          ? AppColors.accent
                          : AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanPlanCard(BuildContext context, UserModel user) {
    final remaining = user.remainingScans;
    final isUnlimited = user.effectiveUnlimited;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '스캔 현황',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (!isUnlimited)
                  GestureDetector(
                    onTap: () async {
                      await context.read<AuthProvider>().unlockUnlimited();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('🎉 무제한 스캔이 활성화되었습니다!'),
                            backgroundColor: AppColors.accent,
                          ),
                        );
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.primaryLight],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '업그레이드',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (isUnlimited)
              const Row(
                children: [
                  Icon(
                    Icons.all_inclusive_rounded,
                    color: AppColors.accent,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    '무제한으로 스캔할 수 있습니다',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              )
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '사용: ${user.scanCount}회',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    '남은 횟수: $remaining회',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: remaining <= 5
                          ? AppColors.error
                          : remaining <= 10
                              ? AppColors.warning
                              : AppColors.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  value: user.scanUsagePercent,
                  backgroundColor: AppColors.border,
                  valueColor: AlwaysStoppedAnimation(
                    remaining <= 5
                        ? AppColors.error
                        : remaining <= 10
                            ? AppColors.warning
                            : AppColors.accent,
                  ),
                  minHeight: 7,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBusinessInfoSection(BuildContext context, UserModel user) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.store_rounded,
                      size: 18, color: AppColors.primary),
                ),
                const SizedBox(width: 10),
                const Text(
                  '내 사업장 정보',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => _showBusinessInfoEditor(context, user),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.2)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_outlined,
                            size: 14, color: AppColors.primary),
                        SizedBox(width: 4),
                        Text(
                          '편집',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.divider),
          if (!user.hasBusinessInfo)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text('🏪',
                      style: TextStyle(fontSize: 32)),
                  const SizedBox(height: 10),
                  const Text(
                    '사업장 정보를 등록하면\n내보내기 리포트에 자동으로 포함됩니다',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () => _showBusinessInfoEditor(context, user),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '정보 입력하기',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _bizInfoRow(Icons.store_outlined, '상호명', user.businessName),
                  _bizInfoRow(Icons.numbers_outlined, '사업자번호',
                      _formatBizNumber(user.businessNumber)),
                  _bizInfoRow(Icons.person_outline_rounded, '대표자', user.ownerName),
                  _bizInfoRow(Icons.location_on_outlined, '주소', user.businessAddress),
                  if (user.phoneNumber.isNotEmpty)
                    _bizInfoRow(Icons.phone_outlined, '전화번호', user.phoneNumber),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _bizInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.textHint),
          const SizedBox(width: 10),
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _formatBizNumber(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 5)}-${digits.substring(5)}';
    }
    return raw;
  }

  void _showBusinessInfoEditor(BuildContext context, UserModel user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _BusinessInfoEditor(user: user),
    );
  }

  Widget _buildStatsSection(BuildContext context) {
    final provider = context.watch<ReceiptProvider>();
    final receipts = provider.allReceipts;
    final totalSpent = receipts.fold(0.0, (s, r) => s + r.totalAmount);
    final fmt = NumberFormat('#,###', 'ko');
    final flowerStats = provider.getFlowerSpending();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '나의 꽃 통계',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _MiniStatCard(
                    label: '총 영수증',
                    value: '${receipts.length}개',
                    emoji: '🧾',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MiniStatCard(
                    label: '총 지출',
                    value: '₩${fmt.format(totalSpent)}',
                    emoji: '💰',
                  ),
                ),
              ],
            ),
            if (flowerStats.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                '자주 구매하는 꽃 TOP 3',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              ...flowerStats.entries.take(3).map((e) {
                final maxVal = flowerStats.values.first;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _FlowerBar(
                    name: e.key,
                    amount: e.value,
                    ratio: e.value / maxVal,
                    fmt: fmt,
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            _SettingsTile(
              icon: Icons.insights_rounded,
              label: '분석 · 관리',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const InsightHubScreen(),
                  ),
                );
              },
            ),
            const Divider(height: 1, indent: 56),
            _SettingsTile(
              icon: Icons.description_outlined,
              label: '정산서 발행',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SettlementScreen(),
                  ),
                );
              },
            ),
            const Divider(height: 1, indent: 56),
            _SettingsTile(
              icon: Icons.workspace_premium_rounded,
              label: SubscriptionService.instance.purchasedPro
                  ? 'PRO 구독 중'
                  : '요금제 안내',
              color: AppColors.primary,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PaywallScreen(),
                  ),
                );
              },
            ),
            // 🔴 'AI 설정' 진입 경로 제거 (사장님 요청).
            //    화면 파일과 저장된 키/프롬프트/모델은 그대로 살아 있다.
            const Divider(height: 1, indent: 56),
            _SettingsTile(
              icon: Icons.notifications_outlined,
              label: '알림 설정',
              onTap: () {},
            ),
            const Divider(height: 1, indent: 56),
            _SettingsTile(
              icon: Icons.help_outline_rounded,
              label: '도움말',
              onTap: () {},
            ),
            const Divider(height: 1, indent: 56),
            _SettingsTile(
              icon: Icons.info_outline_rounded,
              label: '앱 정보',
              trailing: const Text(
                'v1.0.0',
                style: TextStyle(fontSize: 13, color: AppColors.textHint),
              ),
              onTap: () {},
            ),
            const Divider(height: 1, indent: 56),
            _SettingsTile(
              icon: Icons.logout_rounded,
              label: '로그아웃',
              color: AppColors.error,
              onTap: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    title: const Text('로그아웃'),
                    content: const Text('정말 로그아웃하시겠습니까?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('취소'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.error,
                        ),
                        child: const Text('로그아웃'),
                      ),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  await context.read<AuthProvider>().signOut();
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStatCard extends StatelessWidget {
  final String label;
  final String value;
  final String emoji;

  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.emoji,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowerBar extends StatelessWidget {
  final String name;
  final double amount;
  final double ratio;
  final NumberFormat fmt;

  const _FlowerBar({
    required this.name,
    required this.amount,
    required this.ratio,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              name,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '₩${fmt.format(amount)}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: ratio,
            backgroundColor: AppColors.border,
            valueColor: const AlwaysStoppedAnimation(AppColors.accent),
            minHeight: 5,
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final Widget? trailing;

  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textPrimary;
    return ListTile(
      leading: Icon(icon, color: c, size: 22),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 14,
          color: c,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: trailing ?? const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.textHint,
        size: 20,
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
    );
  }
}

// ── 사업자 정보 편집 바텀시트 ──
class _BusinessInfoEditor extends StatefulWidget {
  final UserModel user;
  const _BusinessInfoEditor({required this.user});

  @override
  State<_BusinessInfoEditor> createState() => _BusinessInfoEditorState();
}

class _BusinessInfoEditorState extends State<_BusinessInfoEditor> {
  late final TextEditingController _bizNameCtrl;
  late final TextEditingController _bizNumCtrl;
  late final TextEditingController _ownerCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _phoneCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _bizNameCtrl = TextEditingController(text: widget.user.businessName);
    _bizNumCtrl = TextEditingController(text: widget.user.businessNumber);
    _ownerCtrl = TextEditingController(text: widget.user.ownerName);
    _addressCtrl = TextEditingController(text: widget.user.businessAddress);
    _phoneCtrl = TextEditingController(text: widget.user.phoneNumber);
  }

  @override
  void dispose() {
    _bizNameCtrl.dispose();
    _bizNumCtrl.dispose();
    _ownerCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await context.read<AuthProvider>().updateBusinessInfo(
          businessName: _bizNameCtrl.text.trim(),
          businessNumber: _bizNumCtrl.text.trim(),
          ownerName: _ownerCtrl.text.trim(),
          businessAddress: _addressCtrl.text.trim(),
          phoneNumber: _phoneCtrl.text.trim(),
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 핸들
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  const Text(
                    '내 사업장 정보 편집',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: AppColors.textHint),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _field('상호명 (가게 이름)', _bizNameCtrl,
                      hint: '예: 꽃향기 플라워', icon: Icons.store_outlined),
                  const SizedBox(height: 14),
                  _field('사업자 등록번호', _bizNumCtrl,
                      hint: '예: 123-45-67890',
                      icon: Icons.numbers_outlined,
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 14),
                  _field('대표자 이름', _ownerCtrl,
                      hint: '예: 홍길동', icon: Icons.person_outline_rounded),
                  const SizedBox(height: 14),
                  _field('사업장 주소', _addressCtrl,
                      hint: '예: 서울시 마포구 꽃길로 123',
                      icon: Icons.location_on_outlined,
                      maxLines: 2),
                  const SizedBox(height: 14),
                  _field('전화번호 (선택)', _phoneCtrl,
                      hint: '예: 02-1234-5678',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text(
                              '저장하기',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          keyboardType: keyboardType,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 18, color: AppColors.textHint),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          ),
        ),
      ],
    );
  }
}
