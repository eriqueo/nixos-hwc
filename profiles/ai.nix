{ ... }:
{
  imports = [
    ../modules/services/ai-bible.nix
    ../modules/services/ollama.nix
  ];
  
  hwc.services.aiBible = {
    enable = true;
    features = {
      autoGeneration = true;
      llmIntegration = true;
    };
    llm = {
      provider = "ollama";
      model = "llama2";
    };
  };
  
  hwc.services.ollama = {
    enable = true;
    enableGpu = true;
    models = [ "llama2" "codellama" "mistral" ];
  };
}
