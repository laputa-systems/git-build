#!/bin/sh
set -eu

# Regression test for the relocatable artifact contract: the packaged prefix
# (bin/, libexec/git-core/, share/git-core/templates/) must work from any
# directory name, both invoked directly and through a symlink elsewhere.
# Usage: sh tests/relocatable-layout.sh <prefix_dir>
# <prefix_dir> is an extracted archive root; callers extract under an
# arbitrary directory name.

if [ "$#" -ne 1 ]; then
    echo "usage: sh tests/relocatable-layout.sh <prefix_dir>" >&2
    exit 1
fi

prefix_dir=$(CDPATH= cd -- "$1" && pwd -P)
bin_dir="$prefix_dir/bin"
exec_dir="$prefix_dir/libexec/git-core"
git="$bin_dir/git"

fail() {
    echo "relocatable: $1" >&2
    exit 1
}

test -x "$git" || fail "$git is missing"
test "$("$git" --version)" = "git version $(sh "$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)/scripts/source-lock.sh" git version)" \
    || fail "$git --version mismatch"

work=$(mktemp -d "${TMPDIR:-/tmp}/git-relocatable.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
export HOME="$work/home"
export XDG_CONFIG_HOME="$work/home/.config"
mkdir -p "$HOME"

check_exec_path() {
    got=$($1 --exec-path)
    want="$prefix_dir/libexec/git-core"
    got_phys=$(CDPATH= cd -- "$got" 2>/dev/null && pwd -P || printf '%s' "$got")
    want_phys=$(CDPATH= cd -- "$want" && pwd -P)
    test "$got_phys" = "$want_phys" || fail "$1 --exec-path is $got, want $want"
}

repo_seq=0
check_templates() {
    repo_seq=$((repo_seq + 1))
    repo="$work/repo-$repo_seq"
    mkdir "$repo"
    (
        cd "$repo"
        "$1" init -q >"$work/init.out" 2>"$work/init.err"
    )
    if grep -q "templates not found" "$work/init.err"; then
        fail "$1 init could not find the packaged templates"
    fi
    test -n "$(find "$repo/.git/hooks" -name '*.sample' | head -n 1)" \
        || fail "$1 init did not populate hooks from the templates"
}

# Direct invocation.
check_exec_path "$git"
check_templates "$git"

# Invocation through a symlink in an unrelated directory.
mkdir "$work/links"
ln -s "$git" "$work/links/git"
check_exec_path "$work/links/git"
check_templates "$work/links/git"

# The exec-path listing powers command resolution and `git help`; it must
# expose the shipped helpers. remote-https cannot appear: this build has no
# curl by product decision, so no remote helper binaries exist.
listing=$("$git" help -a 2>/dev/null || true)
printf '%s\n' "$listing" | grep -qw "submodule" \
    || fail "git help -a does not list the exec-path git-submodule helper"
for helper in git-upload-pack git-receive-pack git-upload-archive git-submodule--helper git-sh-i18n--envsubst; do
    test -e "$exec_dir/$helper" || fail "exec-path listing lacks $helper"
done
if printf '%s\n' "$listing" | grep -q "remote-https"; then
    fail "git help -a lists remote-https, which requires curl"
fi
if [ -e "$exec_dir/git-remote-https" ] || [ -e "$bin_dir/git-remote-https" ]; then
    fail "remote-https must be absent without curl"
fi

printf 'relocatable layout verified for %s\n' "$prefix_dir"
