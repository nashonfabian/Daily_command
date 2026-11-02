import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';
import '../shared/date_time_utils.dart';
import '../shared/models.dart';

class DailyReviewService {
  static String yesterdayLocalDate() {
    final today = DateTime.now();
    return DateTimeUtils.formatDate(
      DateTime(today.year, today.month, today.day)
          .subtract(const Duration(days: 1)),
    );
  }

  static Future<bool> shouldShowReviewForYesterday() async {
    final date = yesterdayLocalDate();
    final db = await DatabaseHelper.database;
    final plans = await db.query(
      'daily_plans',
      columns: ['id'],
      where: 'plan_date = ?',
      whereArgs: [date],
      limit: 1,
    );
    if (plans.isEmpty) return false;

    final planId = plans.first['id'];
    final review = await db.query(
      'settings',
      columns: ['setting_value'],
      where: 'setting_key = ?',
      whereArgs: ['reviewed_$date'],
      limit: 1,
    );
    if (review.isNotEmpty && review.first['setting_value'] == 'true') {
      return false;
    }

    final items = await db.query(
      'daily_plan_activities',
      columns: ['id'],
      where: 'plan_id = ? AND status != ?',
      whereArgs: [planId, PlanItemStatus.removed.value],
      limit: 1,
    );
    return items.isNotEmpty;
  }

  static Future<List<DailyPlanActivity>> getReviewItems(String date) async {
    final db = await DatabaseHelper.database;
    final plans = await db.query(
      'daily_plans',
      columns: ['id'],
      where: 'plan_date = ?',
      whereArgs: [date],
      limit: 1,
    );
    if (plans.isEmpty) return [];
    final rows = await db.query(
      'daily_plan_activities',
      where: 'plan_id = ? AND status != ?',
      whereArgs: [plans.first['id'], PlanItemStatus.removed.value],
      orderBy: 'display_order ASC, id ASC',
    );
    return rows.map(DailyPlanActivity.fromMap).toList();
  }

  static Future<void> markReviewed(String date) async {
    final db = await DatabaseHelper.database;
    await db.insert(
      'settings',
      {'setting_key': 'reviewed_$date', 'setting_value': 'true'},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
