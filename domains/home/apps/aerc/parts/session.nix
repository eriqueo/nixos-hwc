{ lib, pkgs, config, osConfig ? {}, ...}:
{
  packages = [];
  services = {};
  env = {};
  shellAliases = {
    mail = "aerc";
    mailsync = "mbsync -a";
    mailindex = "notmuch new";
    urls = "urlscan";
  };
}