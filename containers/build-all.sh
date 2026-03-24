#!/usr/bin/env bash
#
# build-all.sh - Build open-vm-tools packages for all supported distros using Docker
#
# Usage:
#   ./build-all.sh                    # build all distros, latest version
#   ./build-all.sh --version 12.5.0   # build all distros, specific version
#   ./build-all.sh --target rocky9    # build only rocky9
#   ./build-all.sh --list             # list available targets
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${REPO_ROOT}/output"
VERSION=""
TARGET=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()   { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
header(){ echo -e "${CYAN}$*${NC}"; }

# All available build targets
TARGETS=(
    "ubuntu2204"
    "debian12"
    "rocky9"
    "rocky8"
    "fedora"
)

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --version VERSION   Build a specific version (default: latest from GitHub)"
    echo "  --target TARGET     Build only for a specific target (default: all)"
    echo "  --output DIR        Output directory (default: ./output)"
    echo "  --list              List available build targets"
    echo "  --no-cache          Build Docker images without cache"
    echo "  -h, --help          Show this help"
    echo ""
    echo "Available targets: ${TARGETS[*]}"
}

# Parse arguments
NO_CACHE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="$2"
            shift 2
            ;;
        --target)
            TARGET="$2"
            shift 2
            ;;
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --list)
            echo "Available build targets:"
            for t in "${TARGETS[@]}"; do
                echo "  - $t (Dockerfile.$t)"
            done
            exit 0
            ;;
        --no-cache)
            NO_CACHE="--no-cache"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Opzione sconosciuta: $1"
            ;;
    esac
done

# Check Docker is available
if ! command -v docker &>/dev/null; then
    error "Docker non trovato. Installare Docker per procedere."
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Determine which targets to build
if [ -n "$TARGET" ]; then
    # Validate target
    FOUND=0
    for t in "${TARGETS[@]}"; do
        if [ "$t" = "$TARGET" ]; then
            FOUND=1
            break
        fi
    done
    if [ "$FOUND" -eq 0 ]; then
        error "Target '$TARGET' non valido. Targets disponibili: ${TARGETS[*]}"
    fi
    BUILD_TARGETS=("$TARGET")
else
    BUILD_TARGETS=("${TARGETS[@]}")
fi

# Build summary
header "============================================="
header "  VMware Tools Builder - Multi-Distro"
header "============================================="
echo ""
log "Versione: ${VERSION:-latest (auto-detect)}"
log "Targets: ${BUILD_TARGETS[*]}"
log "Output: $OUTPUT_DIR"
echo ""

FAILED=()
SUCCEEDED=()

for target in "${BUILD_TARGETS[@]}"; do
    DOCKERFILE="$SCRIPT_DIR/Dockerfile.$target"

    if [ ! -f "$DOCKERFILE" ]; then
        warn "Dockerfile non trovato: $DOCKERFILE - skip"
        FAILED+=("$target (no Dockerfile)")
        continue
    fi

    header "---------------------------------------------"
    header "  Building: $target"
    header "---------------------------------------------"

    IMAGE_NAME="vmtools-builder:$target"

    # Build Docker image
    log "Build immagine Docker: $IMAGE_NAME ..."
    if ! docker build $NO_CACHE -t "$IMAGE_NAME" -f "$DOCKERFILE" "$SCRIPT_DIR"; then
        warn "Build immagine fallita per $target"
        FAILED+=("$target (docker build)")
        continue
    fi

    # Run container to produce the package
    DOCKER_ENV=""
    if [ -n "$VERSION" ]; then
        DOCKER_ENV="-e VMTOOLS_VERSION=$VERSION"
    fi

    log "Compilazione in corso dentro container $target ..."
    if ! docker run --rm \
        $DOCKER_ENV \
        -v "$OUTPUT_DIR:/output" \
        "$IMAGE_NAME"; then
        warn "Compilazione fallita per $target"
        FAILED+=("$target (compile)")
        continue
    fi

    log "Target $target completato!"
    SUCCEEDED+=("$target")
    echo ""
done

# Summary
echo ""
header "============================================="
header "  RIEPILOGO BUILD"
header "============================================="
echo ""

if [ ${#SUCCEEDED[@]} -gt 0 ]; then
    log "Completati con successo: ${SUCCEEDED[*]}"
fi

if [ ${#FAILED[@]} -gt 0 ]; then
    warn "Falliti: ${FAILED[*]}"
fi

echo ""
log "Pacchetti generati:"
ls -lh "$OUTPUT_DIR/"*.{deb,rpm} 2>/dev/null || warn "Nessun pacchetto trovato in $OUTPUT_DIR"
echo ""

# Copy packages to role files directory if it exists
ROLE_FILES_DIR="$REPO_ROOT/roles/vmware_tools/files"
if [ -d "$ROLE_FILES_DIR" ]; then
    log "Copia pacchetti in $ROLE_FILES_DIR per il ruolo Ansible..."
    cp -v "$OUTPUT_DIR"/*.deb "$ROLE_FILES_DIR/" 2>/dev/null || true
    cp -v "$OUTPUT_DIR"/*.rpm "$ROLE_FILES_DIR/" 2>/dev/null || true
    log "Pacchetti copiati nel ruolo Ansible."
fi

if [ ${#FAILED[@]} -gt 0 ]; then
    exit 1
fi

log "Tutte le build completate con successo!"
