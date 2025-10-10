{ lib, pkgs, br }:
let
  args = lib.concatStringsSep " " (["--noninteractive" "--log-level" (br.logLevel or "warn")] ++ (br.extraArgs or []));

  # For insecure vault mode, exclude pass from PATH to prevent auto-detection
  # Bridge auto-detects pass in PATH and sets Helper:"pass-app", overriding our Helper:""
  isInsecureVault = (br.keychain.helper or "pass") == "";
  basePath = if isInsecureVault
             then "/run/current-system/sw/bin"
             else "/run/current-system/sw/bin:${pkgs.pass}/bin";

  baseEnv = [
    "PATH=${basePath}"
    "PASSWORD_STORE_DIR=%h/.password-store"
    "GNUPGHOME=%h/.gnupg"
  ];
  env = baseEnv ++ lib.mapAttrsToList (k: v: "${k}=${v}") (br.environment or {});
in
{ inherit args env; }
