# domains/server/containers/pihole/options.nix
{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.services.containers.pihole = {
    enable = mkEnableOption "Pi-hole network-wide ad blocking container";

    image = mkOption {
      type = types.str;
      default = "pihole/pihole:latest";
      description = "Container image for Pi-hole";
    };

    webPort = mkOption {
      type = types.port;
      default = 8080;
      description = "Port for Pi-hole web interface (avoid 80 if running other web services)";
    };

    dnsPort = mkOption {
      type = types.port;
      default = 53;
      description = "DNS port for Pi-hole (usually 53, conflicts with systemd-resolved)";
    };

    webPassword = mkOption {
      type = types.str;
      default = "";
      description = ''
        Web interface password. Leave empty to generate one automatically.
        For production, use a secrets management solution.
      '';
    };

    timezone = mkOption {
      type = types.str;
      default = "America/New_York";
      example = "Europe/London";
      description = "Timezone for Pi-hole container";
    };

    upstreamDns = mkOption {
      type = types.listOf types.str;
      default = [ "1.1.1.1" "1.0.0.1" ];
      example = [ "8.8.8.8" "8.8.4.4" ];
      description = "Upstream DNS servers for Pi-hole to use";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/opt/networking/pihole";
      description = "Directory for Pi-hole persistent data";
    };

    dnsmasqDir = mkOption {
      type = types.str;
      default = "/opt/networking/pihole/dnsmasq.d";
      description = "Directory for dnsmasq configuration files";
    };

    disableResolvedStub = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Automatically disable systemd-resolved DNS stub listener to free port 53.
        Set to false if you want to manually configure DNS settings.
      '';
    };

    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      example = {
        DNSSEC = "true";
        TEMPERATUREUNIT = "f";
      };
      description = "Extra environment variables for the Pi-hole container";
    };
  };
}
