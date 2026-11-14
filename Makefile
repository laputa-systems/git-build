DOCKER_BUILD ?= docker buildx build
DOCKER_BUILD_CACHE_ARGS ?=

HOST_OS := $(shell uname -s)
HOST_ARCH := $(shell uname -m)
ifeq ($(HOST_OS),Darwin)
HOST_TARGET := aarch64-apple-darwin
else ifeq ($(HOST_ARCH),x86_64)
HOST_TARGET := x86_64-unknown-linux-musl
else
HOST_TARGET := aarch64-unknown-linux-musl
endif
TARGET ?= $(HOST_TARGET)

ifeq ($(TARGET),x86_64-unknown-linux-musl)
DOCKER_PLATFORM ?= linux/amd64
else
DOCKER_PLATFORM ?= linux/arm64
endif

OUT_DIR ?= out
BIN_DIR ?= dist/$(TARGET)

GIT_VERSION ?= $(shell sh scripts/source-lock.sh git version)
GIT_ARCHIVE_URL ?= $(shell sh scripts/source-lock.sh git url)
GIT_ARCHIVE_SHA256 ?= $(shell sh scripts/source-lock.sh git sha256)
ZLIB_VERSION ?= $(shell sh scripts/source-lock.sh zlib version)
ZLIB_ARCHIVE_URL ?= $(shell sh scripts/source-lock.sh zlib url)
ZLIB_ARCHIVE_SHA256 ?= $(shell sh scripts/source-lock.sh zlib sha256)
GIT_SOURCE_DIR ?= src/git-$(GIT_VERSION)

MACOS_CFLAGS ?= -O3 -flto -DNDEBUG -pipe -ffunction-sections -fdata-sections -fstack-protector-strong
MACOS_LDFLAGS ?= -flto -Wl,-dead_strip

.PHONY: build verify lint clean fetch package compile build-linux build-macos

lint:
	sh -n scripts/archive.sh
	sh -n scripts/audit-release.sh
	sh -n scripts/download-git-source.sh
	sh -n scripts/package.sh
	sh -n scripts/qualify-binaries.sh
	sh -n scripts/sha256.sh
	sh -n scripts/source-lock.sh
	sh -n scripts/verify-archive.sh
	sh -n test/runtime.sh
	sh scripts/source-lock.sh check
	sh scripts/audit-release.sh

fetch:
	sh scripts/download-git-source.sh

build:
	$(MAKE) compile TARGET=$(TARGET)
	$(MAKE) package TARGET=$(TARGET)

compile:
	@case "$(TARGET)" in \
		aarch64-apple-darwin) $(MAKE) fetch build-macos TARGET=$(TARGET) ;; \
		x86_64-unknown-linux-musl|aarch64-unknown-linux-musl) $(MAKE) build-linux TARGET=$(TARGET) ;; \
		*) echo "unsupported TARGET '$(TARGET)'" >&2; exit 1 ;; \
	esac

package:
	sh scripts/package.sh "$(BIN_DIR)" "$(TARGET)" "$(OUT_DIR)"

verify:
	sh scripts/verify-archive.sh "$(OUT_DIR)" "$(TARGET)"

clean:
	rm -rf dist out src

build-linux:
	@set -eu; \
		rm -rf "$(BIN_DIR)"; \
		mkdir -p "$(BIN_DIR)"; \
		$(DOCKER_BUILD) $(DOCKER_BUILD_CACHE_ARGS) \
			--platform=$(DOCKER_PLATFORM) \
			--progress=plain \
			--build-arg=GIT_VERSION=$(GIT_VERSION) \
			--build-arg=GIT_ARCHIVE_URL=$(GIT_ARCHIVE_URL) \
			--build-arg=GIT_ARCHIVE_SHA256=$(GIT_ARCHIVE_SHA256) \
			--build-arg=ZLIB_VERSION=$(ZLIB_VERSION) \
			--build-arg=ZLIB_ARCHIVE_URL=$(ZLIB_ARCHIVE_URL) \
			--build-arg=ZLIB_ARCHIVE_SHA256=$(ZLIB_ARCHIVE_SHA256) \
			--target=artifacts \
			--output=type=local,dest=$(BIN_DIR) \
			.; \
		test -s "$(BIN_DIR)/git"; \
		for helper in git-upload-archive git-shell git-upload-pack git-receive-pack; do \
			test -x "$(BIN_DIR)/$$helper"; \
		done; \
		test -x "$(BIN_DIR)/git-submodule"; \
		test -x "$(BIN_DIR)/git-submodule--helper"; \
		test -s "$(BIN_DIR)/git-sh-setup"; \
		test -s "$(BIN_DIR)/git-sh-i18n"; \
		test -x "$(BIN_DIR)/git-sh-i18n--envsubst"; \
		test -s "$(BIN_DIR)/linker-trace"; \
		test ! -e "$(BIN_DIR)/git-cvsserver"; \
		test ! -e "$(BIN_DIR)/git-lfs"; \
		test ! -e "$(BIN_DIR)/git-filter-repo"; \
		mkdir -p "$(OUT_DIR)"; \
		cp "$(BIN_DIR)/linker-trace" "$(OUT_DIR)/linker-trace-$(TARGET)"; \
		echo "Wrote $(BIN_DIR)/git and $(BIN_DIR)/git-*"

build-macos:
	@set -eu; \
		test "$$(uname -s)" = Darwin; \
		test -f "$(GIT_SOURCE_DIR)/Makefile" || { \
			echo "run make fetch first" >&2; \
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
			git-receive-pack \
			git-submodule \
			git-submodule--helper \
			git-sh-setup \
			git-sh-i18n \
			git-sh-i18n--envsubst; \
		"$$cc" --version | sed -n '1p'; \
		"$(GIT_SOURCE_DIR)/git" --version; \
		"$$strip" -S -x "$(GIT_SOURCE_DIR)/git" "$(GIT_SOURCE_DIR)/git-shell" "$(GIT_SOURCE_DIR)/git-sh-i18n--envsubst"; \
		rm -rf "$(BIN_DIR)"; \
		mkdir -p "$(BIN_DIR)"; \
		cp -a "$(GIT_SOURCE_DIR)/git" "$(GIT_SOURCE_DIR)/git-shell" "$(GIT_SOURCE_DIR)/git-submodule" "$(GIT_SOURCE_DIR)/git-sh-setup" "$(GIT_SOURCE_DIR)/git-sh-i18n" "$(GIT_SOURCE_DIR)/git-sh-i18n--envsubst" "$(BIN_DIR)/"; \
		chmod 644 "$(BIN_DIR)/git-sh-setup" "$(BIN_DIR)/git-sh-i18n"; \
		for helper in git-upload-archive git-upload-pack git-receive-pack git-submodule--helper; do \
			test -x "$(GIT_SOURCE_DIR)/$$helper"; \
			ln -s git "$(BIN_DIR)/$$helper"; \
		done; \
			test -x "$(BIN_DIR)/git"; \
			test -x "$(BIN_DIR)/git-shell"; \
		expected_exec_path="$$("$(BIN_DIR)/git" --exec-path)"; \
		GIT_BIN_DIR="$(abspath $(BIN_DIR))" \
		GIT_EXPECTED_EXEC_PATH="$$expected_exec_path" \
		GIT_EXPECTED_VERSION="$(GIT_VERSION)" \
		GIT_QUALIFY_SCRIPT="$(abspath scripts/qualify-binaries.sh)" \
			sh test/runtime.sh; \
		echo "Wrote $(BIN_DIR)/git and $(BIN_DIR)/git-*"
