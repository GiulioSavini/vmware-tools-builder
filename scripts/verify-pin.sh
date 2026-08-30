#!/usr/bin/env bash
#
# Verifies that the tarball versions.lock points at still exists upstream and
# still hashes to the recorded value.
#
# Run on a schedule, this catches the case a pin exists to catch: upstream
# replacing or re-tagging an asset under a tag that has already shipped. A
# version number alone would not notice; the checksum does.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$REPO_ROOT/versions.lock"

[ -f "$LOCK" ] || { echo "versions.lock not found." >&2; exit 1; }
# shellcheck disable=SC1090,SC1091
. "$LOCK"

for var in VMTOOLS_VERSION VMTOOLS_TAG VMTOOLS_TARBALL_URL VMTOOLS_SHA256; do
    [ -n "${!var:-}" ] || { echo "versions.lock is missing $var." >&2; exit 1; }
done

echo "Pinned: open-vm-tools ${VMTOOLS_VERSION} (${VMTOOLS_TAG})"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if ! curl -fsSL "$VMTOOLS_TARBALL_URL" -o "$TMP/source.tar.gz"; then
    echo >&2
    echo "The pinned tarball is no longer downloadable:" >&2
    echo "  $VMTOOLS_TARBALL_URL" >&2
    echo "Upstream removed or moved the asset. Re-pin with ./scripts/update-pin.sh." >&2
    exit 1
fi

ACTUAL="$(sha256sum "$TMP/source.tar.gz" | cut -d' ' -f1)"

if [ "$ACTUAL" != "$VMTOOLS_SHA256" ]; then
    echo >&2
    echo "CHECKSUM MISMATCH — upstream replaced the asset under an existing tag." >&2
    echo "  expected: $VMTOOLS_SHA256" >&2
    echo "  actual:   $ACTUAL" >&2
    echo >&2
    echo "Do not simply re-pin. Find out why the bytes changed first." >&2
    exit 1
fi

echo "Checksum matches: $ACTUAL"
