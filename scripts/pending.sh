#!/usr/bin/env bash
# pending.sh [min-age-hours] — merged-to-dev PRs that have NOT ridden any uat
# release. The shared reachability check behind:
#   * stranded-pr.yaml        (the nagging issue)
#   * deploy.yaml uat footer  ("NOT on uat yet: …")
#
# A dev PR counts as "on uat" if EITHER:
#   1. its merge commit is an ANCESTOR of uat      (wholesale promotion), or
#   2. some uat commit carries the stamp
#      "(cherry picked from commit <its merge sha>)"   (train / hotfix pick).
#
# With min-age-hours > 0, only PRs merged at least that long ago are listed
# (fresh merges are not "stranded", they just haven't caught a train yet).
#
# Output: TSV  number \t title \t author-login \t merged-at \t age-hours
# Needs: GH_TOKEN, origin = the lab repo. GNU date (CI/linux; gdate on macOS).
set -euo pipefail

MIN_AGE_H="${1:-0}"
git fetch -q origin uat
NOW="$(date +%s)"

gh pr list --base dev --state merged --limit 100 \
   --json number,title,author,mergedAt,mergeCommit \
   --jq '.[] | [(.number|tostring), .title, .author.login, .mergedAt, .mergeCommit.oid] | @tsv' |
while IFS=$'\t' read -r NUM TITLE AUTHOR MERGED_AT SHA; do
  if [ -z "$SHA" ]; then continue; fi
  # (1) rode a wholesale promotion?
  if git merge-base --is-ancestor "$SHA" origin/uat 2>/dev/null; then continue; fi
  # (2) rode a train/hotfix? (its stamp is on some uat commit)
  if [ -n "$(git log origin/uat --grep="cherry picked from commit $SHA" --format=%H -n 1)" ]; then continue; fi
  AGE_H=$(( (NOW - $(date -d "$MERGED_AT" +%s)) / 3600 ))
  if [ "$AGE_H" -lt "$MIN_AGE_H" ]; then continue; fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$NUM" "$TITLE" "$AUTHOR" "$MERGED_AT" "$AGE_H"
done
