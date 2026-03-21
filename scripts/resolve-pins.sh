#!/usr/bin/env bash
# Resolve expected-commit SHAs and checksums after Renovate version bumps.
# Run from the repository root.
set -uo pipefail

cd "$(dirname "$0")/.."

for yaml in *.yaml; do
  # Skip files without expected-commit
  grep -q 'expected-commit:' "$yaml" || continue

  # Skip files without a tag referencing package.version
  tag_line=$(grep '^\s*tag:' "$yaml" | head -1 | sed 's/.*tag: *//' || true)
  echo "$tag_line" | grep -q 'package.version' || continue

  # Extract version
  version=$(yq -r '.package.version' "$yaml" 2>/dev/null || true)
  [ -z "$version" ] || [ "$version" = "null" ] && continue

  # Extract repository URL
  repo=$(grep 'repository:' "$yaml" | head -1 | sed 's|.*github.com/||;s|\.git.*||' | xargs || true)
  [ -z "$repo" ] && continue

  # Resolve tag
  tag=$(echo "$tag_line" | sed "s/\\\${{package.version}}/$version/g")

  echo "Resolving $yaml: $repo@$tag"

  # Get commit SHA via GitHub API (handles both lightweight and annotated tags)
  if ! ref_json=$(gh api "repos/$repo/git/ref/tags/$tag" 2>/dev/null); then
    echo "  WARNING: Could not resolve tag $tag for $repo"
    continue
  fi

  sha=$(echo "$ref_json" | jq -r '.object.sha')
  obj_type=$(echo "$ref_json" | jq -r '.object.type')

  if [ "$obj_type" = "tag" ]; then
    sha=$(gh api "repos/$repo/git/tags/$sha" --jq '.object.sha' 2>/dev/null || true)
    [ -z "$sha" ] && continue
  fi

  old_sha=$(grep 'expected-commit:' "$yaml" | head -1 | awk '{print $2}')

  if [ "$old_sha" != "$sha" ]; then
    echo "  Updating expected-commit: $old_sha -> $sha"
    sed -i "s/$old_sha/$sha/" "$yaml"
  else
    echo "  expected-commit already up to date"
  fi
done

echo "Done."
