#!/usr/bin/env bash
# Resolve expected-commit SHAs and checksums after Renovate version bumps.
# Run from the repository root.
set -uo pipefail

cd "$(dirname "$0")/.."

for yaml in *.yaml; do
  version=$(yq -r '.package.version' "$yaml" 2>/dev/null || true)
  [ -z "$version" ] || [ "$version" = "null" ] && continue

  # --- 1. Resolve expected-commit SHAs for git-checkout packages ---
  if grep -q 'expected-commit:' "$yaml"; then
    tag_line=$(grep '^\s*tag:' "$yaml" | head -1 | sed 's/.*tag: *//' || true)
    if echo "$tag_line" | grep -q 'package.version'; then
      repo=$(grep 'repository:' "$yaml" | head -1 | sed 's|.*github.com/||;s|\.git.*||' | xargs || true)
      if [ -n "$repo" ]; then
        tag=$(echo "$tag_line" | sed "s/\\\${{package.version}}/$version/g")
        echo "Resolving commit: $yaml $repo@$tag"

        if ref_json=$(gh api "repos/$repo/git/ref/tags/$tag" 2>/dev/null); then
          sha=$(echo "$ref_json" | jq -r '.object.sha')
          obj_type=$(echo "$ref_json" | jq -r '.object.type')
          if [ "$obj_type" = "tag" ]; then
            sha=$(gh api "repos/$repo/git/tags/$sha" --jq '.object.sha' 2>/dev/null || true)
          fi

          if [ -n "$sha" ]; then
            old_sha=$(grep 'expected-commit:' "$yaml" | head -1 | awk '{print $2}')
            if [ "$old_sha" != "$sha" ]; then
              echo "  Updating expected-commit: $old_sha -> $sha"
              sed -i "s/$old_sha/$sha/" "$yaml"
            else
              echo "  expected-commit already up to date"
            fi
          fi
        else
          echo "  WARNING: Could not resolve tag $tag for $repo"
        fi
      fi
    fi
  fi

  # --- 2. Resolve expected-sha256 for fetch-based packages ---
  if grep -q 'expected-sha256:' "$yaml"; then
    # Extract the URI from the fetch pipeline step
    uri=$(grep -A2 'uses: fetch' "$yaml" | grep 'uri:' | head -1 | sed 's/.*uri: *//' || true)
    [ -z "$uri" ] && continue

    # Only handle URIs that reference package.version (not build.arch)
    echo "$uri" | grep -q 'package.version' || continue
    # Skip URIs with build.arch — those need per-arch handling
    if echo "$uri" | grep -q 'build.arch'; then
      echo "Skipping $yaml: per-arch fetch URI (manual update needed)"
      continue
    fi

    resolved_url=$(echo "$uri" | sed "s/\\\${{package.version}}/$version/g")
    echo "Resolving sha256: $yaml -> $resolved_url"

    new_sha=$(curl -sL "$resolved_url" | sha256sum | awk '{print $1}')
    if [ -z "$new_sha" ] || [ "$new_sha" = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]; then
      echo "  WARNING: Download failed or empty file"
      continue
    fi

    old_sha=$(grep 'expected-sha256:' "$yaml" | head -1 | awk '{print $2}')
    if [ "$old_sha" != "$new_sha" ]; then
      echo "  Updating expected-sha256: $old_sha -> $new_sha"
      sed -i "s/$old_sha/$new_sha/" "$yaml"
    else
      echo "  expected-sha256 already up to date"
    fi
  fi

  # --- 3. Resolve inline SHA256 checksums in case statements (codex pattern) ---
  if grep -q 'EXPECTED_SHA256=' "$yaml" && grep -q 'build.arch' "$yaml"; then
    # Extract the download URI template
    uri=$(grep 'uri:' "$yaml" | head -1 | sed 's/.*uri: *//' || true)
    [ -z "$uri" ] && continue
    echo "$uri" | grep -q 'package.version' || continue

    echo "Resolving per-arch checksums: $yaml"
    for arch in x86_64 aarch64; do
      resolved_url=$(echo "$uri" | sed "s/\\\${{package.version}}/$version/g;s/\\\${{build.arch}}/$arch/g")
      new_sha=$(curl -sL "$resolved_url" | sha256sum | awk '{print $1}')
      if [ -z "$new_sha" ] || [ "$new_sha" = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ]; then
        echo "  WARNING: Download failed for $arch"
        continue
      fi

      # Find the old SHA for this arch in the case statement
      # Pattern: arch) \n EXPECTED_SHA256="<sha>"
      old_sha=$(awk "/$arch\\)/{getline; match(\$0, /\"([a-f0-9]{64})\"/, m); print m[1]}" "$yaml" || true)
      if [ -n "$old_sha" ] && [ "$old_sha" != "$new_sha" ]; then
        echo "  Updating $arch: $old_sha -> $new_sha"
        sed -i "s/$old_sha/$new_sha/" "$yaml"
      else
        echo "  $arch already up to date"
      fi
    done
  fi
done

echo "Done."
