#!/bin/sh
make_archive() (
    archive=$1
    dir=$2
    shift 2
    members=$(printf '%s\n' "$@" | LC_ALL=C sort)
    stage=$(mktemp -d "${TMPDIR:-/tmp}/git-archive.XXXXXX")
    trap 'rm -rf "$stage"' EXIT HUP INT TERM
    for member in $members; do
        cp -a "$dir/$member" "$stage/$member"
    done
    TZ=UTC find "$stage" -exec touch -h -t 197001010000 {} +
    if [ "$(uname -s)" = Darwin ]; then
        COPYFILE_DISABLE=1 tar --uid 0 --gid 0 --uname '' --gname '' --format ustar --no-xattrs --no-acls --no-fflags -cJf "$archive" -C "$stage" $members
    else
        tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cJf "$archive" -C "$stage" $members
    fi
)
