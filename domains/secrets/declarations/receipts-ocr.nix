# Secrets declarations for receipts OCR service
{ config, lib, ... }:

{
  age.secrets = {
    # PostgreSQL database password for business_user
    receipts-db-password = {
      file = ../../secrets/receipts-db-password.age;
      owner = "eric";
      group = "users";
      mode = "0400";
    };

    # Optional: Ollama API key (if using cloud Ollama)
    ollama-api-key = {
      file = ../../secrets/ollama-api-key.age;
      owner = "eric";
      group = "users";
      mode = "0400";
    };
  };
}
