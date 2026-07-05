import 'package:sqflite_common/sqflite.dart';

class MigrationRunner {
  static Future<void> migrate(Database db) async {
    final version = await _schemaVersion(db);
    if (version < 1) await _v1(db);
    if (version < 2) await _v2(db);
    if (version < 3) await _v3(db);
    if (version < 4) await _v4(db);
    if (version < 5) await _v5(db);
    if (version < 6) await _v6(db);
    if (version < 7) await _v7(db);
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

  /// v2: positioning support for end-user custom fields.
  ///
  /// Adds `insert_after` to `custom_fields` so users can place their own
  /// field after any existing field on the form. `NULL` means "append to
  /// the end of the form", matching the v1 behaviour for any pre-existing
  /// rows on upgrade.
  static Future<void> _v2(Database db) async {
    await db.execute(
      'ALTER TABLE custom_fields ADD COLUMN insert_after TEXT',
    );
    await db.update('schema_version', {'version': 2});
  }

  /// v3: per-device naming counter blocks (ADR-042).
  ///
  /// `naming_block_allocations` is the shared high-water mark per series;
  /// `naming_counter_blocks` records the disjoint block each device has
  /// reserved (and how far into it the device has consumed), so offline
  /// multi-device saves draw from non-overlapping ranges and numbers are never
  /// reused after a delete.
  static Future<void> _v3(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS naming_block_allocations (
        series TEXT PRIMARY KEY,
        allocated_through INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS naming_counter_blocks (
        series TEXT NOT NULL,
        device_id TEXT NOT NULL,
        block_start INTEGER NOT NULL,
        block_end INTEGER NOT NULL,
        next_value INTEGER NOT NULL,
        PRIMARY KEY (series, device_id)
      )
    ''');
    await db.update('schema_version', {'version': 3});
  }

  /// v4: persistent notification log (ADR-048).
  ///
  /// Replaces the in-memory default sink for production: channels (the in-app
  /// inbox, future email/SMS adapters) write to and read from this table via
  /// `SqliteNotificationLog` and `NotificationInbox`. `read_at` is null until
  /// the in-app inbox marks an entry read. Timestamps are epoch milliseconds,
  /// matching the rest of the Dart schema.
  static Future<void> _v4(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notification_log (
        id TEXT PRIMARY KEY NOT NULL,
        app_id TEXT NOT NULL,
        doc_type TEXT NOT NULL,
        document_id TEXT NOT NULL,
        channel TEXT NOT NULL,
        recipient TEXT,
        subject TEXT NOT NULL DEFAULT '',
        body TEXT NOT NULL DEFAULT '',
        emitted_at INTEGER NOT NULL,
        read_at INTEGER
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_notification_recipient ON notification_log (recipient)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_notification_emitted_at ON notification_log (emitted_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_notification_unread ON notification_log (recipient, read_at)');
    await db.update('schema_version', {'version': 4});
  }

  /// v5: file attachments (ADR-043).
  ///
  /// Bytes live on disk under the attachment store's root; this table holds
  /// metadata only. `field_key` is nullable: null is a general document
  /// attachment, non-null binds it to a `FieldType.attach` field for typed UI.
  /// `uploaded_at` is epoch millis, matching the rest of the schema.
  static Future<void> _v5(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS attachments (
        id TEXT PRIMARY KEY NOT NULL,
        document_id TEXT NOT NULL,
        doc_type TEXT NOT NULL,
        field_key TEXT,
        file_name TEXT NOT NULL,
        mime_type TEXT NOT NULL DEFAULT 'application/octet-stream',
        byte_size INTEGER NOT NULL,
        storage_path TEXT NOT NULL,
        uploaded_at INTEGER NOT NULL,
        uploaded_by TEXT NOT NULL,
        sha256 TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_attachments_document ON attachments (document_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_attachments_doctype ON attachments (doc_type)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_attachments_field ON attachments (document_id, field_key)');
    await db.update('schema_version', {'version': 5});
  }

  /// Posting batches (C2) — the atomic-posting ledger: one row per posting
  /// attempt for a source document, with status / idempotency / reversal
  /// linkage. Core owns the primitive; Hub owns the accounting rules.
  static Future<void> _v6(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS posting_batches (
        id TEXT PRIMARY KEY NOT NULL,
        source_type TEXT NOT NULL,
        source_id TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        version INTEGER NOT NULL DEFAULT 1,
        error_code TEXT,
        error_message TEXT,
        posted_at INTEGER,
        posted_by TEXT NOT NULL DEFAULT '',
        reversal_of_batch TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_posting_batches_source ON posting_batches (source_type, source_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_posting_batches_status ON posting_batches (status)');
    await db.update('schema_version', {'version': 6});
  }

  /// v7: per-operator broadcast read receipts (ADR-048 follow-up).
  ///
  /// A broadcast notification (`notification_log.recipient IS NULL`) is shared
  /// across operators and has a single `read_at`, so marking it read for one
  /// operator would mark it read for all. This table records, per (broadcast,
  /// viewer), when a specific operator read a broadcast — letting the audience
  /// inbox resolve broadcast read state per operator without touching the shared
  /// column. Addressed notifications keep using `read_at`. `viewer_id` is the
  /// operator's stable user id; `read_at` is epoch millis.
  static Future<void> _v7(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notification_broadcast_receipt (
        notification_id TEXT NOT NULL,
        viewer_id TEXT NOT NULL,
        read_at INTEGER NOT NULL,
        PRIMARY KEY (notification_id, viewer_id)
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_broadcast_receipt_viewer ON notification_broadcast_receipt (viewer_id)');
    await db.update('schema_version', {'version': 7});
  }
}
