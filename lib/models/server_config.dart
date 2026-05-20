import 'root_mode.dart';

/// Configuration for the FTP server instance.
/// Persisted by [SettingsRepository]; passed to [ServerController] on start.
class ServerConfig {
  const ServerConfig({
    required this.port,
    required this.password,
    this.username = 'ftp',
    this.rootMode = RootMode.nativeRoot,
  });

  /// TCP port to listen on. 0 = OS-assigned ephemeral port.
  final int port;

  /// Server authentication password. Must not be empty before starting.
  final String password;

  /// FTP username. Fixed at "ftp" per design (only password is user-configurable).
  final String username;

  /// Whether to use native-root or virtual-root filesystem mode.
  final RootMode rootMode;

  ServerConfig copyWith({
    int? port,
    String? password,
    String? username,
    RootMode? rootMode,
  }) {
    return ServerConfig(
      port: port ?? this.port,
      password: password ?? this.password,
      username: username ?? this.username,
      rootMode: rootMode ?? this.rootMode,
    );
  }

  Map<String, dynamic> toJson() => {
        'port': port,
        'password': password,
        'username': username,
        'rootMode': rootMode.name,
      };

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      port: (json['port'] as num?)?.toInt() ?? 2121,
      password: json['password'] as String? ?? '',
      username: json['username'] as String? ?? 'ftp',
      rootMode: RootMode.values.firstWhere(
        (e) => e.name == json['rootMode'],
        orElse: () => RootMode.nativeRoot,
      ),
    );
  }

  /// Default config returned when no saved settings exist.
  static const ServerConfig defaults = ServerConfig(
    port: 2121,
    password: '',
    username: 'ftp',
    rootMode: RootMode.nativeRoot,
  );
}
