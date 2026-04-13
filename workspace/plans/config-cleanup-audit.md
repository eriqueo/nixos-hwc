# Config.nix Cleanup Audit

Date: 2026-04-12

## Summary

- **server/config.nix**: 1028 lines total, ~198 lines are implementation detail (**19%**)
- **laptop/config.nix**: 586 lines total, ~242 lines are implementation detail (**41%**)
- **Total blocks to extract**: 20 (11 server, 9 laptop)
- **Shared patterns**: 2 (Syncthing, sysctl/IO scheduler tuning)

---

## Server: Blocks to Extract

### S1: Firewall Port List (HIGH PRIORITY)

- **Lines**: 187-231
- **Current location**: `machines/server/config.nix` (inside `hwc.system.networking`)
- **Should live in**: Each respective domain module (via `openFirewall` options)
- **Why**: Violates Charter Law 2 (namespace fidelity) and DRY principle. Each service module already knows its port — the module should declare its own firewall rules. Currently 45 lines of hardcoded port numbers that duplicate knowledge scattered across 20+ domain modules.
- **Migration approach**: Add `openFirewall = true` option to each domain module that needs external access. The module's implementation adds its port to `networking.firewall.allowedTCPPorts` when enabled. Remove the centralized list entirely.
- **Complexity**: complex (touches ~20 modules, needs coordinated migration)
- **Snippet**:
```nix
    firewall.extraTcpPorts = [
      22000  # Syncthing sync
      # Media services
      5000   # Frigate
      8080   # qBittorrent (via Gluetun)
      7878   # Radarr
```
- **Impact**: Eliminates port conflict risk (a recurring mistake per CLAUDE.md). Each module owns its port.

### S2: Samba File Sharing (MEDIUM PRIORITY)

- **Lines**: 234-266
- **Current location**: `machines/server/config.nix`
- **Should live in**: `domains/gaming/retroarch/parts/samba.nix` (imported by retroarch index.nix)
- **Why**: Raw `services.samba` and `services.samba-wsdd` blocks — implementation detail, not enablement. The share is specifically for RetroArch ROMs. Violates Law 6 (module structure).
- **Migration approach**: Add `hwc.gaming.retroarch.samba.enable` option to existing retroarch module. Move Samba config into `parts/samba.nix`. The config values (share path, protocol settings) become module options.
- **Complexity**: moderate
- **Snippet**:
```nix
  services.samba = {
    enable = true;
    openFirewall = true;
    settings = {
      global = {
        workgroup = "WORKGROUP";
```

### S3: Syncthing (HIGH PRIORITY — shared with laptop)

- **Lines**: 268-288
- **Current location**: `machines/server/config.nix`
- **Should live in**: `domains/data/syncthing/index.nix` (new module)
- **Why**: Raw `services.syncthing` block with device IDs, folder declarations, and settings. Identical structure in both configs. Violates Law 6 (no module wrapping) and Law 9 (no index.nix for this capability).
- **Migration approach**: Create `domains/data/syncthing/index.nix` with `hwc.data.syncthing` namespace. Options for devices, folders, and sync settings. Machine configs just enable + provide device-specific values.
- **Complexity**: moderate
- **Snippet**:
```nix
  services.syncthing = {
    enable = true;
    user = "eric";
    dataDir = "/home/eric";
    openDefaultPorts = true;
    overrideDevices = true;
```

### S4: Gotify Token Auto-Discovery Lambda (LOW PRIORITY)

- **Lines**: 571-592
- **Current location**: `machines/server/config.nix` (inside `hwc.notifications.gotify` block)
- **Should live in**: `domains/notifications/index.nix` (or `parts/gotify.nix`)
- **Why**: 22 lines of inline Nix lambda logic (filterAttrs, mapAttrs', string manipulation) computing token mappings from agenix secrets. This is module-level logic masquerading as configuration. The auto-discovery pattern should be a built-in feature of the gotify module.
- **Migration approach**: Move the `isGotifyToken` + `toAppKey` logic into the notifications/gotify module as a default value or config derivation. Machine config just sets `hwc.notifications.gotify.autoDiscoverTokens = true`.
- **Complexity**: moderate
- **Snippet**:
```nix
    tokens =
      let
        isGotifyToken = name:
          lib.hasPrefix "gotify-" name
          && name != "gotify-admin-password"
```

### S5: Frigate Cleanup Service + Timer (HIGH PRIORITY)

- **Lines**: 634-665
- **Current location**: `machines/server/config.nix`
- **Should live in**: `domains/media/frigate/parts/cleanup.nix` (extend existing frigate module)
- **Why**: Raw `systemd.services.frigate-cleanup` and `systemd.timers.frigate-cleanup` — 32 lines of inline shell script for surveillance recording cleanup. Classic implementation detail that belongs with the Frigate module. Violates Law 6.
- **Migration approach**: Add `hwc.media.frigate.cleanup.enable` option to existing frigate module. Move timer + service + script into `parts/cleanup.nix`. Options for retention days, schedule.
- **Complexity**: trivial
- **Snippet**:
```nix
  systemd.services.frigate-cleanup = {
    description = "Cleanup old Frigate surveillance recordings";
    serviceConfig = {
      Type = "oneshot";
      User = "root";
```

### S6: SMARTD Disk Monitoring (LOW PRIORITY)

- **Lines**: 754-759
- **Current location**: `machines/server/config.nix`
- **Should live in**: `domains/system/hardware/` (extend existing hardware module)
- **Why**: Raw `services.smartd` config. Could be exposed as `hwc.system.hardware.monitoring.smartd.enable`.
- **Migration approach**: Add SMART options to existing `hwc.system.hardware.monitoring` module.
- **Complexity**: trivial
- **Snippet**:
```nix
  services.smartd = {
    enable = true;
    autodetect = true;
    notifications.wall.enable = true;
```

### S7: Journald Configuration (LOW PRIORITY)

- **Lines**: 762-768
- **Current location**: `machines/server/config.nix`
- **Should live in**: `domains/system/core/` (extend existing core module)
- **Why**: Raw `services.journald.extraConfig`. Server-specific log retention. Could be `hwc.system.core.logging.journald` options.
- **Migration approach**: Add logging options to system/core. Server and laptop get different defaults based on role.
- **Complexity**: trivial
- **Snippet**:
```nix
  services.journald.extraConfig = ''
    SystemMaxUse=1G
    RuntimeMaxUse=200M
    SystemMaxFileSize=100M
```

### S8: Logrotate for Container Logs (LOW PRIORITY)

- **Lines**: 770-779
- **Current location**: `machines/server/config.nix`
- **Should live in**: `domains/system/core/` or container runtime section
- **Why**: Raw `services.logrotate.settings.docker`. Container log rotation should be part of the container runtime setup.
- **Migration approach**: Add to the Podman/container module or system/core logging.
- **Complexity**: trivial
- **Snippet**:
```nix
  services.logrotate.settings.docker = {
    files = [ "/var/lib/docker/containers/*/*.log" ];
    frequency = "daily";
    rotate = 7;
```

### S9: udev I/O Scheduler Rules (LOW PRIORITY)

- **Lines**: 748-752
- **Current location**: `machines/server/config.nix`
- **Should live in**: `domains/system/hardware/` (extend existing hardware module)
- **Why**: Raw `services.udev.extraRules` for NVMe/SSD/HDD I/O schedulers. Same pattern in laptop (line 518). Should be a shared option.
- **Migration approach**: Add `hwc.system.hardware.ioScheduler` options to hardware module. Auto-configure based on device type.
- **Complexity**: trivial
- **Snippet**:
```nix
  services.udev.extraRules = lib.mkAfter ''
    ACTION=="add|change", KERNEL=="nvme*", ATTR{queue/scheduler}="mq-deadline"
    ACTION=="add|change", KERNEL=="sd*", ENV{ID_BUS}=="ata", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
```

### S10: Shared Directory tmpfiles Rule (TRIVIAL)

- **Lines**: 713-715
- **Current location**: `machines/server/config.nix`
- **Should live in**: NFS server config in networking module, or a shared-directory submodule
- **Why**: Raw `systemd.tmpfiles.rules` for NFS export directory. Could be part of the NFS server setup.
- **Migration approach**: Move into `hwc.system.networking.nfs.server` implementation — when NFS server is enabled with exports, auto-create the exported directories.
- **Complexity**: trivial
- **Snippet**:
```nix
  systemd.tmpfiles.rules = [
    "d ${config.hwc.paths.user.shared} 0755 eric users -"
  ];
```

### S11: SSH X11 Override (TRIVIAL)

- **Lines**: 679-681
- **Current location**: `machines/server/config.nix`
- **Should live in**: `hwc.system.networking.ssh` options (extend existing module)
- **Why**: Raw `services.openssh.settings` overrides. Could be `hwc.system.networking.ssh.x11Forwarding = false` with server default.
- **Migration approach**: Add option to networking module.
- **Complexity**: trivial
- **Snippet**:
```nix
  services.openssh.settings = {
    X11Forwarding = lib.mkForce false;
    PasswordAuthentication = lib.mkForce true;
```

---

## Laptop: Blocks to Extract

### L1: USB Auto-Mount Scripts (HIGH PRIORITY)

- **Lines**: 12-71 (let bindings) + 517-532 (udev rules referencing them)
- **Current location**: `machines/laptop/config.nix`
- **Should live in**: `domains/system/hardware/parts/usb-automount.nix` (or `domains/system/hardware/usb/index.nix`)
- **Why**: 60 lines of inline shell scripts (`usbAutoMount`, `usbAutoUnmount`) plus 16 lines of udev rules. Classic implementation detail — full bash scripts embedded in Nix config. Violates Law 6 (module structure). Scripts should live in `parts/` files.
- **Migration approach**: Create `hwc.system.hardware.usb.autoMount.enable` option. Move scripts to `parts/usb-automount.sh` and `parts/usb-autounmount.sh`. udev rules generated by the module.
- **Complexity**: moderate (scripts reference pkgs paths, need proper wrapping)
- **Snippet**:
```nix
  usbAutoMount = pkgs.writeShellScript "usb-automount" ''
    #!/usr/bin/env bash
    set -euo pipefail
    [[ -z "''${1:-}" ]] && exit 1
    DEVICE="/dev/$1"
```

### L2: Syncthing (HIGH PRIORITY — shared with server)

- **Lines**: 236-260
- **Current location**: `machines/laptop/config.nix`
- **Should live in**: `domains/data/syncthing/index.nix` (new module, same as S3)
- **Why**: Same as S3. Raw `services.syncthing` with device IDs and folder declarations. Shared pattern with server.
- **Migration approach**: Same new module as S3. Laptop just provides its device-specific values.
- **Complexity**: moderate (combined with S3)
- **Snippet**:
```nix
  services.syncthing = {
    enable = true;
    user = "eric";
    dataDir = "/home/eric";
    openDefaultPorts = true;
    overrideDevices = true;
```

### L3: Seagate Fixperms Service (MEDIUM PRIORITY)

- **Lines**: 295-309
- **Current location**: `machines/laptop/config.nix`
- **Should live in**: `domains/system/hardware/parts/ntfs-fixperms.nix` or alongside USB automount module
- **Why**: Raw `systemd.services.seagate-fixperms` with inline script. The fixperms logic is tied to NTFS permission handling — same concern as USB auto-mount. Violates Law 6.
- **Migration approach**: Include in the USB/external-drive module. Add `hwc.system.hardware.usb.fixNtfsPerms = true` option.
- **Complexity**: trivial (small service, bundled with L1)
- **Snippet**:
```nix
  systemd.services.seagate-fixperms = {
    description = "Fix Seagate NTFS directory ownership for user access";
    after = [ "mnt-seagate.mount" ];
    wantedBy = [ "mnt-seagate.mount" ];
    serviceConfig = {
```

### L4: Libvirt/QEMU Virtualization (MEDIUM PRIORITY)

- **Lines**: 339-373
- **Current location**: `machines/laptop/config.nix`
- **Should live in**: `domains/system/virtualization/index.nix` (new module)
- **Why**: Raw `virtualisation.libvirtd` config with QEMU settings, socket permissions, and commented-out NixVirt pool. This is a capability, not hardware reality. Violates Law 6 and Law 9.
- **Migration approach**: Create `hwc.system.virtualization` module with `libvirt.enable`, `qemu.runAsRoot`, etc. Machine config just enables.
- **Complexity**: moderate
- **Snippet**:
```nix
  virtualisation.libvirtd = {
    extraConfig = ''
      unix_sock_group = "wheel"
      unix_sock_ro_perms = "0770"
      unix_sock_rw_perms = "0770"
```

### L5: TLP Power Management (MEDIUM PRIORITY)

- **Lines**: 460-489
- **Current location**: `machines/laptop/config.nix`
- **Should live in**: `domains/system/hardware/parts/power.nix` (extend existing hardware module)
- **Why**: Raw `services.tlp` block with 30 lines of specific settings. The settings ARE machine-specific (charge thresholds, CPU governors), but the TLP service setup is generic laptop infrastructure. Violates Law 6.
- **Migration approach**: Add `hwc.system.hardware.power.tlp` options to existing hardware module. Machine-specific values (charge thresholds, governor policy) passed as options. Module owns the `services.tlp` implementation.
- **Complexity**: moderate (need to design option interface that exposes the right knobs)
- **Snippet**:
```nix
  services.tlp = {
    enable = true;
    settings = {
      CPU_SCALING_GOVERNOR_ON_AC = "powersave";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
```

### L6: Performance Sysctl Tuning (LOW PRIORITY)

- **Lines**: 497-514
- **Current location**: `machines/laptop/config.nix`
- **Should live in**: `domains/system/hardware/parts/performance.nix` (extend hardware module)
- **Why**: Raw `boot.kernel.sysctl` with 18 lines of network/memory/fs tuning. Shared pattern with server (lines 741-745). Values are machine-specific, but the tuning categories (memory, network, fs) are generic.
- **Migration approach**: Add `hwc.system.hardware.performance` options with presets (`laptop`, `server`). Each preset sets appropriate sysctl values. Machine config selects preset and overrides as needed.
- **Complexity**: moderate (need to handle server vs laptop defaults)
- **Snippet**:
```nix
  boot.kernel.sysctl = {
    "vm.swappiness" = 100;
    "vm.vfs_cache_pressure" = 50;
    "vm.dirty_ratio" = 6;
    "vm.dirty_background_ratio" = 3;
```

### L7: perf-mode / balanced-mode Wrappers (MEDIUM PRIORITY)

- **Lines**: 545-564
- **Current location**: `machines/laptop/config.nix`
- **Should live in**: `domains/system/hardware/parts/power.nix` (bundled with TLP, L5)
- **Why**: `writeShellScriptBin` inline wrappers in `environment.systemPackages`. The file itself has a TODO comment saying "Consider moving to domains/system/services/performance/ module". Inline scripts violate Law 6.
- **Migration approach**: Bundle with L5 TLP module. `hwc.system.hardware.power.perfModeScripts.enable` adds these to systemPackages.
- **Complexity**: trivial (small scripts, bundled with L5)
- **Snippet**:
```nix
    (writeShellScriptBin "perf-mode" ''
      #!/usr/bin/env bash
      echo "Switching to Performance Mode..."
      echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor >/dev/null
```

### L8: nix-ld Library List (LOW PRIORITY)

- **Lines**: 573-581
- **Current location**: `machines/laptop/config.nix`
- **Should live in**: `domains/system/core/` or a compatibility module
- **Why**: Raw `programs.nix-ld` with 20+ library entries. This is a desktop capability (AppImage/binary compat), not machine-specific hardware.
- **Migration approach**: Add `hwc.system.core.compatibility.nixLd.enable` option. Library list maintained in the module.
- **Complexity**: trivial
- **Snippet**:
```nix
  programs.nix-ld.libraries = with pkgs; [
    glib glibc gtk3 pango cairo gdk-pixbuf atk
    nss nspr dbus expat libdrm mesa
    alsa-lib cups libpulseaudio
```

### L9: Flatpak + dconf + Session Variables (LOW PRIORITY)

- **Lines**: 566-572
- **Current location**: `machines/laptop/config.nix`
- **Should live in**: `domains/system/core/` or a desktop-environment module
- **Why**: Raw `programs.dconf.enable`, `services.flatpak.enable`, and `environment.sessionVariables`. Desktop capabilities, not machine-specific.
- **Migration approach**: Add to session profile or system/core desktop module. `hwc.system.core.desktop.flatpak.enable`, etc.
- **Complexity**: trivial
- **Snippet**:
```nix
  programs.dconf.enable = true;
  services.flatpak.enable = true;
  environment.sessionVariables.XDG_DATA_DIRS = [
    "/var/lib/flatpak/exports/share"
```

---

## Blocks That Should Stay

### Server

| Lines | Block | Justification |
|-------|-------|---------------|
| 8-23 | Imports | Machine composition — core purpose of config.nix |
| 25-92 | Assertions | Machine-specific validation (storage, secrets, tailscale, nixpkgs, pg version) |
| 94-99 | System identity | `hostName`, `hostId`, `hwc.server.enable` — machine identity |
| 101-120 | ZFS config | Hardware reality — backup pool, scrub/trim schedules |
| 122-146 | Paths + storage mounts | Machine-specific storage (device UUIDs, mount points) |
| 148-164 | Timezone + nix settings | Machine environment |
| 167-186 | Networking enablement | `hwc.system.networking` options (not raw services) — correct pattern |
| 290-344 | MQTT, Gotify client, Notifications, Alerts | Domain enablement via options — correct pattern |
| 346-430 | Borg backup | Machine-specific backup config (sources, excludes, pre-scripts). preBackupScript is borderline but has machine-specific DB dump logic |
| 432-454 | GPU config | Hardware reality (P1000 Pascal, driver 580, modesetting) |
| 456-519 | AI domain config | Domain enablement via options with machine-specific overrides |
| 521-557 | MCP, CouchDB, Navidrome | Domain enablement — correct pattern |
| 559-570 | Gotify server enablement | Enablement part is fine (token lambda is S4) |
| 593-631 | iGotify, Alert bridge, Frigate NVR | Domain enablement via options |
| 684-702 | Session config | Machine-specific (headless server, passwordless sudo) |
| 703 | Tailscale cert UID | Machine-specific integration |
| 708 | Server packages | Machine role enablement |
| 720-723 | Storage paths | Machine-specific path overrides |
| 728-736 | Container runtime | Machine-specific Podman config |
| 741-745 | Server sysctl | Machine-specific tuning (borderline, but small and targeted) |
| 784-787 | Reverse proxy | Domain enablement |
| 793-1017 | Service enablement block | THE GOOD PART — what config.nix should look like |
| 1018-1027 | Home Manager + stateVersion | Machine identity |

### Laptop

| Lines | Block | Justification |
|-------|-------|---------------|
| 84-99 | Imports + nix settings | Machine composition |
| 116-121 | Boot + identity | Hardware reality (`lid_init_state`, `hostName`, `stateVersion`) |
| 127-142 | logind settings | Hardware reality (lid switch behavior, power button) — laptop-specific |
| 145 | system76-scheduler | Hardware reality (P/E core scheduling) |
| 152-216 | System services config | Domain enablement via options (shell, users, hardware, sudo) |
| 219-234 | Networking config | Domain enablement via options |
| 262-293 | NFS mount + Seagate mount | Hardware reality (UUIDs, mount options, device paths) |
| 316-333 | GPU config | Hardware reality (bus IDs, NVIDIA power management) |
| 354-356 | Docker disable | Machine-specific override |
| 380-383 | System app enables | Domain enablement |
| 392-400 | Paths + HM imports | Machine-specific overrides |
| 404-445 | AI domain config | Domain enablement with machine-specific overrides |
| 447-454 | Static hosts | Borderline — could be networking module, but small and machine-specific |
| 496 | thermald disable | Hardware reality (Meteor Lake unsupported) |
| 534-535 | Intel NPU + graphics | Hardware reality |
| 583-584 | SSH password auth | Machine-specific override |

---

## Proposed New Modules

| New Module Path | Namespace | Absorbs | Priority |
|-----------------|-----------|---------|----------|
| `domains/data/syncthing/index.nix` | `hwc.data.syncthing` | S3, L2 | **high** |
| `domains/system/hardware/parts/usb-automount.nix` | `hwc.system.hardware.usb` | L1, L3 (extend existing hw module) | **high** |
| `domains/system/hardware/parts/power.nix` | `hwc.system.hardware.power` | L5, L7 (extend existing hw module) | **medium** |
| `domains/system/hardware/parts/performance.nix` | `hwc.system.hardware.performance` | L6, S9 (extend existing hw module) | **low** |
| `domains/system/virtualization/index.nix` | `hwc.system.virtualization` | L4 | **medium** |
| (extend) `domains/media/frigate/parts/cleanup.nix` | `hwc.media.frigate.cleanup` | S5 | **high** |
| (extend) `domains/gaming/retroarch/parts/samba.nix` | `hwc.gaming.retroarch.samba` | S2 | **medium** |
| (extend) `domains/notifications/` | `hwc.notifications.gotify.autoDiscoverTokens` | S4 | **low** |
| (extend) `domains/system/core/` | `hwc.system.core.logging`, `.compatibility` | S7, S8, L8, L9 | **low** |

---

## Migration Order

### Phase 1: High-Impact, Low-Risk (do first)

1. **S5: Frigate cleanup** — trivial extraction into existing module. Zero risk. Removes 32 lines of inline systemd from server config.
2. **S3 + L2: Syncthing** — new module, but well-defined scope. Removes 46 lines total. Both configs get cleaner simultaneously.
3. **L1 + L3: USB auto-mount** — removes 75 lines from laptop config (biggest single win). Self-contained.

### Phase 2: Medium Complexity

4. **S2: Samba** — extend existing retroarch module. 33 lines.
5. **L5 + L7: TLP + perf-mode** — extend hardware module. 50 lines. Has a TODO comment already requesting this.
6. **L4: Libvirt/QEMU** — new module, straightforward. 35 lines.

### Phase 3: Architectural (needs design work)

7. **S1: Firewall port list** — the biggest win but requires touching ~20 modules. Each module needs `openFirewall` option + implementation. Do incrementally: migrate 3-4 modules at a time, shrinking the central list gradually.

### Phase 4: Polish (low priority, small wins)

8. **S4: Gotify token auto-discovery** — move lambda into module.
9. **S6 + S9: SMARTD + IO scheduler** — extend hardware module.
10. **S7 + S8: Journald + logrotate** — extend system/core.
11. **L6: sysctl tuning** — extend hardware module with presets.
12. **L8 + L9: nix-ld + flatpak** — extend system/core.

---

## Shared Patterns

### 1. Syncthing (S3 + L2)

Both configs have near-identical `services.syncthing` blocks:
- Same `user`, `dataDir`, `openDefaultPorts`, `overrideDevices`, `overrideFolders`
- Same `globalAnnounceEnabled = false`
- Same 4 folder IDs with identical versioning config
- Only difference: device ID (each machine lists the other)

**Unified module** at `domains/data/syncthing/index.nix` would:
- Declare all folder IDs as options with `devices` list
- Each machine provides its peer device ID
- Module generates the `services.syncthing` config

### 2. sysctl + I/O Scheduler Tuning (S9 + L6 partial)

Both configs set sysctl values and udev I/O scheduler rules:
- Server: `mq-deadline` for NVMe/SSD, `bfq` for HDD
- Laptop: `kyber` for NVMe

Both set `vm.dirty_ratio`, `vm.dirty_background_ratio`, `vm.swappiness` — but with different values.

**Unified module** at `domains/system/hardware/parts/performance.nix` would:
- Offer role-based presets: `hwc.system.hardware.performance.profile = "server"|"laptop"`
- Set appropriate sysctl defaults per role
- Configure I/O schedulers based on detected disk types

### 3. SSH PasswordAuthentication Override

Both configs force `services.openssh.settings.PasswordAuthentication = lib.mkForce true`:
- Server: line 681
- Laptop: line 584

This suggests the base SSH module defaults to `false`, and both machines override. Could be a networking module option.

---

## Estimated Line Reduction

| File | Current | Lines Extracted | Remaining | Reduction |
|------|---------|-----------------|-----------|-----------|
| server/config.nix | 1028 | ~198 | ~830 | **19%** |
| laptop/config.nix | 586 | ~242 | ~344 | **41%** |
| **Total** | **1614** | **~440** | **~1174** | **27%** |

The laptop benefits most because of the 75-line USB auto-mount scripts and 30-line TLP block. The server's biggest single win is the 45-line firewall port list, but that's also the most complex to migrate.
