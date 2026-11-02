import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../shared/date_time_utils.dart';
import '../shared/models.dart';

class StopwatchService {
  Future<Database> get _db async => DatabaseHelper.database;

  Future<Duration> getTotalActiveDuration(int dailyPlanActivityId) async {
    final db = await _db;
    final sessions = await db.query(
      'activity_sessions',
      where: 'daily_plan_activity_id = ?',
      whereArgs: [dailyPlanActivityId],
    );
    final now = DateTime.now().toUtc();
    var total = Duration.zero;
    for (final session in sessions) {
      final start = DateTime.parse(session['started_at'] as String);
      final endText = session['ended_at'] as String?;
      final end = endText == null ? now : DateTime.parse(endText);
      final elapsed = end.difference(start);
      if (!elapsed.isNegative) total += elapsed;
    }
    return total;
  }

  Future<ActivitySession?> getOpenSession() async {
    final db = await _db;
    final sessions = await db.query(
      'activity_sessions',
      where: 'ended_at IS NULL',
      limit: 1,
    );
    return sessions.isEmpty ? null : ActivitySession.fromMap(sessions.first);
  }

  Future<ActivitySession?> getOpenSessionForActivity(int itemId) async {
    final db = await _db;
    final sessions = await db.query(
      'activity_sessions',
      where: 'daily_plan_activity_id = ? AND ended_at IS NULL',
      whereArgs: [itemId],
      limit: 1,
    );
    return sessions.isEmpty ? null : ActivitySession.fromMap(sessions.first);
  }

  Future<void> start(int dailyPlanActivityId) async {
    final db = await _db;
    await db.transaction((txn) async {
      final itemRows = await txn.query(
        'daily_plan_activities',
        columns: ['status'],
        where: 'id = ?',
        whereArgs: [dailyPlanActivityId],
        limit: 1,
      );
      if (itemRows.isEmpty) {
        throw StateError('Plan item $dailyPlanActivityId does not exist.');
      }
      final status = itemRows.first['status'] as String;
      if (status == PlanItemStatus.completed.value ||
          status == PlanItemStatus.removed.value) {
        throw StateError('A completed or removed activity cannot be started.');
      }

      final openSessions = await txn.query(
        'activity_sessions',
        where: 'ended_at IS NULL',
      );
      if (openSessions.length == 1 &&
          openSessions.first['daily_plan_activity_id'] == dailyPlanActivityId) {
        return;
      }

      final now = DateTimeUtils.nowUtcIso();
      for (final session in openSessions) {
        final previousItemId = session['daily_plan_activity_id'] as int;
        await txn.update(
          'activity_sessions',
          {'ended_at': now, 'end_reason': 'paused'},
          where: 'id = ? AND ended_at IS NULL',
          whereArgs: [session['id']],
        );
        await txn.update(
          'daily_plan_activities',
          {
            'status': PlanItemStatus.paused.value,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [previousItemId],
        );
      }

      await txn.insert('activity_sessions', {
        'daily_plan_activity_id': dailyPlanActivityId,
        'started_at': now,
        'ended_at': null,
        'end_reason': null,
        'last_confirmed_at': now,
        'created_at': now,
      });
      await txn.update(
        'daily_plan_activities',
        {
          'status': PlanItemStatus.inProgress.value,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [dailyPlanActivityId],
      );
    });
  }

  Future<void> recordHeartbeat(int sessionId) async {
    final db = await _db;
    await db.update(
      'activity_sessions',
      {'last_confirmed_at': DateTimeUtils.nowUtcIso()},
      where: 'id = ? AND ended_at IS NULL',
      whereArgs: [sessionId],
    );
  }

  Future<void> pause(int dailyPlanActivityId) async {
    final db = await _db;
    await db.transaction((txn) async {
      final now = DateTimeUtils.nowUtcIso();
      await txn.update(
        'activity_sessions',
        {'ended_at': now, 'end_reason': 'paused'},
        where: 'daily_plan_activity_id = ? AND ended_at IS NULL',
        whereArgs: [dailyPlanActivityId],
      );
      await txn.update(
        'daily_plan_activities',
        {
          'status': PlanItemStatus.paused.value,
          'updated_at': now,
        },
        where: 'id = ? AND status != ?',
        whereArgs: [dailyPlanActivityId, PlanItemStatus.removed.value],
      );
    });
  }

  Future<void> resume(int dailyPlanActivityId) => start(dailyPlanActivityId);

  Future<Duration> finish(int dailyPlanActivityId) async {
    final db = await _db;
    var total = Duration.zero;
    await db.transaction((txn) async {
      final now = DateTimeUtils.nowUtcIso();
      final openSessions = await txn.query(
        'activity_sessions',
        where: 'daily_plan_activity_id = ? AND ended_at IS NULL',
        whereArgs: [dailyPlanActivityId],
      );
      for (final session in openSessions) {
        await txn.update(
          'activity_sessions',
          {'ended_at': now, 'end_reason': 'finished'},
          where: 'id = ?',
          whereArgs: [session['id']],
        );
      }

      final sessions = await txn.query(
        'activity_sessions',
        where: 'daily_plan_activity_id = ?',
        whereArgs: [dailyPlanActivityId],
      );
      for (final session in sessions) {
        final start = DateTime.parse(session['started_at'] as String);
        final end = DateTime.parse(
          session['ended_at'] as String? ?? now,
        );
        final elapsed = end.difference(start);
        if (!elapsed.isNegative) total += elapsed;
      }

      await txn.update(
        'daily_plan_activities',
        {
          'status': PlanItemStatus.completed.value,
          'completed_at': now,
          'updated_at': now,
        },
        where: 'id = ? AND status != ?',
        whereArgs: [dailyPlanActivityId, PlanItemStatus.removed.value],
      );
    });
    return total;
  }

  Future<bool> hasSuspiciousOpenSession() async {
    final session = await getOpenSession();
    if (session == null) return false;
    final now = DateTime.now().toUtc();
    final start = DateTime.parse(session.startedAt);
    if (start.isAfter(now)) return true;

    final lastConfirmed = session.lastConfirmedAt == null
        ? start
        : DateTime.parse(session.lastConfirmedAt!);
    if (lastConfirmed.isAfter(now)) return true;
    return now.difference(lastConfirmed) >= const Duration(hours: 6);
  }

  Future<void> resolveInterruption(
    int sessionId, {
    required String action,
    String? correctedEndTime,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      final rows = await txn.query(
        'activity_sessions',
        where: 'id = ? AND ended_at IS NULL',
        whereArgs: [sessionId],
        limit: 1,
      );
      if (rows.isEmpty) return;

      final session = ActivitySession.fromMap(rows.first);
      final start = DateTime.parse(session.startedAt);
      final now = DateTime.now().toUtc();
      final safeEnd = _lastConfirmedEnd(session, start, now);
      final nowIso = now.toIso8601String();

      switch (action) {
        case 'continue':
          await _closeInterrupted(txn, sessionId, safeEnd);
          await txn.insert('activity_sessions', {
            'daily_plan_activity_id': session.dailyPlanActivityId,
            'started_at': nowIso,
            'ended_at': null,
            'end_reason': null,
            'last_confirmed_at': nowIso,
            'created_at': nowIso,
          });
          await txn.update(
            'daily_plan_activities',
            {
              'status': PlanItemStatus.inProgress.value,
              'updated_at': nowIso,
            },
            where: 'id = ?',
            whereArgs: [session.dailyPlanActivityId],
          );
        case 'pause':
          await _closeInterrupted(txn, sessionId, safeEnd);
          await txn.update(
            'daily_plan_activities',
            {
              'status': PlanItemStatus.paused.value,
              'updated_at': nowIso,
            },
            where: 'id = ?',
            whereArgs: [session.dailyPlanActivityId],
          );
        case 'finish_last':
          await _closeInterrupted(txn, sessionId, safeEnd);
          await txn.update(
            'daily_plan_activities',
            {
              'status': PlanItemStatus.completed.value,
              'completed_at': safeEnd.toIso8601String(),
              'updated_at': nowIso,
            },
            where: 'id = ?',
            whereArgs: [session.dailyPlanActivityId],
          );
        case 'adjust':
          final corrected = DateTime.parse(correctedEndTime!).toUtc();
          if (corrected.isBefore(start) || corrected.isAfter(now)) {
            throw ArgumentError(
              'The adjusted end time must be between the start and now.',
            );
          }
          await txn.update(
            'activity_sessions',
            {
              'ended_at': corrected.toIso8601String(),
              'end_reason': 'corrected',
            },
            where: 'id = ?',
            whereArgs: [sessionId],
          );
          await txn.update(
            'daily_plan_activities',
            {
              'status': PlanItemStatus.paused.value,
              'updated_at': nowIso,
            },
            where: 'id = ?',
            whereArgs: [session.dailyPlanActivityId],
          );
        default:
          throw ArgumentError.value(action, 'action', 'Unknown resolution.');
      }
    });
  }

  Future<void> _closeInterrupted(
    Transaction txn,
    int sessionId,
    DateTime end,
  ) async {
    await txn.update(
      'activity_sessions',
      {
        'ended_at': end.toIso8601String(),
        'end_reason': 'interrupted',
      },
      where: 'id = ? AND ended_at IS NULL',
      whereArgs: [sessionId],
    );
  }

  DateTime _lastConfirmedEnd(
    ActivitySession session,
    DateTime start,
    DateTime now,
  ) {
    final text = session.lastConfirmedAt;
    if (text == null) return start;
    final confirmed = DateTime.parse(text);
    if (confirmed.isBefore(start)) return start;
    if (confirmed.isAfter(now)) return start;
    return confirmed;
  }
}
