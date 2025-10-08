# NEW file: domains/system/services/shell/options.nix
{ lib, config, ... }:

{
  options.hwc.system.services.shell = {
    # The master switch for the entire shell environment.
    enable = lib.mkEnableOption "Enable the core shell environment and CLI tools";

    # A sub-option for development tools. This gives you a choice
    # to have a minimal shell or a full development setup.
    development.enable = lib.mkEnableOption "Install development tools (compilers, language servers)";
  };
}
