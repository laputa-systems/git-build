if command -v sha256sum >/dev/null 2>&1; then
    sha256() { sha256sum "$@"; }
else
    echo "sha256: neither sha256sum nor shasum found" >&2
    exit 1
fi
