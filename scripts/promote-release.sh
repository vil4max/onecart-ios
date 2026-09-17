#!/usr/bin/env bash
# Moves the release branch to a verified, correctly versioned release tag.
#
# Usage: scripts/promote-release.sh <vMAJOR.MINOR.PATCH>
#
# Xcode Cloud builds App Store candidates from the release branch. A tag is
# promoted only when it is annotated, matches MARKETING_VERSION, is on main,
# and its commit already reached testflight (every GitHub check passed there).
# Tagging right after pushing is fine: the script waits for that promotion.
set -euo pipefail

TAG="${1:-}"
REMOTE="${RELEASE_REMOTE:-origin}"
WAIT_ATTEMPTS="${RELEASE_WAIT_ATTEMPTS:-45}"
WAIT_SECONDS="${RELEASE_WAIT_SECONDS:-60}"
PBXPROJ="OneCart/OneCart.xcodeproj/project.pbxproj"

fail() {
  echo "::error::$*" >&2
  exit 1
}

[[ "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "tag '$TAG' is not vMAJOR.MINOR.PATCH"
git fetch --quiet "$REMOTE" "refs/tags/$TAG:refs/tags/$TAG"
[[ "$(git cat-file -t "refs/tags/$TAG")" == "tag" ]] || fail "$TAG must be an annotated tag"

sha="$(git rev-list -n 1 "refs/tags/$TAG")"
version="${TAG#v}"
versions="$(git show "$sha:$PBXPROJ" | grep -o 'MARKETING_VERSION = [^;]*' | sed 's/.*= //' | sort -u)"
[[ "$versions" == "$version" ]] || fail "$TAG does not match MARKETING_VERSION at ${sha:0:7}: $(echo "$versions" | tr '\n' ' ')"
git fetch --quiet "$REMOTE" main
git merge-base --is-ancestor "$sha" FETCH_HEAD || fail "$TAG (${sha:0:7}) is not on main"

for ((attempt = 1; ; attempt++)); do
  if git fetch --quiet "$REMOTE" testflight 2>/dev/null && git merge-base --is-ancestor "$sha" FETCH_HEAD; then
    echo "${sha:0:7} passed all checks (reached testflight)"
    break
  fi
  if ((attempt >= WAIT_ATTEMPTS)); then
    fail "${sha:0:7} has not reached testflight; check the Tests run, then rerun this workflow"
  fi
  echo "waiting for ${sha:0:7} to reach testflight ($attempt/$WAIT_ATTEMPTS)"
  sleep "$WAIT_SECONDS"
done

if git fetch --quiet "$REMOTE" release 2>/dev/null && git merge-base --is-ancestor "$sha" FETCH_HEAD; then
  echo "release already contains $TAG"
  exit 0
fi
git push "$REMOTE" "${sha}:refs/heads/release"
echo "release -> $TAG (${sha:0:7})"
