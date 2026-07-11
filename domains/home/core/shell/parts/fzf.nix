# domains/home/core/shell/parts/fzf.nix
# fzf program config — colors from the active palette via `col`.
{ col }:
{
  enable = true;
  enableZshIntegration = true;
  defaultCommand = "fd --type f --hidden --follow --exclude .git";
  fileWidget.command = "fd --type f --hidden --follow --exclude .git";
  historyWidget.options = [ "--exact" ];
  defaultOptions = [
    "--height 40%" "--reverse" "--border"
    "--color=bg+:#${col "bg3" "32373c"},bg:#${col "bg" "282828"},spinner:#${col "success" "a3be8c"},hl:#${col "info" "5e81ac"}"
    "--color=fg:#${col "fg" "d5c4a1"},header:#${col "info" "5e81ac"},info:#${col "warn" "cf995f"},pointer:#${col "success" "a3be8c"}"
    "--color=marker:#${col "success" "a3be8c"},fg+:#${col "fg" "d5c4a1"},prompt:#${col "warn" "cf995f"},hl+:#${col "success" "a3be8c"}"
  ];
}
