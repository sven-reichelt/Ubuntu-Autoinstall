# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-09-01

### Added

- Unattended Ubuntu Server installation (24.04 LTS and 26.04 LTS) via
  subiquity `autoinstall` and a NoCloud seed ISO.
- `autoinstall/build-seed-iso.sh` builds the seed ISO with `xorriso`,
  `genisoimage`, `mkisofs` or `hdiutil`.
- `scripts/get-scripts.sh` - script loader that is copied into the user's home
  during the installation and downloads the maintenance and setup scripts from
  this repository on demand. Interactive menu plus `--list`, `--all`,
  `--download-only`, `--self-update` and running a script by name.
- `scripts/manifest.txt` - list of scripts offered by the loader, with a
  fallback to the GitHub API when the manifest cannot be reached.
- `scripts/change-password.sh` - change the password of a local account, with
  hidden or plain-text entry.
- `scripts/configure-network.sh` - switch an interface between DHCP and a
  static IP using `netplan try` as a safety net.
- `scripts/system-update.sh` - `apt` update, full-upgrade, autoremove and
  autoclean plus a reboot-required check.
- `scripts/install-hfs.sh` - install or update HFS (HTTP File Server) as a
  Docker container with host networking, a configurable port and a compose
  file in `/opt/hfs`.
- `scripts/install-unifi-os-server.sh` - install or update UniFi OS Server via
  Podman from a download URL supplied by the user.
- Custom MOTD that replaces the stock Ubuntu notices and points at the script
  loader.
- `validate.sh` - `bash -n`, ShellCheck, autoinstall YAML validation and a
  consistency check between `scripts/manifest.txt` and `scripts/*.sh`.
- GitHub Actions: `ci.yml` runs the validation on every push and pull request;
  `release.yml` builds `seed.iso`, creates a SHA-256 checksum and attaches both
  to a GitHub release when a `v*` tag is pushed.
- Documentation: `README.md` as the central entry point plus
  `docs/INSTALLATION.md` with the step-by-step VM setup for VMware ESXi and
  Microsoft Hyper-V.

[Unreleased]: https://github.com/sven-reichelt/Ubuntu-Autoinstall/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/sven-reichelt/Ubuntu-Autoinstall/releases/tag/v1.0.0
