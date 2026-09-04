#!/usr/bin/env bash
# Save-time documentation checks.
#
# Runs the repository's own validators. They are dependency-free Node scripts, so this works
# before npm install and before the site is scaffolded — a missing tool is a skip, never a
# failure. This hook is advisory (PostFileSave cannot block) and must stay fast, so the network
# link resolution in check-references is skipped here; CI does the full pass.
set -uo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 0

command -v node >/dev/null 2>&1 || exit 0

status=0

for check in check-placeholders check-asides check-references; do
  [ -f "scripts/$check.mjs" ] || continue
  SKIP_LINK_CHECK=1 node "scripts/$check.mjs" || status=1
done

if [ "$status" -ne 0 ]; then
  echo "docs-check: validators reported issues (advisory; run npm run validate for the full pass)." >&2
fi

exit 0
