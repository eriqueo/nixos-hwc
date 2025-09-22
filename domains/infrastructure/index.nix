# modules/infrastructure/index.nix
#
# Infrastructure Domain - Integration glue for hardware, services, and users
# Imports the 3 clean buckets: hardware, mesh, session
{ lib, ... }:
{
  imports = [
    # Cross-domain orchestrators
    ./filesystem-structure/index.nix  # Cross-domain filesystem structure orchestrator

    # Hardware bucket - user↔hardware integration glue
    ./hardware/permissions.nix    # User groups, hardware ACLs, tmpfiles
    ./hardware/gpu.nix           # GPU acceleration integration
    ./hardware/peripherals.nix   # Printer integration glue
    ./hardware/storage.nix       # Storage device integration
    ./hardware/virtualization.nix # VM/container hardware runtime

    # Mesh bucket - service↔service and service↔network glue
    ./mesh/container-networking.nix  # Container network integration

    # Session bucket - user-scoped helpers (non-WM-specific)
    ./session/services.nix       # Background user services
    ./session/commands.nix       # Shared CLI commands (disabled by default)
  ];
}
