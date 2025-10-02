# REFACTORED domains/system/services/networking/options.nix
{ lib, config, ... }:
{
  options.hwc.networking = {
    # KEEP: This is the master switch for the whole module. Essential.
    enable = lib.mkEnableOption "HWC networking configuration";

    # --- SSH Sub-Module ---
    ssh = {
      # KEEP: A fundamental role.
      enable = lib.mkEnableOption "SSH server configuration";

      # QUESTION: Do you have machines with different SSH ports? If not, this can be hardcoded to 22 in the implementation. If you have a public-facing server, then KEEP it.
      port = lib.mkOption { type = lib.types.port; default = 22; };

      # REMOVE/HARDCODE: Your charter should enforce secure defaults. These should be hardcoded to `false` in the implementation. You should never be tempted to enable them.
      # passwordAuthentication = lib.mkOption { ... };
      # allowRootLogin = lib.mkOption { ... };
    };

    # --- Tailscale Sub-Module ---
    tailscale = {
      # KEEP: A fundamental role.
      enable = lib.mkEnableOption "Tailscale VPN mesh networking";

      # KEEP: These are machine-specific secrets or configurations. Perfect candidates for options.
      authKeyFile = lib.mkOption { ... };
      extraUpFlags = lib.mkOption { ... };
    };

    # --- NetworkManager Sub-Module ---
    networkManager = {
      # KEEP: This is a major choice.
      enable = lib.mkEnableOption "NetworkManager for network management";

      # REMOVE/HARDCODE: Unless you have a strong reason to use something else on a specific machine, pick the best one (systemd-resolved) and hardcode it.
      # dns = lib.mkOption { ... };
    };

    # --- Firewall Sub-Module ---
    firewall = {
      # SUGGESTION: Replace all of this with a single `level` option as described above.
      # This entire block of 10+ options can become one line in your profile.
      level = lib.mkOption {
        type = lib.types.enum [ "off" "basic" "strict" "server" ];
        default = "strict";
        description = "High-level firewall profile.";
      };

      # You can still keep these for overrides if you need them.
      extraTcpPorts = lib.mkOption { ... };
      extraUdpPorts = lib.mkOption { ... };
    };

    # --- DNS Sub-Module ---
    # REMOVE/HARDCODE: DNS servers are rarely machine-specific. This is a classic "sensible default."
    # You can define your preferred DNS servers directly in the implementation. If you need to
    # override them on one specific machine, you can do it directly in that machine's config.
    # dns = { ... };

    # --- Samba Sub-Module ---
    samba = {
      # KEEP: A fundamental role.
      enable = lib.mkEnableOption "Samba file sharing service";

      # KEEP: Shares are, by definition, machine-specific. This is a perfect option.
      shares = lib.mkOption { ... };

      # REMOVE/HARDCODE: These are tweaks. Set them to your preferred defaults in the implementation.
      # workgroup = lib.mkOption { ... };
      # security = lib.mkOption { ... };
    };
  };
}
