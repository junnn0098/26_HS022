import 'package:flutter/material.dart';

import '../../app/app_theme.dart';
import '../../core/state/safety_controller.dart';
import '../alerts/alerts_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../home_map/home_map_screen.dart';
import '../settings/settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    required this.controller,
    required this.onSwitchRole,
    super.key,
  });

  final SafetyController controller;
  final VoidCallback onSwitchRole;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(
        controller: widget.controller,
        onOpenMap: () => setState(() => _index = 1),
        onOpenAlerts: () => setState(() => _index = 2),
        onOpenSettings: () => setState(() => _index = 3),
      ),
      HomeMapScreen(controller: widget.controller),
      AlertsScreen(controller: widget.controller),
      SettingsScreen(controller: widget.controller),
    ];

    return Scaffold(
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: KeyedSubtree(key: ValueKey(_index), child: screens[_index]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'switch-to-care-recipient',
        onPressed: widget.onSwitchRole,
        icon: const Icon(Icons.swap_horiz_rounded),
        label: const Text('피보호자 모드'),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryDark.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          child: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (value) => setState(() => _index = value),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: '홈',
              ),
              NavigationDestination(
                icon: Icon(Icons.grid_view_outlined),
                selectedIcon: Icon(Icons.grid_view_rounded),
                label: '집 안',
              ),
              NavigationDestination(
                icon: Icon(Icons.notifications_none_rounded),
                selectedIcon: Icon(Icons.notifications_rounded),
                label: '알림',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: '설정',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
