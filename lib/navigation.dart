import 'package:flutter/material.dart';
import 'shared/app_navigation.dart';
import 'features/my_day_screen.dart';
import 'features/activities_screen.dart';
import 'features/settings_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});
  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _index = appNavigationIndex.value;
  final _screens = const [MyDayScreen(), ActivitiesScreen(), SettingsScreen()];

  @override
  void initState() {
    super.initState();
    appNavigationIndex.addListener(_navigationChanged);
  }

  @override
  void dispose() {
    appNavigationIndex.removeListener(_navigationChanged);
    super.dispose();
  }

  void _navigationChanged() {
    if (mounted) setState(() => _index = appNavigationIndex.value);
  }

  @override
  Widget build(BuildContext context){
    return Scaffold(
      body: _screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i)=>appNavigationIndex.value=i,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.wb_sunny_outlined), selectedIcon: Icon(Icons.wb_sunny), label: 'My Day'),
          NavigationDestination(icon: Icon(Icons.list_alt_outlined), selectedIcon: Icon(Icons.list_alt), label: 'Activities'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
