import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'firebase_options.dart';

const _kServerUrl = 'http://10.43.100.39:8000';
final _navigatorKey = GlobalKey<NavigatorState>();

// ─── Colors ─────────────────────────────────
const _primary     = Color(0xFF2563EB);
const _primaryLight= Color(0xFFEFF6FF);
const _bg          = Color(0xFFF5F7FA);
const _textPrimary = Color(0xFF111827);
const _textGray    = Color(0xFF6B7280);
const _border      = Color(0xFFE5E7EB);
const _success     = Color(0xFF16A34A);
const _successLight= Color(0xFFDCFCE7);
const _warning     = Color(0xFFD97706);
const _warningLight= Color(0xFFFEF3C7);
const _danger      = Color(0xFFDC2626);
const _dangerLight = Color(0xFFFEE2E2);

// ─── FCM ────────────────────────────────────
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
  messaging.onTokenRefresh.listen((t) async {
    try {
      await http.post(
        Uri.parse('$_kServerUrl/device/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'token': t}),
      );
    } catch (_) {}
  });
  FirebaseMessaging.onMessage.listen((message) {
    final ctx = _navigatorKey.currentContext;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(message.notification?.body ?? '알림이 도착했습니다.'),
      backgroundColor: _danger,
      duration: const Duration(seconds: 5),
    ));
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _setupFcm();
  WsService.instance.connect();
  runApp(const HaniumApp());
}

// ─── App ────────────────────────────────────
class HaniumApp extends StatelessWidget {
  const HaniumApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Hanium Safety',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.light(
          primary: _primary,
          secondary: _primary,
          surface: Colors.white,
        ),
        useMaterial3: true,
      ),
      home: const LoginScreen(),
    );
  }
}

// ─── Models ─────────────────────────────────
class AlertItem {
  final String type;
  final String message;
  final String time;
  AlertItem({required this.type, required this.message, required this.time});
}

class Guardian {
  final String name;
  final String phone;
  Guardian({required this.name, required this.phone});
}

// ─── AppState ───────────────────────────────
class AppState {
  static String status = 'normal';
  static double personX = 0.45;
  static double personY = 0.35;
  static final List<Guardian> guardians = [];
  static final List<AlertItem> alerts = [
    AlertItem(type: 'normal', message: '정상 재실 감지', time: '오늘 14:32'),
    AlertItem(type: 'out',    message: '외출 감지',     time: '오늘 11:15'),
    AlertItem(type: 'normal', message: '귀가 감지',     time: '오늘 09:48'),
    AlertItem(type: 'danger', message: '낙상 의심 감지', time: '어제 22:11'),
    AlertItem(type: 'out',    message: '외출 감지',     time: '어제 13:20'),
  ];
}

// ─── WsService ──────────────────────────────
class WsService {
  WsService._();
  static final WsService instance = WsService._();

  WebSocketChannel? _channel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  String _prevStatus = 'normal';
  bool _connected = false;

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  void connect() {
    if (_connected) return;
    _connected = true;
    final uri = Uri.parse(
      _kServerUrl.replaceFirst('http://', 'ws://') + '/ws/location',
    );
    _channel = WebSocketChannel.connect(uri);
    _channel!.stream.listen(_onData,
        onError: (_) => _reconnect(),
        onDone: () => _reconnect(),
        cancelOnError: true);
  }

  void _onData(dynamic raw) {
    final map = jsonDecode(raw as String) as Map<String, dynamic>;
    AppState.personX = (map['x'] as num).toDouble();
    AppState.personY = (map['y'] as num).toDouble();
    AppState.status  = map['status'] as String;
    if (map['status'] != _prevStatus) {
      final now = DateTime.now();
      final t   = '오늘 ${now.hour}:${now.minute.toString().padLeft(2, '0')}';
      final msg = switch (map['status'] as String) {
        'danger' => '낙상 의심 감지',
        'out'    => '외출 감지',
        _        => '정상 재실 감지',
      };
      AppState.alerts.insert(0,
          AlertItem(type: map['status'] as String, message: msg, time: t));
      _prevStatus = map['status'] as String;
    }
    _controller.add(map);
  }

  void _reconnect() {
    _connected = false;
    Future.delayed(const Duration(seconds: 3), connect);
  }
}

// ─── Helpers ────────────────────────────────
Map<String, dynamic> _statusInfo(String status) {
  switch (status) {
    case 'danger':
      return {'label': '위험 감지!', 'desc': '낙상 의심 상황이 감지되었습니다',
               'color': _danger, 'light': _dangerLight, 'icon': Icons.warning_rounded};
    case 'out':
      return {'label': '외출 중', 'desc': '어르신이 외출 중입니다',
               'color': _warning, 'light': _warningLight, 'icon': Icons.directions_walk_rounded};
    default:
      return {'label': '정상 재실', 'desc': '어르신이 실내에 계십니다',
               'color': _success, 'light': _successLight, 'icon': Icons.check_circle_rounded};
  }
}

BoxDecoration _cardDeco({BorderRadius? radius, Color? color}) => BoxDecoration(
  color: color ?? Colors.white,
  borderRadius: radius ?? BorderRadius.circular(14),
  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))],
);

// ─── Login Screen ───────────────────────────
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _idCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  void _login() async {
    setState(() { _loading = true; _error = null; });
    await Future.delayed(const Duration(milliseconds: 600));
    if (_idCtrl.text == 'admin' && _pwCtrl.text == '1234') {
      if (!mounted) return;
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainScreen()));
    } else {
      setState(() { _loading = false; _error = '아이디 또는 비밀번호가 올바르지 않습니다.'; });
    }
  }

  @override
  void dispose() { _idCtrl.dispose(); _pwCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              Center(child: Column(children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(color: _primaryLight, borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.shield_rounded, color: _primary, size: 36),
                ),
                const SizedBox(height: 16),
                const Text('Hanium Safety',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _textPrimary)),
                const SizedBox(height: 4),
                const Text('어르신 안전 모니터링 시스템',
                    style: TextStyle(fontSize: 13, color: _textGray)),
              ])),
              const SizedBox(height: 48),
              const Text('아이디',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _textPrimary)),
              const SizedBox(height: 8),
              _field(_idCtrl, 'admin', Icons.person_outline_rounded),
              const SizedBox(height: 16),
              const Text('비밀번호',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: _textPrimary)),
              const SizedBox(height: 8),
              _field(_pwCtrl, '••••••••', Icons.lock_outline_rounded,
                  obscure: _obscure,
                  suffix: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: _textGray, size: 20),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  )),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Row(children: [
                  const Icon(Icons.error_outline_rounded, color: _danger, size: 16),
                  const SizedBox(width: 6),
                  Text(_error!, style: const TextStyle(color: _danger, fontSize: 13)),
                ]),
              ],
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Text('로그인',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint, IconData icon,
      {bool obscure = false, Widget? suffix}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        style: const TextStyle(color: _textPrimary, fontSize: 15),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
          prefixIcon: Icon(icon, color: const Color(0xFF9CA3AF), size: 20),
          suffixIcon: suffix,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
        onSubmitted: (_) => _login(),
      ),
    );
  }
}

// ─── Main Screen ────────────────────────────
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _index = 0;
  final _screens = const [DashboardScreen(), RadarScreen(), AlertScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, -2))],
        ),
        child: NavigationBar(
          backgroundColor: Colors.white,
          indicatorColor: _primaryLight,
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded, color: _primary),
              label: '홈',
            ),
            NavigationDestination(
              icon: Icon(Icons.radar_outlined),
              selectedIcon: Icon(Icons.radar, color: _primary),
              label: '레이더',
            ),
            NavigationDestination(
              icon: Icon(Icons.notifications_outlined),
              selectedIcon: Icon(Icons.notifications_rounded, color: _primary),
              label: '알림',
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Dashboard Screen ───────────────────────
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final info  = _statusInfo(AppState.status);
    final color = info['color'] as Color;
    final light = info['light'] as Color;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('안녕하세요 👋',
                      style: TextStyle(fontSize: 13, color: _textGray)),
                  SizedBox(height: 2),
                  Text('Hanium Safety',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _textPrimary)),
                ]),
                GestureDetector(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const GuardianScreen())),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: _cardDeco(radius: BorderRadius.circular(12)),
                    child: const Icon(Icons.manage_accounts_rounded, color: _primary, size: 24),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Status card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: light,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withOpacity(0.2)),
              ),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: color.withOpacity(0.2), blurRadius: 8)],
                  ),
                  child: Icon(info['icon'] as IconData, color: color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('현재 상태',
                      style: TextStyle(fontSize: 12, color: _textGray)),
                  const SizedBox(height: 2),
                  Text(info['label'] as String,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
                  const SizedBox(height: 2),
                  Text(info['desc'] as String,
                      style: const TextStyle(fontSize: 13, color: _textGray)),
                ])),
              ]),
            ),
            const SizedBox(height: 14),

            // Stats
            Row(children: [
              _stat('오늘 감지', '12회', Icons.wifi_rounded, _primary),
              const SizedBox(width: 10),
              _stat('외출 시간', '2시간', Icons.directions_walk_rounded, _warning),
              const SizedBox(width: 10),
              _stat('알림 횟수', '1회', Icons.notifications_rounded, _danger),
            ]),
            const SizedBox(height: 20),

            const Text('최근 감지 기록',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textPrimary)),
            const SizedBox(height: 12),
            ...AppState.alerts.take(3).map(_alertTile),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: _cardDeco(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 10),
          Text(value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _textPrimary)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: _textGray)),
        ]),
      ),
    );
  }

  Widget _alertTile(AlertItem alert) {
    final info  = _statusInfo(alert.type);
    final color = info['color'] as Color;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(),
      child: Row(children: [
        Container(
            width: 4, height: 40,
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 12),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(info['icon'] as IconData, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(alert.message,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _textPrimary)),
          const SizedBox(height: 2),
          Text(alert.time, style: const TextStyle(fontSize: 12, color: _textGray)),
        ])),
        const Icon(Icons.chevron_right_rounded, color: _border, size: 20),
      ]),
    );
  }
}

// ─── Radar Screen ───────────────────────────
class RadarScreen extends StatefulWidget {
  const RadarScreen({super.key});
  @override
  State<RadarScreen> createState() => _RadarScreenState();
}

class _RadarScreenState extends State<RadarScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  StreamSubscription? _wsSub;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _wsSub = WsService.instance.stream.listen((_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() { _animCtrl.dispose(); _wsSub?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
              Text('실시간 레이더',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _textPrimary)),
              SizedBox(height: 2),
              Text('WiFi CSI 기반 위치 추적',
                  style: TextStyle(fontSize: 13, color: _textGray)),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              _chip(Icons.wifi_rounded, 'CSI 신호', '강함', _primary),
              const SizedBox(width: 10),
              _chip(Icons.update_rounded, '업데이트', '실시간', _success),
              const SizedBox(width: 10),
              _chip(Icons.person_pin_rounded, '감지 인원', '1명', _warning),
            ]),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1A2E),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 20, offset: const Offset(0, 4))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: AnimatedBuilder(
                    animation: _animCtrl,
                    builder: (_, __) => CustomPaint(
                      painter: RadarPainter(
                        personX: AppState.personX,
                        personY: AppState.personY,
                        scanAngle: _animCtrl.value * 2 * pi,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _legend(const Color(0xFF4FC3F7), '어르신 위치'),
              const SizedBox(width: 20),
              _legend(const Color(0xFF1E3A5C), '탐지 범위'),
              const SizedBox(width: 20),
              _legend(const Color(0xFF4FC3F7).withOpacity(0.3), '스캔'),
            ]),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: _cardDeco(radius: BorderRadius.circular(12)),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
            child: Icon(icon, color: color, size: 14),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 10, color: _textGray)),
          ]),
        ]),
      ),
    );
  }

  Widget _legend(Color color, String label) {
    return Row(children: [
      Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(fontSize: 12, color: _textGray)),
    ]);
  }
}

class RadarPainter extends CustomPainter {
  final double personX, personY, scanAngle;
  RadarPainter({required this.personX, required this.personY, required this.scanAngle});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final cx = w / 2, cy = h / 2;
    final maxR = min(cx, cy) * 0.85;

    final gridPaint = Paint()
      ..color = const Color(0xFF1E3A5C).withOpacity(0.5)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;
    for (int i = 1; i < 8; i++) {
      canvas.drawLine(Offset(w * i / 8, 0), Offset(w * i / 8, h), gridPaint);
      canvas.drawLine(Offset(0, h * i / 8), Offset(w, h * i / 8), gridPaint);
    }

    final circlePaint = Paint()
      ..color = const Color(0xFF1E4A7C).withOpacity(0.6)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (int i = 1; i <= 4; i++) {
      canvas.drawCircle(Offset(cx, cy), maxR * i / 4, circlePaint);
    }

    final scanPaint = Paint()
      ..shader = SweepGradient(
        startAngle: scanAngle - 0.8, endAngle: scanAngle,
        colors: [const Color(0xFF4FC3F7).withOpacity(0.0), const Color(0xFF4FC3F7).withOpacity(0.15)],
      ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: maxR))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(cx, cy), maxR, scanPaint);

    final linePaint = Paint()
      ..color = const Color(0xFF4FC3F7).withOpacity(0.6)
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(cx, cy),
        Offset(cx + maxR * cos(scanAngle), cy + maxR * sin(scanAngle)), linePaint);

    final roomPaint = Paint()
      ..color = const Color(0xFF2A4A6C)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(w * 0.5, h * 0.05), Offset(w * 0.5, h * 0.55), roomPaint);
    canvas.drawLine(Offset(w * 0.05, h * 0.55), Offset(w * 0.95, h * 0.55), roomPaint);

    _label(canvas, '거실',   Offset(w * 0.25, h * 0.28));
    _label(canvas, '안방',   Offset(w * 0.75, h * 0.28));
    _label(canvas, '주방',   Offset(w * 0.25, h * 0.75));
    _label(canvas, '화장실', Offset(w * 0.75, h * 0.75));

    final px = personX * w, py = personY * h;
    for (int i = 3; i >= 1; i--) {
      canvas.drawCircle(Offset(px, py), 6.0 * (i + 1) * 1.5,
          Paint()..color = const Color(0xFF4FC3F7).withOpacity(0.08 * i)..style = PaintingStyle.fill);
    }
    canvas.drawCircle(Offset(px, py), 7, Paint()..color = const Color(0xFF4FC3F7)..style = PaintingStyle.fill);
    canvas.drawCircle(Offset(px, py), 3, Paint()..color = Colors.white);

    final coordPainter = TextPainter(
      text: TextSpan(
        text: '(${(personX * 10).toStringAsFixed(1)}m, ${(personY * 10).toStringAsFixed(1)}m)',
        style: const TextStyle(color: Color(0xFF4FC3F7), fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    coordPainter.paint(canvas, Offset(px + 10, py - 10));
  }

  void _label(Canvas canvas, String text, Offset offset) {
    final p = TextPainter(
      text: TextSpan(text: text,
          style: TextStyle(color: const Color(0xFF2A4A6C).withOpacity(0.8), fontSize: 12)),
      textDirection: TextDirection.ltr,
    )..layout();
    p.paint(canvas, Offset(offset.dx - p.width / 2, offset.dy - p.height / 2));
  }

  @override
  bool shouldRepaint(RadarPainter old) =>
      old.personX != personX || old.personY != personY || old.scanAngle != scanAngle;
}

// ─── Alert Screen ───────────────────────────
class AlertScreen extends StatefulWidget {
  const AlertScreen({super.key});
  @override
  State<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends State<AlertScreen> {
  StreamSubscription? _wsSub;

  @override
  void initState() {
    super.initState();
    _wsSub = WsService.instance.stream.listen((_) { if (mounted) setState(() {}); });
  }

  @override
  void dispose() { _wsSub?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('알림 기록',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: _textPrimary)),
              SizedBox(height: 2),
              Text('감지된 이벤트 전체 기록',
                  style: TextStyle(fontSize: 13, color: _textGray)),
            ]),
          ),
          Expanded(
            child: AppState.alerts.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: const BoxDecoration(color: _primaryLight, shape: BoxShape.circle),
                      child: const Icon(Icons.notifications_none_rounded, color: _primary, size: 36),
                    ),
                    const SizedBox(height: 16),
                    const Text('알림 기록이 없습니다',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: _textPrimary)),
                    const SizedBox(height: 4),
                    const Text('이상 감지 시 여기에 기록됩니다',
                        style: TextStyle(fontSize: 13, color: _textGray)),
                  ]))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: AppState.alerts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final alert = AppState.alerts[i];
                      final info  = _statusInfo(alert.type);
                      final color = info['color'] as Color;
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: _cardDeco(),
                        child: Row(children: [
                          Container(
                              width: 4, height: 44,
                              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                            child: Icon(info['icon'] as IconData, color: color, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(alert.message,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _textPrimary)),
                            const SizedBox(height: 3),
                            Text(alert.time, style: const TextStyle(fontSize: 12, color: _textGray)),
                          ])),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                            child: Text(info['label'] as String,
                                style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
                          ),
                        ]),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Guardian Screen ────────────────────────
class GuardianScreen extends StatefulWidget {
  const GuardianScreen({super.key});
  @override
  State<GuardianScreen> createState() => _GuardianScreenState();
}

class _GuardianScreenState extends State<GuardianScreen> {
  bool _sending = false;
  String? _result;
  bool _ok = false;

  Future<void> _sendTest() async {
    setState(() { _sending = true; _result = null; });
    try {
      final resp = await http.post(Uri.parse('$_kServerUrl/alarm/test'));
      final data = jsonDecode(resp.body);
      setState(() { _ok = true; _result = '발송 완료 (수신 기기: ${data['recipients']}대)'; });
    } catch (_) {
      setState(() { _ok = false; _result = '발송 실패: 서버에 연결할 수 없습니다.'; });
    } finally {
      setState(() => _sending = false);
    }
  }

  void _showAddDialog() {
    final nameCtrl  = TextEditingController();
    final phoneCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('보호자 추가', style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _dialogField(nameCtrl, '이름', Icons.person_outline_rounded),
          const SizedBox(height: 12),
          _dialogField(phoneCtrl, '전화번호', Icons.phone_outlined, type: TextInputType.phone),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: _textGray)),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.isNotEmpty && phoneCtrl.text.isNotEmpty) {
                AppState.guardians.add(Guardian(name: nameCtrl.text, phone: phoneCtrl.text));
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _primary, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: const Text('추가'),
          ),
        ],
      ),
    ).then((_) => setState(() {}));
  }

  Widget _dialogField(TextEditingController ctrl, String hint, IconData icon,
      {TextInputType? type}) {
    return Container(
      decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border)),
      child: TextField(
        controller: ctrl,
        keyboardType: type,
        style: const TextStyle(color: _textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
          prefixIcon: Icon(icon, color: const Color(0xFF9CA3AF), size: 18),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 14),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('보호자 관리',
            style: TextStyle(color: _textPrimary, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: _textPrimary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Test alarm card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _danger.withOpacity(0.2)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.notifications_active_rounded, color: _danger, size: 20),
                SizedBox(width: 8),
                Text('알람 테스트',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textPrimary)),
              ]),
              const SizedBox(height: 6),
              const Text('앱이 설치된 모든 기기에 테스트 알람을 발송합니다.',
                  style: TextStyle(fontSize: 13, color: _textGray)),
              if (_result != null) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Icon(
                    _ok ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                    color: _ok ? _success : _danger, size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(_result!, style: TextStyle(fontSize: 13, color: _ok ? _success : _danger)),
                ]),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity, height: 46,
                child: ElevatedButton.icon(
                  onPressed: _sending ? null : _sendTest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _danger, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, size: 18),
                  label: Text(_sending ? '발송 중...' : '테스트 알람 발송'),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          const Text('등록된 보호자',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _textPrimary)),
          const SizedBox(height: 12),
          Expanded(
            child: AppState.guardians.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: const [
                    Icon(Icons.people_outline_rounded, color: _border, size: 48),
                    SizedBox(height: 12),
                    Text('등록된 보호자가 없습니다.',
                        style: TextStyle(color: _textGray, fontSize: 15)),
                    SizedBox(height: 4),
                    Text('아래 + 버튼으로 추가하세요.',
                        style: TextStyle(color: _border, fontSize: 12)),
                  ]))
                : ListView.separated(
                    itemCount: AppState.guardians.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final g = AppState.guardians[i];
                      return Container(
                        padding: const EdgeInsets.all(16),
                        decoration: _cardDeco(),
                        child: Row(children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: _primaryLight, shape: BoxShape.circle),
                            child: const Icon(Icons.person_rounded, color: _primary, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(g.name,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _textPrimary)),
                            const SizedBox(height: 2),
                            Text(g.phone,
                                style: const TextStyle(fontSize: 13, color: _textGray)),
                          ])),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: _border),
                            onPressed: () => setState(() => AppState.guardians.removeAt(i)),
                          ),
                        ]),
                      );
                    },
                  ),
          ),
        ]),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        backgroundColor: _primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
