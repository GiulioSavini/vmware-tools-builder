#!/usr/bin/env bash
#
# build.sh - Pull latest open-vm-tools release, compile, and package (.deb or .rpm)
#
# Usage: sudo bash build.sh
#
set -euo pipefail

BUILD_DIR="/tmp/open-vm-tools-build"
OUTPUT_DIR="${HOME}/ansible"
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
# Detect OS
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
    log "Recupero ultima versione da GitHub..."

    if ! command -v curl &>/dev/null; then
        error "curl non trovato. Installalo prima."
    fi

    RELEASE_JSON=$(curl -sL "https://api.github.com/repos/vmware/open-vm-tools/releases/latest")

    LATEST_TAG=$(echo "$RELEASE_JSON" \
        | grep '"tag_name"' \
        | head -1 \
        | sed 's/.*"tag_name": "\(.*\)".*/\1/')

    if [ -z "$LATEST_TAG" ]; then
        error "Impossibile recuperare l'ultima versione da GitHub"
    fi

    # Get the actual tarball URL from release assets
    TARBALL_URL=$(echo "$RELEASE_JSON" \
        | grep '"browser_download_url"' \
        | grep '\.tar\.gz"' \
        | head -1 \
        | sed 's/.*"browser_download_url": "\(.*\)".*/\1/')

    # Tag format: stable-XX.Y.Z or vXX.Y.Z
    VERSION=$(echo "$LATEST_TAG" | sed 's/^stable-//' | sed 's/^v//')

    log "Ultima versione: $VERSION (tag: $LATEST_TAG)"
    if [ -n "$TARBALL_URL" ]; then
        log "Tarball URL: $TARBALL_URL"
    fi
}

# ------------------------------------------------------------------------------
# Install build dependencies
# ------------------------------------------------------------------------------
install_deps_debian() {
    log "Installazione dipendenze di build (Debian/Ubuntu)..."
    apt-get update -qq
    apt-get install -y --no-install-recommends \
        build-essential \
        automake \
        autoconf \
        libtool \
        pkg-config \
        libglib2.0-dev \
        libpam0g-dev \
        libssl-dev \
        libxml2-dev \
        libxmlsec1-dev \
        libmspack-dev \
        libfuse3-dev \
        libudev-dev \
        libdrm-dev \
        libtirpc-dev \
        rpcsvc-proto \
        curl \
        wget \
        git \
        dpkg-dev \
        fakeroot \
        debhelper
}

install_deps_rhel() {
    log "Installazione dipendenze di build (RHEL/CentOS)..."
    yum install -y epel-release 2>/dev/null || true
    yum groupinstall -y "Development Tools"
    yum install -y \
        automake \
        autoconf \
        libtool \
        glib2-devel \
        pam-devel \
        openssl-devel \
        libxml2-devel \
        xmlsec1-devel \
        libmspack-devel \
        fuse3-devel \
        systemd-devel \
        libudev-devel \
        libdrm-devel \
        libtirpc-devel \
        rpcgen \
        curl \
        wget \
        git \
        rpm-build
}

# ------------------------------------------------------------------------------
# Download and extract source
# ------------------------------------------------------------------------------
download_source() {
    log "Download sorgente open-vm-tools $VERSION..."

    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"

    # Use the asset URL from the release API if available, otherwise fallback
    if [ -z "$TARBALL_URL" ]; then
        TARBALL_URL="https://github.com/vmware/open-vm-tools/releases/download/${LATEST_TAG}/open-vm-tools-${VERSION}.tar.gz"
    fi

    TARBALL_FILE="open-vm-tools-${VERSION}.tar.gz"

    log "URL: $TARBALL_URL"
    curl -fsSL "$TARBALL_URL" -o "$TARBALL_FILE" \
        || error "Download fallito. Verifica la release su GitHub."

    tar xzf "$TARBALL_FILE"

    # Il tarball potrebbe estrarre in open-vm-tools-X.Y.Z o open-vm-tools/open-vm-tools
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

    make -j"$(nproc)"

    log "Compilazione completata."
}

# ------------------------------------------------------------------------------
# Build .deb package
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

    cat > "$INSTALL_ROOT/DEBIAN/control" <<EOF
Package: ${PKG_NAME}
Version: ${VERSION}-1
Section: admin
Priority: optional
Architecture: ${ARCH}
Depends: libglib2.0-0, libpam0g, libssl3 | libssl1.1, libxml2, libfuse3-3 | libfuse2, libtirpc3
Conflicts: open-vm-tools
Replaces: open-vm-tools
Provides: open-vm-tools
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
# Build .rpm package
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
    RPM_BUILDROOT="$BUILD_DIR/pkg-root-rpm"
    mkdir -p "$RPM_TOPDIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

    cat > "$RPM_TOPDIR/SPECS/${PKG_NAME}.spec" <<EOF
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

%files
${PKG_PREFIX}/
/etc/systemd/system/vmtoolsd.service
/etc/ld.so.conf.d/vmware-tools.conf
/etc/vmware-tools/
/etc/pam.d/vmtoolsd
/usr/bin/vm-support
/usr/lib/udev/rules.d/99-vmware-scsi-udev.rules
EOF

    rpmbuild --define "_topdir $RPM_TOPDIR" \
             --buildroot="$RPM_BUILDROOT" \
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
# Uninstall existing VMware Tools
# ------------------------------------------------------------------------------
uninstall_existing() {
    log "Controllo installazione VMware Tools esistente..."

    if [ -x /usr/bin/vmware-uninstall-tools.pl ]; then
        warn "Trovati VMware Tools Perl-based, rimozione..."
        /usr/bin/vmware-uninstall-tools.pl -d 2>/dev/null || true
    fi

    if [ "$OS_FAMILY" = "debian" ]; then
        if dpkg -l | grep -q '^ii.*open-vm-tools '; then
            warn "Trovato open-vm-tools standard, rimozione..."
            apt-get remove -y open-vm-tools open-vm-tools-desktop 2>/dev/null || true
            apt-get autoremove -y 2>/dev/null || true
        fi
    else
        if rpm -q open-vm-tools &>/dev/null; then
            warn "Trovato open-vm-tools standard, rimozione..."
            yum remove -y open-vm-tools open-vm-tools-desktop 2>/dev/null || true
        fi
    fi

    systemctl stop vmtoolsd.service 2>/dev/null || true
    systemctl stop open-vm-tools.service 2>/dev/null || true
    pkill -f vmtoolsd 2>/dev/null || true

    log "Pulizia completata."
}

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------
cleanup() {
    log "Pulizia file temporanei..."
    rm -rf "$BUILD_DIR"
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------
main() {
    echo "============================================="
    echo "  VMware Tools Builder"
    echo "============================================="
    echo ""

    if [ "$(id -u)" -ne 0 ]; then
        error "Eseguire come root: sudo bash $0"
    fi

    detect_os
    get_latest_version

    if [ "$OS_FAMILY" = "debian" ]; then
        install_deps_debian
    else
        install_deps_rhel
    fi

    download_source
    uninstall_existing
    compile

    if [ "$OS_FAMILY" = "debian" ]; then
        build_deb
    else
        build_rpm
    fi

    # --------------------------------------------------------------------------
    # Installa il pacchetto anche sulla macchina locale (proxy/build host)
    # --------------------------------------------------------------------------
    log "Installazione pacchetto sulla macchina locale..."
    uninstall_existing

    if [ "$OS_FAMILY" = "debian" ]; then
        dpkg -i "$OUTPUT_DIR"/${PKG_NAME}_*.deb
    else
        rpm -Uvh --force "$OUTPUT_DIR"/${PKG_NAME}-*.rpm
    fi

    ldconfig
    systemctl daemon-reload
    systemctl enable vmtoolsd.service
    systemctl restart vmtoolsd.service || true

    log "Verifica installazione locale..."
    if "${PKG_PREFIX}/bin/vmtoolsd" --version; then
        log "vmtoolsd installato e funzionante sulla macchina locale!"
    else
        warn "vmtoolsd installato ma verifica versione fallita. Controllare manualmente."
    fi

    cleanup

    echo ""
    log "========================================"
    log "Build e installazione locale completate!"
    log "Pacchetto in: $OUTPUT_DIR/"
    log "========================================"
    log ""
    log "Prossimo passo: cd ansible && ansible-playbook -i inventory.ini deploy-vmtools.yml"
}

main "$@"
