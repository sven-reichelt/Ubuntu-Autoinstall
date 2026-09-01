# Security Policy

## Supported versions

Only the latest release on the `main` branch receives fixes.

| Version        | Supported |
| -------------- | --------- |
| latest release | yes       |
| older releases | no        |

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Use GitHub's private reporting instead:
**[Report a vulnerability](https://github.com/sven-reichelt/Ubuntu-Autoinstall/security/advisories/new)**
(repository → *Security* → *Advisories* → *Report a vulnerability*).

Please include:

- a description of the problem and its impact,
- the steps to reproduce it,
- the affected file(s) and the release or commit you tested.

You will normally get a first response within 14 days. Please give the fix a
reasonable amount of time before disclosing the issue publicly.

## What this project ships - and what it deliberately does not

This repository contains **no secrets, no private keys and no personal
credentials**, and none must ever be committed. `.gitignore` blocks the usual
suspects (`*.key`, `*.pem`, `id_rsa*`, `id_ed25519*`, `*.local`, built ISO
images and virtual disks), but that is a safety net, not a substitute for
checking what you commit.

### Known-by-design: the default credentials

`autoinstall/user-data` contains a **publicly known default password** so that
the installation can run completely unattended and you can log in afterwards:

| | |
| --- | --- |
| User | `ubuntu-admin` |
| Password | `ubuntu` |
| Hash | SHA-512 crypt (`$6$...`) in `identity.password` |

This is a bootstrap credential, not a secret. Anyone who has the repository or
a built `seed.iso` knows it.

**Consequences you must plan for:**

1. **Change the password immediately after the first login:**

   ```bash
   sudo ~/get-scripts.sh change-password.sh
   ```

2. **Do not install the VM on an untrusted network** while the default
   password is still active. SSH password login is enabled by default.

3. **Better: replace the credential before building the ISO.** Generate your
   own hash and put it into `autoinstall/user-data`:

   ```bash
   openssl passwd -6 'YOUR-PASSWORD'
   ```

   Never commit that modified file to a public fork.

4. **Best: use an SSH key.** In `autoinstall/user-data` add your public key
   under `ssh.authorized-keys` and set `allow-pw: false`:

   ```yaml
   ssh:
     install-server: true
     allow-pw: false
     authorized-keys:
       - "ssh-ed25519 AAAA... your-key"
   ```

### Scripts are downloaded over the network

`get-scripts.sh` fetches scripts over HTTPS from
`raw.githubusercontent.com/sven-reichelt/Ubuntu-Autoinstall` and runs them with
root privileges. TLS certificate validation is enforced (`curl -fsSL` without
`-k`), and downloads are rejected unless they start with a shebang. There is no
signature verification beyond that, so:

- run the loader only against a repository you trust,
- if you fork the project, change `REPO_OWNER` in `scripts/get-scripts.sh` to
  point at **your** fork.

### Third-party software

`install-hfs.sh` and `install-unifi-os-server.sh` install software from third
parties (Docker CE, the `rejetto/hfs` container image, the UniFi OS Server
installer). Their security is the responsibility of those projects.

`install-hfs.sh` asks for the password of the HFS `admin` account and seeds it
through HFS's `create-admin` configuration entry, which HFS removes again once
the account exists. The password is therefore in `/opt/hfs/data/config.yaml` in
clear text only for the moment between writing it and HFS reading it. With
`--yes` the script generates a random password and prints it once — there is no
way to retrieve it afterwards, so write it down.

Note that HFS serves the Admin-panel without credentials to requests from
localhost (`localhost_admin`, default `true`). Anyone with shell access to the
server can therefore reach the panel through `http://127.0.0.1:<port>/~/admin`.
Set `localhost_admin: false` in `config.yaml` if that is not acceptable.
