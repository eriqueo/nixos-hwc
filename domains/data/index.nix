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
    ./backup/index.nix              # hwc.data.backup — user/server backup (canonical)
    ./backup-scheduler/index.nix    # hwc.system.services.backup — TODO: migrate namespace to hwc.data.*
    ./borg/index.nix                # hwc.system.services.borg — TODO: migrate namespace to hwc.data.*
    ./storage/index.nix
    ./couchdb/index.nix
  ];
}
