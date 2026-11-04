# Pure verification function; not a NixOS or Home Manager module.
{ lib, pkgs, self }:
{

meals-integration = let
  work = self.nixosConfigurations.hwc-work.config;
  cfg = work.hwc.server.services.meals;
  unit = work.systemd.services.meals;
  settings = builtins.fromJSON (builtins.readFile (lib.last (lib.splitString " " unit.serviceConfig.ExecStart)));
in
assert lib.assertMsg (cfg.enable
  && settings.database == "${work.hwc.paths.state}/meals/meals.db"
  && settings.writesEnabled == cfg.writesEnabled
  && settings.baseUrl == cfg.url
  && settings.timeZone == work.time.timeZone
  && (builtins.fromJSON (builtins.unsafeDiscardStringContext (builtins.readFile work.systemd.services.wall-display.environment.WALL_CONFIG))).meals.readUrl == "http://127.0.0.1:${toString cfg.port}"
  && settings.converter == { inherit (work.hwc.server.ai.dx2) baseUrl model apiKeyFile; modelIdentity = cfg.cookingModelIdentity; }
  && settings.cookingPromotion == cfg.cookingPromotion
  && work.hwc.system.mcp.mealCollections == cfg.collections
  && work.hwc.networking.shared.routeOwners.meals.owner == "work"
  && (lib.findFirst (r: r.name == "meals") {} work.hwc.networking.shared.routes).headers."X-Forwarded-For" == "{remote_host}"
  && lib.hasInfix "--check" unit.preStart
  && lib.hasInfix "--backup" work.services.borgbackup.jobs.hwc-backup.preHook
  && work.systemd.timers.meals-cleanup.timerConfig.Persistent)
  "Meals must bind exact effect targets, boot checks, backed-up state and cleanup";
pkgs.runCommand "meals-integration" {} ''touch "$out"'';
}
