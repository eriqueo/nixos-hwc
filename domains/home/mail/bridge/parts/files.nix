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

in
{ home.file = setup // keep; }
