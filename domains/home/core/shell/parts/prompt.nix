# domains/home/core/shell/parts/prompt.nix
# Starship prompt settings — powerline style, colors from the active
# palette via `col` (token -> hex with fallback).
{ lib, col }:
{
  scan_timeout = 100;
  command_timeout = 1000;
  add_newline = false;

  format = lib.concatStrings [
    "[](fg:#${col "bg" "282828"} bg:#${col "sectionA" "856b43"})"
    "$directory"
    "$git_branch"
    "$git_status"
    "[](fg:#${col "sectionB" "576f69"} bg:#${col "bg" "282828"}) "
    "$character"
  ];

  directory = {
    format = "[ $path ](bg:#${col "sectionA" "856b43"} fg:#${col "fg" "d5c4a1"})";
    truncation_length = 3;
    truncation_symbol = ".../";
    style = "bg:#${col "sectionA" "856b43"} fg:#${col "fg" "d5c4a1"}";
  };

  git_branch = {
    format = "[](fg:#${col "sectionA" "856b43"} bg:#${col "sectionB" "576f69"})[ $symbol$branch ](bg:#${col "sectionB" "576f69"} fg:#${col "fg" "d5c4a1"})";
    symbol = " ";
    style = "bg:#${col "sectionB" "576f69"} fg:#${col "fg" "d5c4a1"}";
  };

  git_status = {
    format = "[$all_status$ahead_behind ](bg:#${col "sectionB" "576f69"} fg:#${col "warn" "cf995f"})";
    style = "bg:#${col "sectionB" "576f69"} fg:#${col "warn" "cf995f"}";
    conflicted = "!";
    ahead = "⇡\${count}";
    behind = "⇣\${count}";
    diverged = "⇕";
    untracked = "?";
    modified = "~";
    staged = "+";
    deleted = "✘";
  };

  python  = { disabled = true; };
  nodejs  = { disabled = true; };
  rust    = { disabled = true; };
  golang  = { disabled = true; };

  character = {
    success_symbol = "[❯](bold fg:#${col "success" "a3be8c"})";
    error_symbol   = "[❯](bold fg:#${col "error" "bf616a"})";
  };
}
