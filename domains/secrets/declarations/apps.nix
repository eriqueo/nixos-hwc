# domains/secrets/declarations/apps.nix
#
# Application secrets - User and system application credentials
# Data-only module that declares age.secrets entries for applications
{ config, lib, ... }:
{
  # Apps domain deprecated: no age.secrets here.
  age.secrets = { };
}
