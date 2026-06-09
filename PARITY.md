# Core — Flutter Parity Tracker

Tracks the Flutter port of `mercantis.core.app` (Swift/SwiftUI) toward feature
parity. The Swift app is the source of truth; this file is the burndown.

**Strategy:** _ERP correctness first._ Engine subsystems and anything the Hub
ERP depends on (reporting, ledger-adjacent plumbing) lead; UI capstones follow.

**Status:** the headless **engine** layer has effectively reached parity — the
last engine gaps (attachments, import/export, printing, saved reports,
notification inbox) all landed. The remaining work is now almost entirely in
the **UI shell**: surfacing those engines in screens, plus the report/dashboard
viewers and richer field widgets.

Legend: ✅ parity · 🟡 partial / stubbed · ❌ missing

## Headless engine — `packages/mercantis_core`

| Subsystem | Swift | Flutter | Notes |
|-----------|:----:|:------:|-------|
| Metadata registry, field defs, MetaComposer | ✅ | ✅ | 34 field types defined |
| Document engine (CRUD, submit/cancel/amend) | ✅ | ✅ | optimistic concurrency, audit diffs |
| Validation pipeline | ✅ | ✅ | required/unique/link/rule stages |
| Storage + migrations | ✅ | ✅ | sqflite_common |
| Permissions (doctype/field/row) | ✅ | ✅ | |
| Workflow engine | ✅ | ✅ | role + condition guards |
| Expression engine | ✅ | ✅ | recursive-descent, LRU cache |
| Sync engine + conflict resolution | ✅ | ✅ | LWW / VCM / append-only |
| **FileSystemCloudAdapter** (ADR-047) | ✅ | ✅ | peer-to-peer shared-folder sync |
| Naming strategies | ✅ | ✅ | uuid / series / field / format |
| **Per-device counter blocks** (ADR-042) | ✅ | ✅ | offline-safe series allocation |
| Automation runner + built-in actions | ✅ | ✅ | |
| **Scheduled rules** (ADR-041) | ✅ | ✅ | `onSchedule` fan-out |
| Notifications / EventEmitter | ✅ | ✅ | events ✅ |
| **Notification inbox + log** (ADR-048) | ✅ | ✅ | persistent log + reader API; **UI ✅** (`NotificationInboxView`) |
| Scheduling (cron, tick) | ✅ | ✅ | |
| Customization (custom fields, property setters) | ✅ | ✅ | |
| App runtime (manifest, installer) | ✅ | ✅ | |
| Reporting — ReportEngine execution | ✅ | ✅ | engine done; **UI viewer ❌** |
| Dashboards — DashboardEngine execution | ✅ | ✅ | engine done; **UI grid ❌** |
| **Saved reports** (ADR-050) | ✅ | ✅ | `SavedReportEngine` — registry, role-gating, persistent defs |
| **Files / Attachments** (ADR-043) | ✅ | ✅ | `attachment` + manager + store; **UI ❌** |
| **Import / Export (CSV/JSON)** (ADR-046) | ✅ | ✅ | bulk importer/exporter + CSV codec; **UI ❌** |
| **Printing / PDF** (ADR-044) | ✅ | ✅ | `PrintFormat` + plain-text/PDF renderers; **UI ❌** |

> Engine parity reached. The ✅ entries flagged **UI ❌** above have a working
> headless engine but are not yet wired to any screen — those bindings are
> tracked in the UI shell table below.

## UI shell — `packages/mercantis_core_ui`

| Surface | Status | Notes |
|---------|:----:|-------|
| Adaptive shell / navigation / routing | ✅ | phone/tablet/desktop breakpoints |
| Generic form view | 🟡 | ~16 of 34 field types real; rest fall back to text editor |
| Date/time & media/attachment field widgets | 🟡 | **date, time, dateTime pickers + signature, color, barcode now real**; file/attach (and code/geolocation/rating/duration) still fall back to text |
| Generic list views | ✅ | no bulk/multi-select |
| Record workspace chrome (Form/Timeline/Attachments) | ✅ | Attachments tab (`AttachmentsPanel`) + **Timeline tab now live** (`DocumentTimelineView` over the audit log: created/updated events with field diffs) |
| Form builder (palette/canvas/inspector) | ✅ | editable — add / rename / toggle-required / reorder / delete **custom fields**, persisted via `CustomField` on Save (cache invalidated so the form picks them up); base fields shown read-only |
| Command palette / global search | ✅ | Cmd-K |
| Workspaces / dashboard cards | 🟡 | cards render; need real DashboardEngine data via the grid |
| Approvals inbox | ✅ | |
| **Notification inbox** | ✅ | `NotificationInboxView` (list, unread styling, mark-read/mark-all, swipe-delete) + providers, exported from core_ui |
| **Report viewer** | ✅ | `ReportResultView` renders a `ReportResult` as a table + Copy-CSV (exported from core_ui) |
| **Dashboard grid** | ✅ | `DashboardResultGrid` renders a `DashboardResult` (count/sum/list/shortcut/chart, per-widget error isolation) |
| **Attachments UI** | ✅ | `AttachmentsPanel` (list/upload/delete via `AttachmentManager`, file_picker) wired into the record Attachments tab |
| **Import / Export UI** | ✅ | `ImportExportMenu` (export CSV/JSON, import file via file_picker → report) in the list trailing actions |
| **Print / PDF UI** | ✅ | `PrintRecordButton` renders a record (auto default format) to a real PDF via `PrintService` (pure-Dart `pdf` renderer) and hands it to the `printing` plugin — native print/preview (`layoutPdf`) + share sheet (`sharePdf`) |
| Settings screen | 🟡 | route is a "coming soon" stub |
| **Recents** | ✅ | `RecentsView` over `recentsProvider`/`RecentsStore` — opened records persisted in a `ui_recents` table (MRU, de-duped, capped at 20), recorded from `GenericFormView`; routes back on tap |

## Sequenced plan (engine done → UI capstones)

1. **Phase 4 — report/dashboard UI.** `GenericReportView` (table + CSV export)
   and the dashboard grid that renders `DashboardResult` widgets; feeds Hub's
   reports & de-mocks dashboard cards.
2. **Phase 5 — wire landed engines to UI.** Attachments list/upload,
   notification inbox reader, import/export actions, print/PDF action — all
   have working engines awaiting screens.
3. **Phase 6 — UI capstones.** Settings screen, real field widgets (time,
   dateTime, file, signature, color, barcode), form-builder persistence,
   Timeline/Attachments/Recents tabs.

> Hub-side business logic (ledger derivation, stock balance) lives in the
> **Hub** repo's `PARITY.md`; it is the critical path and proceeds in parallel.
> The report/dashboard execution engine it depends on has landed.
