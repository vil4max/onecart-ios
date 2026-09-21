# ADR 0004: Tags, not pushes, request TestFlight builds

Status: accepted by the owner, 2026-09-21. Supersedes the promotion, `release` branch and tag
sections of [ADR 0003](0003-ci-split.md); ADR 0003's split — GitHub Actions tests, Xcode Cloud
archives — stands.

## Context

Under ADR 0003, every push to `main` whose `Tests` run passed fast-forwarded `testflight`, and
Xcode Cloud archived and uploaded every such commit. Every push was a TestFlight build,
including commits that change no shipped code. On 2026-09-21 a Runtime update that touches only
`Tooling/` could not be pushed without spending an Xcode Cloud build on a binary identical to
the one testers already had, so `main` sat ahead of `origin` — the repository could be clean or
cheap, not both.

The sibling app regional-check hit the costly end of the same design: every green merge
uploaded, documentation-only commits included, until App Store Connect refused a build with
`ITMS-90382: Upload limit reached` (its `docs/lessons.md`, 2026-09-17). It moved to tags (its
ADR 0012 and 0013) and, by its own count, avoided about 25 builds over the next 50 commits, 23
of which changed only documentation. The Runtime (`ios-agent-toolchain`) now ships that model
for every app.

## Decision

OneCart uses the Runtime's tag model as installed under `Tooling/` — see
[`Tooling/docs/testflight.md`](../../Tooling/docs/testflight.md) for the procedure. In short:

| Event | Effect |
|-------|--------|
| Push to `main` | `Tests` runs. Nothing is promoted and no build starts |
| Annotated `tf-MAJOR.MINOR.PATCH-BUILD` tag | GitHub Actions `TestFlight` checks it and fast-forwards `testflight`; Xcode Cloud "Internal TestFlight (verified main)" archives it for the Friends and Family group |
| Annotated `vMAJOR.MINOR.PATCH` tag | Moves nothing. `TestFlight` checks that it marks a commit with its own `tf-` round of that version — the build submitted to App Review |

A `tf-` or `v` tag is accepted only when it is annotated, every `MARKETING_VERSION` in the
project equals the tag's version, the commit is on `main`, and the commit has its own
successful `Tests` run for a push to `main` (the workflow waits up to 45 minutes for one).
`just tf-check [<commit>]` runs the same checks locally, read-only, and prints the tag
commands with the next free `BUILD`.

Pieces in this repository:

- [`.github/workflows/testflight.yml`](../../.github/workflows/testflight.yml) — copied from
  `Tooling/templates/github/testflight.yml`, with `actions/checkout` pinned by commit like every
  other workflow here.
- `Tooling/scripts/tf-promote.sh`, `tf-check.sh`, `testflight-lib.sh` — Runtime-owned; updated
  by `just harness-update`, not edited here.
- [`.github/workflows/tests.yml`](../../.github/workflows/tests.yml) — tests only; its
  concurrency keeps one run per pushed commit on `main`, which the tag checks depend on.

`BUILD` counts the TestFlight rounds of one marketing version from `1`. It names the round, not
the uploaded build number, which `OneCart/ci_scripts/ci_post_clone.sh` takes from
`CI_BUILD_NUMBER`. The tag annotation is the round's What to Test: a checklist of behaviour a
tester can pass or fail, plus what was not verified.

Tag authority: the owner creates `v` tags and submits for App Review. A `tf-` tag is the
owner's, or an agent's when the owner has authorized it; `AGENTS.md` records the current rule.

## Consequences

- Tooling, documentation and refactoring commits push for free, so `main` can stay equal to
  `origin/main` without spending builds.
- A TestFlight round is a deliberate act: someone must tag. A `testflight` branch that has not
  moved no longer means `Tests` is broken; it means nobody asked for a build.
- Only the head commit of a push has a `Tests` run of its own, so only it can be tagged. Push
  a release-prep commit last, or alone. `just tf-check` blocks a mid-push commit before a tag
  is wasted on it.
- The App Review candidate is a TestFlight build the owner picks in App Store Connect, not a
  separate archive. `scripts/promote-release.sh` and `.github/workflows/release.yml` are
  removed; nothing moves the `release` branch any more. It stays at `a5e6915` (`v1.2.1`) until
  the owner retires it, and the Xcode Cloud "App Store candidate (release tag)" workflow, which
  only that branch started, becomes unused — retiring it is the owner's step in App Store
  Connect.
- A rejected tag must be deleted locally and remotely before retrying
  (`git push origin :refs/tags/tf-X.Y.Z-N`). A tag on a commit `testflight` already contains
  moves nothing; rebuild such a commit with Start Build on `testflight` in App Store Connect.
- The local pre-push smoke run is unchanged: it already ran on every branch push and skips
  tag-only pushes.
- The description of "Internal TestFlight (verified main)" in App Store Connect still says it
  archives every `main` commit that passed `Tests`; the owner updates it there.
- Because the App Review candidate is now a TestFlight round's build, the one remaining Xcode
  Cloud workflow must archive with distribution preparation **TestFlight and App Store**. Apple:
  choose "TestFlight (Internal Testing Only)" to distribute a development version to your team,
  and "TestFlight and App Store" to create a binary eligible for public TestFlight testing and
  release on the App Store
  ([Creating a workflow that builds your app for distribution](https://developer.apple.com/documentation/xcode/creating-a-workflow-that-builds-your-app-for-distribution)).
  The same page makes **Restrict editing** in the workflow's General settings "a required step
  if you want to create a build that's eligible for app review", and lists selecting **Clean**
  in its Environment settings, so builds start without cached data. Which options the workflow
  uses today is not recorded in this repository. Order in App Store Connect: first give that
  workflow TestFlight and App Store distribution, restricted editing and a start condition of
  branch changes on `testflight` only, then retire "App Store candidate (release tag)". Retiring
  it first could leave no build that can be submitted.

## Rejected alternatives

- **Keep promoting every green push, and skip documentation-only pushes.** Needs a path filter
  that predicts which files affect the binary, and still spends a build on every code push
  nobody asked testers to try.
- **Keep promoting every green push, and hold tooling commits locally.** What happened on
  2026-09-21: `main` sits ahead of `origin` and depends on someone remembering to push.
- **Tag-gated TestFlight, but keep the `release` branch and its second archive for App
  Review.** Keeps two builds of one commit and a second Xcode Cloud workflow, and needs an
  app-local promotion script beside the Runtime's; regional-check dropped the same split in its
  ADR 0013 for those reasons.
- **Copy regional-check's app-local scripts.** Would make OneCart a third copy of the same
  checks; the Runtime now owns them for both apps.
