# Mercantis Core — Architecture

## Package structure

```
mercantis.core.flutter/
├── packages/
│   ├── mercantis_core/        # Pure Dart headless engine (no Flutter)
│   └── mercantis_core_ui/    # Flutter UI shell
└── app/                      # Dev-shell Flutter application
```

## mercantis_core — subsystem map

```
lib/src/
├── metadata/          # DocType registry, field definitions, MetaComposer
├── document_engine/   # Save / delete / fetch / list / submit / cancel / amend
├── storage/           # SQLite via sqflite_common; MigrationRunner
├── permissions/       # DocType-level, field-level, row-level checks
├── workflow/          # State-machine transitions with role + condition guards
├── expression_engine/ # Lexer → Parser → Evaluator (recursive descent AST)
├── sync_engine/       # Offline-first mutation queue; push / pull / apply
├── naming/            # UUID, NamingSeries, FieldDerived, Format strategies
├── automation/        # Event-triggered rule runner; built-in action handlers
├── notifications/     # Typed EventEmitter (publish / subscribe)
├── app_runtime/       # AppManifest + AppInstaller
├── scheduling/        # Tick-based scheduler with 5-field cron parser
└── customization/     # CustomField + PropertySetter overlays
```

## Key design decisions

### Metadata-driven entities
All document types are described by `DocType` + `FieldDefinition` objects stored in SQLite. Adding a new entity type requires no schema migration — only a new `DocType` registration via `AppInstaller.install()`. Business data lives in a single `documents` table with a JSON `data` column; `json_extract()` is used for indexed queries.

### Offline-first sync
Every write appended to `sync_queue` as a `MutationRecord`. `SyncEngine` pushes pending mutations to any `CloudAdapter` implementation and pulls remote mutations, resolving conflicts via configurable `ConflictResolution` policy (lastWriteWins | versionCheckedMerge | appendOnly).

### Expression engine
Boolean conditions and formula fields are evaluated by a full recursive-descent parser (`Lexer` → `ExpressionParser` → `ExpressionEvaluator`). Parsed ASTs are cached (LRU, 256 entries). Supported: arithmetic, comparisons, string ops, dot-notation for user context (`user.role`), built-in functions (`len`, `contains`, `startsWith`, `upper`, `lower`, `now`, `today`).

### No code generation
The project deliberately avoids `drift`, `freezed`, and `json_serializable`. All serialisation is hand-written with `dart:convert`. This keeps the `flutter pub get` → build cycle free of `build_runner`.

### Optimistic concurrency
`DocumentEngine.save()` compares `localVersion` on the stored row before writing; a mismatch raises `ConcurrencyConflictError`. Each successful write increments `localVersion` and appends a `DocumentVersion` diff to `audit_log`.

### Adaptive layout
`NavigationShell` / `HubShell` switch between `NavigationRail` (≥ 800 px wide) and `NavigationBar` (narrow / phone). No platform conditionals — the same widget tree runs on iOS, iPadOS, macOS, and Windows.

## Data flow — document save

```
UI field change
  └─> _changes map updated (no widget rebuild per keystroke)

User taps Save
  └─> DocumentEngine.save(doc)
        ├─ NamingService.generate()          (assign name if new)
        ├─ ValidationPipeline.run()          (required, unique, link checks)
        ├─ SQLite INSERT / UPDATE            (optimistic concurrency check)
        ├─ audit_log INSERT                  (DocumentVersion diff)
        ├─ SyncEngine.appendMutation()       (enqueue to sync_queue)
        └─ EventEmitter.publish(DocumentSavedEvent)
              └─> AutomationRunner evaluates matching rules
```

## Platform targets

| Platform | SQLite driver | Min OS |
|----------|--------------|--------|
| iOS / iPadOS | `sqflite` (sqflite_darwin) | 17.0 |
| macOS | `sqflite_common_ffi` | 14.0 |
| Windows 11 | `sqflite_common_ffi` | 11 |

`_platformFactory()` in `core_providers.dart` selects the correct `DatabaseFactory` at runtime using `dart:io Platform` checks.

## State management

`flutter_riverpod` is used throughout `mercantis_core_ui`. All engines are exposed as `FutureProvider` instances that chain on `mercantisDatabaseProvider`. The dependency graph:

```
mercantisDatabaseProvider
  ├─ metadataRegistryProvider
  │    └─ metaComposerProvider
  │         └─ resolvedMetaProvider (family)
  ├─ namingServiceProvider
  ├─ eventEmitterProvider (sync, no Future)
  ├─ syncEngineProvider
  ├─ documentEngineProvider
  ├─ workflowEngineProvider
  ├─ schedulerServiceProvider
  ├─ automationRunnerProvider
  └─ appInstallerProvider
```

## Navigation

`go_router` with a `ShellRoute` wrapping the adaptive navigation shell. Routes:

| Path | Widget |
|------|--------|
| `/home` | `DocTypeListView` — modules grouped by `DocType.module` |
| `/list/:docType` | `GenericListView` — paginated document list |
| `/form/:docType/new` | `GenericFormView` — new document |
| `/form/:docType/:name` | `GenericFormView` — existing document |
| `/form-builder/:docType` | `FormBuilderView` — palette / canvas / inspector |
| `/settings` | Settings placeholder |

`RecordWorkspaceChrome` wraps every form with three tabs: **Form** / **Timeline** / **Attachments**. The `CommandBarView` above the tab bar shows Save, Submit, Cancel, and Amend actions based on `docstatus`.
