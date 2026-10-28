#!/bin/sh
set -eu

usage() {
    echo "usage: sh scripts/qualify-binaries.sh <bin_dir>" >&2
}

if [ "$#" -ne 1 ]; then
    usage
    exit 1
fi

bin_dir=$1
git="$bin_dir/git"
shell="$bin_dir/git-shell"

fail() {
    echo "qualify: $1" >&2
    exit 1
}

note() {
    echo "qualify: $1"
}

test -d "$bin_dir" || fail "$bin_dir is not a directory"
test -f "$git" || fail "$git is missing"
test -f "$shell" || fail "$shell is missing"
test -x "$git" || fail "$git is not executable"
test -x "$shell" || fail "$shell is not executable"
test ! -L "$git" || fail "$git must not be a symlink"
test ! -L "$shell" || fail "git-shell must be a separate executable, not a symlink"

for helper in git-upload-archive git-upload-pack git-receive-pack; do
    test -x "$bin_dir/$helper" || fail "$bin_dir/$helper is missing"
    test -L "$bin_dir/$helper" || fail "$bin_dir/$helper must be a symlink to git"
    target=$(readlink "$bin_dir/$helper")
    test "$target" = "git" || fail "$bin_dir/$helper links to $target, want git"
done

for omitted in git-cvsserver git-lfs git-filter-repo git-remote-http git-remote-https; do
    test ! -e "$bin_dir/$omitted" || fail "$bin_dir/$omitted must be absent"
done

magic=$(od -A n -t x1 -N 4 "$git" | tr -d ' \n')
shell_magic=$(od -A n -t x1 -N 4 "$shell" | tr -d ' \n')
test "$magic" = "$shell_magic" || fail "git and git-shell are different file types"

case "$magic" in
    7f454c46)
        kind=elf
        ;;
    cffaedfe|cafebabe|feedfacf)
        kind=macho
        ;;
    *)
        fail "$git has unrecognized magic $magic"
        ;;
esac

if [ "$kind" = "elf" ]; then
    command -v readelf >/dev/null || fail "readelf is required to qualify Linux binaries"

    host_arch=$(uname -m)
    case "$host_arch" in
        arm64|aarch64) host_arch=arm64 ;;
        x86_64|amd64) host_arch=x86_64 ;;
    esac

    for bin in "$git" "$shell"; do
        name=$(basename "$bin")
        headers=$(readelf -lW "$bin")
        dynamic=$(readelf -dW "$bin" 2>/dev/null || true)
        versions=$(readelf -VW "$bin" 2>/dev/null || true)

        echo "$headers" | grep -q "INTERP" && fail "$bin has PT_INTERP, want static"
        echo "$dynamic" | grep -q "NEEDED" && fail "$bin has DT_NEEDED, want static"
        echo "$dynamic" | grep -q "TEXTREL" && fail "$bin has text relocations"
        echo "$versions" | grep -q "GLIBC" && fail "$bin references glibc"

        machine=$(readelf -h "$bin" | sed -n 's/^ *Machine: *//p')
        etype=$(readelf -h "$bin" | sed -n 's/^ *Type: *//p')
        case "$etype" in
            DYN*) ;;
            *) fail "$bin has ELF type $etype, want DYN (static PIE)" ;;
        esac
        case "$machine" in
            "Advanced Micro Devices X86-64")
                elf_arch=x86_64
                ;;
            AArch64)
                elf_arch=arm64
                ;;
            *)
                fail "$bin has unexpected machine $machine"
                ;;
        esac
        note "$name: ELF $machine $etype, static PIE (no INTERP/NEEDED)"

        stack_flags=$(echo "$headers" | awk '$1 == "GNU_STACK" { print $(NF-1)$NF }')
        case "$stack_flags" in
            *E*) fail "$bin has executable stack ($stack_flags)" ;;
        esac

        echo "$headers" | awk '$1 == "LOAD" { flags=""; for (i = 7; i < NF; i++) flags = flags $i; if (flags ~ /W/ && flags ~ /E/) found=1 } END { exit !found }' \
            && fail "$bin has a W+X LOAD segment"

        echo "$headers" | grep -q "GNU_RELRO" || fail "$bin has no GNU_RELRO"
        note "$name: non-executable stack, no W+X, GNU_RELRO present"
    done
    if [ "$elf_arch" = "$host_arch" ]; then
        "$git" --version >/dev/null || fail "$git --version failed to execute"
        note "git: executes ($("$git" --version))"
    else
        note "git: skipping exec smoke (binary $elf_arch, host $host_arch)"
    fi
else
    command -v otool >/dev/null || fail "otool is required to qualify macOS binaries"
    command -v codesign >/dev/null || fail "codesign is required to qualify macOS binaries"

    for bin in "$git" "$shell"; do
        name=$(basename "$bin")
        mh=$(otool -hv "$bin")
        echo "$mh" | grep -q "ARM64" || fail "$bin is not arm64"
        echo "$mh" | grep -q "PIE" || fail "$bin is not PIE"

        build_version=$(otool -l "$bin" | awk '/LC_BUILD_VERSION/{found=1} found && /minos/{print $2; exit}')
        test -n "$build_version" || fail "$bin has no LC_BUILD_VERSION minos"
        major=${build_version%%.*}
        test "$major" -ge 15 2>/dev/null || fail "$bin minos $build_version is below the 15.0 floor"

        bad_libs=$(otool -L "$bin" | sed '1d' | awk '$1 !~ /^\/(usr\/lib|System\/Library)\// { print $1 }')
        test -z "$bad_libs" || fail "$bin links non-system libraries: $bad_libs"

        codesign -v "$bin" 2>/dev/null || fail "$bin signature is invalid"
        note "$name: Mach-O arm64 PIE, minos $build_version, system-only dylibs, signature valid"
    done

    "$git" --version >/dev/null || fail "$git --version failed to execute"
    note "git: executes ($("$git" --version))"
fi

note "qualified $bin_dir"
