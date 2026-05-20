import 'package:network_info_plus/network_info_plus.dart';

/// Provides network information, primarily the device's Wi-Fi IPv4 address.
class NetworkManager {
  NetworkManager({NetworkInfo? networkInfo})
      : _networkInfo = networkInfo ?? NetworkInfo();

  final NetworkInfo _networkInfo;

  /// Returns the device's current Wi-Fi IPv4 address, or [null] if the device
  /// is not connected to a Wi-Fi network.
  Future<String?> getWifiIpAddress() async {
    try {
      return await _networkInfo.getWifiIP();
    } catch (_) {
      // On emulators or when permission is missing, getWifiIP can throw.
      return null;
    }
  }
}
