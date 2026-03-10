# domains/ai/nanoclaw/default.nix
#
# NanoClaw AI Agent Orchestrator
# Lightweight alternative to OpenClaw built on Anthropic's Agents SDK.
# Runs AI agents in isolated containers, connects to Slack/Telegram/etc.
#
# Phase 1: Interactive setup via `podman exec -it nanoclaw bash`
# Phase 2: Declarative entrypoint after verifying start command
#
# USAGE:
#   hwc.ai.nanoclaw.enable = true;

{ lib, config, pkgs, ... }:

let
  cfg = config.hwc.ai.nanoclaw;
in
{
  #==========================================================================
  # OPTIONS
  #==========================================================================
  options.hwc.ai.nanoclaw = {
    enable = lib.mkEnableOption "NanoClaw AI agent orchestrator";

    image = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/library/node:20-slim";
      description = "Base image for NanoClaw container";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "${config.hwc.paths.ai.root}/nanoclaw";
      description = "Persistent directory for NanoClaw project and data";
    };

    slack.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Pre-inject Slack tokens from agenix (Phase 2)";
    };

    # Declarative group configurations with container mounts
    groups = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule {
        options = {
          slackChannel = lib.mkOption {
            type = lib.types.str;
            description = "Slack channel ID for this group (e.g., C09V251ABV1)";
          };
          description = lib.mkOption {
            type = lib.types.str;
            default = "";
            description = "Human-readable description of this group";
          };
          additionalMounts = lib.mkOption {
            type = lib.types.listOf (lib.types.submodule {
              options = {
                hostPath = lib.mkOption {
                  type = lib.types.str;
                  description = "Path on the host system";
                };
                containerPath = lib.mkOption {
                  type = lib.types.str;
                  description = "Name/path inside the container (under /workspace/extra/)";
                };
                readonly = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                  description = "Mount as read-only";
                };
              };
            });
            default = [];
            description = "Additional host paths to mount into agent containers for this group";
          };
        };
      });
      default = {};
      description = "Declarative agent group configurations with mount settings";
      example = lib.literalExpression ''
        {
          server-admin = {
            slackChannel = "C09V251ABV1";
            description = "Server administration agent";
            additionalMounts = [
              { hostPath = "/home/eric/.nixos"; containerPath = "nixos"; readonly = false; }
              { hostPath = "/mnt/media"; containerPath = "media"; readonly = false; }
              { hostPath = "/var/log"; containerPath = "logs"; readonly = true; }
            ];
          };
        }
      '';
    };
  };

  imports = [ ./sys.nix ];

  #==========================================================================
  # IMPLEMENTATION
  #==========================================================================
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.hwc.secrets.enable;
        message = "NanoClaw requires hwc.secrets.enable = true for Anthropic API key";
      }
    ];
  };
}
