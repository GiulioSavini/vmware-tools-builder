# VMware Tools Builder & Deployer

Script per compilare l'ultima versione di `open-vm-tools` da sorgente (`.deb` per Debian/Ubuntu, `.rpm` per RHEL/CentOS) e playbook Ansible per distribuirlo su tutte le macchine.

## Struttura

```
.
├── build.sh                  # Script di build (da eseguire sulla build machine)
├── ansible/
│   ├── inventory.ini         # Inventory delle macchine target
│   ├── deploy-vmtools.yml    # Playbook di distribuzione
│   └── templates/
│       ├── vmtoolsd.service.j2
│       └── vmware-tools.conf.j2
└── README.md
```

## Prerequisiti

- Build machine: Debian/Ubuntu o RHEL/CentOS con accesso internet
- Ansible installato sulla build machine
- SSH access alle macchine target

## Uso

### 1. Build del pacchetto

```bash
# Su una macchina Debian/Ubuntu per creare il .deb:
sudo bash build.sh

# Su una macchina RHEL/CentOS per creare il .rpm:
sudo bash build.sh

# Lo script rileva automaticamente l'OS e crea il pacchetto corretto
# Il pacchetto viene messo in ~/ansible/
```

### 2. Configurare l'inventory

Edita `ansible/inventory.ini` con le tue macchine:

```ini
[debian]
crd-haproxy01 ansible_host=10.0.0.1
crd-haproxy02 ansible_host=10.0.0.2

[rhel]
crd-app01 ansible_host=10.0.0.10
```

### 3. Deploy

```bash
cd ansible
ansible-playbook -i inventory.ini deploy-vmtools.yml
```

## Cosa fa il playbook

### Caso 1 — Ha gia' `open-vm-tools-custom`
- Installa il nuovo pacchetto sopra (upgrade)
- Verifica ldconfig, service file, rimuove link vgauth
- Riavvia il demone

### Caso 2 — Ha `open-vm-tools` standard (da repo Ubuntu/RHEL)
- Rimuove prima il pacchetto standard (`apt remove` / `yum remove`)
- Installa il pacchetto custom
- Riscrive il service file con il path corretto (`/usr/local/bin/vmtoolsd`)
- Configura ldconfig
- Avvia e abilita il demone

### Verifica finale
- Controlla che `vmtoolsd` sia running
- Stampa la versione installata
