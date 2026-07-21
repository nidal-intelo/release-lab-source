#!/usr/bin/env bash
# boarded.sh <from-ref> <to-ref> — which dev PRs are aboard this commit range?
#
# Two ways a dev PR's work can appear in a range of uat/production commits:
#   1. its merge (or squash) commit is IN the range      -> wholesale promotion
#      (subject "Merge pull request #N ..." or "title (#N)")
#   2. a cherry-pick STAMPED with its commit sha is in the range
#      -> release train / hotfix ("(cherry picked from commit <sha>)";
#         ask GitHub which PR owns <sha>)
#
# Output: TSV   number \t title \t author-login \t merged-at
# Only PRs that were MERGED with base=dev qualify — the promotion/train PR
# itself is the vehicle, not the cargo, and is filtered out here.
# Needs: GH_TOKEN + a checkout whose 'origin' is the lab repo. Linux (CI) bash.
set -euo pipefail

FROM="${1:-}"; TO="${2:-HEAD}"
if [ -n "$FROM" ] && git rev-parse -q --verify "$FROM^{commit}" >/dev/null 2>&1; then
  RANGE="$FROM..$TO"
else
  RANGE="$TO"      # no usable start ref: scan the whole history of TO
fi

NUMS="$(mktemp)"
trap 'rm -f "$NUMS"' EXIT

# (1) PR numbers named in commit subjects
git log --format=%s "$RANGE" | { grep -oE '#[0-9]+' || true; } | tr -d '#' >>"$NUMS"

# (2) cherry-pick stamps -> origin sha -> owning PR(s)
for SHA in $(git log --format=%B "$RANGE" \
             | { grep -oE 'cherry picked from commit [0-9a-f]{40}' || true; } \
             | awk '{print $5}' | sort -u); do
  gh api "repos/{owner}/{repo}/commits/$SHA/pulls" --jq '.[].number' >>"$NUMS" 2>/dev/null || true
done

for N in $(sort -un "$NUMS"); do
  gh pr view "$N" --json number,title,author,baseRefName,state,mergedAt \
    --jq 'select(.baseRefName=="dev" and .state=="MERGED")
          | [(.number|tostring), .title, .author.login, .mergedAt] | @tsv' \
    2>/dev/null || true
done | sort -u -t$'\t' -k1,1n
