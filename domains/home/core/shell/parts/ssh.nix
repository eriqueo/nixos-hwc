# domains/home/core/shell/parts/ssh.nix
# SSH client config — API differs between HM 25.11 (stable) and 26.05+
# (unstable). Stable uses `matchBlocks` with HM camelCase attrs; unstable
# uses `settings` with literal "Host *" keys and OpenSSH directive names.
# The user-facing DSL (cfg.ssh.matchBlocks) is translated per API here.
{ lib, cfg, nixosApiVersion }:
if nixosApiVersion == "stable" then {
  enable = true;
  enableDefaultConfig = false;
  matchBlocks = {
    "*" = {
      forwardAgent = false;
      addKeysToAgent = "no";
      compression = false;
      serverAliveInterval = 0;
      serverAliveCountMax = 3;
      hashKnownHosts = false;
      userKnownHostsFile = "~/.ssh/known_hosts";
      controlMaster = "no";
      controlPath = "~/.ssh/master-%r@%n:%p";
      controlPersist = "no";
    };
  } // (lib.mapAttrs (name: host: {
    hostname     = host.hostname;
    user         = host.user;
    forwardAgent = host.forwardAgent;
  } // lib.optionalAttrs (host.proxyCommand != null) {
    proxyCommand = host.proxyCommand;
  }) cfg.ssh.matchBlocks);
} else {
  enable = true;
  enableDefaultConfig = false;
  settings = lib.mkMerge [
    {
      "Host *" = {
        ForwardAgent = false;
        AddKeysToAgent = "no";
        Compression = false;
        ServerAliveInterval = 0;
        ServerAliveCountMax = 3;
        HashKnownHosts = false;
        UserKnownHostsFile = "~/.ssh/known_hosts";
        ControlMaster = "no";
        ControlPath = "~/.ssh/master-%r@%n:%p";
        ControlPersist = "no";
      };
    }
    (lib.mapAttrs' (name: host: lib.nameValuePair "Host ${name}" ({
      HostName     = host.hostname;
      User         = host.user;
      ForwardAgent = host.forwardAgent;
    } // lib.optionalAttrs (host.proxyCommand != null) {
      ProxyCommand = host.proxyCommand;
    })) cfg.ssh.matchBlocks)
  ];
}
