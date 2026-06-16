# domains/home/core/shell/parts/zsh-init.nix
# zsh initContent: hash refresh, rebuild helpers (snix/tnix/bnix/hms),
# ff/status/add-app/graph functions.
{ config }:
''
        # Refresh zsh's command hash table before every prompt. Required because
        # this host runs BOTH HM-as-module (via nixos-rebuild, useUserPackages=true)
        # and HM-as-flake (via `hms`). HM-as-module wipes the legacy nix-env user
        # profile under ~/.nix-profile during activation, which invalidates any
        # absolute paths zsh already cached from there (e.g. starship). hash -r
        # is in-process and effectively free.
        # NB: add-zsh-hook requires a function NAME, not a command — wrap hash -r.
        autoload -Uz add-zsh-hook
        _hwc_hash_refresh() { hash -r; }
        add-zsh-hook precmd _hwc_hash_refresh

        # Rebind the running shell's prompt to a live starship binary.
        # `starship init zsh` bakes the ABSOLUTE path of the binary that ran it
        # into the prompt hook functions (e.g. __starship_get_time, PROMPT2). A
        # shell that baked ~/.nix-profile/bin/starship dies on every prompt after
        # an HM-as-module activation, because activation WIPES ~/.nix-profile —
        # and `hash -r` can't fix it (it only re-resolves bare command names, not
        # an absolute path literal inside a function). Re-running init after a
        # rebuild rebakes the path via PATH, which now lands on the stable
        # /etc/profiles/per-user/$USER/bin/starship symlink (repopulated every
        # activation, never wiped). Guarded so hosts with starship disabled skip it.
        _hwc_reinit_prompt() {
          hash -r
          if command -v starship >/dev/null 2>&1; then
            eval "$(starship init zsh)"
          fi
        }

        # NixOS rebuild shortcuts (dynamic hostname)
        # `env HOME=/root` stops Nix warning that /home/eric isn't owned by root.
        # Must be the ABSOLUTE path, not `~root`: zsh doesn't tilde-expand it in
        # an env-assignment arg, so `HOME=~root` set the literal string `~root`
        # and made Nix create `./~root/.nix-defexpr` junk in the repo (see the
        # detailed note at the HOME=/root line below).
        # (sudo -H / -i don't work here: this system's sudo preserves the caller's
        # environment and HOME survives both flags — verified 2026-06-10.)
        # snix/tnix auto-reload Hyprland when run inside a Hyprland session because they
        # activate the HM-as-module config (via home-manager-eric.service, oneshot, so
        # ~/.config/hypr/hyprland.conf is on disk by the time the command returns).
        # bnix is pure build, no activation, so no reload.
        # _hwc_rebuild tees output to a temp log and re-prints warning lines at the
        # end so deprecation warnings can't scroll away unnoticed (zero-warning baseline).
        _hwc_rebuild() {
          local log rc warns
          log=$(mktemp -t nixos-rebuild-log.XXXXXX)
          # HOME=/root (root's real home), NOT ~root: zsh does not tilde-expand
          # `~root` in an env-assignment argument, so `HOME=~root` would set the
          # LITERAL string "~root" — and nix then creates `./~root/.nix-defexpr`
          # junk in the cwd (the repo). Absolute /root keeps nix's root-owned
          # state where it belongs and silences the "$HOME not owned" warning.
          sudo env HOME=/root nixos-rebuild "$@" --flake "$HWC_NIXOS_DIR#$(hostname)" 2>&1 | tee "$log"
          rc=''${pipestatus[1]}
          warns=$(grep -E '^(evaluation warning|warning|trace):' "$log" | sort -u)
          rm -f "$log"
          if [ -n "$warns" ]; then
            print -P "\n%F{yellow}── warnings (deduped) ──%f"
            print -r -- "$warns"
          fi
          return $rc
        }
        snix() {
          if [ -n "$(git -C "$HWC_NIXOS_DIR" status --porcelain 2>/dev/null)" ]; then
            print -P "%F{yellow}dirty git tree%f — doctrine: commit before rebuild"
            git -C "$HWC_NIXOS_DIR" status --short
            read -q "?continue anyway? [y/N] " || { print; return 1; }
            print
          fi
          _hwc_rebuild switch "$@" || return $?
          _hwc_reinit_prompt
          if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
            hyprctl reload >/dev/null
          fi
        }
        tnix() {
          _hwc_rebuild test "$@" || return $?
          _hwc_reinit_prompt
          if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
            hyprctl reload >/dev/null
          fi
        }
        bnix() {
          _hwc_rebuild build "$@"
        }

        # Home Manager standalone activation (HM-as-flake path).
        # Auto-reloads Hyprland after activation when running inside a
        # Hyprland session, because HM activation writes ~/.config/hypr/
        # hyprland.conf but does not signal the compositor. Reload is a
        # no-op if the new generation didn't change hyprland config.
        # Extra args (e.g. --show-trace, --refresh) are forwarded to nix build.
        hms() {
          local activator
          activator=$(nix build --no-link --print-out-paths \
            "$HWC_NIXOS_DIR#homeConfigurations.\"eric@$(hostname)\".activationPackage" \
            "$@") || return $?
          "$activator/activate" || return $?
          _hwc_reinit_prompt
          if [ -n "''${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
            hyprctl reload >/dev/null
          fi
        }

        # Fuzzy finding function
        ff() {
          fd -t f . ~ | fzf --query="$*" --preview 'head -20 {}'
        }

        # Quick system status check
        status() {
          echo "System Status Overview"
          echo "=========================="
          echo "Memory: $(free -h | awk 'NR==2{printf "%.1f%%", $3*100/$2 }')"
          echo "Disk: $(df -h / | awk 'NR==2{print $5}')"
          echo "Load: $(uptime | awk -F'load average:' '{print $2}')"
        }

        # add-app shell function
        add-app() {
          ${config.home.homeDirectory}/.nixos/workspace/nixos-dev/add-home-app.sh "$@"
        }

        # Interactive graph function for hwc-graph tool
        graph() {
          local graph_script="${config.home.homeDirectory}/.nixos/workspace/nixos-dev/graph/hwc_graph.py"

          # If arguments provided, pass directly to script
          if [ $# -gt 0 ]; then
            python3 "$graph_script" "$@"
            return
          fi

          # Interactive mode
          echo "HWC Dependency Graph Analyzer"
          echo "================================"
          echo ""

          PS3=$'\n'"Choose a command (1-6): "
          select cmd in "List all modules" "Show module details" "Impact analysis" "Requirements analysis" "Graph statistics" "Export to JSON" "Exit"; do
            case $REPLY in
              1)
                python3 "$graph_script" list
                break
                ;;
              2)
                echo ""
                echo -n "Enter module name (supports partial match): "
                read module_name
                if [ -n "$module_name" ]; then
                  python3 "$graph_script" show "$module_name"
                else
                  echo "Module name required"
                fi
                break
                ;;
              3)
                echo ""
                echo -n "Enter module name to analyze impact: "
                read module_name
                if [ -n "$module_name" ]; then
                  python3 "$graph_script" impact "$module_name"
                else
                  echo "Module name required"
                fi
                break
                ;;
              4)
                echo ""
                echo -n "Enter module name to analyze requirements: "
                read module_name
                if [ -n "$module_name" ]; then
                  python3 "$graph_script" requirements "$module_name"
                else
                  echo "Module name required"
                fi
                break
                ;;
              5)
                python3 "$graph_script" stats
                break
                ;;
              6)
                echo ""
                echo -n "Output file (default: graph.json): "
                read output_file
                output_file=''${output_file:-graph.json}
                python3 "$graph_script" export --format=json > "$output_file"
                echo "Exported to $output_file"
                break
                ;;
              7)
                echo "Goodbye!"
                break
                ;;
              *)
                echo "Invalid option. Please choose 1-7."
                ;;
            esac
          done
        }
''
