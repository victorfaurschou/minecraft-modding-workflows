#!/bin/sh
set -e

for cmd in curl jq; do
    command -v "$cmd" > /dev/null 2>&1 || { printf 'Error: %s is not installed\n' "$cmd"; exit 1; }
done

for var in MODRINTH_TOKEN PROJECT_ID VERSION MINECRAFT_VERSION JAR MOD_NAME; do
    val=$(printenv "$var")
    [ -z "$val" ] && printf 'Error: %s is not set\n' "$var" && exit 1
done

existing=$(curl -sf "https://api.modrinth.com/v2/project/${PROJECT_ID}/version" \
    -H "Authorization: ${MODRINTH_TOKEN}" \
    -H "User-Agent: victorfaurschou/${MOD_NAME}")

if printf '%s' "$existing" | jq -e --arg v "$VERSION" 'any(.[]; .version_number == $v)' > /dev/null; then
    printf 'Version %s already exists on Modrinth, skipping.\n' "$VERSION"
    exit 0
fi

prefix=$(printf '%s' "$MINECRAFT_VERSION" | cut -d. -f1,2)
game_versions=$(curl -sf "https://api.modrinth.com/v2/tag/game_version" \
    -H "User-Agent: victorfaurschou/${MOD_NAME}" | \
    jq --arg p "$prefix" '[.[] | select(.version_type == "release") | select(.version == $p or (.version | startswith($p + "."))) | .version]')

deps="${DEPENDENCIES:-[]}"

data=$(jq -n \
    --arg name "$VERSION" \
    --arg version_number "$VERSION" \
    --arg project_id "$PROJECT_ID" \
    --argjson game_versions "$game_versions" \
    --argjson dependencies "$deps" \
    '{name:$name,version_number:$version_number,project_id:$project_id,file_parts:["jar"],game_versions:$game_versions,loaders:["fabric"],version_type:"release",status:"listed",dependencies:$dependencies,featured:true}')

response=$(curl -s -X POST "https://api.modrinth.com/v2/version" \
    -H "Authorization: ${MODRINTH_TOKEN}" \
    -H "User-Agent: victorfaurschou/${MOD_NAME}" \
    -F "data=${data}" \
    -F "jar=@${JAR}")

printf '%s\n' "$response"
version_id=$(printf '%s' "$response" | jq -e -r '.id')

if [ -n "${ENVIRONMENT:-}" ]; then
    curl -sf -X PATCH "https://api.modrinth.com/v3/version/${version_id}" \
        -H "Authorization: ${MODRINTH_TOKEN}" \
        -H "User-Agent: victorfaurschou/${MOD_NAME}" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg e "$ENVIRONMENT" '{environment:$e}')"
fi

current=$(curl -sf "https://api.modrinth.com/v2/project/${PROJECT_ID}" \
    -H "Authorization: ${MODRINTH_TOKEN}" \
    -H "User-Agent: victorfaurschou/${MOD_NAME}")

readme=$(cat README.md)
summary=$(printf '%s' "$readme" | tail -n +3 | sed '/^$/q' | head -n -1 | tr '\n' ' ' | sed 's/\*\*//g; s/__//g; s/\*//g; s/_//g; s/  */ /g; s/^ //; s/ $//')

current_description=$(printf '%s' "$current" | jq -r '.description')
current_body=$(printf '%s' "$current" | jq -r '.body')

if [ "$current_description" != "$summary" ] || [ "$current_body" != "$readme" ]; then
    curl -sf -X PATCH "https://api.modrinth.com/v2/project/${PROJECT_ID}" \
        -H "Authorization: ${MODRINTH_TOKEN}" \
        -H "User-Agent: victorfaurschou/${MOD_NAME}" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg description "$summary" --arg body "$readme" '{description:$description,body:$body}')"
fi
