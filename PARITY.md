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
| **Notification inbox + log** (ADR-048) | ✅ | ✅ | persistent log + reader API (`notification_inbox.dart`); **UI ❌** |
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
| Generic form view | 🟡 | ~13 of 34 field types real; rest fall back to text editor |
| Date/time & media/attachment field widgets | 🟡 | date picker only; time, dateTime, file/attach, signature, color, barcode fall back to text |
| Generic list views | ✅ | no bulk/multi-select |
| Record workspace chrome (Form/Timeline/Attachments) | 🟡 | Timeline & Attachments tabs are placeholders (no-op buttons) |
| Form builder (palette/canvas/inspector) | 🟡 | **save not wired** to DocumentEngine |
| Command palette / global search | ✅ | Cmd-K |
| Workspaces / dashboard cards | 🟡 | cards render; need real DashboardEngine data via the grid |
| Approvals inbox | ✅ | |
| **Notification inbox** | ❌ | engine done; reader UI missing (only approvals inbox exists) |
| **Report viewer** | ❌ | render `ReportResult` as table + CSV export (Swift: `GenericReportView`) |
| **Dashboard grid** | ❌ | render `DashboardResult` widgets (only a `DashboardCard` wrapper exists) |
| **Attachments UI** | ❌ | list/upload bound to the attachment engine |
| **Import / Export UI** | ❌ | bound to the import/export engine |
| **Print / PDF UI** | ❌ | print action + format picker bound to the print service |
| Settings screen | 🟡 | route is a "coming soon" stub |
| Recents | ❌ | |

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
