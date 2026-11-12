#!/bin/sh
set -eu

# Package one target's binaries as git-<version>-<triple>.tar.xz plus a
# git-<version>-<triple>.manifest.json, then refresh and verify
# <out_dir>/SHA256SUMS over every packaged asset.
# Usage: sh scripts/package.sh <bin_dir> <triple> <out_dir> [toolchain]
# Triples: aarch64-apple-darwin, x86_64-unknown-linux-musl,
#          aarch64-unknown-linux-musl.
# The toolchain argument defaults to the macOS compiler for the darwin triple
# and to the pinned builder image in the Dockerfile for the linux triples.

if [ "$#" -lt 3 ] || [ "$#" -gt 4 ]; then
    echo "usage: sh scripts/package.sh <bin_dir> <triple> <out_dir> [toolchain]" >&2
    exit 1
fi

bin_dir=$1
triple=$2
out_dir=$3
toolchain=${4:-}

case "$triple" in
    aarch64-apple-darwin|x86_64-unknown-linux-musl|aarch64-unknown-linux-musl) ;;
    *) echo "package: unknown triple $triple" >&2; exit 1 ;;
esac

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd -P)
qualify="$script_dir/qualify-binaries.sh"
dockerfile="$repo_root/Dockerfile"
lock="$repo_root/sources.lock.json"

. "$script_dir/sha256.sh"
command -v tar >/dev/null || { echo "package: tar is required" >&2; exit 1; }
command -v jaq >/dev/null || { echo "package: jaq is required" >&2; exit 1; }
test -f "$qualify" || { echo "package: $qualify is missing" >&2; exit 1; }

sh "$qualify" "$bin_dir" || exit 1

version=$(sh "$script_dir/source-lock.sh" git version)
upstream_sha256=$(sh "$script_dir/source-lock.sh" git sha256)
sources_lock_sha256=$(sha256 "$lock" | awk '{ print $1 }')

source_revision=$(git -C "$repo_root" rev-parse HEAD)
build_dirty=false
git -C "$repo_root" status --short | grep -q . && build_dirty=true || true

if [ -z "$toolchain" ]; then
    case "$triple" in
        *-apple-darwin)
            cc=$(xcrun --sdk macosx --find clang)
            toolchain=$("$cc" --version | sed -n '1p')
            ;;
        *)
            toolchain=$(sed -n 's/^FROM \(ghcr\.io\/[^ ]*\) AS build$/\1/p' "$dockerfile")
            ;;
    esac
fi
test -n "$toolchain" || { echo "package: cannot determine toolchain" >&2; exit 1; }

mkdir -p "$out_dir"
out_dir=$(CDPATH= cd -- "$out_dir" && pwd -P)
archive_name="git-$version-$triple.tar.xz"
manifest_name="git-$version-$triple.manifest.json"
rm -f "$out_dir/$archive_name" "$out_dir/$manifest_name"

COPYFILE_DISABLE=1 tar -C "$bin_dir" -cJf "$out_dir/$archive_name" \
    git git-shell git-upload-archive git-upload-pack git-receive-pack \
    git-submodule git-submodule--helper git-sh-setup git-sh-i18n git-sh-i18n--envsubst

jaq -n \
    --arg version "$version" \
    --arg target "$triple" \
    --arg source_revision "$source_revision" \
    --arg sources_lock_sha256 "$sources_lock_sha256" \
    --arg upstream_sha256 "$upstream_sha256" \
    --argjson build_dirty "$build_dirty" \
    --arg toolchain "$toolchain" \
    '{
        schema_version: 1,
        product: "git",
        version: $version,
        target: $target,
        source_revision: $source_revision,
        sources_lock_sha256: $sources_lock_sha256,
        upstream_sha256: $upstream_sha256,
        build_dirty: $build_dirty,
        toolchain: $toolchain
    }' > "$out_dir/$manifest_name"

(cd "$out_dir" && sha256 git-*.tar.xz git-*.manifest.json | LC_ALL=C sort -k 2 > SHA256SUMS.tmp)
mv "$out_dir/SHA256SUMS.tmp" "$out_dir/SHA256SUMS"
(cd "$out_dir" && sha256 -c SHA256SUMS)

printf 'Packaged %s and %s\n' "$archive_name" "$manifest_name"
