import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

/// Asks the operating system for local-network access before a room is opened.
///
/// Local music rooms require local network Wi-Fi device access to bind and connect to
/// sockets and discover nearby room hosts/guests. On Android 13+ (API 33+),
/// `NEARBY_WIFI_DEVICES` is requested; on earlier Android versions, location
/// permission is requested for Wi-Fi scanning. On iOS, `accessLocalNetwork`
/// requests local network permission.
abstract interface class LocalNetworkPermission {
  /// Ask for access, returning true when a room may go ahead and open.
  Future<bool> request();
}

/// The real [LocalNetworkPermission], backed by `permission_handler`.
class PlatformLocalNetworkPermission implements LocalNetworkPermission {
  const PlatformLocalNetworkPermission();

  @override
  Future<bool> request() async {
    if (Platform.isAndroid) {
      try {
        // On Android 13+ (API 33+), NEARBY_WIFI_DEVICES permission is required
        // for local network Wi-Fi device communication & discovery.
        final nearbyStatus = await Permission.nearbyWifiDevices.status;
        if (nearbyStatus.isGranted) return true;
        if (nearbyStatus.isPermanentlyDenied) return false;

        final nearbyResult = await Permission.nearbyWifiDevices.request();
        if (nearbyResult.isGranted) return true;

        // Fallback for Android < 33 (API < 33 requires location permission for Wi-Fi local network access)
        final locationStatus = await Permission.locationWhenInUse.status;
        if (locationStatus.isGranted) return true;
        if (locationStatus.isPermanentlyDenied) return false;

        return (await Permission.locationWhenInUse.request()).isGranted;
      } on Object {
        return true;
      }
    } else if (Platform.isIOS) {
      try {
        final current = await Permission.accessLocalNetwork.status;
        if (current.isGranted) return true;
        if (current.isPermanentlyDenied) return false;

        return (await Permission.accessLocalNetwork.request()).isGranted;
      } on Object {
        return true;
      }
    }

    return true;
  }
}
