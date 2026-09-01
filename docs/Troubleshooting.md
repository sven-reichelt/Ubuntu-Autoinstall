# Troubleshooting

Common problems during and after the installation.

- [Installation](#installation)
- [Network](#network)
- [Script loader](#script-loader)
- [Scripts](#scripts)

---

## Installation

### The installer asks for a language / keyboard layout — nothing is automated

The seed data was not found. Check, in this order:

- Is `seed.iso` attached as a **second** CD drive and **connected**? On ESXi the
  *Connect at power on* checkbox is the usual culprit; on Hyper-V the DVD drive
  must be added to the SCSI controller.
- Was the ISO built with the volume label `CIDATA`? `build-seed-iso.sh` sets it;
  a manually built ISO with a different label is not recognised as a NoCloud
  datasource.
- Did you take Way 1 or Way 2 in
  [Installation → Part 5](Installation.md#part-5--start-the-installation)?
  Without the `autoinstall` kernel parameter or a `yes` at the prompt, the
  installer runs interactively.

### The VM does not boot from the CD / goes straight to the EFI shell

- Check the boot order: the DVD drive with the Ubuntu ISO must be first.
- **Hyper-V:** Secure Boot must be **off** (Settings → Security).
- **ESXi:** firmware should be UEFI; make sure the ISO is actually attached and
  not just selected.

### "Continue with autoinstall?" appears every time

That is expected when the Ubuntu ISO is used unmodified — see
[Installation → Part 5](Installation.md#part-5--start-the-installation). Either
answer `yes` or add the `autoinstall` kernel parameter in GRUB. Remastering the
Ubuntu ISO to avoid this is deliberately out of scope for this project.

### After the reboot the installer starts again

The VM booted from the CD again. Disconnect both CD drives (ESXi: uncheck
*Connected*; Hyper-V: set the DVD drives to *None*) or move the hard disk to the
top of the boot order, then reset the VM.

### The installation aborts / the disk is not partitioned

Check the disk size — `storage.layout.name: direct` needs a disk it can use
exclusively. On a very small disk (below ~10 GB) the installer runs out of room
once the security updates are pulled in.

---

## Network

### No IP address / no network

- Is the VM's network adapter connected to a working switch or port group?
- On Hyper-V an **Internal** or **Private** switch has no DHCP server — use an
  **External** switch or configure a static IP with
  [`configure-network.sh`](Scripts.md#configure-networksh).
- Check on the VM console:

  ```bash
  ip -4 addr
  ip route
  resolvectl status
  ```

### I lost the SSH connection after configure-network.sh

Nothing is broken. `netplan try` rolls back after 60 seconds — reconnect using
the **old** IP address and start the script again with corrected values.

If you can only reach the machine through the hypervisor console, the previous
netplan files are in `/etc/netplan/configure-network.orig/`.

### The static IP is not applied / DHCP comes back after a reboot

Something else is writing netplan configuration. Check what is in the
directory:

```bash
ls -l /etc/netplan/
sudo netplan get
```

Only `90-autoinstall-network.yaml` should be there.
`configure-network.sh` moves competing files aside and disables cloud-init's
network management, so this normally cannot happen — unless a file was restored
by hand or `cloud-init clean` was run without the disable file in place.

---

## Script loader

### get-scripts.sh: "Could not reach GitHub"

The system has no working internet connection or DNS. Test it:

```bash
ping -c3 1.1.1.1                          # is there any connectivity?
getent hosts raw.githubusercontent.com    # does DNS resolve?
curl -I https://raw.githubusercontent.com # is HTTPS reachable?
```

Fix the network first ([`configure-network.sh`](Scripts.md#configure-networksh)
or your firewall), then run the loader again.

### get-scripts.sh is missing from the home directory

The late-command could not copy it. This happens if the seed ISO was built
without the loader, or if `identity.username` and `TARGET_USER` in `user-data`
do not match — see
[Configuration → Changing the user name](Configuration.md#changing-the-user-name).
Rebuild the seed ISO after running `./validate.sh`, which checks exactly that.

As a stopgap, fetch the loader directly:

```bash
curl -fsSL -o ~/get-scripts.sh \
  https://raw.githubusercontent.com/sven-reichelt/Ubuntu-Autoinstall/main/scripts/get-scripts.sh
chmod +x ~/get-scripts.sh
```

### "Downloaded file is not a shell script"

The download returned something else — usually a GitHub error page or a captive
portal login page. Check the URL by hand:

```bash
curl -fsSL https://raw.githubusercontent.com/sven-reichelt/Ubuntu-Autoinstall/main/scripts/manifest.txt
```

If you are running a fork, make sure `REPO_OWNER` in the loader points at it.

### The menu lists scripts without descriptions

The manifest could not be read and the loader fell back to the GitHub API. The
downloads still work. It usually means a transient network problem or that
`scripts/manifest.txt` is missing in the repository the loader points at.

---

## Scripts

### install-hfs.sh: the port is already in use

HFS runs with host networking, so it cannot share a port. Check what holds it:

```bash
sudo ss -ltnp 'sport = :80'
```

Then either stop that service or run the script again with a different port:

```bash
sudo ~/scripts/install-hfs.sh --port 8080
```

### install-hfs.sh: the web interface does not answer

```bash
docker compose -f /opt/hfs/docker-compose.yml ps
docker compose -f /opt/hfs/docker-compose.yml logs -f
```

A first start can take a moment while the image initialises `/opt/hfs/data`.

### install-hfs.sh: I cannot log in to the Admin-panel

HFS creates accounts through the Admin-panel only from localhost, and it lets
the panel be opened without credentials from there — so over the network you get
a login prompt with no account behind it. The script seeds the account through
HFS's `create-admin` entry; if that did not work, the entry is still sitting in
the configuration file:

```bash
grep create-admin /opt/hfs/data/config.yaml
```

If it is still there, the container is not running or not reading the file:

```bash
docker compose -f /opt/hfs/docker-compose.yml ps
docker compose -f /opt/hfs/docker-compose.yml logs -f
```

HFS reloads `config.yaml` as soon as it changes, so once the container runs the
account appears and the entry disappears by itself.

### install-hfs.sh: I forgot the admin password

Add the entry again and save — no restart needed:

```bash
echo "create-admin: 'new-password'" | sudo tee -a /opt/hfs/data/config.yaml
```

Quote the password in single quotes, and double any single quote inside it
(`it's` → `'it''s'`).

### docker: permission denied

The user was added to the `docker` group, but group membership only takes effect
after a new login. Log out and back in, or use `sudo docker ...` in the
meantime.

### install-unifi-os-server.sh: "the service 'uosserver' was not found"

The installation failed. Look at `/var/log/unifi-install.log` for the installer
output. The usual causes:

- the download URL expired or was copied incompletely — get a fresh one from
  <https://ui.com/download/releases/unifi-os-server>,
- too little RAM (give the VM 4 GB),
- not enough free disk space (the script needs ~2 GB just for the download).

### install-unifi-os-server.sh: the web interface does not answer

The first start is slow on weak hardware. Check the service and try again in a
few minutes:

```bash
systemctl status uosserver
```

### uosserver commands say "permission denied"

Same as with Docker: the `uosserver` group membership needs a fresh login.
