# Migration Patterns

## Pattern 1: Simple Containerized Service
```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.services.myservice;
in {
  options = { ... };
  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.containers.myservice = { ... };
  };
}
```

## Pattern 2: Service with GPU Support

```nix
extraOptions = lib.optionals cfg.enableGpu [
  "--gpus=all"
  "--runtime=nvidia"
];
```

## Pattern 3: Service with State Management

```nix
systemd.tmpfiles.rules = [
  "d ${cfg.dataDir} 0750 ${cfg.user} ${cfg.group} -"
];
```

## Pattern 4: Service with Dependencies

```nix
after = [ "network.target" ] ++ 
  lib.optional cfg.needsDatabase "postgresql.service";
```

## Pattern 5: Service with Scheduled Tasks

```nix
systemd.timers.myservice-task = {
  wantedBy = [ "timers.target" ];
  timerConfig.OnCalendar = "daily";
};
```

