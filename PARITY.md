# Core — Flutter Parity Tracker

Tracks the Flutter port of `mercantis.core.app` (Swift/SwiftUI) toward feature
parity. The Swift app is the source of truth; this file is the burndown.

**Strategy:** _ERP correctness first._ Engine subsystems and anything the Hub
ERP depends on (reporting, ledger-adjacent plumbing) lead; UI capstones follow.

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
| Naming strategies | ✅ | ✅ | uuid / series / field / format |
| Automation runner + built-in actions | ✅ | ✅ | |
| Notifications / EventEmitter | ✅ | 🟡 | events ✅; notification **inbox** reader ❌ |
| Scheduling (cron, tick) | ✅ | ✅ | |
| Customization (custom fields, property setters) | ✅ | ✅ | |
| App runtime (manifest, installer) | ✅ | ✅ | |
| **Reporting — ReportEngine execution** | ✅ | 🟡 | engine landed (this branch); UI viewer ❌ |
| **Dashboards — DashboardEngine execution** | ✅ | 🟡 | engine landed (this branch); UI grid ❌ |
| Saved reports (ADR-050) | ✅ | ❌ | |
| **Files / Attachments** | ✅ | ❌ | Attachment + manager + store |
| **Import / Export (CSV/JSON)** | ✅ | ❌ | |
| **Printing / PDF** | ✅ | ❌ | PrintFormat + renderers |

## UI shell — `packages/mercantis_core_ui`

| Surface | Status | Notes |
|---------|:----:|-------|
| Adaptive shell / navigation / routing | ✅ | phone/tablet/desktop breakpoints |
| Generic form view | 🟡 | ~13 of 34 field types real; rest fall back to text editor |
| Date/time & media/attachment field widgets | ❌ | pickers, file, signature, color, barcode |
| Generic list views | ✅ | no bulk/multi-select |
| Record workspace chrome (Form/Timeline/Attachments) | 🟡 | Timeline & Attachments tabs are placeholders |
| Form builder (palette/canvas/inspector) | 🟡 | **save not wired** to DocumentEngine |
| Command palette / global search | ✅ | Cmd-K |
| Workspaces / dashboard cards | 🟡 | cards render; need real DashboardEngine data |
| Approvals inbox | ✅ | |
| **Report viewer** | ❌ | render `ReportResult` as table + CSV export |
| **Dashboard grid** | ❌ | render `DashboardResult` widgets |
| Settings screen | ❌ | route is a "coming soon" stub |
| Recents | ❌ | |

## Sequenced plan (ERP-correctness-first)

1. **Phase 1 — engine gaps Hub needs.** Report + dashboard execution ✅ (this
   branch); notification inbox; (defer attachments/import-export/printing).
2. **Phase 4 — report/dashboard UI.** `GenericReportView`, dashboard grid;
   feeds Hub's reports & de-mocks dashboards.
3. **Phase 5 — UI capstones.** Settings, real field widgets, form-builder
   persistence, Timeline/Attachments/Recents tabs.
4. **Phase 6 — Attachments, Import/Export, Printing.**

> Hub-side business logic (ledger derivation, stock balance) lives in the
> **Hub** repo's `PARITY.md`; it is the critical path and proceeds in parallel
> once the report engine (above) is in place.
