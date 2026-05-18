import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'firebase_options.dart';

// 서버 IP를 본인 환경에 맞게 수정하세요
const _kServerUrl = 'http://172.30.1.47:8000';

final _navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> _setupFcm() async {
  final messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);

  FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);

  final token = await messaging.getToken();
  if (token != null) {
    try {
      await http.post(
        Uri.parse('$_kServerUrl/device/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': token}),
      );
    } catch (_) {}
  }

  messaging.onTokenRefresh.listen((newToken) async {
    try {
      await http.post(
        Uri.parse('$_kServerUrl/device/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': newToken}),
      );
    } catch (_) {}
  });

  FirebaseMessaging.onMessage.listen((message) {
    final ctx = _navigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(message.notification?.body ?? '알림이 도착했습니다.'),
        backgroundColor: const Color(0xFFEF5350),
        duration: const Duration(seconds: 5),
      ),
    );
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _setupFcm();
  runApp(const HaniumApp());
}

class HaniumApp extends StatelessWidget {
  const HaniumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Hanium Safety',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0A0E1A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF4FC3F7),
          secondary: Color(0xFF81D4FA),
          surface: Color(0xFF141A2E),
        ),
        useMaterial3: true,
        fontFamily: 'Pretendard',
      ),
      home: const LoginScreen(),
    );
  }
}

// ───────────────────────────────────────────
// 로그인 화면
// ───────────────────────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _idCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  bool _obscure = true;
  bool _isLoading = false;
  String? _errorMsg;

  void _login() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    await Future.delayed(const Duration(milliseconds: 800));

    if (_idCtrl.text == 'admin' && _pwCtrl.text == '1234') {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } else {
      setState(() {
        _isLoading = false;
        _errorMsg = '아이디 또는 비밀번호가 올바르지 않습니다.';
      });
    }
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              // 로고 영역
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: const Color(0xFF141A2E),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFF4FC3F7).withOpacity(0.4), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4FC3F7).withOpacity(0.15),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.shield_rounded, color: Color(0xFF4FC3F7), size: 40),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Hanium Safety',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '어르신 안전 모니터링 시스템',
                      style: TextStyle(fontSize: 13, color: Colors.white38),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 56),
              // 아이디 입력
              const Text('아이디', style: TextStyle(fontSize: 13, color: Colors.white54)),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _idCtrl,
                hint: 'admin',
                icon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: 20),
              // 비밀번호 입력
              const Text('비밀번호', style: TextStyle(fontSize: 13, color: Colors.white54)),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _pwCtrl,
                hint: '••••••••',
                icon: Icons.lock_outline_rounded,
                obscure: _obscure,
                suffix: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    color: Colors.white38,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              // 오류 메시지
              if (_errorMsg != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.error_outline_rounded, color: Color(0xFFEF5350), size: 16),
                    const SizedBox(width: 6),
                    Text(_errorMsg!, style: const TextStyle(color: Color(0xFFEF5350), fontSize: 13)),
                  ],
                ),
              ],
              const SizedBox(height: 32),
              // 로그인 버튼
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4FC3F7),
                    foregroundColor: const Color(0xFF0A0E1A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Color(0xFF0A0E1A),
                          ),
                        )
                      : const Text(
                          '로그인',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF141A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E2A45)),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Colors.white24),
          prefixIcon: Icon(icon, color: Colors.white38, size: 20),
          suffixIcon: suffix,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onSubmitted: (_) => _login(),
      ),
    );
  }
}

// ───────────────────────────────────────────
// 공유 상태 (실제 서버 연결 전 Mock 데이터)
// ───────────────────────────────────────────
class AppState {
  static String status = 'normal'; // normal | out | danger
  static double personX = 0.45;
  static double personY = 0.35;
  static final List<AlertItem> alerts = [
    AlertItem(type: 'normal', message: '정상 재실 감지', time: '오늘 14:32'),
    AlertItem(type: 'out', message: '외출 감지', time: '오늘 11:15'),
    AlertItem(type: 'normal', message: '귀가 감지', time: '오늘 09:48'),
    AlertItem(type: 'danger', message: '낙상 의심 감지', time: '어제 22:11'),
    AlertItem(type: 'out', message: '외출 감지', time: '어제 13:20'),
  ];
}

class AlertItem {
  final String type;
  final String message;
  final String time;
  AlertItem({required this.type, required this.message, required this.time});
}

// ───────────────────────────────────────────
// 메인 화면 (하단 네비게이션)
// ───────────────────────────────────────────
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;

  final _screens = const [
    DashboardScreen(),
    RadarScreen(),
    AlertScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFF1E2A45), width: 1)),
        ),
        child: NavigationBar(
          backgroundColor: const Color(0xFF0D1220),
          indicatorColor: const Color(0xFF1A3A5C),
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded, color: Color(0xFF4FC3F7)),
              label: '홈',
            ),
            NavigationDestination(
              icon: Icon(Icons.radar_outlined),
              selectedIcon: Icon(Icons.radar, color: Color(0xFF4FC3F7)),
              label: '레이더',
            ),
            NavigationDestination(
              icon: Icon(Icons.notifications_outlined),
              selectedIcon: Icon(Icons.notifications_rounded, color: Color(0xFF4FC3F7)),
              label: '알림',
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────
// 1. 대시보드 화면
// ───────────────────────────────────────────
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final statusInfo = _getStatusInfo(AppState.status);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildStatusCard(statusInfo),
            const SizedBox(height: 20),
            _buildStatsRow(),
            const SizedBox(height: 20),
            _buildSectionTitle('최근 감지 기록'),
            const SizedBox(height: 12),
            ...AppState.alerts.take(3).map((a) => _buildAlertTile(a)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Hanium Safety',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '어르신 실시간 안전 모니터링',
              style: TextStyle(fontSize: 13, color: Colors.white38),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF141A2E),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF1E2A45)),
          ),
          child: const Icon(Icons.person_rounded, color: Color(0xFF4FC3F7), size: 24),
        ),
      ],
    );
  }

  Widget _buildStatusCard(Map<String, dynamic> info) {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (context, child) {
        return Transform.scale(
          scale: AppState.status == 'danger' ? _pulseAnim.value : 1.0,
          child: child,
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [info['color'].withOpacity(0.3), info['color'].withOpacity(0.05)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: info['color'].withOpacity(0.5), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: info['color'].withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(info['icon'], color: info['color'], size: 32),
            ),
            const SizedBox(width: 20),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '현재 상태',
                  style: TextStyle(fontSize: 13, color: Colors.white38),
                ),
                const SizedBox(height: 4),
                Text(
                  info['label'],
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: info['color'],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  info['desc'],
                  style: const TextStyle(fontSize: 13, color: Colors.white54),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _buildStatCard('오늘 감지', '12회', Icons.wifi_rounded, const Color(0xFF4FC3F7)),
        const SizedBox(width: 12),
        _buildStatCard('외출 시간', '2시간', Icons.directions_walk_rounded, const Color(0xFF81C784)),
        const SizedBox(width: 12),
        _buildStatCard('알림 횟수', '1회', Icons.warning_rounded, const Color(0xFFFFB74D)),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF141A2E),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF1E2A45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 10),
            Text(value,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.white38)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
          fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white70),
    );
  }

  Widget _buildAlertTile(AlertItem alert) {
    final info = _getStatusInfo(alert.type);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF141A2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF1E2A45)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: info['color'].withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(info['icon'], color: info['color'], size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(alert.message,
                    style: const TextStyle(fontSize: 14, color: Colors.white)),
                const SizedBox(height: 2),
                Text(alert.time,
                    style: const TextStyle(fontSize: 12, color: Colors.white38)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
        ],
      ),
    );
  }

  Map<String, dynamic> _getStatusInfo(String status) {
    switch (status) {
      case 'danger':
        return {
          'label': '위험 감지!',
          'desc': '낙상 의심 상황이 감지되었습니다',
          'color': const Color(0xFFEF5350),
          'icon': Icons.warning_rounded,
        };
      case 'out':
        return {
          'label': '외출 중',
          'desc': '어르신이 외출 중입니다',
          'color': const Color(0xFFFFB74D),
          'icon': Icons.directions_walk_rounded,
        };
      default:
        return {
          'label': '정상 재실',
          'desc': '어르신이 실내에 계십니다',
          'color': const Color(0xFF66BB6A),
          'icon': Icons.check_circle_rounded,
        };
    }
  }
}

// ───────────────────────────────────────────
// 2. 레이더 화면
// ───────────────────────────────────────────
class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});

  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  Timer? _moveTimer;
  final Random _rand = Random();

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();

    _moveTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (mounted) {
        setState(() {
          AppState.personX = (AppState.personX + (_rand.nextDouble() - 0.5) * 0.12)
              .clamp(0.1, 0.9);
          AppState.personY = (AppState.personY + (_rand.nextDouble() - 0.5) * 0.12)
              .clamp(0.1, 0.9);
        });
      }
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _moveTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '실시간 레이더',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 4),
            const Text('WiFi CSI 기반 위치 추적',
                style: TextStyle(fontSize: 13, color: Colors.white38)),
            const SizedBox(height: 20),
            _buildSignalInfo(),
            const SizedBox(height: 16),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1A2E),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF1E3A5C), width: 1.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: AnimatedBuilder(
                    animation: _animCtrl,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: RadarPainter(
                          personX: AppState.personX,
                          personY: AppState.personY,
                          scanAngle: _animCtrl.value * 2 * pi,
                        ),
                        child: const SizedBox.expand(),
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildRoomLegend(),
          ],
        ),
      ),
    );
  }

  Widget _buildSignalInfo() {
    return Row(
      children: [
        _buildInfoChip(Icons.wifi_rounded, 'CSI 신호', '강함', const Color(0xFF4FC3F7)),
        const SizedBox(width: 10),
        _buildInfoChip(Icons.update_rounded, '업데이트', '실시간', const Color(0xFF81C784)),
        const SizedBox(width: 10),
        _buildInfoChip(Icons.person_pin_rounded, '감지 인원', '1명', const Color(0xFFFFB74D)),
      ],
    );
  }

  Widget _buildInfoChip(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF141A2E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E2A45)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold, color: color)),
                Text(label,
                    style: const TextStyle(fontSize: 10, color: Colors.white38)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _legendItem(const Color(0xFF4FC3F7), '어르신 위치'),
        const SizedBox(width: 20),
        _legendItem(const Color(0xFF1E3A5C), '탐지 범위'),
        const SizedBox(width: 20),
        _legendItem(const Color(0xFF4FC3F7).withOpacity(0.3), '스캔'),
      ],
    );
  }

  Widget _legendItem(Color color, String label) {
    return Row(
      children: [
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white54)),
      ],
    );
  }
}

class RadarPainter extends CustomPainter {
  final double personX;
  final double personY;
  final double scanAngle;

  RadarPainter({
    required this.personX,
    required this.personY,
    required this.scanAngle,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final maxR = min(cx, cy) * 0.85;

    // 배경 그리드
    final gridPaint = Paint()
      ..color = const Color(0xFF1E3A5C).withOpacity(0.5)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    // 수평/수직 그리드
    for (int i = 1; i < 8; i++) {
      final x = w * i / 8;
      final y = h * i / 8;
      canvas.drawLine(Offset(x, 0), Offset(x, h), gridPaint);
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // 동심원
    final circlePaint = Paint()
      ..color = const Color(0xFF1E4A7C).withOpacity(0.6)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(Offset(cx, cy), maxR * i / 4, circlePaint);
    }

    // 스캔 효과 (회전하는 섹터)
    final scanPaint = Paint()
      ..shader = SweepGradient(
        startAngle: scanAngle - 0.8,
        endAngle: scanAngle,
        colors: [
          const Color(0xFF4FC3F7).withOpacity(0.0),
          const Color(0xFF4FC3F7).withOpacity(0.15),
        ],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: maxR))
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(cx, cy), maxR, scanPaint);

    // 스캔 라인
    final linePaint = Paint()
      ..color = const Color(0xFF4FC3F7).withOpacity(0.6)
      ..strokeWidth = 1.5;

    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + maxR * cos(scanAngle), cy + maxR * sin(scanAngle)),
      linePaint,
    );

    // 방 구분선 (집 평면도)
    final roomPaint = Paint()
      ..color = const Color(0xFF2A4A6C)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // 방 구분
    canvas.drawLine(Offset(w * 0.5, h * 0.05), Offset(w * 0.5, h * 0.55), roomPaint);
    canvas.drawLine(Offset(w * 0.05, h * 0.55), Offset(w * 0.95, h * 0.55), roomPaint);

    // 방 라벨
    _drawRoomLabel(canvas, '거실', Offset(w * 0.25, h * 0.28));
    _drawRoomLabel(canvas, '안방', Offset(w * 0.75, h * 0.28));
    _drawRoomLabel(canvas, '주방', Offset(w * 0.25, h * 0.75));
    _drawRoomLabel(canvas, '화장실', Offset(w * 0.75, h * 0.75));

    // 어르신 위치 (빛나는 점)
    final px = personX * w;
    final py = personY * h;

    // 외곽 빛
    for (int i = 3; i >= 1; i--) {
      final glowPaint = Paint()
        ..color = const Color(0xFF4FC3F7).withOpacity(0.08 * i)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(px, py), 6.0 * (i + 1) * 1.5, glowPaint);
    }

    // 핵심 점
    final dotPaint = Paint()
      ..color = const Color(0xFF4FC3F7)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(px, py), 7, dotPaint);

    // 중심 흰 점
    canvas.drawCircle(
        Offset(px, py), 3, Paint()..color = Colors.white);

    // 좌표 텍스트
    final coordPainter = TextPainter(
      text: TextSpan(
        text: '(${(personX * 10).toStringAsFixed(1)}m, ${(personY * 10).toStringAsFixed(1)}m)',
        style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    coordPainter.paint(canvas, Offset(px + 10, py - 10));
  }

  void _drawRoomLabel(Canvas canvas, String text, Offset offset) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            color: const Color(0xFF2A4A6C).withOpacity(0.8), fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
        canvas, Offset(offset.dx - painter.width / 2, offset.dy - painter.height / 2));
  }

  @override
  bool shouldRepaint(RadarPainter old) =>
      old.personX != personX ||
      old.personY != personY ||
      old.scanAngle != scanAngle;
}

// ───────────────────────────────────────────
// 3. 알림 화면
// ───────────────────────────────────────────
class AlertScreen extends StatelessWidget {
  const AlertScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '알림 기록',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 4),
            const Text('감지된 이벤트 전체 기록',
                style: TextStyle(fontSize: 13, color: Colors.white38)),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.separated(
                itemCount: AppState.alerts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, i) {
                  final alert = AppState.alerts[i];
                  final info = _getInfo(alert.type);
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141A2E),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: (info['color'] as Color).withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: (info['color'] as Color).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(info['icon'] as IconData,
                              color: info['color'] as Color, size: 22),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                alert.message,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white),
                              ),
                              const SizedBox(height: 4),
                              Text(alert.time,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.white38)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: (info['color'] as Color).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            info['tag'] as String,
                            style: TextStyle(
                                fontSize: 11,
                                color: info['color'] as Color,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _getInfo(String type) {
    switch (type) {
      case 'danger':
        return {
          'color': const Color(0xFFEF5350),
          'icon': Icons.warning_rounded,
          'tag': '위험',
        };
      case 'out':
        return {
          'color': const Color(0xFFFFB74D),
          'icon': Icons.directions_walk_rounded,
          'tag': '외출',
        };
      default:
        return {
          'color': const Color(0xFF66BB6A),
          'icon': Icons.check_circle_rounded,
          'tag': '정상',
        };
    }
  }
}
