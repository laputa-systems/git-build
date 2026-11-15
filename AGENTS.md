# git-minimal-musl-static

Minimal Git for macOS arm64 and static Linux musl. Linux builds in the shared musl-toolchain image
(clang, musl and zlib built without GCC) and ships hardened static PIE; macOS uses system Clang and keeps
iconv for filename normalization. Both omit HTTPS/cURL, Expat, gettext, Perl,
Python, Tcl/Tk, Gitweb, and Rust.

```sh
make build TARGET=aarch64-apple-darwin   # fetch, compile, and package into out/
make build TARGET=x86_64-unknown-linux-musl   # or aarch64-unknown-linux-musl; needs Docker
make verify TARGET=...            # checksums, manifest, archive contents, runtime test
make fetch                        # download and verify the trimmed Git source into src/
make package TARGET=...           # archive and manifest from an existing dist/<target>
make lint                         # shell syntax, sources.lock.json, release audit
make clean
sh scripts/qualify-binaries.sh dist/aarch64-apple-darwin
sh test/runtime.sh                # needs GIT_BIN_DIR pointing at binaries
```

Invariants: `sources.lock.json` is the only place the Git and zlib versions,
URLs, and digests are written; `scripts/source-lock.sh` reads it with `jaq` for
`Makefile`, `Dockerfile` build arguments, `scripts/*`, and `test/runtime.sh`. Every target ships the same ten files: `git`, `git-shell`,
`git-sh-i18n--envsubst`, the `git-submodule` script plus
`git-sh-setup`/`git-sh-i18n` shell libs, and four relative helper symlinks
to `git` (three pack transport helpers plus `git-submodule--helper`). HTTPS
remotes must fail naming the missing remote helper. SSH-only transport is a
product decision: never reintroduce libcurl or a TLS stack to regain HTTPS.

To upgrade Git, update its entry in `sources.lock.json`, then verify with
`make build TARGET=aarch64-apple-darwin` and a Linux target.

`test/runtime.sh` also exercises bare-remote clone/push/fetch/merge/rebase
and submodule add/update/status; `make verify` reruns it against each
extracted archive.

Releases come from `.github/workflows/release.yml` (manual dispatch, three
matrix targets, `git-<version>-<target>.tar.xz` and `.manifest.json` assets,
verified `SHA256SUMS`); `sh scripts/audit-release.sh` checks the workflow
contract. The manifest format lives in `scripts/package.sh`. The Linux
`Dockerfile` builds from the shared musl-toolchain image and emits
`linker-trace`, which the release job passes to the static ELF check.
