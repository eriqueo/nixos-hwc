# shim: forward old path to new co-located sys.nix
{ ... }: { imports = [ ../sys.nix ]; }
