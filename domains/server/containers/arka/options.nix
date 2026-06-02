{ lib, ... }:
let
  inherit (lib) mkOption mkEnableOption types;
in
{
  options.hwc.server.containers.arka = {
    enable = mkEnableOption "Arka MCP Gateway";

    images = {
      backend = mkOption {
        type = types.str;
        default = "localhost/arka-backend:latest";
        description = "Backend + worker container image";
      };
      frontend = mkOption {
        type = types.str;
        default = "localhost/arka-frontend:latest";
        description = "Frontend nginx container image";
      };
      postgres = mkOption {
        type = types.str;
        default = "docker.io/postgres:16-alpine";
        description = "PostgreSQL container image";
      };
    };

    ports = {
      frontend = mkOption {
        type = types.int;
        default = 8880;
        description = "Host port for frontend nginx (Caddy proxies this)";
      };
      backend = mkOption {
        type = types.int;
        default = 18000;
        description = "Host port for backend API (debug access)";
      };
      worker = mkOption {
        type = types.int;
        default = 18001;
        description = "Host port for worker (debug access)";
      };
      caddy = mkOption {
        type = types.int;
        default = 19443;
        description = "External Caddy TLS port for Arka UI";
      };
    };

    storage = {
      dataDir = mkOption {
        type = types.str;
        default = "/opt/arka";
        description = "Root storage directory for Arka data";
      };
    };

    urls = {
      frontend = mkOption {
        type = types.str;
        default = "https://hwc-server.ocelot-wahoo.ts.net:19443";
        description = "Public URL of the Arka frontend";
      };
      backend = mkOption {
        type = types.str;
        default = "https://hwc-server.ocelot-wahoo.ts.net:19443";
        description = "Public URL of the Arka backend (same host, nginx proxies /api/)";
      };
    };
  };
}
