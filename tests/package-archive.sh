#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
. "$root/scripts/archive.sh"
work=$(mktemp -d "${TMPDIR:-/tmp}/git-package-test.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir "$work/files"
printf '#!/bin/sh\n' > "$work/files/git"
printf 'library\n' > "$work/files/git-sh-setup"
chmod 755 "$work/files/git"
chmod 644 "$work/files/git-sh-setup"
ln -s git "$work/files/git-upload-pack"
make_archive "$work/first.tar.xz" "$work/files" git-upload-pack git-sh-setup git
touch "$work/files/git" "$work/files/git-sh-setup"
make_archive "$work/second.tar.xz" "$work/files" git git-upload-pack git-sh-setup
cmp "$work/first.tar.xz" "$work/second.tar.xz"
python3 - "$work/first.tar.xz" <<'PY'
import sys
import tarfile

with tarfile.open(sys.argv[1], 'r:xz') as archive:
    members = archive.getmembers()
    assert [member.name for member in members] == ['git', 'git-sh-setup', 'git-upload-pack']
    assert all((member.uid, member.gid, member.mtime) == (0, 0, 0) for member in members)
    assert [member.mode for member in members[:2]] == [0o755, 0o644]
    assert members[2].issym() and members[2].linkname == 'git'
print('archive order, metadata, modes, symlink and reproducibility verified')
PY
