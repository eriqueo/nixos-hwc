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

    ${lib.optionalString cfg.modelValidation.enable ''
      echo "Validating ${model}..."
      RESPONSE=$(${pkgs.curl}/bin/curl -sS -X POST -H 'Content-Type: application/json' \
        --data '{"model":"${model}","prompt":"${cfg.modelValidation.testPrompt}","stream":false}' \
        http://127.0.0.1:${toString cfg.port}/api/generate 2>&1)

      if echo "$RESPONSE" | ${pkgs.gnugrep}/bin/grep -q '"response"'; then
        echo "✓ Validated: ${model} (inference successful)"
      else
        echo "✗ Validation failed for ${model}: $RESPONSE"
        exit 1
      fi
    ''}
  '') cfg.models}

  touch "$mark"
''