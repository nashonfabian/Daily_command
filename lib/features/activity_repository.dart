import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';
import '../shared/models.dart';
import '../shared/date_time_utils.dart';

class ActivityRepository {
  Future<Database> get _db async => await DatabaseHelper.database;

  Future<List<Activity>> getAll({bool includeArchived=false}) async {
    final db = await _db;
    final where = includeArchived ? null : 'is_archived=0';
    final maps = await db.query('activities', where: where, orderBy: 'category ASC, name ASC');
    return maps.map((m)=>Activity.fromMap(m)).toList();
  }

  Future<List<String>> getCategories() async {
    final db = await _db;
    final res = await db.rawQuery('SELECT DISTINCT category FROM activities WHERE category IS NOT NULL AND category != "" AND is_archived=0 ORDER BY category');
    return res.map((r)=>r['category'] as String).toList();
  }

  Future<Activity> create(Activity a) async {
    final db = await _db;
    final now = DateTimeUtils.nowUtcIso();
    final map = a.toMap()..['created_at']=now..['updated_at']=now..remove('id');
    final id = await db.insert('activities', map);
    return Activity.fromMap({...map,'id':id});
  }

  Future<void> update(Activity a) async {
    final db = await _db;
    final now = DateTimeUtils.nowUtcIso();
    await db.update('activities', {...a.toMap()..['updated_at']=now..remove('id')}, where:'id=?', whereArgs:[a.id]);
  }

  Future<void> archive(int id) async {
    final db = await _db;
    await db.update('activities', {'is_archived':1, 'updated_at': DateTimeUtils.nowUtcIso()}, where:'id=?', whereArgs:[id]);
  }

  Future<void> restore(int id) async {
    final db = await _db;
    await db.update('activities', {'is_archived':0, 'updated_at': DateTimeUtils.nowUtcIso()}, where:'id=?', whereArgs:[id]);
  }

  Future<Activity?> getById(int id) async {
    final db = await _db;
    final maps = await db.query('activities', where:'id=?', whereArgs:[id], limit:1);
    if(maps.isEmpty) return null;
    return Activity.fromMap(maps.first);
  }
}
