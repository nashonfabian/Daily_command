import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:daily_command/app.dart';
import 'package:daily_command/database/database_helper.dart';
import 'package:daily_command/database/migrations.dart';
import 'package:daily_command/features/activities_screen.dart';
import 'package:daily_command/features/activity_repository.dart';
import 'package:daily_command/features/daily_plan_repository.dart';
import 'package:daily_command/features/daily_review_service.dart';
import 'package:daily_command/features/notification_service.dart';
import 'package:daily_command/features/stopwatch_service.dart';
import 'package:daily_command/shared/date_time_utils.dart';
import 'package:daily_command/shared/models.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path/path.dart' as path_util;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:timezone/timezone.dart' as tz;

const _notificationsChannel =
    MethodChannel('dexterous.com/flutter/local_notifications');
const _timezoneChannel = MethodChannel('daily_command/timezone');
final List<MethodCall> _notificationCalls = [];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_notificationsChannel, (call) async {
      _notificationCalls.add(call);
      if (call.method == 'pendingNotificationRequests') return [];
      if (call.method == 'requestNotificationsPermission') return false;
      return true;
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _timezoneChannel,
      (_) async => 'Africa/Dar_es_Salaam',
    );

    final path = path_util.join(
      await sqflite.getDatabasesPath(),
      'daily_command.db',
    );
    await sqflite.databaseFactory.deleteDatabase(path);
  });

  tearDownAll(() async {
    await DatabaseHelper.close();
    final path = path_util.join(
      await sqflite.getDatabasesPath(),
      'daily_command.db',
    );
    await sqflite.databaseFactory.deleteDatabase(path);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_notificationsChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_timezoneChannel, null);
  });

  test('database initializes once with the required schema', () async {
    final databases = await Future.wait(
      List.generate(4, (_) => DatabaseHelper.database),
    );
    expect(
      databases.every((database) => identical(database, databases.first)),
      isTrue,
    );

    final db = databases.first;
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final tableNames = tables.map((row) => row['name']).toSet();
    expect(
      tableNames,
      containsAll([
        'activities',
        'daily_plans',
        'daily_plan_activities',
        'activity_sessions',
        'settings',
      ]),
    );

    final foreignKeys = await db.rawQuery('PRAGMA foreign_keys');
    expect(foreignKeys.single['foreign_keys'], 1);

    final indexes = await db.rawQuery('PRAGMA index_list(activity_sessions)');
    expect(
      indexes.any((row) => row['name'] == 'idx_one_open_session'),
      isTrue,
    );
    expect(
      indexes.any((row) => row['name'] == 'idx_one_open_session_global'),
      isTrue,
    );
  });

  test('activity edits preserve daily-plan snapshots and can be restored',
      () async {
    final activityRepository = ActivityRepository();
    final planRepository = DailyPlanRepository();
    final now = DateTime.now().toUtc().toIso8601String();
    final created = await activityRepository.create(
      Activity(
        name: 'Research',
        description: 'First description',
        category: 'Learning',
        estimatedMinutes: 45,
        endNudgeEnabled: false,
        createdAt: now,
        updatedAt: now,
      ),
    );
    final plan = await planRepository.getOrCreateToday();
    final planItem = await planRepository.addActivityToPlan(
      planId: plan.id!,
      activity: created,
    );

    await activityRepository.update(
      Activity(
        id: created.id,
        name: 'Updated research',
        description: 'Updated description',
        category: 'Work',
        estimatedMinutes: 60,
        endNudgeEnabled: false,
        createdAt: created.createdAt,
        updatedAt: now,
      ),
    );

    final snapshot = (await planRepository.getPlanItems(plan.id!)).single;
    expect(snapshot.id, planItem.id);
    expect(snapshot.snapshotName, 'Research');
    expect(snapshot.snapshotCategory, 'Learning');
    expect(snapshot.estimatedMinutes, 45);

    await activityRepository.archive(created.id!);
    expect(await activityRepository.getAll(), isEmpty);
    await activityRepository.restore(created.id!);
    expect((await activityRepository.getAll()).single.name, 'Updated research');
  });

  test('concurrent creation returns one daily plan for a date', () async {
    final repository = DailyPlanRepository();
    final date = DateTimeUtils.todayLocalYYYYMMDD();
    final plans = await Future.wait(
      List.generate(4, (_) => repository.getOrCreateForDate(date)),
    );
    expect(plans.map((plan) => plan.id).toSet(), hasLength(1));
  });

  test('reordering persists only the supplied plan item IDs', () async {
    final activityRepository = ActivityRepository();
    final planRepository = DailyPlanRepository();
    final now = DateTime.now().toUtc().toIso8601String();
    final plan = await planRepository.getOrCreateForDate('2031-02-03');
    final items = <DailyPlanActivity>[];
    for (final name in ['First', 'Second', 'Third']) {
      final activity = await activityRepository.create(
        Activity(name: name, createdAt: now, updatedAt: now),
      );
      items.add(
        await planRepository.addActivityToPlan(
          planId: plan.id!,
          activity: activity,
        ),
      );
    }

    await planRepository.updateOrder(
      plan.id!,
      [items[2].id!, items[0].id!, items[1].id!],
    );
    final saved = await planRepository.getPlanItems(plan.id!);
    expect(saved.map((item) => item.id).toList(), [
      items[2].id,
      items[0].id,
      items[1].id,
    ]);

    await expectLater(
      planRepository.updateOrder(plan.id!, [items[0].id!, items[0].id!]),
      throwsArgumentError,
    );
  });

  test('stopwatch accumulates active segments and switches one timer',
      () async {
    final activityRepository = ActivityRepository();
    final planRepository = DailyPlanRepository();
    final stopwatch = StopwatchService();
    final now = DateTime.now().toUtc().toIso8601String();
    final plan = await planRepository.getOrCreateForDate('2031-02-04');
    final planItems = <DailyPlanActivity>[];
    for (final name in ['Timed one', 'Timed two', 'Timed three']) {
      final activity = await activityRepository.create(
        Activity(name: name, createdAt: now, updatedAt: now),
      );
      planItems.add(
        await planRepository.addActivityToPlan(
          planId: plan.id!,
          activity: activity,
        ),
      );
    }

    final first = planItems[0];
    await stopwatch.start(first.id!);
    var session = (await stopwatch.getOpenSession())!;
    final firstStart = DateTime.now().toUtc().subtract(
          const Duration(minutes: 2),
        );
    final db = await DatabaseHelper.database;
    await db.update(
      'activity_sessions',
      {
        'started_at': firstStart.toIso8601String(),
        'last_confirmed_at': DateTime.now().toUtc().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [session.id],
    );
    await stopwatch.pause(first.id!);
    expect(
      (await stopwatch.getTotalActiveDuration(first.id!)).inSeconds,
      greaterThanOrEqualTo(119),
    );

    await stopwatch.resume(first.id!);
    session = (await stopwatch.getOpenSession())!;
    await db.update(
      'activity_sessions',
      {
        'started_at': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 1))
            .toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [session.id],
    );
    final duration = await stopwatch.finish(first.id!);
    expect(duration.inSeconds, greaterThanOrEqualTo(179));
    expect(duration.inSeconds, lessThan(185));

    final oldSessions = await db.query(
      'activity_sessions',
      where: 'daily_plan_activity_id = ?',
      whereArgs: [first.id],
    );
    await planRepository.moveToDate(first.id!, '2031-02-06');
    final movedItem = (await planRepository.getPlanItems(
      (await planRepository.getOrCreateForDate('2031-02-06')).id!,
    ))
        .single;
    expect(movedItem.id, first.id);
    expect(
      await db.query(
        'activity_sessions',
        where: 'daily_plan_activity_id = ?',
        whereArgs: [movedItem.id],
      ),
      hasLength(oldSessions.length),
    );

    await stopwatch.start(planItems[1].id!);
    await stopwatch.start(planItems[2].id!);
    final openSession = await stopwatch.getOpenSession();
    expect(openSession?.dailyPlanActivityId, planItems[2].id);
    final pausedItem = await db.query(
      'daily_plan_activities',
      where: 'id = ?',
      whereArgs: [planItems[1].id],
    );
    expect(pausedItem.single['status'], PlanItemStatus.paused.value);
    await expectLater(
      db.insert('activity_sessions', {
        'daily_plan_activity_id': planItems[1].id,
        'started_at': DateTime.now().toUtc().toIso8601String(),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }),
      throwsA(isA<sqflite.DatabaseException>()),
    );
    await stopwatch.finish(planItems[2].id!);
    await stopwatch.start(planItems[1].id!);
    await planRepository.removeFromPlan(planItems[1].id!);
    expect(await stopwatch.getOpenSession(), isNull);
    final removed = await db.query(
      'daily_plan_activities',
      where: 'id = ?',
      whereArgs: [planItems[1].id],
    );
    expect(removed.single['status'], PlanItemStatus.removed.value);
  });

  test('interruption recovery completes at the last confirmed time', () async {
    final activityRepository = ActivityRepository();
    final planRepository = DailyPlanRepository();
    final stopwatch = StopwatchService();
    final now = DateTime.now().toUtc();
    final plan = await planRepository.getOrCreateForDate('2031-02-05');
    final activity = await activityRepository.create(
      Activity(
        name: 'Interrupted',
        createdAt: now.toIso8601String(),
        updatedAt: now.toIso8601String(),
      ),
    );
    final item = await planRepository.addActivityToPlan(
      planId: plan.id!,
      activity: activity,
    );
    await stopwatch.start(item.id!);
    final session = (await stopwatch.getOpenSession())!;
    final start = now.subtract(const Duration(hours: 8));
    final lastConfirmed = now.subtract(const Duration(hours: 7));
    final db = await DatabaseHelper.database;
    await db.update(
      'activity_sessions',
      {
        'started_at': start.toIso8601String(),
        'last_confirmed_at': lastConfirmed.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [session.id],
    );

    expect(await stopwatch.hasSuspiciousOpenSession(), isTrue);
    await stopwatch.resolveInterruption(
      session.id!,
      action: 'finish_last',
    );
    final savedSession = await db.query(
      'activity_sessions',
      where: 'id = ?',
      whereArgs: [session.id],
    );
    final savedItem = await db.query(
      'daily_plan_activities',
      where: 'id = ?',
      whereArgs: [item.id],
    );
    expect(savedSession.single['ended_at'], lastConfirmed.toIso8601String());
    expect(savedSession.single['end_reason'], 'interrupted');
    expect(savedItem.single['status'], PlanItemStatus.completed.value);
    expect(savedItem.single['completed_at'], lastConfirmed.toIso8601String());
  });

  test('next-day review is offered once and can be marked complete', () async {
    final activityRepository = ActivityRepository();
    final planRepository = DailyPlanRepository();
    final yesterday = DailyReviewService.yesterdayLocalDate();
    final now = DateTime.now().toUtc().toIso8601String();
    final plan = await planRepository.getOrCreateForDate(yesterday);
    final activity = await activityRepository.create(
      Activity(name: 'Review me', createdAt: now, updatedAt: now),
    );
    await planRepository.addActivityToPlan(
      planId: plan.id!,
      activity: activity,
    );

    expect(await DailyReviewService.shouldShowReviewForYesterday(), isTrue);
    await DailyReviewService.markReviewed(yesterday);
    expect(await DailyReviewService.shouldShowReviewForYesterday(), isFalse);
  });

  test('reminders honor quiet hours and selected weekdays', () async {
    SharedPreferences.setMockInitialValues({
      'morning_enabled': true,
      'morning_time': '23:00',
      'planned_reminder_enabled': true,
      'planned_reminder_time': '12:00',
      'free_time_reminder_enabled': false,
      'evening_enabled': false,
      'quiet_hours_enabled': true,
      'quiet_start': '22:00',
      'quiet_end': '06:00',
      'reminder_days': ['1'],
    });
    _notificationCalls.clear();

    await NotificationService.rescheduleFromPrefs();

    final schedules = _notificationCalls
        .where((call) => call.method == 'zonedSchedule')
        .map((call) => call.arguments as Map<dynamic, dynamic>)
        .toList();
    expect(schedules, hasLength(1));
    expect(schedules.single['id'], 1100 + DateTime.monday);
    expect(schedules.single['title'], contains('intended to work'));
    expect(
      schedules.single['matchDateTimeComponents'],
      isNotNull,
    );

    _notificationCalls.clear();
    final now = tz.TZDateTime.now(tz.local);
    final todayAtQuietHours = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      23,
      30,
    );
    final nudgeTime = todayAtQuietHours.isAfter(now)
        ? todayAtQuietHours
        : todayAtQuietHours.add(const Duration(days: 1));
    await NotificationService.scheduleNudge(
      id: 777,
      activityName: 'Rest',
      after: nudgeTime.difference(now),
    );
    final nudge = _notificationCalls
        .singleWhere((call) => call.method == 'zonedSchedule')
        .arguments as Map<dynamic, dynamic>;
    final scheduledNudge = DateTime.parse(
      nudge['scheduledDateTime'] as String,
    );
    expect(scheduledNudge.hour, 6);
    expect(scheduledNudge.minute, 0);
    expect(await NotificationService.requestPermission(), isFalse);
  });

  test('legacy database upgrade adds timing recovery schema and index',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('daily_command_migration_');
    final path = path_util.join(directory.path, 'legacy.db');

    final legacyDb = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE activity_sessions ('
            'id INTEGER PRIMARY KEY, '
            'daily_plan_activity_id INTEGER NOT NULL, '
            'ended_at TEXT)',
          );
          await db.insert('activity_sessions', {
            'daily_plan_activity_id': 7,
            'ended_at': '2026-01-01T10:00:00Z',
          });
        },
      ),
    );
    await legacyDb.close();

    final upgradedDb = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 4,
        onUpgrade: Migrations.migrate,
      ),
    );
    final indexes = await upgradedDb.rawQuery(
      'PRAGMA index_list(activity_sessions)',
    );
    final rows = await upgradedDb.query('activity_sessions');

    expect(
      indexes.any((row) => row['name'] == 'idx_one_open_session'),
      isTrue,
    );
    expect(
      indexes.any((row) => row['name'] == 'idx_one_open_session_global'),
      isTrue,
    );
    final columns =
        await upgradedDb.rawQuery('PRAGMA table_info(activity_sessions)');
    expect(columns.any((row) => row['name'] == 'last_confirmed_at'), isTrue);
    expect(rows, hasLength(1));

    await upgradedDb.close();
    await directory.delete(recursive: true);
  });

  testWidgets('saving an activity closes the form and refreshes the list', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => DatabaseHelper.database);
    await tester.pumpWidget(
      const MaterialApp(home: ActivitiesScreen()),
    );
    for (var attempt = 0;
        attempt < 10 && find.byType(FloatingActionButton).evaluate().isEmpty;
        attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Saved activity');
    await tester.tap(find.text('CREATE'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(tester.takeException(), isNull);
    expect(find.text('Saved activity'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('app opens and navigates between its three destinations', (
    tester,
  ) async {
    await tester.pumpWidget(const DailyCommandApp());
    for (var attempt = 0;
        attempt < 10 && find.text('DAILY COMMAND').evaluate().isEmpty;
        attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    expect(find.text('DAILY COMMAND'), findsOneWidget);
    expect(find.text('I HAVE FREE TIME'), findsOneWidget);

    await tester.tap(find.text('Activities').last);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await tester.pump();
    expect(find.text('Activities'), findsWidgets);

    await tester.tap(find.text('Settings').last);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    expect(find.text('Settings'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
