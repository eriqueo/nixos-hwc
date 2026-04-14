# domains/data/syncthing/

## Purpose

Bidirectional file sync between HWC machines using Syncthing over Tailscale. Provides declarative device pairing and folder configuration.

## Boundaries

- **Manages**: Syncthing service enablement, device declarations, folder sync config, versioning
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
    # ...
  };
};
```

## Design Decisions

- `globalAnnounce = false` by default -- all machines use Tailscale, no cloud relay needed
- `overrideDevices = true` and `overrideFolders = true` -- fully declarative, no GUI state drift
- Versioning defaults to staggered with 30-day retention per folder
- Device addresses are optional -- omit for auto-discovery, specify for fixed Tailscale IPs

## Changelog

- 2026-04-12: Created module, extracted from machines/server/config.nix and machines/laptop/config.nix
