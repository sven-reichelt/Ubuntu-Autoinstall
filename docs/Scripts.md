# Scripts

The installed system carries exactly one script: the loader `get-scripts.sh`.
Everything else lives in this repository and is downloaded when you ask for it.

- [The script loader](#the-script-loader)
- [Available scripts](#available-scripts)
  - [change-password.sh](#change-passwordsh)
  - [configure-network.sh](#configure-networksh)
  - [system-update.sh](#system-updatesh)
  - [install-hfs.sh](#install-hfssh)
  - [install-unifi-os-server.sh](#install-unifi-os-serversh)

---

## The script loader

`get-scripts.sh` is copied into the user's home directory during the
installation. It reads the list of available scripts from
[`scripts/manifest.txt`](../scripts/manifest.txt), downloads what you pick into
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

The interactive menu:

```
== Ubuntu-Autoinstall - script loader ==
   target directory: /home/ubuntu-admin/scripts

Available scripts (https://github.com/sven-reichelt/Ubuntu-Autoinstall):

   1) change-password.sh           Change the password of a local user account
   2) configure-network.sh         Switch a network interface between DHCP and a static IP
   3) system-update.sh             Update all packages (apt update / full-upgrade / autoremove)
   4) install-hfs.sh               Install or update HFS (HTTP File Server) in Docker
   5) install-unifi-os-server.sh   Install or update UniFi OS Server

   a) download all      r) refresh list      q) quit

Selection:
```

### How it behaves

- **Always current.** Downloads come from the `main` branch, so running the
  loader again is also how you update a script.
- **Correct ownership.** Files land in the home directory of the user who
  invoked `sudo`, not in `/root`, and belong to that user.
- **Offline-safe listing.** If `scripts/manifest.txt` cannot be reached, the
  loader falls back to the GitHub API and lists the `*.sh` files in `scripts/`
  directly (without descriptions).
- **Sanity checks.** A download is rejected if the file is empty or does not
  start with a shebang, so an error page never ends up being executed.
- **Names without the suffix work too:** `sudo ~/get-scripts.sh system-update`.

To point the loader at your own fork, see
[Configuration → Running a fork](Configuration.md#running-a-fork).

---

## Available scripts

Every script requires root (`sudo`) and says so if started without it. Each one
is safe to run again: an existing installation is detected and updated instead
of duplicated. Where a log makes sense, it is written to `/var/log/`.

| Script | Log | What it does |
| --- | --- | --- |
| [`change-password.sh`](#change-passwordsh) | — | Change the password of a local account |
| [`configure-network.sh`](#configure-networksh) | — | Switch an interface between DHCP and a static IP |
| [`system-update.sh`](#system-updatesh) | `/var/log/system-update.log` | Update all packages |
| [`install-hfs.sh`](#install-hfssh) | `/var/log/hfs-install.log` | HFS (HTTP File Server) in Docker |
| [`install-unifi-os-server.sh`](#install-unifi-os-serversh) | `/var/log/unifi-install.log` | UniFi OS Server via Podman |

---

### change-password.sh

Changes the password of a local account.

```bash
sudo ~/get-scripts.sh change-password.sh          # the sudo user
sudo ~/scripts/change-password.sh <username>      # someone else
```

It offers two ways to type the new password:

1. **Hidden entry** via `passwd` — the default, and what you normally want.
2. **Plain-text entry** — for the case where the keyboard layout garbles
   special characters and you want to see what actually arrived. The script
   asks twice and prints the result at the end.

---

### configure-network.sh

Switches an interface between DHCP and a static IP and writes the netplan
configuration.

```bash
sudo ~/get-scripts.sh configure-network.sh
```

It asks for the interface (skipped when there is only one), then for DHCP or a
static IP with address, subnet mask *or* prefix, gateway and up to two DNS
servers, shows a summary, and applies the change.

#### Why it moves other netplan files aside

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

#### The safety net

`netplan try` applies the change for **60 seconds**. Confirm with ENTER in the
same window; if the SSH session dies, do nothing and netplan rolls back. The
script additionally restores the previous *files*, because `netplan try` only
rolls back the running connection — otherwise a reboot would activate the
unconfirmed configuration after all.

---

### system-update.sh

Updates every package on the system.

```bash
sudo ~/get-scripts.sh system-update.sh          # ask before rebooting
sudo ~/scripts/system-update.sh --reboot        # reboot automatically if needed
sudo ~/scripts/system-update.sh --no-reboot     # never reboot, only report
```

Runs `apt-get update`, `full-upgrade`, `autoremove --purge` and `autoclean`,
then reports whether a reboot is required and which packages caused it.

`full-upgrade` is used on purpose: a plain `upgrade` silently holds back updates
that need to install or remove packages, such as a new kernel ABI. Existing
configuration files are kept without asking
(`--force-confdef` / `--force-confold`).

---

### install-hfs.sh

Installs [HFS](https://rejetto.com/hfs) (HTTP File Server) as a Docker
container, including Docker itself.

```bash
sudo ~/get-scripts.sh install-hfs.sh                  # asks for port and password
sudo ~/scripts/install-hfs.sh --port 8080             # port set, still asks for the password
sudo ~/scripts/install-hfs.sh --admin-password 'secret' --port 8080
sudo ~/scripts/install-hfs.sh --shares /srv/data --yes # generates a random password
```

| | |
| --- | --- |
| Compose file | `/opt/hfs/docker-compose.yml` |
| Configuration and logs | `/opt/hfs/data` (mounted as `/data`) |
| Shared files | `/srv/hfs/shares` (mounted as `/shares`, override with `--shares`) |
| Port | asked interactively, default `80`, set via `HFS_PORT` |
| Networking | `network_mode: host` |
| Restart policy | `unless-stopped` |
| Admin account | `admin`, password asked interactively |

**Docker** comes from the official Docker repository (`docker-ce` plus the
compose plugin). If Docker publishes no suite for the running Ubuntu release
yet, the script falls back to the newest LTS suite, and if the repository is
unreachable altogether, to Ubuntu's own `docker.io` packages. The invoking user
is added to the `docker` group — that takes effect after the next login.

**Host networking** is what the HFS Docker wiki recommends: it is the only way
HFS sees the real client IP addresses in its log. The price is that there is no
port mapping, so the chosen port must be free on the host — the script warns if
it is not.

#### The admin account

HFS only lets you create an account through the Admin-panel **from localhost**,
and it lets the Admin-panel be opened without credentials from localhost too
(`localhost_admin`, default `true`). On a headless server that is precisely
where you are not: you reach the panel over the network, it asks for a login,
and there is no account to log in with.

The way out is a special configuration entry that HFS understands:

```yaml
create-admin: <password>
```

HFS reloads `config.yaml` as soon as it changes, creates the account, and
**removes that entry again** — so the password does not stay on disk in clear
text. The script does this for you:

- On a fresh installation it writes `/opt/hfs/data/config.yaml` before the first
  start, with your password and the `/shares` entry the image would create
  itself.
- If a `config.yaml` exists but holds no account, it appends the entry — that is
  the case if a container was started before without an account being set up.
- If an account already exists, it is left untouched.

Afterwards the script waits until the entry has disappeared and an `accounts:`
section is there, and reports the result. If that does not happen within 60
seconds it says so instead of claiming success on a server you cannot
administer.

To reset a forgotten password, add the line yourself and save — HFS picks it up
while running:

```bash
echo "create-admin: 'new-password'" | sudo tee -a /opt/hfs/data/config.yaml
```

Everyday commands:

```bash
docker compose -f /opt/hfs/docker-compose.yml ps
docker compose -f /opt/hfs/docker-compose.yml logs -f
docker compose -f /opt/hfs/docker-compose.yml restart
sudo ~/scripts/install-hfs.sh                 # pull a new image and recreate
```

Running the script again keeps the configured port and everything under
`/opt/hfs/data`.

---

### install-unifi-os-server.sh

Installs or updates
[UniFi OS Server](https://ui.com/download/releases/unifi-os-server) via Podman.

Ubiquiti publishes **no stable "latest" URL** for the Linux installer — the file
name contains the version plus a checksum and changes with every release. You
therefore pass the download link to the script:

1. Open <https://ui.com/download/releases/unifi-os-server>
2. Right-click the download of the **Linux (x64)** entry
3. Choose *Copy link address*

```bash
sudo ~/get-scripts.sh install-unifi-os-server.sh "https://fw-download.ubnt.com/data/unifi-os-server/...-x64"

# or as an environment variable
sudo UOS_URL="https://..." ~/scripts/install-unifi-os-server.sh

# or without an argument - the script asks for the URL
sudo ~/scripts/install-unifi-os-server.sh
```

The script installs `podman` and `slirp4netns`, downloads the installer to
`/var/tmp` (not `/tmp`, which is a RAM-backed tmpfs on some releases and too
small), sanity-checks the download, runs it, verifies that the `uosserver`
service exists afterwards, adds the user to the `uosserver` group, enables the
service and waits up to five minutes for the web interface.

The web interface is then at `https://<SERVER-IP>:11443` — the certificate
warning is expected.

To update, run the script again with a new download URL. It detects the existing
installation and the installer upgrades it in place.
