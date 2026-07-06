# domains/home/core/shell/parts/aliases.nix
# Default shell aliases. ws = workspace root env var reference;
# nixosPath = resolved hwc.paths.nixos (Law 3 with Law-1 fallback).
{ ws, nixosPath }:
{
  "ll" = "eza -l"; "la" = "eza -lh"; "lt" = "eza --tree --level=2";
  "cd" = "z"; "cdi" = "zi"; "cz" = "z"; "czz" = "zi";
  ".." = "cd .."; "..." = "cd ../.."; "...." = "cd ../../..";
  "df" = "df -h"; "du" = "du -h"; "free" = "free -h";
  "aliases" = "cd ~/.nixos && nvim domains/home/core/shell/index.nix";
  "web-build" = "cd /opt/business/website-site && npx @11ty/eleventy";
  "htop" = "btop"; "open" = "xdg-open";
  "web-deploy" = "curl -s -X POST -H 'x-api-key: '$(cat /run/agenix/cms-api-key) http://localhost:8095/api/deploy | jq .";
  "web-speed" = "${ws}/tools/web-speed.sh";
  "gs" = "git status -sb"; "ga" = "git add ."; "gc" = "git commit -m"; "gp" = "git push"; "gpl" = "git pull";
  "nixsearch" = "nix search nixpkgs"; "nixclean" = "nix-collect-garbage -d";
  "checkup" = "$HWC_NIXOS_DIR/scripts/system-checkup.sh"; "speedtest" = "speedtest-cli";
  "myip" = "curl -s ifconfig.me"; "reload" = "source ~/.zshrc";
  "server" = "ssh eric@100.114.232.124"; "xps" = "ssh eric@100.126.80.42";
  "vpnon" = "sudo systemctl start wg-quick-protonvpn"; "vpnoff" = "sudo systemctl stop wg-quick-protonvpn";
  "vpnstatus" = "sudo wg show protonvpn 2>/dev/null || echo 'VPN disconnected'";
  "website" = "ssh -i ~/.ssh/hostinger_deploy -p 65002 u930853409@194.195.84.13";
  "cdn" = "cd ~/.nixos";
  "cdd" = "cd ~/700_datax/datax"; "cdj" = "cd ~/700_datax/jt-mcp";
  "downloads" = "cd ~/000_inbox/downloads"; "hwc" = "cd ~/100_hwc"; "inbox" = "cd ~/000_inbox";
  "screenshots" = "cd ~/500_media/510_pictures/screenshots";
  "cameras" = "echo 'Frigate: http://100.115.126.41:5000'";
  "ls" = "eza"; "vpn" = "vpnstatus"; "which-command" = "whence"; "run-help" = "man";
  # workbench = the full zellij ops layout (bare `workbench` is just the host
  # pane). attach -c reuses/creates the named session; `command workbench`
  # still reaches the raw binary (the zellij layout itself execs it directly).
  "workbench" = "zellij attach -c workbench";
  # wb-reload is now a REAL binary (writeShellScriptBin in apps/workbench/index.nix),
  # NOT an alias — the SUPER+W keybind runs `kitty -e wb-reload`, and `kitty -e`
  # can't see shell aliases. The binary kills + recreates the named session
  # (picks up layout edits); SUPER+W reloads workbench every time, by design.
  # Run from a NON-workbench terminal (it kills the session it'd be sitting in).
  # Workspace script aliases
  "errors" = "${ws}/monitoring/journal-errors.sh";
  "errors-hour" = "${ws}/monitoring/journal-errors.sh '1 hour ago'";
  "errors-today" = "${ws}/monitoring/journal-errors.sh 'today'";
  "errors-tdarr" = "${ws}/monitoring/journal-errors.sh '10 minutes ago' podman-tdarr";
  "services" = "${ws}/nixos-dev/list-services.sh";
  "rebuild" = "${ws}/nixos-dev/grebuild.sh"; "lint" = "${ws}/nixos-dev/charter-lint.sh";
  "caddy" = "${ws}/monitoring/caddy-health-check.sh"; "health" = "${ws}/monitoring/caddy-health-check.sh";
  "secret" = "${ws}/system/secret-manager.sh";
}
