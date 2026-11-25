# git-minimal-musl-static

Minimal Git for macOS arm64 and static Linux musl (arm64, amd64), shipped as
a relocatable prefix: `bin/` holds `git`, `git-shell`, `scalar`, and the
`git-receive-pack`/`git-upload-archive`/`git-upload-pack` symlinks to `git`;
`libexec/git-core/` holds the runtime helpers (`git-submodule` plus the
`git-sh-setup`/`git-sh-i18n` shell libs, `git-sh-i18n--envsubst`, `git-shell`,
and the dashed helper symlinks); `share/git-core/templates/` holds the
upstream templates `git init` copies. Git is built with `RUNTIME_PREFIX`, so
the prefix can live under any directory name and every consumer resolves
`--exec-path`, templates, and helpers relative to it.

HTTPS remotes are unsupported and fail with `Unable to find remote helper`.
Perl, Python, gettext, Expat, cURL, Gitweb, and Rust are omitted.

## Install

Get `git-<version>-<target>.tar.xz` and `SHA256SUMS` from the
[prereleases](https://github.com/laputa-systems/git-build/releases), then
check just your asset and install the prefix anywhere:

```sh
grep -F 'git-2.56.0-aarch64-apple-darwin.tar.xz' SHA256SUMS > CHECKSUM
shasum -a 256 -c CHECKSUM
tar -xJf git-2.56.0-aarch64-apple-darwin.tar.xz -C ~/.local/lib/git
export PATH="$HOME/.local/lib/git/bin:$PATH"
```

Targets: `aarch64-apple-darwin`, `aarch64-unknown-linux-musl`,
`x86_64-unknown-linux-musl`. Each archive has a
`git-<version>-<target>.manifest.json` beside it with the schema version,
product, version, target, source revision, `sources.lock.json` digest,
upstream archive digest, dirty flag, and toolchain.
