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
command -v tar >/dev/null || { echo "verify: tar is required" >&2; exit 1; }

fail() {
    echo "verify: $1" >&2
    exit 1
}

version=$(sh "$script_dir/source-lock.sh" git version)
archive="$out_dir/git-$version-$triple.tar.xz"
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

members=$(tar -tJf "$archive")
top=$(printf '%s\n' "$members" | cut -d/ -f1 | LC_ALL=C sort -u)
expected_top=$(printf '%s\n' bin libexec share)
test "$top" = "$expected_top" || fail "$archive has unexpected top-level entries: $top"

for required in \
    bin/git bin/git-shell bin/scalar \
    bin/git-upload-pack bin/git-receive-pack bin/git-upload-archive \
    libexec/git-core/git-shell libexec/git-core/git-sh-i18n--envsubst \
    libexec/git-core/git-submodule libexec/git-core/git-sh-setup libexec/git-core/git-sh-i18n \
    libexec/git-core/git-upload-pack libexec/git-core/git-receive-pack \
    libexec/git-core/git-upload-archive libexec/git-core/git-submodule--helper \
    share/git-core/templates/hooks share/git-core/templates/info/exclude \
    share/git-core/templates/description; do
    printf '%s\n' "$members" | grep -Fx -e "$required" -e "$required/" >/dev/null \
        || fail "$archive is missing $required"
done
for forbidden in git-cvsserver git-lfs git-filter-repo git-remote-http git-remote-https; do
    if printf '%s\n' "$members" | grep -F "$forbidden" >/dev/null; then
        fail "$archive contains forbidden $forbidden"
    fi
done

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/git-verify.XXXXXX")
trap 'rm -rf "$work_dir"' EXIT HUP INT TERM
tar -xJf "$archive" -C "$work_dir"
work_dir=$(CDPATH= cd -- "$work_dir" && pwd -P)

GIT_BIN_DIR="$work_dir/bin" \
GIT_EXPECTED_VERSION="$version" \
GIT_EXPECTED_EXEC_PATH="$work_dir/libexec/git-core" \
GIT_QUALIFY_SCRIPT="$script_dir/qualify-binaries.sh" \
    sh "$script_dir/../test/runtime.sh"

sh "$repo_root/tests/relocatable-layout.sh" "$work_dir"

printf 'Verified %s\n' "$archive"
