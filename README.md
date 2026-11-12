# git-minimal-musl-static

Minimal Git for macOS arm64 and static Linux musl (arm64, amd64), shipped as
one `bin` directory holding `git`, `git-shell`, `git-sh-i18n--envsubst`,
the submodule script and shell libs (`git-submodule`, `git-sh-setup`,
`git-sh-i18n`), and four helper symlinks (`git-upload-archive`,
`git-upload-pack`, `git-receive-pack`, `git-submodule--helper`) pointing at
`git`.

HTTPS remotes are unsupported and fail with `Unable to find remote helper`.
Perl, Python, gettext, Expat, cURL, Gitweb, and Rust are omitted.

## Install

Get `git-<version>-<target>.tar.xz` and `SHA256SUMS` from the
[prereleases](https://github.com/laputa-systems/git-build/releases), then
check just your asset and install it:

```sh
grep -F 'git-2.56.0-aarch64-apple-darwin.tar.xz' SHA256SUMS > CHECKSUM
shasum -a 256 -c CHECKSUM
tar -xJf git-2.56.0-aarch64-apple-darwin.tar.xz -C ~/.local/bin
```

Targets: `aarch64-apple-darwin`, `aarch64-unknown-linux-musl`,
`x86_64-unknown-linux-musl`. Each archive has a
`git-<version>-<target>.manifest.json` beside it with the schema version,
product, version, target, source revision, `sources.lock.json` digest,
upstream archive digest, dirty flag, and toolchain.
