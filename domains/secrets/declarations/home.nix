# domains/secrets/declarations/home.nix
#
# Home domain secrets - User email and personal credentials
# Data-only module that declares age.secrets entries for user applications
{ config, lib, ... }:
{
  # Home domain secrets - email credentials
  age.secrets = {
    # Email service credentials
    proton-bridge-password = {
      file = ../parts/home/proton-bridge-password.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    gmail-personal-password = {
      file = ../parts/home/gmail-personal-password.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    gmail-business-password = {
      file = ../parts/home/gmail-business-password.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };
    gmail-oauth-client = {
      file = ../parts/home/gmail-oauth-client.json.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

    openai-api-key = {
      file = ../parts/home/openai-api-key.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

  };
}
