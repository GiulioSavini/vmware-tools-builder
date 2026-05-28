# vmware-tools-builder

> Build the **latest open-vm-tools from source** and deploy it across your entire VMware infrastructure with a single Ansible role — no manual compiling, no distro-specific headaches.

[![CI](https://github.com/GiulioSavini/vmware-tools-builder/actions/workflows/ci.yml/badge.svg)](https://github.com/GiulioSavini/vmware-tools-builder/actions/workflows/ci.yml)
[![Ansible Galaxy](https://img.shields.io/badge/Ansible%20Galaxy-giuliosavini.vmware__tools__builder-blue?logo=ansible)](https://galaxy.ansible.com/giuliosavini/vmware_tools_builder)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![open-vm-tools](https://img.shields.io/badge/open--vm--tools-latest-green)](https://github.com/vmware/open-vm-tools)

---

## Why this project?

The `open-vm-tools` packages bundled with most Linux distros are **months or years behind** the upstream release. This matters when you need:

- Fixes for guest OS compatibility with newer ESXi/vCenter versions
- VMCI socket support and improved balloon memory driver
- CVE patches not yet backported by your distro

This role compiles the latest release inside **isolated Docker containers** (no build deps polluting your controller), produces clean `.deb`/`.rpm` packages, and deploys them via Ansible — all in one go.

---

## Features

- Builds from the **latest upstream open-vm-tools** release (or pin a version)
- Fully **containerized build** (Docker) — clean, reproducible, no host pollution
- Multi-distro support: Ubuntu, Debian, RHEL/Rocky/Alma 8+9, Fedora, SUSE
- Handles all three deployment scenarios automatically:
  - Fresh install
  - Upgrade from existing custom build
  - Replace distro-packaged `open-vm-tools`
- Auto-diagnose & recovery if `vmtoolsd` fails to start
- Available on **Ansible Galaxy** — one-liner install

---

## Quick Start

### 1. Install from Galaxy

```bash
ansible-galaxy install giuliosavini.vmware_tools_builder
```

### 2. Or build packages from source

```bash
git clone https://github.com/GiulioSavini/vmware-tools-builder.git
cd vmware-tools-builder/containers

# Build for all supported distros (latest version)
./build-all.sh

# Single distro
./build-all.sh --target rocky9

# Pin a specific version
./build-all.sh --version 12.5.0
```

Packages land in `files/` automatically, ready for the Ansible deploy step.

### 3. Write your inventory

```ini
[debian]
srv-web01  ansible_host=10.0.0.1

[rhel]
srv-app01  ansible_host=10.0.0.10

[all:vars]
ansible_user=root
```

### 4. Run the playbook

```bash
ansible-playbook -i inventory.ini playbook.yml
```

---

## Supported platforms

| Distro | Build container | Deploy | Package |
|--------|----------------|--------|---------|
| Ubuntu 22.04+ | ✅ | ✅ | `.deb` |
| Debian 12+ | ✅ | ✅ | `.deb` |
| RHEL / Rocky / Alma 9 | ✅ | ✅ | `.rpm` |
| RHEL / Rocky / Alma 8 | ✅ | ✅ | `.rpm` |
| Fedora | ✅ | ✅ | `.rpm` |
| SUSE / openSUSE | — | ✅ | `.rpm` |

---

## Requirements

| Tool | Minimum version |
|------|----------------|
| Docker | 20.10+ (build host) |
| Ansible | 2.12+ |
| Python | 3.8+ |

---

## Role variables

| Variable | Default | Description |
|----------|---------|-------------|
| `vmtools_pkg_name` | `open-vm-tools-custom` | Package name |
| `vmtools_prefix` | `/usr/local` | Install prefix |
| `vmtools_service` | `vmtoolsd` | Systemd service name |
| `vmtools_packages_dir` | `{{ role_path }}/files` | Pre-built packages directory |
| `vmtools_remove_standard` | `true` | Remove distro `open-vm-tools` before install |
| `vmtools_diagnose_on_failure` | `true` | Run diagnostics if service fails |
| `vmtools_auto_recover` | `true` | Attempt automatic recovery |
| `vmtools_cleanup_temp` | `true` | Remove temp files from target hosts |

---

## How the deploy works

For each host the role:

1. **Preflight** — detects OS, installed packages, selects the right `.deb`/`.rpm`
2. **Deploy** — copies and installs the package (`apt` / `yum` / `zypper`)
3. **Post-install** — configures `ldconfig`, systemd unit, masks the old service
4. **Diagnose** — if `vmtoolsd` fails to start, collects logs and attempts recovery
5. **Verify** — confirms the service is running and prints the installed version

---

## Example playbook

```yaml
- name: Deploy custom open-vm-tools
  hosts: all
  become: true
  gather_facts: true
  roles:
    - role: giuliosavini.vmware_tools_builder
      vmtools_remove_standard: true
      vmtools_diagnose_on_failure: true
```

### With requirements.yml

```yaml
# requirements.yml
roles:
  - name: giuliosavini.vmware_tools_builder
    version: ">=1.0.0"
```

```bash
ansible-galaxy install -r requirements.yml
```

---

## Repository structure

```
vmware-tools-builder/
├── .github/workflows/
│   └── ci.yml                     # Ansible lint + metadata checks
├── containers/
│   ├── build-all.sh               # Multi-distro build orchestrator
│   ├── build-inside-container.sh  # Runs inside the container
│   ├── Dockerfile.ubuntu2204
│   ├── Dockerfile.debian12
│   ├── Dockerfile.rocky9
│   ├── Dockerfile.rocky8
│   └── Dockerfile.fedora
├── tasks/
│   ├── main.yml
│   ├── preflight.yml
│   ├── deploy_debian.yml
│   ├── deploy_rhel.yml
│   ├── deploy_suse.yml
│   ├── post_install.yml
│   ├── diagnose.yml
│   └── verify.yml
├── templates/
│   ├── vmtoolsd.service.j2
│   └── vmware-tools.conf.j2
├── defaults/main.yml
├── handlers/main.yml
├── meta/main.yml
├── CHANGELOG.md
├── playbook.yml
└── inventory.ini
```

---

## Contributing

PRs and issues welcome. If you add a new distro, open a PR with the matching `Dockerfile.*` and `tasks/deploy_*.yml`.

---

## License

MIT — see [LICENSE](LICENSE)

## Author

[GiulioSavini](https://github.com/GiulioSavini) — VMware/vSphere infrastructure automation
