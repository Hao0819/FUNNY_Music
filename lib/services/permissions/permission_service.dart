import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Local audio access and optional playback notifications.
class PermissionService {
  static const _mediaStore = MethodChannel('music_player/media_store');

  Future<Permission> _audioPermission() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return Permission.audio;
    }

    // Android 12 and below grant shared audio access through storage.
    final sdkInt = await _mediaStore.invokeMethod<int>('sdkInt');
    return sdkInt != null && sdkInt < 33
        ? Permission.storage
        : Permission.audio;
  }

  Future<PermissionStatus> status() async => (await _audioPermission()).status;

  Future<PermissionStatus> request() async =>
      (await _audioPermission()).request();

  /// The media notification's permission. Only a runtime permission from
  /// Android 13; below that the plugin reports it granted, so callers do not
  /// branch on version here either.
  Future<PermissionStatus> notificationStatus() =>
      Permission.notification.status;

  Future<PermissionStatus> requestNotification() =>
      Permission.notification.request();

  Future<bool> openSettings() => openAppSettings();
}
