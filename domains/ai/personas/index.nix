{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.ai.personas;

  libraryDir = ./library;

  personaNames = lib.pipe (builtins.readDir libraryDir) [
    (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".nix" n))
    builtins.attrNames
    (map (n: lib.removeSuffix ".nix" n))
  ];

  loadPersona = name:
    let
      meta = import (libraryDir + "/${name}.nix");
      body = builtins.readFile (libraryDir + "/${name}.md");
    in
      meta // { inherit name; systemPrompt = body; };

  personaLib =
    lib.listToAttrs (map (n: { name = n; value = loadPersona n; }) personaNames);

  manifestFile = pkgs.writeText "hwc-personas.json"
    (builtins.toJSON personaLib);

  hwc-llm = pkgs.writeShellApplication {
    name = "hwc-llm";
    runtimeInputs = [ pkgs.curl pkgs.jq pkgs.coreutils ];
    text = ''
      manifest=${manifestFile}
      gpu_url=${cfg.gpuUrl}
      cpu_url=${cfg.cpuUrl}

      usage() {
        {
          echo "usage: hwc-llm <persona> <prompt>"
          echo "       hwc-llm <persona> -          # read prompt from stdin"
          echo "       hwc-llm --list"
          echo
          echo "Available personas:"
          jq -r 'to_entries[]
                 | "  \(.key) [\(.value.model)] — \(.value.description)"' \
                 "$manifest"
        } >&2
      }

      if [ $# -lt 1 ]; then usage; exit 2; fi
      case "$1" in
        --list|-l)
          jq -r 'to_entries[]
                 | "\(.key)\t\(.value.model)\t\(.value.description)"' \
                 "$manifest"
          exit 0
          ;;
        --help|-h)
          usage; exit 0 ;;
      esac
      if [ $# -lt 2 ]; then usage; exit 2; fi

      persona="$1"; shift
      if [ "$1" = "-" ]; then
        prompt=$(cat)
      else
        prompt="$*"
      fi

      meta=$(jq -e --arg p "$persona" \
        '.[$p] // error("unknown persona: \($p)")' "$manifest")

      backend=$(jq -r '.model' <<<"$meta")
      case "$backend" in
        gpu) endpoint="$gpu_url" ;;
        cpu) endpoint="$cpu_url" ;;
        *)   echo "persona $persona has invalid model: $backend" >&2; exit 1 ;;
      esac

      payload=$(jq -n \
        --arg sys  "$(jq -r '.systemPrompt' <<<"$meta")" \
        --arg user "$prompt" \
        --argjson temp "$(jq '.temperature' <<<"$meta")" \
        --argjson topp "$(jq '.topP'        <<<"$meta")" \
        --argjson maxt "$(jq '.maxTokens'   <<<"$meta")" \
        '{
          messages: [
            {role: "system", content: $sys},
            {role: "user",   content: $user}
          ],
          temperature: $temp,
          top_p:       $topp,
          max_tokens:  $maxt
        }')

      response=$(curl -fsS "$endpoint/v1/chat/completions" \
        -H 'content-type: application/json' \
        -d "$payload")

      jq -r '.choices[0].message.content' <<<"$response"
    '';
  };
in
{
  options.hwc.ai.personas = {
    enable = lib.mkEnableOption
      "hwc-llm persona CLI wrapping local llama.cpp services";

    gpuUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:11500";
      description = "Base URL of the GPU llama-server (LFM2-2.6B by default).";
    };

    cpuUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:11501";
      description = "Base URL of the CPU llama-server (LFM2-24B-A2B by default).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ hwc-llm ];

    assertions = [
      {
        assertion = personaNames != [ ];
        message =
          "hwc.ai.personas.enable = true but library/ contains no <name>.nix files.";
      }
    ];
  };
}
