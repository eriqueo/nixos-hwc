# domains/data/index.nix
#
# Data domain — databases, backup, storage, CouchDB.
# Consolidates all data infrastructure into one domain.
#
# Namespace: hwc.server.databases.*, hwc.server.native.{backup,storage,couchdb}.*
# TODO Phase 8: Migrate to hwc.data.*

{ lib, config, ... }:

{
  imports = [
    ./databases/index.nix
    ./backup/index.nix
    ./storage/index.nix
    ./couchdb/index.nix
  ];
}
