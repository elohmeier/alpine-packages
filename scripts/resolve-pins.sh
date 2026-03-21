#!/usr/bin/env bash
# Resolve expected-commit SHAs and checksums after Renovate version bumps.
# Run from the repository root.
set -euo pipefail

cd "$(dirname "$0")/.."

for yaml in *.yaml; do
  version=$(yq -r '.package.version' "$yaml" 2>/dev/null) || continue
  [ "$version" = "null" ] && continue

  # Skip files without expected-commit
  grep -q 'expected-commit:' "$yaml" || continue

  # Extract repository URL
  repo=$(grep 'repository:' "$yaml" | head -1 | sed 's|.*github.com/||;s|\.git.*||' | xargs)
  [ -z "$repo" ] && continue

  # Extract tag pattern and resolve
  tag_line=$(grep '^\s*tag:' "$yaml" | head -1 | sed 's/.*tag: *//')
  tag=$(echo "$tag_line" | sed "s/\\\${{package.version}}/$version/g")

  # Skip non-version tags (e.g. branch-based checkouts)
  echo "$tag_line" | grep -q 'package.version' || continue

  echo "Resolving $yaml: $repo@$tag"

  # Get commit SHA via GitHub API (handles both lightweight and annotated tags)
  ref_json=$(gh api "repos/$repo/git/ref/tags/$tag" 2>/dev/null) || {
    echo "  WARNING: Could not resolve tag $tag for $repo"
    continue
  }

  sha=$(echo "$ref_json" | jq -r '.object.sha')
  obj_type=$(echo "$ref_json" | jq -r '.object.type')

  if [ "$obj_type" = "tag" ]; then
    sha=$(gh api "repos/$repo/git/tags/$sha" --jq '.object.sha')
  fi

  old_sha=$(grep 'expected-commit:' "$yaml" | head -1 | awk '{print $2}')

  if [ "$old_sha" != "$sha" ]; then
    echo "  Updating expected-commit: $old_sha -> $sha"
    sed -i "s/$old_sha/$sha/" "$yaml"
  else
    echo "  expected-commit already up to date"
  fi
done
