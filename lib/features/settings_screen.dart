import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _morningEnabled = false;
  String _morningTime = '07:00';
  bool _plannedEnabled = false;
  String _plannedTime = '12:00';
  bool _freeTimeEnabled = false;
  String _freeTimeReminderTime = '15:00';
  bool _eveningEnabled = false;
  String _eveningTime = '20:00';
  bool _quietEnabled = false;
  String _quietStart = '22:00';
  String _quietEnd = '06:00';
  bool _use24HourTime = true;
  int _defaultFreeTime = 20;
  Set<int> _selectedDays = {1, 2, 3, 4, 5, 6, 7};
  bool _loading = true;

  static const _weekdayLabels = {
    DateTime.monday: 'Mon',
    DateTime.tuesday: 'Tue',
    DateTime.wednesday: 'Wed',
    DateTime.thursday: 'Thu',
    DateTime.friday: 'Fri',
    DateTime.saturday: 'Sat',
    DateTime.sunday: 'Sun',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _morningEnabled = prefs.getBool('morning_enabled') ?? false;
      _morningTime = prefs.getString('morning_time') ?? '07:00';
      _plannedEnabled = prefs.getBool('planned_reminder_enabled') ?? false;
      _plannedTime = prefs.getString('planned_reminder_time') ?? '12:00';
      _freeTimeEnabled = prefs.getBool('free_time_reminder_enabled') ?? false;
      _freeTimeReminderTime =
          prefs.getString('free_time_reminder_time') ?? '15:00';
      _eveningEnabled = prefs.getBool('evening_enabled') ?? false;
      _eveningTime = prefs.getString('evening_time') ?? '20:00';
      _quietEnabled = prefs.getBool('quiet_hours_enabled') ?? false;
      _quietStart = prefs.getString('quiet_start') ?? '22:00';
      _quietEnd = prefs.getString('quiet_end') ?? '06:00';
      _use24HourTime = prefs.getBool('use_24_hour_time') ?? true;
      _defaultFreeTime = prefs.getInt('default_free_time') ?? 20;
      _selectedDays = (prefs.getStringList('reminder_days') ??
              const ['1', '2', '3', '4', '5', '6', '7'])
          .map(int.parse)
          .toSet();
      _loading = false;
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('morning_enabled', _morningEnabled);
    await prefs.setString('morning_time', _morningTime);
    await prefs.setBool('planned_reminder_enabled', _plannedEnabled);
    await prefs.setString('planned_reminder_time', _plannedTime);
    await prefs.setBool('free_time_reminder_enabled', _freeTimeEnabled);
    await prefs.setString('free_time_reminder_time', _freeTimeReminderTime);
    await prefs.setBool('evening_enabled', _eveningEnabled);
    await prefs.setString('evening_time', _eveningTime);
    await prefs.setBool('quiet_hours_enabled', _quietEnabled);
    await prefs.setString('quiet_start', _quietStart);
    await prefs.setString('quiet_end', _quietEnd);
    await prefs.setBool('use_24_hour_time', _use24HourTime);
    await prefs.setInt('default_free_time', _defaultFreeTime);
    await prefs.setStringList(
      'reminder_days',
      (_selectedDays.toList()..sort()).map((day) => day.toString()).toList(),
    );
    await NotificationService.rescheduleFromPrefs();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
  }

  Future<bool> _explainAndRequestPermission() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Allow local reminders?'),
        content: const Text(
          'DAILY COMMAND uses notifications for reminders you choose. '
          'They are scheduled on this device and may be delayed by Android '
          'battery settings. Your activities and timers work without them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (accepted != true) return false;
    return NotificationService.requestPermission();
  }

  Future<void> _setReminderEnabled(String key, bool enabled) async {
    if (enabled) {
      final granted = await _explainAndRequestPermission();
      if (!mounted) return;
      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Notification permission was not granted. The app still works offline.',
            ),
          ),
        );
        return;
      }
    }

    setState(() {
      switch (key) {
        case 'morning':
          _morningEnabled = enabled;
        case 'planned':
          _plannedEnabled = enabled;
        case 'free_time':
          _freeTimeEnabled = enabled;
        case 'evening':
          _eveningEnabled = enabled;
      }
    });
    await _save();
  }

  Future<void> _pickTime(String key) async {
    final value = switch (key) {
      'morning' => _morningTime,
      'planned' => _plannedTime,
      'free_time' => _freeTimeReminderTime,
      'evening' => _eveningTime,
      'quiet_start' => _quietStart,
      'quiet_end' => _quietEnd,
      _ => throw ArgumentError.value(key, 'key', 'Unknown time preference.'),
    };
    final parts = value.split(':');
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          alwaysUse24HourFormat: _use24HourTime,
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    final formatted =
        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
    setState(() {
      switch (key) {
        case 'morning':
          _morningTime = formatted;
        case 'planned':
          _plannedTime = formatted;
        case 'free_time':
          _freeTimeReminderTime = formatted;
        case 'evening':
          _eveningTime = formatted;
        case 'quiet_start':
          _quietStart = formatted;
        case 'quiet_end':
          _quietEnd = formatted;
      }
    });
    await _save();
  }

  String _displayTime(String value) {
    final parts = value.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    if (_use24HourTime) return value;
    final suffix = hour < 12 ? 'AM' : 'PM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${minute.toString().padLeft(2, '0')} $suffix';
  }

  Future<void> _toggleDay(int day, bool selected) async {
    setState(() {
      if (selected) {
        _selectedDays.add(day);
      } else {
        _selectedDays.remove(day);
      }
    });
    await _save();
  }

  Widget _reminderCard({
    required String title,
    required String key,
    required bool enabled,
    required String time,
  }) {
    return Card(
      child: Column(
        children: [
          SwitchListTile(
            title: Text(title),
            subtitle: Text(_displayTime(time)),
            value: enabled,
            onChanged: (value) => _setReminderEnabled(key, value),
          ),
          ListTile(
            title: const Text('Reminder time'),
            trailing: Text(_displayTime(time)),
            onTap: () => _pickTime(key),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'TODAY MATTERS. SHOW UP.',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1),
          ),
          const SizedBox(height: 16),
          const Text(
            'Reminders are optional and local to this device. Delivery may '
            'depend on Android permission, battery settings and device scheduling.',
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final granted = await _explainAndRequestPermission();
              if (!mounted) return;
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    granted
                        ? 'Notification permission granted'
                        : 'Permission not granted — all core features remain available',
                  ),
                ),
              );
              if (granted) await NotificationService.rescheduleFromPrefs();
            },
            child: const Text('Request notification permission'),
          ),
          const SizedBox(height: 16),
          const Text(
            'Reminder days',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          Wrap(
            spacing: 4,
            children: [
              for (final entry in _weekdayLabels.entries)
                FilterChip(
                  label: Text(entry.value),
                  selected: _selectedDays.contains(entry.key),
                  onSelected: (selected) => _toggleDay(entry.key, selected),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _reminderCard(
            title: 'Morning reminder',
            key: 'morning',
            enabled: _morningEnabled,
            time: _morningTime,
          ),
          _reminderCard(
            title: 'Planned activity reminder',
            key: 'planned',
            enabled: _plannedEnabled,
            time: _plannedTime,
          ),
          _reminderCard(
            title: 'Free-time prompt reminder',
            key: 'free_time',
            enabled: _freeTimeEnabled,
            time: _freeTimeReminderTime,
          ),
          _reminderCard(
            title: 'Evening review reminder',
            key: 'evening',
            enabled: _eveningEnabled,
            time: _eveningTime,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Quiet hours',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Enable quiet hours'),
                    value: _quietEnabled,
                    onChanged: (value) {
                      setState(() => _quietEnabled = value);
                      _save();
                    },
                  ),
                  if (_quietEnabled) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Start'),
                      trailing: Text(_displayTime(_quietStart)),
                      onTap: () => _pickTime('quiet_start'),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('End'),
                      trailing: Text(_displayTime(_quietEnd)),
                      onTap: () => _pickTime('quiet_end'),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Use 24-hour time'),
                  value: _use24HourTime,
                  onChanged: (value) {
                    setState(() => _use24HourTime = value);
                    _save();
                  },
                ),
                ListTile(
                  title: const Text('Default free-time choice'),
                  trailing: DropdownButton<int>(
                    value: _defaultFreeTime,
                    items: const [
                      DropdownMenuItem(value: 10, child: Text('10 min')),
                      DropdownMenuItem(value: 20, child: Text('20 min')),
                      DropdownMenuItem(value: 30, child: Text('30 min')),
                      DropdownMenuItem(value: 60, child: Text('60+ min')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _defaultFreeTime = value);
                      _save();
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('About', style: TextStyle(fontWeight: FontWeight.w800)),
                  SizedBox(height: 8),
                  Text(
                    'DAILY COMMAND helps you recognise the value of the '
                    'present moment, choose meaningful activities and show up for them today.',
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Offline-first • No account • No backend • SQLite local • '
                    'Rest is legitimate • No streaks or scores.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
