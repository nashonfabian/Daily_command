import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'migrations.dart';

class DatabaseHelper {
  static Database? _db;
  static Future<Database>? _opening;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    final opening = _opening ??= _init();
    try {
      final db = await opening;
      _db = db;
      return db;
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  static Future<Database> _init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'daily_command.db');
    return openDatabase(
      path,
      version: 4,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await Migrations.createV1(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await Migrations.migrate(db, oldVersion, newVersion);
      },
    );
  }

  static Future<void> close() async {
    final db = _db;
    if (db != null) {
      await db.close();
      _db = null;
    }
    _opening = null;
  }
}
