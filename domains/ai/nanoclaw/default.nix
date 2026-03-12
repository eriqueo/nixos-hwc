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
      default = "docker.io/library/node:20-bookworm";
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
