DOCKER_BUILD ?= docker buildx build
DOCKER_BUILD_CACHE_ARGS ?=
DOCKER_PLATFORM ?= linux/arm64

GIT_VERSION ?= $(shell sed -n 's/^version=//p' scripts/download-git-source.sh)
GIT_ARCHIVE_SHA256 ?= $(shell sed -n 's/^archive_sha256=//p' scripts/download-git-source.sh)
GIT_SOURCE_DIR ?= src/git-$(GIT_VERSION)

MACOS_DIST ?= dist/macos
MACOS_CFLAGS ?= -O3 -flto -DNDEBUG -pipe -ffunction-sections -fdata-sections -fstack-protector-strong
MACOS_LDFLAGS ?= -flto -Wl,-dead_strip

.PHONY: git lint macos

lint:
	sh -n scripts/audit-release.sh
	sh -n scripts/download-git-source.sh
	sh -n scripts/package.sh
	sh -n scripts/qualify-binaries.sh
	sh -n test/runtime.sh
	sh scripts/audit-release.sh

git:
	@set -eu; \
		mkdir -p dist; \
		rm -f dist/git dist/git-shell dist/git-upload-archive dist/git-upload-pack dist/git-receive-pack; \
		$(DOCKER_BUILD) $(DOCKER_BUILD_CACHE_ARGS) \
			--platform=$(DOCKER_PLATFORM) \
			--progress=plain \
			--build-arg=GIT_VERSION=$(GIT_VERSION) \
			--build-arg=GIT_ARCHIVE_SHA256=$(GIT_ARCHIVE_SHA256) \
			--target=artifacts \
			--output=type=local,dest=dist \
			.; \
		test -s dist/git; \
		for helper in git-upload-archive git-shell git-upload-pack git-receive-pack; do \
			test -x "dist/$$helper"; \
		done; \
		test ! -e dist/git-cvsserver; \
		test ! -e dist/git-lfs; \
		test ! -e dist/git-filter-repo; \
		echo "Wrote dist/git and dist/git-*"

macos:
	@set -eu; \
		test "$$(uname -s)" = Darwin; \
		test -f "$(GIT_SOURCE_DIR)/Makefile" || { \
			echo "run ./scripts/download-git-source.sh first" >&2; \
			exit 1; \
		}; \
		sdkroot="$$(xcrun --sdk macosx --show-sdk-path)"; \
		cc="$$(xcrun --sdk macosx --find clang)"; \
		ar="$$(xcrun --sdk macosx --find ar)"; \
		ranlib="$$(xcrun --sdk macosx --find ranlib)"; \
		strip="$$(xcrun --sdk macosx --find strip)"; \
		jobs="$$(sysctl -n hw.ncpu)"; \
		$(MAKE) -C "$(GIT_SOURCE_DIR)" -j"$$jobs" \
			CC="$$cc" \
			AR="$$ar" \
			RANLIB="$$ranlib" \
			STRIP="$$strip" \
			CPPFLAGS="-isysroot $$sdkroot" \
			CFLAGS="$(MACOS_CFLAGS)" \
			LDFLAGS="$(MACOS_LDFLAGS) -isysroot $$sdkroot" \
			NO_CURL=YesPlease \
			NO_DARWIN_PORTS=YesPlease \
			NO_EXPAT=YesPlease \
			NO_GETTEXT=YesPlease \
			NO_GITWEB=YesPlease \
			NO_HOMEBREW=YesPlease \
			NO_OPENSSL=YesPlease \
			NO_PERL=YesPlease \
			NO_PYTHON=YesPlease \
			NO_REGEX=NeedsStartEnd \
			NO_RUST=YesPlease \
			NO_TCLTK=YesPlease \
			RUNTIME_PREFIX=YesPlease \
			prefix=/usr \
			bindir=/usr/bin \
			gitexecdir=bin \
			git \
			git-upload-archive \
			git-shell \
			git-upload-pack \
			git-receive-pack; \
		"$$cc" --version | sed -n '1p'; \
		"$(GIT_SOURCE_DIR)/git" --version; \
		"$$strip" -S -x "$(GIT_SOURCE_DIR)/git" "$(GIT_SOURCE_DIR)/git-shell"; \
		rm -rf "$(MACOS_DIST)"; \
		mkdir -p "$(MACOS_DIST)"; \
		cp -a "$(GIT_SOURCE_DIR)/git" "$(GIT_SOURCE_DIR)/git-shell" "$(MACOS_DIST)/"; \
		for helper in git-upload-archive git-upload-pack git-receive-pack; do \
			test -x "$(GIT_SOURCE_DIR)/$$helper"; \
			ln -s git "$(MACOS_DIST)/$$helper"; \
		done; \
			test -x "$(MACOS_DIST)/git"; \
			test -x "$(MACOS_DIST)/git-shell"; \
		expected_exec_path="$$("$(MACOS_DIST)/git" --exec-path)"; \
		GIT_BIN_DIR="$(abspath $(MACOS_DIST))" \
		GIT_EXPECTED_EXEC_PATH="$$expected_exec_path" \
		GIT_EXPECTED_VERSION="$(GIT_VERSION)" \
		GIT_QUALIFY_SCRIPT="$(abspath scripts/qualify-binaries.sh)" \
			sh test/runtime.sh; \
		echo "Wrote $(MACOS_DIST)/git and $(MACOS_DIST)/git-*"
