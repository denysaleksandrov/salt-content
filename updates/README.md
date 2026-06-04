# updates

Salt state for upgrading or downgrading the `salt-minion` package on **RHEL** and **Windows** systems.

Handles platform-specific quirks: service masking on RHEL to prevent DNF from restarting the minion mid-run, installer-type detection on Windows (MSI vs EXE), and a delayed background restart so the minion can return a result before the service drops.

---

## Directory structure

```
salt-content/
├── _grains/
│   └── installer_type.py   # Custom grain: detects MSI vs EXE installer on Windows
└── updates/
    └── update.sls          # Main state: upgrades or downgrades salt-minion
```

---

## Prerequisites

### 1 — Deploy the custom grain (Windows only)

`_grains/installer_type.py` must be present on the Salt master so it can be synced to Windows minions.
Deploy path on master: `/srv/salt/_grains/installer_type.py`

Sync the grain to all Windows minions:

```bash
salt -G 'os:Windows' saltutil.sync_grains
```

Verify:

```bash
salt -G 'os:Windows' grains.get installer_type
# Expected output: msi  or  exe
```

The grain inspects `HKLM\Software\Microsoft\Windows\CurrentVersion\Uninstall` (both 32-bit and 64-bit hive paths) for a `Salt Minion` entry and reads the `WindowsInstaller` registry value (or falls back to the `UninstallString`) to determine the installer type.

### 2 — Populate the Windows package repository

The state uses Salt's WinRepo to resolve Windows package names. Refresh the repo before running updates:

```bash
salt-run winrepo.update_git_repos
salt -G 'os:Windows' pkg.refresh_db
```

---

## How it works

### RHEL

| Step | State ID | What it does |
|---|---|---|
| 1 | `mask_service_to_prevent_rpm_restart` | Masks `salt-minion` so RPM/DNF scriptlets cannot restart it during install |
| 2 | `install_or_downgrade_minion` | Installs target version via `dnf install -y salt-<ver> salt-minion-<ver>` |
| 3 | `unmask_service_after_install` | Unmasks `salt-minion` |
| 4 | `schedule_delayed_restart` | Schedules a background `systemctl restart salt-minion` after a 15-second delay so the minion can return a result first |

**Logic switch** — when `target_version` is `latest`, uses `pkg.uptodate`; when a specific version is given, uses a raw `dnf install` command to work around Salt's `pkg` module dependency-resolution issues on RHEL.

### Windows

| Step | State ID | What it does |
|---|---|---|
| 1 | *(Jinja)* | Reads the `installer_type` grain; if missing, queries the registry via PowerShell at render time |
| 2 | *(Jinja)* | Selects the WinRepo package name: `salt-minion-msi-py3` (MSI) or `salt-minion-py3` (EXE) |
| 3 | `install_or_downgrade_minion` | Calls `pkg.install` via `module.run` to force execution and bypass state idempotency issues during downgrades |
| 4 | `schedule_delayed_restart` | Schedules a background `Restart-Service salt-minion` after a 30-second delay |

**Version pinning** — if `target_version` is omitted (`latest`), Windows is pinned to `3006.25` to avoid unintentional upgrades to the 3007.x branch.

---

## Usage

### Upgrade to a specific version

```bash
# RHEL
salt -G 'os_family:RedHat' state.sls updates.update pillar='{"target_version": "3006.17"}'

# Windows
salt -G 'os:Windows' state.sls updates.update pillar='{"target_version": "3006.25"}'

# Single minion
salt 'minion-id' state.sls updates.update pillar='{"target_version": "3006.25"}'
```

### Upgrade to latest (RHEL only — Windows pins to 3006.25)

```bash
salt -G 'os_family:RedHat' state.sls updates.update
```

### Downgrade

Pass the older version as `target_version` — the same command handles both directions:

```bash
salt 'minion-id' state.sls updates.update pillar='{"target_version": "3006.14"}'
```

---

## Expected behaviour during execution

The minion **will disconnect** briefly during the delayed service restart. This is expected. The master will report `Minion did not return. [Not connected]` — wait ~30–60 seconds and verify with:

```bash
salt '*' test.ping
salt -G 'os:Windows' test.version
```

---

## Package names (WinRepo)

| Installer type | WinRepo package name |
|---|---|
| EXE (`.exe` setup) | `salt-minion-py3` |
| MSI (`.msi`) | `salt-minion-msi-py3` |

The correct name is selected automatically from the `installer_type` grain.

---

## Grain reference

| Grain | OS | Values | Set by |
|---|---|---|---|
| `installer_type` | Windows only | `msi` / `exe` / `undetermined-exe` | `_grains/installer_type.py` |

---

## File locations on master

```
/srv/salt/
├── _grains/
│   └── installer_type.py
└── updates/
    └── update.sls
```
