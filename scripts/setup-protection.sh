#!/usr/bin/env bash
# setup-protection.sh — branch rulesets for uat + production. Run ONCE, needs
# repo admin. (Public repo, so rulesets actually enforce on the free plan.)
#
# What each ruleset says, and why:
#   * pull_request           releases enter ONLY via PR — no direct pushes.
#       allowed_merge_methods: ["merge"]  <- merge commits only. Squash/rebase
#       would rewrite the SHAs, and this whole CI decides "was PR X released?"
#       by ancestry + cherry-pick stamps (scripts/pending.sh, gate.yaml).
#       Squash a promotion PR once and every dev PR aboard it reads as
#       stranded forever.
#   * required_status_checks: the "gate" job must pass. This is the line that
#       turns a red gate into CANNOT MERGE — and, combined with GitHub
#       suppressing events for github.token-created PRs, the line that makes
#       bot PRs unmergeable until LAB_BOT_PAT exists (exercise 3.4).
#   * deletion + non_fast_forward: nobody deletes or force-pushes an env branch.
#
# dev stays OPEN on purpose: work lands there PR-or-not; the release lanes
# are where the ceremony lives.
#
# TAGS ARE NOT PROTECTED: deploy.yaml keeps pushing lab-*-latest / rc-* /
# rel-* tags with the default token. (Branch rulesets don't touch tags.)
set -euo pipefail

for BR in uat production; do
  gh api -X POST 'repos/{owner}/{repo}/rulesets' --input - <<EOF
{
  "name": "release-lane-$BR",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["refs/heads/$BR"], "exclude": [] } },
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    { "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "allowed_merge_methods": ["merge"]
      } },
    { "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "required_status_checks": [ { "context": "gate" } ]
      } }
  ]
}
EOF
  echo "ruleset created: release-lane-$BR"
done
