{ ... }: {
  imports = [ ../../modules/users/eric.nix ];
  hwc.users.eric.enable = true;
}
