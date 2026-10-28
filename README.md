# git-minimal-musl-static

Minimal Git builds for macOS arm64 and static Linux musl (arm64 + amd64):
five files that live together in one `bin` directory.

```
git  git-shell  git-upload-archive -> git  git-upload-pack -> git  git-receive-pack -> git
```

Built-in commands and native transports such as SSH work. HTTPS remotes are
unsupported: any `https://` remote fails with `Unable to find remote helper`.
Perl, Python, gettext, Expat, cURL, Gitweb, and Rust are omitted.

## Install

Download `git-<triple>.zip` and its `SHA256SUMS` from a prerelease, then:

```sh
sha256sum -c SHA256SUMS
unzip git-aarch64-apple-darwin.zip -d ~/.local/bin
```

Triples: `aarch64-apple-darwin`, `aarch64-unknown-linux-musl`,
`x86_64-unknown-linux-musl`.

## Build

```sh
make macos                      # dist/macos/
make git                        # dist/ (linux, via Docker)
make git DOCKER_PLATFORM=linux/amd64
sh scripts/qualify-binaries.sh dist/macos
sh scripts/package.sh dist/macos aarch64-apple-darwin out/
```

Upgrading the Git version is documented in `AGENTS.md`.
