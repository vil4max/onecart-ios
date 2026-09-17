# Git history privacy cleanup

Assignee: onecart-e1
State: blocked
Requested by: agent-engineering-kit-40 relaying owner request (2026-09-17)
Evidence: audit and plan below (blocked on owner approval of the removal list); no history rewrite or force push done

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
| `justfile` (`$HOME/Library/Developer/…`) | `e1a37bc` / removed in `3bfaf91` | Local machine user path | Low; rewrite the string if history is rewritten anyway |
| `ios/App/App/SupabaseServices.swift` (`sb_publishable_…`), `docs/legacy.md`, `NATIVE_IOS.md` (Supabase project ref) | `ebd4583` / removed by `bf2eaf1` and later docs | Supabase publishable (client) key and project ref of the retired backend; publishable keys are designed to ship in clients | Revoke the key / delete the retired Supabase project instead of relying on a rewrite |
| Commit author `alex member <member@gmail.com>` (28 commits) | `ebd4583` / `723c88d` | Second personal e-mail address in commit metadata | Owner decides: keep, or map to the primary identity with `--mailbox-map` |
| Local `refs/codex/*`, `refs/copilot/*` (25 refs) | agent checkpoints | Dead local artifacts; not on GitHub | Delete locally (owner approval) |

Not sensitive: `vil4max@gmail.com` (public support contact and primary author), bundle ID, team
ID, `fastlane/Appfile`, `invite-site/.openai/hosting.json` (empty bindings), `design-system/`,
`tf-welcome-siwa.mp4` (simulator recording), Supabase migrations (`service_role` grants are SQL,
not keys). No private keys, tokens, `.env` or certificate files were ever committed.

## Rewrite plan (not executed; needs owner approval)

1. Owner approves the final removal list from the table above.
2. Tool: `git filter-repo` (already installed at `/opt/homebrew/bin/git-filter-repo`).
3. Work in a fresh mirror clone under
   `~/Developer/Personal/agent-artifacts/2026-09-17/onecart-history-cleanup/work/`:
   `git clone --mirror https://github.com/vil4max/OneCart.git`, then a backup
   `git bundle create onecart-before-rewrite.bundle --all` kept in `outputs/`.
4. Rewrite: `--replace-text` for the phone number and the `/Users/…` path, `--invert-paths
   --path …` for approved files, optional `--mailbox-map` for the author identity.
5. Verify in the mirror: re-run the audit scan (no matches), `git fsck`, both tags still point
   at commits with the same trees except removed paths.
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
8. Owner approvals required separately: removal list, running the rewrite, each force push,
   tag re-creation, disabling Xcode Cloud workflows, contacting GitHub Support.

## Done in this brief

- Phone number removed from `docs/operations/release.md` at `HEAD`.
