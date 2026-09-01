# Ubuntu-Autoinstall

Unattended **Ubuntu Server** installation (24.04 LTS or 26.04 LTS) in a virtual
machine on **VMware ESXi** or **Microsoft Hyper-V** — plus a script loader that
fetches setup and maintenance scripts from this repository on demand.

[![CI](https://github.com/sven-reichelt/Ubuntu-Autoinstall/actions/workflows/ci.yml/badge.svg)](https://github.com/sven-reichelt/Ubuntu-Autoinstall/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/sven-reichelt/Ubuntu-Autoinstall?label=release&color=blue)](https://github.com/sven-reichelt/Ubuntu-Autoinstall/releases/latest)
[![Pre-release](https://img.shields.io/github/v/release/sven-reichelt/Ubuntu-Autoinstall?include_prereleases&label=pre-release&color=orange)](https://github.com/sven-reichelt/Ubuntu-Autoinstall/releases)
[![License: GPL v3+](https://img.shields.io/badge/license-GPLv3%2B-blue.svg)](LICENSE)

---

## How it works

Ubuntu installs itself from a small **seed ISO** (subiquity `autoinstall`) — the
Ubuntu ISO stays untouched. Nothing is pre-installed beyond a minimal base
system. After the first boot a single script, `get-scripts.sh`, sits in the
user's home directory and downloads whatever you actually need.

```
  ubuntu-XX.XX.iso  +  seed.iso (CIDATA)  ->  unattended install  ->  reboot
                                                                       |
                        sudo ~/get-scripts.sh  <---------------------- +
                                |
                                +--> downloads scripts from this repo on demand
```

New scripts therefore reach machines that were installed months ago, **without
building a single new ISO**.

---

## Quick start

1. **Get `seed.iso`** — download it from the
   [latest release](https://github.com/sven-reichelt/Ubuntu-Autoinstall/releases/latest),
   or build it yourself:

   ```bash
   cd autoinstall && ./build-seed-iso.sh
   ```

2. **Get the Ubuntu Server ISO** — `ubuntu-24.04.x-live-server-amd64.iso` or
   `ubuntu-26.04.x-live-server-amd64.iso` from
   [ubuntu.com](https://ubuntu.com/download/server).

3. **Create the VM**, attach the Ubuntu ISO as the boot medium and `seed.iso` as
   a **second CD drive**, then boot.
   → VM settings for both hypervisors: **[Installation](docs/Installation.md)**

4. **Log in and change the password:**

   ```bash
   ssh ubuntu-admin@<SERVER-IP>          # password: ubuntu
   sudo ~/get-scripts.sh change-password.sh
   ```

---

## Documentation

Full documentation lives in [`docs/`](docs) and is mirrored to the
[**wiki**](https://github.com/sven-reichelt/Ubuntu-Autoinstall/wiki).

| | |
| --- | --- |
| **[Installation](docs/Installation.md)** | ISO preparation, VM settings for ESXi and Hyper-V, first login |
| **[Scripts](docs/Scripts.md)** | The loader and every script it offers, with options and defaults |
| **[Configuration](docs/Configuration.md)** | Hostname, user, password, keyboard, network, packages — and adding your own scripts |
| **[Troubleshooting](docs/Troubleshooting.md)** | When the installer asks questions, the VM will not boot, or a script fails |
| **[Development](docs/Development.md)** | Repository layout, `validate.sh`, CI, release process |

---

## Available scripts

| Script | What it does |
| --- | --- |
| [`change-password.sh`](docs/Scripts.md#change-passwordsh) | Change the password of a local account |
| [`configure-network.sh`](docs/Scripts.md#configure-networksh) | Switch an interface between DHCP and a static IP, with automatic rollback |
| [`system-update.sh`](docs/Scripts.md#system-updatesh) | Update all packages and report whether a reboot is required |
| [`install-hfs.sh`](docs/Scripts.md#install-hfssh) | Install or update [HFS](https://rejetto.com/hfs) (HTTP File Server) in Docker |
| [`install-unifi-os-server.sh`](docs/Scripts.md#install-unifi-os-serversh) | Install or update [UniFi OS Server](https://ui.com/download/releases/unifi-os-server) via Podman |

```bash
sudo ~/get-scripts.sh              # interactive menu
sudo ~/get-scripts.sh --list       # list what is available
sudo ~/get-scripts.sh --all        # download everything to ~/scripts
```

Adding your own takes two steps: drop the script into [`scripts/`](scripts) and
add a line to [`scripts/manifest.txt`](scripts/manifest.txt). See
[Configuration → Adding your own script](docs/Configuration.md#adding-your-own-script).

---

## Security

`autoinstall/user-data` ships a **publicly known** default password so the
installation can run unattended: **`ubuntu-admin` / `ubuntu`**. Change it right
after the first login, or better, replace the hash before building the ISO and
use an SSH key. Details and the vulnerability reporting process:
**[SECURITY.md](SECURITY.md)**.

---

## License

GNU General Public License v3.0 **or later** — see [LICENSE](LICENSE).
Changes are tracked in [CHANGELOG.md](CHANGELOG.md).
