#!/usr/bin/env bash
set -euo pipefail

: "${RELEASE_TAG:?Missing release tag}"
: "${EXPECTED_COMMIT:?Missing verified commit}"
: "${SDK_REPOSITORY_URL:?Missing SDK repository URL}"
: "${GITHUB_REPOSITORY:?Missing GitHub repository}"

# An annotated tag has its own object ID; compare its peeled commit instead.
remote_commit="$(git ls-remote --exit-code "$SDK_REPOSITORY_URL" \
  "refs/tags/$RELEASE_TAG" "refs/tags/$RELEASE_TAG^{}" |
  awk '$2 ~ /\^\{\}$/ { peeled = $1; next } { direct = $1 } END { print peeled ? peeled : direct }')"
if [[ "$remote_commit" != "$EXPECTED_COMMIT" ]]; then
  echo "Release tag $RELEASE_TAG no longer points to verified commit $EXPECTED_COMMIT (found $remote_commit)." >&2
  exit 1
fi

release_args=(--verify-tag --generate-notes --title "Release $RELEASE_TAG")
version_without_metadata="${RELEASE_TAG%%+*}"
if [[ "$version_without_metadata" == *-* ]]; then
  release_args+=(--prerelease --latest=false)
fi

gh release create "$RELEASE_TAG" --repo "$GITHUB_REPOSITORY" "${release_args[@]}"
