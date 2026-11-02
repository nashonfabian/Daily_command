import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

import '../shared/app_navigation.dart';
import '../shared/date_time_utils.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static const _timezoneChannel = MethodChannel('daily_command/timezone');
  static bool _initialized = false;
  static const _reminders = <_Reminder>[
    _Reminder(
      idBase: 1000,
      enabledKey: 'morning_enabled',
      timeKey: 'morning_time',
      defaultEnabled: false,
      title: 'Today is here. What will you show up for?',
      body: 'DAILY COMMAND',
    ),
    _Reminder(
      idBase: 1100,
      enabledKey: 'planned_reminder_enabled',
      timeKey: 'planned_reminder_time',
      defaultEnabled: false,
      title: 'You intended to work on this. Ready to begin?',
      body: 'Open My Day to choose what to start.',
    ),
    _Reminder(
      idBase: 1200,
      enabledKey: 'free_time_reminder_enabled',
      timeKey: 'free_time_reminder_time',
      defaultEnabled: false,
      title: 'You have an opportunity. How will you use it?',
      body: 'Choose how much time you have in My Day.',
    ),
    _Reminder(
      idBase: 1300,
      enabledKey: 'evening_enabled',
      timeKey: 'evening_time',
      defaultEnabled: false,
      title:
          'Before today ends, is there something important you still want to show up for?',
      body: 'Review your day',
    ),
  ];

  static Future<void> init() async {
    if (_initialized) return;
    timezone_data.initializeTimeZones();
    try {
      final zoneId = await _timezoneChannel.invokeMethod<String>(
        'getLocalTimezone',
      );
      if (zoneId == null || zoneId.isEmpty) {
        throw StateError('Android did not return a local timezone.');
      }
      tz.setLocalLocation(tz.getLocation(zoneId));
      DateTimeUtils.localTimezoneId = zoneId;
    } on PlatformException catch (error, stackTrace) {
      debugPrint('Could not read the device timezone: $error\n$stackTrace');
      tz.setLocalLocation(tz.getLocation('UTC'));
      DateTimeUtils.localTimezoneId = 'UTC';
    } on MissingPluginException catch (error, stackTrace) {
      debugPrint('Timezone channel is unavailable: $error\n$stackTrace');
      tz.setLocalLocation(tz.getLocation('UTC'));
      DateTimeUtils.localTimezoneId = 'UTC';
    } on ArgumentError catch (error, stackTrace) {
      debugPrint('Unknown device timezone; using UTC: $error\n$stackTrace');
      tz.setLocalLocation(tz.getLocation('UTC'));
      DateTimeUtils.localTimezoneId = 'UTC';
    }

    const androidInitialization = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInitialization),
      onDidReceiveNotificationResponse: (_) => appNavigationIndex.value = 0,
    );
    _initialized = true;
  }

  static Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  static Future<void> refreshLocalTimezone() async {
    await init();
    try {
      final zoneId = await _timezoneChannel.invokeMethod<String>(
        'getLocalTimezone',
      );
      if (zoneId == null || zoneId.isEmpty || zoneId == tz.local.name) return;
      final location = tz.getLocation(zoneId);
      tz.setLocalLocation(location);
      DateTimeUtils.localTimezoneId = zoneId;
      await rescheduleFromPrefs();
    } on PlatformException catch (error, stackTrace) {
      debugPrint('Could not refresh the device timezone: $error\n$stackTrace');
    } on MissingPluginException catch (error, stackTrace) {
      debugPrint('Timezone channel is unavailable: $error\n$stackTrace');
    } on ArgumentError catch (error, stackTrace) {
      debugPrint('Unknown device timezone: $error\n$stackTrace');
    }
  }

  static Future<void> rescheduleFromPrefs() async {
    await init();
    final prefs = await SharedPreferences.getInstance();
    final weekdays = (prefs.getStringList('reminder_days') ??
            const ['1', '2', '3', '4', '5', '6', '7'])
        .map(int.parse)
        .toSet();

    final pending = await _plugin.pendingNotificationRequests();
    if (!(prefs.getBool('legacy_nudges_cleared') ?? false)) {
      for (final request in pending) {
        if (request.id >= 1000 && request.id < 1900) {
          await _plugin.cancel(request.id);
        }
      }
      await prefs.setBool('legacy_nudges_cleared', true);
    }
    for (final request in pending) {
      if (request.id >= 100000) await _plugin.cancel(request.id);
    }

    for (final reminder in _reminders) {
      for (var weekday = DateTime.monday;
          weekday <= DateTime.sunday;
          weekday++) {
        await _plugin.cancel(reminder.idBase + weekday);
      }
    }
    await _plugin.cancel(1);
    await _plugin.cancel(2);

    for (final reminder in _reminders) {
      if (!(prefs.getBool(reminder.enabledKey) ?? reminder.defaultEnabled)) {
        continue;
      }
      final time = _parseTime(prefs.getString(reminder.timeKey) ?? '07:00');
      if (time == null || _isInQuietHours(time.hour, time.minute, prefs)) {
        continue;
      }

      for (final weekday in weekdays) {
        if (weekday < DateTime.monday || weekday > DateTime.sunday) continue;
        await _plugin.zonedSchedule(
          reminder.idBase + weekday,
          reminder.title,
          reminder.body,
          _nextWeekdayTime(weekday, time.hour, time.minute),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'daily_command_daily',
              'Daily Reminders',
              importance: Importance.defaultImportance,
              channelDescription: 'Daily reminders and prompts',
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        );
      }
    }
  }

  static Future<void> scheduleNudge({
    required int id,
    required String activityName,
    required Duration after,
  }) async {
    if (after <= Duration.zero) return;
    await init();
    final prefs = await SharedPreferences.getInstance();
    var when = tz.TZDateTime.now(tz.local).add(after);
    if (_isInQuietHours(when.hour, when.minute, prefs)) {
      when = _quietHoursEnd(when, prefs);
    }

    await _plugin.zonedSchedule(
      nudgeNotificationId(id),
      'Your planned time is up',
      '"$activityName" — Continue, finish or switch?',
      when,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_command_nudge',
          'Estimated Nudges',
          importance: Importance.low,
          channelDescription: 'Gentle optional estimated-duration reminders',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static int nudgeNotificationId(int dailyPlanActivityId) =>
      100000 + dailyPlanActivityId;

  static Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id);
  }

  static Future<void> cancelNudge(int dailyPlanActivityId) =>
      cancel(nudgeNotificationId(dailyPlanActivityId));

  static tz.TZDateTime _nextWeekdayTime(int weekday, int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    while (scheduled.weekday != weekday || !scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  static _ReminderTime? _parseTime(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null ||
        minute == null ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      return null;
    }
    return _ReminderTime(hour: hour, minute: minute);
  }

  static bool _isInQuietHours(
    int hour,
    int minute,
    SharedPreferences prefs,
  ) {
    if (!(prefs.getBool('quiet_hours_enabled') ?? false)) return false;
    final start = _parseTime(prefs.getString('quiet_start') ?? '22:00');
    final end = _parseTime(prefs.getString('quiet_end') ?? '06:00');
    if (start == null || end == null) return false;
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    if (startMinutes == endMinutes) return false;
    final nowMinutes = hour * 60 + minute;
    return startMinutes < endMinutes
        ? nowMinutes >= startMinutes && nowMinutes < endMinutes
        : nowMinutes >= startMinutes || nowMinutes < endMinutes;
  }

  static tz.TZDateTime _quietHoursEnd(
    tz.TZDateTime when,
    SharedPreferences prefs,
  ) {
    final start = _parseTime(prefs.getString('quiet_start') ?? '22:00')!;
    final end = _parseTime(prefs.getString('quiet_end') ?? '06:00')!;
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;
    final whenMinutes = when.hour * 60 + when.minute;
    final crossesMidnight = startMinutes > endMinutes;
    final endDate = crossesMidnight && whenMinutes >= startMinutes
        ? when.add(const Duration(days: 1))
        : when;
    return tz.TZDateTime(
      tz.local,
      endDate.year,
      endDate.month,
      endDate.day,
      end.hour,
      end.minute,
    );
  }
}

class _ReminderTime {
  const _ReminderTime({required this.hour, required this.minute});

  final int hour;
  final int minute;
}

class _Reminder {
  const _Reminder({
    required this.idBase,
    required this.enabledKey,
    required this.timeKey,
    required this.defaultEnabled,
    required this.title,
    required this.body,
  });

  final int idBase;
  final String enabledKey;
  final String timeKey;
  final bool defaultEnabled;
  final String title;
  final String body;
}
