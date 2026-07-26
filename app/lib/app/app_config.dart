class AppConfig {
  const AppConfig._();

  static const serverUrl = String.fromEnvironment(
    'SERVER_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const demoMode = bool.fromEnvironment(
    'DEMO_MODE',
    defaultValue: false,
  );

  static const apiTimeout = Duration(milliseconds: 900);
  static const locationPollInterval = Duration(milliseconds: 350);
  static const healthPollInterval = Duration(seconds: 2);

  static String get serverBaseUrl => serverUrl.replaceFirst(RegExp(r'/+$'), '');

  static Uri httpUri(String path) => Uri.parse('$serverBaseUrl$path');

  static Uri wsUri(String path) {
    final wsBase = serverBaseUrl.startsWith('https://')
        ? serverBaseUrl.replaceFirst('https://', 'wss://')
        : serverBaseUrl.replaceFirst('http://', 'ws://');
    return Uri.parse('$wsBase$path');
  }
}
