# ADR 0004: Tags, not pushes, request TestFlight builds

Status: accepted. Supersedes the promotion, `release` branch and tag sections of
[ADR 0003](0003-ci-split.md); ADR 0003's split — GitHub Actions tests, Xcode Cloud archives —
stands.

## Context

Under the earlier design, every push to `main` whose `Tests` run passed fast-forwarded
`testflight`, and Xcode Cloud archived and uploaded every such commit. Every push was a
TestFlight build, including commits that change no shipped code. A tooling-only update could not
be pushed without spending an Xcode Cloud build on a binary identical to the one testers already
had, so `main` could sit ahead of `origin`: the repository could be clean or cheap, not both.

The same design has a hard failure mode: App Store Connect refuses a build with
`ITMS-90382: Upload limit reached` once too many builds are uploaded, documentation-only commits
included. Gating builds behind tags avoids the cost, and the shared build tooling now ships that
model.

## Decision

OneCart uses the tag model as installed under `Tooling/` — see
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

- [`.github/workflows/testflight.yml`](../../.github/workflows/testflight.yml) — copied unchanged
  from `Tooling/templates/github/testflight.yml`, which pins its actions by commit.
- `Tooling/scripts/tf-promote.sh`, `tf-check.sh`, `testflight-lib.sh` — owned by the shared
  tooling, updated by `just harness-update`, not edited here.
- [`.github/workflows/tests.yml`](../../.github/workflows/tests.yml) — the shared tests workflow
  (`just ci`); its concurrency keeps one run per pushed commit on `main`, which the tag checks
  depend on.

`BUILD` counts the TestFlight rounds of one marketing version from `1`. It names the round, not
the uploaded build number, which `OneCart/ci_scripts/ci_post_clone.sh` takes from
`CI_BUILD_NUMBER`. The tag annotation is the round's What to Test: a checklist of behaviour a
tester can pass or fail, plus what was not verified.

Tag authority: the maintainer creates `v` tags and submits for App Review. `AGENTS.md` records
who may create `tf-` tags.

## Consequences

- Tooling, documentation and refactoring commits push for free, so `main` can stay equal to
  `origin/main` without spending builds.
- A TestFlight round is a deliberate act: someone must tag. A `testflight` branch that has not
  moved no longer means `Tests` is broken; it means nobody asked for a build.
- Only the head commit of a push has a `Tests` run of its own, so only it can be tagged. Push
  a release-prep commit last, or alone. `just tf-check` blocks a mid-push commit before a tag
  is wasted on it.
- The App Review candidate is a TestFlight build picked in App Store Connect, not a separate
  archive. `scripts/promote-release.sh` and `.github/workflows/release.yml` are removed; nothing
  moves the `release` branch any more. It stays at the commit tagged `v1.2.1`, and the Xcode
  Cloud "App Store candidate (release tag)" workflow, which only that branch started, is unused.
- A rejected tag must be deleted locally and remotely before retrying
  (`git push origin :refs/tags/tf-X.Y.Z-N`). A tag on a commit `testflight` already contains
  moves nothing; rebuild such a commit with Start Build on `testflight` in App Store Connect.
- The repository has no git hooks: push hooks build and test nothing. `just verify` and the
  `Tests` workflow run the tests.
- Because the App Review candidate is a TestFlight round's build, the one remaining Xcode
  Cloud workflow must archive with distribution preparation **TestFlight and App Store**. Apple:
  choose "TestFlight (Internal Testing Only)" to distribute a development version to your team,
  and "TestFlight and App Store" to create a binary eligible for public TestFlight testing and
  release on the App Store
  ([Creating a workflow that builds your app for distribution](https://developer.apple.com/documentation/xcode/creating-a-workflow-that-builds-your-app-for-distribution)).
  The same page makes **Restrict editing** in the workflow's General settings "a required step
  if you want to create a build that's eligible for app review", and lists selecting **Clean**
  in its Environment settings, so builds start without cached data. Order of changes in App
  Store Connect: first give that workflow TestFlight and App Store distribution, restricted
  editing and a start condition of branch changes on `testflight` only, then retire "App Store
  candidate (release tag)". Retiring it first could leave no build that can be submitted. ADR
  0003 records the resulting settings.

## Rejected alternatives

- **Keep promoting every green push, and skip documentation-only pushes.** Needs a path filter
  that predicts which files affect the binary, and still spends a build on every code push
  nobody asked testers to try.
- **Keep promoting every green push, and hold tooling commits locally.** `main` sits ahead of
  `origin` and depends on someone remembering to push.
- **Tag-gated TestFlight, but keep the `release` branch and its second archive for App
  Review.** Keeps two builds of one commit and a second Xcode Cloud workflow, and needs an
  app-local promotion script beside the shared one.
- **Copy app-local promotion scripts into each app.** Would make every app a separate copy of
  the same checks; the shared tooling owns them.
