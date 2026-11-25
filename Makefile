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

.PHONY: build verify test lint clean fetch package compile build-linux build-macos

test:
	sh tests/package-archive.sh

lint:
	sh -n tests/package-archive.sh
	sh -n tests/relocatable-layout.sh
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
	@for artifact in ./dist ./out; do \
	  if test -L "$$artifact" || { test -e "$$artifact" && ! test -d "$$artifact"; }; then \
	    printf '%s\n' "make clean: $$artifact must be a local build directory" >&2; exit 1; \
	  fi; \
	done
	rm -rf -- ./dist ./out

build-linux:
	@set -eu; \
		rm -rf "$(BIN_DIR)"; \
		mkdir -p "$(BIN_DIR)"; \
		$(DOCKER_BUILD) $(DOCKER_BUILD_CACHE_ARGS) \
			--build-context=git-patches=./patches \
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
		for program in git git-shell scalar; do \
			test -x "$(BIN_DIR)/bin/$$program"; \
		done; \
		for helper in git-upload-pack git-receive-pack git-upload-archive; do \
			test -L "$(BIN_DIR)/bin/$$helper"; \
			test "$$(readlink "$(BIN_DIR)/bin/$$helper")" = git; \
		done; \
		for program in git-shell git-sh-i18n--envsubst; do \
			test -x "$(BIN_DIR)/libexec/git-core/$$program"; \
		done; \
		for lib in git-submodule git-sh-setup git-sh-i18n; do \
			case "$$lib" in \
				git-submodule) test -x "$(BIN_DIR)/libexec/git-core/$$lib" ;; \
				*) test -s "$(BIN_DIR)/libexec/git-core/$$lib" ;; \
			esac; \
		done; \
		for helper in git-upload-pack git-receive-pack git-upload-archive git-submodule--helper; do \
			test -L "$(BIN_DIR)/libexec/git-core/$$helper"; \
			test "$$(readlink "$(BIN_DIR)/libexec/git-core/$$helper")" = git; \
		done; \
		for program in git scalar; do \
			test -L "$(BIN_DIR)/libexec/git-core/$$program"; \
			test "$$(readlink "$(BIN_DIR)/libexec/git-core/$$program")" = ../../bin/$$program; \
		done; \
		for template in hooks info/exclude description; do \
			test -e "$(BIN_DIR)/share/git-core/templates/$$template"; \
		done; \
		for forbidden in git-cvsserver git-lfs git-filter-repo git-remote-http git-remote-https; do \
			test ! -e "$(BIN_DIR)/bin/$$forbidden"; \
			test ! -e "$(BIN_DIR)/libexec/git-core/$$forbidden"; \
		done; \
		test -s "$(BIN_DIR)/linker-trace"; \
		mkdir -p "$(OUT_DIR)"; \
		cp "$(BIN_DIR)/linker-trace" "$(OUT_DIR)/linker-trace-$(TARGET)"; \
		echo "Wrote $(BIN_DIR)/{bin,libexec/git-core,share/git-core/templates}"

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
			git \
			git-shell \
			scalar \
			git-submodule \
			git-sh-setup \
			git-sh-i18n \
			git-sh-i18n--envsubst; \
		"$$cc" --version | sed -n '1p'; \
		"$(GIT_SOURCE_DIR)/git" --version; \
		"$$strip" -S -x "$(GIT_SOURCE_DIR)/git" "$(GIT_SOURCE_DIR)/git-shell" "$(GIT_SOURCE_DIR)/scalar" "$(GIT_SOURCE_DIR)/git-sh-i18n--envsubst"; \
		rm -rf "$(BIN_DIR)"; \
		mkdir -p "$(BIN_DIR)/bin" "$(BIN_DIR)/libexec/git-core" "$(BIN_DIR)/share/git-core"; \
		src="$(GIT_SOURCE_DIR)"; \
		for program in git git-shell scalar; do \
			test -x "$$src/$$program"; \
			cp -p "$$src/$$program" "$(BIN_DIR)/bin/$$program"; \
		done; \
		for helper in git-receive-pack git-upload-archive git-upload-pack; do \
			ln -s git "$(BIN_DIR)/bin/$$helper"; \
		done; \
		for program in git-shell git-sh-i18n--envsubst; do \
			test -x "$$src/$$program"; \
			cp -p "$$src/$$program" "$(BIN_DIR)/libexec/git-core/$$program"; \
		done; \
		test -x "$$src/git-submodule"; \
		cp -p "$$src/git-submodule" "$(BIN_DIR)/libexec/git-core/git-submodule"; \
		for lib in git-sh-setup git-sh-i18n; do \
			test -s "$$src/$$lib"; \
			cp -p "$$src/$$lib" "$(BIN_DIR)/libexec/git-core/$$lib"; \
		done; \
		chmod 644 "$(BIN_DIR)/libexec/git-core/git-sh-setup" "$(BIN_DIR)/libexec/git-core/git-sh-i18n"; \
		for helper in git-upload-pack git-receive-pack git-upload-archive git-submodule--helper; do \
			ln -s git "$(BIN_DIR)/libexec/git-core/$$helper"; \
		done; \
		ln -s ../../bin/git "$(BIN_DIR)/libexec/git-core/git"; \
		ln -s ../../bin/scalar "$(BIN_DIR)/libexec/git-core/scalar"; \
		$(MAKE) -C "$$src/templates" all >/dev/null; \
		mkdir -p "$(BIN_DIR)/share/git-core/templates"; \
		(cd "$$src/templates/blt" && tar cf - .) | \
			(cd "$(BIN_DIR)/share/git-core/templates" && tar xf -); \
		rm -rf "$$src/templates/blt" "$$src/templates/boilerplates.made"; \
			test -x "$(BIN_DIR)/bin/git"; \
			test -x "$(BIN_DIR)/bin/git-shell"; \
			expected_exec_path="$$(cd "$(BIN_DIR)" && pwd -P)/libexec/git-core"; \
		GIT_BIN_DIR="$$(cd "$(BIN_DIR)/bin" && pwd -P)" \
		GIT_EXPECTED_EXEC_PATH="$$expected_exec_path" \
		GIT_EXPECTED_VERSION="$(GIT_VERSION)" \
		GIT_QUALIFY_SCRIPT="$(abspath scripts/qualify-binaries.sh)" \
			sh test/runtime.sh; \
		echo "Wrote $(BIN_DIR)/bin, $(BIN_DIR)/libexec/git-core, $(BIN_DIR)/share/git-core/templates"
