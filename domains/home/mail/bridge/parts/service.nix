{ lib, pkgs, br, runtime }:
{
  systemd.user.services.protonmail-bridge = {
    Unit = {
      Description = "ProtonMail Bridge (headless)";
      After = [ "default.target" "network-online.target" "graphical-session.target" "gpg-agent.service" ];
      Wants = [ "network-online.target" "gpg-agent.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStartPre = pkgs.writeShellScript "bridge-init" ''
        mkdir -p ~/.config/protonmail/bridge-v3
        if [ ! -f ~/.config/protonmail/bridge-v3/keychain.json ]; then
          cat > ~/.config/protonmail/bridge-v3/keychain.json << 'EOF'
{"Helper":"${br.keychain.helper or ""}","DisableTest":${if (br.keychain.disableTest or true) then "true" else "false"}}
EOF
        fi
      '';
      ExecStart = "${(br.package or pkgs.protonmail-bridge)}/bin/protonmail-bridge ${runtime.args}";
      Restart = "on-failure";
      RestartSec = "${toString (br.restartSec or 5)}";
      Environment = runtime.env ++ [
        "GPG_TTY=%t/tty"
        "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%U/bus"
      ];
    };
    Install = { WantedBy = [ "default.target" ]; };
  };
}
