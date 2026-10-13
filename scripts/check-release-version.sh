#!/usr/bin/env bash
# Fail unless the release tag is "v" + the version in .claude-plugin/plugin.json.
# An unchanged plugin version keeps users on their cached copy, so a release
# must never ship without its version bump.
set -euo pipefail
tag="${1:?usage: scripts/check-release-version.sh <tag>}"
root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$root/.claude-plugin/plugin.json")"
if [ "$tag" != "v$version" ]; then
  echo "release tag $tag does not match plugin.json version $version (want v$version)" >&2
  exit 1
fi
echo "release tag $tag matches plugin.json version $version"
