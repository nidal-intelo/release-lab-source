# Act 2 — the source world grows a CI

Act 1 / 1.5 automated the pinned world: wheels, pins, repin bots, drift
alarms, provenance manifests. The source world needs none of that — there is
nothing to bump, nothing to pin, nothing to publish. What runs on an
environment is **whatever its branch says**, full stop.

So what does release engineering even mean here? Exactly one thing: **deciding
which commits a branch contains**, and being able to prove it. This act's CI
is six small pieces around that single idea:

| piece | file | job | real-repo file it prototypes |
|---|---|---|---|
| deploy | `.github/workflows/deploy.yaml` | deploy on env-branch push; rc-/rel- tags; release notes; Slack preview | the `v1-*` deployment workflows + notify-slack |
| promote | `.github/workflows/promote.yaml` | the release button: wholesale PR (Mode A) or cherry-picked train (Mode B — dev→uat only) | dispatch side of `v1-promotion-gate.yaml` |
| gate | `.github/workflows/gate.yaml` | the one required check: lanes, stamps, uat-first | `v1-promotion-gate.yaml` |
| hotfix | `.github/workflows/hotfix.yaml` | stamped fix off production's tip; twin PRs on twin branches (SHA-keyed checks) | `v1-hotfix-create.yaml` |
| stranded-pr | `.github/workflows/stranded-pr.yaml` | the nagging issue: merged to dev ≠ released | the visibility / notify layer |
| protection | `scripts/setup-protection.sh` | rulesets: PR-only + required gate on uat/production | branch protection config |

Plus three shared scripts: `scripts/cut-train.sh` (the train engine),
`scripts/boarded.sh` (which PRs rode a range of commits),
`scripts/pending.sh` (which dev PRs never rode at all).

### Ground rules

- Remote: **release-lab-source** on GitHub. `dev` is open; `uat` and
  `production` only accept PRs, and only with a green **gate** check
  (rulesets are already active — try `git push origin dev:uat` and read the
  refusal).
- Merges into `uat`/`production` are **merge commits only** (the ruleset
  enforces it). This CI decides "was PR X released?" by commit ancestry and
  cherry-pick stamps; a squash would erase both.
- **Production is wholesale-only.** uat validates a *whole state*; picking a
  subset at the prod step would ship a combination uat never ran. Trains run
  dev→uat only; `hotfix/*` is the single exception lane into production (and
  even it must ride uat first). promote refuses `target=production` with
  `prs`; the gate refuses `train/*` aimed at production.
- Watching runs: `gh run list --limit 5`, `gh run watch`, and — every time —
  the run's **summary** (`gh run view --web`). The summaries are the deploy
  log, the Slack preview, and the release notes of this world.
- **One repo setting stands between you and the buttons**: *Settings →
  Actions → General → Allow GitHub Actions to create and approve pull
  requests* is currently **OFF**. Until it's on, promote/hotfix can cut and
  push branches but their `gh pr create` fails outright ("GitHub Actions is
  not permitted to create or approve pull requests") — the run's summary
  explains itself. Flip it now:

  ```sh
  gh api -X PUT repos/{owner}/{repo}/actions/permissions/workflow \
    -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true
  ```

  That's the *coarse* gate. The finer, sneakier one — token-created PRs fire
  no checks — is exercise 3.4. (A `LAB_BOT_PAT` secret bypasses both; you
  mint it in 3.4.)

### Starting state (the setup's own shakedown is in the history — spoilers)

- `dev`: 1.5-era qb **plus** merged PRs #2 (qb audit log), #3 (solver
  jitter), #4 (report v2 header), #8 (qb epsilon guard), #9 (**the empty-cart
  fix!**), #12 (worker prefix).
- `uat`: has ridden two wholesales (#1, #7) and three trains (#5 → PRs 2+3,
  #13 → PR 12, #17 → PR 14). **#8 and #9 are NOT on uat** — they are your
  3.1 cargo.
- `production`: still 1.3-era qb + the CI files (which arrived as stamped
  cherry-picks — `git log origin/production --oneline` and look) + one real
  hotfix: the wholesale-only CI policy itself rode the emergency lane down
  (PR #16, tag `rel-2026.07.21-hf1`). The cart bug still lives there.
- Tags: `rc-*`/`rel-*` from the shakedown; floating `lab-<branch>-latest` per
  branch. (Ignore the stray `rel-hf1` — an Act-1-era leftover on an orphaned
  commit; the release-notes logic ignores it too.)
- Issue #6 (stranded) exists, closed. Closed PRs are previews: #10/#11 = the
  3.5 drill; #15 = a hotfix twin that *conflicted* at uat (its fix touched CI
  files whose uat/production copies diverged — off-ramp: the fix rode a
  normal yellow train, #17, and the production twin #16 proceeded); #18/#19 =
  gate probes for the wholesale-only rule.

> **Known wrinkle (seed-lineage add/add).** The CI files reached uat and
> production as *cherry-picks* of dev commits, so each branch added them with
> its own SHAs — the branches' merge-base predates the files entirely. Every
> wholesale promotion therefore re-merges them as add/add: silent while the
> copies are content-identical, a **conflict** the moment any copy drifts
> (that bit PR #27 in `scripts/cut-train.sh`, repaired by hotfix #28; same
> family as twin #15). The one-liner lesson: **cherry-picking the same change
> onto both sides of a fence splits its file history — picks copy content,
> only merges join lineage.** The first wholesale merge across the fence
> heals it for good. The real repo doesn't have this class of problem: its
> workflow files flow between branches via merges from the start.

---

## Exercise 3.0 — Tour the six pieces

**Goal:** know what each machine does before you press anything.

**Commands:**

```sh
git switch dev && git pull
less .github/workflows/deploy.yaml      # read the WATCH LIST comment vs pinned world
less .github/workflows/promote.yaml     # read the token teachable in `env:`
less .github/workflows/gate.yaml        # the three rules
less .github/workflows/hotfix.yaml
less .github/workflows/stranded-pr.yaml
less scripts/cut-train.sh scripts/pending.sh scripts/boarded.sh
gh api 'repos/{owner}/{repo}/rulesets' | jq '.[].name'
git log origin/production --oneline | head   # CI arrived by stamped picks
gh run list --limit 10                       # the shakedown's runs
```

**What you should observe:** deploy's watch list includes `common/` — the
exact directory the pinned world's deploy deliberately ignores. The gate's
three rules are the entire law of this world. `scripts/` holds the one
reachability check used by both the stranded issue and the deploy footer.

**What just happened:** nothing yet. Note what's *absent* compared to Act
1.5: no publish workflow, no repin bot, no drift alarm, no manifest. Versions
are frozen at `0.0.0` and nobody cares.

---

## Exercise 3.1 — Mode A: wholesale release to uat

**Goal:** one button, everything on dev goes to uat — rc tag, Slack preview,
release bookkeeping all included.

**Commands:**

```sh
gh workflow run promote.yaml -f target=uat        # prs empty = Mode A
gh run watch                                       # PR appears (setting from ground rules is on)
gh pr list --base uat
gh pr checks <pr>                                  # gate: pass (dev→uat is a lane)
gh pr merge <pr> --merge
gh run watch                                       # the uat deploy
gh run view --web                                  # READ THE SUMMARY
git fetch --tags -f && git tag -l 'rc-*'
```

If the gate shows *no checks* on the PR: you skipped ground rules — or you're
previewing 3.4. `gh pr close <pr> && gh pr reopen <pr>` (your token, not the
bot's) kicks the event; the real fix is 3.4.

**What you should observe:** the deploy summary shows both consumers
**redeployed** (common/ changed), behavior strings now carrying `+ audit log
[epsilon 1e-9]` and `empty carts handled correctly` on uat; a new
`rc-YYYY.MM.DD-n` tag; a **SLACK PREVIEW** section listing #8 and #9 with
`<@author>` pings and "test yours; anything broken gets fixed or reverted via
the next yellow train, before the prod release"; the same message posted as a
comment on your promotion PR; and the footer — **NOT on uat yet: nothing**.

**What just happened:** a release was: merge one PR. The Slack table wasn't
typed by anyone — `scripts/boarded.sh` read it out of the commit range
(merge subjects + cherry-pick stamps). Compare with Act 1's promotion
(exercise 1.3): edit pins, hope you remembered every consumer.

---

## Exercise 3.2 — Mode B: a release train (and what it leaves behind)

**Goal:** release a *subset* — two of three PRs — and watch the machinery
account for the one left on the platform.

**Step 1 — make three small PRs to dev** (distinct one-line tweaks so you can
see each one in behavior strings later):

```sh
git switch dev && git pull
# PR a: common/qb/src/qb/__init__.py    — append something to ROUNDING
# PR b: common/solver/src/solver/__init__.py — tweak STRATEGY
# PR c: consumers/report/src/report/__init__.py — tweak main()'s string
# for each: branch, commit, push, gh pr create --base dev, gh pr merge --merge
```

**Step 2 — train two of them** (say a and b; c misses the train):

```sh
gh workflow run promote.yaml -f target=uat -f prs=<a>,<b>
gh run watch
gh pr view <train-pr>            # READ THE ECHO-BACK TABLE — that is the release
gh pr checks <train-pr>          # gate: pass — every commit stamped, origins on dev
gh pr merge <train-pr> --merge --delete-branch
gh run watch                     # uat deploy
```

**Step 3 — the one left behind:**

```sh
gh workflow run stranded-pr.yaml -f max_age_hours=0
gh run watch
gh issue list                    # "Stranded on dev: …" — assigned to <c>'s author
```

**What you should observe:** the train PR body echoes exactly two picks with
their stamped SHAs; the Slack preview pings exactly two authors; the deploy
footer says **NOT on uat yet: #<c>**; the stranded issue opens, listing #<c>,
assigned to its author (here: you — in a team repo, the person who'd
otherwise ask "wait, is my thing live?").

**What just happened:** cherry-picks with `-x` gave every train commit a
provenance stamp; `pending.sh` used ancestry + those stamps to compute
"released" without a manifest, a registry, or anyone's memory. Bonus: dispatch
a train containing a PR that *depends* on an unbucketed one and read the
dependency detector's verdict (the shakedown hit it — see the failed hotfix
run for PR #8 in the Actions history).

---

## Exercise 3.3 — Self-heal: the wholesale sweep (and the refusal)

**Goal:** watch the stranded issue close itself — then try to be selective at
the prod step and read the machine's answer.

**Commands:**

```sh
gh workflow run promote.yaml -f target=uat          # Mode A again
gh pr merge <pr> --merge                            # after gate is green
gh workflow run stranded-pr.yaml -f max_age_hours=0
gh run watch
gh issue list --state all | head -3                 # closed, with a comment
```

**What you should observe:** the wholesale merge made #<c>'s merge commit an
*ancestor* of uat; the next audit found nothing stranded and closed the issue
with "Nothing stranded — … Auto-closing."

**Now the refusal** — uat looks good, so try to take just your favorite PR to
production:

```sh
gh workflow run promote.yaml -f target=production -f prs=<a>
gh run watch                     # fails immediately; READ THE SUMMARY:
                                 # "refused: production releases are wholesale —
                                 #  selectivity happens at dev→uat; for emergencies
                                 #  use the hotfix workflow"
gh workflow run promote.yaml -f target=production   # the correct button (Mode A)
gh pr view <promo-pr>            # body ECHOES what's riding: every dev PR on uat
                                 # not yet on production — merge it if you mean it
```

(The gate enforces the same law from the other side: a `train/*` branch aimed
at production is refused *by lane*, stamps or no stamps — the shakedown's
probe PR #18 shows the exact message.)

> **Principle: uat is a queue, not a parking lot.** Boarding a yellow train
> = committed to prod; the next wholesale ships *everything* uat has. The
> off-ramps are fix-forward or revert — both via dev, both riding the same
> trains. There is no "leave it on uat and ship around it."

**What just happened:** the audit is stateless — it recomputes reality from
git every run, so it heals no matter *how* the PR got released (train stamp
or wholesale ancestry). Nobody updates a spreadsheet. And production
promotions carry no `prs` knob: uat validated a whole state, so a subset
picked at the prod step would ship a combination uat never ran.

---

## Exercise 3.4 — The bot with no voice (mint the PAT)

**Goal:** meet event suppression: PRs created by `github.token` fire **no**
checks — and the gate is *required*.

**Commands:**

```sh
# temporarily flip the ground-rules setting back OFF? No — leave it. Instead:
# look at any promote run from BEFORE you flipped it (the shakedown's):
gh run list --workflow promote.yaml
gh run view <failed-run> --web    # summary: "promotion PR NOT created" + both lessons
```

With the setting ON but still no PAT, dispatch a train and look at its PR:
**zero checks**. A required check that never runs isn't green — the merge box
is stuck. Prove the gate itself is fine:

```sh
git fetch && git switch <train-branch>
git commit --allow-empty -m "kick" && git push    # YOUR push → synchronize event fires
gh pr checks <train-pr>                           # gate appears (and passes the empty commit? no —
                                                  # read its verdict: unstamped! drop it: next exercise
                                                  # teaches you to never hand-touch a train anyway)
gh pr close <train-pr> --delete-branch            # re-cut cleanly after the PAT:
```

Now fix it properly: GitHub → Settings → Developer settings → fine-grained
PAT, **this repo only**, permissions: Contents RW + Pull requests RW. Then:

```sh
gh secret set LAB_BOT_PAT
gh workflow run promote.yaml -f target=uat -f prs=<any merged dev PR>
gh pr checks <new-train-pr>       # checks fire on their own this time
```

**What you should observe:** same workflow, same YAML — the only variable is
*whose token created the PR*. With `LAB_BOT_PAT`, the PR belongs to a real
identity and `pull_request` events fire normally.

**What just happened:** GitHub suppresses events for `GITHUB_TOKEN`-created
objects to prevent workflow loops. Every real-world release bot hits this
wall once. The promote/hotfix `env:` block documents the whole ladder:
github.token (mute) → repo setting (can't even create) → PAT (full voice).
Cost of the fix: a credential that now exists, expires, and must be rotated —
write that down for the tally.

---

## Exercise 3.5 — The hotfix drill

**Goal:** ship a fix to production without shipping dev — and watch the gate
make the twin ordering mechanical.

**Step 1 — a fresh fix, fix-forward on dev first:**

```sh
git switch dev && git pull
# make a small "fix" PR (one line in common/qb — e.g. guard something) and merge it to dev
# do NOT release it to uat — that's the point
```

**Step 2 — the button:**

```sh
gh workflow run hotfix.yaml -f prs=<fix-pr>
gh run watch          # cuts hotfix/pr-<n>-uat AND hotfix/pr-<n>-prod from PRODUCTION's
                      # tip — identical content, two branches — and opens the twins
gh pr list            # "hotfix: …" → uat   and   "[merge after uat] hotfix: …" → production
```

> **Why two branches?** Branch-protection required checks are keyed by
> **(commit SHA, check name)**. Twins sharing one head commit share one
> `gate` slot — the production twin's *correctly* red verdict would also
> block the *legitimately green* uat twin (the first learner run hit exactly
> this: #30/#31, reissued as #32/#33). Separate identical-content branches
> give each twin its own SHA, so each holds its own verdict. This is a
> real-repo requirement too: the actual `v1-hotfix-create.yaml` must open
> its twins on separate branches for the same reason.

**Step 3 — try to merge production FIRST:**

```sh
gh pr checks <prod-twin>         # gate: FAIL — "has not ridden uat — Yellow train before red."
gh pr merge <prod-twin> --merge  # refused: required check is red
```

**Step 4 — the right order:**

```sh
gh pr merge <uat-twin> --merge          # its own gate is green; uat deploys, rc-tag
# the prod twin's gate verdict predates the uat merge — re-run it to re-judge:
gh run rerun <prod-gate-run-id>         # or "Re-run" in the web UI
gh pr merge <prod-twin> --merge         # now green: picks are on uat
gh run watch                            # production deploy
git fetch --tags -f && git tag -l 'rel-*'   # rel-YYYY.MM.DD-hf1
```

**Step 5 — try to cheat** (on a NEW hotfix branch, or before merging):
hand-edit a file on the hotfix branch, commit without `-x`, push. The gate
names your commit: **UNSTAMPED … Hand edits don't ride trains.** (The
shakedown's PRs #10/#11 show exactly this — read their comment threads.)

One edge worth knowing: if the uat twin shows **conflicts** (it can, when the
fix touches files whose uat and production copies have diverged histories),
close it and ride a normal yellow train to uat instead
(`promote target=uat prs=<fix-pr>`) — the production twin doesn't care *how*
its picks got to uat, only that they did. The shakedown's #15→#17→#16 chain
is a worked example.

**What you should observe:** production got ONE change (check its deploy
summary: qb redeployed, behavior shows your fix on top of 1.3-era strings —
dev's other work did NOT come along); the release notes on the prod deploy
list just your PR; the tag says `-hf1`.

**What just happened:** the hotfix lane is the train engine pointed at
production, plus twins. Ordering wasn't a checklist item — the production
twin was *physically unmergeable* until uat had the picks. Compare Act 1.5's
hotfix: release branch, version 1.3.1, registry publish, repin PR, manifest
entry. Here: two merges and a tag, and `git log production` IS the manifest.

---

## Exercise 3.6 — Pull-back: reverting is just another fix

**Goal:** un-ship something using the exact same lane, in reverse.

**Commands:**

```sh
git switch dev && git pull
git revert -m 1 <merge-commit-of-something-released>   # or revert a plain commit
git switch -c revert-<thing> && git push -u origin HEAD
gh pr create --base dev --title "revert: <thing>" && gh pr merge --merge
gh workflow run hotfix.yaml -f prs=<revert-pr>
# twins: uat first, then production — identical drill to 3.5
```

**What you should observe:** the same twin flow, same stamps, same gate, same
`rel-…-hfN` tag — with release notes that say "revert: …". The pull-back has
the same paper trail as the ship.

**What just happened:** symmetric flow. In the pinned world a pull-back is
"pin back to the old version" (fast, surgical — that's its superpower). Here
it's "land the inverse commit and release it" — one more train. Neither world
skips the paperwork; they just keep it in different ledgers (pins vs commits).

---

## Closing tally — Act 2 vs Act 1.5, side by side

Same yardstick as exercise 2.5. One behavior change in a shared package,
landed and released to uat:

| | pinned world (Act 1.5) | source world (Act 2) |
|---|---|---|
| steps to uat | 1 push + 1 bot-repin-PR merge (auto-bump + publish + repin in between) | 1 dev PR merge + 1 promotion/train PR merge |
| workflow runs involved | ~4 (publish, repin, resolve-check, deploy) | ~3 (deploy dev, gate, deploy uat) |
| human-owned records | version numbers (bot-minted, human-reviewed), pins per consumer, manifest correctness | which PRs board a train — that's the list |
| bots needed | repin bot, auto-bump, drift alarm, provenance manifest | none of those; 1 visibility bot (stranded-pr) |
| credentials to keep alive | LAB_BOT_PAT | LAB_BOT_PAT (same teachable, 3.4) |
| "what runs in prod?" | manifest.json + pins archaeology | `git log production` — the branch is the answer |
| ship qb to ONE consumer only | yes — pin just that consumer | **no** — common/ change redeploys every consumer on the branch |
| hotfix artifact left behind | `release/qb-1.3.0` branch shelf, forever | a deleted `hotfix/pr-N` branch and a `rel-*-hfN` tag |
| partial release | choose pins, per env | choose train picks (dependency detector watching) — **to uat only**; production takes uat whole |
| failure mode to fear | forgotten repin / stale pin (drift alarm exists *because* of it) | conflicted pick = hidden dependency (detector names it); squash-merge erasing stamps (ruleset forbids it) |

Count what each column asks a human to *remember* versus *decide*. The pinned
world spends its machinery on bookkeeping (versions, pins, manifests) and
buys surgical control per consumer. The source world deletes the bookkeeping
outright — ancestry and stamps are computed, not recorded — and pays for it
in blast radius: the branch releases together.

Neither column is the verdict. The verdict is a question: **which set of
things-that-can-go-wrong would your team rather own?**
