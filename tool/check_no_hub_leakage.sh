#!/usr/bin/env bash
# Fails if any Hub-specific ERP identifier sneaks into mercantis_core or
# mercantis_core_ui. Core must remain domain-neutral.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE_DIRS=(
  "$ROOT/packages/mercantis_core/lib"
  "$ROOT/packages/mercantis_core_ui/lib"
)

# Whole-word identifiers that signal Hub-specific (ERP) leakage.
# Anchor with \b boundaries to avoid false positives like "purchase"
# inside a generic word.
FORBIDDEN_REGEX='\b(Selling|Buying|CRM|Sales[[:space:]]+Order|Sales[[:space:]]+Invoice|Purchase[[:space:]]+Order|Purchase[[:space:]]+Invoice|Delivery[[:space:]]+Note|Stock[[:space:]]+Entry|Journal[[:space:]]+Entry|Payment[[:space:]]+Entry|Quotation|Opportunity|HubManifest|HubModule)\b'

status=0
for dir in "${CORE_DIRS[@]}"; do
  if [[ ! -d "$dir" ]]; then continue; fi
  if matches=$(grep -RnE "$FORBIDDEN_REGEX" "$dir" \
       --include='*.dart' \
       --exclude-dir='generated' 2>/dev/null); then
    echo "::error::Hub-specific identifiers leaked into Core:"
    echo "$matches"
    status=1
  fi
done

if [[ $status -ne 0 ]]; then
  echo
  echo "Move the offending logic to mercantis.hub.flutter."
  exit 1
fi

echo "OK: no Hub-specific identifiers found in Core."
