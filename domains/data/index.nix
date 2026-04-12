# domains/data/index.nix
#
# Data domain — databases, backup, storage, CouchDB.
# Consolidates all data infrastructure into one domain.
#
# Namespace: hwc.data.{databases,backup,borg,storage,syncthing,couchdb}.*

{ lib, config, ... }:

{
  imports = [
    ./databases/index.nix
    ./backup/index.nix      # hwc.data.backup — merged backup system
    ./borg/index.nix         # hwc.data.borg — BorgBackup engine
    ./storage/index.nix
    ./syncthing/index.nix  # hwc.data.syncthing — bidirectional file sync
    ./couchdb/index.nix
    ./cloudbeaver/index.nix  # hwc.data.cloudbeaver — web database manager
  ];
}
