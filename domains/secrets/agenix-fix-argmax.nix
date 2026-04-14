# domains/secrets/agenix-fix-argmax.nix
#
# Improved agenix workaround for large secret counts (>50-60 secrets).
# - Avoids "Argument list too long" by using external scripts.
# - Silent by default during normal rebuilds.
# - Shows clean summary only on new generation + any errors/warnings.

{ config, lib, pkgs, ... }:
let
  cfg = config.age;
  ageBin = cfg.ageBin;

  # Helper to set truePath
  setTruePath = secretType: ''
    _truePath="${cfg.secretsMountPoint}/$_agenix_generation/${secretType.name}"
  '';

  # Decrypt one secret (silent unless error)
  installSecret = secretType: ''
    ${setTruePath secretType}
    TMP_FILE="$_truePath.tmp"
    IDENTITIES=()
    for identity in ${builtins.toString cfg.identityPaths}; do
      test -r "$identity" || continue
      test -s "$identity" || continue
      IDENTITIES+=(-i)
      IDENTITIES+=("$identity")
    done

    if [ "''${#IDENTITIES[@]}" -eq 0 ]; then
      echo "[agenix] WARNING: no readable identities found!"
    fi

    mkdir -p "$(dirname "$_truePath")"
    [ "${secretType.path}" != "${cfg.secretsDir}/${secretType.name}" ] && mkdir -p "$(dirname "${secretType.path}")"

    (
      umask u=r,g=,o=
      if ! test -f "${secretType.file}"; then
        echo "[agenix] WARNING: encrypted file ${secretType.file} does not exist!"
      fi

      LANG=${config.i18n.defaultLocale or "C"} ${ageBin} --decrypt "''${IDENTITIES[@]}" -o "$TMP_FILE" "${secretType.file}" \
        || echo "[agenix] ERROR: failed to decrypt ${secretType.file}"
    )

    chmod ${secretType.mode} "$TMP_FILE" 2>/dev/null || true
    mv -f "$TMP_FILE" "$_truePath" 2>/dev/null || true

    ${lib.optionalString secretType.symlink ''
      [ "${secretType.path}" != "${cfg.secretsDir}/${secretType.name}" ] && ln -sfT "${cfg.secretsDir}/${secretType.name}" "${secretType.path}"
    ''}
  '';

  # Chown after decryption
  chownSecret = secretType: ''
    _truePath="${cfg.secretsMountPoint}/$_agenix_generation/${secretType.name}"
    chown ${secretType.owner}:${secretType.group} "$_truePath" 2>/dev/null || true
  '';

  # Main install script (runs once per new generation)
  installScript = pkgs.writeShellScript "agenix-install" ''
    _agenix_generation="$1"

    echo "[agenix] creating new generation $_agenix_generation"

    # Decrypt all secrets (silent unless warning/error)
    ${builtins.concatStringsSep "\n" (map installSecret (builtins.attrValues cfg.secrets))}

    # Summary + symlink + cleanup
    echo "[agenix] symlinking new secrets to ${cfg.secretsDir} (generation $_agenix_generation)..."
    ln -sfT "${cfg.secretsMountPoint}/$_agenix_generation" ${cfg.secretsDir}

    if (( _agenix_generation > 1 )); then
      echo "[agenix] removing old secrets (generation $(( _agenix_generation - 1 )))..."
      rm -rf "${cfg.secretsMountPoint}/$(( _agenix_generation - 1 ))"
    fi
  '';

  # Chown script
  chownScript = pkgs.writeShellScript "agenix-chown" ''
    _agenix_generation="$1"
    chown :keys "${cfg.secretsMountPoint}" "${cfg.secretsMountPoint}/$_agenix_generation" 2>/dev/null || true
    ${builtins.concatStringsSep "\n" (map chownSecret (builtins.attrValues cfg.secrets))}
  '';
in
{
  config = lib.mkIf (cfg.secrets != {}) {
    # Override agenix activation scripts with our quiet file-based versions
    system.activationScripts.agenixInstall = lib.mkForce {
      text = ''
        ${installScript} "$_agenix_generation"
      '';
      deps = [ "agenixNewGeneration" "specialfs" ];
    };

    system.activationScripts.agenixChown = lib.mkForce {
      text = ''${chownScript} "$_agenix_generation"'';
      deps = [ "users" "groups" ];
    };
  };
}
