# Handoff — Mercantis Flutter port

Snapshot for resuming work in a new session. The **`PARITY.md`** in each repo is
the canonical per-feature status; this file is just the short version + open
threads.

## Repos & branch
- `mercantis.hub.flutter` — the ERP app (modules, ledger spine, screens).
- `mercantis.core.flutter` — the engine + UI shell (`packages/mercantis_core`,
  `packages/mercantis_core_ui`); a Dart **pub workspace**. Hub depends on Core
  via a **pinned git ref**, so Core changes only reach Hub when that ref bumps.
- Working branch (both): `claude/elegant-cori-9fb2hj`. Most work has been
  merged to `main` via PRs; new work lands on this branch → PR → merge.

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
  date/time field widgets, attachments, import/export, print preview,
  notification inbox; form-builder save; live Timeline tab.

## Open threads
1. **Confirm Core CI** for the Timeline-tab commit (`5fa367a`, "live Timeline
   tab over the audit log") is green; open/merge a PR for this branch if needed.
2. **Recents** screen (Core UI shell) — no new deps.
3. **Native print/PDF share** — currently a plain-text preview
   (`PrintRecordButton`); needs a printing/share plugin for real PDF output.
4. **Field widgets**: `signature`, `color`, `barcode` still fall back to text
   (need plugins). `date/time/dateTime` are done.
5. **`mercantis_core` lint cleanup** (~20 unused-import/field warnings), then
   restore `--fatal-warnings` in Core CI.

## How to resume
> Continue the mercantis Flutter port on branch `claude/elegant-cori-9fb2hj`.
> Read both repos' `PARITY.md` + this `HANDOFF.md`. Push commits and confirm CI
> (GitHub MCP tools) goes green for each change. Re-subscribe to any open PR you
> want watched.
