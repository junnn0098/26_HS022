part of '../main.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _idCtrl = TextEditingController(text: 'guardian');
  final _pwCtrl = TextEditingController(text: '1234');
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _idCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    await Future.delayed(const Duration(milliseconds: 450));

    final id = _idCtrl.text.trim().toLowerCase();
    final password = _pwCtrl.text;
    final validAccount =
        password == '1234' &&
        (id == 'guardian' || id == 'admin' || id == 'protector');

    if (validAccount) {
      AppState.signedInGuardianName = _primaryGuardian()?.name ?? '김주환 보호자';
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const MainScreen()));
      return;
    }

    setState(() {
      _loading = false;
      _error = '아이디 또는 비밀번호가 올바르지 않습니다.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 300,
                width: double.infinity,
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(32),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF5C7CFF), Color(0xFF7659E8)],
                  ),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -28,
                      top: -42,
                      child: Container(
                        width: 136,
                        height: 136,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.verified_user_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          '카메라 없이,\n가족의 안전을 확인하세요',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            height: 1.18,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '착용 기기 없이 집 안의 위험 징후를 감지해요.',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                        const SizedBox(height: 18),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Row(
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Color(0xFFFFDF6E),
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '낙상 · 장시간 무반응 · 외부인 침입\n위험할 때 보호자에게 바로 알려드려요.',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                '보호자 로그인',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '등록된 보호자 계정으로 시작하세요.',
                style: TextStyle(color: _textMuted),
              ),
              const SizedBox(height: 22),
              _LoginField(
                controller: _idCtrl,
                label: '아이디',
                icon: Icons.person_rounded,
              ),
              const SizedBox(height: 14),
              _LoginField(
                controller: _pwCtrl,
                label: '비밀번호',
                icon: Icons.lock_rounded,
                obscureText: _obscure,
                trailing: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    color: _textMuted,
                  ),
                ),
                onSubmitted: (_) => _login(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: _danger,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '로그인',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: _softCard(color: _primaryLight, radius: 18),
                child: const Row(
                  children: [
                    Icon(Icons.shield_rounded, color: _primary),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '사생활을 침해하지 않는 안전 확인\n카메라 없이 집 안 위험 신호를 살펴요.',
                        style: TextStyle(
                          color: _primaryDark,
                          height: 1.4,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_kDemoMode) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: _softCard(
                    color: const Color(0xFFFFF7ED),
                    radius: 18,
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.key_rounded, color: _warning),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '발표용 계정  ID guardian · PW 1234\n실사용 모드에서는 보호자 계정만 보이게 숨겨져요.',
                          style: TextStyle(
                            color: _textPrimary,
                            height: 1.35,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LoginField extends StatelessWidget {
  const _LoginField({
    required this.controller,
    required this.label,
    required this.icon,
    this.trailing,
    this.obscureText = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final Widget? trailing;
  final bool obscureText;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: _primary),
        suffixIcon: trailing,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: _border),
        ),
      ),
    );
  }
}
