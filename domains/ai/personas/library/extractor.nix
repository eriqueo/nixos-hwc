import ./_defaults.nix // {
  temperature = 0.1;
  topP = 0.9;
  maxTokens = 512;
  description = "Extract structured JSON from unstructured input";
  # stateless transformer; no memory
  useMemory = false;
}
