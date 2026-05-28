# Changelog

All notable changes to this role are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

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
