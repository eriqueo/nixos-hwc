# shim: forward old path to new co-located sys.nix
{ osConfig ? {}, ... }: { imports = [ ../sys.nix ]; }