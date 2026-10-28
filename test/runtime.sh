#!/bin/sh
set -eu

bin_dir=${GIT_BIN_DIR:-/usr/local/bin}
git="$bin_dir/git"
if [ -n "${GIT_EXPECTED_VERSION:-}" ]; then
    expected_version=$GIT_EXPECTED_VERSION
else
    script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)
    expected_version=$(sed -n 's/^version=//p' "$script_dir/../scripts/download-git-source.sh")
fi

test -x "$git"
test -n "$expected_version"
test "$("$git" --version)" = "git version $expected_version"

exec_path=$("$git" --exec-path)
if [ -n "${GIT_EXPECTED_EXEC_PATH:-}" ]; then
    test "$exec_path" = "$GIT_EXPECTED_EXEC_PATH"
else
    case "$exec_path" in
        /*) ;;
        *) echo "exec-path $exec_path is not absolute" >&2; exit 1 ;;
    esac
    case "$exec_path" in
        "$bin_dir"/*) echo "exec-path $exec_path tracks $bin_dir, want relocatable" >&2; exit 1 ;;
    esac
fi

check_linkage() {
    case "$(uname -s)" in
        Linux)
            test -z "$(ldd "$1" 2>&1 | grep -F '=>' || true)"
            ;;
        Darwin)
            test -z "$(otool -L "$1" | sed '1d' | awk '$1 !~ /^\/(usr\/lib|System\/Library)\// { print $1 }')"
            ;;
        *)
            echo "unsupported runtime: $(uname -s)" >&2
            exit 1
            ;;
    esac
}

check_linkage "$git"
check_linkage "$bin_dir/git-shell"

test -x "$bin_dir/git-shell"
test ! -L "$bin_dir/git-shell"
for helper in git-upload-archive git-upload-pack git-receive-pack; do
    test -x "$bin_dir/$helper"
    test -L "$bin_dir/$helper"
done

test ! -e "$bin_dir/git-cvsserver"
test ! -e "$bin_dir/git-lfs"
test ! -e "$bin_dir/git-filter-repo"
test ! -e "$bin_dir/git-remote-http"
test ! -e "$bin_dir/git-remote-https"

if [ -n "${GIT_QUALIFY_SCRIPT:-}" ]; then
    sh "$GIT_QUALIFY_SCRIPT" "$bin_dir"
fi

test_home=$(mktemp -d)
trap 'rm -rf "$test_home"' EXIT HUP INT TERM
export HOME="$test_home"
export XDG_CONFIG_HOME="$test_home/.config"
export PATH="$bin_dir:$PATH"
mkdir -p "$XDG_CONFIG_HOME/git"
: > "$XDG_CONFIG_HOME/git/config"

if GIT_TERMINAL_PROMPT=0 git ls-remote https://127.0.0.1/no-such-repo.git 2>"$test_home/https.err"; then
    echo "https remote unexpectedly succeeded without curl support" >&2
    exit 1
fi
grep -q "remote helper" "$test_home/https.err" || {
    echo "https failure does not name the missing remote helper" >&2
    exit 1
}

git config --global user.name "Joshua Li"
git config --global user.email joshuarli98@gmail.com
test "$(git config --global --get user.name)" = "Joshua Li"
test "$(git config --global --get user.email)" = joshuarli98@gmail.com
test -f "$XDG_CONFIG_HOME/git/config"

repo="$test_home/repo"
mkdir "$repo"
repo=$(cd "$repo" && pwd -P)
cd "$repo"
git init -q --template=
printf '%s\n' hello > hello.txt
git add hello.txt
GIT_AUTHOR_NAME=Joshua \
GIT_AUTHOR_EMAIL=joshua@example.com \
GIT_COMMITTER_NAME=Joshua \
GIT_COMMITTER_EMAIL=joshua@example.com \
    git commit -qm initial

branch=$(git branch --show-current)
test -n "$branch"
git rev-parse --is-inside-work-tree
test "$(git rev-parse --show-toplevel)" = "$repo"
git show-ref --verify --quiet "refs/heads/$branch"
git branch --merged "$branch"
test -z "$(git remote)"
git fsck --no-dangling --no-progress
git pack-refs --all
git rerere gc
git worktree prune
git reflog expire --expire=90.days --expire-unreachable=90.days --all
git gc --quiet
git repack -d --geometric=2 --no-write-bitmap-index --quiet
git prune
git commit-graph write --reachable --changed-paths
git multi-pack-index write --bitmap
test -z "$(git status --short)"

upstream="$test_home/upstream.git"
git init --bare -q --template= "$upstream"
git clone -q --template= "$upstream" "$test_home/clone-a"
cd "$test_home/clone-a"
git checkout -qb work
printf '%s\n' one > file.txt
git add file.txt
GIT_AUTHOR_NAME=Joshua \
GIT_AUTHOR_EMAIL=joshua@example.com \
GIT_COMMITTER_NAME=Joshua \
GIT_COMMITTER_EMAIL=joshua@example.com \
    git commit -qm one
git push -q origin work
git --git-dir="$upstream" symbolic-ref -q HEAD refs/heads/work
git clone -q --template= "$upstream" "$test_home/clone-b"
cd "$test_home/clone-b"
git checkout -q -B work origin/work
printf '%s\n' two >> file.txt
git add file.txt
GIT_AUTHOR_NAME=Joshua \
GIT_AUTHOR_EMAIL=joshua@example.com \
GIT_COMMITTER_NAME=Joshua \
GIT_COMMITTER_EMAIL=joshua@example.com \
    git commit -qm two
git push -q origin work
cd "$test_home/clone-a"
printf '%s\n' three > side.txt
git add side.txt
GIT_AUTHOR_NAME=Joshua \
GIT_AUTHOR_EMAIL=joshua@example.com \
GIT_COMMITTER_NAME=Joshua \
GIT_COMMITTER_EMAIL=joshua@example.com \
    git commit -qm three
git fetch -q origin
git rebase -q origin/work
test "$(cat file.txt)" = "$(printf 'one\ntwo')"
test "$(cat side.txt)" = three
git push -q origin work
printf '%s\n' five >> side.txt
git add side.txt
GIT_AUTHOR_NAME=Joshua \
GIT_AUTHOR_EMAIL=joshua@example.com \
GIT_COMMITTER_NAME=Joshua \
GIT_COMMITTER_EMAIL=joshua@example.com \
    git commit -qm five
cd "$test_home/clone-b"
printf '%s\n' four >> file.txt
git add file.txt
GIT_AUTHOR_NAME=Joshua \
GIT_AUTHOR_EMAIL=joshua@example.com \
GIT_COMMITTER_NAME=Joshua \
GIT_COMMITTER_EMAIL=joshua@example.com \
    git commit -qm four
git fetch -q origin
git rebase -q origin/work
git push -q origin work
cd "$test_home/clone-a"
git fetch -q origin
git merge -q -m merge-upstream origin/work
test "$(git rev-list --merges --count HEAD)" = 1
test "$(cat file.txt)" = "$(printf 'one\ntwo\nfour')"
test "$(cat side.txt)" = "$(printf 'three\nfive')"
git push -q origin work
test -z "$(git status --short)"
cd "$repo"
test -z "$(git status --short)"
