import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/services/permissions/permission_service.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  final messenger =
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  const mediaStore = MethodChannel('music_player/media_store');
  const permissions = MethodChannel('flutter.baseflow.com/permissions/methods');

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(mediaStore, null);
    messenger.setMockMethodCallHandler(permissions, null);
  });

  for (final (sdk, permission) in [
    (30, Permission.storage), // Android 11, the Redmi 10 launch OS.
    (32, Permission.storage),
    (33, Permission.audio),
  ]) {
    test('checks and requests $permission on API $sdk', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      messenger.setMockMethodCallHandler(mediaStore, (call) async {
        expect(call.method, 'sdkInt');
        return sdk;
      });
      messenger.setMockMethodCallHandler(permissions, (call) async {
        switch (call.method) {
          case 'checkPermissionStatus':
            expect(call.arguments, permission.value);
            return PermissionStatus.denied.index;
          case 'requestPermissions':
            expect(call.arguments, [permission.value]);
            return {permission.value: PermissionStatus.granted.index};
          default:
            fail('Unexpected permission call: ${call.method}');
        }
      });

      final service = PermissionService();
      expect(await service.status(), PermissionStatus.denied);
      expect(await service.request(), PermissionStatus.granted);
    });
  }
}
