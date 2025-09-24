{ lib, config, ... }:
let
  cfg = config.hwc.filesystem;
  p = cfg.paths;
  s = cfg.structure;

  nonNull = v: v != null && v != "";
  isAbs   = v: lib.hasPrefix "/" v;
  mkDir   = d: "d ${d.path} ${d.mode} ${d.user} ${d.group} -";

  fromPaths =
    builtins.concatLists [
      (if nonNull p.state then [ { path = p.state; mode = "0755"; user = "root"; group = "root"; } ] else [])
      (if nonNull p.cache then [ { path = p.cache; mode = "0755"; user = "root"; group = "root"; } ] else [])
      (if nonNull p.logs  then [ { path = p.logs;  mode = "0755"; user = "root"; group = "root"; } ] else [])
      (if nonNull p.temp  then [ { path = p.temp;  mode = "0755"; user = "root"; group = "root"; } ] else [])
      (if nonNull p.business.root then [ { path = p.business.root; mode = "0755"; user = "root"; group = "root"; } ] else [])
      (if nonNull p.ai.root then [ { path = p.ai.root; mode = "0755"; user = "root"; group = "root"; } ] else [])
      (if nonNull p.security.secrets then [ { path = p.security.secrets; mode = "0700"; user = "root"; group = "root"; } ] else [])
    ];

  allPaths = builtins.filter nonNull [
    p.hot p.cold
    p.user.home p.user.inbox p.user.work
    p.business.root p.ai.root
    p.state p.cache p.logs p.temp
    p.security.secrets p.security.sopsAgeKey
  ];

  ericHome = (config.users.users.eric.home or "/home/eric");
in
{
  config = lib.mkIf cfg.enable {
    # derive user paths from declared account if present
    hwc.filesystem.paths.user.home  = lib.mkDefault ericHome;
    hwc.filesystem.paths.user.inbox = lib.mkDefault "${ericHome}/Inbox";
    hwc.filesystem.paths.user.work  = lib.mkDefault "${ericHome}/Work";

    assertions = [
      { assertion = builtins.all isAbs allPaths;
        message   = "All hwc.filesystem.paths values must be absolute."; }
    ];

    environment.variables = {
      HEARTWOOD_HOT_STORAGE   = lib.mkForce (if nonNull p.hot then p.hot else "");
      HEARTWOOD_COLD_STORAGE  = if nonNull p.cold then p.cold else "";
      HEARTWOOD_BUSINESS_ROOT = p.business.root;
      HEARTWOOD_AI_ROOT       = p.ai.root;
      HEARTWOOD_SECRETS_DIR   = lib.mkForce p.security.secrets;
      HEARTWOOD_SOPS_AGE_KEY  = lib.mkForce p.security.sopsAgeKey;
      HEARTWOOD_USER_HOME     = p.user.home;
      HEARTWOOD_USER_INBOX    = p.user.inbox;
      HEARTWOOD_USER_WORK     = p.user.work;
    };

    systemd.tmpfiles.rules =
      builtins.map mkDir (fromPaths ++ s.dirs);
  };
}
