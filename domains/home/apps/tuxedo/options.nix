# domains/home/apps/tuxedo/options.nix
#
# Option surface for the tuxedo todo.txt TUI.
# NAMESPACE: hwc.home.apps.tuxedo.*  (Charter Law 2: namespace = folder path)

{ config, lib, ... }:

{
  options.hwc.home.apps.tuxedo = {
    enable = lib.mkEnableOption "tuxedo — fast, keyboard-driven todo.txt TUI";

    package = lib.mkOption {
      type        = lib.types.nullOr lib.types.package;
      default     = null;
      description = ''
        tuxedo package to use. If null, builds from the upstream release binary
        via parts/package.nix (the todo.txt `tuxedo` is not in nixpkgs; only the
        unrelated `tuxedo-rs` hardware daemon is). Override to point at a nixpkgs
        attribute if/when it lands there.
      '';
    };

    todoDir = lib.mkOption {
      type        = lib.types.str;
      default     = "${config.home.homeDirectory}/000_inbox/todo";
      description = ''
        Directory holding todo.txt and done.txt. Exported as TODO_DIR;
        TODO_FILE and DONE_FILE are derived from it. tuxedo and any todo.txt-cli
        compatible tool read these to locate the task files.
      '';
    };
  };
}
