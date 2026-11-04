# Read-only readiness shared by native HTTP services. ExecStartPost keeps
# After/Requires consumers waiting until the application can answer a GET.
# mkTsNode owns TypeScript launchers; mkInfraContainer owns containers.
{ lib, pkgs }:
{ name, url, attempts ? 20 }:
assert builtins.isInt attempts && attempts >= 1 && attempts <= 100;
{
  # Each GET has a one-second ceiling; retry waits have jitter below one second.
  timeoutSeconds = 2 * attempts + 5;
  command = pkgs.writeShellScript "${name}-ready" ''
    for ((attempt = 1; attempt <= ${toString attempts}; attempt++)); do
      if ${pkgs.curl}/bin/curl --fail --silent --show-error \
        --connect-timeout 1 --max-time 1 --output /dev/null \
        ${lib.escapeShellArg url}; then
        exit 0
      fi
      if ((attempt < ${toString attempts})); then
        ${pkgs.coreutils}/bin/sleep "0.$((500 + RANDOM % 500))"
      fi
    done
    echo ${lib.escapeShellArg "${name} readiness failed after ${toString attempts} attempts"} >&2
    exit 1
  '';
}
