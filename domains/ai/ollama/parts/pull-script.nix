{ lib, pkgs, config }:

let
  cfg = config.hwc.ai.ollama;
in
pkgs.writeShellScript "ollama-pull-models" ''
  set -euo pipefail
  mark=/var/lib/ollama-models-pulled

  if [ -f "$mark" ]; then
    echo "Models already pulled (marker: $mark)"
    exit 0
  fi

  echo "Waiting for Ollama to be ready on port ${toString cfg.port}..."
  for i in $(seq 1 120); do
    if ${pkgs.curl}/bin/curl -fsS http://127.0.0.1:${toString cfg.port}/api/tags >/dev/null; then
      break
    fi
    sleep 1
  done

  ${lib.concatMapStringsSep "\n" (model: ''
    echo "Pulling ${model}..."
    ${pkgs.curl}/bin/curl -sS -X POST -H 'Content-Type: application/json' \
      --data '{"name":"${model}","stream":false}' \
      http://127.0.0.1:${toString cfg.port}/api/pull || exit 1
    echo "Pulled: ${model}"
  '') cfg.models}

  touch "$mark"
''