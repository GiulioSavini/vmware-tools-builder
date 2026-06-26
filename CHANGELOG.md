# Changelog

All notable changes to this role are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added
- Ubuntu 26.04 LTS (Resolute Raccoon) support: `containers/Dockerfile.ubuntu2604` build target, `ubuntu2604` added to `build-all.sh`, and `resolute` listed in Galaxy platforms (the Ansible role already resolves the `ubuntu2604` package subdir dynamically from `ansible_distribution_version`)
- CI now builds each per-distro Docker image and compiles open-vm-tools inside it (matrix `build-container` job), so "does it compile in Docker" is verified on every push/PR and the resulting package is uploaded as an artifact

### Fixed
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
