#!/bin/sh
set -e

for cmd in curl jq; do
    command -v "$cmd" > /dev/null 2>&1 || { printf 'Error: %s is not installed\n' "$cmd"; exit 1; }
done

for var in CURSEFORGE_API_TOKEN CURSEFORGE_LEGACY_API_TOKEN PROJECT_ID VERSION MINECRAFT_VERSION JAR MOD_NAME; do
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

prefix=$(printf '%s' "$MINECRAFT_VERSION" | cut -d. -f1,2)
type_id=$(printf '%s' "$versions" | jq --arg mc "$MINECRAFT_VERSION" --arg p "$prefix" \
    'first(.[] | select(.name == $mc or .name == $p or (.name | startswith($p + "."))) | .gameVersionTypeID)')
[ -z "$type_id" ] && printf 'Error: Could not find CurseForge version type for Minecraft %s\n' "$MINECRAFT_VERSION" && exit 1
mc_ids=$(printf '%s' "$versions" | jq -r --arg p "$prefix" --argjson type_id "$type_id" \
    '[.[] | select(.gameVersionTypeID == $type_id) | select(.name == $p or (.name | startswith($p + "."))) | .id] | join(",")')
[ -z "$mc_ids" ] && printf 'Error: Could not find CurseForge version IDs for Minecraft %s\n' "$MINECRAFT_VERSION" && exit 1
fabric_id=$(printf '%s' "$versions" | jq '.[] | select(.slug == "fabric") | .id')
[ -z "$fabric_id" ] && printf 'Error: Could not find Fabric version ID on CurseForge\n' && exit 1

relations="${CURSEFORGE_RELATIONS:-[]}"

metadata=$(jq -n \
    --argjson mc_ids "[$mc_ids]" \
    --argjson fabric_id "$fabric_id" \
    --argjson relations "$relations" \
    '{changelog:"See GitHub release notes.",changelogType:"text",releaseType:"release",gameVersions:($mc_ids + [$fabric_id]),relations:{projects:$relations}}')

response=$(curl -sf -X POST "https://minecraft.curseforge.com/api/projects/${PROJECT_ID}/upload-file" \
    -H "X-Api-Token: ${CURSEFORGE_LEGACY_API_TOKEN}" \
    -H "User-Agent: victorfaurschou/${MOD_NAME}" \
    -F "metadata=${metadata}" \
    -F "file=@${JAR}")

printf '%s\n' "$response"
printf '%s' "$response" | jq -e '.id' > /dev/null
