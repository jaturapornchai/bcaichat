import 'dart:io' show Platform, Process, ProcessStartMode;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  final ValueChanged<AppUser> onLoggedIn;

  const LoginScreen({super.key, required this.onLoggedIn});

  /// Seeded by backend/src/seed.rs (TEST_ACCOUNTS); all five share the
  /// personal group room "แก๊งเพื่อนสนิท 5 คน + BC AI" with BC AI.
  static const List<({String email, String name, String role, String desc})>
  testAccounts = [
    (
      email: 'demo1@bcaichat.local',
      name: 'ก้อง (Demo 1)',
      role: 'เพื่อนสนิท',
      desc: 'สายเที่ยว & ถ่ายรูป — คุยแชทกลุ่มและแชร์อัลบั้มภาพ',
    ),
    (
      email: 'demo2@bcaichat.local',
      name: 'แพร (Demo 2)',
      role: 'เพื่อนสนิท',
      desc: 'สายคาเฟ่ & ชวนกินข้าว — หารค่าข้าวและส่งโพลนัดร้าน',
    ),
    (
      email: 'demo3@bcaichat.local',
      name: 'บอส (Demo 3)',
      role: 'ครอบครัว',
      desc: 'สายแกดเจ็ต & เพลง — ส่งรูป ความทรงจำ และบันทึกส่วนตัว',
    ),
    (
      email: 'demo4@bcaichat.local',
      name: 'มายด์ (Demo 4)',
      role: 'เพื่อนสนิท',
      desc: 'สายดูหนัง & ซีรีส์ — คุยเล่น นัดเจอ และเรียก @ai ช่วยคิด',
    ),
    (
      email: 'demo5@bcaichat.local',
      name: 'ต้น (Demo 5)',
      role: 'ก๊วนกีฬา',
      desc: 'สายวิ่ง & แคมป์ปิ้ง — วางแผนทริปเที่ยวและลิสต์ของฝาก',
    ),
  ];

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController(
    text: 'jead@bcaichat.local',
  );
  final TextEditingController _nameController = TextEditingController(
    text: 'ลุงจืด',
  );
  final TextEditingController _serverUrlController = TextEditingController();

  bool _isLoading = false;
  bool _showServerUrlEditor = false;
  String? _errorMessage;

  static const List<Map<String, String>> _demoAccounts = [
    {
      'email': 'jead@bcaichat.local',
      'name': 'ลุงจืด',
      'role': 'เจ้าของระบบ',
      'desc': 'ดูแลระบบ ตั้งค่าธีมบ้านเชียง ผู้ช่วย AI และข่าวสารแอป',
    },
    {
      'email': 'somchai@bcaichat.local',
      'name': 'สมชาย เพื่อนบ้าน',
      'role': 'เพื่อนบ้าน',
      'desc': 'ชวนคุยเรื่องแถวบ้าน ส่งรูปและไฟล์ถาวรข้ามเครื่อง',
    },
    {
      'email': 'nida@bcaichat.local',
      'name': 'นิดา พี่สาว',
      'role': 'ครอบครัว',
      'desc': 'แชทห้องครอบครัว เก็บรูปถ่ายถาวร และสมุดบันทึก BC',
    },
  ];

  @override
  void initState() {
    super.initState();
    _serverUrlController.text = ApiService.customBaseUrl.isNotEmpty
        ? ApiService.customBaseUrl
        : ApiService.baseUrl;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }

  Future<void> _performLogin({
    required String email,
    required String displayName,
  }) async {
    if (email.trim().isEmpty) {
      setState(() => _errorMessage = 'กรุณากรอกอีเมล Gmail ก่อนเข้าสู่ระบบ');
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final user = await ApiService.instance.loginWithGoogle(
        email: email.trim(),
        displayName: displayName.trim().isEmpty
            ? email.split('@').first
            : displayName.trim(),
      );
      if (!mounted) return;
      widget.onLoggedIn(user);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveServerUrlInline([String? preset]) async {
    if (preset != null) {
      _serverUrlController.text = preset;
    }
    await ApiService.instance.setCustomBaseUrl(
      _serverUrlController.text.trim().isEmpty
          ? null
          : _serverUrlController.text.trim(),
    );
    await ApiService.instance.loadBusinessTheme();
    if (!mounted) return;
    setState(() => _showServerUrlEditor = false);
  }

  // Fade + slide in once; delay staggers hero and card.
  Widget _enter({required Widget child, int delayMs = 0}) {
    final total = 400 + delayMs;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: total),
      curve: Interval(delayMs / total, 1, curve: AppTheme.motionCurve),
      builder: (context, t, c) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 14), child: c),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1F0E0C), Color(0xFF2B1410), Color(0xFF4A1812)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            // Soft radial terracotta glow behind the hero.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: isWide
                          ? const Alignment(-0.6, -0.3)
                          : const Alignment(0, -0.8),
                      radius: 0.9,
                      colors: [
                        AppTheme.brandPrimary.withValues(alpha: 0.16),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isWide ? 24 : 12,
                    vertical: isWide ? 18 : 10,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: isWide ? 1120 : 480),
                    child: isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                flex: 11,
                                child: _enter(child: _buildHeroShowcase()),
                              ),
                              const SizedBox(width: 48),
                              Expanded(
                                flex: 10,
                                child: _enter(
                                  delayMs: 120,
                                  child: _buildLoginCard(wide: true),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            children: [
                              _enter(child: _buildCompactHeroHeader()),
                              const SizedBox(height: 10),
                              _enter(
                                delayMs: 120,
                                child: _buildLoginCard(wide: false),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logoTile(double size, double fontSize) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppTheme.brandGradient,
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: AppTheme.glow(AppTheme.brandPrimary),
      ),
      alignment: Alignment.center,
      child: Text(
        'BC',
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildCompactHeroHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _logoTile(52, 21),
        const SizedBox(width: 14),
        const Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'BC Ai Chat',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
              Text(
                'แชทใช้งานง่าย · ไฟล์ไม่หมดอายุ · ซิงค์ข้ามเครื่องด้วย Gmail',
                style: TextStyle(
                  color: Color(0xFFE7D3CF),
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeroShowcase() {
    const features = [
      (
        Icons.cloud_done_rounded,
        'เก็บรูปและไฟล์ความทรงจำถาวร (Permanent Photo Vault)',
        'เก็บรูปทริปเที่ยว รูปครอบครัว และไฟล์สำคัญถาวรบน MinIO เปิดดูย้อนหลังได้ตลอด ไม่หมดอายุ',
      ),
      (
        Icons.sync_lock_rounded,
        'ซิงค์แชทข้ามเครื่อง 100% ด้วยบัญชี Gmail',
        'สลับใช้มือถือหรือคอมพิวเตอร์เมื่อไหร่ ประวัติแชทและสมุดบันทึก BC ก็มาครบทุกห้องทันที',
      ),
      (
        Icons.folder_special_rounded,
        'แยกห้องแชท ครอบครัว / เพื่อนสนิท / กลุ่ม / เก็บถาวร',
        'จัดระเบียบแชทกับคนที่บ้านและแก๊งเพื่อน พร้อมอัลบั้มรูป โพลชวนโหวต และการ์ดนัดเจอ',
      ),
      (
        Icons.dashboard_customize_rounded,
        'เครื่องมือสนุกในแชท + ผู้ช่วย BC AI ส่วนตัว',
        'ชวนหารค่าข้าว จัดทริปเที่ยว ลิสต์ของฝาก ส่งการ์ดชวนนัดเจอ และเรียก @ai ช่วยคิดได้ทันที',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _logoTile(58, 23),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'BC Ai Chat',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                        ),
                      ),
                      Container(
                        height: 24,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: AppTheme.brandPrimary.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: AppTheme.goldClay.withValues(alpha: 0.6),
                          ),
                        ),
                        // widthFactor keeps the pill hugging its label
                        // instead of stretching across the hero column.
                        child: const Center(
                          widthFactor: 1,
                          child: Text(
                            'Ban Chiang Heritage · Cloud Vault',
                            style: TextStyle(
                              color: AppTheme.goldClay,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'แชทส่วนตัว ครอบครัว และแก๊งเพื่อนสไตล์ไทยร่วมสมัย ใช้งานง่ายบนมือถือตั้งแต่ครั้งแรก',
                    style: TextStyle(
                      color: Color(0xFFE7D3CF),
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ...features.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppTheme.brandPrimary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                    child: Icon(
                      item.$1,
                      color: AppTheme.goldClay,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.$2,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.$3,
                          style: const TextStyle(
                            color: Color(0xFFCBD5E1),
                            fontSize: 12.5,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard({required bool wide}) {
    return Container(
      padding: EdgeInsets.all(wide ? 20 : 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        boxShadow: AppTheme.shadowLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.brandSoft,
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
                child: Icon(
                  Icons.verified_user_rounded,
                  color: AppTheme.brandPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'เข้าสู่ระบบด้วยบัญชี Gmail',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.slateDark,
                        height: 1.3,
                      ),
                    ),
                    Text(
                      'ไม่ต้องจำรหัสผ่าน ซิงค์ประวัติแชทและไฟล์อัตโนมัติ',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.slateMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AppTheme.dangerRed,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.dangerRed,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Primary Google Sign-In Button (logs in directly with inline form — no extra popup)
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () => _performLogin(
                      email: _emailController.text,
                      displayName: _nameController.text,
                    ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.slateDark,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'G',
                      style: TextStyle(
                        color: Color(0xFFEA4335),
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Flexible(
                    child: Text(
                      'เข้าสู่ระบบด้วย Google (Gmail)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Expanded(child: Divider(height: 1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'หรือกรอก Gmail เข้าใช้งานทันที',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: AppTheme.slateMuted.withValues(alpha: 0.9),
                  ),
                ),
              ),
              const Expanded(child: Divider(height: 1)),
            ],
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'บัญชี Gmail ส่วนตัว',
              prefixIcon: Icon(Icons.alternate_email_rounded, size: 18),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'ชื่อที่แสดงในห้องแชท',
              prefixIcon: Icon(Icons.badge_outlined, size: 18),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _isLoading
                  ? null
                  : () => _performLogin(
                      email: _emailController.text,
                      displayName: _nameController.text,
                    ),
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.arrow_forward_rounded, size: 18),
              label: Text(
                _isLoading
                    ? 'กำลังซิงค์ข้อมูลแชท...'
                    : 'เข้าสู่ระบบ BC Ai Chat',
              ),
            ),
          ),

          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _isLoading
                ? null
                : () => setState(
                    () => _showServerUrlEditor = !_showServerUrlEditor,
                  ),
            icon: const Icon(Icons.dns_rounded, size: 16),
            label: Text(
              'Server URL: ${ApiService.baseUrl}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_showServerUrlEditor) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceBg,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'ค่าเริ่มต้น: ${ApiService.defaultBaseUrl}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.slateMuted,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _serverUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Backend Base URL',
                      hintText: 'http://127.0.0.1:8096',
                      prefixIcon: Icon(Icons.dns_rounded, size: 18),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ActionChip(
                        label: const Text('เครื่องนี้ (:8096)'),
                        onPressed: () =>
                            _saveServerUrlInline('http://127.0.0.1:8096'),
                      ),
                      ActionChip(
                        label: const Text('Android Emulator'),
                        onPressed: () =>
                            _saveServerUrlInline('http://10.0.2.2:8096'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () async {
                          _serverUrlController.text = ApiService.defaultBaseUrl;
                          await ApiService.instance.setCustomBaseUrl(null);
                          await ApiService.instance.loadBusinessTheme();
                          if (!mounted) return;
                          setState(() => _showServerUrlEditor = false);
                        },
                        child: const Text('คืนค่าเริ่มต้น'),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton(
                        onPressed: () => _saveServerUrlInline(),
                        child: const Text('บันทึก URL'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.bolt_rounded, size: 18, color: AppTheme.brandPrimary),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Quick Demo Login (คลิกเดียวสลับบัญชีทดสอบ)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.slateDark,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          ..._demoAccounts.map((acc) {
            final email = acc['email']!;
            final name = acc['name']!;
            final role = acc['role']!;
            return _DemoAccountTile(
              name: name,
              role: role,
              email: email,
              desc: acc['desc']!,
              onTap: _isLoading
                  ? null
                  : () {
                      _emailController.text = email;
                      _nameController.text = name;
                      _performLogin(email: email, displayName: name);
                    },
            );
          }),
          const SizedBox(height: 18),
          _buildTestChatSection(),
        ],
      ),
    );
  }

  // Only the desktop exe can relaunch itself as extra windows.
  bool get _canOpenTestWindows =>
      defaultTargetPlatform == TargetPlatform.windows;

  Future<void> _openTestChatWindows() async {
    try {
      for (var i = 0; i < LoginScreen.testAccounts.length; i++) {
        await Process.start(Platform.resolvedExecutable, [
          '--test-login=${LoginScreen.testAccounts[i].email}',
          '--test-slot=$i',
        ], mode: ProcessStartMode.detached);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = 'เปิดหน้าต่างทดสอบไม่สำเร็จ: $e');
    }
  }

  Widget _buildTestChatSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(Icons.groups_rounded, size: 18, color: AppTheme.brandPrimary),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                '5 บัญชี Demo แก๊งเพื่อน & ครอบครัว + BC AI',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slateDark,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'ทั้ง 5 คนอยู่ใน "แก๊งเพื่อนสนิท 5 คน + BC AI" ลองส่งข้อความ รูปภาพ ไฟล์ เสียง โพล ชวนนัดเจอ และพิมพ์ @ai ได้เลย',
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.slateMuted,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 10),
        if (_canOpenTestWindows) ...[
          FilledButton.icon(
            onPressed: _isLoading ? null : _openTestChatWindows,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('เปิด 5 หน้าต่าง Demo คุยกันทันที'),
          ),
          const SizedBox(height: 10),
        ],
        ...LoginScreen.testAccounts.map(
          (acc) => _DemoAccountTile(
            name: acc.name,
            role: acc.role,
            email: acc.email,
            desc: acc.desc,
            onTap: _isLoading
                ? null
                : () {
                    _emailController.text = acc.email;
                    _nameController.text = acc.name;
                    _performLogin(email: acc.email, displayName: acc.name);
                  },
          ),
        ),
      ],
    );
  }
}

class _DemoAccountTile extends StatefulWidget {
  final String name;
  final String role;
  final String email;
  final String desc;
  final VoidCallback? onTap;

  const _DemoAccountTile({
    required this.name,
    required this.role,
    required this.email,
    required this.desc,
    required this.onTap,
  });

  @override
  State<_DemoAccountTile> createState() => _DemoAccountTileState();
}

class _DemoAccountTileState extends State<_DemoAccountTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final isAdmin =
        widget.role.contains('เจ้าของระบบ') ||
        widget.role.contains('ผู้ดูแล') ||
        widget.role.contains('Admin');
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: widget.onTap == null
            ? SystemMouseCursors.basic
            : SystemMouseCursors.click,
        child: AnimatedContainer(
          duration: AppTheme.motionFast,
          curve: AppTheme.motionCurve,
          decoration: BoxDecoration(
            color: _hover ? AppTheme.brandSoft : AppTheme.surfaceBg,
            borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            border: Border.all(
              color: _hover
                  ? AppTheme.brandPrimary.withValues(alpha: 0.5)
                  : AppTheme.borderSubtle,
            ),
            boxShadow: _hover ? AppTheme.shadowSm : const [],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    UserAvatar(name: widget.name, radius: 16, showOnline: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  widget.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.slateDark,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              PillBadge(
                                text: widget.role,
                                backgroundColor: isAdmin
                                    ? AppTheme.brandSoft
                                    : const Color(0xFFE0E7FF),
                                textColor: isAdmin
                                    ? AppTheme.brandDeep
                                    : AppTheme.workBlue,
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.email} · ${widget.desc}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: AppTheme.slateMuted,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: AppTheme.slateMuted,
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
