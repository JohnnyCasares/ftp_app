import 'dart:io';

import 'package:ftp_server/ftp_server.dart';
import 'package:ftp_server/file_operations/physical_file_operations.dart';
import 'package:ftp_server/file_operations/virtual_file_operations.dart';
import 'package:ftp_server/server_type.dart';

import '../models/virtual_path.dart';

/// Wraps the `ftp_server` Dart package and owns the FTP server instance.
///
/// Authentication is handled by the package's built-in mechanism:
/// - Non-null [username]/[password] → require those exact credentials.
/// - Both null → anonymous mode (any FTP client user/password accepted),
///   per ASSUMPTION A6 (user override 2026-05-19).
///
/// ## FTP command coverage (DESIGN.md §7)
/// The `ftp_server` package (v2.3.2) implements all required commands:
/// USER ✓  PASS ✓  QUIT ✓  SYST ✓  FEAT ✓  PWD ✓  CWD ✓  CDUP ✓
/// LIST ✓  NLST ✓  RETR ✓  STOR ✓  DELE ✓  MKD ✓   RMD ✓
/// RNFR ✓  RNTO ✓  SIZE ✓  MDTM ✓  TYPE ✓  MODE ✓  STRU ✓
/// PASV ✓  PORT ✓  EPSV ✓
/// EPRT: NOT explicitly implemented by the package — the switch in
/// ftp_command_handler.dart falls through to '502 Command not implemented'.
/// Real FTP clients fall back to EPSV/PASV automatically, so this is not a
/// blocker in practice. Noted here per the PLAN.md Phase 3 requirement.
class FtpEngine {
  FtpServer? _server;

  /// Number of active client sessions.
  int get activeClients => _server?.activeSessions.length ?? 0;

  /// Starts the FTP server in native-root mode (single physical directory tree).
  ///
  /// [port] — TCP port to bind (0 = OS-assigned ephemeral port; we resolve it
  ///           before binding via [_pickFreePort] to work around the package
  ///           not exposing the bound port number).
  /// [username] — FTP username, or null for anonymous mode.
  /// [password] — FTP password, or null for anonymous mode.
  /// [rootPath] — Absolute path to serve as the FTP root.
  ///
  /// Returns the actual port the server bound to.
  Future<int> start({
    required int port,
    required String? username,
    required String? password,
    required String rootPath,
  }) async {
    // Stop any existing server before starting a new one.
    await stop();

    final resolvedPort = port == 0 ? await _pickFreePort() : port;

    final fileOps = PhysicalFileOperations(rootPath);

    _server = FtpServer(
      resolvedPort,
      username: username,
      password: password,
      fileOperations: fileOps,
      serverType: ServerType.readAndWrite, // A8: full read+write
      logFunction: _log,
    );

    // startInBackground() binds the ServerSocket immediately and returns;
    // it does not block waiting for connections.
    await _server!.startInBackground();
    return resolvedPort;
  }

  /// Starts the FTP server in virtual-root mode (multiple real directories
  /// presented as a unified virtual tree).
  ///
  /// [paths] — list of [VirtualPath] entries mapping FTP-visible names to
  /// real filesystem paths. Only [VirtualPath.readable] == true entries are
  /// included. [VirtualFileOperations] uses the basename of each [realPath]
  /// as the FTP-visible directory name (e.g. ".../DCIM" → "DCIM").
  Future<int> startVirtual({
    required int port,
    required String? username,
    required String? password,
    required List<VirtualPath> paths,
  }) async {
    await stop();

    final allowedDirs = paths
        .where((vp) => vp.readable)
        .map((vp) => vp.realPath)
        .toList();

    if (allowedDirs.isEmpty) {
      throw StateError(
          'No readable virtual paths provided — cannot start FTP server.');
    }

    final resolvedPort = port == 0 ? await _pickFreePort() : port;

    final fileOps = VirtualFileOperations(allowedDirs);

    _server = FtpServer(
      resolvedPort,
      username: username,
      password: password,
      fileOperations: fileOps,
      serverType: ServerType.readAndWrite,
      logFunction: _log,
    );

    await _server!.startInBackground();
    return resolvedPort;
  }

  /// Stops the FTP server and closes all active sessions.
  Future<void> stop() async {
    if (_server != null) {
      await _server!.stop();
      _server = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  void _log(String message) {
    // ignore: avoid_print
    print('[FtpEngine] $message');
  }

  /// Finds a free TCP port by briefly binding a [ServerSocket] on port 0,
  /// recording the OS-assigned port, then releasing it.
  ///
  /// There is a tiny TOCTOU race between releasing the socket and the FTP
  /// server binding the same port, but on a single-user phone app this is
  /// negligible in practice.
  static Future<int> _pickFreePort() async {
    final socket =
        await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }
}
