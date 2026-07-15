#!/usr/bin/env bash
# "Deploy" = build + install the consumers from the CHECKED-OUT source tree.
# Whatever the branch says, runs. No registry, no pins, no version numbers.
#
# usage: ./deploy.sh [env-label]     (defaults to the current branch name)
set -euo pipefail
command -v uv >/dev/null 2>&1 || export PATH="/opt/homebrew/bin:$PATH"

ROOT="$(cd "$(dirname "$0")" && pwd)"
BRANCH="$(git -C "$ROOT" branch --show-current 2>/dev/null || true)"
ENV="${1:-${BRANCH:-detached}}"

echo "--- source-world: deploying '$ENV' (branch: ${BRANCH:-detached}) ---"
cd "$ROOT"
for CONSUMER in report worker; do
    uv sync -q --package "$CONSUMER"
    OUT="$("$ROOT/.venv/bin/python" -c "import $CONSUMER; print($CONSUMER.main())")"
    echo "[$CONSUMER on $ENV] $OUT"
done
