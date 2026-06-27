part of '../main.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeScreen(onOpenHomeStatus: () => setState(() => _index = 1)),
      const HomeStatusScreen(),
      const AlertScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0F172A).withOpacity(0.08),
              blurRadius: 20,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          backgroundColor: Colors.white,
          indicatorColor: _primaryLight,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded, color: _primary),
              label: '홈',
            ),
            NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view_rounded, color: _primary),
              label: '집 안',
            ),
            NavigationDestination(
              icon: Icon(Icons.notifications_none_rounded),
              selectedIcon: Icon(Icons.notifications_rounded, color: _primary),
              label: '알림',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded, color: _primary),
              label: '설정',
            ),
          ],
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onOpenHomeStatus});

  final VoidCallback onOpenHomeStatus;

  @override
  Widget build(BuildContext context) {
    return LiveBuilder(
      builder: (context) {
        final info = _statusInfo(AppState.status);

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HomeHeader(info: info),
                const SizedBox(height: 20),
                _StatusHeroCard(info: info),
                const SizedBox(height: 14),
                _NextActionCard(
                  info: info,
                  onOpenHomeStatus: onOpenHomeStatus,
                  onEmergency: () => _openEmergency(context),
                ),
                const SizedBox(height: 24),
                const Text(
                  '오늘의 안심 요약',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _SummaryCard(info: info),
                const SizedBox(height: 24),
                const Text(
                  '빠른 연락',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _ContactCard(onEmergency: () => _openEmergency(context)),
                const SizedBox(height: 14),
                _InfoStrip(
                  icon: AppState.serverConnected
                      ? Icons.verified_user_rounded
                      : Icons.sync_problem_rounded,
                  title: _connectionTitle(),
                  subtitle: _careStatusDetail(),
                  color: _connectionColor(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.info});

  final StatusInfo info;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '김영희 어르신',
                style: TextStyle(
                  color: _textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                info.title == '이상 징후가 없어요' ? '지금 상태를 확인했어요' : info.title,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _primaryLight,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.person_rounded,
                color: _primary,
                size: 30,
              ),
            ),
            Positioned(
              right: -1,
              top: -1,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: info.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusHeroCard extends StatelessWidget {
  const _StatusHeroCard({required this.info});

  final StatusInfo info;

  @override
  Widget build(BuildContext context) {
    final isDanger = info.color == _danger;
    final isWarning = info.color == _warning;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDanger
              ? const [Color(0xFFFF6178), Color(0xFFFF4E67)]
              : isWarning
                  ? const [Color(0xFFFFBF5E), Color(0xFFF4A62A)]
                  : const [Color(0xFF45D298), Color(0xFF21B77D)],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -24,
            top: -38,
            child: Container(
              width: 128,
              height: 128,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.22),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(info.icon, color: Colors.white, size: 34),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '현재 상태',
                          style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          info.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 23,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                info.subtitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              Divider(color: Colors.white.withOpacity(0.22)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _WhitePill(
                    icon: Icons.location_on_rounded,
                    text:
                        '${_roomDisplayName(AppState.room)} · ${_lastUpdatedText()}',
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _openEmergency(context),
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    child: Text(isDanger ? '긴급 확인' : info.action),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WhitePill extends StatelessWidget {
  const _WhitePill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.info});

  final StatusInfo info;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _softCard(radius: 24),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: info.lightColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(info.icon, color: info.color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _summaryTitle(info),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _summarySubtitle(info),
                      style: const TextStyle(color: _textMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(color: _border),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                '최근 활동',
                style: TextStyle(
                  color: _textMuted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${_roomDisplayName(AppState.room)} → ${_roomDisplayName(AppState.room == '거실' ? '침실' : '거실')} · 12분 전',
                style: const TextStyle(
                  color: _textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({required this.onEmergency});

  final VoidCallback onEmergency;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _softCard(radius: 24),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _primaryLight,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.phone_rounded, color: _primary),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '어르신께 연락이 필요한가요?',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _textPrimary,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '등록된 전화번호로 바로 연결해요.',
                  style: TextStyle(color: _textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
          TextButton(onPressed: onEmergency, child: const Text('전화하기')),
        ],
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _softCard(color: color.withOpacity(0.08), radius: 22),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: _textMuted, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HomeStatusScreen extends StatelessWidget {
  const HomeStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return LiveBuilder(
      builder: (context) {
        final info = _statusInfo(AppState.status);

        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '집 안 상태',
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                              color: _textPrimary,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '김영희 어르신 · 생활 상태 확인',
                            style: TextStyle(color: _textMuted),
                          ),
                        ],
                      ),
                    ),
                    _StatusPill(info: info),
                  ],
                ),
                const SizedBox(height: 18),
                const FloorPlanCard(),
                const SizedBox(height: 18),
                const _ConnectionStatusCard(),
                const SizedBox(height: 14),
                _InfoStrip(
                  icon: Icons.check_circle_rounded,
                  title:
                      '${_roomDisplayName(AppState.room)}에서 ${_poseLabel(AppState.pose)} 상태',
                  subtitle: '안전 확인을 위한 추정 정보예요. 위험 변화가 생기면 바로 알려드려요.',
                  color: info.color,
                ),
                const SizedBox(height: 14),
                _CareGuideCard(info: info),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _poseLabel(String pose) {
  return switch (pose) {
    'lying' => '누워 있는',
    'sitting' => '앉아 있는',
    'walking' => '이동 중인',
    _ => '서 있는',
  };
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.info});

  final StatusInfo info;

  @override
  Widget build(BuildContext context) {
    final color = !AppState.serverConnected ? _warning : info.color;
    final text = !AppState.serverConnected
        ? '확인 중'
        : info.color == _success
            ? '안심 확인'
            : '확인 필요';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, color: color, size: 10),
          const SizedBox(width: 7),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionStatusCard extends StatelessWidget {
  const _ConnectionStatusCard();

  @override
  Widget build(BuildContext context) {
    final connected = AppState.serverConnected;
    final color = _connectionColor();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _softCard(color: color.withOpacity(0.08), radius: 22),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              connected
                  ? Icons.health_and_safety_rounded
                  : Icons.manage_search_rounded,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _connectionTitle(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  connected ? _careStatusSubtitle() : _careStatusDetail(),
                  style: const TextStyle(
                    color: _textMuted,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class FloorPlanCard extends StatelessWidget {
  const FloorPlanCard({super.key});

  @override
  Widget build(BuildContext context) {
    final info = _statusInfo(AppState.status);
    final movementPath = List<Offset>.of(AppState.movementPath);
    final showPath = AppState.settingBool('showPath', true);
    final showSensors = AppState.settingBool('showSensors', true);
    final roomLabels = _roomLabelsForDisplay();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _softCard(radius: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: _primaryLight,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.location_searching_rounded,
                        color: _primary,
                        size: 16,
                      ),
                      SizedBox(width: 6),
                      Text(
                        '현재 위치 중심',
                        style: TextStyle(
                          color: _primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.add_rounded),
                style: IconButton.styleFrom(backgroundColor: _bg),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.menu_rounded),
                style: IconButton.styleFrom(backgroundColor: _bg),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 0.82,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FBFF),
                  border: Border.all(color: _border),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final w = constraints.maxWidth;
                    final h = constraints.maxHeight;
                    final left = (AppState.personX.clamp(0.07, 0.93) * w - 18)
                        .toDouble();
                    final top = (AppState.personY.clamp(0.08, 0.90) * h - 32)
                        .toDouble();

                    return Stack(
                      children: [
                        CustomPaint(
                          painter: FloorPlanPainter(
                            statusColor: info.color,
                            movementPath: movementPath,
                            showPath: showPath,
                            showSensors: showSensors,
                            roomLabels: roomLabels,
                          ),
                          size: Size.infinite,
                        ),
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeOutCubic,
                          left: left,
                          top: top,
                          child: MiniPersonMarker(
                            color: info.color,
                            pose: AppState.pose,
                          ),
                        ),
                        Positioned(
                          left: 16,
                          bottom: 14,
                          child: _MapLegend(color: info.color),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class FloorPlanPainter extends CustomPainter {
  const FloorPlanPainter({
    required this.statusColor,
    required this.movementPath,
    required this.showPath,
    required this.showSensors,
    required this.roomLabels,
  });

  final Color statusColor;
  final List<Offset> movementPath;
  final bool showPath;
  final bool showSensors;
  final Map<String, String> roomLabels;

  @override
  void paint(Canvas canvas, Size size) {
    final wall = Paint()
      ..color = const Color(0xFF3C465A)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final thinWall = Paint()
      ..color = const Color(0xFF3C465A)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    Rect r(double l, double t, double rr, double b) {
      return Rect.fromLTRB(
        size.width * l,
        size.height * t,
        size.width * rr,
        size.height * b,
      );
    }

    void room(Rect rect, Color fill, String label) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()..color = fill,
      );

      final text = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Color(0xFF586176),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      text.paint(canvas, Offset(rect.left + 10, rect.top + 10));
    }

    final outer = r(0.07, 0.07, 0.93, 0.92);
    canvas.drawRRect(
      RRect.fromRectAndRadius(outer, const Radius.circular(6)),
      Paint()..color = Colors.white,
    );

    final living = r(0.07, 0.07, 0.61, 0.56);
    final kitchen = r(0.61, 0.07, 0.93, 0.42);
    final bedroom = r(0.07, 0.56, 0.47, 0.92);
    final bath = r(0.47, 0.56, 0.67, 0.92);
    final entrance = r(0.67, 0.42, 0.93, 0.92);

    room(living, const Color(0xFFEAF3EF), roomLabels['거실'] ?? '거실');
    room(kitchen, const Color(0xFFF5E8C9), roomLabels['주방'] ?? '주방');
    room(bedroom, const Color(0xFFE8F0FF), roomLabels['침실'] ?? '침실');
    room(bath, const Color(0xFFEAF7FB), roomLabels['욕실'] ?? '욕실');
    room(entrance, const Color(0xFFF0E5F8), roomLabels['현관'] ?? '현관');

    canvas.drawRRect(
      RRect.fromRectAndRadius(outer, const Radius.circular(6)),
      wall,
    );
    canvas.drawLine(
      Offset(size.width * 0.61, size.height * 0.07),
      Offset(size.width * 0.61, size.height * 0.92),
      thinWall,
    );
    canvas.drawLine(
      Offset(size.width * 0.07, size.height * 0.56),
      Offset(size.width * 0.67, size.height * 0.56),
      thinWall,
    );
    canvas.drawLine(
      Offset(size.width * 0.67, size.height * 0.42),
      Offset(size.width * 0.93, size.height * 0.42),
      thinWall,
    );
    canvas.drawLine(
      Offset(size.width * 0.47, size.height * 0.56),
      Offset(size.width * 0.47, size.height * 0.92),
      thinWall,
    );
    canvas.drawLine(
      Offset(size.width * 0.67, size.height * 0.42),
      Offset(size.width * 0.67, size.height * 0.92),
      thinWall,
    );

    _drawFurniture(canvas, size);
    if (showPath) _drawRecentPath(canvas, size);
    if (showSensors) _drawSensors(canvas, size);
  }

  void _drawFurniture(Canvas canvas, Size size) {
    RRect rr(
      double l,
      double t,
      double w,
      double h,
      Color color, {
      double radius = 8,
    }) {
      return RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * l,
          size.height * t,
          size.width * w,
          size.height * h,
        ),
        Radius.circular(radius),
      );
    }

    final furniture = Paint()..color = const Color(0xFFB8C9BD);
    final wood = Paint()..color = const Color(0xFFD7C79F);
    final blue = Paint()..color = const Color(0xFFBFD1EF);
    final purple = Paint()..color = const Color(0xFFD6BEE5);
    final line = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..strokeWidth = 2;

    canvas.drawRRect(
      rr(0.12, 0.16, 0.25, 0.08, const Color(0xFFB8C9BD)),
      furniture,
    );
    canvas.drawRRect(rr(0.18, 0.36, 0.16, 0.10, const Color(0xFFD7C79F)), wood);
    canvas.drawCircle(
      Offset(size.width * 0.26, size.height * 0.41),
      8,
      Paint()..color = const Color(0xFFF6EECF),
    );
    canvas.drawCircle(
      Offset(size.width * 0.32, size.height * 0.41),
      8,
      Paint()..color = const Color(0xFFF6EECF),
    );

    canvas.drawRRect(rr(0.67, 0.14, 0.20, 0.10, const Color(0xFFD7C79F)), wood);
    canvas.drawRRect(rr(0.70, 0.26, 0.16, 0.08, const Color(0xFFF1E2BC)), wood);
    canvas.drawCircle(
      Offset(size.width * 0.75, size.height * 0.30),
      9,
      Paint()..color = const Color(0xFFFFF7D7),
    );
    canvas.drawCircle(
      Offset(size.width * 0.82, size.height * 0.30),
      9,
      Paint()..color = const Color(0xFFFFF7D7),
    );

    canvas.drawRRect(rr(0.13, 0.66, 0.25, 0.16, const Color(0xFFBFD1EF)), blue);
    canvas.drawLine(
      Offset(size.width * 0.14, size.height * 0.71),
      Offset(size.width * 0.37, size.height * 0.71),
      line,
    );
    canvas.drawRRect(
      rr(0.52, 0.66, 0.08, 0.13, const Color(0xFFBED8E1)),
      Paint()..color = const Color(0xFFBED8E1),
    );
    canvas.drawCircle(
      Offset(size.width * 0.56, size.height * 0.73),
      9,
      Paint()..color = Colors.white,
    );
    canvas.drawRRect(
      rr(0.73, 0.62, 0.13, 0.18, const Color(0xFFD6BEE5)),
      purple,
    );
  }

  void _drawRecentPath(Canvas canvas, Size size) {
    if (movementPath.length < 2) return;

    final path = movementPath
        .map(
          (point) => Offset(
            size.width * point.dx.clamp(0.07, 0.93).toDouble(),
            size.height * point.dy.clamp(0.07, 0.92).toDouble(),
          ),
        )
        .toList();

    final paint = Paint()
      ..color = _primary.withOpacity(0.45)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    for (var i = 0; i < path.length - 1; i++) {
      _drawDashedLine(canvas, path[i], path[i + 1], paint);
    }

    canvas.drawCircle(path.first, 4, Paint()..color = _primary.withOpacity(0.35));
    canvas.drawCircle(path.last, 5, Paint()..color = statusColor.withOpacity(0.7));
  }

  void _drawSensors(Canvas canvas, Size size) {
    final sensors = [
      Offset(size.width * 0.08, size.height * 0.08),
      Offset(size.width * 0.92, size.height * 0.08),
      Offset(size.width * 0.08, size.height * 0.91),
      Offset(size.width * 0.92, size.height * 0.91),
    ];

    for (final sensor in sensors) {
      canvas.drawCircle(
        sensor,
        10,
        Paint()..color = _success.withOpacity(0.16),
      );
      canvas.drawCircle(sensor, 5, Paint()..color = _success);

      final signal = Paint()
        ..color = _success.withOpacity(0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawArc(
        Rect.fromCircle(center: sensor, radius: 13),
        -1.0,
        1.8,
        false,
        signal,
      );
    }
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    final distance = (b - a).distance;
    final direction = (b - a) / distance;
    const dash = 7.0;
    const gap = 7.0;
    var current = 0.0;

    while (current < distance) {
      final start = a + direction * current;
      final end = a + direction * min(current + dash, distance);
      canvas.drawLine(start, end, paint);
      current += dash + gap;
    }
  }

  @override
  bool shouldRepaint(FloorPlanPainter oldDelegate) {
    if (oldDelegate.statusColor != statusColor ||
        oldDelegate.showPath != showPath ||
        oldDelegate.showSensors != showSensors ||
        oldDelegate.roomLabels.toString() != roomLabels.toString() ||
        oldDelegate.movementPath.length != movementPath.length) {
      return true;
    }

    if (movementPath.isEmpty) return false;
    return oldDelegate.movementPath.isEmpty ||
        oldDelegate.movementPath.last != movementPath.last;
  }
}

class MiniPersonMarker extends StatelessWidget {
  const MiniPersonMarker({required this.color, required this.pose, super.key});

  final Color color;
  final String pose;

  @override
  Widget build(BuildContext context) {
    final lying = pose == 'lying';
    final scale = switch (AppState.settings['miniatureSize']) {
      'small' => 0.86,
      'large' => 1.18,
      _ => 1.0,
    };

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: 8 * scale,
            vertical: 5 * scale,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Text(
            '${_poseLabel(pose)} 상태 · ${_roomDisplayName(AppState.room)}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 10 * scale,
            ),
          ),
        ),
        const SizedBox(height: 4),
        AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          width: (lying ? 42 : 34) * scale,
          height: (lying ? 22 : 46) * scale,
          decoration: BoxDecoration(
            color: color.withOpacity(0.16),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Transform.rotate(
            angle: lying ? pi / 2 : 0,
            child: CustomPaint(painter: PersonPainter(color: color)),
          ),
        ),
      ],
    );
  }
}

class PersonPainter extends CustomPainter {
  PersonPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final head = Paint()..color = color;

    final cx = size.width / 2;
    canvas.drawCircle(Offset(cx, size.height * 0.22), 5, head);
    canvas.drawLine(
      Offset(cx, size.height * 0.34),
      Offset(cx, size.height * 0.62),
      paint,
    );
    canvas.drawLine(
      Offset(cx, size.height * 0.43),
      Offset(cx - 8, size.height * 0.56),
      paint,
    );
    canvas.drawLine(
      Offset(cx, size.height * 0.43),
      Offset(cx + 8, size.height * 0.56),
      paint,
    );
    canvas.drawLine(
      Offset(cx, size.height * 0.62),
      Offset(cx - 8, size.height * 0.82),
      paint,
    );
    canvas.drawLine(
      Offset(cx, size.height * 0.62),
      Offset(cx + 8, size.height * 0.82),
      paint,
    );
  }

  @override
  bool shouldRepaint(PersonPainter oldDelegate) => oldDelegate.color != color;
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _LegendDot(color: color, text: '사람'),
          const SizedBox(width: 12),
          const _LegendDot(color: _success, text: '확인 구역'),
          const SizedBox(width: 12),
          const _LegendDot(color: _primary, text: '최근 이동'),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 10,
            color: _textMuted,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _NextActionCard extends StatelessWidget {
  const _NextActionCard({
    required this.info,
    required this.onOpenHomeStatus,
    required this.onEmergency,
  });

  final StatusInfo info;
  final VoidCallback onOpenHomeStatus;
  final VoidCallback onEmergency;

  @override
  Widget build(BuildContext context) {
    final isDanger = info.color == _danger;
    final hasConcern = info.color != _success;
    final title = isDanger
        ? '먼저 이렇게 확인해 주세요'
        : hasConcern
            ? '잠깐 확인해 주세요'
            : '오늘은 이렇게만 확인하면 돼요';
    final steps = isDanger
        ? const [
            '어르신께 전화 또는 문자로 반응을 확인',
            '집 도면에서 현재 위치와 상태 확인',
            '위험하면 119 신고 정보를 바로 확인',
          ]
        : hasConcern
            ? const [
                '집 도면에서 위치와 이동 흐름 확인',
                '몇 분 뒤 상태가 바뀌는지 다시 확인',
                '걱정되면 등록된 번호로 바로 연락',
              ]
            : const [
                '현재 위치와 최근 확인 시각만 확인',
                '위험 알림이 없는지 간단히 확인',
                '필요할 때만 전화하기 버튼 사용',
              ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _softCard(color: info.lightColor, radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: info.color.withOpacity(0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(info.icon, color: info.color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.86),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: TextStyle(
                        color: info.color,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: const TextStyle(
                        color: _textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.icon(
              onPressed: isDanger ? onEmergency : onOpenHomeStatus,
              style: FilledButton.styleFrom(
                backgroundColor: isDanger ? _primaryDark : Colors.white,
                foregroundColor: isDanger ? Colors.white : info.color,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: Icon(
                isDanger
                    ? Icons.emergency_share_rounded
                    : Icons.grid_view_rounded,
                size: 18,
              ),
              label: Text(isDanger ? '긴급 화면 열기' : '집 안 상태 보기'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CareGuideCard extends StatelessWidget {
  const _CareGuideCard({required this.info});

  final StatusInfo info;

  @override
  Widget build(BuildContext context) {
    final hasRisk = info.color != _success;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _softCard(radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '보호자가 볼 내용',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 17,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          _SensorRow(
            icon: Icons.schedule_rounded,
            title: '최근 확인',
            status: _lastUpdatedText(),
            color: AppState.serverConnected ? _success : _warning,
          ),
          _SensorRow(
            icon: Icons.location_on_rounded,
            title: '현재 위치',
            status: _roomDisplayName(AppState.room),
            color: info.color,
          ),
          _SensorRow(
            icon: hasRisk
                ? Icons.notification_important_rounded
                : Icons.check_circle_rounded,
            title: hasRisk ? '필요한 행동' : '현재 알림',
            status: hasRisk ? info.action : '확인할 위험 알림 없음',
            color: hasRisk ? info.color : _success,
          ),
        ],
      ),
    );
  }
}

class _SensorRow extends StatelessWidget {
  const _SensorRow({
    required this.icon,
    required this.title,
    required this.status,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: _textPrimary,
              ),
            ),
          ),
          Text(
            status,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}
