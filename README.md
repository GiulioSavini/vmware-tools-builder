# VMware Tools Builder

Ruolo Ansible per compilare e distribuire l'ultima versione di `open-vm-tools` da sorgente su tutte le distro Linux supportate, utilizzando build containerizzate (Docker).

## Requisiti

- **Docker** sulla macchina di build (per compilare i pacchetti)
- **Ansible >= 2.12** per il deploy
- **SSH access** alle macchine target

## Struttura del ruolo

```
vmware-tools-builder/
├── defaults/main.yml              # Variabili default del ruolo
├── tasks/
│   ├── main.yml                   # Entry point
│   ├── preflight.yml              # Detect stato attuale
│   ├── deploy_debian.yml          # Deploy su Debian/Ubuntu
│   ├── deploy_rhel.yml            # Deploy su RHEL/CentOS/Rocky
│   ├── deploy_suse.yml            # Deploy su SUSE/openSUSE
│   ├── post_install.yml           # Configurazione post-install
│   ├── diagnose.yml               # Diagnostica e recovery automatico
│   └── verify.yml                 # Verifica finale
├── handlers/main.yml              # Handler (ldconfig, reload, restart)
├── templates/
│   ├── vmtoolsd.service.j2        # Systemd service unit
│   └── vmware-tools.conf.j2       # Configurazione ld.so
├── files/                         # Pacchetti .deb/.rpm compilati
├── meta/main.yml                  # Metadata Ansible Galaxy
├── containers/                    # Build containerizzata
│   ├── build-all.sh               # Orchestratore multi-distro
│   ├── build-inside-container.sh  # Script compilazione (gira nel container)
│   ├── Dockerfile.ubuntu2204
│   ├── Dockerfile.debian12
│   ├── Dockerfile.rocky9
│   ├── Dockerfile.rocky8
│   └── Dockerfile.fedora
├── build.sh                       # Script legacy (standalone, senza container)
├── playbook.yml                   # Playbook di esempio
└── inventory.ini                  # Inventory di esempio
```

## Installazione

### Da Ansible Galaxy

```bash
ansible-galaxy install giuliosavini.vmware_tools_builder
```

### Da GitHub

```bash
ansible-galaxy install git+https://github.com/GiulioSavini/vmware-tools-builder.git,main
```

### Manuale

```bash
cd ~/.ansible/roles/   # oppure nella directory roles/ del tuo progetto
git clone https://github.com/GiulioSavini/vmware-tools-builder.git giuliosavini.vmware_tools_builder
```

## Quick Start

### 1. Build dei pacchetti

```bash
cd containers

# Build per tutte le distro (latest version)
./build-all.sh

# Solo una distro specifica
./build-all.sh --target rocky9

# Versione specifica
./build-all.sh --version 12.5.0

# Help
./build-all.sh --help
```

I pacchetti vengono generati in `output/` e copiati automaticamente in `files/`.

### 2. Configurare l'inventory

```ini
[debian]
srv-web01    ansible_host=10.0.0.1
srv-web02    ansible_host=10.0.0.2

[rhel]
srv-app01    ansible_host=10.0.0.10

[suse]
srv-db01     ansible_host=10.0.0.20

[all:vars]
ansible_user=root
```

### 3. Deploy

```bash
ansible-playbook -i inventory.ini playbook.yml
```

## Variabili del ruolo

| Variabile | Default | Descrizione |
|-----------|---------|-------------|
| `vmtools_pkg_name` | `open-vm-tools-custom` | Nome del pacchetto |
| `vmtools_prefix` | `/usr/local` | Prefix di installazione |
| `vmtools_service` | `vmtoolsd` | Nome del servizio systemd |
| `vmtools_packages_dir` | `{{ role_path }}/files` | Directory con i pacchetti compilati |
| `vmtools_remove_standard` | `true` | Rimuovi open-vm-tools standard prima dell'install |
| `vmtools_diagnose_on_failure` | `true` | Esegui diagnostica se il servizio non parte |
| `vmtools_auto_recover` | `true` | Tenta recovery automatico |
| `vmtools_cleanup_temp` | `true` | Pulisci file temporanei sul target |

## Come funziona il deploy

Il ruolo gestisce automaticamente tre scenari:

| Scenario | Azione |
|----------|--------|
| Ha gia' `open-vm-tools-custom` | Upgrade con il nuovo pacchetto |
| Ha `open-vm-tools` standard | Rimuove il pacchetto standard, installa il custom |
| Installazione pulita | Installa direttamente |

Workflow per ogni host:
1. **Preflight**: rileva OS, pacchetti installati, seleziona il .deb/.rpm corretto
2. **Deploy**: copia e installa il pacchetto (apt/yum/zypper)
3. **Post-install**: configura ldconfig, systemd service, maschera il vecchio service
4. **Diagnostica**: se il servizio non parte, raccoglie log e tenta recovery
5. **Verifica**: conferma che vmtoolsd e' running e stampa la versione

## Esempio playbook

```yaml
- name: Deploy VMware Tools Custom
  hosts: all
  become: true
  gather_facts: true
  roles:
    - role: giuliosavini.vmware_tools_builder
      vmtools_remove_standard: true
      vmtools_diagnose_on_failure: true
```

## Distro supportate

| Distro | Build | Deploy | Pacchetto |
|--------|-------|--------|-----------|
| Ubuntu 22.04+ | container | ruolo | .deb |
| Debian 12+ | container | ruolo | .deb |
| RHEL/Rocky/Alma 9 | container | ruolo | .rpm |
| RHEL/Rocky/Alma 8 | container | ruolo | .rpm |
| Fedora | container | ruolo | .rpm |
| SUSE/openSUSE | da aggiungere | ruolo | .rpm |

## Licenza

MIT

## Autore

GiulioSavini
