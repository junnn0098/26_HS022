import 'package:flutter_test/flutter_test.dart';
import 'package:hanium_app/core/models/safety_models.dart';

// 서버 계약(status 'unknown', breathingRate null, 정확한 source 값)을 앱 모델이 지키는지 확인한다.
void main() {
  group('status', () {
    test('unknown and unsupported values are never shown as normal', () {
      expect(safetyStatusFrom('normal'), SafetyStatus.normal);
      expect(safetyStatusFrom('unknown'), SafetyStatus.unknown);
      expect(safetyStatusFrom('model_unavailable'), SafetyStatus.unknown);
      expect(safetyStatusFrom(null), SafetyStatus.unknown);
      expect(safetyStatusFrom('fall'), SafetyStatus.danger);
    });

    test('unknown is a neutral 확인 필요 state', () {
      final snapshot = SafetySnapshot.initial().copyWith(status: SafetyStatus.unknown);
      expect(snapshot.levelLabel, '확인 필요');
      expect(snapshot.isDanger, isFalse);
      expect(snapshot.needsAttention, isFalse);
      expect(snapshot.isUnknown, isTrue);
    });

    test('initial snapshot does not claim normal before server data', () {
      expect(SafetySnapshot.initial().status, SafetyStatus.unknown);
    });
  });

  group('breathingRate', () {
    test('missing or estimated values become 측정 대기', () {
      expect(measuredBreathingRate({}), isNull);
      expect(measuredBreathingRate({'breathingRate': null}), isNull);
      expect(measuredBreathingRate({'breathingRate': 16.2, 'breathingEstimated': true}), isNull);
      expect(measuredBreathingRate({'breathingRate': 16.2}), 16.2);

      final snapshot = SafetySnapshot.initial();
      expect(snapshot.breathingRate, isNull);
      expect(snapshot.breathingRateLabel, '측정 대기');
    });

    test('cached snapshots keep a missing value missing', () {
      final restored = SafetySnapshot.fromCacheJson({'status': 'normal', 'breathingRate': null});
      expect(restored.breathingRate, isNull);
    });
  });

  group('source', () {
    SafetySnapshot withSource(String source) =>
        SafetySnapshot.initial().copyWith(dataSource: source);

    test('only jetson_orin counts as live edge inference', () {
      expect(withSource('jetson_orin').isLiveSensorSource, isTrue);
      expect(withSource('jetson_orin').dataSourceLabel, 'Jetson 실시간 추론');
      for (final source in ['jetson', 'demo_sensor', 'sensor', 'sensor-waiting', 'unknown']) {
        expect(withSource(source).isLiveSensorSource, isFalse, reason: source);
      }
    });

    test('scripted_demo is labelled as demo input', () {
      final snapshot = withSource('scripted_demo');
      expect(snapshot.isScriptedDemoSource, isTrue);
      expect(snapshot.dataSourceLabel, '시연 입력');
      expect(withSource('unknown').dataSourceLabel, '출처 미지정');
    });

    test('no data yet or cached data is never labelled as live or demo', () {
      final initial = SafetySnapshot.initial();
      expect(initial.dataSource, 'unknown');
      expect(initial.dataSourceLabel, '출처 미지정');

      final restored = SafetySnapshot.fromCacheJson({
        'status': 'normal',
        'dataSource': 'jetson_orin',
      });
      expect(restored.isLiveSensorSource, isFalse);
      expect(restored.dataSourceLabel, '앱에 저장된 마지막 상태');
    });
  });

  test('emergency info no longer carries a door password', () {
    final info = EmergencyInfo.fromJson({'doorPassword': '1234'});
    expect(info.toJson().containsKey('doorPassword'), isFalse);
  });
}
