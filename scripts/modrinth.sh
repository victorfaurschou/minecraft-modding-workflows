#!/bin/sh
set -e

for cmd in curl jq; do
    command -v "$cmd" > /dev/null 2>&1 || { printf 'Error: %s is not installed\n' "$cmd"; exit 1; }
done

for var in MODRINTH_TOKEN PROJECT_ID VERSION MINECRAFT_VERSIONS LOADERS ENVIRONMENT JAR MOD_NAME; do
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

gv_list=""
for mc_version in ${MINECRAFT_VERSIONS}; do
    gv_list="${gv_list:+$gv_list,}\"$mc_version\""
done

loaders_list=""
for loader in ${LOADERS}; do
    loaders_list="${loaders_list:+$loaders_list,}\"$loader\""
done

deps="${DEPENDENCIES:-[]}"

data=$(jq -n \
    --arg name "${VERSION_NAME:-$VERSION}" \
    --arg version_number "$VERSION" \
    --arg project_id "$PROJECT_ID" \
    --argjson game_versions "[$gv_list]" \
    --argjson loaders "[$loaders_list]" \
    --argjson dependencies "$deps" \
    --arg version_type "${VERSION_TYPE:-release}" \
    --arg changelog "${CHANGELOG:-}" \
    '{name:$name,version_number:$version_number,project_id:$project_id,file_parts:["jar"],game_versions:$game_versions,loaders:$loaders,version_type:$version_type,status:"listed",dependencies:$dependencies,featured:true} +
    if $changelog != "" then {changelog:$changelog} else {} end')

response=$(curl -s -X POST "https://api.modrinth.com/v2/version" \
    -H "Authorization: ${MODRINTH_TOKEN}" \
    -H "User-Agent: victorfaurschou/${MOD_NAME}" \
    -F "data=${data}" \
    -F "jar=@${JAR}")

printf '%s\n' "$response"
version_id=$(printf '%s' "$response" | jq -e -r '.id')

curl -sf -X PATCH "https://api.modrinth.com/v3/version/${version_id}" \
    -H "Authorization: ${MODRINTH_TOKEN}" \
    -H "User-Agent: victorfaurschou/${MOD_NAME}" \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg e "$ENVIRONMENT" '{environment:$e}')"

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
