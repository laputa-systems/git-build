#!/bin/sh
set -eu

# Package one target's binaries as git-<triple>.zip plus a build manifest,
# then refresh and verify <out_dir>/SHA256SUMS over every packaged asset.
# Usage: sh scripts/package.sh <bin_dir> <triple> <out_dir> [toolchain]
# Triples: aarch64-apple-darwin, x86_64-unknown-linux-musl,
#          aarch64-unknown-linux-musl.
# The toolchain argument defaults to the macOS compiler for the darwin triple
# and to the pinned Dockerfile toolchain for the linux triples.

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
canonical="$repo_root/scripts/download-git-source.sh"
qualify="$script_dir/qualify-binaries.sh"
dockerfile="$repo_root/Dockerfile"

command -v zip >/dev/null || { echo "package: zip is required" >&2; exit 1; }
command -v shasum >/dev/null || { echo "package: shasum is required" >&2; exit 1; }
test -f "$qualify" || { echo "package: $qualify is missing" >&2; exit 1; }

sh "$qualify" "$bin_dir" || exit 1

upstream_version=$(sed -n 's/^version=//p' "$canonical")
upstream_sha256=$(sed -n 's/^archive_sha256=//p' "$canonical")
test -n "$upstream_version" || { echo "package: cannot read version" >&2; exit 1; }
test -n "$upstream_sha256" || { echo "package: cannot read archive sha" >&2; exit 1; }

build_commit=$(git -C "$repo_root" rev-parse HEAD)
build_dirty=false
git -C "$repo_root" status --short | grep -q . && build_dirty=true || true

if [ -z "$toolchain" ]; then
    case "$triple" in
        *-apple-darwin)
            cc=$(xcrun --sdk macosx --find clang)
            toolchain=$("$cc" --version | sed -n '1p')
            ;;
        *)
            llvm=$(sed -n 's/^ARG LLVM_VERSION=//p' "$dockerfile")
            pins=$(sed -n 's/^ *\([a-z0-9]*\)=\([0-9][^ ]*\) .*$/\1 \2/p' "$dockerfile" \
                | grep -E "^(binutils|clang22|gcc|lld22|llvm22) " | tr '\n' ';')
            toolchain="llvm $llvm; $pins"
            ;;
    esac
fi
test -n "$toolchain" || { echo "package: cannot determine toolchain" >&2; exit 1; }

mkdir -p "$out_dir"
out_dir=$(CDPATH= cd -- "$out_dir" && pwd -P)
zip_name="git-$triple.zip"
manifest_name="git-$triple.manifest"
rm -f "$out_dir/$zip_name" "$out_dir/$manifest_name"

(cd "$bin_dir" && zip -y -X -q "$out_dir/$zip_name" \
    git git-shell git-upload-archive git-upload-pack git-receive-pack)

cat > "$out_dir/$manifest_name" <<EOF
upstream_version=$upstream_version
upstream_sha256=$upstream_sha256
target=$triple
build_commit=$build_commit
build_dirty=$build_dirty
toolchain=$toolchain
EOF

(cd "$out_dir" && shasum -a 256 git-*.zip git-*.manifest | sort -k 2 > SHA256SUMS.tmp)
mv "$out_dir/SHA256SUMS.tmp" "$out_dir/SHA256SUMS"
(cd "$out_dir" && shasum -a 256 -c SHA256SUMS)

printf 'Packaged %s and %s\n' "$zip_name" "$manifest_name"
