#!/bin/sh
set -eu

# Verify one target's packaged release assets: checksums, manifest, archive
# contents, then qualification and the runtime test on the extracted tree.
# Usage: sh scripts/verify-archive.sh <out_dir> <triple>

if [ "$#" -ne 2 ]; then
    echo "usage: sh scripts/verify-archive.sh <out_dir> <triple>" >&2
    exit 1
fi

out_dir=$1
triple=$2

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P)

. "$script_dir/sha256.sh"
command -v jaq >/dev/null || { echo "verify: jaq is required" >&2; exit 1; }
command -v unzip >/dev/null || { echo "verify: unzip is required" >&2; exit 1; }

fail() {
    echo "verify: $1" >&2
    exit 1
}

version=$(sh "$script_dir/source-lock.sh" git version)
archive="$out_dir/git-$version-$triple.zip"
manifest="$out_dir/git-$version-$triple.manifest.json"
test -f "$archive" || fail "$archive is missing"
test -f "$manifest" || fail "$manifest is missing"

(cd "$out_dir" && sha256 -c SHA256SUMS >/dev/null) || fail "SHA256SUMS does not match the assets"

lock_sha256=$(sha256 "$repo_root/sources.lock.json" | awk '{ print $1 }')
jaq -e \
    --arg version "$version" \
    --arg target "$triple" \
    --arg lock "$lock_sha256" \
    '.schema_version == 1
        and .product == "git"
        and .version == $version
        and .target == $target
        and (.source_revision | test("^[0-9a-f]{40}$"))
        and .sources_lock_sha256 == $lock' "$manifest" >/dev/null \
    || fail "$manifest does not match the build inputs"

expected=$(printf '%s\n' git git-receive-pack git-sh-i18n git-sh-i18n--envsubst git-sh-setup \
    git-shell git-submodule git-submodule--helper git-upload-archive git-upload-pack)
actual=$(unzip -Z1 "$archive" | LC_ALL=C sort)
test "$actual" = "$expected" || fail "$archive has unexpected contents: $actual"

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/git-verify.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
unzip -q "$archive" -d "$work_dir"

GIT_BIN_DIR="$work_dir" \
GIT_EXPECTED_VERSION="$version" \
GIT_QUALIFY_SCRIPT="$script_dir/qualify-binaries.sh" \
    sh "$script_dir/../test/runtime.sh"

printf 'Verified %s\n' "$archive"
