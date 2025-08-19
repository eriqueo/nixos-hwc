{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.secrets;
  paths = config.hwc.paths;
in {
  options.hwc.secrets = {
    enable = lib.mkEnableOption "Secrets management";

    provider = lib.mkOption {
      type = lib.types.enum [ "sops" "vault" "age" ];
      default = "age";
      description = "Secrets provider";
    };

    sops = {
      keyFile = lib.mkOption {
        type = lib.types.path;
        default = "/var/lib/sops-nix/key.txt";
        description = "SOPS key file";
      };

      secrets = lib.mkOption {
        type = lib.types.attrsOf lib.types.attrs;
        default = {};
        description = "SOPS secrets configuration";
      };
    };

    vault = {
      enable = lib.mkEnableOption "HashiCorp Vault";

      address = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:8200";
        description = "Vault address";
      };

      tokenFile = lib.mkOption {
        type = lib.types.path;
        description = "Vault token file";
      };
    };
  };

  config = lib.mkMerge [
#    (lib.mkIf (cfg.enable && cfg.provider == "sops" && (config ? sops)) {
 #     sops = {
  #      defaultSopsFile = ./secrets/secrets.yaml;
  #      age.keyFile = cfg.sops.keyFile;
  #      secrets = cfg.sops.secrets;
  #    };

   #   # Ensure key directory exists
   #   systemd.tmpfiles.rules = [
   #     "d /var/lib/sops-nix 0755 root root -"
   #   ];
   # })

    (lib.mkIf (cfg.enable && cfg.provider == "vault") {
      services.vault = {
        enable = cfg.vault.enable;
        address = cfg.vault.address;

        storageConfig = ''
          storage "file" {
            path = "${paths.state}/vault"
          }
        '';
      };

      environment.systemPackages = [ pkgs.vault ];
    })
  ];
}
