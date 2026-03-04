# domains/data/index.nix
#
# Data domain — databases, backup, storage, CouchDB.
# Consolidates all data infrastructure into one domain.
#
# Namespace: hwc.data.{databases,backup,storage,couchdb}.*

{ lib, config, ... }:

{
  imports = [
    ./databases/index.nix
    ./backup/index.nix
    ./storage/index.nix
    ./couchdb/index.nix
  ];
}
