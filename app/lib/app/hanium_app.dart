import 'dart:async';

import 'package:flutter/material.dart';

import '../core/models/app_role.dart';
import '../core/services/local_safety_cache.dart';
import '../core/services/notification_service.dart';
import '../core/services/safety_repository.dart';
import '../core/state/safety_controller.dart';
import '../features/auth/login_screen.dart';
import '../features/care_recipient/care_recipient_screen.dart';
import '../features/shell/main_shell.dart';
import 'app_theme.dart';

class HaniumApp extends StatefulWidget {
  // 테스트에서는 네트워크·Firebase·파일 캐시 대신 가짜 구현을 넣을 수 있다.
  const HaniumApp({
    this.repository,
    this.cache,
    this.notificationService,
    super.key,
  });

  final SafetyRepository? repository;
  final LocalSafetyCache? cache;
  final NotificationService? notificationService;

  @override
  State<HaniumApp> createState() => _HaniumAppState();
}

class _HaniumAppState extends State<HaniumApp> {
  late final SafetyRepository _repository;
  late final SafetyController _controller;
  late final NotificationService _notificationService;
  bool _signedIn = false;
  AppRole _role = AppRole.guardian;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? SafetyRepository();
    _controller = SafetyController(_repository, cache: widget.cache);
    _notificationService =
        widget.notificationService ?? NotificationService(_repository);
    _controller.start();
    unawaited(_notificationService.start(role: _role));
  }

  @override
  void dispose() {
    unawaited(_notificationService.dispose());
    _controller.dispose();
    super.dispose();
  }

  void _setRole(AppRole role, {bool signedIn = true}) {
    setState(() {
      _role = role;
      _signedIn = signedIn;
    });
    unawaited(_notificationService.registerRole(role));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final largeTextMode = _controller.snapshot.settingBool(
          'largeTextMode',
          false,
        );
        return MaterialApp(
          title: '한이음 어플',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          builder: (context, child) {
            final media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(
                textScaler: TextScaler.linear(largeTextMode ? 1.34 : 1.0),
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: _signedIn
              ? _role == AppRole.guardian
                    ? MainShell(
                        controller: _controller,
                        onSwitchRole: () => _setRole(AppRole.careRecipient),
                      )
                    : CareRecipientScreen(
                        controller: _controller,
                        onSwitchRole: () => _setRole(AppRole.guardian),
                      )
              : LoginScreen(onSignedIn: (role) => _setRole(role)),
        );
      },
    );
  }
}
