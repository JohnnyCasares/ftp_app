/// Lifecycle state of the FTP server.
enum ServerState { stopped, starting, running, error }

/// Live status snapshot exposed by [ServerController] to the UI.
class ServerStatus {
  const ServerStatus({
    required this.state,
    this.boundAddress,
    this.activeClients = 0,
    this.errorMessage,
    this.rootDescription,
  });

  /// Current server lifecycle state.
  final ServerState state;

  /// Full connection URL, e.g. "ftp://192.168.1.42:2121".
  /// Non-null only when [state] is [ServerState.running].
  final String? boundAddress;

  /// Number of FTP clients currently connected.
  final int activeClients;

  /// Human-readable error message. Non-null only when [state] is [ServerState.error].
  final String? errorMessage;

  /// Description of the root being served (e.g. "/storage/emulated/0" or
  /// "DCIM, Pictures, Downloads"). Populated after server starts.
  final String? rootDescription;

  static const ServerStatus stopped = ServerStatus(state: ServerState.stopped);

  ServerStatus copyWith({
    ServerState? state,
    String? boundAddress,
    int? activeClients,
    String? errorMessage,
    String? rootDescription,
  }) {
    return ServerStatus(
      state: state ?? this.state,
      boundAddress: boundAddress ?? this.boundAddress,
      activeClients: activeClients ?? this.activeClients,
      errorMessage: errorMessage ?? this.errorMessage,
      rootDescription: rootDescription ?? this.rootDescription,
    );
  }
}
