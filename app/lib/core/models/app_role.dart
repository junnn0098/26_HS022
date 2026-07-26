enum AppRole { guardian, careRecipient }

extension AppRoleLabel on AppRole {
  String get serverValue {
    return switch (this) {
      AppRole.guardian => 'guardian',
      AppRole.careRecipient => 'careRecipient',
    };
  }

  String get title {
    return switch (this) {
      AppRole.guardian => '보호자',
      AppRole.careRecipient => '피보호자',
    };
  }

  String get subtitle {
    return switch (this) {
      AppRole.guardian => '가족의 상태와 위험 알림을 확인해요',
      AppRole.careRecipient => '내 생활 리듬과 위치 공유를 관리해요',
    };
  }
}
