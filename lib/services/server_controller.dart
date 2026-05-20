import 'package:flutter/foundation.dart';

import '../models/root_mode.dart';
import '../models/server_config.dart';
import '../models/server_status.dart';
import 'ftp_engine.dart';
import 'network_manager.dart';
import 'storage_access_service.dart';

/// Controls the FTP server lifecycle and exposes live status to the UI.
///
/// This is a [ChangeNotifier] so it can be provided via [Provider] and
/// listened to by widgets.
///
/// Phase 4: Uses [StorageAccessService] to determine the real storage root or
/// build a virtual-root union, replacing the Phase 3 app-scoped safe root.
class ServerController extends ChangeNotifier {
  ServerController({
    FtpEngine? engine,
    NetworkManager? networkManager,
    StorageAccessService? storageAccessService,
  })  : _engine = engine ?? FtpEngine(),
        _networkManager = networkManager ?? NetworkManager(),
        _storageService = storageAccessService ?? StorageAccessService();

  final FtpEngine _engine;
  final NetworkManager _networkManager;
  final StorageAccessService _storageService;

  ServerStatus _status = ServerStatus.stopped;

  /// Current snapshot of the server's state.
  ServerStatus get status => _status;

  void _setStatus(ServerStatus newStatus) {
    _status = newStatus;
    notifyListeners();
  }

  /// Starts the FTP server with the given [config].
  ///
  /// Auth rules (Task 1 — 2026-05-19):
  ///   • Both username and password blank → anonymous mode.
  ///     Pass username=null, password=null so ftp_server accepts any credentials.
  ///   • Password set, username blank → use "ftp" as the effective username.
  ///     WinSCP-style clients prompt for both; the user should type "ftp".
  ///   • Username set (with or without password) → use exactly what was saved.
  ///
  /// Storage (Phase 4):
  ///   [StorageAccessService.determineRootMode()] checks whether
  ///   MANAGE_EXTERNAL_STORAGE is granted.  If yes → native root at
  ///   /storage/emulated/0.  If no → virtual root over readable public dirs.
  ///   The caller (MainScreen) is responsible for showing the permission
  ///   explanation dialog and calling [requestNativeRootAccess] BEFORE calling
  ///   this method, because MANAGE_EXTERNAL_STORAGE opens a system Settings
  ///   screen that requires the user to return manually.
  Future<void> startServer(ServerConfig config) async {
    _setStatus(const ServerStatus(state: ServerState.starting));

    // Guard: Wi-Fi must be connected before starting.
    final ip = await _networkManager.getWifiIpAddress();
    if (ip == null) {
      _setStatus(const ServerStatus(
        state: ServerState.error,
        errorMessage: 'Connect to Wi-Fi before starting the server.',
      ));
      return;
    }

    // Resolve anonymous vs authenticated mode (Task 1 — 2026-05-19).
    //
    // The ftp_server package uses null/null to signal anonymous access
    // (verified in ftp_command_handler.dart lines 205–206 and 219–222 of v2.3.2).
    final String? ftpUsername;
    final String? ftpPassword;
    if (config.password.isEmpty && config.username.isEmpty) {
      // Fully anonymous — accept any FTP client without prompting credentials.
      ftpUsername = null;
      ftpPassword = null;
    } else {
      // Authenticated mode. Default username to "ftp" if the user left it blank.
      ftpUsername = config.username.isNotEmpty ? config.username : 'ftp';
      ftpPassword = config.password;
    }

    // Phase 4: resolve the real storage root.
    final rootResult = await _storageService.determineRootMode();

    final String authMode =
        (ftpUsername == null) ? 'anonymous' : 'password-protected';

    try {
      final int boundPort;

      if (rootResult.mode == RootMode.nativeRoot) {
        // Serve the full Internal storage tree.
        boundPort = await _engine.start(
          port: config.port,
          username: ftpUsername,
          password: ftpPassword,
          rootPath: rootResult.nativePath!,
        );
      } else {
        // Serve a virtual union of readable public directories.
        if (rootResult.virtualPaths.isEmpty) {
          _setStatus(const ServerStatus(
            state: ServerState.error,
            errorMessage:
                'No readable directories found on this device. '
                'Grant "All files access" in Android Settings and try again.',
          ));
          return;
        }
        boundPort = await _engine.startVirtual(
          port: config.port,
          username: ftpUsername,
          password: ftpPassword,
          paths: rootResult.virtualPaths,
        );
      }

      _setStatus(ServerStatus(
        state: ServerState.running,
        boundAddress: 'ftp://$ip:$boundPort',
        rootDescription: rootResult.description,
        activeClients: 0,
      ));

      debugPrint(
          '[ServerController] FTP server started — $authMode, '
          'root: ${rootResult.description}, address: ftp://$ip:$boundPort');
    } catch (e) {
      _setStatus(ServerStatus(
        state: ServerState.error,
        errorMessage: 'Failed to start FTP server: $e',
      ));
    }
  }

  /// Stops the FTP server.
  Future<void> stopServer() async {
    if (_status.state == ServerState.stopped) return;

    try {
      await _engine.stop();
    } catch (e) {
      debugPrint('[ServerController] Error stopping FTP engine: $e');
    } finally {
      _setStatus(ServerStatus.stopped);
    }
  }

  /// Returns the number of currently connected FTP clients.
  int get activeClients => _engine.activeClients;

  /// Exposes the [StorageAccessService] so [MainScreen] can check permission
  /// status and request it before calling [startServer].
  StorageAccessService get storageService => _storageService;
}
