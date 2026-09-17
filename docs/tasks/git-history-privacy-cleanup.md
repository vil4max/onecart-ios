# Git history privacy cleanup

Assignee: onecart-e1
State: blocked
Requested by: agent-engineering-kit-40 relaying owner request (2026-09-17)
Evidence: #37 (phone removed from HEAD), review video removed from HEAD; history rewrite blocked until 1.2.1 App Review ends and the owner says yes to the force push in this session

## Goal

Find personal material and secrets that ever existed in any ref of this public repository and
prepare an owner-approved plan to remove them from history. Privacy gate: personal diaries,
career or social notes, naming brainstorms, competitive research, business strategy, learning
plans, private system names, machine paths, personal contact data, secrets.

## Audit (2026-09-17)

Scope: 297 commits reachable from `main`, `testflight`, `release`, tags `v1.2.0`, `v1.2.1`, and
25 local agent checkpoint refs (`refs/codex/*`, `refs/copilot/*`, never pushed). Remote refs:
`main`, `testflight`, `release`, two tags, 36 `refs/pull/*`; no forks.

Method: `git log --all --name-only` (617 paths ever tracked) filtered by name; a content scan of
every added line in `git log --all -p` for JWT/API-key/private-key/token patterns, Supabase keys,
e-mail addresses, phone numbers and `/Users/` paths; frames extracted from both committed videos.

| Path | First / last commit | Why sensitive | Proposal |
|---|---|---|---|
| `docs/release.md` → `docs/operations/release.md` (line "Contact: … phone") | `d155ff5` (2026-09-01) / still at `HEAD` | Owner's personal phone number in a public file | Remove from `HEAD` now (this PR); rewrite the string out of history |
| `assets/store/review/delete-account-physical-2026-09-01.mp4` | `4a0a9cb` / still at `HEAD` | App Review screen recording from a physical device shows the owner's Apple Account name and profile photo in the Sign in with Apple sheet | Owner decides: keep (review evidence) or remove from `HEAD` and history |
| `qa/onecart-backup.json`, `qa/onecart-lists.csv`, `qa/dogfood-report.md` | `ebd4583` / removed in `bf2eaf1` | Web-prototype seed data with family first names as users; store addresses are public shops | Low; owner decides |
| `justfile` (a `/Users/<local user>/Library/Developer/…` path) | `e1a37bc` / removed in `3bfaf91` | Local machine user path | Low; rewrite the string if history is rewritten anyway |
| `ios/App/App/SupabaseServices.swift` (`sb_publishable_…`), `docs/legacy.md`, `NATIVE_IOS.md` (Supabase project ref) | `ebd4583` / removed by `bf2eaf1` and later docs | Supabase publishable (client) key and project ref of the retired backend; publishable keys are designed to ship in clients | Revoke the key / delete the retired Supabase project instead of relying on a rewrite |
| Second commit author identity with a personal e-mail (28 commits) | `ebd4583` / `723c88d` | Second personal e-mail address in commit metadata | Owner decides: keep, or map to the primary identity with `--mailbox-map` |
| Local `refs/codex/*`, `refs/copilot/*` (25 refs) | agent checkpoints | Dead local artifacts; not on GitHub | Delete locally (owner approval) |

Not sensitive: `vil4max@gmail.com` (public support contact and primary author), bundle ID, team
ID, `fastlane/Appfile`, `invite-site/.openai/hosting.json` (empty bindings), `design-system/`,
`tf-welcome-siwa.mp4` (simulator recording), Supabase migrations (`service_role` grants are SQL,
not keys). No private keys, tokens, `.env` or certificate files were ever committed.

## Approvals

- 2026-09-17, owner direct in session github-privacy-revision, relayed by that session:
  "подтверждаю - исправляй, отправляй сессиям задания" — approves the removal list below, removing
  the review video, the rewrite plan, and preparing the GitHub Support text.
- 2026-09-17, owner direct in the same session: "катору в авторах комитах нормально - не нормально
  в коде" — the second author identity stays in commit metadata (no author remap, superseding an
  earlier "убирай"); the identity's user name and the owner's local user name must not appear in
  file content on `HEAD` or in history.
- Still required in this session before execution: the owner's direct yes to the force push and
  tag re-creation. Owner-only: revoking the retired Supabase key, sending the GitHub Support
  request.

## Approved removal list

| Kind | Target | filter-repo option |
|---|---|---|
| Path | `assets/store/review/delete-account-physical-2026-09-01.mp4` | `--invert-paths --path` |
| Path | `qa/onecart-backup.json`, `qa/onecart-lists.csv`, `qa/dogfood-report.md` | `--invert-paths --path` |
| String | owner phone number in `docs/release.md`, `docs/operations/release.md` | `--replace-text` |
| String | the local user path in `justfile` | `--replace-text` → `$HOME/` |
| String | retired Supabase publishable key and project ref (`SupabaseServices.swift`, `docs/legacy.md`, `NATIVE_IOS.md`) | `--replace-text` → `<redacted>` |
| String | the second identity's user name and e-mail user part, and the owner's local user name (Latin and Cyrillic spellings), in file content | `--replace-text` (regex, case-insensitive); commit author/committer metadata unchanged |

## Rewrite plan (approved scope; not executed)

1. Owner approves the final removal list from the table above.
2. Tool: `git filter-repo` (already installed at `/opt/homebrew/bin/git-filter-repo`).
3. Work in a fresh mirror clone under
   `~/Developer/Personal/agent-artifacts/2026-09-17/github-privacy-revision/work/onecart/`:
   `git clone --mirror https://github.com/vil4max/OneCart.git`, then a backup
   `git bundle create onecart-before-rewrite.bundle --all` kept in `outputs/`.
4. Rewrite in one `git filter-repo` run with the approved removal list (expressions and mailmap
   files stay in `work/`, never in the repository).
5. Verify in the mirror: the audit scan finds none of the removed strings or paths;
   `git grep` over every revision for the removed user names returns nothing (commit metadata is
   not rewritten and keeps the second author identity); `git fsck`; `main` tree equals
   the pre-rewrite `main` tree apart from removed paths and strings.
6. Refs that change: every commit from the first affected one (`ebd4583` if `qa/` or the author
   map is included, otherwise `d155ff5`) onward, so `main`, `testflight`, `release`, `v1.2.0`,
   `v1.2.1` all get new SHAs.
7. Impact and ordering:
   - Wait until App Review for 1.2.1 finishes (build 105 comes from `release` at `a5e6915`;
     Xcode Cloud keeps its archive, the ref rewrite does not affect a submitted build).
   - Pause merges; no open PRs or other worktrees exist now (check again before starting).
   - Force-push `main`, then `testflight` and `release` to the rewritten SHAs, then force-update
     tags. Pushing `testflight`/`release` starts Xcode Cloud builds of already-shipped code:
     disable both Xcode Cloud workflows during the push or cancel those builds.
   - `promote-release.sh` checks a `Tests` run for the tagged SHA: rewritten tag SHAs have no
     runs, so re-tagged old releases cannot be re-promoted (not needed); the next release works
     normally after a green push.
   - Every local clone and session must re-clone or hard-reset; announce before and after.
   - GitHub keeps the old commits reachable through the 36 `refs/pull/*` refs and cached views
     until GitHub Support purges them; request that only after the force push.
8. After the push: every local clone and worktree is re-cloned (this checkout included), and the
   audit is re-run against `origin`.

## GitHub Support request (owner sends it after the force push)

> Subject: Remove cached views and pull request refs after a history rewrite — vil4max/OneCart
>
> Hello, I rewrote the history of my public repository https://github.com/vil4max/OneCart to
> remove personal data (a phone number, a screen recording showing my account name and photo,
> seed data with family names, a local machine path, a retired API key, and a second e-mail
> address in commit metadata). The rewritten branches and tags are already force-pushed.
> Old commits are still reachable through the repository's `refs/pull/*` refs (pull requests
> #1–#38) and cached commit and file views. Please run garbage collection and purge cached views
> and pull request refs that point to the pre-rewrite commits. The repository has no forks.
> Thank you.

## Done in this brief

- Phone number removed from `docs/operations/release.md` at `HEAD` (#37).
- Review video copied to
  `~/Developer/Personal/agent-artifacts/2026-09-17/github-privacy-revision/work/onecart/`
  (SHA-256 `8afe91f1…5b60`, identical to the committed file) and removed from `HEAD`; links in
  `docs/operations/release.md` and `assets/store/README.md` updated.
- Latin user name removed from file content on `HEAD`: `AGENTS.md`, `docs/engineering/review-changelog.md`,
  test fixture name in `OneCart/Tests/CartActivityDiffTests.swift`.
- Cyrillic spelling of the same first name renamed in test fixtures, and personal first names in
  demo data, the debug test account, tests and docs replaced with neutral ones (owner direct in
  this session, 2026-09-17: rename it in tests and keep the project neutral, not tied to specific
  people); `just verify` passed.
