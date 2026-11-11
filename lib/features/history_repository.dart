import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../shared/models.dart';

class HistoryActivityRecord {
  final DailyPlanActivity item;
  final List<ActivitySession> sessions;

  const HistoryActivityRecord({required this.item, required this.sessions});

  Duration get recordedDuration {
    final now = DateTime.now().toUtc();
    return sessions.fold(Duration.zero, (total, session) {
      final start = DateTime.parse(session.startedAt);
      final end =
          session.endedAt == null ? now : DateTime.parse(session.endedAt!);
      final duration = end.difference(start);
      return duration.isNegative ? total : total + duration;
    });
  }
}

class HistoryDay {
  final DailyPlan plan;
  final List<HistoryActivityRecord> activities;

  const HistoryDay({required this.plan, required this.activities});

  Duration get recordedDuration => activities.fold(
        Duration.zero,
        (total, activity) => total + activity.recordedDuration,
      );
}

class HistoryRepository {
  Future<Database> get _db async => DatabaseHelper.database;

  Future<HistoryDay?> getDay(String date) async {
    final db = await _db;
    final plans = await db.query(
      'daily_plans',
      where: 'plan_date = ?',
      whereArgs: [date],
      limit: 1,
    );
    if (plans.isEmpty) return null;

    final plan = DailyPlan.fromMap(plans.first);
    final itemRows = await db.query(
      'daily_plan_activities',
      where: 'plan_id = ?',
      whereArgs: [plan.id],
      orderBy: 'display_order ASC, id ASC',
    );
    if (itemRows.isEmpty) {
      return HistoryDay(plan: plan, activities: const []);
    }

    final items = itemRows.map(DailyPlanActivity.fromMap).toList();
    final placeholders = List.filled(items.length, '?').join(', ');
    final sessionRows = await db.query(
      'activity_sessions',
      where: 'daily_plan_activity_id IN ($placeholders)',
      whereArgs: items.map((item) => item.id).toList(),
      orderBy: 'started_at ASC, id ASC',
    );
    final sessionsByItem = <int, List<ActivitySession>>{};
    for (final row in sessionRows) {
      final session = ActivitySession.fromMap(row);
      sessionsByItem
          .putIfAbsent(session.dailyPlanActivityId, () => [])
          .add(session);
    }

    return HistoryDay(
      plan: plan,
      activities: [
        for (final item in items)
          HistoryActivityRecord(
            item: item,
            sessions: sessionsByItem[item.id] ?? const [],
          ),
      ],
    );
  }
}
