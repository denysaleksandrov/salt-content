# patching

Salt states for patching Linux and Windows minions.
Uses a `Patched` grain as a guard so already-patched systems are skipped on subsequent runs.

---

## Directory structure

```
patching/
├── init.sls    # Main patching state — runs upgrades and sets the Patched grain
└── status.sls  # Pre-flight check — inspects pending updates and sets the Patched grain
```

---

## How it works

### `status.sls`

Queries the system for pending updates without installing anything:

- **Linux** — calls `pkg.list_upgrades()`.
- **Windows** — calls `win_wua.list()` via the Windows Update Agent module.

Depending on the result, it sets a custom grain on the minion:

| Result | `Patched` grain |
|---|---|
| No updates available (empty dict or `0`) | `True` |
| Updates available | `False` |

Run `status.sls` before `init.sls` so that `init.sls` knows whether to skip the system.

### `init.sls`

Reads the `Patched` grain set by `status.sls` and acts accordingly:

- **`Patched: False`** — installs all available updates and then sets `Patched: True`.
  - Linux: `pkg.uptodate`
  - Windows: `wua.uptodate` (with automatic reboot enabled)
- **`Patched: True`** — skips patching and reports "System is up to date already" via a no-op test state.

---

## Usage

### Step 1 — Check patch status

Apply `status.sls` to all (or a targeted set of) minions to populate the `Patched` grain:

```bash
# All minions
salt '*' state.apply patching.status

# Specific group
salt -G 'role:webserver' state.apply patching.status
```

### Step 2 — Apply patches

Apply `init.sls` to the same target. Systems with `Patched: True` are skipped automatically:

```bash
# All minions
salt '*' state.apply patching

# Specific group
salt -G 'role:webserver' state.apply patching
```

### Run both in sequence (one-liner)

```bash
salt '*' state.apply patching.status && salt '*' state.apply patching
```

---

## Grain reference

| Grain | Type | Values | Set by |
|---|---|---|---|
| `Patched` | boolean | `True` / `False` | `status.sls`, `init.sls` |

To inspect the grain on a minion:

```bash
salt 'minion-id' grains.get Patched
```

To reset the grain (force re-patching on next run):

```bash
salt 'minion-id' grains.setval Patched False
```

---

## Platform support

| OS | Update mechanism | Reboot behaviour |
|---|---|---|
| Linux | `pkg.uptodate` | No automatic reboot |
| Windows | `wua.uptodate` | Reboots if required (`skip_reboot: False`) |

---

## Workflow summary

| Step | Command | Purpose |
|---|---|---|
| 1 | `state.apply patching.status` | Detect pending updates; set `Patched` grain |
| 2 | `state.apply patching` | Install updates on unpatched systems; skip patched ones |
