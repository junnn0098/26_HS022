import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/models/app_role.dart';
import '../../shared/ui/app_ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.onSignedIn, super.key});

  final ValueChanged<AppRole> onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _idController = TextEditingController(text: 'admin');
  final _passwordController = TextEditingController(text: '1234');
  AppRole _selectedRole = AppRole.guardian;
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _idController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (!mounted) return;
    setState(() => _loading = false);
    widget.onSignedIn(_selectedRole);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, Color(0xFF765EF2)],
                ),
                borderRadius: BorderRadius.circular(34),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.health_and_safety_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    '카메라 없이,\n가족의 안전을 확인하세요',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      height: 1.18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'WiFi 센싱으로 집 안의 생활 움직임을 해석하고, 필요한 순간 보호자와 어르신에게 맞는 정보를 보여줘요.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.86),
                      height: 1.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          color: Color(0xFFFFE082),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '보호자는 위험 대응, 피보호자는 내 생활 리듬과 위치 공유를 관리해요.',
                            style: TextStyle(
                              color: Colors.white,
                              height: 1.35,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '시작할 모드를 선택하세요',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w900,
                color: AppColors.text,
              ),
            ),
            const SizedBox(height: 10),
            _RoleSelector(
              selectedRole: _selectedRole,
              onChanged: (role) => setState(() => _selectedRole = role),
            ),
            const SizedBox(height: 20),
            if (_selectedRole == AppRole.guardian) ...[
              _LoginField(
                controller: _idController,
                label: '아이디',
                icon: Icons.person_rounded,
              ),
              const SizedBox(height: 12),
              _LoginField(
                controller: _passwordController,
                label: '비밀번호',
                icon: Icons.lock_rounded,
                obscureText: _obscure,
                suffix: IconButton(
                  onPressed: () => setState(() => _obscure = !_obscure),
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ] else
              const SizedBox(height: 18),
            PrimaryButton(
              label: _loading ? '시작하는 중...' : '${_selectedRole.title}로 시작하기',
              icon: Icons.login_rounded,
              onPressed: _loading ? () {} : _signIn,
              color: _selectedRole == AppRole.guardian
                  ? AppColors.primary
                  : AppColors.success,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleSelector extends StatelessWidget {
  const _RoleSelector({required this.selectedRole, required this.onChanged});

  final AppRole selectedRole;
  final ValueChanged<AppRole> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RoleCard(
            role: AppRole.guardian,
            selected: selectedRole == AppRole.guardian,
            icon: Icons.family_restroom_rounded,
            color: AppColors.primary,
            onTap: () => onChanged(AppRole.guardian),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RoleCard(
            role: AppRole.careRecipient,
            selected: selectedRole == AppRole.careRecipient,
            icon: Icons.elderly_rounded,
            color: AppColors.success,
            onTap: () => onChanged(AppRole.careRecipient),
          ),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.role,
    required this.selected,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final AppRole role;
  final bool selected;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.12) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? color : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 14),
            Text(
              role.title,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              role.subtitle,
              style: const TextStyle(
                color: AppColors.muted,
                height: 1.35,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
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
    this.obscureText = false,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool obscureText;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white,
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.primary),
        suffixIcon: suffix,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}
