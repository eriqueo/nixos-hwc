{ lib, pkgs, br }:
let
  args = lib.concatStringsSep " " (["--noninteractive" "--log-level" (br.logLevel or "warn")] ++ (br.extraArgs or []));
  baseEnv = [
    "PATH=/run/current-system/sw/bin:${pkgs.pass}/bin"
    "PASSWORD_STORE_DIR=%h/.password-store"
    "GNUPGHOME=%h/.gnupg"
  ];
  env = baseEnv ++ lib.mapAttrsToList (k: v: "${k}=${v}") (br.environment or {});
in
{ inherit args env; }
