# scripts/validate-charter-v4.sh
#!/usr/bin/env bash
set -euo pipefail
violations=0

rg -q "writeScriptBin" domains/home/ && echo "home contains hardware scripts" && violations=$((violations+1))
rg -q "hardware\." domains/services/ && echo "services reference hardware.*" && violations=$((violations+1))
rg -q "systemd\.services" domains/home/ && echo "home defines systemd services" && violations=$((violations+1))
rg -q "/mnt/" domains/ && echo "hardcoded /mnt paths in modules" && violations=$((violations+1))

rg -q "domains/home/" --glob '!profiles/**' --glob '!domains/home/**' && echo "HM import outside profiles" && violations=$((violations+1))

rg -q "systemd\.|virtualisation\.|services\.[^h]|environment\.|programs\." profiles/ && echo "profile implementation present" && violations=$((violations+1))

for m in machines/*/config.nix; do
  rg -q "systemd\.|virtualisation\.|environment\.|programs\." "$m" && echo "machine contains implementation: $m" && violations=$((violations+1))
done

rg -q "home-manager\.extraSpecialArgs.*nixosConfig\s*=\s*config" profiles/ || { echo "HM bridge missing in profiles"; violations=$((violations+1)); }

if [ $violations -eq 0 ]; then
  echo "No violations found"
  exit 0
else
  echo "Violations: $violations"
  exit 1
fi
