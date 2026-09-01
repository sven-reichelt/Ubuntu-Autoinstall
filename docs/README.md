# Ubuntu-Autoinstall documentation

Unattended **Ubuntu Server** installation (24.04 LTS or 26.04 LTS) in a virtual
machine on **VMware ESXi** or **Microsoft Hyper-V**, plus a script loader that
fetches setup and maintenance scripts from the repository on demand.

> These pages are generated from [`docs/`](https://github.com/sven-reichelt/Ubuntu-Autoinstall/tree/main/docs)
> in the repository and mirrored into the wiki automatically on every push to
> `main`. Edit the files in the repository, not the wiki — direct wiki edits are
> overwritten by the next sync.

---

## Where to start

| Page | What it covers |
| --- | --- |
| **[Installation](Installation.md)** | Preparing the ISO files, VM settings for VMware ESXi and Hyper-V, starting the installation, first login. **Start here.** |
| **[Scripts](Scripts.md)** | The script loader `get-scripts.sh` and every script it offers, with options and defaults. |
| **[Configuration](Configuration.md)** | Changing hostname, user, password, keyboard, network and packages in `user-data`. Adding your own scripts. Running a fork. |
| **[Troubleshooting](Troubleshooting.md)** | What to do when the installer asks questions, the VM does not boot, there is no network, or a script fails. |
| **[Development](Development.md)** | Repository layout, `validate.sh`, the CI, and how a release is cut. |

---

## How it works in one picture

```
   +-------------------------+
   |   Virtual machine       |
   |                         |
   |  CD 1: ubuntu-XX.XX.iso |  <- boot medium, unmodified
   |  CD 2: seed.iso (CIDATA)|  <- user-data + meta-data + get-scripts.sh
   |  Disk: 32 GB            |
   +-------------------------+
              |
              v
   unattended installation, reboot
              |
              v
   ubuntu-admin@ubuntu:~$ ls
   get-scripts.sh
              |
              v
   sudo ~/get-scripts.sh   ->  downloads scripts from GitHub on demand
```

The Ubuntu ISO is never modified. A tiny second ISO with the volume label
`CIDATA` carries the answers for the installer, and the only thing that ends up
on the installed system is the loader — everything else is pulled from the
repository when you actually want it. New scripts therefore reach machines that
were installed months ago, without building a single new ISO.

---

## Defaults after the installation

| | |
| --- | --- |
| Hostname | `ubuntu` |
| User | `ubuntu-admin` |
| Password | `ubuntu` — **publicly known, change it immediately** |
| Network | DHCP |
| SSH | enabled, password login allowed |
| Locale / keyboard / timezone | `de_DE.UTF-8` / `de` / `Europe/Berlin` |

```bash
ssh ubuntu-admin@<SERVER-IP>
sudo ~/get-scripts.sh change-password.sh
```

See [SECURITY.md](https://github.com/sven-reichelt/Ubuntu-Autoinstall/blob/main/SECURITY.md)
for why that credential exists and how to replace it before building the ISO.

---

## Sources

- [Ubuntu autoinstall reference (subiquity)](https://canonical-subiquity.readthedocs-hosted.com/en/latest/reference/autoinstall-reference.html)
- [cloud-init NoCloud datasource](https://cloudinit.readthedocs.io/en/latest/reference/datasources/nocloud.html)
- [Netplan documentation](https://netplan.readthedocs.io/)
- [Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/)
- [HFS – Docker (wiki)](https://github.com/rejetto/hfs/wiki/Docker)
- [Self-hosting UniFi – Ubiquiti Help Center](https://help.ui.com/hc/en-us/articles/34210126298775-Self-Hosting-UniFi)
- [UniFi OS Server downloads](https://ui.com/download/releases/unifi-os-server)
