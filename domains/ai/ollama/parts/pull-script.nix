{ lib, pkgs, config }:

let
  cfg = config.hwc.ai.ollama;

  # Normalize model configuration: strings → {name, autoUpdate=true, priority=50}
  normalizeModel = model:
    if lib.isString model then
      { name = model; autoUpdate = true; priority = 50; }
    else
      model // { autoUpdate = model.autoUpdate or true; priority = model.priority or 50; };

  # Normalize all models and sort by priority (lower = pulled first)
  sortedModels = lib.sort (a: b: a.priority < b.priority)
    (map normalizeModel cfg.models);
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
    echo "Pulling ${model.name} (priority: ${toString model.priority}, autoUpdate: ${if model.autoUpdate then "yes" else "no"})..."
    ${pkgs.curl}/bin/curl -sS -X POST -H 'Content-Type: application/json' \
      --data '{"name":"${model.name}","stream":false}' \
      http://127.0.0.1:${toString cfg.port}/api/pull || exit 1
    echo "Pulled: ${model.name}"

    ${lib.optionalString cfg.modelValidation.enable ''
      echo "Validating ${model.name}..."
      RESPONSE=$(${pkgs.curl}/bin/curl -sS -X POST -H 'Content-Type: application/json' \
        --data '{"model":"${model.name}","prompt":"${cfg.modelValidation.testPrompt}","stream":false}' \
        http://127.0.0.1:${toString cfg.port}/api/generate 2>&1)

      if echo "$RESPONSE" | ${pkgs.gnugrep}/bin/grep -q '"response"'; then
        echo "✓ Validated: ${model.name} (inference successful)"
      else
        echo "✗ Validation failed for ${model.name}: $RESPONSE"
        exit 1
      fi
    ''}
  '') sortedModels}

  touch "$mark"
''