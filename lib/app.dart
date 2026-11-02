import 'package:flutter/material.dart';
import 'theme.dart';
import 'navigation.dart';
import 'database/database_helper.dart';
import 'features/notification_service.dart';

class DailyCommandApp extends StatefulWidget {
  const DailyCommandApp({super.key});
  @override
  State<DailyCommandApp> createState() => _DailyCommandAppState();
}

class _DailyCommandAppState extends State<DailyCommandApp> {
  late Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _initialization = _initialize();
  }

  Future<void> _initialize() async {
    await DatabaseHelper.database;
    try {
      await NotificationService.init();
      await NotificationService.rescheduleFromPrefs();
    } catch (error, stackTrace) {
      debugPrint('Notification initialization failed: $error\n$stackTrace');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DAILY COMMAND',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: FutureBuilder<void>(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Unable to open the local database.'),
                      const SizedBox(height: 12),
                      Text(
                        snapshot.error.toString(),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _initialization = _initialize();
                          });
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return const MainNavigation();
        },
      ),
    );
  }
}
