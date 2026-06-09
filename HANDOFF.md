# Handoff — Mercantis Flutter port

Snapshot for resuming work in a new session. The **`PARITY.md`** in each repo is
the canonical per-feature status; this file is just the short version + open
threads.

## Repos & branch
- `mercantis.hub.flutter` — the ERP app (modules, ledger spine, screens).
- `mercantis.core.flutter` — the engine + UI shell (`packages/mercantis_core`,
  `packages/mercantis_core_ui`); a Dart **pub workspace**. Hub depends on Core
  via a **pinned git ref**, so Core changes only reach Hub when that ref bumps.
- Working branch (both): `claude/blissful-goldberg-12z7co` (the previous
  `claude/elegant-cori-9fb2hj` work is merged to `main`). New work lands on
  this branch → PR → merge.

## CI (both repos have `.github/workflows/ci.yml`)
- Jobs: `flutter analyze` + `flutter test` per package.
- **Hub**: Flutter `3.29.0`, analyze is strict.
- **Core**: Flutter **`3.32.0`** (its `melos` dev-dep needs Dart ≥3.8), and
  analyze runs **`--no-fatal-warnings --no-fatal-infos`** to skip ~20
  pre-existing lint warnings in `mercantis_core` (see open threads).
- This environment has **no Flutter SDK**, so verification is via CI: push, then
  read the run with the GitHub MCP tools and fix any red.

## Status (high level)
- **Hub**: feature-complete at module + master-data level — CRM/Selling/Buying/
  Stock/Accounting(+VAT)/POS/Manufacturing/Deliveries, full ledger+stock
  derivation, reports (incl. Trial Balance + AR/AP aging), guided payments,
  onboarding seeder, settings + data-driven operator, POS till, shop-floor.
- **Core**: every engine→UI binding done — report viewer, dashboard grid,
  date/time + signature/color/barcode field widgets, attachments,
  import/export, **native PDF print+share**, notification inbox; form-builder
  save; live Timeline tab; **Recents**.

## Open threads
1. ✅ **Timeline-tab** (`5fa367a`) merged to `main` (PR #40, green).
2. ✅ **Recents** — `RecentsView`/`recentsProvider`/`RecentsStore` (persisted
   `ui_recents` table, MRU/capped/de-duped), recorded from `GenericFormView`.
3. ✅ **Native print/PDF share** — `PrintRecordButton` renders real PDF bytes
   and drives the `printing` plugin (`layoutPdf` print/preview + `sharePdf`).
4. 🟡 **Field widgets**: `signature`, `color`, `barcode`, `rating`, `duration`,
   `code` are now real. Still falling back to text: `attach`/`attachImage`
   (file) and `geolocation`.
5. ✅ **`mercantis_core` lint cleanup** — 18 warnings cleared across both
   packages; Core CI restored to `flutter analyze --no-fatal-infos` (warnings
   fatal again). ~25 info-level lints remain (non-fatal) for a later burndown.

### Newer threads (this session)
6. ✅ **WorkflowEngine emits `WorkflowTransitionEvent`** (shared emitter), wired
   through the UI provider. Enables the Hub's Work Order → completion Stock
   Entry **auto-post** (`ManufacturingDerivationService`, Hub repo) — its end-to-
   end firing in production needs the Hub's pinned Core ref bumped to include
   this commit.
7. **Hub-side** (see `mercantis.hub.flutter`): Item child tables + Supplier
   Quotation, Sales/Inventory dashboard de-mock — all landed.

### Still open
- Core **Settings screen** (still a "coming soon" stub); `attach`/`geolocation`
  field widgets (need plugins).
- Hub: de-mock the bespoke custom screens (Sales Orders, Customer Acct, Routes,
  Driver, Low Stock); `NumberingSeries`; real auth.
- **Core ref bump** in Hub `pubspec.yaml` once the Core workflow-event change
  merges, to activate WO auto-post in production.

## How to resume
> Continue the mercantis Flutter port on branch `claude/blissful-goldberg-12z7co`.
> Read both repos' `PARITY.md` + this `HANDOFF.md`. Push commits and confirm CI
> (GitHub MCP tools) goes green for each change. Re-subscribe to any open PR you
> want watched.
