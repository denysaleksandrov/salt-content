# switch_masters

Salt orchestration state for migrating minions from one Salt master to another.
Supports both Linux and Windows minions.

---

## Directory structure

```
switch_masters/
├── init.sls                # Orchestration entry point — iterates over minions
├── map.yaml                # Reference example of the minions.yaml structure
├── move_minions_map.sls    # Per-minion state: update config and restart service
└── files/
    ├── maptmpl.yaml        # Jinja template used to render minions.yaml
    └── minionids.sls       # Optional: auto-generates minions.yaml from all up minions
```

---

## How it works

For each minion ID listed in `files/minions.yaml`, the orchestration:

1. Deletes the cached master public key (`minion_master.pub`) so the minion will accept the new master's key.
2. Replaces `master: <oldmaster>` with `master: <newmaster>` in the minion config file.
3. Restarts the `salt-minion` service to apply the change.
4. Removes the minion key from the **old** master once the minion is no longer reachable from it.

---

## Switching masters for specific minions

### Step 1 — Define the minion list

**Option A — Manual (recommended for specific minions)**

Edit `map.yaml` with the correct master IPs and the specific minion IDs you want to move:

```yaml
newmaster: 10.40.7.222   # new master IP
oldmaster: 10.40.7.221   # current master IP

minionids:
  - minion-id-1
  - minion-id-2
  - minion-id-3
```

Then copy it to the location `init.sls` reads from:

```bash
cp /srv/salt/switch_masters/map.yaml /srv/salt/switch_masters/files/minions.yaml
```

**Option B — Auto-generate from all currently up minions**

Run `minionids.sls` against the old master, passing old/new master IPs as pillar:

```bash
salt <old-master-minion-id> state.apply switch_masters.files.minionids \
  pillar='{"oldmaster": "10.40.7.221", "newmaster": "10.40.7.222"}'
```

This writes `files/minions.yaml` automatically using all currently up minions.
Edit the file afterwards to keep only the specific minions you want to move.

---

### Step 2 — Run the orchestration

```bash
# Blocking — waits for all minions to complete
salt-run state.orch switch_masters

# Async — recommended for large batches
salt-run state.orch switch_masters --async
```

---

### Step 3 — Accept minion keys on the new master

After each minion restarts it connects to the new master with an unaccepted key.
Run the following **on the new master**:

```bash
# List pending keys
salt-key -L

# Accept a specific minion
salt-key -a minion-id-1

# Accept all pending at once
salt-key -A
```

Verify connectivity:

```bash
salt '*' test.ping
```

---

## Per-minion config paths

| OS | Master public key | Minion config file |
|---|---|---|
| Linux | `/etc/salt/pki/minion/minion_master.pub` | `/etc/salt/minion.d/minion.conf` |
| Windows | `C:\ProgramData\Salt Project\Salt\conf\pki\minion\minion_master.pub` | `C:\ProgramData\Salt Project\Salt\conf\minion` |

---

## Workflow summary

| Step | What runs | Purpose |
|---|---|---|
| 1 | `map.yaml` or `minionids.sls` | Define or generate the list of minions to move |
| 2 | `init.sls` (orchestration) | Iterate over minion list, apply move state, clean up old keys |
| 3 | `move_minions_map.sls` (per minion) | Delete cached key, update master IP in config, restart service |
| 4 | `salt-key -A` (on new master) | Accept minion keys so the new master trusts them |
