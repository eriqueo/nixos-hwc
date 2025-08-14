{ lib }:
{
  # Helper to import from old config
  importLegacy = path: 
    import (/etc/nixos + "/${path}");
  
  # Helper to track migration status  
  migrationStatus = service: status:
    lib.trace "Migration: ${service} is ${status}" true;
}
