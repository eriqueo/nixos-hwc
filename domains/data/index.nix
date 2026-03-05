# domains/data/index.nix
#
# Data domain — databases, backup, storage, CouchDB.
# Consolidates all data infrastructure into one domain.
#
# Namespace: hwc.data.{databases,backup,borg,storage,couchdb}.*

{ lib, config, ... }:

{
  imports = [
    ./databases/index.nix
    ./backup/index.nix      # hwc.data.backup — merged backup system
    ./borg/index.nix         # hwc.data.borg — BorgBackup engine
    ./storage/index.nix
    ./couchdb/index.nix
  ];
}
