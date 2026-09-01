# Configuration

Everything that shapes the installed system lives in
[`autoinstall/user-data`](../autoinstall/user-data). Edit it **before** building
the seed ISO — a `seed.iso` downloaded from a release always carries the
defaults.

- [What can be changed](#what-can-be-changed)
- [Password and SSH](#password-and-ssh)
- [Locale, keyboard, timezone](#locale-keyboard-timezone)
- [Network](#network)
- [Disk layout and packages](#disk-layout-and-packages)
- [Changing the user name](#changing-the-user-name)
- [Adding your own script](#adding-your-own-script)
- [Running a fork](#running-a-fork)

---

## What can be changed

| What | Where | Default |
| --- | --- | --- |
| Hostname | `identity.hostname` | `ubuntu` |
| Display name | `identity.realname` | `Ubuntu Server` |
| User name | `identity.username` **and** `TARGET_USER` in `late-commands` | `ubuntu-admin` |
| Password | `identity.password` (SHA-512 hash) | `ubuntu` |
| SSH key | `ssh.authorized-keys` | not set |
| Password login | `ssh.allow-pw` | `true` |
| Locale | `locale` | `de_DE.UTF-8` |
| Keyboard | `keyboard.layout` | `de` |
| Timezone | `timezone` | `Europe/Berlin` |
| Network | `network` | DHCP on every `e*` interface |
| Disk layout | `storage.layout.name` | `direct` (one large root partition) |
| Packages | `packages` | `curl`, `ca-certificates`, `open-vm-tools` |
| MOTD | the `99-custom` block in `late-commands` | points at the script loader |

After every change:

```bash
./validate.sh                       # catches the common mistakes
cd autoinstall && ./build-seed-iso.sh
```

---

## Password and SSH

Generate your own hash and paste the complete `$6$...` string into
`identity.password`:

```bash
openssl passwd -6 'YOUR-PASSWORD'
```

Better still, use an SSH key and turn password login off:

```yaml
ssh:
  install-server: true
  allow-pw: false
  authorized-keys:
    - "ssh-ed25519 AAAA... your-key"
```

> The shipped password `ubuntu` is a bootstrap credential, not a secret — it is
> in this repository and in every released `seed.iso`. See
> [SECURITY.md](../SECURITY.md) for the reasoning and the full list of options.

---

## Locale, keyboard, timezone

```yaml
locale: en_US.UTF-8
keyboard:
  layout: us
timezone: Europe/London
```

The keyboard layout also applies to the login console, which matters when a
password contains special characters. If you get that wrong,
[`change-password.sh`](Scripts.md#change-passwordsh) has a plain-text entry mode
that shows you what actually arrived.

---

## Network

The default gives every ethernet interface DHCP. The match `e*` deliberately
covers both VMware (`ens*`, `enp*`) and Hyper-V (`eth0`):

```yaml
network:
  version: 2
  ethernets:
    anyeth:
      match:
        name: "e*"
      dhcp4: true
```

For a static IP at install time, comment that block out and use the alternative
below it in the file:

```yaml
network:
  version: 2
  ethernets:
    ens160:
      dhcp4: false
      addresses: [192.168.1.50/24]
      routes:
        - to: default
          via: 192.168.1.1
      nameservers:
        addresses: [192.168.1.1, 1.1.1.1]
```

Note that this hard-codes the interface name, which differs between
hypervisors. For an already installed system
[`configure-network.sh`](Scripts.md#configure-networksh) is the easier route —
it detects the interface and rolls back automatically if the change locks you
out.

---

## Disk layout and packages

`storage.layout.name: direct` uses the whole disk with one large root
partition — simple and robust. For LVM:

```yaml
storage:
  layout:
    name: lvm
```

The package list is deliberately minimal. It contains only what the loader
needs plus the VMware guest tools:

```yaml
packages:
  - curl
  - ca-certificates
  - open-vm-tools
```

Everything else is installed by the scripts that need it — `install-hfs.sh`
brings Docker, `install-unifi-os-server.sh` brings Podman. On Hyper-V,
`open-vm-tools` does nothing and can be removed; the integration services are
already part of the kernel.

---

## Changing the user name

The user name appears in **two** places that must stay in sync:

1. `identity.username`
2. `TARGET_USER="ubuntu-admin"` in the `late-commands` block (twice)

If they drift apart, the loader is copied into a home directory that does not
exist and the installed system comes up without `get-scripts.sh`.
`validate.sh` checks exactly this and fails if it finds a mismatch.

---

## Adding your own script

1. Put the script into [`scripts/`](../scripts). Conventions:
   `#!/usr/bin/env bash`, `set -euo pipefail`, comments in English and ASCII
   only, a root check at the top, idempotent where possible.
2. Add one line to [`scripts/manifest.txt`](../scripts/manifest.txt):

   ```
   my-script.sh|Short description shown in the menu
   ```

3. Add a section to [Scripts](Scripts.md) and an entry to
   [CHANGELOG.md](../CHANGELOG.md).
4. Run `./validate.sh` and commit.

That is all. **No new seed ISO is needed** — every already-installed system sees
the new script the next time `get-scripts.sh` runs.

`validate.sh` (and the CI) enforces that the manifest and the directory stay in
sync in both directions: a listed script must exist, and an existing script must
be listed. The loader itself must *not* appear in the manifest.

---

## Running a fork

The loader downloads from a fixed repository. If you fork the project, change
the configuration block at the top of
[`scripts/get-scripts.sh`](../scripts/get-scripts.sh):

```bash
REPO_OWNER="your-name"
REPO_NAME="Ubuntu-Autoinstall"
REPO_BRANCH="main"
```

Also adjust the project URL in the MOTD block of `user-data`, then rebuild the
seed ISO. Systems that were installed from an older ISO keep pointing at the old
repository — on those, replace `~/get-scripts.sh` by hand or run
`--self-update` after changing the source.
