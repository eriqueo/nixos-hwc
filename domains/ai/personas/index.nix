{ config, lib, pkgs, ... }:

let
  cfg = config.hwc.ai.personas;

  libraryDir = ./library;

  # Persona file names = library/*.nix, excluding underscore-prefixed
  # support files (e.g., _defaults.nix that personas merge from).
  personaNames = lib.pipe (builtins.readDir libraryDir) [
    (lib.filterAttrs (n: t:
      t == "regular"
      && lib.hasSuffix ".nix" n
      && !(lib.hasPrefix "_" n)
    ))
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
      daemon_url=${cfg.daemonUrl}

      usage() {
        {
          echo "usage:"
          echo "  hwc-llm <persona> <prompt>                       # stateless"
          echo "  hwc-llm <persona> --new-conversation <prompt>    # start a conversation"
          echo "  hwc-llm <persona> --new-conversation --print-id <prompt>"
          echo "                                                  # print only the new conv id"
          echo "  hwc-llm <persona> --conversation <id> <prompt>   # continue a conversation"
          echo "  hwc-llm <persona> - [...flags...]                # read prompt from stdin"
          echo "  hwc-llm --list"
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

      persona="$1"; shift

      # Parse remaining flags.
      conv_id=""
      new_conv="false"
      print_id="false"
      prompt_args=()
      while [ $# -gt 0 ]; do
        case "$1" in
          --conversation)
            conv_id="$2"; shift 2 ;;
          --new-conversation)
            new_conv="true"; shift ;;
          --print-id)
            print_id="true"; shift ;;
          --)
            shift; prompt_args+=("$@"); break ;;
          *)
            prompt_args+=("$1"); shift ;;
        esac
      done

      if [ ''${#prompt_args[@]} -lt 1 ]; then usage; exit 2; fi

      if [ "''${prompt_args[0]}" = "-" ]; then
        prompt=$(cat)
      else
        prompt="''${prompt_args[*]}"
      fi

      meta=$(jq -e --arg p "$persona" \
        '.[$p] // error("unknown persona: \($p)")' "$manifest")

      # Memory path: route through persona-daemon if --conversation or
      # --new-conversation is set. Otherwise stateless direct-to-backend
      # (preserves Phase 1 contract).
      if [ -n "$conv_id" ] || [ "$new_conv" = "true" ]; then
        body=$(jq -n \
          --arg persona "$persona" \
          --arg cid "$conv_id" \
          --argjson newconv "$new_conv" \
          --arg user "$prompt" \
          '{
             persona: $persona,
             messages: [{role: "user", content: $user}]
           }
           | if ($cid | length) > 0 then . + {conversation_id: $cid} else . end
           | if $newconv then . + {new_conversation: true} else . end
          ')

        response=$(curl -fsS "$daemon_url/v1/chat/completions" \
          -H 'content-type: application/json' \
          -d "$body")

        if [ "$print_id" = "true" ]; then
          jq -r '.conversation_id // empty' <<<"$response"
        else
          jq -r '.choices[0].message.content' <<<"$response"
          new_cid=$(jq -r '.conversation_id // empty' <<<"$response")
          if [ "$new_conv" = "true" ] && [ -n "$new_cid" ]; then
            echo "[conversation: $new_cid]" >&2
          fi
        fi
        exit 0
      fi

      # Stateless path (Phase 1 contract).
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
      description = "Base URL of the GPU llama-server (used in stateless mode).";
    };

    cpuUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:11501";
      description = "Base URL of the CPU llama-server (used in stateless mode).";
    };

    daemonUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:11550";
      description = ''
        Base URL of persona-daemon — used when hwc-llm is invoked with
        --conversation or --new-conversation. If the daemon isn't running,
        those flags will fail with curl connection-refused; the stateless
        path (default) does not depend on the daemon.
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      environment.systemPackages = [ hwc-llm ];

      assertions = [
        {
          assertion = personaNames != [ ];
          message =
            "hwc.ai.personas.enable = true but library/ contains no <name>.nix files.";
        }
      ];
    }

    # Hand the JSON manifest to persona-daemon when both are enabled.
    # This keeps the daemon agnostic to the personas module's file layout.
    (lib.mkIf (config.hwc.server.ai.personaDaemon.enable or false) {
      hwc.server.ai.personaDaemon.personaManifestFile = manifestFile;
    })
  ]);
}
