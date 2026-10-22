import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// On-device cache for offline-drafted claims (ARCHITECTURE.md §1 — "two
/// databases, two different jobs"). Postgres is the only system of record;
/// this is purely a local holding pen until a draft syncs. Schema is
/// deliberately denormalized (line_items as a JSON blob column) because
/// this table only ever round-trips through ClaimDraft.toJson() — it isn't
/// queried relationally the way Postgres is.
///
/// What happens to a row after a successful sync (deleted vs. kept as a
/// read cache) is OPEN/PENDING per ARCHITECTURE.md §1 — this class only
/// implements write-while-offline + mark-synced; the policy decision is
/// deferred, not assumed here.
class LocalDraftDb {
  LocalDraftDb._();
  static final LocalDraftDb instance = LocalDraftDb._();

  static const _dbName = 'claim_drafts.db';
  static const table = 'draft_claim';

  Database? _db;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(dir.path, _dbName);
    _db = await openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) => db.execute('''
        CREATE TABLE $table (
          id TEXT PRIMARY KEY,
          claim_type_id INTEGER NOT NULL,
          title TEXT NOT NULL,
          description TEXT,
          claim_currency_code TEXT NOT NULL,
          line_items_json TEXT NOT NULL,
          synced INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL
        )
      '''),
    );
    return _db!;
  }

  Future<void> saveDraft(Map<String, dynamic> row) async {
    final db = await _open();
    await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> unsyncedDrafts() async {
    final db = await _open();
    return db.query(table, where: 'synced = 0');
  }

  Future<void> markSynced(String id) async {
    final db = await _open();
    await db.update(table, {'synced': 1}, where: 'id = ?', whereArgs: [id]);
  }
}
