#!/usr/bin/env bash
# Moves the release branch to a verified, correctly versioned release tag.
#
# Usage: scripts/promote-release.sh <vMAJOR.MINOR.PATCH>
#
# Xcode Cloud builds App Store candidates from the release branch. A tag is
# promoted only when it is annotated, matches MARKETING_VERSION, is on main,
# and the Tests run for a push of that exact commit to main succeeded. Being an
# ancestor of testflight is not enough: a later green commit would promote past
# a red tagged commit. Tagging right after pushing is fine: the script waits.
#
# Needs GH_TOKEN with actions:read and GITHUB_REPOSITORY (both set in Actions).
set -euo pipefail

TAG="${1:-}"
REMOTE="${RELEASE_REMOTE:-origin}"
WAIT_ATTEMPTS="${RELEASE_WAIT_ATTEMPTS:-45}"
WAIT_SECONDS="${RELEASE_WAIT_SECONDS:-60}"
TESTS_WORKFLOW="${RELEASE_TESTS_WORKFLOW:-tests.yml}"
PBXPROJ="OneCart/OneCart.xcodeproj/project.pbxproj"

fail() {
  echo "::error::$*" >&2
  exit 1
}

# Prints success, failure, pending, or missing for the Tests runs of a push of $1 to main.
tests_state() {
  gh api "repos/${GITHUB_REPOSITORY}/actions/workflows/${TESTS_WORKFLOW}/runs?head_sha=${1}&event=push&branch=main" \
    --jq '[.workflow_runs[] | {status, conclusion}] as $runs
      | if ($runs | length) == 0 then "missing"
        elif any($runs[]; .conclusion == "success") then "success"
        elif any($runs[]; .status != "completed") then "pending"
        else "failure" end'
}

[[ -n "${GITHUB_REPOSITORY:-}" ]] || fail "GITHUB_REPOSITORY is not set"
[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "tag '$TAG' is not vMAJOR.MINOR.PATCH"
git fetch --quiet "$REMOTE" "refs/tags/$TAG:refs/tags/$TAG"
[[ "$(git cat-file -t "refs/tags/$TAG")" == "tag" ]] || fail "$TAG must be an annotated tag"

sha="$(git rev-list -n 1 "refs/tags/$TAG")"
version="${TAG#v}"
versions="$(git show "${sha}:${PBXPROJ}" | grep -o 'MARKETING_VERSION = [^;]*' | sed 's/.*= //' | sort -u)"
[[ "$versions" == "$version" ]] || fail "$TAG does not match MARKETING_VERSION at ${sha:0:7}: $(echo "$versions" | tr '\n' ' ')"
git fetch --quiet "$REMOTE" main
git merge-base --is-ancestor "$sha" FETCH_HEAD || fail "$TAG (${sha:0:7}) is not on main"

for ((attempt = 1; ; attempt++)); do
  state="$(tests_state "$sha")"
  case "$state" in
    success)
      echo "${sha:0:7} passed Tests on main"
      break
      ;;
    failure)
      fail "Tests failed for ${sha:0:7}; fix main, bump PATCH, and tag the fixed commit"
      ;;
  esac
  # A commit inside a multi-commit push has no run of its own and stays "missing".
  if ((attempt >= WAIT_ATTEMPTS)); then
    fail "no successful Tests run for a push of ${sha:0:7} to main ($state); tag the commit a Tests run verified, or rerun this workflow once it is green"
  fi
  echo "waiting for Tests on ${sha:0:7}: $state ($attempt/$WAIT_ATTEMPTS)"
  sleep "$WAIT_SECONDS"
done

# promote-testflight runs in the same Tests run, so a green run has already moved testflight.
if ! { git fetch --quiet "$REMOTE" testflight 2>/dev/null && git merge-base --is-ancestor "$sha" FETCH_HEAD; }; then
  fail "${sha:0:7} passed Tests but is not on testflight; check the promote-testflight job"
fi

if git fetch --quiet "$REMOTE" release 2>/dev/null && git merge-base --is-ancestor "$sha" FETCH_HEAD; then
  echo "release already contains $TAG"
  exit 0
fi
git push "$REMOTE" "${sha}:refs/heads/release"
echo "release -> $TAG (${sha:0:7})"
