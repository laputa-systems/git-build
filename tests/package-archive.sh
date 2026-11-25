#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$root/scripts/archive.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/git-package-test.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/files/bin" "$work/files/libexec/git-core" "$work/files/share/git-core/templates/hooks"
printf '#!/bin/sh\n' > "$work/files/bin/git"
printf '#!/bin/sh\n' > "$work/files/bin/git-shell"
printf 'library\n' > "$work/files/libexec/git-core/git-sh-setup"
printf 'hook\n' > "$work/files/share/git-core/templates/hooks/pre-commit.sample"
chmod 755 "$work/files/bin/git" "$work/files/bin/git-shell"
chmod 644 "$work/files/libexec/git-core/git-sh-setup" "$work/files/share/git-core/templates/hooks/pre-commit.sample"
ln -s git "$work/files/bin/git-upload-pack"
make_archive "$work/first.tar.xz" "$work/files" bin libexec share
touch "$work/files/bin/git" "$work/files/libexec/git-core/git-sh-setup" "$work/files/share/git-core/templates/hooks/pre-commit.sample"
make_archive "$work/second.tar.xz" "$work/files" bin libexec share
cmp "$work/first.tar.xz" "$work/second.tar.xz"
python3 - "$work/first.tar.xz" <<'PY'
import sys
import tarfile

with tarfile.open(sys.argv[1], 'r:xz') as archive:
    members = archive.getmembers()
    names = [member.name.rstrip('/') for member in members]
    assert len(names) == len(set(names)), names
    assert 'bin' in names and 'libexec' in names and 'share' in names
    assert 'bin/git' in names and 'bin/git-shell' in names
    assert 'libexec/git-core/git-sh-setup' in names
    assert 'share/git-core/templates/hooks/pre-commit.sample' in names
    assert all((member.uid, member.gid, member.mtime) == (0, 0, 0) for member in members)
    by_name = {member.name: member for member in members}
    assert by_name['bin/git'].mode == 0o755
    assert by_name['libexec/git-core/git-sh-setup'].mode == 0o644
    link = by_name['bin/git-upload-pack']
    assert link.issym() and link.linkname == 'git'
print('archive order, metadata, modes, symlink and reproducibility verified')
PY
