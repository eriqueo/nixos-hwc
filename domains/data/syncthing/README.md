# domains/data/syncthing/

## Purpose

Bidirectional file sync between HWC machines using Syncthing over Tailscale. Provides declarative device pairing and folder configuration.

## Boundaries

- **Manages**: Syncthing service enablement, device declarations, folder sync config, versioning, per-folder `.stignore` provisioning
- **Does NOT manage**: Tailscale networking (-> domains/system/networking), file storage paths (-> domains/paths), backup (-> domains/data/borg)

## Structure

```
domains/data/syncthing/
├── index.nix     # Module: hwc.data.syncthing.* (service + options)
└── README.md
```

## Configuration

```nix
# In machines/server/config.nix:
hwc.data.syncthing = {
  enable = true;
  devices."hwc-laptop".id = "H3EVGHN-...";
  folders = {
    "000_inbox" = { path = "/home/eric/000_inbox"; devices = [ "hwc-laptop" ]; };
    "brain" = {
      path = "/home/eric/900_vaults/brain";
      devices = [ "hwc-laptop" "hwc-phone" ];
      ignores = [ ".git" ".trash/" ];   # written to <path>/.stignore
    };
    # ...
  };
};
```

## Design Decisions

- `globalAnnounce = false` by default -- all machines use Tailscale, no cloud relay needed
- `overrideDevices = true` and `overrideFolders = true` -- fully declarative, no GUI state drift
- Versioning defaults to staggered with 30-day retention per folder
- Device addresses are optional -- omit for auto-discovery, specify for fixed Tailscale IPs
- **`.stignore` is provisioned declaratively** (`folders.<name>.ignores`). Syncthing never
  syncs `.stignore` between devices, so it cannot be relied on to propagate — a git-backed
  vault folder MUST declare `.git` in `ignores` or Syncthing replicates `.git` internals and
  a stale peer can silently clobber committed history. The `syncthing-stignore` oneshot writes
  `<path>/.stignore` before `syncthing.service` starts.
- **Folder direction** is set per folder via `folders.<name>.type`
  (`sendreceive` default / `sendonly` / `receiveonly`). The `brain` folder is `sendonly` on
  the server: in Tier-2 the vault syncs by git (see `domains/automation/vault-sync`), and
  Syncthing's only job is to feed the receive-only phone mirror. `sendonly` guarantees the
  server never accepts vault changes back from the phone, so a stale phone cannot clobber the
  source. The laptop is no longer a `brain` peer at all (git-only).

## Changelog

- 2026-07-11: `dataDir` now `config.hwc.paths.user.home` instead of hardcoded `/home/eric` (Law 3 migration, value unchanged).

- 2026-04-12: Created module, extracted from machines/server/config.nix and machines/laptop/config.nix
- 2026-06-15: Add declarative per-folder `.stignore` provisioning (`folders.<name>.ignores` +
  `syncthing-stignore` oneshot). Root-cause fix for the brain-vault git/Syncthing clobber: the
  server had no `.stignore`, so Syncthing was replicating the vault's `.git`. `brain` folder now
  excludes `.git` on both hosts.
- 2026-06-15: Add per-folder `folders.<name>.type`. Tier-2 cutover: `brain` is now `sendonly`
  on the server + phone-only (laptop removed → git-only via domains/automation/vault-sync).
