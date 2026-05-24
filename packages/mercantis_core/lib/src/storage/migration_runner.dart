import 'package:sqflite_common/sqflite.dart';

class MigrationRunner {
  static Future<void> migrate(Database db) async {
    final version = await _schemaVersion(db);
    if (version < 1) await _v1(db);
  }

  static Future<int> _schemaVersion(Database db) async {
    try {
      final rows = await db.query('schema_version');
      if (rows.isEmpty) return 0;
      return (rows.first['version'] as int?) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> _v1(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS schema_version (
        version INTEGER NOT NULL
      )
    ''');
    await db.insert('schema_version', {'version': 1});

    await db.execute('''
      CREATE TABLE IF NOT EXISTS doctypes (
        id TEXT PRIMARY KEY,
        payload TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS documents (
        id TEXT PRIMARY KEY,
        doctype TEXT NOT NULL,
        company TEXT,
        docstatus INTEGER NOT NULL DEFAULT 0,
        payload TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        modified_at INTEGER,
        sync_version TEXT,
        sync_state TEXT NOT NULL DEFAULT 'local',
        amended_from TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_documents_doctype ON documents (doctype)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_documents_company ON documents (company)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_documents_sync_state ON documents (sync_state)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS document_children (
        id TEXT PRIMARY KEY,
        parent_id TEXT NOT NULL,
        parent_doctype TEXT NOT NULL,
        table_name TEXT NOT NULL,
        row_index INTEGER NOT NULL,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_children_parent ON document_children (parent_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        doctype TEXT NOT NULL,
        document_id TEXT NOT NULL,
        payload TEXT NOT NULL,
        device_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        local_timestamp INTEGER NOT NULL,
        sync_version TEXT,
        status TEXT NOT NULL DEFAULT 'pending'
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_status ON sync_queue (status)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS audit_log (
        id TEXT PRIMARY KEY,
        document_id TEXT NOT NULL,
        doctype TEXT NOT NULL,
        action TEXT NOT NULL,
        user_id TEXT NOT NULL,
        device_id TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        payload TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_audit_document ON audit_log (document_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS apps (
        id TEXT PRIMARY KEY,
        version TEXT NOT NULL,
        payload TEXT NOT NULL,
        installed_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS workflows (
        id TEXT PRIMARY KEY,
        app_id TEXT,
        payload TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS workflow_transitions (
        id TEXT PRIMARY KEY,
        workflow_id TEXT NOT NULL,
        document_id TEXT NOT NULL,
        from_state TEXT NOT NULL,
        to_state TEXT NOT NULL,
        action TEXT NOT NULL,
        user_id TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_wt_document ON workflow_transitions (document_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS custom_fields (
        id TEXT PRIMARY KEY,
        doctype_id TEXT NOT NULL,
        payload TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_cf_doctype ON custom_fields (doctype_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS property_setters (
        id TEXT PRIMARY KEY,
        doctype_id TEXT NOT NULL,
        field_key TEXT NOT NULL,
        property TEXT NOT NULL,
        value TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ps_doctype ON property_setters (doctype_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS scheduler_state (
        task_key TEXT PRIMARY KEY,
        last_run_at INTEGER NOT NULL
      )
    ''');
  }
}
