# Development

How the repository is laid out, what is checked before a commit, and how a
release is cut.

- [Repository layout](#repository-layout)
- [Conventions](#conventions)
- [Validation](#validation)
- [Continuous integration](#continuous-integration)
- [Documentation and the wiki](#documentation-and-the-wiki)
- [Cutting a release](#cutting-a-release)

---

## Repository layout

```
.
├── README.md                          landing page
├── CHANGELOG.md                       version history (Keep a Changelog)
├── SECURITY.md                        security policy and the default credentials
├── LICENSE                            GNU GPL v3
├── validate.sh                        all checks (bash -n, ShellCheck, YAML, manifest)
├── .github/
│   ├── scripts/build-wiki.sh          renders docs/ into wiki pages
│   └── workflows/
│       ├── ci.yml                     validation on every push and pull request
│       ├── release.yml                builds seed.iso and publishes the release
│       └── wiki.yml                   mirrors docs/ into the GitHub wiki
├── autoinstall/
│   ├── user-data                      autoinstall configuration - the heart of it
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
└── docs/                              documentation source, mirrored to the wiki
    ├── README.md                      -> wiki Home
    ├── Installation.md
    ├── Scripts.md
    ├── Configuration.md
    ├── Troubleshooting.md
    └── Development.md
```

---

## Conventions

**Shell scripts**

- `#!/usr/bin/env bash` and `set -euo pipefail`.
- A root check at the top when the script needs privileges.
- Comments in English, **ASCII only** — no umlauts or typographic characters,
  to avoid encoding surprises on a freshly installed system.
- A header block explaining what the script does, how it is called and why the
  non-obvious parts are the way they are.
- Idempotent where possible: detect an existing installation and update it.
- `|| true` only where failure is genuinely acceptable, with a comment.

**Ubuntu versions**

24.04 LTS and 26.04 LTS are supported side by side. `user-data` is deliberately
version-neutral — never hard-code a release or a codename. Where a third party
forces a codename (the Docker repository in `install-hfs.sh`), probe for it and
fall back.

**Line endings**

`.gitattributes` forces LF for `*.sh`, `user-data`, `meta-data` and
`manifest.txt`. A shell script committed with CRLF fails to run on Ubuntu.

**Never commit** built ISOs, virtual disks or real secrets — `.gitignore`
covers the usual suspects, but it is a safety net, not a substitute for looking
at what you stage.

---

## Validation

```bash
./validate.sh
```

It runs four groups of checks and reports every problem before exiting
non-zero:

1. **`bash -n`** on every `*.sh` in the repository.
2. **ShellCheck** (`-e SC1091`), skipped with a note if it is not installed.
3. **Autoinstall YAML**: `user-data` and `meta-data` must parse; the mandatory
   keys must be present; `identity.password` must be a `$6$` SHA-512 hash; and
   `TARGET_USER` in `late-commands` must match `identity.username`.
   Uses Python with PyYAML, falling back to Node (`npx yaml`) on machines
   without it — for example Git Bash on Windows.
4. **Manifest consistency**: every entry in `scripts/manifest.txt` must have a
   matching file with a description, every script in `scripts/` must be listed,
   and the loader must not be listed.

---

## Continuous integration

| Workflow | Trigger | What it does |
| --- | --- | --- |
| [`ci.yml`](../.github/workflows/ci.yml) | push to `main`, pull request, manual | Installs PyYAML and ShellCheck, runs `validate.sh`. |
| [`release.yml`](../.github/workflows/release.yml) | `v*` tag, manual with a tag input | Validates, builds `seed.iso`, creates a SHA-256 checksum, extracts the release notes from `CHANGELOG.md` and publishes both files as release assets. |
| [`wiki.yml`](../.github/workflows/wiki.yml) | push to `main` touching `docs/`, manual | Renders `docs/` into wiki pages and pushes them to the wiki repository. |

The seed ISO is built **only** for releases, not on every commit — that keeps
the Actions minutes down. `release.yml` runs the full validation first, so a
broken tag fails before anything is published.

---

## Documentation and the wiki

`docs/` is the single source of truth. The wiki is a **mirror** — direct edits
there are overwritten by the next sync.

[`.github/scripts/build-wiki.sh`](../.github/scripts/build-wiki.sh) renders the
pages:

- `docs/README.md` becomes the wiki `Home`, every other `docs/*.md` keeps its
  name as the page name.
- Links to sibling pages lose their `.md` suffix (`Scripts.md` → `Scripts`),
  because that is how the wiki resolves them.
- Links pointing out of `docs/` (`../autoinstall/user-data`) become absolute
  URLs into the repository, so they still work from the wiki.
- `_Sidebar.md` and `_Footer.md` are generated from a fixed page order in the
  script. Adding a page to `docs/` without adding it to that order makes the
  script fail — the same "both directions must agree" idea as the script
  manifest.

Render the pages locally to see what the wiki will get:

```bash
.github/scripts/build-wiki.sh /tmp/wiki-preview
ls /tmp/wiki-preview
```

> The wiki repository (`<repo>.wiki.git`) only exists once a first page has been
> created through the GitHub web interface. Until then the sync workflow fails
> with a clear message. This is a one-time manual step per repository.

Keep `README.md`, `docs/` and `CHANGELOG.md` in sync when behaviour changes.

---

## Cutting a release

1. Move the entries from `## [Unreleased]` into a new version section in
   `CHANGELOG.md`, with the release date, and update the link definitions at
   the bottom of the file.
2. Commit and push to `main`, and wait for the CI to go green.
3. Tag and push:

   ```bash
   git tag -a v1.1.0 -m "Release 1.1.0"
   git push origin v1.1.0
   ```

`release.yml` does the rest. Tags containing `-rc` or `-beta` are published as
pre-releases.

To rebuild the assets of an existing release, start the workflow manually and
pass the tag name.

Verifying a published ISO:

```bash
sha256sum -c seed.iso.sha256
```
