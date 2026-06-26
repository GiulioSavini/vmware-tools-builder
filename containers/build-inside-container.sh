#!/usr/bin/env bash
#
# build-inside-container.sh - Runs inside Docker container to compile open-vm-tools
#
# Environment variables (set by Dockerfile or docker run):
#   VMTOOLS_VERSION  - (optional) force a specific version, otherwise latest is fetched
#   OUTPUT_DIR       - (default: /output) where the final .deb/.rpm is placed
#
set -euo pipefail

OUTPUT_DIR="${OUTPUT_DIR:-/output}"
BUILD_DIR="/tmp/open-vm-tools-build"
PKG_NAME="open-vm-tools-custom"
PKG_PREFIX="/usr/local"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ------------------------------------------------------------------------------
# Detect OS family
# ------------------------------------------------------------------------------
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_FAMILY=""
        case "$ID" in
            ubuntu|debian|linuxmint)
                OS_FAMILY="debian"
                ;;
            rhel|centos|rocky|almalinux|ol|fedora)
                OS_FAMILY="rhel"
                ;;
            opensuse*|sles|suse)
                OS_FAMILY="suse"
                ;;
            *)
                error "OS non supportato: $ID"
                ;;
        esac
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
    else
        error "Impossibile rilevare l'OS (/etc/os-release mancante)"
    fi
    log "OS rilevato: $OS_ID $OS_VERSION (famiglia: $OS_FAMILY)"
}

# ------------------------------------------------------------------------------
# Get latest release version from GitHub
# ------------------------------------------------------------------------------
get_latest_version() {
    if [ -n "${VMTOOLS_VERSION:-}" ]; then
        VERSION="$VMTOOLS_VERSION"
        LATEST_TAG="stable-${VERSION}"
        TARBALL_URL=""
        log "Versione forzata: $VERSION"
        return
    fi

    log "Recupero ultima versione da GitHub..."

    RELEASE_JSON=$(curl -sL "https://api.github.com/repos/vmware/open-vm-tools/releases/latest")

    LATEST_TAG=$(echo "$RELEASE_JSON" \
        | grep '"tag_name"' \
        | head -1 \
        | sed 's/.*"tag_name": "\(.*\)".*/\1/')

    if [ -z "$LATEST_TAG" ]; then
        error "Impossibile recuperare l'ultima versione da GitHub"
    fi

    TARBALL_URL=$(echo "$RELEASE_JSON" \
        | grep '"browser_download_url"' \
        | grep '\.tar\.gz"' \
        | head -1 \
        | sed 's/.*"browser_download_url": "\(.*\)".*/\1/')

    VERSION=$(echo "$LATEST_TAG" | sed 's/^stable-//' | sed 's/^v//')

    log "Ultima versione: $VERSION (tag: $LATEST_TAG)"
}

# ------------------------------------------------------------------------------
# Download and extract source
# ------------------------------------------------------------------------------
download_source() {
    log "Download sorgente open-vm-tools $VERSION..."

    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    if [ -z "${TARBALL_URL:-}" ]; then
        TARBALL_URL="https://github.com/vmware/open-vm-tools/releases/download/${LATEST_TAG}/open-vm-tools-${VERSION}.tar.gz"
    fi

    TARBALL_FILE="open-vm-tools-${VERSION}.tar.gz"

    log "URL: $TARBALL_URL"
    curl -fsSL "$TARBALL_URL" -o "$TARBALL_FILE" \
        || error "Download fallito. Verifica la release su GitHub."

    tar xzf "$TARBALL_FILE"

    if [ -d "open-vm-tools-${VERSION}" ]; then
        cd "open-vm-tools-${VERSION}"
    elif [ -d "open-vm-tools" ]; then
        cd "open-vm-tools"
    else
        EXTRACTED=$(find . -maxdepth 1 -type d -name 'open-vm-tools*' | head -1)
        if [ -n "$EXTRACTED" ]; then
            cd "$EXTRACTED"
        else
            error "Directory sorgente non trovata dopo l'estrazione"
        fi
    fi

    SOURCE_DIR="$(pwd)"
    log "Directory sorgente: $SOURCE_DIR"
}

# ------------------------------------------------------------------------------
# Compile
# ------------------------------------------------------------------------------
compile() {
    log "Compilazione open-vm-tools $VERSION..."
    cd "$SOURCE_DIR"

    if [ ! -f configure ]; then
        log "Esecuzione autoreconf..."
        autoreconf -vif
    fi

    ./configure \
        --prefix="$PKG_PREFIX" \
        --sbindir="$PKG_PREFIX/sbin" \
        --sysconfdir=/etc \
        --without-x \
        --without-gtk2 \
        --without-gtk3 \
        --without-gtkmm \
        --without-gtkmm3 \
        --without-kernel-modules \
        --disable-deploypkg \
        --disable-multimon \
        --disable-tests \
        CFLAGS="-O2" \
        CXXFLAGS="-O2"

    # I Makefile generati hanno -Werror hardcoded e su GCC nuovi (es. Fedora 41+
    # con GCC 15) warning come -Wdiscarded-qualifiers diventano error. Passare
    # -Wno-error via CFLAGS non basta: autotools lo mette PRIMA di -Werror del
    # progetto, quindi -Werror vince. Strippiamo -Werror dai Makefile dopo
    # configure: stiamo solo compilando, non sviluppando il progetto.
    find . -name 'Makefile' -print0 | xargs -0 sed -i 's/-Werror//g'

    # Su glib2 >= 2.68 (Fedora 41+, Ubuntu 24+) i symbol g_malloc_n e simili
    # sono nativi: glib_stubs.c che li ridichiara va in collisione con
    # /usr/include/glib-2.0/glib/gmem.h. Lo stubs file serve solo per glib
    # vecchi (<2.68), su glib moderno e' superfluo - lo svuotiamo. Il file vero
    # sta in lib/stubs/ ma e' referenziato da piu' moduli via VPATH/include:
    # svuotiamo TUTTE le copie nel source tree.
    if pkg-config --atleast-version=2.68 glib-2.0 2>/dev/null; then
        log "glib2 >= 2.68 rilevato: svuoto tutti i glib_stubs.c per evitare collisioni"
        find . -name 'glib_stubs.c' -exec sh -c ': > "$1"' _ {} \; -print
    fi

    make -j"$(nproc)"

    log "Compilazione completata."
}

# ------------------------------------------------------------------------------
# Build .deb
# ------------------------------------------------------------------------------
build_deb() {
    log "Creazione pacchetto .deb..."

    INSTALL_ROOT="$BUILD_DIR/pkg-root"
    rm -rf "$INSTALL_ROOT"
    mkdir -p "$INSTALL_ROOT"

    cd "$SOURCE_DIR"
    make DESTDIR="$INSTALL_ROOT" install

    ARCH=$(dpkg --print-architecture)
    mkdir -p "$INSTALL_ROOT/DEBIAN"

    # Note: no 'Provides: open-vm-tools' to avoid conflict with usr-is-merged on Debian 12+
    cat > "$INSTALL_ROOT/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${VERSION}-1
Section: admin
Priority: optional
Architecture: ${ARCH}
Depends: libglib2.0-0t64 | libglib2.0-0, libpam0g, libssl3t64 | libssl3 | libssl1.1, libxml2, libfuse3-3 | libfuse2, libtirpc3t64 | libtirpc3
Conflicts: open-vm-tools
Replaces: open-vm-tools
Maintainer: Infrastructure Team
Description: VMware Tools (open-vm-tools) custom build
 Compiled from source, version ${VERSION}.
 Installs to ${PKG_PREFIX}.
EOF

    mkdir -p "$INSTALL_ROOT/etc/systemd/system"
    cat > "$INSTALL_ROOT/etc/systemd/system/vmtoolsd.service" <<EOF
[Unit]
Description=VMware Tools Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${PKG_PREFIX}/bin/vmtoolsd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    mkdir -p "$INSTALL_ROOT/etc/ld.so.conf.d"
    echo "${PKG_PREFIX}/lib" > "$INSTALL_ROOT/etc/ld.so.conf.d/vmware-tools.conf"

    cat > "$INSTALL_ROOT/DEBIAN/postinst" <<'POSTINST'
#!/bin/bash
set -e
ldconfig
if [ -f /usr/lib/systemd/system/open-vm-tools.service ]; then
    SIZE=$(stat -c%s /usr/lib/systemd/system/open-vm-tools.service 2>/dev/null || echo 0)
    if [ "$SIZE" -lt 10 ]; then
        systemctl mask open-vm-tools.service 2>/dev/null || true
    fi
fi
rm -f /etc/systemd/system/open-vm-tools.service.requires/vgauth.service
systemctl daemon-reload
systemctl enable vmtoolsd.service
systemctl restart vmtoolsd.service || true
POSTINST
    chmod 755 "$INSTALL_ROOT/DEBIAN/postinst"

    cat > "$INSTALL_ROOT/DEBIAN/prerm" <<'PRERM'
#!/bin/bash
set -e
systemctl stop vmtoolsd.service 2>/dev/null || true
systemctl disable vmtoolsd.service 2>/dev/null || true
PRERM
    chmod 755 "$INSTALL_ROOT/DEBIAN/prerm"

    DEB_FILE="${PKG_NAME}_${VERSION}-1_${ARCH}.deb"
    dpkg-deb --build "$INSTALL_ROOT" "$BUILD_DIR/$DEB_FILE"

    mkdir -p "$OUTPUT_DIR"
    cp "$BUILD_DIR/$DEB_FILE" "$OUTPUT_DIR/"

    log "Pacchetto .deb creato: $OUTPUT_DIR/$DEB_FILE"
}

# ------------------------------------------------------------------------------
# Build .rpm
# ------------------------------------------------------------------------------
build_rpm() {
    log "Creazione pacchetto .rpm..."

    RPM_STAGING="$BUILD_DIR/rpm-staging"
    rm -rf "$RPM_STAGING"
    mkdir -p "$RPM_STAGING"

    cd "$SOURCE_DIR"
    make DESTDIR="$RPM_STAGING" install

    mkdir -p "$RPM_STAGING/etc/systemd/system"
    cat > "$RPM_STAGING/etc/systemd/system/vmtoolsd.service" <<EOF
[Unit]
Description=VMware Tools Daemon
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${PKG_PREFIX}/bin/vmtoolsd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    mkdir -p "$RPM_STAGING/etc/ld.so.conf.d"
    echo "${PKG_PREFIX}/lib" > "$RPM_STAGING/etc/ld.so.conf.d/vmware-tools.conf"

    ARCH=$(uname -m)
    RPM_TOPDIR="$BUILD_DIR/rpmbuild"
    mkdir -p "$RPM_TOPDIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

    # Genera la lista %files dinamicamente da cio' che make install ha messo in
    # staging. Hard-codare i path e' fragile: distro diverse installano file in
    # posti diversi (es. Fedora non genera 99-vmware-scsi-udev.rules, Rocky/OL
    # si'; udev rules dir e' /usr/lib su alcuni, /lib su altri). Cosi' il pacco
    # contiene esattamente cio' che e' stato installato.
    # I file .la (libtool archive) non servono a runtime e su Fedora moderno la
    # brp di rpmbuild li rimuove dal buildroot: se restano nel filelist generato
    # da staging la build fallisce con "File not found: ...la". Li togliamo dallo
    # staging cosi' filelist e buildroot restano coerenti su tutte le distro.
    find "$RPM_STAGING" -name '*.la' -type f -delete
    FILELIST="$RPM_TOPDIR/SPECS/${PKG_NAME}.files"
    ( cd "$RPM_STAGING" && find . \( -type f -o -type l \) -printf '/%P\n' ) > "$FILELIST"

    cat > "$RPM_TOPDIR/SPECS/${PKG_NAME}.spec" <<EOF
# Disabilita la brp script che rimuove i .la su Fedora moderno: noi includiamo
# i .la nel filelist e vogliamo comportamento uniforme con EL (Rocky/OL) dove
# i .la restano in buildroot. Su EL il macro non esiste e la def. e' no-op.
%define __brp_la_files %{nil}

Name:           ${PKG_NAME}
Version:        ${VERSION}
Release:        1%{?dist}
Summary:        VMware Tools (open-vm-tools) custom build
License:        LGPLv2+
URL:            https://github.com/vmware/open-vm-tools

AutoReqProv:    no
Conflicts:      open-vm-tools
Provides:       open-vm-tools = %{version}

%description
VMware Tools (open-vm-tools) compiled from source, version %{version}.
Installs to ${PKG_PREFIX}.

%install
cp -a ${RPM_STAGING}/* %{buildroot}/

%post
ldconfig
rm -f /etc/systemd/system/open-vm-tools.service.requires/vgauth.service
systemctl daemon-reload
systemctl enable vmtoolsd.service
systemctl restart vmtoolsd.service || true

%preun
systemctl stop vmtoolsd.service 2>/dev/null || true
systemctl disable vmtoolsd.service 2>/dev/null || true

%postun
ldconfig

%files -f ${FILELIST}
EOF

    # Con --prefix=/usr/local libtool incorpora un RUNPATH /usr/local/lib nei
    # binari. La QA di redhat-rpm-config (check-rpaths) su Fedora la considera
    # "invalida" perche' matcha ld.so.conf, e fa fallire la build. Qui e'
    # legittima (le lib stanno li, ed e' gia' in ld.so.conf.d), quindi
    # accettiamo standard/invalid/empty rpath via QA_RPATHS.
    QA_RPATHS=$(( 0x0001 | 0x0002 | 0x0010 )) \
    rpmbuild --define "_topdir $RPM_TOPDIR" \
             --buildroot="$BUILD_DIR/pkg-root-rpm" \
             -bb "$RPM_TOPDIR/SPECS/${PKG_NAME}.spec"

    RPM_FILE=$(find "$RPM_TOPDIR/RPMS" -name "*.rpm" | head -1)
    if [ -z "$RPM_FILE" ]; then
        error "RPM non trovato dopo la build"
    fi

    mkdir -p "$OUTPUT_DIR"
    cp "$RPM_FILE" "$OUTPUT_DIR/"

    log "Pacchetto .rpm creato: $OUTPUT_DIR/$(basename "$RPM_FILE")"
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
    echo "============================================="
    echo "  VMware Tools Builder (containerized)"
    echo "============================================="
    echo ""

    detect_os
    get_latest_version
    download_source
    compile

    if [ "$OS_FAMILY" = "debian" ]; then
        build_deb
    else
        build_rpm
    fi

    echo ""
    log "========================================"
    log "Build completata!"
    log "Pacchetto in: $OUTPUT_DIR/"
    ls -lh "$OUTPUT_DIR/"
    log "========================================"
}

main "$@"
