#!/usr/bin/env bash
# cut-train.sh <target-branch> <new-branch> <pr-csv> — the train engine.
# Shared by promote.yaml (Mode B) and hotfix.yaml:
#
#   1. resolve every PR number: it must be a MERGED dev PR
#      (grab merge SHA, title, author, merge time)
#   2. order the picks by merge time — the order they landed on dev
#   3. cut <new-branch> from origin/<target-branch>'s CURRENT TIP
#   4. cherry-pick each merge commit with -x (writes the
#      "(cherry picked from commit <sha>)" stamp the gate later verifies)
#      and -m 1 (mainline = the dev side) when the commit is a merge commit
#   5. on conflict: abort the pick and run the DEPENDENCY DETECTOR —
#      which OTHER dev PRs touched the conflicted files after <target>
#      last saw them? Those are the likely missing dependencies.
#
# On success: <new-branch> is left checked out, and a picks table is written
# to $PICKS_OUT (TSV: number, title, author-login, picked-merge-sha).
# On failure: the branch is deleted and we exit 1 with the detector's verdict.
# Needs: GH_TOKEN, git identity configured, origin = the lab repo.
set -euo pipefail

TARGET="$1"; BRANCH="$2"; PRS_CSV="$3"
PICKS_OUT="${PICKS_OUT:-picks.tsv}"

git fetch -q origin dev "$TARGET"

# --- 1: resolve ---------------------------------------------------------
RESOLVED="$(mktemp)"
trap 'rm -f "$RESOLVED"' EXIT
for N in $(tr ',' ' ' <<<"$PRS_CSV"); do
  N="${N//[!0-9]/}"; [ -z "$N" ] && continue
  ROW="$(gh pr view "$N" --json number,title,author,state,baseRefName,mergedAt,mergeCommit \
         --jq 'select(.state=="MERGED" and .baseRefName=="dev")
               | [.mergedAt, (.number|tostring), .title, .author.login, .mergeCommit.oid] | @tsv' \
         2>/dev/null || true)"
  if [ -z "$ROW" ]; then
    echo "::error::PR #$N is not a MERGED dev PR — only work that already landed on dev can board a train." >&2
    exit 1
  fi
  printf '%s\n' "$ROW" >>"$RESOLVED"
done
if [ ! -s "$RESOLVED" ]; then
  echo "::error::no valid PR numbers in '$PRS_CSV'" >&2
  exit 1
fi

# --- 2: order by merge time (ISO timestamps sort lexicographically) ------
sort -o "$RESOLVED" "$RESOLVED"

# --- 3: cut from the target's current tip --------------------------------
git switch -q -c "$BRANCH" "origin/$TARGET"

# --- 4 + 5: stamped picks, detector on conflict ---------------------------
: >"$PICKS_OUT"
while IFS=$'\t' read -r -u 3 MERGED_AT NUM TITLE AUTHOR SHA; do
  MAINLINE=()
  # merge commit? (has a second parent) -> pick the dev-side diff
  if git rev-parse -q --verify "$SHA^2" >/dev/null 2>&1; then MAINLINE=(-m 1); fi

  if ! git cherry-pick -x "${MAINLINE[@]}" "$SHA" >/dev/null 2>&1; then
    CONFLICTED="$(git diff --name-only --diff-filter=U)"
    git cherry-pick --abort 2>/dev/null || true

    # DEPENDENCY DETECTOR: commits that are on dev but not on <target> and
    # touch the same files. Map each to its PR — anything not already on this
    # train is a suspect.
    SUSPECTS="$(mktemp)"
    for C in $(git log --format=%H "origin/$TARGET..origin/dev" -- $CONFLICTED); do
      gh api "repos/{owner}/{repo}/commits/$C/pulls" --jq '.[].number' >>"$SUSPECTS" 2>/dev/null || true
    done
    REQUESTED="$(cut -f2 "$RESOLVED")"
    LIKELY=""
    for S in $(sort -un "$SUSPECTS"); do
      if grep -qx "$S" <<<"$REQUESTED"; then continue; fi
      # only dev PRs count as dependencies — a commit is also "associated"
      # with the promotion PR that later carried it to uat, which is noise
      if [ -z "$(gh pr view "$S" --json baseRefName --jq 'select(.baseRefName=="dev") | .number' 2>/dev/null)" ]; then continue; fi
      LIKELY="$LIKELY #$S"
    done
    rm -f "$SUSPECTS"

    # clean up the half-built train before failing
    git switch -q --detach "origin/$TARGET"
    git branch -q -D "$BRANCH" || true

    if [ -n "$LIKELY" ]; then
      echo "::error::pick #$NUM (${SHA:0:7}) conflicts; likely depends on unbucketed PR(s):${LIKELY} — include them in the train or drop #$NUM." >&2
    else
      echo "::error::pick #$NUM (${SHA:0:7}) conflicts in: $(tr '\n' ' ' <<<"$CONFLICTED") — no candidate PR found; inspect manually." >&2
    fi
    exit 1
  fi
  printf '%s\t%s\t%s\t%s\n' "$NUM" "$TITLE" "$AUTHOR" "$SHA" >>"$PICKS_OUT"
done 3<"$RESOLVED"
