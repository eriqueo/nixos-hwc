# NEW file: domains/system/services/backup/options.nix
{ lib, config, ... }:

{
  options.hwc.system.services.backup = {
    enable = lib.mkEnableOption "Enable the system-wide backup service";

    protonDrive = {
      enable = lib.mkEnableOption "Enable Proton Drive as a backup target";

      # We only need the secret name, as 'useSecret' is implied.
      # The module will handle finding and using the secret.
      secretName = lib.mkOption {
        type = lib.types.str;
        default = "rclone-proton-config";
        description = "Name of the agenix secret containing the rclone config for Proton Drive.";
      };
    };

    monitoring = {
      enable = lib.mkEnableOption "Enable backup monitoring and maintenance tools";
    };

    # Keep this for flexibility on a per-machine basis.
    extraTools = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "Additional backup-related packages to install.";
    };
  };
}
