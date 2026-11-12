#!/bin/sh
set -eu

# Read sources.lock.json.
# Usage: sh scripts/source-lock.sh <input> <field>
#        sh scripts/source-lock.sh check

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
lock=${SOURCES_LOCK:-$script_dir/../sources.lock.json}

fail() {
    echo "source-lock: $1" >&2
    exit 1
}

command -v jaq >/dev/null || fail "jaq is required"
test -f "$lock" || fail "$lock is missing"

if [ "$#" -eq 1 ] && [ "$1" = check ]; then
    jaq -e '
        .schema_version == 1
        and (.inputs | type == "array" and length > 0)
        and ([.inputs[].name] | length == (unique | length))
        and all(.inputs[];
            (.name | type == "string" and length > 0)
            and (.version | type == "string" and length > 0)
            and (.sha256 | type == "string" and test("^[0-9a-f]{64}$"))
            and ((.url | type == "string") or (.urls | type == "array" and length > 0)))
    ' "$lock" >/dev/null || fail "$lock is not a valid schema_version 1 sources lock"
    exit 0
fi

if [ "$#" -ne 2 ]; then
    echo "usage: sh scripts/source-lock.sh <input> <field> | check" >&2
    exit 1
fi

value=$(jaq -r --arg name "$1" --arg field "$2" \
    '[.inputs[] | select(.name == $name) | .[$field] | select(. != null)] | first // empty' "$lock")
test -n "$value" || fail "no $2 for input $1"
printf '%s\n' "$value"
