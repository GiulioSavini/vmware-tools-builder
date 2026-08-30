#!/usr/bin/env bash
#
# Moves the pin in versions.lock to a new upstream release.
#
#   ./scripts/update-pin.sh           # newest release
#   ./scripts/update-pin.sh 13.0.5    # a specific one
#
# Downloads the tarball, records its SHA256, and rewrites versions.lock. The
# result is a four-line diff that says exactly what changed and what it hashes
# to — which is the point: bumping the version becomes a reviewable commit
# rather than something that happens silently at build time.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/source-resolver.sh
# shellcheck disable=SC1091  # resolved at run time from the repo root
. "$REPO_ROOT/scripts/lib/source-resolver.sh"

LOCK="$REPO_ROOT/versions.lock"

export VMTOOLS_VERSION="${1:-latest}"
# Resolve against a lock path that does not exist, so the current pin cannot
# short-circuit the lookup and we always hit the API.
resolve_vmtools_source "/nonexistent" >/dev/null || {
    echo "Could not resolve a release for '${1:-latest}'." >&2
    exit 1
}

OLD_VERSION="$(grep '^VMTOOLS_VERSION=' "$LOCK" | cut -d= -f2 || echo none)"
OLD_SHA="$(grep '^VMTOOLS_SHA256=' "$LOCK" | cut -d= -f2 || echo none)"

echo "Current pin: ${OLD_VERSION}"
echo "New release: ${VMTOOLS_VERSION} (${VMTOOLS_TAG})"
echo "Downloading  ${VMTOOLS_TARBALL_URL}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

curl -fsSL "$VMTOOLS_TARBALL_URL" -o "$TMP/source.tar.gz"
NEW_SHA="$(sha256sum "$TMP/source.tar.gz" | cut -d' ' -f1)"
echo "SHA256:      ${NEW_SHA}"

# Sanity: the archive must actually contain an open-vm-tools source tree. A
# release asset that is a signature or a checksum file would otherwise be
# pinned happily and fail at build time.
# `tar tzf | grep -q` would look right and fail always: grep exits at the first
# match, tar takes SIGPIPE, and pipefail turns that into a failed pipeline. Read
# the first entry into a variable instead.
FIRST_ENTRY="$(tar tzf "$TMP/source.tar.gz" 2>/dev/null | head -1 || true)"
case "$FIRST_ENTRY" in
    open-vm-tools-[0-9]*) ;;
    *)
        echo "That asset does not look like an open-vm-tools source tarball" >&2
        echo "(first entry: ${FIRST_ENTRY:-<empty>})." >&2
        exit 1
        ;;
esac

if [ "$OLD_VERSION" = "$VMTOOLS_VERSION" ] && [ "$OLD_SHA" = "$NEW_SHA" ]; then
    echo
    echo "Already pinned to this exact tarball. Nothing to do."
    exit 0
fi

if [ "$OLD_VERSION" = "$VMTOOLS_VERSION" ] && [ "$OLD_SHA" != "$NEW_SHA" ]; then
    echo >&2
    echo "WARNING: version ${VMTOOLS_VERSION} is already pinned but now hashes" >&2
    echo "differently. Upstream replaced the asset under an existing tag." >&2
    echo "Investigate before committing this." >&2
fi

python3 - "$LOCK" "$VMTOOLS_VERSION" "$VMTOOLS_TAG" "$VMTOOLS_TARBALL_URL" "$NEW_SHA" <<'PY'
import re, sys
lock, version, tag, url, sha = sys.argv[1:6]
text = open(lock).read()
for key, value in (("VMTOOLS_VERSION", version), ("VMTOOLS_TAG", tag),
                   ("VMTOOLS_TARBALL_URL", url), ("VMTOOLS_SHA256", sha)):
    text = re.sub(rf'^{key}=.*$', f'{key}={value}', text, flags=re.M)
open(lock, "w").write(text)
PY

echo
echo "versions.lock updated. Review and commit:"
echo "  git diff versions.lock"
