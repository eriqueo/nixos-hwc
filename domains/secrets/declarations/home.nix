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
    google-oauth-client-id = {
      file = ../parts/home/google-oauth-client-id.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };
    google-oauth-client-secret = {
      file = ../parts/home/google-oauth-client-secret.age;
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

    # Scraper credentials for social media login
    scraper-facebook-email = {
      file = ../parts/home/scraper/facebook-email.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };
    scraper-facebook-password = {
      file = ../parts/home/scraper/facebook-password.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };
    scraper-nextdoor-email = {
      file = ../parts/home/scraper/nextdoor-email.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };
    scraper-nextdoor-password = {
      file = ../parts/home/scraper/nextdoor-password.age;
      mode = "0440";
      owner = "root";
      group = "secrets";
    };

  apple-app-pw = {
    file = ../parts/home/apple-app-pw.age;
    mode = "0440";
    owner = "root";
    group = "secrets";
  };
  };
}
