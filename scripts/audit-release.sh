#!/bin/sh
set -eu

# Local audit for .github/workflows/release.yml: asserts the 12 release
# properties the prerelease workflow must hold. Fails closed on the first
# missing property.
# Usage: sh scripts/audit-release.sh

workflow=".github/workflows/release.yml"
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
file="$repo_root/$workflow"

test -f "$file" || { echo "audit: $workflow is missing" >&2; exit 1; }

pass=0
check() {
    pass=$((pass + 1))
    printf 'ok %d - %s\n' "$pass" "$1"
}

grep -q "workflow_dispatch:" "$file" || { echo "audit 1: no workflow_dispatch trigger" >&2; exit 1; }
if grep -Eq "^[[:space:]]*(push|pull_request|schedule)[[:space:]]*:" "$file"; then
    echo "audit 1: workflow has triggers beyond manual workflow_dispatch" >&2
    exit 1
fi
check "1 manual workflow_dispatch only"

grep -q "default_branch" "$file" || { echo "audit 2: no default-branch guard" >&2; exit 1; }
grep -q "refs/heads/" "$file" || { echo "audit 2: no refs/heads/ ref check" >&2; exit 1; }
check "2 preflight refuses non-default-branch refs"

triples=$(grep -c "triple: " "$file")
test "$triples" -eq 3 || { echo "audit 3: want 3 matrix triples, found $triples" >&2; exit 1; }
for triple in aarch64-apple-darwin x86_64-unknown-linux-musl aarch64-unknown-linux-musl; do
    grep -q "$triple" "$file" || { echo "audit 3: triple $triple is missing" >&2; exit 1; }
done
check "3 exactly the three matrix targets"

uses=$(grep -E "uses:[[:space:]]*[^[:space:]]+@" "$file" | sed 's/^ *//')
test -n "$uses" || { echo "audit 4: no pinned actions found" >&2; exit 1; }
echo "$uses" | while IFS= read -r line; do
    case "$line" in
        *@[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]*)
            ;;
        *)
            echo "audit 4: action is not SHA-pinned: $line" >&2
            exit 1
            ;;
    esac
done
if grep -E "uses:[[:space:]]*[^[:space:]]+@v[0-9]" "$file"; then
    echo "audit 4: movable action tag in use" >&2
    exit 1
fi
check "4 SHA-pinned actions"

grep -q "^permissions: {}" "$file" || { echo "audit 5: top-level permissions are not empty" >&2; exit 1; }
job_permissions=$(grep -c "^    permissions:" "$file")
test "$job_permissions" -ge 3 || { echo "audit 5: want per-job permissions, found $job_permissions" >&2; exit 1; }
check "5 limited permissions"

grep -q "actions/upload-artifact@" "$file" || { echo "audit 6: no upload-artifact step" >&2; exit 1; }
grep -q "actions/download-artifact@" "$file" || { echo "audit 6: no download-artifact step" >&2; exit 1; }
check "6 upload/download between jobs"

grep -q "Inventory release assets" "$file" || { echo "audit 7: no inventory step" >&2; exit 1; }
grep -q "missing, duplicate, or extra" "$file" || { echo "audit 7: inventory rejects nothing" >&2; exit 1; }
check "7 inventory rejects missing/duplicate/extra assets"

grep -q "SHA256SUMS" "$file" || { echo "audit 8: no SHA256SUMS step" >&2; exit 1; }
grep -Eq "(sha256sum|shasum).*-c" "$file" || { echo "audit 8: SHA256SUMS is never verified" >&2; exit 1; }
check "8 consolidated verified SHA256SUMS"

grep -q 'release-${{ github.sha }}' "$file" || { echo "audit 9: release tag is missing" >&2; exit 1; }
check "9 tag release-\${{ github.sha }}"

grep -q "git/refs" "$file" || { echo "audit 10: no tag-via-API step" >&2; exit 1; }
grep -q 'sha=$GITHUB_SHA' "$file" || { echo "audit 10: tag is not pinned to the triggering commit" >&2; exit 1; }
check "10 tag created at the triggering commit via the API"

grep -q "gh release create" "$file" || { echo "audit 11: no gh release create step" >&2; exit 1; }
grep -q -- "--prerelease" "$file" || { echo "audit 11: release is not a prerelease" >&2; exit 1; }
grep -q -- "--verify-tag" "$file" || { echo "audit 11: release does not pass --verify-tag" >&2; exit 1; }
check "11 gh release create --prerelease --verify-tag"

grep -q "needs: \[preflight, build\]" "$file" || { echo "audit 12: release does not gate on preflight and build" >&2; exit 1; }
grep -q "fail-fast: false" "$file" || { echo "audit 12: matrix bails early" >&2; exit 1; }
inventory_line=$(grep -n "Inventory release assets" "$file" | cut -d: -f1)
create_line=$(grep -n "gh release create" "$file" | cut -d: -f1)
test "$inventory_line" -lt "$create_line" || { echo "audit 12: inventory runs after publication" >&2; exit 1; }
check "12 no partial releases"

echo "audited $workflow: 12/12 properties hold"
