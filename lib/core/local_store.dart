import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Local-first metadata cache. Document bytes are kept in app-private storage;
/// SQLite holds their private path and synchronization state.
class LocalStore {
  LocalStore._();
  static final LocalStore instance = LocalStore._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final root = await getDatabasesPath();
    _database = await openDatabase(p.join(root, 'fyface.db'), version: 1,
        onCreate: (db, version) async {
      await db.execute('''CREATE TABLE documents (
        id TEXT PRIMARY KEY, owner_id TEXT, name TEXT NOT NULL,
        category TEXT NOT NULL, local_path TEXT, storage_path TEXT,
        created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        sync_state TEXT NOT NULL DEFAULT 'pending', is_shared INTEGER NOT NULL DEFAULT 0
      )''');
      await db.execute('''CREATE TABLE access_logs (
        id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, viewer_label TEXT NOT NULL,
        document_names TEXT NOT NULL, viewed_at TEXT NOT NULL, source TEXT NOT NULL DEFAULT 'local'
      )''');
      await db.execute('''CREATE TABLE sync_queue (
        id TEXT PRIMARY KEY, entity TEXT NOT NULL, operation TEXT NOT NULL,
        payload TEXT NOT NULL, created_at TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0
      )''');
    });
    return _database!;
  }

  Future<void> saveDocument(Map<String, Object?> document) async {
    final db = await database;
    await db.insert('documents', document, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, Object?>>> documents() async {
    final db = await database;
    return db.query('documents', orderBy: 'updated_at DESC');
  }

  Future<List<Map<String, Object?>>> pendingDocuments() async {
    final db = await database;
    return db.query('documents', where: "sync_state = 'pending'", orderBy: 'created_at ASC');
  }

  Future<void> markDocumentSynced(String id, String storagePath, String ownerId) async {
    final db = await database;
    await db.update('documents', {
      'sync_state': 'synced',
      'storage_path': storagePath,
      'owner_id': ownerId,
      'updated_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> logAccess(Map<String, Object?> log) async {
    final db = await database;
    await db.insert('access_logs', log, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
