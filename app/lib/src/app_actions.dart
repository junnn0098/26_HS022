part of '../main.dart';

void _openEmergency(BuildContext context) {
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const EmergencyScreen()));
}

void _showTodoSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _refreshServerHealth(BuildContext context) async {
  final result = await ApiService.get('/health');
  if (!context.mounted) return;

  if (result == null) {
    AppState.serverConnected = false;
    AppState.connectionMessage = '상태를 다시 확인하는 중이에요';
    WsService.instance.notify();
    _showTodoSnack(context, '지금은 상태 확인이 지연되고 있어요.');
    return;
  }

  AppState.serverConnected = true;
  AppState.connectionMessage = '최근 상태 확인 완료';
  WsService.instance.notify();
  _showTodoSnack(context, '안심 상태가 정상적으로 확인됐어요.');
}

Future<void> _saveMiniatureSize(BuildContext context, String size) async {
  AppState.settings['miniatureSize'] = size;
  WsService.instance.notify();

  final result = await ApiService.post('/settings', {'miniatureSize': size});
  if (!context.mounted) return;

  if (result == null) {
    _showTodoSnack(context, '표시 설정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.');
    return;
  }

  _applyServerState(result);
  WsService.instance.notify();
  _showTodoSnack(context, '미니어처 크기를 저장했어요.');
}

Future<bool> _showGuardianEditor(
  BuildContext context, {
  Guardian? guardian,
  String defaultRole = '1순위 보호자',
}) async {
  final result = await Navigator.of(context).push<Map<String, String>>(
    MaterialPageRoute(
      builder: (_) => GuardianEditScreen(
        guardian: guardian,
        defaultRole: defaultRole,
      ),
    ),
  );

  if (result == null || !context.mounted) return false;

  final body = <String, dynamic>{
    'name': result['name'],
    'phone': result['phone'],
    'role': result['role'],
  };
  if (guardian != null) body['id'] = guardian.id;

  final response = await ApiService.post(
    guardian == null ? '/guardians' : '/guardians/update',
    body,
  );

  if (!context.mounted) return false;
  if (response == null) {
    _showTodoSnack(context, '저장하지 못했어요. 잠시 후 다시 시도해 주세요.');
    return false;
  }

  _applyServerState(response);
  _showTodoSnack(context, guardian == null ? '보호자를 추가했어요.' : '보호자 정보를 수정했어요.');
  return true;
}

Future<bool> _confirmDeleteGuardian(
  BuildContext context,
  Guardian guardian,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('보호자 삭제'),
        content: Text('${guardian.name} 정보를 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(backgroundColor: _danger),
            child: const Text('삭제'),
          ),
        ],
      );
    },
  );

  if (confirmed != true || !context.mounted) return false;

  final response = await ApiService.post('/guardians/delete', {
    'id': guardian.id,
  });

  if (!context.mounted) return false;
  if (response == null) {
    _showTodoSnack(context, '삭제하지 못했어요. 잠시 후 다시 시도해 주세요.');
    return false;
  }

  _applyServerState(response);
  WsService.instance.notify();
  _showTodoSnack(context, '보호자 정보를 삭제했어요.');
  return true;
}

Future<void> _triggerDangerScenario(BuildContext context) async {
  if (!_kDemoMode) {
    _showTodoSnack(context, '발표 모드에서만 사용할 수 있는 기능이에요.');
    return;
  }

  final result = await ApiService.post('/scenario', {
    'status': 'danger',
    'seconds': 18,
  });

  if (!context.mounted) return;
  if (result == null) {
    _showTodoSnack(context, '발표 상태를 불러오지 못했어요. 잠시 후 다시 시도해 주세요.');
    return;
  }

  final location = result['location'];
  if (location is Map) {
    _applyLocationFromServer(Map<String, dynamic>.from(location));
  } else {
    AppState.status = 'danger';
    AppState.pose = 'lying';
    AppState.room = '거실';
  }
  AppState.alerts.insert(
    0,
    AlertItem(
      type: 'danger',
      title: '발표용 낙상 의심 상황',
      message: '발표용으로 위험 상황을 발생시켰어요.',
      time: _formatTime(DateTime.now()),
      room: AppState.room,
      urgent: true,
    ),
  );
  unawaited(_syncAlertsFromServer());
  WsService.instance.notify();

  _showTodoSnack(context, '발표용 위험 상황을 발생시켰어요.');
  _openEmergency(context);
}

Guardian? _careTarget() {
  for (final guardian in AppState.guardians) {
    if (guardian.role.contains('보호 대상') || guardian.name.contains('어르신')) {
      return guardian;
    }
  }
  return AppState.guardians.isEmpty ? null : AppState.guardians.first;
}

Guardian? _primaryGuardian() {
  for (final guardian in AppState.guardians) {
    final isCareTarget =
        guardian.role.contains('보호 대상') || guardian.name.contains('어르신');
    if (!isCareTarget && guardian.role.contains('보호자')) {
      return guardian;
    }
  }

  if (AppState.guardians.length > 1) return AppState.guardians[1];
  return AppState.guardians.isEmpty ? null : AppState.guardians.first;
}

String _phoneForDial(String phone) {
  return phone.replaceAll(RegExp(r'[^0-9+]'), '');
}

String _buildEmergencySummary() {
  final target = _careTarget()?.name ?? '보호 대상';
  final info = AppState.emergencyInfo;
  final status = _statusInfo(AppState.status);
  final includeDoorPassword = AppState.settingBool(
    'showDoorPasswordInEmergency',
    true,
  );
  final includeMedicalInfo = AppState.settingBool(
    'shareMedicalInfoInEmergency',
    true,
  );

  final lines = [
    '[한이음 안전 알림]',
    '$target에게 빠른 확인이 필요합니다.',
    '',
    '상태: ${status.title}',
    '감지 내용: ${_emergencyEventMessage()}',
    '감지 위치: ${_roomDisplayName(AppState.room)}',
    '현재 자세: ${_poseLabel(AppState.pose)} 상태',
    '감지 확실성: ${_certaintyLabel()}',
    '확인 시각: ${_formatTime(DateTime.now())}',
    '',
    '집 주소: ${info.address}',
    '출입 안내: ${info.accessNote}',
    if (includeDoorPassword && info.doorPassword.trim().isNotEmpty)
      '도어락 참고: ${info.doorPassword}',
    if (includeMedicalInfo) '의료 참고사항: ${info.medicalNote}',
    '가까운 병원: ${info.hospital}',
  ];

  return lines.join('\n');
}

Future<void> _openNativeAction(
  BuildContext context, {
  required String method,
  required Map<String, String> arguments,
  required String successMessage,
  required String fallbackMessage,
}) async {
  try {
    final opened = await _emergencyChannel.invokeMethod<bool>(
      method,
      arguments,
    );
    if (!context.mounted) return;

    if (opened == true) {
      _showTodoSnack(context, successMessage);
    } else {
      _showTodoSnack(context, fallbackMessage);
    }
  } on MissingPluginException {
    if (!context.mounted) return;
    _showTodoSnack(context, '현재 실행 환경에서는 전화/문자 앱을 직접 열 수 없어요.');
  } on PlatformException catch (error) {
    if (!context.mounted) return;
    _showTodoSnack(context, error.message ?? fallbackMessage);
  } catch (_) {
    if (!context.mounted) return;
    _showTodoSnack(context, fallbackMessage);
  }
}

Future<void> _callCareTarget(BuildContext context) async {
  final target = _careTarget();
  final phone = _phoneForDial(target?.phone ?? '');
  if (target == null || phone.isEmpty) {
    _showTodoSnack(context, '설정에서 보호 대상 연락처를 먼저 입력해 주세요.');
    return;
  }

  await _openNativeAction(
    context,
    method: 'dial',
    arguments: {'phone': phone},
    successMessage: '${target.name} 전화 화면을 열었어요.',
    fallbackMessage: '전화 앱을 열 수 없어요. 연락처: ${target.phone}',
  );
}

Future<void> _dial119(BuildContext context) async {
  await Clipboard.setData(ClipboardData(text: _buildEmergencySummary()));

  if (!context.mounted) return;
  await _openNativeAction(
    context,
    method: 'dial',
    arguments: {'phone': '119'},
    successMessage: '119 전화 화면을 열었어요. 신고 문장도 복사했어요.',
    fallbackMessage: '전화 앱을 열 수 없어요. 신고 문장은 복사해뒀어요.',
  );
}

Future<void> _sendEmergencySms(BuildContext context) async {
  final guardian = _primaryGuardian();
  final phone = _phoneForDial(guardian?.phone ?? '');
  if (guardian == null || phone.isEmpty) {
    _showTodoSnack(context, '설정에서 1순위 보호자 연락처를 먼저 입력해 주세요.');
    return;
  }

  await _openNativeAction(
    context,
    method: 'sms',
    arguments: {'phone': phone, 'message': _buildEmergencySummary()},
    successMessage: '${guardian.name}에게 보낼 문자 초안을 열었어요.',
    fallbackMessage: '문자 앱을 열 수 없어요. 보호자 연락처: ${guardian.phone}',
  );
}

Future<void> _copyEmergencySummary(BuildContext context) async {
  if (!AppState.settingBool('allowClipboardCopy', true)) {
    _showTodoSnack(context, '개인정보 보호 설정으로 문장 복사가 꺼져 있어요.');
    return;
  }

  await Clipboard.setData(ClipboardData(text: _buildEmergencySummary()));
  if (!context.mounted) return;
  _showTodoSnack(context, '119 신고 문장을 복사했어요.');
}

Future<void> _copyAlertSummary(BuildContext context, AlertItem alert) async {
  if (!AppState.settingBool('allowClipboardCopy', true)) {
    _showTodoSnack(context, '개인정보 보호 설정으로 알림 복사가 꺼져 있어요.');
    return;
  }

  final text = [
    '[한이음 안전 알림]',
    alert.title,
    '',
    '내용: ${alert.message}',
    '감지 근거: ${_alertReason(alert)}',
    '보호자 안내: ${_guardianMeaning(alert)}',
    '감지 위치: ${_roomDisplayName(alert.room)}',
    '감지 시각: ${alert.time}',
    '현재 위치: ${_roomDisplayName(AppState.room)}',
    '현재 자세: ${_poseLabel(AppState.pose)} 상태',
    '감지 확실성: ${_certaintyLabel()}',
    '',
    '집 주소: ${AppState.emergencyInfo.address}',
    '출입 안내: ${AppState.emergencyInfo.accessNote}',
  ].join('\n');

  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  _showTodoSnack(context, '알림 내용을 복사했어요.');
}

Future<void> _confirmSafe(BuildContext context) async {
  final result = await ApiService.post('/alerts/resolve');

  if (!context.mounted) return;
  if (result == null) {
    _showTodoSnack(context, '확인 완료 처리에 실패했어요. 잠시 후 다시 시도해 주세요.');
    return;
  }

  AppState.status = 'normal';
  AppState.pose = 'standing';
  _applyServerState(result);
  WsService.instance.notify();

  Navigator.of(context).maybePop();
  _showTodoSnack(context, '위험 알림을 확인 완료로 처리했어요.');
}

Future<void> _editRoomLabel(BuildContext context, String room) async {
  final controller = TextEditingController(text: _roomDisplayName(room));
  final nextName = await showDialog<String>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text('$room 이름 수정'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            hintText: '예: 안방, 작은방, 현관 앞',
            helperText: '도면과 알림 문구에 표시될 이름이에요.',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onSubmitted: (_) {
            Navigator.of(dialogContext).pop(controller.text.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(controller.text.trim());
            },
            child: const Text('저장'),
          ),
        ],
      );
    },
  );
  controller.dispose();

  if (nextName == null || !context.mounted) return;

  final labels = _roomLabelsForDisplay();
  labels[room] = nextName.isEmpty ? room : nextName;
  await _saveRoomLabels(context, labels, successMessage: '$room 이름을 저장했어요.');
}

Future<void> _resetRoomLabels(BuildContext context) async {
  final labels = {for (final room in _roomOrder) room: room};
  await _saveRoomLabels(context, labels, successMessage: '기본 방 이름으로 되돌렸어요.');
}

Future<void> _saveRoomLabels(
  BuildContext context,
  Map<String, String> labels, {
  required String successMessage,
}) async {
  AppState.settings['roomLabels'] = labels;
  WsService.instance.notify();

  final result = await ApiService.post('/settings', {'roomLabels': labels});
  if (!context.mounted) return;

  if (result == null) {
    _showTodoSnack(context, '방 이름을 서버에 저장하지 못했어요. 화면에는 임시 반영됐어요.');
    return;
  }

  _applyServerState(result);
  WsService.instance.notify();
  _showTodoSnack(context, successMessage);
}

Future<void> _saveRetentionDays(BuildContext context, int days) async {
  AppState.settings['alertRetentionDays'] = days;
  WsService.instance.notify();

  final result = await ApiService.post('/settings', {
    'alertRetentionDays': days,
  });
  if (!context.mounted) return;

  if (result == null) {
    _showTodoSnack(context, '보관 기간을 서버에 저장하지 못했어요. 화면에는 임시 반영됐어요.');
    return;
  }

  _applyServerState(result);
  WsService.instance.notify();
  _showTodoSnack(context, '알림 기록 보관 기간을 ${days}일로 저장했어요.');
}

Future<void> _saveSettingToServer(
  String key,
  dynamic value,
  BuildContext context,
) async {
  final result = await ApiService.post('/settings', {key: value});
  if (!context.mounted) return;
  if (result == null) {
    _showTodoSnack(context, '설정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요.');
    return;
  }

  _applyServerState(result);
  WsService.instance.notify();
}
