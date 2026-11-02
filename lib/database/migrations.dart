import 'package:sqflite/sqflite.dart';

class Migrations {
  static Future<void> createV1(Database db) async {
    await db.execute(
        '''CREATE TABLE activities (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, description TEXT, category TEXT, estimated_minutes INTEGER, importance TEXT, end_nudge_enabled INTEGER NOT NULL DEFAULT 0, is_archived INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''');
    await db.execute(
        '''CREATE TABLE daily_plans (id INTEGER PRIMARY KEY AUTOINCREMENT, plan_date TEXT NOT NULL UNIQUE, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, timezone_id TEXT)''');
    await db.execute(
        '''CREATE TABLE daily_plan_activities (id INTEGER PRIMARY KEY AUTOINCREMENT, plan_id INTEGER NOT NULL, activity_id INTEGER, snapshot_name TEXT NOT NULL, snapshot_description TEXT, snapshot_category TEXT, display_order INTEGER NOT NULL, status TEXT NOT NULL, estimated_minutes INTEGER, importance TEXT, intent TEXT, notes TEXT, completed_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, FOREIGN KEY(plan_id) REFERENCES daily_plans(id) ON DELETE CASCADE, FOREIGN KEY(activity_id) REFERENCES activities(id) ON DELETE SET NULL)''');
    await db.execute(
        '''CREATE TABLE activity_sessions (id INTEGER PRIMARY KEY AUTOINCREMENT, daily_plan_activity_id INTEGER NOT NULL, started_at TEXT NOT NULL, ended_at TEXT, end_reason TEXT, last_confirmed_at TEXT, created_at TEXT NOT NULL, FOREIGN KEY(daily_plan_activity_id) REFERENCES daily_plan_activities(id) ON DELETE CASCADE)''');
    await db.execute(
        '''CREATE TABLE settings (id INTEGER PRIMARY KEY AUTOINCREMENT, setting_key TEXT NOT NULL UNIQUE, setting_value TEXT)''');
    await db
        .execute('CREATE INDEX idx_daily_plans_date ON daily_plans(plan_date)');
    await db.execute(
        'CREATE INDEX idx_dpa_plan_order ON daily_plan_activities(plan_id, display_order)');
    await db.execute(
        'CREATE INDEX idx_dpa_activity ON daily_plan_activities(activity_id)');
    await db.execute(
        'CREATE INDEX idx_sessions_dpa ON activity_sessions(daily_plan_activity_id, started_at)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_one_open_session ON activity_sessions(daily_plan_activity_id) WHERE ended_at IS NULL');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_one_open_session_global ON activity_sessions((1)) WHERE ended_at IS NULL');
    await db.insert('settings',
        {'setting_key': 'morning_enabled', 'setting_value': 'true'});
    await db.insert(
        'settings', {'setting_key': 'morning_time', 'setting_value': '07:00'});
    await db.insert('settings',
        {'setting_key': 'evening_enabled', 'setting_value': 'true'});
    await db.insert(
        'settings', {'setting_key': 'evening_time', 'setting_value': '20:00'});
  }

  static Future<void> migrate(Database db, int oldV, int newV) async {
    if (oldV < 2 && newV >= 2) {
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_one_open_session '
        'ON activity_sessions(daily_plan_activity_id) WHERE ended_at IS NULL',
      );
    }
    if (oldV < 4 && newV >= 4) {
      await db.execute(
        'ALTER TABLE activity_sessions ADD COLUMN last_confirmed_at TEXT',
      );
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_one_open_session_global '
        'ON activity_sessions((1)) WHERE ended_at IS NULL',
      );
    }
  }
}
