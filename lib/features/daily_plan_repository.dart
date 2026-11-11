import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../shared/date_time_utils.dart';
import '../shared/models.dart';

class DailyPlanRepository {
  Future<Database> get _db async => DatabaseHelper.database;

  Future<DailyPlan> getOrCreateToday() =>
      getOrCreateForDate(DateTimeUtils.todayLocalYYYYMMDD());

  Future<DailyPlan> getOrCreateForDate(String yyyyMMdd) async {
    final parsed = DateTime.tryParse(yyyyMMdd);
    if (parsed == null ||
        DateTimeUtils.formatDate(parsed) != yyyyMMdd ||
        yyyyMMdd.length != 10) {
      throw ArgumentError.value(yyyyMMdd, 'yyyyMMdd', 'Expected YYYY-MM-DD.');
    }

    final db = await _db;
    return db.transaction((txn) async {
      final existing = await txn.query(
        'daily_plans',
        where: 'plan_date = ?',
        whereArgs: [yyyyMMdd],
        limit: 1,
      );
      if (existing.isNotEmpty) return DailyPlan.fromMap(existing.first);

      final now = DateTimeUtils.nowUtcIso();
      final timezone =
          DateTimeUtils.localTimezoneId ?? DateTime.now().timeZoneName;
      final id = await txn.insert('daily_plans', {
        'plan_date': yyyyMMdd,
        'created_at': now,
        'updated_at': now,
        'timezone_id': timezone,
      });
      return DailyPlan(
        id: id,
        planDate: yyyyMMdd,
        createdAt: now,
        updatedAt: now,
        timezoneId: timezone,
      );
    });
  }

  Future<List<DailyPlanActivity>> getPlanItems(int planId) async {
    final db = await _db;
    final maps = await db.query(
      'daily_plan_activities',
      where: 'plan_id = ? AND status != ?',
      whereArgs: [planId, PlanItemStatus.removed.value],
      orderBy: 'display_order ASC, id ASC',
    );
    return maps.map(DailyPlanActivity.fromMap).toList();
  }

  Future<DailyPlanActivity?> getItemById(int itemId) async {
    final db = await _db;
    final rows = await db.query(
      'daily_plan_activities',
      where: 'id = ? AND status != ?',
      whereArgs: [itemId, PlanItemStatus.removed.value],
      limit: 1,
    );
    return rows.isEmpty ? null : DailyPlanActivity.fromMap(rows.first);
  }

  Future<List<DailyPlanActivity>> getAllItemsForDate(String date) async {
    final plan = await getOrCreateForDate(date);
    return getPlanItems(plan.id!);
  }

  Future<DailyPlanActivity> addActivityToPlan({
    required int planId,
    required Activity activity,
    int? estimatedOverride,
  }) async {
    if (estimatedOverride != null && estimatedOverride <= 0) {
      throw ArgumentError.value(
        estimatedOverride,
        'estimatedOverride',
        'Estimate must be greater than zero.',
      );
    }
    final db = await _db;
    return db.transaction((txn) async {
      final plan = await txn.query(
        'daily_plans',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [planId],
        limit: 1,
      );
      if (plan.isEmpty) throw StateError('Daily plan $planId does not exist.');

      final maxOrderResult = await txn.rawQuery(
        'SELECT MAX(display_order) AS max_order '
        'FROM daily_plan_activities WHERE plan_id = ?',
        [planId],
      );
      final maxOrder = (maxOrderResult.first['max_order'] as int?) ?? -1;
      final now = DateTimeUtils.nowUtcIso();
      final item = <String, Object?>{
        'plan_id': planId,
        'activity_id': activity.id,
        'snapshot_name': activity.name,
        'snapshot_description': activity.description,
        'snapshot_category': activity.category,
        'display_order': maxOrder + 1,
        'status': PlanItemStatus.notStarted.value,
        'estimated_minutes': estimatedOverride ?? activity.estimatedMinutes,
        'importance': activity.importance,
        'intent': null,
        'notes': null,
        'created_at': now,
        'updated_at': now,
      };
      final id = await txn.insert('daily_plan_activities', item);
      return DailyPlanActivity.fromMap({...item, 'id': id});
    });
  }

  Future<void> updateOrder(int planId, List<int> orderedIds) async {
    final db = await _db;
    await db.transaction((txn) async {
      final currentItems = await txn.query(
        'daily_plan_activities',
        columns: ['id'],
        where: 'plan_id = ? AND status != ?',
        whereArgs: [planId, PlanItemStatus.removed.value],
      );
      final currentIds = currentItems.map((row) => row['id'] as int).toSet();
      if (orderedIds.length != currentIds.length ||
          orderedIds.toSet().length != orderedIds.length ||
          orderedIds.toSet().difference(currentIds).isNotEmpty) {
        throw ArgumentError('The reordered IDs must match the plan items.');
      }

      final now = DateTimeUtils.nowUtcIso();
      for (var index = 0; index < orderedIds.length; index++) {
        await txn.update(
          'daily_plan_activities',
          {'display_order': index, 'updated_at': now},
          where: 'id = ? AND plan_id = ?',
          whereArgs: [orderedIds[index], planId],
        );
      }
    });
  }

  Future<void> updateItem(DailyPlanActivity item) async {
    if (item.id == null) throw ArgumentError('Plan item must have an ID.');
    final db = await _db;
    await db.update(
      'daily_plan_activities',
      {
        'snapshot_name': item.snapshotName,
        'snapshot_description': item.snapshotDescription,
        'snapshot_category': item.snapshotCategory,
        'estimated_minutes': item.estimatedMinutes,
        'importance': item.importance,
        'intent': item.intent,
        'notes': item.notes,
        'updated_at': DateTimeUtils.nowUtcIso(),
      },
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<void> removeFromPlan(int id) async {
    final db = await _db;
    await db.transaction((txn) async {
      final now = DateTimeUtils.nowUtcIso();
      await txn.update(
        'activity_sessions',
        {'ended_at': now, 'end_reason': 'paused'},
        where: 'daily_plan_activity_id = ? AND ended_at IS NULL',
        whereArgs: [id],
      );
      await txn.update(
        'daily_plan_activities',
        {
          'status': PlanItemStatus.removed.value,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<List<DailyPlanActivity>> getUnfinished(String date) async {
    final db = await _db;
    final plan = await getOrCreateForDate(date);
    final maps = await db.query(
      'daily_plan_activities',
      where: 'plan_id = ? AND status IN (?, ? ,?)',
      whereArgs: [
        plan.id,
        PlanItemStatus.notStarted.value,
        PlanItemStatus.inProgress.value,
        PlanItemStatus.paused.value,
      ],
      orderBy: 'display_order ASC, id ASC',
    );
    return maps.map(DailyPlanActivity.fromMap).toList();
  }

  Future<void> moveToDate(int itemId, String targetDate) async {
    final targetPlan = await getOrCreateForDate(targetDate);
    final db = await _db;
    await db.transaction((txn) async {
      final itemMaps = await txn.query(
        'daily_plan_activities',
        where: 'id = ? AND status != ?',
        whereArgs: [itemId, PlanItemStatus.removed.value],
        limit: 1,
      );
      if (itemMaps.isEmpty) return;

      final item = DailyPlanActivity.fromMap(itemMaps.first);
      if (item.planId == targetPlan.id) return;

      final orderResult = await txn.rawQuery(
        'SELECT MAX(display_order) AS max_order '
        'FROM daily_plan_activities WHERE plan_id = ?',
        [targetPlan.id],
      );
      final maxOrder = (orderResult.first['max_order'] as int?) ?? -1;
      final openSessions = await txn.query(
        'activity_sessions',
        columns: ['id'],
        where: 'daily_plan_activity_id = ? AND ended_at IS NULL',
        whereArgs: [itemId],
      );
      final now = DateTimeUtils.nowUtcIso();
      for (final session in openSessions) {
        await txn.update(
          'activity_sessions',
          {'ended_at': now, 'end_reason': 'paused'},
          where: 'id = ?',
          whereArgs: [session['id']],
        );
      }

      final sessions = await txn.query(
        'activity_sessions',
        columns: ['id'],
        where: 'daily_plan_activity_id = ?',
        whereArgs: [itemId],
        limit: 1,
      );
      if (openSessions.isNotEmpty) {
        await txn.update(
          'daily_plan_activities',
          {
            'status': PlanItemStatus.paused.value,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [itemId],
        );
      }

      await txn.insert('daily_plan_activities', {
        'plan_id': targetPlan.id,
        'activity_id': item.activityId,
        'snapshot_name': item.snapshotName,
        'snapshot_description': item.snapshotDescription,
        'snapshot_category': item.snapshotCategory,
        'display_order': maxOrder + 1,
        'status': sessions.isEmpty
            ? PlanItemStatus.notStarted.value
            : PlanItemStatus.paused.value,
        'estimated_minutes': item.estimatedMinutes,
        'importance': item.importance,
        'intent': null,
        'notes': null,
        'created_at': now,
        'updated_at': now,
      });
    });
  }
}
