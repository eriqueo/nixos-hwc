{ lib, ... }:

{
  options.hwc.ai.ollama = {
    enable = lib.mkEnableOption "Ollama local LLM service";

    port = lib.mkOption {
      type = lib.types.port;
      default = 11434;
      description = "API port for the Ollama service";
    };

    models = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "llama3:8b" "codellama:13b" ];
      description = "Models to pre-download and keep available";
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/ollama";
      description = "Directory for storing Ollama models";
    };

    healthCheck = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable health check for Ollama service";
      };

      interval = lib.mkOption {
        type = lib.types.str;
        default = "5min";
        description = "Health check interval (systemd time format)";
      };
    };

    modelValidation = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Validate models after pull by testing inference";
      };

      testPrompt = lib.mkOption {
        type = lib.types.str;
        default = "Hello";
        description = "Test prompt to verify model loads correctly";
      };
    };

    modelHealth = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable periodic model health checks";
      };

      schedule = lib.mkOption {
        type = lib.types.str;
        default = "03:00";
        description = "Time to run model health checks (HH:MM format)";
      };
    };
  };
}