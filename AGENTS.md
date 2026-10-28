# git-minimal-musl-static

Minimal Git for macOS arm64 and static Linux musl. Linux uses Alpine's LLVM 22
toolchain and ships hardened static PIE; macOS uses system Clang and keeps
iconv for filename normalization. Both omit HTTPS/cURL, Expat, gettext, Perl,
Python, Tcl/Tk, Gitweb, and Rust.

```sh
make macos                        # dist/macos/
make git                          # dist/, DOCKER_PLATFORM=linux/arm64|amd64
make lint                         # shell syntax plus release audit
sh scripts/qualify-binaries.sh dist/macos
sh scripts/package.sh dist/macos aarch64-apple-darwin out/
sh test/runtime.sh                # needs GIT_BIN_DIR pointing at binaries
```

Invariants: `version=` in `scripts/download-git-source.sh` is the only
version string — `Makefile`, `Dockerfile`, and `test/runtime.sh` derive from
it. Every target ships the same five files: `git`, `git-shell`, and three
relative helper symlinks to `git`. HTTPS remotes must fail naming the missing
remote helper. SSH-only transport is a product decision: never reintroduce
libcurl or a TLS stack to regain HTTPS.

To upgrade Git, update `version=` and `archive_sha256=` in
`scripts/download-git-source.sh`, run it to refresh `src/`, then verify with
`make macos` and `make git`.

Releases come from `.github/workflows/release.yml` (manual dispatch, three
matrix triples, verified `SHA256SUMS`); `sh scripts/audit-release.sh` checks
the workflow contract. The build manifest format lives in
`scripts/package.sh`.
