# git-minimal-musl-static

Minimal Git for macOS arm64 and static Linux musl (arm64, amd64), shipped as
one `bin` directory holding `git`, `git-shell`, and three helper symlinks
(`git-upload-archive`, `git-upload-pack`, `git-receive-pack`) pointing at `git`.

HTTPS remotes are unsupported and fail with `Unable to find remote helper`.
Perl, Python, gettext, Expat, cURL, Gitweb, and Rust are omitted.

## Install

Get `git-<triple>.zip` and `SHA256SUMS` from the
[prereleases](https://github.com/laputa-systems/git-build/releases), then:

```sh
shasum -a 256 -c SHA256SUMS
unzip git-aarch64-apple-darwin.zip -d ~/.local/bin
```

Triples: `aarch64-apple-darwin`, `aarch64-unknown-linux-musl`,
`x86_64-unknown-linux-musl`.
