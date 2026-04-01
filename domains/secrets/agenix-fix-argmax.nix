# domains/secrets/agenix-fix-argmax.nix
#
# Workaround for agenix 0.15 + large secret counts.
# With 89+ secrets, agenix inlines all decrypt commands into a single
# activation-script environment variable that exceeds Linux MAX_ARG_STRLEN
# (128 KB), causing "Argument list too long" at build time.
#
# Fix: replace the inline activation scripts with a systemd oneshot service
# that runs the same logic from a script file (no env var size limit).
{ config, lib, pkgs, ... }:

let
  cfg = config.age;
  ageBin = cfg.ageBin;
  users = config.users.users;

  setTruePath = secretType: ''
    _truePath="${cfg.secretsMountPoint}/$_agenix_generation/${secretType.name}"
  '';

  installSecret = secretType: ''
    ${setTruePath secretType}
    echo "decrypting '${secretType.file}' to '$_truePath'..."
    TMP_FILE="$_truePath.tmp"

    IDENTITIES=()
    for identity in ${builtins.toString cfg.identityPaths}; do
      test -r "$identity" || continue
      test -s "$identity" || continue
      IDENTITIES+=(-i)
      IDENTITIES+=("$identity")
    done
    test "''${#IDENTITIES[@]}" -eq 0 && echo "[agenix] WARNING: no readable identities found!"

    mkdir -p "$(dirname "$_truePath")"
    [ "${secretType.path}" != "${cfg.secretsDir}/${secretType.name}" ] && mkdir -p "$(dirname "${secretType.path}")"
    (
      umask u=r,g=,o=
      test -f "${secretType.file}" || echo '[agenix] WARNING: encrypted file ${secretType.file} does not exist!'
      test -d "$(dirname "$TMP_FILE")" || echo "[agenix] WARNING: $(dirname "$TMP_FILE") does not exist!"
      LANG=${config.i18n.defaultLocale or "C"} ${ageBin} --decrypt "''${IDENTITIES[@]}" -o "$TMP_FILE" "${secretType.file}"
    )
    chmod ${secretType.mode} "$TMP_FILE"
    mv -f "$TMP_FILE" "$_truePath"
    ${lib.optionalString secretType.symlink ''
      [ "${secretType.path}" != "${cfg.secretsDir}/${secretType.name}" ] && ln -sfT "${cfg.secretsDir}/${secretType.name}" "${secretType.path}"
    ''}
  '';

  chownSecret = secretType: ''
    ${setTruePath secretType}
    chown ${secretType.owner}:${secretType.group} "$_truePath"
  '';

  cleanupAndLink = ''
    _agenix_generation="$(basename "$(readlink ${cfg.secretsDir})" || echo 0)"
    (( ++_agenix_generation ))
    echo "[agenix] symlinking new secrets to ${cfg.secretsDir} (generation $_agenix_generation)..."
    ln -sfT "${cfg.secretsMountPoint}/$_agenix_generation" ${cfg.secretsDir}

    (( _agenix_generation > 1 )) && {
    echo "[agenix] removing old secrets (generation $(( _agenix_generation - 1 )))..."
    rm -rf "${cfg.secretsMountPoint}/$(( _agenix_generation - 1 ))"
    }
  '';

  # Scripts receive _agenix_generation as $1 from the activation snippet,
  # since the variable is set by the prior agenixNewGeneration snippet
  # in the same bash process.
  installScript = pkgs.writeShellScript "agenix-install" ''
    _agenix_generation="$1"
    ${builtins.concatStringsSep "\n" (map (path: ''
      test -f ${path} || echo '[agenix] WARNING: identity ${path} not present!'
    '') cfg.identityPaths)}
    ${builtins.concatStringsSep "\n" (map installSecret (builtins.attrValues cfg.secrets))}
    ${cleanupAndLink}
  '';

  chownScript = pkgs.writeShellScript "agenix-chown" ''
    _agenix_generation="$1"
    chown :keys "${cfg.secretsMountPoint}" "${cfg.secretsMountPoint}/$_agenix_generation" 2>/dev/null || true
    ${builtins.concatStringsSep "\n" (map chownSecret (builtins.attrValues cfg.secrets))}
  '';
in
{
  config = lib.mkIf (cfg.secrets != {}) {
    # Override agenix activation scripts with file-based versions.
    # _agenix_generation is set by agenixNewGeneration in the same shell.
    system.activationScripts.agenixInstall = lib.mkForce {
      text = ''
        echo '[agenix] decrypting secrets...'
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
