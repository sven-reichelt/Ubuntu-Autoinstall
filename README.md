# Ubuntu-Autoinstall

Unattended **Ubuntu Server** installation (24.04 LTS or 26.04 LTS) in a virtual
machine on **VMware ESXi** or **Microsoft Hyper-V** — plus a script loader that
fetches setup and maintenance scripts from this repository whenever you need
them.

Ubuntu installs itself from a small seed ISO (subiquity `autoinstall`). Nothing
is pre-installed beyond a minimal base system. After the first boot a single
script, `get-scripts.sh`, sits in the user's home directory and downloads the
scripts you actually want — so new scripts become available on every existing
machine without rebuilding a single ISO.

[![CI](https://github.com/sven-reichelt/Ubuntu-Autoinstall/actions/workflows/ci.yml/badge.svg)](https://github.com/sven-reichelt/Ubuntu-Autoinstall/actions/workflows/ci.yml)
[![License: GPL v3+](https://img.shields.io/badge/License-GPLv3%2B-blue.svg)](LICENSE)

---

## Contents

- [Features](#features)
- [Quick start](#quick-start)
- [Using the script loader](#using-the-script-loader)
- [Available scripts](#available-scripts)
- [Adding your own script](#adding-your-own-script)
- [Customising the installation](#customising-the-installation)
- [Project layout](#project-layout)
- [Requirements](#requirements)
- [Validation and CI](#validation-and-ci)
- [Releases](#releases)
- [Security](#security)
- [License](#license)
- [Sources](#sources)

---

## Features

- **Fully unattended Ubuntu installation** (24.04 LTS and 26.04 LTS) via
  `autoinstall` and a NoCloud seed ISO. No keystrokes, no remastered Ubuntu ISO.
- **Scripts on demand instead of baked in.** Only the loader ships on the seed
  ISO; everything else is pulled from GitHub at the moment you need it.
- **Ready-made scripts** for password changes, network configuration, system
  updates, HFS (HTTP File Server) and UniFi OS Server.
- **Custom MOTD** that replaces Ubuntu's stock notices (help text, package
  news, Ubuntu Pro advertising) with the next steps for this system.
- **One configuration for both hypervisors** — the network match `e*` covers
  VMware (`ens*`/`enp*`) and Hyper-V (`eth0`) alike.
- **Seed ISO built by GitHub Actions** and attached to every release, so you do
  not need a Linux machine to build one.

---

## Quick start

### 1. Get a seed ISO

**Either** download `seed.iso` from the
[latest release](https://github.com/sven-reichelt/Ubuntu-Autoinstall/releases/latest)
(built by GitHub Actions, checksum included),

**or** build it yourself on Linux, WSL or macOS:

```bash
git clone https://github.com/sven-reichelt/Ubuntu-Autoinstall.git
cd Ubuntu-Autoinstall/autoinstall
./build-seed-iso.sh          # produces seed.iso in this directory
```

### 2. Get the Ubuntu Server ISO

Download `ubuntu-24.04.x-live-server-amd64.iso` **or**
`ubuntu-26.04.x-live-server-amd64.iso` from
[ubuntu.com](https://ubuntu.com/download/server).

### 3. Create the VM and boot it

Attach **both** ISOs: the Ubuntu Server ISO as the boot medium and `seed.iso`
as a **second CD/DVD drive**. Then start the VM.

Step-by-step VM settings for both hypervisors are in
**[docs/INSTALLATION.md](docs/INSTALLATION.md)** — read it before creating the
VM, a few settings (Secure Boot, static memory, boot order) matter.

The installation runs on its own and reboots when it is done. Depending on the
hardware and the download of security updates this takes roughly 10–20 minutes.

### 4. Log in

```
User:     ubuntu-admin
Password: ubuntu
Hostname: ubuntu
```

> **The password is public knowledge** — it is in this repository and in every
> `seed.iso`. Change it right away (see the next step) and do not put the VM on
> an untrusted network before you do. See [SECURITY.md](SECURITY.md).

### 5. Fetch the scripts you need

```bash
sudo ~/get-scripts.sh change-password.sh    # recommended first step
sudo ~/get-scripts.sh                       # or: browse the menu
```

---

## Using the script loader

`get-scripts.sh` is the only script placed on the system by the installation.
It reads the list of available scripts from
[`scripts/manifest.txt`](scripts/manifest.txt), downloads what you pick into
`~/scripts`, makes it executable and can run it straight away.

```bash
sudo ~/get-scripts.sh                     # interactive menu (default)
sudo ~/get-scripts.sh --list              # list available scripts and exit
sudo ~/get-scripts.sh --all               # download everything to ~/scripts
sudo ~/get-scripts.sh install-hfs.sh      # download one script and run it
sudo ~/get-scripts.sh -d install-hfs.sh   # download it, but do not run it
sudo ~/get-scripts.sh --self-update       # update the loader itself
~/get-scripts.sh --help                   # show the built-in help
```

The interactive menu looks like this:

```
== Ubuntu-Autoinstall - script loader ==
   target directory: /home/ubuntu-admin/scripts

Available scripts (https://github.com/sven-reichelt/Ubuntu-Autoinstall):

   1) change-password.sh          Change the password of a local user account
   2) configure-network.sh        Switch a network interface between DHCP and a static IP
   3) system-update.sh            Update all packages (apt update / full-upgrade / autoremove)
   4) install-hfs.sh              Install or update HFS (HTTP File Server) in Docker
   5) install-unifi-os-server.sh  Install or update UniFi OS Server

   a) download all      r) refresh list      q) quit

Selection:
```

Notes:

- Downloads always fetch the current version from the `main` branch, so running
  the loader again is also how you update a script.
- Files land in the home directory of the user who invoked `sudo`, not in
  `/root`, and are owned by that user.
- If `scripts/manifest.txt` cannot be reached, the loader falls back to the
  GitHub API and lists the `*.sh` files in `scripts/` directly.
- A download is rejected if the file is empty or does not start with a shebang.

---

## Available scripts

| Script | What it does |
| --- | --- |
| [`change-password.sh`](scripts/change-password.sh) | Changes the password of a local account. Offers hidden entry (`passwd`) or plain-text entry for the case where the keyboard layout garbles special characters. |
| [`configure-network.sh`](scripts/configure-network.sh) | Switches an interface between DHCP and a static IP and writes the netplan configuration. Uses `netplan try` as a safety net: if the connection drops, the previous configuration is restored automatically — files included. Cleans up competing netplan files and disables cloud-init's network management. |
| [`system-update.sh`](scripts/system-update.sh) | `apt-get update`, `full-upgrade`, `autoremove --purge`, `autoclean`, then reports whether a reboot is required and which packages caused it. Supports `--reboot` / `--no-reboot`. |
| [`install-hfs.sh`](scripts/install-hfs.sh) | Installs Docker CE from the official Docker repository and runs [HFS](https://rejetto.com/hfs) as a container with host networking (real client IPs), a configurable port and a compose file in `/opt/hfs`. Run it again to update. |
| [`install-unifi-os-server.sh`](scripts/install-unifi-os-server.sh) | Installs or updates [UniFi OS Server](https://ui.com/download/releases/unifi-os-server) via Podman. Ubiquiti publishes no stable "latest" URL, so you pass the download link from ui.com to the script. Web UI on port 11443. |

Every script:

- requires root (`sudo`) and says so if started without it,
- is idempotent enough to be run again — an existing installation is detected
  and updated instead of duplicated,
- writes a log to `/var/log/` where a log makes sense.

### Script details

<details>
<summary><strong>configure-network.sh</strong> — why it moves other netplan files aside</summary>

Netplan applies **all** `*.yaml` files in `/etc/netplan/` together. cloud-init
writes `50-cloud-init.yaml` (DHCP on `e*`) on the first boot. If the script only
added its own file, both would fight over the same interface.

It therefore backs up every other netplan file to
`/etc/netplan/configure-network.orig/`, writes
`/etc/netplan/90-autoinstall-network.yaml` as the single source of truth and
disables cloud-init's network management permanently
(`/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg`). Switching back to DHCP
rewrites that file too — it is never merely deleted, which would leave the
interface without any configuration at all.

`netplan try` applies the change for 60 seconds. Confirm with ENTER in the same
window; if the SSH session dies, do nothing and netplan rolls back. The script
additionally restores the previous *files*, because `netplan try` only rolls
back the running connection — otherwise a reboot would activate the unconfirmed
configuration after all.
</details>

<details>
<summary><strong>install-hfs.sh</strong> — layout and defaults</summary>

| | |
| --- | --- |
| Compose file | `/opt/hfs/docker-compose.yml` |
| Configuration and logs | `/opt/hfs/data` (mounted as `/data`) |
| Shared files | `/srv/hfs/shares` (mounted as `/shares`, override with `--shares`) |
| Port | asked interactively, default `80`, set via `HFS_PORT` |
| Networking | `network_mode: host` — recommended by the HFS wiki so HFS logs the real client IPs |
| Restart policy | `unless-stopped` |

```bash
sudo ~/get-scripts.sh install-hfs.sh          # interactive
sudo ~/scripts/install-hfs.sh --port 8080     # non-interactive
sudo ~/scripts/install-hfs.sh --shares /srv/data --yes
```

Because of host networking there is no port mapping — the script warns if the
chosen port is already in use. Everyday commands:

```bash
docker compose -f /opt/hfs/docker-compose.yml ps
docker compose -f /opt/hfs/docker-compose.yml logs -f
sudo ~/scripts/install-hfs.sh                 # pull a new image and recreate
```

> The HFS image creates a default account **`admin` / `please-change`**.
> Change it in the admin panel (`http://<SERVER-IP>:<PORT>/~/admin`) immediately.
</details>

<details>
<summary><strong>install-unifi-os-server.sh</strong> — getting the download URL</summary>

1. Open <https://ui.com/download/releases/unifi-os-server>
2. Right-click the download of the **Linux (x64)** entry
3. Choose *Copy link address*

```bash
sudo ~/get-scripts.sh install-unifi-os-server.sh "https://fw-download.ubnt.com/data/unifi-os-server/...-x64"
```

The file name contains the version plus a checksum and changes with every
release, which is why no URL is hard-coded. The web interface is then available
at `https://<SERVER-IP>:11443` (the certificate warning is expected).
</details>

---

## Adding your own script

1. Put the script into `scripts/`. Conventions: `#!/usr/bin/env bash`,
   `set -euo pipefail`, comments in English and ASCII only, root check at the
   top, idempotent where possible.
2. Add one line to `scripts/manifest.txt`:

   ```
   my-script.sh|Short description shown in the menu
   ```

3. Run `./validate.sh` and commit.

That is all. **No new seed ISO is needed** — every already-installed system
sees the new script the next time `get-scripts.sh` runs.

`validate.sh` (and the CI) enforces that the manifest and the directory stay in
sync in both directions: a listed script must exist, and an existing script
must be listed.

---

## Customising the installation

Everything that shapes the installed system lives in
[`autoinstall/user-data`](autoinstall/user-data). Edit it **before** building
the seed ISO.

| What | Where | Default |
| --- | --- | --- |
| Hostname | `identity.hostname` | `ubuntu` |
| Display name | `identity.realname` | `Ubuntu Server` |
| User name | `identity.username` **and** `TARGET_USER` in `late-commands` | `ubuntu-admin` |
| Password | `identity.password` (SHA-512 hash) | `ubuntu` |
| SSH key | `ssh.authorized-keys` | not set |
| Locale / keyboard / timezone | `locale`, `keyboard.layout`, `timezone` | `de_DE.UTF-8`, `de`, `Europe/Berlin` |
| Network | `network` | DHCP on every `e*` interface |
| Disk layout | `storage.layout.name` | `direct` (one large root partition) |
| Packages | `packages` | `curl`, `ca-certificates`, `open-vm-tools` |

**Own password hash:**

```bash
openssl passwd -6 'YOUR-PASSWORD'
```

Paste the complete `$6$...` string into `identity.password`.

**SSH key instead of a password** (recommended):

```yaml
ssh:
  install-server: true
  allow-pw: false
  authorized-keys:
    - "ssh-ed25519 AAAA... your-key"
```

**Static IP at install time:** comment out the `anyeth` block under `network`
and use the commented alternative below it. For an already installed system use
`configure-network.sh` instead.

**A different user name:** change `identity.username` *and* both occurrences of
`TARGET_USER="ubuntu-admin"` in `late-commands`. `validate.sh` fails if they
drift apart.

**Your own fork:** change `REPO_OWNER` (and `REPO_NAME` / `REPO_BRANCH` if
needed) at the top of `scripts/get-scripts.sh` so the loader pulls from your
repository, and adjust the project URL in the MOTD block of `user-data`.

---

## Project layout

```
.
├── README.md                          this file - central documentation
├── CHANGELOG.md                       version history
├── SECURITY.md                        security policy and the default credentials
├── LICENSE                            GNU GPL v3
├── validate.sh                        all checks (bash -n, ShellCheck, YAML, manifest)
├── .github/workflows/
│   ├── ci.yml                         validation on every push and pull request
│   └── release.yml                    builds seed.iso and publishes the release
├── autoinstall/
│   ├── user-data                      autoinstall configuration (edit this!)
│   ├── meta-data                      minimal cloud-init metadata (NoCloud)
│   └── build-seed-iso.sh              builds seed.iso (volume label CIDATA)
├── scripts/
│   ├── get-scripts.sh                 the loader - the only script on the seed ISO
│   ├── manifest.txt                   list of scripts offered by the loader
│   ├── change-password.sh
│   ├── configure-network.sh
│   ├── system-update.sh
│   ├── install-hfs.sh
│   └── install-unifi-os-server.sh
└── docs/
    └── INSTALLATION.md                VM setup for VMware ESXi and Hyper-V
```

---

## Requirements

**On the hypervisor host**

- VMware ESXi / vCenter **or** Windows with the Hyper-V role
- Ubuntu Server ISO: `ubuntu-24.04.x-live-server-amd64.iso` or
  `ubuntu-26.04.x-live-server-amd64.iso`

**Recommended VM sizing**

| | Minimum | Recommended | Note |
| --- | --- | --- | --- |
| vCPU | 2 | 2–4 | |
| RAM | 2 GB | 4 GB | static memory on Hyper-V |
| Disk | 20 GB | 32 GB+ | UniFi OS Server needs ~2 GB free just for the download |
| Firmware | UEFI | UEFI | Hyper-V: Generation 2 with Secure Boot **off** |

**To build the ISO yourself** (not needed if you download it from a release)

- `xorriso` (Linux/WSL: `sudo apt-get install -y xorriso`), or `genisoimage`,
  `mkisofs`, or `hdiutil` on macOS

---

## Validation and CI

Validate everything locally before committing:

```bash
./validate.sh
```

It runs:

1. `bash -n` on every `*.sh`
2. ShellCheck (skipped with a note if it is not installed)
3. YAML validation of `autoinstall/user-data` and `meta-data`, including the
   mandatory fields, a `$6$` password hash and a check that `TARGET_USER` in
   `late-commands` matches `identity.username`
4. Consistency between `scripts/manifest.txt` and `scripts/*.sh`

The same checks run in GitHub Actions on every push and pull request
([`ci.yml`](.github/workflows/ci.yml)).

---

## Releases

Pushing a version tag builds and publishes everything automatically
([`release.yml`](.github/workflows/release.yml)):

```bash
git tag -a v1.1.0 -m "Release 1.1.0"
git push origin v1.1.0
```

The workflow validates the repository, builds `seed.iso`, creates a SHA-256
checksum, takes the release notes from the matching section of `CHANGELOG.md`
and publishes both files as release assets.

Verify a downloaded ISO:

```bash
sha256sum -c seed.iso.sha256
```

All versions: [Releases](https://github.com/sven-reichelt/Ubuntu-Autoinstall/releases).

---

## Security

`autoinstall/user-data` ships a **publicly known** default password so the
installation can run unattended:

| User | Password |
| --- | --- |
| `ubuntu-admin` | `ubuntu` |

Change it immediately after the first login, or better, replace the hash before
building the ISO and use an SSH key. Details, the reporting process for
vulnerabilities and the notes on third-party software are in
**[SECURITY.md](SECURITY.md)**.

Built ISOs, virtual disks and real secrets must never be committed — see
`.gitignore`.

---

## License

GNU General Public License v3.0 **or later** — see [LICENSE](LICENSE).

---

## Sources

- [Ubuntu autoinstall reference (subiquity)](https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html)
- [cloud-init NoCloud datasource](https://cloudinit.readthedocs.io/en/latest/reference/datasources/nocloud.html)
- [Netplan documentation](https://netplan.readthedocs.io/)
- [Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [HFS – Docker (wiki)](https://github.com/rejetto/hfs/wiki/Docker)
- [Self-hosting UniFi – Ubiquiti Help Center](https://help.ui.com/hc/en-us/articles/34210126298775-Self-Hosting-UniFi)
- [UniFi OS Server downloads](https://ui.com/download/releases/unifi-os-server)
