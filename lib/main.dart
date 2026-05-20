import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:provider/provider.dart';

import 'services/foreground_service_manager.dart';
import 'services/foreground_task_handler.dart';
import 'services/network_manager.dart';
import 'services/server_controller.dart';
import 'services/settings_repository.dart';
import 'ui/screens/main_screen.dart';
import 'ui/screens/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise the isolate communication port so the TaskHandler isolate can
  // send messages (e.g. "Stop" button press) back to the main isolate.
  // Must be called before runApp() and before any foreground service starts.
  FlutterForegroundTask.initCommunicationPort();

  // Register the top-level task handler callback so the foreground service
  // can invoke it when the service starts.
  FlutterForegroundTask.setTaskHandler(FtpTaskHandler());

  // Pre-initialise the foreground task options so they are ready before the
  // user presses Start for the first time.
  ForegroundServiceManager.initialize();

  runApp(const FtpApp());
}

class FtpApp extends StatelessWidget {
  const FtpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SettingsRepository>(
          create: (_) => SettingsRepository(),
        ),
        Provider<NetworkManager>(
          create: (_) => NetworkManager(),
        ),
        // ServerController shares the same NetworkManager instance so Wi-Fi
        // checks inside startServer() are consistent with the UI's IP display.
        ChangeNotifierProxyProvider<NetworkManager, ServerController>(
          create: (ctx) =>
              ServerController(networkManager: ctx.read<NetworkManager>()),
          update: (ctx, nm, prev) => prev ?? ServerController(networkManager: nm),
        ),
      ],
      child: MaterialApp(
        title: 'FTP Server',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueAccent),
          useMaterial3: true,
        ),
        initialRoute: '/',
        routes: {
          '/': (_) => const MainScreen(),
          '/settings': (_) => const SettingsScreen(),
        },
      ),
    );
  }
}
