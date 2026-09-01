# Installation

Step-by-step setup of the virtual machine for **VMware ESXi** and
**Microsoft Hyper-V**, from the two ISO files to the first login.

For the short version see the
[repository README](../README.md#quick-start). If something goes wrong, see
[Troubleshooting](Troubleshooting.md).

---

## Contents

- [Overview](#overview)
- [Part 1 – Prepare the ISO files](#part-1--prepare-the-iso-files)
- [Part 2 – Adjust the configuration (optional)](#part-2--adjust-the-configuration-optional)
- [Part 3 – Create the VM on VMware ESXi](#part-3--create-the-vm-on-vmware-esxi)
- [Part 4 – Create the VM on Hyper-V](#part-4--create-the-vm-on-hyper-v)
- [Part 5 – Start the installation](#part-5--start-the-installation)
- [Part 6 – First login](#part-6--first-login)
- [Part 7 – Fetch and run scripts](#part-7--fetch-and-run-scripts)

---

## Overview

The VM boots from the **Ubuntu Server ISO**. A **second CD drive** holds
`seed.iso`, a tiny image with the volume label `CIDATA` containing `user-data`,
`meta-data` and the script loader. Ubuntu's installer (subiquity) finds that
NoCloud datasource, reads the answers from it and installs without asking
anything.

The Ubuntu ISO itself is **not** modified. That keeps the setup simple and lets
you use any 24.04.x or 26.04.x image — but it means one small keystroke is
needed at the boot menu, see [Part 5](#part-5--start-the-installation).

**Recommended VM sizing**

| | Minimum | Recommended | Note |
| --- | --- | --- | --- |
| vCPU | 2 | 2–4 | |
| RAM | 2 GB | 4 GB | static memory on Hyper-V |
| Disk | 20 GB | 32 GB+ | UniFi OS Server needs ~2 GB free just for the download |
| Firmware | UEFI | UEFI | Hyper-V: Generation 2 with Secure Boot **off** |

---

## Part 1 – Prepare the ISO files

### 1.1 Ubuntu Server ISO

Download from <https://ubuntu.com/download/server>:

- `ubuntu-24.04.x-live-server-amd64.iso` **or**
- `ubuntu-26.04.x-live-server-amd64.iso`

Both work; the configuration is deliberately version-neutral.

> Use the **Server** image, not Desktop and not the "live" Desktop installer —
> only the server image ships subiquity's autoinstall support.

### 1.2 seed.iso

**Option A — download (no Linux needed):**

Take `seed.iso` from the
[latest release](https://github.com/sven-reichelt/Ubuntu-Autoinstall/releases/latest).
Verify it if you like:

```bash
sha256sum -c seed.iso.sha256
```

**Option B — build it yourself** (Linux, WSL or macOS):

```bash
git clone https://github.com/sven-reichelt/Ubuntu-Autoinstall.git
cd Ubuntu-Autoinstall/autoinstall
./build-seed-iso.sh
```

Requires `xorriso` (`sudo apt-get install -y xorriso`), or `genisoimage`,
`mkisofs`, or `hdiutil` on macOS. The result is `autoinstall/seed.iso`.

### 1.3 Upload both files

- **ESXi:** upload both ISOs to a datastore
  (*Storage → Datastore browser → Upload*).
- **Hyper-V:** put both ISOs in a folder on the Hyper-V host, e.g. `D:\iso\`.

---

## Part 2 – Adjust the configuration (optional)

Skip this if the defaults are fine — you can change everything after the
installation as well.

The defaults:

| Setting | Value |
| --- | --- |
| Hostname | `ubuntu` |
| Display name | `Ubuntu Server` |
| User | `ubuntu-admin` |
| Password | `ubuntu` |
| Locale / keyboard / timezone | `de_DE.UTF-8` / `de` / `Europe/Berlin` |
| Network | DHCP |
| Disk | whole disk, one root partition |
| SSH | enabled, password login allowed |

If you want different values they have to go into
[`autoinstall/user-data`](../autoinstall/user-data) **before** building the seed
ISO (Option B above) — a downloaded release ISO always carries the defaults.

The full list of what can be changed, including your own password hash, an SSH
key, a different keyboard layout and a static IP at install time, is on the
[Configuration](Configuration.md) page.

After editing, rebuild the seed ISO and check the result:

```bash
./validate.sh
cd autoinstall && ./build-seed-iso.sh
```

---

## Part 3 – Create the VM on VMware ESXi

In the vSphere/ESXi client: **Create/Register VM → Create a new virtual
machine**.

| Setting | Value |
| --- | --- |
| Guest OS family | **Linux** |
| Guest OS version | **Ubuntu Linux (64-bit)** |
| CPU | **2 vCPUs** |
| Memory | **4 GB** (2 GB minimum) |
| Hard disk | **32 GB**, thin provisioned |
| SCSI controller | **VMware Paravirtual** (or LSI Logic SAS) |
| Network adapter | **VMXNET3**, connected to the right port group / VLAN |
| Firmware | **UEFI** (default; Secure Boot can stay off) |
| CD/DVD drive 1 | Datastore ISO → `ubuntu-2x.04.x-live-server-amd64.iso`, **Connect at power on** ✔ |
| CD/DVD drive 2 | Datastore ISO → `seed.iso`, **Connect at power on** ✔ |

Adding the second CD drive: *Add other device → CD/DVD Drive*, then set it to
*Datastore ISO file* and pick `seed.iso`. **Both** drives must have *Connect at
power on* ticked — without it the installer never sees the seed data and stops
at the language selection.

Also make sure the **boot order starts with the CD/DVD drive**
(*VM Options → Boot Options*). It usually does by default.

> **If you plan to run UniFi OS Server:** Ubiquiti recommends **not cloning**
> these VMs. Clones share remote-access tokens and behave unpredictably. Set up
> each installation from scratch.

---

## Part 4 – Create the VM on Hyper-V

In Hyper-V Manager: **Action → New → Virtual Machine**.

| Wizard page | Value |
| --- | --- |
| Name | e.g. `ubuntu-server` |
| Generation | **Generation 2** (UEFI) |
| Startup memory | **4096 MB**, **uncheck** "Use Dynamic Memory" |
| Networking | your virtual switch, ideally an **External** switch |
| Virtual hard disk | **32 GB** (dynamically expanding VHDX is fine) |
| Installation options | *Install an operating system from a bootable image file* → the **Ubuntu Server ISO** |

Then open the VM's **Settings** and change four things — the VM will not
install correctly without them:

1. **Security → Secure Boot: uncheck "Enable Secure Boot".**
   Ubuntu's ISO does not boot under Hyper-V's default Microsoft Windows
   template, and the boot-menu step in Part 5 needs the GRUB screen.

2. **SCSI Controller → Add → DVD Drive → Image file: `seed.iso`.**
   This is the second CD drive holding the seed data.

3. **Processor → Number of virtual processors: 2.**

4. **Firmware → Boot order: move the DVD drive with the Ubuntu ISO to the
   top.** (On Generation 2 VMs the hard disk is often first.)

Start the VM and open the console:

*Hyper-V Manager → right-click the VM → Connect → Start*

> **Hyper-V detail:** the network adapter is usually called `eth0` here. The
> shipped `user-data` already covers that (interface match `e*`), so DHCP works
> without any change. `open-vm-tools` in the package list does nothing on
> Hyper-V but is harmless — remove it from `packages` if you like, the
> integration services are already part of the kernel.

> **About UniFi OS Server on Hyper-V:** Ubiquiti's note that "installation in a
> Hyper-V guest is not supported" refers to the **Windows installer with WSL**.
> This project installs the **Linux installer** in a native Ubuntu VM, which is
> unproblematic under Hyper-V.

---

## Part 5 – Start the installation

Power the VM on and open its console. You get Ubuntu's **GRUB boot menu**.

Because the Ubuntu ISO is used unmodified, the installer needs to be told once
that it should run unattended. Pick **one** of these two ways:

### Way 1 – add the kernel parameter (recommended, fully unattended afterwards)

1. In the GRUB menu highlight **"Try or Install Ubuntu Server"** and press
   **`e`**.
2. Find the line starting with `linux ... /casper/vmlinuz ...` and append a
   space plus **`autoinstall`** at the **end** of that line.
3. Press **`Ctrl`+`X`** (or `F10`) to boot.

### Way 2 – confirm the prompt

Just let the VM boot normally. After a moment the installer asks

```
Continue with autoinstall? (yes|no)
```

Type **`yes`** and press Enter.

---

From here everything runs on its own: partitioning, package installation, user
creation, security updates, the MOTD changes and copying `get-scripts.sh` into
the home directory. The VM **reboots automatically** when it is finished.

Expect roughly **10–20 minutes**, mostly depending on how fast the security
updates download.

> After the reboot the VM may boot from the CD again. If it shows the GRUB menu
> a second time, disconnect both CD drives (or change the boot order) and reset
> the VM.

---

## Part 6 – First login

Find the IP address on the VM console (it is shown in the login banner) or in
your DHCP server's lease list, then connect:

```bash
ssh ubuntu-admin@<SERVER-IP>
```

| | |
| --- | --- |
| Hostname | `ubuntu` |
| User | `ubuntu-admin` |
| Password | `ubuntu` |

You are greeted by the project's own login message instead of Ubuntu's stock
notices:

```
=============== Ubuntu-Autoinstall - next steps ===============

This system was installed unattended. No maintenance or setup
scripts are installed yet - fetch them from GitHub when needed:

  sudo ~/get-scripts.sh            browse and run available scripts
  sudo ~/get-scripts.sh --list     just list what is available
  sudo ~/get-scripts.sh --all      download everything to ~/scripts

Recommended first step: change the default password
  sudo ~/get-scripts.sh change-password.sh

Project: https://github.com/sven-reichelt/Ubuntu-Autoinstall
```

The stock help text, package news and Ubuntu Pro/ESM advertising are disabled
permanently — including their sources, so a package update does not bring them
back.

---

## Part 7 – Fetch and run scripts

### 7.1 Change the password (do this first)

```bash
sudo ~/get-scripts.sh change-password.sh
```

The password `ubuntu` is public knowledge — it is in the repository and in
every `seed.iso`.

### 7.2 Set a static IP (optional)

```bash
sudo ~/get-scripts.sh configure-network.sh
```

The script asks for the interface, IP address, subnet mask or prefix, gateway
and DNS servers, then applies the change **on trial** for 60 seconds. If your
SSH session survives, press ENTER in that same window to make it permanent. If
the connection drops, do nothing — netplan restores the previous configuration
automatically and you reconnect on the old address.

### 7.3 Update the system

```bash
sudo ~/get-scripts.sh system-update.sh
```

### 7.4 Install an application

```bash
sudo ~/get-scripts.sh                # browse the menu
sudo ~/get-scripts.sh install-hfs.sh # HFS (HTTP File Server) in Docker
```

For UniFi OS Server, first copy the Linux (x64) download link from
<https://ui.com/download/releases/unifi-os-server> and pass it along:

```bash
sudo ~/get-scripts.sh install-unifi-os-server.sh "https://fw-download.ubnt.com/data/unifi-os-server/...-x64"
```

What each script does, and all of their options, is on the
[Scripts](Scripts.md) page.
