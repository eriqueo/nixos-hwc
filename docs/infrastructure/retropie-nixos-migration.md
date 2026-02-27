# Raspberry Pi 5 RetroPie: NixOS Migration Analysis

**Status**: Deferred (risk too high for current needs)
**Date**: 2026-02-24
**Device**: Raspberry Pi 5 Model B Rev 1.1 (8GB RAM)
**Current OS**: Debian 13 (trixie) with RetroPie 4.8.11

---

## Executive Summary

NixOS on Raspberry Pi 5 is **feasible but risky**. The main blocker is the 16KB page size issue with the vendor kernel, which can cause emulator crashes. Recommended to defer until official NixOS support improves.

---

## Current Stack on Pi

| Service | Version | Purpose |
|---------|---------|---------|
| RetroPie | 4.8.11 | Emulation framework |
| EmulationStation | 2.11.2rp | Game launcher frontend |
| lr-mupen64plus-next | Latest | N64 emulation (RetroArch core) |
| Project OutFox | 0.5.0-pre043 | Rhythm game (StepMania fork) |
| Tailscale | Latest | VPN/networking |

---

## NixOS Package Availability (aarch64)

| Package | Available | nixpkgs Path |
|---------|-----------|--------------|
| RetroArch | ✅ | `pkgs.retroarch` |
| mupen64plus-next | ✅ | `pkgs.libretro.mupen64plus` |
| OutFox | ✅ | `pkgs.outfox` |
| Tailscale | ✅ | `services.tailscale.enable` |
| EmulationStation | ❌ | Use `pkgs.pegasus-frontend` instead |

---

## Critical Issues Identified

### 1. 16KB Page Size Problem (HIGH RISK)

Pi 5 vendor kernel uses 16KB pages; many packages assume 4KB.

**Symptoms**: Random segfaults, mmap failures, emulator crashes

**Mitigation**:
```nix
imports = [
  inputs.nixos-raspberrypi.nixosModules.raspberry-pi-5.page-size-16k
];
```

**Alternative**: Build kernel with `CONFIG_ARM64_4K_PAGES=y` (loses optimizations)

### 2. Wayland-Only GPU = Latency Concerns

No X11 support with Pi 5 GPU drivers. Compositors add latency.

**Mitigation**: Use direct KMS scanout, bypass compositor:
```nix
programs.retroarch.settings = {
  video_driver = "kms";
  video_context_driver = "khr_display";
};
```

### 3. SD Card Wear from Nix Store

Nix does heavy writes; SD cards have limited write cycles.

**Mitigation**:
- Use USB SSD for root filesystem
- tmpfs for /tmp and /var/log
- Consider read-only root with persistent overlay

### 4. Binary Cache Coverage Gaps

aarch64 builds may not be cached; compilation can take hours.

**Mitigation**:
- Add nixos-raspberrypi.cachix.org
- Use hwc-server as remote builder with binfmt:
```nix
# On hwc-server
boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
```

### 5. Controller Permissions & Polling

Default udev rules may not set optimal polling rates.

**Mitigation**: Custom udev rules for 1000Hz polling, proper permissions.

### 6. Audio Latency

PipeWire defaults not optimized for gaming.

**Mitigation**:
```nix
environment.etc."pipewire/pipewire.conf.d/99-low-latency.conf".text = ''
  context.properties = {
    default.clock.quantum = 256
    default.clock.min-quantum = 128
  }
'';
```

### 7. No Easy Testing Without Hardware

Can't iterate on x86 dev machine.

**Mitigation**: Create VM-testable config factored out from hardware-specific parts.

### 8. Secrets/agenix Integration

Need separate age key for Pi, update secrets.nix with Pi's public key.

### 9. Kernel/Firmware Lag

nixos-raspberrypi may lag behind Raspberry Pi Foundation releases.

**Mitigation**: Pin to known-working version or follow develop branch carefully.

### 10. ROM/Save Storage

SD card slow for large ROM libraries.

**Mitigation**: USB SSD or NFS mount from hwc-server.

---

## Recommended Flake Integration (When Ready)

```nix
# flake.nix inputs
inputs.nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi";

# machines/retropie/config.nix
{ config, pkgs, inputs, ... }:
{
  imports = [
    inputs.nixos-raspberrypi.nixosModules.raspberry-pi-5.base
    inputs.nixos-raspberrypi.nixosModules.raspberry-pi-5.display-vc4
    inputs.nixos-raspberrypi.nixosModules.raspberry-pi-5.page-size-16k
  ];

  environment.systemPackages = with pkgs; [
    retroarch
    libretro.mupen64plus
    libretro.snes9x
    libretro.nestopia
    pegasus-frontend
    outfox
  ];

  services.tailscale.enable = true;

  # Direct boot to RetroArch (KMS, no compositor)
  services.greetd = {
    enable = true;
    settings.default_session = {
      command = "${pkgs.retroarch}/bin/retroarch";
      user = "eric";
    };
  };
}
```

---

## Effort Estimates

| Task | Effort | Risk |
|------|--------|------|
| Basic NixOS on Pi 5 | Medium | Medium |
| RetroArch + cores working | Medium-High | High (16KB pages) |
| Full RetroPie parity | High | Medium |
| Long-term maintainability | Low | Low |

---

## Decision

**Deferred** - Continue with Debian/RetroPie optimization. Revisit when:
- Official NixOS Pi 5 support lands
- 16KB page size issues are resolved upstream
- More time available for experimentation

Keep Debian SD card as production system; can experiment with NixOS on separate SD card later.

---

## Resources

- [NixOS on Raspberry Pi 5 Wiki](https://wiki.nixos.org/wiki/NixOS_on_ARM/Raspberry_Pi_5)
- [nixos-raspberrypi flake](https://github.com/nvmd/nixos-raspberrypi)
- [Pi 5 NixOS support issue](https://github.com/NixOS/nixpkgs/issues/260754)
- [Pegasus Frontend](https://pegasus-frontend.org/)
