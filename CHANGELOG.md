# Changelog

All notable changes to this role are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- Ubuntu 26.04 LTS (Resolute Raccoon) support: `containers/Dockerfile.ubuntu2604` build target, `ubuntu2604` added to `build-all.sh`, and `resolute` listed in Galaxy platforms (the Ansible role already resolves the `ubuntu2604` package subdir dynamically from `ansible_distribution_version`)
- CI now builds each per-distro Docker image and compiles open-vm-tools inside it (matrix `build-container` job), so "does it compile in Docker" is verified on every push/PR and the resulting package is uploaded as an artifact

### Fixed
- `build.sh` (host build): self-heal a broken `install-info`/`update-info-dir` dpkg state that blocks apt on Ubuntu 26.04; tolerate *unrelated* broken packages (e.g. apache2 dual-MPM, py3clean hook failures) as long as the build dependencies themselves are installed; install the produced package with `apt-get install ./pkg.deb` so runtime deps (`libxml2`, `libfuse3-3`, …) are resolved instead of failing under `dpkg -i`; local install is now best-effort (the package is the deliverable and is always saved to the output dir)
- `build.sh` `.deb` runtime `Depends` now use the t64 library names (`libglib2.0-0t64`, `libssl3t64`, `libtirpc3t64`) with non-t64 fallbacks, matching the container build (Ubuntu 24.04+/Debian 13+)
- RHEL build deps: enable EPEL from Fedora mirror when `epel-release` isn't in the distro repos, and enable CodeReady Builder via `subscription-manager` on real RHEL (so `xmlsec1-devel`, `libmspack-devel` and `rpcgen` resolve)

## [1.1.0] - 2026-05-28

### Added
- GitHub Actions CI: ansible-lint + Galaxy metadata validation
- Improved Galaxy tags for better discoverability (vsphere, esxi, vcenter, drivers, guest)
- CHANGELOG.md

### Changed
- Expanded role description for Galaxy search

## [1.0.0] - 2026-05-02

### Added
- Initial release
- Containerized build pipeline (Docker) for Ubuntu, Debian, RHEL/Rocky/Alma 8+9, Fedora
- Multi-distro Ansible deployment (apt / yum / zypper)
- Auto-diagnose and recovery if vmtoolsd fails to start
- Role variables: vmtools_remove_standard, vmtools_diagnose_on_failure, vmtools_auto_recover
- Playbook and inventory examples
