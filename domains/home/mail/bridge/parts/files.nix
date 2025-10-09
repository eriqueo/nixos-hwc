{ lib, br }:
let
  setup =
    if (br.setupScript.enable or true) then {
      ".local/bin/proton-bridge-setup" = {
        text = ''
          #!/usr/bin/env bash
          set -euo pipefail
          protonmail-bridge --cli
        '';
        executable = true;
      };
    } else {};
  keep =
    if (br.ensureConfigDir or true) then {
      ".config/protonmail/bridge/.keep".text = "";
    } else {};

  # Declarative keychain configuration for reliable operation
  keychain = {
    ".config/protonmail/bridge-v3/keychain.json" = {
      text = builtins.toJSON {
        Helper = br.keychain.helper or "pass";
        DisableTest = br.keychain.disableTest or true;
      };
    };
  };
in
{ home.file = setup // keep // keychain; }
