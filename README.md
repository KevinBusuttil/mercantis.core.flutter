# Mercantis Core — Flutter

> The offline-first, metadata-driven platform layer for building business applications. Flutter port targeting iOS/iPadOS, macOS, and Windows 11.

## Overview

Mercantis Core Flutter is a complete Dart/Flutter port of the Mercantis Core Swift/SwiftUI application. It provides the same foundational infrastructure — document engine, metadata-driven schemas, offline-first sync, workflow engine, expression evaluator, and multi-level permissions — built for cross-platform deployment.

## Target Platforms

| Platform | Target | Status |
|----------|--------|--------|
| iOS / iPadOS | iOS 17+ | ✅ |
| macOS | macOS 14+ | ✅ |
| Windows | Windows 11 | ✅ |

## Repository Structure

Monorepo managed with [Melos](https://melos.invertase.dev/):

```
packages/
  mercantis_core/        # Pure Dart — headless engine (no Flutter dependency)
  mercantis_core_ui/     # Flutter — metadata-driven UI shell
app/                     # Flutter dev shell (uses both packages)
```

## Key Capabilities

- **Metadata-driven documents** — Every entity is a DocType. No schema migrations for business data.
- **Offline-first sync** — Every write produces a MutationRecord; a mutation log drives cloud sync.
- **Declarative plugin model** — Apps are AppManifest objects. Business logic runs in a sandboxed expression engine.
- **Multi-level permissions** — DocType → field → row → workflow action, evaluated at runtime.
- **Workflow engine** — State-machine transitions with role guards and condition expressions.
- **Document lifecycle** — Submit/cancel/amend flow for submittable DocTypes.
- **Expression engine** — Sandboxed AST-based evaluator for boolean conditions and formula fields.
- **Conflict resolution** — Last-Write-Wins, Version-Checked Merge, Append-Only policies per DocType.

## Getting Started

```bash
dart pub global activate melos
melos bootstrap
cd app && flutter run
```

## Related Repositories

- [mercantis.hub.flutter](https://github.com/KevinBusuttil/mercantis.hub.flutter) — First-party ERP app built on this platform
- [mercantis.core.app](https://github.com/KevinBusuttil/mercantis.core.app) — Original Swift/SwiftUI implementation
