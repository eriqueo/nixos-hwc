# domains/mail/taxonomy/lib.nix
#
# Pure derivation helpers over data.nix — per-consumer views of the canonical
# taxonomy. Importable from both lanes (`import .../taxonomy/lib.nix { inherit lib; }`).
# No options and no runtime artifact producer.
{ lib }:
let
  data = import ./data.nix;
  s = data.senders;

in
{
  inherit data;

  # Per-disposition lists remain configuration data for the separate Gmail
  # janitor. They do not classify or place local mail.
  derived = {
    trashSenders = s.trash;
  };
}
