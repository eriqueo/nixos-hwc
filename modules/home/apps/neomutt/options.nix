# modules/home/apps/neomutt/options.nix
{ lib, ... }:

{
  options.features.neomutt = {
    enable = lib.mkEnableOption "Enable NeoMutt (command-line email client)";

    # Email account configuration for ProtonMail Bridge integration
    accounts = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule ({ name, ... }: {
        options = {
          # The name of the account (e.g., "proton")
          name = lib.mkOption {
            type = lib.types.str;
            default = name;
            description = "The name of the account.";
          };

          # User details
          realName = lib.mkOption {
            type = lib.types.str;
            description = "Your full name for outgoing emails.";
          };
          email = lib.mkOption {
            type = lib.types.str;
            description = "Your email address.";
          };

          # Proton Bridge specific details
          bridgeUsername = lib.mkOption {
            type = lib.types.str;
            description = "The username provided by Proton Mail Bridge.";
          };
          useAgenixPassword = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to use agenix-managed ProtonMail Bridge password.";
          };
          bridgePasswordCommand = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Command to retrieve the password from the password store. Only used if useAgenixPassword is false.";
            example = "pass show proton/bridge-password";
          };
        };
      }));
      default = {};
      description = "Declaratively configure NeoMutt email accounts.";
    };
  };
}
