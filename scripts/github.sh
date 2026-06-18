#!/bin/sh
set -e

command -v gh > /dev/null 2>&1 || { printf 'Error: gh is not installed\n'; exit 1; }

for var in GH_TOKEN GH_REPO TAG JAR SOURCES_JAR; do
    val=$(printenv "$var")
    [ -z "$val" ] && printf 'Error: %s is not set\n' "$var" && exit 1
done

if gh release view "$TAG" --json isDraft --jq 'select(.isDraft == false) | true' 2>/dev/null | grep -q true; then
    printf 'Release %s already exists on GitHub, skipping.\n' "$TAG"
    exit 0
fi

gh release delete "$TAG" --yes 2>/dev/null || true

gh release create "$TAG" --title "$TAG" --generate-notes "$JAR" "$SOURCES_JAR"
