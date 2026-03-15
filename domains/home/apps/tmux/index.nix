# domains/home/apps/tmux/index.nix
#
# tmux — terminal multiplexer
# Prefix: C-a  |  vim navigation  |  status bar styled to match theme
#
{ config, lib, pkgs, ... }:
let
  cfg = config.hwc.home.apps.tmux;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.home.apps.tmux = {
    enable = lib.mkEnableOption "tmux terminal multiplexer";
  };

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    programs.tmux = {
      enable = true;
      package = pkgs.tmux;

      prefix = "C-a";
      baseIndex = 1;
      escapeTime = 0;
      historyLimit = 50000;
      keyMode = "vi";
      mouse = true;
      terminal = "tmux-256color";
      sensibleOnTop = true;

      extraConfig = ''
        # True color support
        set -ga terminal-overrides ",xterm-256color:Tc"

        # Send C-a to applications by pressing C-a twice
        bind C-a send-prefix

        # Split with | and - (keep current path)
        bind | split-window -h -c "#{pane_current_path}"
        bind - split-window -v -c "#{pane_current_path}"
        unbind '"'
        unbind %

        # New window keeps current path
        bind c new-window -c "#{pane_current_path}"

        # Vim-style pane navigation
        bind h select-pane -L
        bind j select-pane -D
        bind k select-pane -U
        bind l select-pane -R

        # Resize panes with capital HJKL
        bind -r H resize-pane -L 5
        bind -r J resize-pane -D 5
        bind -r K resize-pane -U 5
        bind -r L resize-pane -R 5

        # Reload config
        bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded"

        # Vi-style copy mode
        bind -T copy-mode-vi v send -X begin-selection
        bind -T copy-mode-vi y send -X copy-pipe-and-cancel "wl-copy"
        bind -T copy-mode-vi Escape send -X cancel

        # Don't rename windows automatically
        set -g allow-rename off

        # ── Status bar (Gruvbox/Nord neutral palette) ──────────────────────────
        set -g status on
        set -g status-interval 5
        set -g status-position bottom
        set -g status-style "bg=#282828,fg=#ebdbb2"

        set -g status-left-length 40
        set -g status-left "#[bg=#458588,fg=#282828,bold] #S #[bg=#282828,fg=#458588]"

        set -g status-right-length 60
        set -g status-right "#[fg=#a89984] %H:%M  %d %b #[fg=#458588,bold]#H "

        set -g window-status-format         "#[fg=#a89984] #I:#W "
        set -g window-status-current-format "#[bg=#458588,fg=#282828,bold] #I:#W #[bg=#282828,fg=#458588]"
        set -g window-status-separator      ""

        # Pane borders
        set -g pane-border-style        "fg=#3c3836"
        set -g pane-active-border-style "fg=#458588"

        # Message / command line
        set -g message-style "bg=#458588,fg=#282828"
      '';
    };
  };
}
