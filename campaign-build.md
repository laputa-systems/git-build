# Campaign: Modernize and distribute minimal Git builds

## Status

Goal: minimal Git 2.56.0 for macOS arm64 + static Linux musl, published as
qualified SHA-tagged ZIP prereleases, installable via `usr/dl`.
Base: `08204cc` (Git 2.56.0, no diff-pretty), branch `master`, tree clean.
Accepted: none yet (preflight). Red: none on the integration branch.
Next: A1. Resume: pick the next open item in **Sequence**, brief per the
orchestrate run-a-slice contract, steer after each accept.
No README.md exists in `git-minimal-musl-static`; AGENTS.md is the doc.

## Charter

- Decide and keep going. Record a decision only when a later slice depends on it.
- Proceed without waiting inside the grant. Park items needing outside authority.
- Hard stops park the item: irreversible/outside-repo action, a doc boundary,
  or a loop with nothing checkable. Pushing is always forbidden.
- Fix egregious breakage met on the way in its own commit (shellcheck findings,
  dead links, trivially broken scripts); park anything estimated over 30 min.
- Parity and completeness before optimization; product-performance budgets are
  logged, not gating, until the final hardening slice.
- One writer by default. Parallel lanes only for the disjoint pairs named in
  **Sequence**, in worktrees at `.work/wt/<lane>`, never `/tmp` or `$TMPDIR`.
- Every commit is a Conventional Commit with the workstream as scope
  (`git-distro:`, `repomod:`, `dl:`); the item ID goes in the body.
  Code comments never cite this doc.

## Decisions

Owner-decided (2026-10-28):
- diff-pretty stays removed (`71e1aa9`). Every draft requirement to preserve,
  rebase, lock, harden, package, qualify, or document it is superseded.
- Static PIE: attempt it; if the musl chain cannot do it, record `readelf`
  evidence and the exact blocker, ship hardened non-PIE static binaries,
  and keep moving. No failing gate left pending.

Prescribed:
- `usr` lives at `~/usr` (not `~/d/usr`). `dl git` follows the `codex`
  precedent (`~/usr/dl:1900-2042`): versioned dir, `DEST` symlinks via
  temp-link + atomic `mv`, `readlink` guard, `own_file`/`own_dir`, `STATE`.
- Assets are `git-<triple>.zip` + build manifest + verified `SHA256SUMS`
  (triples from the matrix in **Reference**).
- Canonical version source is `scripts/download-git-source.sh:4` (`version=`);
  Makefile, Dockerfile, and `test/runtime.sh` must derive from it. The upgrade
  procedure is documented in AGENTS.md, not duplicated across files.
- Default branch is `master`; release tag is exactly `release-${{ github.sha }}`.
- The executor never pushes, dispatches workflows, creates tags/releases, or
  enables the `dl` default set. Publication is the owner's hard stop (see
  **Needs environment**).

Delegated (bound in parentheses):
- Exact CFLAGS/LDFLAGS (keep `-O3`, LTO, section GC/dead-strip; add stack
  protection where supported; never `-march=native` or target-only CPU flags).
- Manifest fields (must include upstream version, archive SHA-256, target,
  build commit, toolchain versions).
- B2 fixture modeling of the C/Makefile layout.
- `dl` install root (must be a managed versioned dir under `~/.local/share`
  with a current-pointer, per draft §8).

## Baseline

- Green: `make macos` builds Git 2.56.0 and `test/runtime.sh` passes
  (verified at preflight). Loop: incremental `make macos` ≈3s; clean build is
  the long pole (minutes — executor times the first clean run).
- Unrun: repomod suite, `dl-test.sh`, `make git`.
- Docker daemon was down at preflight (OrbStack socket refused), so `make git`
  is unproven locally. Executor may start the local daemon; if it stays down,
  Linux-byte proof moves to CI artifacts (see **Needs environment**).

## Sequence

Serial within a workstream (shared files); parallel only across the pairs in
(PAR). Each item ends on its acceptance command on the integrated tree, then
the parent steering checkpoint; red work never lands.

- A1 — Single-source Git version + upgrade procedure. Owns: `Makefile`,
  `Dockerfile`, `scripts/download-git-source.sh`, `test/runtime.sh`,
  `AGENTS.md`. Prereq: none. Accept: `make macos` green and exactly one
  editable version string (`grep -rn` proves derivation). (PAR: B2, D1)
- A2 — Harden Linux build, static-PIE verdict, binary-inspection script. Owns:
  `Dockerfile`, `scripts/qualify-binaries.sh` (new), `test/runtime.sh` hook.
  Prereq: A1. Accept: `sh scripts/qualify-binaries.sh dist/macos` green now;
  `make git` + script green on Linux bytes when docker/CI allows, else parked
  with cause and retry condition. (PAR: B2, D1)
- A3 — Packaging (3 ZIPs + manifest + `SHA256SUMS`), final-bytes runtime
  qualification (relocation, helper layout, HTTPS-failure behavior),
  README.md + AGENTS.md. Owns: `scripts/package.sh` (new), `test/runtime.sh`,
  `AGENTS.md`, `README.md` (new). Prereq: A2. Accept: `make macos`, package,
  `sh test/runtime.sh` green against the extracted ZIP in a disposable dir
  with `GIT_BIN_DIR` pointed at the extract. (PAR: B1, D1)
- B2 — repomod: recognize pure C/Makefile binaries, multi-ELF static-smoke
  rule, catalog entry, regression tests. Owns (in `~/d/repomod`):
  `src/repomod/rules/binary_release.py`, `tests/test_binary_release.py`,
  `tests/fixtures/binary_release/*`, `catalog.toml`. Prereq: none. Accept:
  `uv run --group dev --quiet pytest tests/test_binary_release.py` green.
- B1 — ish-conformant release workflow + local audit script. Owns:
  `.github/workflows/release.yml`, `scripts/audit-release.sh` (new).
  Prereq: B2 (uses its classifier as cross-check). Accept:
  `sh scripts/audit-release.sh` green (asserts all 12 properties in
  **Acceptance**) and repomod reports no binary-release findings on the repo.
- D1 — `dl git` bundle installer + mocked regression tests. Owns (in `~/usr`):
  `dl`, `dotfiles/dl-test.sh`. Prereq: A3 (final layout must exist first).
  Accept: `sh dotfiles/dl-test.sh` green with `HOME` under `.work/`.
- C — Publish prerelease. PARKED behind the owner hard stop; see
  **Needs environment**. D2 (`git` in the default `dl` set) is parked behind C.

## Acceptance

- Git 2.56.0 builds for all three targets: `make macos` + `make git`
  (`DOCKER_PLATFORM` per matrix) green, `test/runtime.sh` green on final bytes.
- Every dependency pinned and verified: single version source; archive
  SHA-256 enforced in `ADD --checksum` and the download script (fail closed).
- Linux ELF: static, correct arch, no `PT_INTERP`/`DT_NEEDED`, non-executable
  stack, no W+X segments, no text relocs, RELRO where applicable, no glibc —
  via `scripts/qualify-binaries.sh` (`readelf`, not `ldd` claims).
- macOS Mach-O: arch, PIE, deployment floor, system-only dylibs, valid
  signature after strip — via the same script (`otool -l`, `codesign -v`).
- Release workflow (all 12, audited locally): 1 manual `workflow_dispatch`
  only; 2 preflight refuses non-default-branch refs; 3 exactly the three
  matrix targets; 4 SHA-pinned actions; 5 limited `permissions`; 6
  upload/download between jobs; 7 inventory rejects missing/duplicate/extra
  assets; 8 consolidated verified `SHA256SUMS`; 9 tag `release-${{ github.sha }}`;
  10 tag created at the triggering commit via the API; 11
  `gh release create --prerelease --verify-tag`; 12 no partial releases.
- repomod: `tests/test_binary_release.py` green; repo passes with no
  warnings or exceptions.
- `dl git`: installs/updates the full bundle (5 commands) from mocks;
  failures preserve the prior install with no partial state; existing suite
  unweakened.

## Needs environment

Not blocking local completion; each with the owner's command:
- Linux bytes if the daemon stays down: `docker info && make git` /
  `make git DOCKER_PLATFORM=linux/amd64`, then
  `sh scripts/qualify-binaries.sh dist`.
- Publish: `gh workflow run release.yml --ref master`, then download the 3
  ZIPs + `SHA256SUMS`, `sha256sum -c SHA256SUMS`, and inspect contents,
  arch, and linkage per platform. Native per-arch proof comes from CI runners.
- D2 unblocks only after the above shows three verified assets.

## Execution boundary and non-goals

Authorized: edits in the three repos, worktrees under `.work/wt/<lane>`,
local builds, mocked tests, starting the local Docker daemon.
Forbidden: push, workflow dispatch, tag/release creation, enabling the `dl`
default set early, HTTPS/cURL dependencies, Nix/Bazel/CMake, bundled TLS
roots, `-march=native`, generated binaries in the repo, `|| true` on gates,
weakening any check to pass. Contract changes for the owner: tarballs become
ZIPs + manifest + `SHA256SUMS`; repomod policy gains Make-C recognition, a
multi-ELF rule, and a catalog entry; `dl` gains a default-set member (after C).
Non-goals: HTTPS remotes (documented unsupported, failure explicitly tested),
glibc/Intel/universal builds, diff-pretty (removed, see Decisions), release
metadata services.

## Reference

- Distro (`/Users/josh/d/git-minimal-musl-static`, `master`): `Makefile:5`
  version, `Dockerfile:40-44` pinned source, `scripts/download-git-source.sh:4`
  canonical version, `test/runtime.sh:9` version check,
  `.github/workflows/release.yml` (99 lines, current tarball flow).
  Matrix: `aarch64-apple-darwin` (macos-26), `x86_64-unknown-linux-musl`
  (linux/amd64), `aarch64-unknown-linux-musl` (linux/arm64).
- Canonical prerelease (`~/d/ish/.github/workflows/release.yml`, 259 lines):
  preflight `:21-42`, matrix `:54-66`, SHA pins `:69-154`,
  static-link gate `:159-191`, inventory + `SHA256SUMS` `:193-227`,
  tag-via-API `:228-254`, create `:259`. Conventions:
  `docs/development.md:29-61`, `docs/rfc/ISH-42-release-delivery.md:18-55`.
- Policy (`~/d/repomod`): `release-policy.toml` (targets only);
  `src/repomod/rules/binary_release.py` (`:168-189` make-gate,
  `:221-241` native-build kinds, `:244-270` ambiguous verdict,
  `:416-477` standard format, `:534-573` ELF smoke, `:568-572` one-per-arch);
  `catalog.toml` (v2, no git entry yet); run `Makefile:3-4` pytest command.
- Installer (`~/usr`): `dl:364-440` single-binary (not for Git),
  `dl:1900-2042` codex bundle pattern, `dl:2416-2426` default set,
  `dotfiles/dl-test.sh` mocked suite. Lock reference: `~/d/python-build`
  (`sources.lock.json`, `build.py`).
