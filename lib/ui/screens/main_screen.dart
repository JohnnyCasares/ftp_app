import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../models/server_config.dart';
import '../../models/server_status.dart';
import '../../services/foreground_task_handler.dart';
import '../../services/network_manager.dart';
import '../../services/server_controller.dart';
import '../../services/settings_repository.dart';
import '../widgets/status_banner.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  String? _wifiIp;
  late ServerConfig _config;
  bool _configLoaded = false;
  bool _batteryDialogShown = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();

    // Phase 5 / Task 6: listen for "Stop" presses coming from the foreground
    // service notification (sent by FtpTaskHandler.onNotificationButtonPressed
    // via FlutterForegroundTask.sendDataToMain).
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    super.dispose();
  }

  void _onTaskData(Object data) {
    if (data == FtpTaskHandler.msgStop && mounted) {
      context.read<ServerController>().stopServer();
    }
  }

  Future<void> _loadInitialData() async {
    final repo = context.read<SettingsRepository>();
    final nm = context.read<NetworkManager>();

    final results = await Future.wait([
      repo.loadSettings(),
      nm.getWifiIpAddress(),
    ]);

    if (!mounted) return;
    setState(() {
      _config = results[0] as ServerConfig;
      _wifiIp = results[1] as String?;
      _configLoaded = true;
    });
  }

  /// Full FTP URL from current Wi-Fi IP and configured port.
  String get _addressText {
    if (_wifiIp == null) return 'No Wi-Fi connection';
    final port = _configLoaded ? _config.port : 2121;
    return 'ftp://$_wifiIp:$port';
  }

  void _onStartStop(ServerController controller) async {
    if (controller.status.state == ServerState.running) {
      await controller.stopServer();
      return;
    }

    if (!_configLoaded) return;

    // Phase 5 / Task 7: request POST_NOTIFICATIONS on Android 13+.
    // Without it, the persistent notification is silently suppressed.
    await controller.storageService.requestNotificationPermission();

    // Phase 5 / Task 8: ask for battery-optimization exemption on the first
    // Start press only (per-session guard; the system also no-ops if granted).
    if (mounted && !_batteryDialogShown) {
      final alreadyGranted =
          await controller.storageService.isBatteryOptimizationIgnored();
      if (!alreadyGranted && mounted) {
        _batteryDialogShown = true;
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Keep server alive'),
            content: const Text(
              'Android may stop the FTP server in the background to save '
              'battery. To keep the server running while the screen is off, '
              'allow FTP Server to ignore battery optimizations.\n\n'
              'Tap "Allow" to open the next prompt, or "Skip" to continue '
              'without the exemption (the server may stop after a few minutes '
              'in the background).',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Skip'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Allow'),
              ),
            ],
          ),
        );
        if (proceed == true) {
          await controller.storageService.requestBatteryOptimizationExemption();
        }
      } else {
        _batteryDialogShown = true;
      }
    }

    if (!mounted) return;

    // Phase 4: check MANAGE_EXTERNAL_STORAGE permission before starting.
    // This permission opens a system Settings screen, so we explain it first.
    final permStatus =
        await controller.storageService.checkNativeRootPermissionStatus();

    if (mounted &&
        (permStatus == PermissionStatus.denied ||
            permStatus == PermissionStatus.permanentlyDenied)) {
      // Show an explanation dialog.  The user can tap "Continue" to open
      // Android Settings, or "Skip" to fall back to virtual-root mode
      // (the server still starts — it just won't show the full storage tree).
      final shouldRequest = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Storage Access'),
          content: const Text(
            'To browse all your phone\'s files from your PC, this app needs '
            '"All files access".\n\n'
            'Tap "Continue" to open Android Settings and enable it for '
            'FTP Server, then return to this app.\n\n'
            'Tap "Skip" to start with limited access (Pictures, Downloads, '
            'DCIM, Documents, Music, Movies only).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Skip'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );

      if (mounted && shouldRequest == true) {
        // Opens Android Settings — the user must toggle the switch and return.
        await controller.storageService.requestNativeRootAccess();
        // After returning, determineRootMode() inside startServer() will
        // re-check the status and use whatever the user chose.
      }
    }

    if (!mounted) return;
    await controller.startServer(_config);

    if (!mounted) return;
    final status = controller.status;
    if (status.state == ServerState.running) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Server started. Connect from your PC: ${status.boundAddress ?? _addressText}',
          ),
        ),
      );
    }
  }

  void _copyAddress(BuildContext context) {
    final text = _addressText;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Address copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ServerController>();
    final status = controller.status;
    final isRunning = status.state == ServerState.running;
    final isStarting = status.state == ServerState.starting;
    // Show the virtual-root banner when the server is running in virtual mode,
    // i.e. the description starts with "Virtual root".
    final isVirtual = isRunning &&
        (status.rootDescription?.startsWith('Virtual root') ?? false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('FTP Server'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () async {
              await Navigator.pushNamed(context, '/settings');
              // Reload config in case the user changed settings.
              if (mounted) await _loadInitialData();
            },
          ),
        ],
      ),
      // Center everything vertically and horizontally.
      // A ConstrainedBox caps card width on large screens (tablets).
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Virtual-root fallback banner
                if (isVirtual)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: StatusBanner(
                      message:
                          'Full storage access was not granted. Serving a virtual root with the folders your device permits.',
                    ),
                  ),

                // Error banner
                if (status.state == ServerState.error &&
                    status.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline,
                              color: Colors.red.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              status.errorMessage!,
                              style: TextStyle(color: Colors.red.shade800),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Address card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Address',
                            style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                isRunning
                                    ? (status.boundAddress ?? _addressText)
                                    : _addressText,
                                style: const TextStyle(
                                    fontFamily: 'monospace', fontSize: 15),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy, size: 18),
                              tooltip: 'Copy address',
                              onPressed: () => _copyAddress(context),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Directory card
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Directory(ies)',
                            style: Theme.of(context).textTheme.labelLarge),
                        const SizedBox(height: 6),
                        Text(
                          status.rootDescription ?? '—',
                          style: const TextStyle(fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Client count — only shown when running
                if (isRunning)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      status.activeClients == 1
                          ? '1 client connected'
                          : '${status.activeClients} clients connected',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),

                // Start / Stop button — centered within the constrained column
                Center(
                  child: SizedBox(
                    width: 160,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isRunning
                            ? Colors.red.shade400
                            : Colors.green.shade600,
                        foregroundColor: Colors.white,
                      ),
                      onPressed:
                          isStarting ? null : () => _onStartStop(controller),
                      child: isStarting
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(isRunning ? 'Stop' : 'Start',
                              style: const TextStyle(fontSize: 16)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
