#!/bin/sh
set -e

for cmd in curl jq; do
    command -v "$cmd" > /dev/null 2>&1 || { printf 'Error: %s is not installed\n' "$cmd"; exit 1; }
done

for var in CURSEFORGE_API_TOKEN CURSEFORGE_LEGACY_API_TOKEN PROJECT_ID VERSION MINECRAFT_VERSIONS LOADERS JAR MOD_NAME; do
    val=$(printenv "$var")
    [ -z "$val" ] && printf 'Error: %s is not set\n' "$var" && exit 1
done

existing=$(curl -sf "https://api.curseforge.com/v1/mods/${PROJECT_ID}/files" \
    -H "x-api-key: ${CURSEFORGE_API_TOKEN}" \
    -H "User-Agent: victorfaurschou/${MOD_NAME}")

jar_name=$(basename "$JAR")
if printf '%s' "$existing" | jq -e --arg name "$jar_name" '.data | any(.[]; .fileName == $name)' > /dev/null; then
    printf 'Version %s already exists on CurseForge, skipping.\n' "$VERSION"
    exit 0
fi

versions=$(curl -sf "https://minecraft.curseforge.com/api/game/versions" \
    -H "X-Api-Token: ${CURSEFORGE_LEGACY_API_TOKEN}" \
    -H "User-Agent: victorfaurschou/${MOD_NAME}")

gvn_list=""

for mc_version in ${MINECRAFT_VERSIONS}; do
    gvn_list="${gvn_list:+$gvn_list,}\"$mc_version\""
done

for loader in ${LOADERS}; do
    loader_name=$(printf '%s' "$versions" | jq -r --arg slug "$loader" 'first(.[] | select(.slug == $slug) | .name)')
    [ -z "$loader_name" ] && printf 'Error: Could not find "%s" loader on CurseForge\n' "$loader" && exit 1
    gvn_list="${gvn_list:+$gvn_list,}\"$loader_name\""
done

case "${ENVIRONMENT:-}" in
    client) gvn_list="${gvn_list:+$gvn_list,}\"Client\"" ;;
    server) gvn_list="${gvn_list:+$gvn_list,}\"Server\"" ;;
    both)   gvn_list="${gvn_list:+$gvn_list,}\"Client\",\"Server\"" ;;
    "")     ;;
    *)      printf 'Error: Invalid ENVIRONMENT value: %s (must be client, server, or both)\n' "${ENVIRONMENT}" && exit 1 ;;
esac

for jv in ${JAVA_VERSIONS:-}; do
    gvn_list="${gvn_list:+$gvn_list,}\"Java $jv\""
done

relations="${CURSEFORGE_RELATIONS:-[]}"

metadata=$(jq -n \
    --argjson game_version_names "[$gvn_list]" \
    --argjson relations "$relations" \
    --arg release_type "${RELEASE_TYPE:-release}" \
    --arg changelog "${CHANGELOG:-}" \
    --arg changelog_type "${CHANGELOG_TYPE:-text}" \
    '{changelog:$changelog,changelogType:$changelog_type,releaseType:$release_type,gameVersionNames:$game_version_names} +
    if ($relations | length) > 0 then {relations:{projects:$relations}} else {} end')

response=$(curl -s -X POST "https://minecraft.curseforge.com/api/projects/${PROJECT_ID}/upload-file" \
    -H "X-Api-Token: ${CURSEFORGE_LEGACY_API_TOKEN}" \
    -H "User-Agent: victorfaurschou/${MOD_NAME}" \
    -F "metadata=${metadata}" \
    -F "file=@${JAR}")

printf '%s\n' "$response"
printf '%s' "$response" | jq -e '.id' > /dev/null
