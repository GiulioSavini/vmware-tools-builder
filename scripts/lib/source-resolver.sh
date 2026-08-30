#!/usr/bin/env bash
#
# Resolves which open-vm-tools tarball to build, for both the host build
# (build.sh) and the container driver (containers/build-all.sh).
#
# Three modes:
#   (unset)            use versions.lock — pinned, checksummed, reproducible
#   VMTOOLS_VERSION=X  build release X, resolving its real asset URL from the
#                      GitHub API. No checksum unless X happens to be the pin.
#   VMTOOLS_VERSION=latest  resolve the newest release. Explicitly not
#                      reproducible, and says so.
#
# Exports: VMTOOLS_VERSION VMTOOLS_TAG VMTOOLS_TARBALL_URL VMTOOLS_SHA256
#
# The asset URL cannot be constructed from the version. Release assets carry a
# build number — open-vm-tools-13.1.0-25218885.tar.gz — so a URL built as
# open-vm-tools-${VERSION}.tar.gz returns 404. That was the bug that made the
# documented `--version` flag fail every time it was used.

_resolver_api() {
    local tag_path="$1"
    curl -fsSL "https://api.github.com/repos/vmware/open-vm-tools/releases/${tag_path}" 2>/dev/null
}

# Pull the source tarball asset out of a release payload, skipping the
# signature and checksum assets GitHub lists alongside it.
_resolver_asset_url() {
    grep '"browser_download_url"' \
        | sed 's/.*"browser_download_url": "\(.*\)".*/\1/' \
        | grep -E '/open-vm-tools-[0-9].*\.tar\.gz$' \
        | head -1
}

resolve_vmtools_source() {
    local lock_file="$1"
    local requested="${VMTOOLS_VERSION:-}"

    if [ -z "$requested" ]; then
        [ -f "$lock_file" ] || { echo "versions.lock not found at $lock_file" >&2; return 1; }
        # shellcheck disable=SC1090
        . "$lock_file"
        export VMTOOLS_VERSION VMTOOLS_TAG VMTOOLS_TARBALL_URL VMTOOLS_SHA256
        echo "open-vm-tools ${VMTOOLS_VERSION} (pinned in versions.lock, checksum enforced)"
        return 0
    fi

    local json tag
    if [ "$requested" = "latest" ]; then
        json="$(_resolver_api latest)" || { echo "Could not reach the GitHub releases API." >&2; return 1; }
        tag="$(echo "$json" | grep '"tag_name"' | head -1 | sed 's/.*"tag_name": "\(.*\)".*/\1/')"
    else
        tag="stable-${requested}"
        json="$(_resolver_api "tags/${tag}")" || true
        if [ -z "$json" ] || echo "$json" | grep -q '"message": *"Not Found"'; then
            tag="v${requested}"
            json="$(_resolver_api "tags/${tag}")" || true
        fi
        if [ -z "$json" ] || echo "$json" | grep -q '"message": *"Not Found"'; then
            echo "No open-vm-tools release found for version ${requested} (tried stable-${requested} and v${requested})." >&2
            return 1
        fi
    fi

    local url
    url="$(echo "$json" | _resolver_asset_url)"
    [ -n "$url" ] || { echo "Release ${tag} publishes no source tarball asset." >&2; return 1; }

    VMTOOLS_TAG="$tag"
    VMTOOLS_VERSION="$(echo "$tag" | sed 's/^stable-//; s/^v//')"
    VMTOOLS_TARBALL_URL="$url"
    VMTOOLS_SHA256=""

    # If the caller asked for exactly the pinned version, keep the checksum.
    if [ -f "$lock_file" ]; then
        local pinned_version pinned_sha
        pinned_version="$(grep '^VMTOOLS_VERSION=' "$lock_file" | cut -d= -f2)"
        pinned_sha="$(grep '^VMTOOLS_SHA256=' "$lock_file" | cut -d= -f2)"
        if [ "$pinned_version" = "$VMTOOLS_VERSION" ]; then
            VMTOOLS_SHA256="$pinned_sha"
        fi
    fi

    export VMTOOLS_VERSION VMTOOLS_TAG VMTOOLS_TARBALL_URL VMTOOLS_SHA256

    if [ -n "$VMTOOLS_SHA256" ]; then
        echo "open-vm-tools ${VMTOOLS_VERSION} (matches versions.lock, checksum enforced)"
    else
        echo "open-vm-tools ${VMTOOLS_VERSION} (requested explicitly; NOT checksummed, NOT reproducible)"
        echo "  To pin this version: ./scripts/update-pin.sh ${VMTOOLS_VERSION}"
    fi
}

# Verifies a downloaded tarball. Used inside the container, where the checksum
# arrives as an environment variable.
verify_vmtools_tarball() {
    local file="$1" expected="${2:-}"

    if [ -z "$expected" ]; then
        echo "No checksum recorded for this build; skipping verification."
        return 0
    fi

    local actual
    actual="$(sha256sum "$file" | cut -d' ' -f1)"
    if [ "$actual" != "$expected" ]; then
        echo "Checksum mismatch for $file" >&2
        echo "  expected: $expected" >&2
        echo "  actual:   $actual" >&2
        echo "The tarball upstream serves is not the one this repository pinned." >&2
        return 1
    fi
    echo "Checksum verified: $actual"
}
