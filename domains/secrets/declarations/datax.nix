# domains/secrets/declarations/datax.nix
#
# DataX domain secrets — Discord webhook for FB classifier notifications
{ config, lib, ... }:
{
  age.secrets = {
    datax-discord-webhook = {
      file = ../parts/services/datax-discord-webhook.age;
      mode = "0440";
      owner = "eric";
      group = "secrets";
    };
  };
}
